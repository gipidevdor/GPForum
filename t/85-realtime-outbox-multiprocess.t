# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use POSIX qw(strftime);
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Service::Notification::Dispatcher;
use GPForum::Service::Outbox::DomainEventTransport;
use GPForum::Service::Realtime::ChannelAuthorizer;
use GPForum::Service::Realtime::ConnectionRegistry;
use GPForum::Service::Realtime::EventEnvelope;
use GPForum::Service::Realtime::Hub;
use GPForum::Service::Realtime::PgListener;
use GPForum::Service::Realtime::PgNotifier;
use GPForum::Test::AnsweringFunctions;
use GPForum::Test::FixedClock;
use GPForum::Test::Id;
use GPForum::Test::NotificationInboxFunctions;
use GPForum::Test::OutboxPayloadRow;
use GPForum::Test::RealtimeBusDbh;
use GPForum::Test::RealtimeBusSchema;
use GPForum::Test::RealtimeConnection;
use GPForum::Test::RealtimePermissionEngine;

our $VERSION = '0.001';

# The database's clock in these tests, as epoch seconds.
const my $NOW              => 1_780_000_000;
const my $LONG_AGO         => -86_400;
const my $PAST_THE_SETTLE  => 10;
const my $PROCESS_A_PID    => 101;
const my $PROCESS_B_PID    => 202;
const my $STAMP_LATE_ROW   => 3;
const my $STAMP_EARLY_ROW  => 4;
const my $SEEN_BEFORE_LATE => 6;
const my $SMALL_MEMORY     => 2;
const my $SETTLE_SECONDS   => 5;

_assert_thread_update_crosses_processes();
_assert_badges_cross_processes();
_assert_moderation_invalidation_crosses_processes();
_assert_backstop_starts_at_the_head();
_assert_backstop_idles_without_sockets();
_assert_backstop_cursor_advances();
_assert_backstop_reads_a_late_commit();
_assert_cursor_survives_reconnect();
_assert_backstop_survives_a_failed_query();
_assert_badges_leave_the_dedup_memory_alone();

done_testing();

sub _assert_thread_update_crosses_processes {
    my $bus        = GPForum::Test::RealtimeBusDbh->new;
    my $connection = GPForum::Test::RealtimeConnection->new;
    my $listener   = _listener_for( $bus, 'thread:thread-1', $connection );
    my $transport  = _transport_for_bus($bus);

    $listener->start;
    $transport->dispatch(
        _outbox_message(
            {
                event_id       => 'event-post-1',
                event_type     => 'post.created',
                aggregate_type => 'post',
                aggregate_id   => 'post-1',
                actor_id       => 'user-author',
                domain_payload => { thread_id => 'thread-1' },
            }
        )
    );
    my $poll = $listener->poll_once;

    is( $poll->{received},  1, 'listener receives worker NOTIFY event' );
    is( $poll->{delivered}, 1, 'listener delivers remote worker event' );
    is( $connection->sent->[0]{json}{type},
        'thread.update', 'remote worker event reaches local websocket' );
    is( $connection->sent->[0]{json}{payload}{post_id},
        'post-1', 'thread update payload survives cross-process fanout' );

    return;
}

# A badge used to be pushed to the hub of the process that changed the
# count, so a reader whose socket sat on another worker or node never saw
# it. Process A serves the request here and holds no socket; the socket is on
# process B, a second backend of the same PostgreSQL.
sub _assert_badges_cross_processes {
    my $backend_a =
      GPForum::Test::RealtimeBusDbh->new( pg_pid => $PROCESS_A_PID );
    my $backend_b =
      GPForum::Test::RealtimeBusDbh->new( pg_pid => $PROCESS_B_PID )
      ->join_network($backend_a);
    my $local  = GPForum::Test::RealtimeConnection->new;
    my $remote = GPForum::Test::RealtimeConnection->new;
    my $listener_a =
      _listener_for( $backend_a, 'thread:thread-elsewhere', $local );
    my $listener_b =
      _listener_for( $backend_b, 'notifications:user-1', $remote );
    $listener_a->start;
    $listener_b->start;

    my $dispatcher = _dispatcher_for($backend_a);
    $dispatcher->create_notification(
        {
            notification_type => 'mention',
            payload           => { thread_id => 'thread-1' },
            recipient_user_id => 'user-1',
            source_id         => 'post-mention',
            source_type       => 'post',
        }
    );
    $listener_a->poll_once;
    $listener_b->poll_once;

    is( _last_frame($remote)->{json}{type},
        'notification.badge', 'a mention made on process A reaches B' );
    is( _last_frame($remote)->{json}{payload}{unread_count},
        1, 'and carries the new unread count' );
    is( scalar @{ $local->sent },
        0, 'process A sends nothing to a socket that did not subscribe' );

    $dispatcher->mark_all_read('user-1');
    $listener_b->poll_once;

    is( _last_frame($remote)->{json}{payload}{unread_count},
        0, 'mark all read on process A clears the badge on process B' );
    is( scalar @{ $remote->sent }, 2, 'one badge per change, not two' );

    return;
}

sub _assert_moderation_invalidation_crosses_processes {
    my $bus        = GPForum::Test::RealtimeBusDbh->new;
    my $connection = GPForum::Test::RealtimeConnection->new;
    my $listener   = _listener_for( $bus, 'moderation:queue', $connection );
    my $transport  = _transport_for_bus($bus);

    $listener->start;
    $transport->dispatch(
        _outbox_message(
            {
                event_id       => 'event-report-1',
                event_type     => 'report.created',
                aggregate_type => 'report',
                aggregate_id   => 'report-1',
                actor_id       => 'user-reporter',
            }
        )
    );
    $listener->poll_once;

    is( $connection->sent->[0]{json}{type},
        'moderation.queue.invalidate',
        'moderation invalidation reaches remote process' );

    return;
}

# A new listener -- every deploy, every worker recycled after 10,000
# requests -- started from the oldest done row and replayed up to seven days
# of events into live sockets.
sub _assert_backstop_starts_at_the_head {
    my $outbox     = [ _done_row( 'old', 'thread-head', $LONG_AGO ) ];
    my $now        = $NOW;
    my $connection = GPForum::Test::RealtimeConnection->new;
    my $listener =
      _backstop_listener( $outbox, \$now, 'thread:thread-head', $connection );

    my $start = $listener->start;
    ok( $start->{degraded},
        'without LISTEN the listener starts in polling fallback' );
    $listener->poll_once;
    push @{$outbox}, _done_row( 'new', 'thread-head', 1 );
    $now += $PAST_THE_SETTLE;
    my $poll = $listener->poll_once;

    is( $poll->{received}, 1, 'the backstop reads only the row done since' );
    is_deeply( [ map { $_->{json}{payload}{post_id} } @{ $connection->sent } ],
        ['post-new'],
        'a row done before the listener started is not replayed' );

    return;
}

# ADR 0067: the backstop polled every second in every worker whether or not
# anyone was connected to it.
sub _assert_backstop_idles_without_sockets {
    my $functions =
      _outbox_functions( [ _done_row( 'idle', 'thread-idle', 1 ) ] );
    my $now      = $NOW + $PAST_THE_SETTLE;
    my $asked    = 0;
    my $hub      = _hub();
    my $listener = GPForum::Service::Realtime::PgListener->new(
        db_now    => sub { $asked++; return $now; },
        functions => $functions,
        hub       => $hub,
    );
    $listener->start;
    $listener->outbox_poll_cursor(
        { next_attempt_at => 'x', created_at => 'x', outbox_id => 'x' } );

    $listener->poll_once;

    is_deeply( $functions->calls, [],
        'with no local socket no outbox query runs' );
    is( $asked, 0, 'nor is the database clock read' );
    ok( !$listener->outbox_poll_cursor,
        'and the cursor is dropped, so the next socket starts at the head' );

    return;
}

sub _assert_backstop_cursor_advances {
    my $outbox     = [];
    my $now        = $NOW;
    my $connection = GPForum::Test::RealtimeConnection->new;
    my $listener =
      _backstop_listener( $outbox, \$now, 'thread:thread-cursor', $connection );
    $listener->batch_limit(1);

    $listener->start;
    $listener->poll_once;
    push @{$outbox},
      _done_row( 'cursor-1', 'thread-cursor', 1 ),
      _done_row( 'cursor-2', 'thread-cursor', 1 );
    $now += $PAST_THE_SETTLE;
    my $first_poll  = $listener->poll_once;
    my $second_poll = $listener->poll_once;

    is( $first_poll->{received}, 1, 'outbox polling reads first cursor batch' );
    is( $second_poll->{received}, 1,
        'outbox polling advances to second batch' );
    is( scalar @{ $connection->sent },
        2, 'outbox polling cursor avoids replaying the first row' );
    is( $connection->sent->[1]{json}{payload}{post_id},
        'post-cursor-2', 'second cursor batch reaches websocket' );
    my $asked = $listener->functions->asked('ops_realtime_poll')->[-1];
    is_deeply(
        [ @{$asked}{qw(after_next_at settled_at)} ],
        [ _stamp(1), _stamp( $PAST_THE_SETTLE - $SETTLE_SECONDS ) ],
        'the batch is asked from the cursor up to the settled instant'
    );

    return;
}

# The dispatcher stamps next_attempt_at before its UPDATE commits. With two
# dispatchers, a row stamped earlier can commit after one stamped later; a
# cursor that had already passed the later stamp never read the earlier row.
sub _assert_backstop_reads_a_late_commit {
    my $outbox     = [];
    my $now        = $NOW;
    my $connection = GPForum::Test::RealtimeConnection->new;
    my $listener =
      _backstop_listener( $outbox, \$now, 'thread:thread-late', $connection );

    $listener->start;
    $listener->poll_once;
    push @{$outbox}, _done_row( 'prompt', 'thread-late', $STAMP_EARLY_ROW );
    $now += $SEEN_BEFORE_LATE;
    $listener->poll_once;

    push @{$outbox}, _done_row( 'late', 'thread-late', $STAMP_LATE_ROW );
    $now += $PAST_THE_SETTLE;
    $listener->poll_once;

    is_deeply(
        [ map { $_->{json}{payload}{post_id} } @{ $connection->sent } ],
        [ 'post-late', 'post-prompt' ],
        'a row that committed late within the settle window is still read'
    );

    return;
}

sub _assert_cursor_survives_reconnect {
    my $outbox     = [];
    my $now        = $NOW;
    my $connection = GPForum::Test::RealtimeConnection->new;
    my $listener =
      _backstop_listener( $outbox, \$now, 'thread:thread-again', $connection );

    $listener->start;
    $listener->poll_once;
    push @{$outbox}, _done_row( 'before', 'thread-again', 1 );
    $now += $PAST_THE_SETTLE;
    $listener->poll_once;
    my $cursor = $listener->outbox_poll_cursor;

    $listener->reconnect;
    is_deeply( $listener->outbox_poll_cursor,
        $cursor, 'a reconnect keeps the backstop cursor' );

    push @{$outbox}, _done_row( 'during', 'thread-again', 2 );
    $now += $PAST_THE_SETTLE;
    $listener->poll_once;

    is_deeply(
        [ map { $_->{json}{payload}{post_id} } @{ $connection->sent } ],
        [ 'post-before', 'post-during' ],
        'so what was missed during the outage is read once, nothing replayed'
    );

    return;
}

# The backstop built its query inside an eval and ran it outside one, so a
# lost connection made the poll throw. A failed query is an unavailable
# backstop now: the cursor stays, and the next poll asks again.
sub _assert_backstop_survives_a_failed_query {
    my $outbox   = [];
    my $now      = $NOW;
    my $listener = _backstop_listener( $outbox, \$now, 'thread:thread-lost',
        GPForum::Test::RealtimeConnection->new );
    $listener->functions->answers->{ops_realtime_poll} =
      sub ($) { die "server closed the connection unexpectedly\n"; };

    $listener->start;
    $listener->poll_once;
    my $cursor = $listener->outbox_poll_cursor;
    $now += $PAST_THE_SETTLE;
    my $poll;
    try {
        $poll = $listener->poll_once;
    }
    catch ($error) {
        $poll = undef;
    };

    ok( $poll, 'a failed backstop query does not throw' );
    ok( $poll && $poll->{degraded},
        'with no LISTEN either, the poll reports itself degraded' );
    is_deeply( $listener->outbox_poll_cursor,
        $cursor, 'and the cursor stays where it was' );

    return;
}

# The dedup memory is for the hints both paths carry. A badge only ever
# comes by NOTIFY, yet each took a place in it: the badges of one reply's
# fanout pushed out every hint NOTIFYed before them, and the backstop sent
# those hints a second time to every subscriber.
sub _assert_badges_leave_the_dedup_memory_alone {
    my $bus        = GPForum::Test::RealtimeBusDbh->new;
    my $outbox     = [];
    my $now        = $NOW;
    my $connection = GPForum::Test::RealtimeConnection->new;
    my $listener   = GPForum::Service::Realtime::PgListener->new(
        db_now          => sub { return $now; },
        functions       => _outbox_functions($outbox),
        hub             => _hub_for( 'thread:thread-memory', $connection ),
        max_seen_events => $SMALL_MEMORY,
        schema          => GPForum::Test::RealtimeBusSchema->new( dbh => $bus ),
    );
    my $notifier = GPForum::Service::Realtime::PgNotifier->new(
        schema => GPForum::Test::RealtimeBusSchema->new( dbh => $bus ) );
    my $row = _done_row( 'memory', 'thread-memory', 1 );

    $listener->start;
    $listener->poll_once;
    _transport_for_bus($bus)->dispatch( _outbox_message( $row->{payload} ) );
    for my $user_id (qw(user-a user-b user-c)) {
        $notifier->notify(
            GPForum::Service::Realtime::EventEnvelope->new->notification_badge(
                $user_id, 1
            )
        );
    }
    $listener->poll_once;

    push @{$outbox}, $row;
    $now += $PAST_THE_SETTLE;
    $listener->poll_once;

    is( scalar @{ $connection->sent },
        1, 'a hint NOTIFYed before a burst of badges is not sent again' );

    return;
}

sub _last_frame {
    my ($connection) = @_;

    my @sent = @{ $connection->sent };

    return @sent ? $sent[-1] : {};
}

sub _dispatcher_for {
    my ($backend) = @_;

    return GPForum::Service::Notification::Dispatcher->new(
        clock             => GPForum::Test::FixedClock->new,
        id_service        => GPForum::Test::Id->new,
        realtime_notifier => GPForum::Service::Realtime::PgNotifier->new(
            schema => GPForum::Test::RealtimeBusSchema->new( dbh => $backend ),
        ),
        functions => GPForum::Test::NotificationInboxFunctions->new,
        schema    => {},
    );
}

sub _transport_for_bus {
    my ( $bus, $handlers ) = @_;

    my $schema = GPForum::Test::RealtimeBusSchema->new( dbh => $bus );

    return GPForum::Service::Outbox::DomainEventTransport->new(
        handlers          => $handlers || [],
        realtime_notifier => GPForum::Service::Realtime::PgNotifier->new(
            schema => $schema,
        ),
    );
}

sub _listener_for {
    my ( $bus, $channel, $connection ) = @_;

    return GPForum::Service::Realtime::PgListener->new(
        batch_limit => 10,
        hub         => _hub_for( $channel, $connection ),
        schema      => GPForum::Test::RealtimeBusSchema->new( dbh => $bus ),
    );
}

# A listener with no LISTEN, so the outbox backstop is the only path.
sub _backstop_listener {
    my ( $outbox, $now, $channel, $connection ) = @_;

    return GPForum::Service::Realtime::PgListener->new(
        batch_limit => 10,
        db_now      => sub { return ${$now}; },
        functions   => _outbox_functions($outbox),
        hub         => _hub_for( $channel, $connection ),
    );
}

# The function layer as api.ops_realtime_poll answers it over the rows
# given: the done rows after the cursor's (next_attempt_at, created_at,
# outbox_id) and stamped no later than the settled instant, in that order,
# at most row_limit of them. Stamps of one format compare as text.
sub _outbox_functions {
    my ($outbox) = @_;

    return GPForum::Test::AnsweringFunctions->new(
        answers => {
            ops_realtime_poll => sub ($asked) {
                my %cursor;
                @cursor{qw(next_attempt_at created_at outbox_id)} =
                  @{$asked}{qw(after_next_at after_created_at after_id)};
                my @rows = sort { _keyset_order( $a, $b ) } grep {
                         $_->{status} eq 'done'
                      && $_->{next_attempt_at} le $asked->{settled_at}
                      && _keyset_order( $_, \%cursor ) > 0
                } @{$outbox};
                return [ splice @rows, 0, $asked->{row_limit} ];
            },
        }
    );
}

# The order of two rows, or of a row and a cursor, by their keyset.
sub _keyset_order {
    my ( $row, $other ) = @_;

    return
         $row->{next_attempt_at} cmp $other->{next_attempt_at}
      || $row->{created_at}      cmp $other->{created_at}
      || $row->{outbox_id}       cmp $other->{outbox_id};
}

sub _hub {
    return GPForum::Service::Realtime::Hub->new(
        registry   => GPForum::Service::Realtime::ConnectionRegistry->new,
        authorizer => GPForum::Service::Realtime::ChannelAuthorizer->new(
            permission_engine => GPForum::Test::RealtimePermissionEngine->new,
        ),
    );
}

sub _hub_for {
    my ( $channel, $connection ) = @_;

    my $hub = _hub();
    $hub->register_connection( 'connection-1', { user_id => 'user-1' },
        $connection );
    $hub->subscribe(
        {
            actor         => { user_id => 'user-1' },
            channel       => $channel,
            connection_id => 'connection-1',
            context       => {},
        }
    );

    return $hub;
}

sub _outbox_message {
    my ($payload) = @_;

    return GPForum::Test::OutboxPayloadRow->new(
        data => {
            payload => $payload,
        },
    );
}

# A post.created row for post-$name, done $offset seconds after $NOW by the
# database's clock.
sub _done_row {
    my ( $name, $thread_id, $offset ) = @_;

    my $stamp = _stamp($offset);

    return {
        outbox_id       => "outbox-$name",
        status          => 'done',
        next_attempt_at => $stamp,
        created_at      => $stamp,
        payload         => {
            event_id       => "event-$name",
            event_type     => 'post.created',
            aggregate_type => 'post',
            aggregate_id   => "post-$name",
            domain_payload => { thread_id => $thread_id },
        },
    };
}

# $offset seconds after $NOW, as the listener writes an instant.
sub _stamp {
    my ($offset) = @_;

    return strftime( '%Y-%m-%dT%H:%M:%SZ', gmtime( $NOW + $offset ) );
}

1;
