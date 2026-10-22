# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Notification::DigestQueue;

use Const::Fast;
use Mojo::Base -base, -signatures;
use v5.40;

use GPForum::Infrastructure::EventRecorder;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Service::Clock;
use GPForum::Service::Forum::ViewerResolver;

our $VERSION = '0.001';

# ADR 0078: the mail event a digest is queued as, the threads one names
# (the rest are counted), the members one page of the due list takes by
# default and at most (the database's own cap), the pages one run reads,
# and how long the record of a period is kept: past the 14-day window a
# digest catches up.
const my $DIGEST_REQUESTED  => 'notification.digest.requested';
const my $ITEM_LIMIT        => 20;
const my $DEFAULT_LIMIT     => 100;
const my $MAX_LIMIT         => 1_000;
const my $PAGES_PER_RUN     => 50;
const my $KEEP_SECONDS      => 35 * 24 * 60 * 60;
const my @ITEM_FIELDS       => qw(thread_id title category_title new_posts);
const my %COUNTED_OUTCOMES  => map { $_ => 1 } qw(queued empty);
const my $FIRST_LINE        => qr/\A ([^\n]*)/msx;
const my $TRAILING_LOCATION => qr/\s+ at \s+ \S+ \s+ line \s+ \d+ [.]? \z/msx;

has clock          => sub { return GPForum::Service::Clock->new; };
has event_recorder => sub ($self) {
    return GPForum::Infrastructure::EventRecorder->new(
        schema => $self->schema );
};
has functions => sub ($self) {
    return GPForum::Infrastructure::SqlFunction->for_schema( $self->schema );
};
has logger          => undef;          # optional: failures are only counted
has schema          => undef;          # optional: without one nothing is queued
has viewer_resolver => sub ($self) {
    return GPForum::Service::Forum::ViewerResolver->new(
        logger => $self->logger,
        schema => $self->schema,
    );
};

# One bounded run: the members due a digest, the longest waiting first,
# page after page by the due list's key until it is drained or the run has
# read its pages, each read as they read and recorded once -- queued with
# the threads it names, or empty -- then the records past keeping removed.
# A member that fails is named in errors, passed over by the key and taken
# again by the next run; the others go on.
sub run ( $self, $input = {} ) {
    my $functions = $self->functions;
    return { ok => 1, queued => 0, skipped => 'unavailable' } if !$functions;

    my $limit = $input->{limit} || $DEFAULT_LIMIT;
    $limit = $limit > $MAX_LIMIT ? $MAX_LIMIT : $limit;
    my $now   = $self->clock->now_iso8601;
    my %done  = ( queued      => 0,     empty         => 0 );
    my %after = ( after_start => undef, after_user_id => undef );
    my @errors;
    for ( 1 .. $PAGES_PER_RUN ) {
        my $due = $functions->rows( 'notification_digest_due',
            { now => $now, %after, row_limit => $limit } );
        for my $member ( @{$due} ) {
            push @errors, $self->_queue_counted( $member, $now, \%done );
        }
        last if @{$due} < $limit;
        %after = (
            after_start   => $due->[-1]{period_start},
            after_user_id => $due->[-1]{user_id},
        );
    }
    my $purged = $functions->row(
        'notification_digest_purge',
        {
            before    => $self->clock->epoch_plus_iso8601( -$KEEP_SECONDS ),
            row_limit => $limit,
        }
    );

    return {
        ok     => @errors ? 0 : 1,
        queued => $done{queued},
        empty  => $done{empty},
        purged => $purged ? $purged->{deleted} // 0 : 0,
        ( @errors ? ( errors => \@errors ) : () ),
    };
}

# Queues one member and counts the outcome; answers its error line, if any.
sub _queue_counted ( $self, $member, $now, $done ) {
    my @error;
    try {
        my $status = $self->_queue( $member, $now );
        if ( $COUNTED_OUTCOMES{$status} ) {
            $done->{$status}++;
        }
    }
    catch ($error) {
        my ($line) = "$error" =~ $FIRST_LINE;
        $line =~ s/$TRAILING_LOCATION//msx;
        push @error, "$member->{user_id}: $line";
        if ( $self->logger ) {
            $self->logger->warn("digest not queued: $member->{user_id}: $line");
        }
    };

    return @error;
}

sub _queue ( $self, $member, $now ) {
    my $user_id = $member->{user_id};
    my $viewer  = $self->viewer_resolver->resolve($user_id);
    my $items   = $self->functions->rows(
        'notification_digest_items',
        {
            user_id      => $user_id,
            period_start => $member->{period_start},
            period_end   => $member->{period_end},
            member       => $viewer->member,
            global_read  => $viewer->global_read,
            category_ids => $viewer->category_ids,
            space_ids    => $viewer->space_ids,
            row_limit    => $ITEM_LIMIT,
        }
    );
    my $total = @{$items} ? $items->[0]{thread_total} : 0;
    my $call  = {
        event         => undef,
        outbox_id     => undef,
        outbox_extras => undef,
        explicit      => 0,
    };
    if ($total) {
        $call = $self->event_recorder->event_call(
            event_type        => $DIGEST_REQUESTED,
            aggregate_type    => 'user',
            aggregate_id      => $user_id,
            aggregate_version => 1,
            actor_id          => $user_id,
            idempotency_key   => join( q{:},
                'notification.digest', $user_id,
                $member->{frequency},  $member->{period_start} ),
            payload => {
                recipient_user_id => $user_id,
                frequency         => $member->{frequency},
                period_start      => $member->{period_start},
                period_end        => $member->{period_end},
                thread_total      => $total,
                items => [ map { +{ %{$_}{@ITEM_FIELDS} } } @{$items} ],
            },
        );
    }
    my $row = $self->functions->row(
        'notification_digest_record',
        {
            user_id      => $user_id,
            frequency    => $member->{frequency},
            period_start => $member->{period_start},
            period_end   => $member->{period_end},
            thread_count => $total,
            now          => $now,
            %{$call},
        }
    );

    return $row ? $row->{status} : 'invalid';
}

1;

__END__

=head1 NAME

GPForum::Service::Notification::DigestQueue - Queues the daily and weekly email digests.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $summary = GPForum::Service::Notification::DigestQueue->new(
        schema => $schema )->run( { limit => 100 } );
    # { ok => 1, queued => 3, empty => 9, purged => 0 }

=head1 DESCRIPTION

ADR 0078. The C<notification_digests> job of the scheduled-jobs runner. A
member who turned the digest channel on, daily or weekly, with the email
channel on, a verified address and no suspension, is due a window: from
where their last digest ended to the end of their last complete period
(the UTC day, or the UTC week from Monday, complete ten minutes after it
ends), at most 14 days back. The due members are read in pages of
C<limit>, the longest waiting first, up to 50 pages a run. For each, the
threads they follow and the threads in the categories they follow (less
those they muted) with posts from that window they have not read are
read as the member reads (L<GPForum::Service::Forum::ViewerResolver>), and
the window is recorded once: with threads, as a
C<notification.digest.requested> event in the event log and outbox (the
twenty latest threads, and how many there were), which
L<GPForum::Worker::Handler::NotificationDigest> mails; without, as empty.
A second run finds nothing new due; a run cut short, or missed, leaves
the rest due for the next, whose window covers what was
missed. Records of periods that ended over 35 days ago are then removed,
at most C<limit> of them.

=head1 SUBROUTINES/METHODS

=head2 run

Takes an optional hash reference with C<limit>, the members per page
(100 by default, at most 1,000). Returns C<< { ok, queued, empty, purged } >>,
with C<errors> (C<user id: reason>) and C<ok> 0 when a member could not be
queued, or C<< { ok => 1, queued => 0, skipped => 'unavailable' } >>
without the PostgreSQL function layer.

=head1 DIAGNOSTICS

A failure for one member is caught, logged and named in C<errors>; the
due list or the purge failing propagates.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<Const::Fast>, L<GPForum::Infrastructure::EventRecorder>,
L<GPForum::Infrastructure::SqlFunction>, L<GPForum::Service::Clock> and
L<GPForum::Service::Forum::ViewerResolver>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Periods are UTC: a member far from it receives the day's digest at their
own morning or evening. A member who switches between daily and weekly
receives the new frequency's next complete period, from where the last
digest ended. A member who turns the digest back on within 14 days is
caught up from their last digest.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause
license.

=cut
