# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Realtime::PgListener;

use Const::Fast;
use Mojo::Base -base, -async_await;
use v5.40;
use Mojo::Util qw(monkey_patch);
use POSIX      qw(strftime);

use GPForum::Infrastructure::PgNotifications;
use GPForum::Service::Realtime::EventEnvelope;
use GPForum::Service::Realtime::OutboxEventMapper;

use GPForum::Infrastructure::SqlFunction;
use GPForum::Infrastructure::ResultRow;

our $VERSION = '0.001';

# The backstop's call layer. Without one -- no schema, or one that is not
# PostgreSQL's -- the backstop poll is off.
has functions => \&GPForum::Infrastructure::SqlFunction::for_service;

const my $DEFAULT_BATCH_LIMIT => 100;
const my $DEFAULT_SEEN_LIMIT  => 1000;
const my $MICROSECONDS        => 1_000_000;
const my $NOTIFICATION_BADGE  => 'notification.badge';

# A done row is read only once it is this old by the database's clock. The
# dispatcher stamps next_attempt_at before its UPDATE commits, so a cursor
# that ran up to the newest stamp could pass a row that committed a moment
# later with an older one, and never read it. The stamp comes from the
# dispatcher host's clock, so the window also covers that host's offset from
# the database's, which NTP keeps far below it. api.ops_realtime_poll bounds
# the batch by the same five seconds, so the poll needs no separate query
# for the clock.
const my $SETTLE_SECONDS => 5;

# The head of the outbox as a cursor: no row stamped at the seed instant
# sorts after these, so only rows stamped later are read.
const my $HEAD_CREATED_AT => 'infinity';
const my $HEAD_OUTBOX_ID  => 'ffffffff-ffff-ffff-ffff-ffffffffffff';

# What a start or a poll moves: the status, whether badges are stale (set
# by a gap and cleared once badge snapshots went out, which waits for the
# LISTEN to be in effect again) and the backstop's cursor (set by the first
# poll). Each is read and set by its accessor, and kept in one hash built
# with the listener, which a blocking copy shares.
const my %PROGRESS => (
    badges_stale       => 0,
    outbox_poll_cursor => undef,
    status             => 'stopped',
);

has batch_limit => $DEFAULT_BATCH_LIMIT;
has channel     => 'gpforum_domain_events';

# The database's clock, as a code ref returning epoch seconds. Left undef,
# PostgreSQL's own clock bounds the batch; tests set it to stamp rows by a
# clock of their own.
has db_now => undef;    # optional: a test's clock; else the database's
has event_contract =>
  sub { return GPForum::Service::Realtime::EventEnvelope->new; };
has hub             => undef;    # optional: without one nothing is broadcast
has max_seen_events => $DEFAULT_SEEN_LIMIT;

# The process's one queue for its handle, shared with the cache
# invalidation bus (Bootstrap injects it).
has notifications => sub ($self) {
    return GPForum::Infrastructure::PgNotifications->new(
        schema => $self->schema );
};
has outbox_event_mapper =>
  sub { return GPForum::Service::Realtime::OutboxEventMapper->new; };
has outbox_poll_enabled => 1;
has progress            => sub { return {%PROGRESS}; };
has seen_event_ids      => sub { return {}; };
has seen_order          => sub { return []; };
has schema => undef;    # optional: without one the backstop poll is off
has stats  => sub {
    return {
        badge_snapshots        => 0,
        broadcast              => 0,
        broadcast_failures     => 0,
        delivered              => 0,
        degraded               => 0,
        duplicates             => 0,
        failed                 => 0,
        gaps                   => 0,
        invalid_payloads       => 0,
        listen_notify_received => 0,
        malformed              => 0,
        malformed_payloads     => 0,
        outbox_poll_received   => 0,
        reconnect_count        => 0,
    };
};

for my $name ( sort keys %PROGRESS ) {
    monkey_patch __PACKAGE__, $name => sub ( $self, @value ) {
        return $self->progress->{$name} if !@value;
        $self->progress->{$name} = $value[0];
        return $self;
    };
}

# A start, a reconnect and a poll are written once, as their promise
# methods (ADR 0177); the blocking forms are their twins, the hub blocking
# with them.
GPForum::Infrastructure::SqlFunction->blocking_twins(
    qw(start reconnect poll_once));
GPForum::Infrastructure::SqlFunction->blocking_parts('hub');

# What a poll moves -- its progress, the counters, the delivered ids, the
# queue -- is the process's, shared with every blocking copy of the
# listener: it is built here, before a copy is made, or a copy would poll
# from state of its own and lose where it got to.
sub new ( $class, @arguments ) {
    my $self = $class->SUPER::new(@arguments);
    for my $name ( sort keys %PROGRESS ) {
        if ( exists $self->{$name} ) {
            $self->progress->{$name} = delete $self->{$name};
        }
    }
    for my $built (qw(progress stats seen_event_ids seen_order notifications)) {
        $self->$built;
    }

    return $self;
}

async sub start_p ($self) {
    if ( !( await $self->notifications->listen_to_p( $self->channel ) ) ) {
        return $self->_start_outbox_polling('listen_unavailable');
    }

    $self->status('listening');

    return { ok => 1, status => $self->status, channel => $self->channel };
}

async sub poll_once_p ($self) {
    my $notify = await $self->_poll_listen_notify_p;
    my $outbox = await $self->_poll_outbox_p;
    if ( !$notify->{available} && !$outbox->{available} ) {
        return $self->_degraded('poll_unavailable');
    }

    return _combined_summary( $notify, $outbox );
}

async sub _poll_listen_notify_p ($self) {
    my $taken = await $self->notifications->take_p( $self->channel );
    $self->_note_listen_state;

    my %summary = (
        available  => $taken->{available},
        delivered  => 0,
        failed     => 0,
        invalid    => 0,
        received   => 0,
        duplicates => 0,
    );

    for my $notification ( @{ $taken->{notifications} } ) {
        $summary{received} += 1;
        $self->stats->{listen_notify_received} += 1;

        my $decoded =
          $self->event_contract->deserialize(
            _notification_payload($notification) );
        if ( $decoded->{ok} ) {
            await $self->_deliver_event_p( \%summary, $decoded->{event} );
        }
        else {
            $summary{invalid}                  += 1;
            $self->stats->{invalid_payloads}   += 1;
            $self->stats->{malformed}          += 1;
            $self->stats->{malformed_payloads} += 1;
        }
    }

    # Badges are absolute counts, so the ones lost in a gap are rebuilt by
    # sending each local subscriber its count again, once the LISTEN is in
    # effect: while it fails the queue reports a gap on every take, and a
    # snapshot sent then would be stale at the next change it cannot hear.
    # Thread and moderation hints lost in a gap are read back by the outbox
    # backstop.
    if ( $taken->{gap} ) {
        $self->stats->{gaps} += 1;
        $self->badges_stale(1);
    }
    if (   $self->badges_stale
        && $self->notifications->listening( $self->channel ) )
    {
        await $self->_resend_badges_p;
        $self->badges_stale(0);
    }

    return \%summary;
}

sub _note_listen_state ($self) {
    return if $self->status eq 'stopped';

    $self->status(
        $self->notifications->listening( $self->channel )
        ? 'listening'
        : 'polling'
    );

    return;
}

async sub _resend_badges_p ($self) {
    return if !$self->hub;

    $self->stats->{badge_snapshots} +=
      await $self->hub->resend_badge_snapshots_p;

    return;
}

# The backstop for NOTIFYs that never arrived. ADR 0067: it runs for this
# process's sockets, so with none there is nothing to poll for; every worker
# on every node polling regardless made PostgreSQL's load grow with the
# processes, not with the connections. The cursor goes with the last socket,
# and the next one starts from the head.
async sub _poll_outbox_p ($self) {
    if ( !$self->outbox_poll_enabled || !$self->_outbox_available ) {
        return _unavailable_summary();
    }
    if ( !$self->_has_local_connections ) {
        $self->outbox_poll_cursor(undef);
        return _available_summary();
    }

    # A new cursor starts at the head, not at the oldest retained row: a
    # worker recycled or deployed replayed up to seven days of events into
    # live sockets, and was minutes behind the NOTIFYs it was backing up.
    if ( !$self->outbox_poll_cursor ) {
        my $head = await $self->_settled_instant_p;
        return _unavailable_summary() if !defined $head;

        $self->outbox_poll_cursor(
            {
                next_attempt_at => $head,
                created_at      => $HEAD_CREATED_AT,
                outbox_id       => $HEAD_OUTBOX_ID,
            }
        );
        return _available_summary();
    }

    my $messages = await $self->_outbox_messages_p;
    return _unavailable_summary() if !$messages;

    my %summary = %{ _available_summary() };
    for my $message ( @{$messages} ) {
        my @events =
          $self->outbox_event_mapper->events_for_payload(
            $message->get_column('payload') );
        for my $event (@events) {
            $summary{received} += 1;
            $self->stats->{outbox_poll_received} += 1;
            await $self->_deliver_event_p( \%summary, $event );
        }
        $self->outbox_poll_cursor(
            {
                map { $_ => $message->get_column($_) // q{} }
                  qw(next_attempt_at created_at outbox_id)
            }
        );
    }

    return \%summary;
}

sub _has_local_connections ($self) {
    return 0 if !$self->hub;

    return $self->hub->connection_count > 0 ? 1 : 0;
}

async sub _deliver_event_p ( $self, $summary, $event ) {

    # Only hints shared by NOTIFY and the backstop need deduplication.
    # Remembering badges would evict hints during a notification fanout.
    my $event_id =
      ( $event->{type} // q{} ) eq $NOTIFICATION_BADGE
      ? q{}
      : $event->{event_id} // q{};
    if ( length $event_id && $self->seen_event_ids->{$event_id} ) {
        $summary->{duplicates} += 1;
        $self->stats->{duplicates} += 1;
        return;
    }

    # The hub asks the database who may read a thread (ADR 0102), and that
    # can fail, most likely just after the reconnect that made a gap. The
    # exception left the poll, dropping the gap the take had returned and
    # every notification after this one. It is a failed broadcast instead,
    # and the id is remembered only after success so the backstop may retry.
    my $broadcast;
    try {
        $broadcast =
          $self->hub
          ? await $self->hub->broadcast_event_p($event)
          : { ok => 0, reason => 'hub_unavailable' };
    }
    catch ($error) {
        $broadcast = undef;
    };
    if ( !$broadcast ) {
        $broadcast = { ok => 0, reason => 'broadcast_failed' };
    }
    $self->stats->{broadcast} += 1;

    if ( !$broadcast->{ok} ) {
        $summary->{failed}                 += 1;
        $self->stats->{failed}             += 1;
        $self->stats->{broadcast_failures} += 1;
        return;
    }

    if ( length $event_id ) {
        $self->_remember_delivered($event_id);
    }

    my $delivered = $broadcast->{delivered} || 0;
    my $failed    = $broadcast->{failed}    || 0;
    $summary->{delivered}     += $delivered;
    $self->stats->{delivered} += $delivered;
    $summary->{failed}        += $failed;
    $self->stats->{failed}    += $failed;

    return;
}

# The next batch after the cursor, as a keyset over (next_attempt_at,
# created_at, outbox_id) bounded by the settle window, or undef when the
# database could not be asked: the cursor stays where it was and the next
# poll asks again.
async sub _outbox_messages_p ($self) {
    my $cursor = $self->outbox_poll_cursor;
    my $rows;
    try {
        $rows = await $self->functions->rows_p(
            'ops_realtime_poll',
            {
                after_next_at    => $cursor->{next_attempt_at},
                after_created_at => $cursor->{created_at},
                after_id         => $cursor->{outbox_id},
                settled_at       => $self->_settled_bound,
                settle_seconds   => $SETTLE_SECONDS,
                row_limit        => $self->batch_limit
            }
        );
    }
    catch ($error) {
        return undef;
    };

    return [ map { GPForum::Infrastructure::ResultRow->from($_) } @{$rows} ];
}

# The settled instant as a value, for the head cursor: one query when a
# cursor is seeded, none per poll. Undef when the database cannot be asked.
async sub _settled_instant_p ($self) {
    return $self->_settled_bound if $self->db_now;

    my $instant;
    try {
        $instant = (
            await $self->functions->row_p(
                'ops_realtime_settled', { settle_seconds => $SETTLE_SECONDS }
            )
        )->{settled_at};
    }
    catch ($error) {
        return undef;
    };

    return $instant;
}

# The database's clock, not this host's: each dispatcher stamps rows with
# its own host's clock, and the database's is the one they all share. Undef
# leaves the bound to the function, which reads that clock itself; a test's
# clock gives it as a value.
sub _settled_bound ($self) {
    return undef if !$self->db_now;

    return _iso8601( $self->db_now->() - $SETTLE_SECONDS );
}

# The LISTEN stays registered and the cursor stays where it was: the queue
# re-issues the LISTEN on whatever backend the handle has now and reports
# the gap, and the backstop reads what was missed during the outage.
async sub reconnect_p ($self) {
    $self->stats->{reconnect_count} += 1;

    return await $self->start_p;
}

sub stop ($self) {
    if ( !$self->notifications->unlisten( $self->channel ) ) {
        $self->stats->{degraded} += 1;
    }
    $self->status('stopped');

    return { ok => 1, status => $self->status };
}

sub snapshot ($self) {
    return {
        %{ $self->stats },
        channel       => $self->channel,
        notifications => $self->notifications->snapshot,
        status        => $self->status,
    };
}

sub _degraded ( $self, $reason ) {
    $self->stats->{degraded} += 1;
    $self->status('degraded');

    return {
        ok       => 0,
        degraded => 1,
        reason   => $reason,
        status   => $self->status,
    };
}

sub _start_outbox_polling ( $self, $reason ) {
    return $self->_degraded($reason) if !$self->_outbox_available;

    $self->stats->{degraded} += 1;
    $self->status('polling');

    return {
        ok       => 1,
        degraded => 1,
        reason   => $reason,
        status   => $self->status,
        channel  => $self->channel,
    };
}

sub _outbox_available ($self) {
    return $self->functions ? 1 : 0;
}

# Failed attempts never enter either structure: deleting only the hash
# entry left an older FIFO entry that later evicted a successful retry.
sub _remember_delivered ( $self, $event_id ) {
    $self->seen_event_ids->{$event_id} = 1;
    push @{ $self->seen_order }, $event_id;
    while ( @{ $self->seen_order } > $self->max_seen_events ) {
        my $oldest = shift @{ $self->seen_order };
        delete $self->seen_event_ids->{$oldest};
    }

    return;
}

sub _notification_payload ($notification) {
    return $notification->[2]       if ref $notification eq 'ARRAY';
    return $notification->{payload} if ref $notification eq 'HASH';

    return $notification;
}

# UTC, to the microsecond PostgreSQL keeps; the fraction is left out when
# there is none.
sub _iso8601 ($epoch) {
    my $seconds  = int $epoch;
    my $fraction = int( ( $epoch - $seconds ) * $MICROSECONDS );
    my $text     = strftime( '%Y-%m-%dT%H:%M:%S', gmtime $seconds );

    return $fraction ? sprintf( '%s.%06dZ', $text, $fraction ) : $text . 'Z';
}

sub _available_summary {
    return { %{ _unavailable_summary() }, available => 1 };
}

sub _unavailable_summary {
    return {
        available  => 0,
        delivered  => 0,
        failed     => 0,
        invalid    => 0,
        received   => 0,
        duplicates => 0,
    };
}

sub _combined_summary ( $notify, $outbox ) {
    return {
        ok         => 1,
        delivered  => $notify->{delivered} + $outbox->{delivered},
        failed     => $notify->{failed} + $outbox->{failed},
        invalid    => $notify->{invalid} + $outbox->{invalid},
        received   => $notify->{received} + $outbox->{received},
        duplicates => $notify->{duplicates} + $outbox->{duplicates},
    };
}

1;

__END__

=head1 NAME

GPForum::Service::Realtime::PgListener - Delivers domain events from
PostgreSQL to this process's websocket subscribers.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $listener = GPForum::Service::Realtime::PgListener->new(
        hub           => $hub,
        notifications => $pg_notifications,
        schema        => $schema,
    );

    await $listener->start_p;
    await $listener->poll_once_p;    # from the supervisor's timer

=head1 DESCRIPTION

Every web process runs one listener, and each fans out only to its own
sockets (ADR 0006, 0055). There is no shared presence or subscription
registry.

Events arrive two ways. The fast path is LISTEN/NOTIFY on
C<gpforum_domain_events>, read from the process's shared notification queue
(L<GPForum::Infrastructure::PgNotifications>), so the cache invalidation bus
on the same handle keeps its own notifications. The backstop reads done
outbox rows through a cursor, for NOTIFYs that never arrived; it runs only
while this process has sockets, starts at the head of the outbox, and reads a
row only once it has settled for five seconds by the database's clock.
Duplicate event ids from the two paths are suppressed with a bounded memory,
which badges, carried by NOTIFY alone, do not take up.

When the queue reports a gap -- the handle's connection was replaced, a
LISTEN failed, or the queue overflowed -- the listener sends every local
notifications subscriber its unread count again, once its LISTEN is in
effect.

C<hub>, when given, is a L<GPForum::Service::Realtime::Hub>: the listener
broadcasts events through it, asks it for its connection count and has it
resend the badge snapshots.

The backstop reads C<api.ops_realtime_poll> and C<api.ops_realtime_settled>
through the schema's PostgreSQL function layer (C<functions>); without one
the backstop is off. A start, a reconnect and a poll are written once, as C<start_p>,
C<reconnect_p> and C<poll_once_p>; C<start>, C<reconnect> and C<poll_once>
are their blocking twins (ADR 0177), the hub blocking with them. What they move -- the status, the stale
badges, the cursor, the counters and the delivered ids -- is built with the
listener, so a blocking copy shares it. The blocking twins take the queue as
it answers: on the web workers' native LISTEN connection it answers on the
event loop, which a blocking twin refuses to wait for.

=head1 SUBROUTINES/METHODS

=head2 new

The Mojo::Base constructor. It builds C<progress> -- moving a
C<status>, C<badges_stale> or C<outbox_poll_cursor> given to it there --
C<stats>, the delivered ids and C<notifications> at once: they are the
process's state, which the blocking copies of a start or a poll share.

=head2 status, badges_stale, outbox_poll_cursor

Accessors of C<progress>: each answers its value, or sets it and answers
the listener.

=head2 start

The blocking twin of L</start_p>. Issues the LISTEN. Returns C<status =E<gt> 'polling'> and C<degraded> when it
could not, and the outbox backstop is the only path.

=head2 stop

Issues the UNLISTEN.

=head2 poll_once

The blocking twin of L</poll_once_p>. Delivers what arrived on both paths. Fails only when neither is available;
a backstop whose query failed counts as unavailable, and keeps its cursor.

=head2 reconnect_p

Counts the reconnect and starts again without dropping the channel or the
cursor.

=head2 reconnect

The blocking twin of L</reconnect_p>.

=head2 snapshot

Counters, status and the notification queue's state, for C</metrics>.

=head2 poll_once_p

The poll itself. Awaits one nonblocking poll, preserving the existing cursor, gap handling and delivery counters. The supervisor coalesces overlapping timer polls.

=head2 start_p

The start itself. Starts the listener with asynchronous connection and LISTEN setup. State, registration and timers remain in the owning process.

=head1 DIAGNOSTICS

Never throws. Malformed payloads, duplicates, failed broadcasts (one whose
readability query died among them) and gaps are counted in C<stats>.

=head1 CONFIGURATION AND ENVIRONMENT

Started by L<GPForum::Service::Realtime::ListenerSupervisor> when
C<GPFORUM_REALTIME_LISTENER_ENABLED> is set. The settle window (5 seconds)
and batch size are constants.

=head1 DEPENDENCIES

L<GPForum::Infrastructure::PgNotifications>,
L<GPForum::Service::Realtime::EventEnvelope>,
L<GPForum::Service::Realtime::OutboxEventMapper>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

There is no replay log. A client that reconnects refetches canonical state;
the backstop only covers NOTIFYs lost while this process had sockets.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
