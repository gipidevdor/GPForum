# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Outbox::Dispatcher;

use Const::Fast;
use GPForum::Service::Clock;
use GPForum::Service::Outbox::ClaimedMessage;
use GPForum::Service::Outbox::DeadLetterRecorder;
use GPForum::Service::Outbox::FailureType;
use GPForum::Service::Outbox::Retry;
use Mojo::Base 'GPForum::Base', -signatures;
use v5.40;

use GPForum::Infrastructure::SqlFunction;
use GPForum::Infrastructure::AsyncWork;
use GPForum::Infrastructure::AsyncGate;
use Digest::SHA qw(sha256);
use Mojo::Promise;
use GPForum::Jobs::EventPayload;
use GPForum::X::Unavailable;

our $VERSION = '0.001';

has functions => \&GPForum::Infrastructure::SqlFunction::for_service;

const my $MAX_CONCURRENCY     => 8;
const my $DIGEST_PREFIX_BYTES => 4;

const my $DEFAULT_LIMIT        => 100;
const my $DEFAULT_MAX_ATTEMPTS => 5;
const my $DONE_STATUS          => 'done';
const my $GENERIC_ERROR_CLASS  => 'error';

__PACKAGE__->requires(qw(schema transport));
has clock         => sub { return GPForum::Service::Clock->new; };
has worker_id     => 'worker';
has max_attempts  => $DEFAULT_MAX_ATTEMPTS;
has id_service    => undef; # optional: the dead-letter recorder's default
has logger        => undef; # optional: lost claims are only counted without one
has failure_types => sub { return GPForum::Service::Outbox::FailureType->new; };
has retry         => sub {
    my ($self) = @_;

    return GPForum::Service::Outbox::Retry->new(
        max_attempts => $self->max_attempts, );
};
has dead_letter_recorder => sub {
    my ($self) = @_;

    return GPForum::Service::Outbox::DeadLetterRecorder->new(
        $self->_dead_letter_recorder_args, );
};

# A batch is claimed for Retry's lock_seconds, and a slow batch can outlive
# that claim: acknowledged together at the end, its messages would be claimed
# and delivered by a second worker once the lease ran out, and again by this
# one. So each message is handled on its own: its claim renewed just before
# it is dispatched, its outcome written as soon as it is known, and every one
# of those writes made only while the message is still this worker's.
sub dispatch_pending ( $self, $limit ) {
    my @messages = $self->claim_ready_batch( $limit || $DEFAULT_LIMIT );
    my %summary  = (
        acknowledged  => 0,
        dead_lettered => 0,
        dispatched    => 0,
        failed        => 0,
        lost          => 0,
        selected      => scalar @messages,
    );

    for my $message (@messages) {
        for my $counter ( $self->_handle($message) ) {
            $summary{$counter} += 1;
        }
    }

    return \%summary;
}

# CLI/background entry point. A batch uses a bounded number of children,
# rather than a new fork per message. Events of the same aggregate stay on
# one ordered lane; canonical application writes never enter this executor.
sub dispatch_pending_p ( $self, $limit, $concurrency = 2 ) {
    _validate_concurrency($concurrency);
    return Mojo::Promise->resolve->then(
        sub { return $self->dispatch_pending($limit); } )
      if $concurrency <= 1;
    return $self->_claimed_rows_p( $self->_functions, $limit || $DEFAULT_LIMIT )
      ->then(
        sub ($rows) {
            my $lanes    = $self->_dispatch_lanes( $rows, $concurrency );
            my $executor = GPForum::Infrastructure::AsyncWork->new(
                gate => GPForum::Infrastructure::AsyncGate->new(
                    concurrency => $concurrency
                )
            );
            my @work =
              map { $executor->job_p( $self, 'dispatch_claimed_rows', [$_] ) }
              grep { @{$_} } @{$lanes};
            return _dispatch_summary() if !@work;
            return Mojo::Promise->all(@work)->then(
                sub (@parts) {
                    return _dispatch_summary( map { $_->[0] } @parts );
                }
            );
        }
      );
}

sub _dispatch_lanes ( $self, $rows, $concurrency ) {
    my @lanes = map { [] } 1 .. $concurrency;
    for my $row ( @{$rows} ) {
        my $message = $self->_claimed_message_for_row($row);
        my $payload = GPForum::Jobs::EventPayload->normalize(
            $message->get_column('payload') );
        my $key = join q{:},
          map { $payload->{$_} // q{} } qw(aggregate_type aggregate_id);
        if ( $key eq q{:} ) { $key = 'legacy'; }
        my $digest = sha256($key);
        my $prefix = substr $digest, 0, $DIGEST_PREFIX_BYTES;
        my $bucket = unpack 'N', $prefix;
        push @{ $lanes[ $bucket % $concurrency ] }, $row;
    }
    return \@lanes;
}

sub _dispatch_summary (@parts) {
    my %summary = map { $_ => 0 }
      qw(acknowledged dead_lettered dispatched failed lost selected);
    for my $part (@parts) {
        for my $counter ( keys %summary ) {
            $summary{$counter} += $part->{$counter};
        }
    }
    return \%summary;
}

sub _validate_concurrency ($concurrency) {
    if (  !defined $concurrency
        || ref $concurrency
        || $concurrency !~ /\A[1-9]\d*\z/amsx
        || $concurrency > $MAX_CONCURRENCY )
    {
        GPForum::X::Argument->throw(
            message => 'outbox concurrency must be between 1 and 8' );
    }
    return;
}

sub dispatch_claimed_rows ( $self, $rows ) {
    my %summary =
      map { $_ => 0 } qw(acknowledged dead_lettered dispatched failed lost);
    $summary{selected} = scalar @{$rows};
    for my $row ( @{$rows} ) {
        for my $counter (
            $self->_handle( $self->_claimed_message_for_row($row) ) )
        {
            $summary{$counter}++;
        }
    }
    return \%summary;
}

# The batch is claimed once, by _claimed_rows_p: here on the blocking
# layer, by dispatch_pending_p on a pooled connection.
sub claim_ready_batch ( $self, $limit ) {
    my $rows = GPForum::Infrastructure::SqlFunction->settled(
        $self->_claimed_rows_p( $self->_functions->blocking_layer, $limit ) );

    return map { $self->_claimed_message_for_row($_) } @{$rows};
}

sub _claimed_rows_p ( $self, $functions, $limit ) {
    return $functions->rows_p(
        'outbox_claim_ready',
        {
            now          => $self->clock->now_iso8601,
            locked_until =>
              $self->clock->epoch_plus_iso8601( $self->retry->lock_seconds ),
            worker_id => $self->worker_id,
            row_limit => $limit,
        }
    );
}

sub _functions ($self) {
    return $self->functions // GPForum::X::Unavailable->throw( message =>
          'the outbox dispatcher needs the PostgreSQL function layer' );
}

# One message from claim to outcome; answers the summary counters it adds
# to. A message whose claim another worker took is not dispatched; one
# handled after its claim was taken is not acknowledged, and one that failed
# then leaves its failure to the worker that owns it.
sub _handle ( $self, $message ) {
    if ( !$self->_renew_claim($message) ) {
        return $self->_lost( $message, 'before dispatching it; skipped' );
    }

    try {
        $self->transport->dispatch($message);
    }
    catch ($error) {
        return $self->_record_failure( $message, $error );
    };

    if ( !$self->_owned_write( $message, $self->_done_columns ) ) {
        return (
            'dispatched',
            $self->_lost(
                $message,
                'after dispatching it; another worker may deliver it again'
            )
        );
    }

    return qw(dispatched acknowledged);
}

# The lease starts again from now, so a message that waited in the batch is
# dispatched with a whole lease ahead of it. A message whose lease ran out
# while it waited is renewed all the same when no other worker claimed it.
sub _renew_claim ( $self, $message ) {
    return $self->_owned_write(
        $message,
        {
            locked_until =>
              $self->clock->epoch_plus_iso8601( $self->retry->lock_seconds ),
        }
    );
}

# Writes the changes while the message is still this worker's and answers
# whether they landed: through api.outbox_owned_write, which writes only a
# message this worker still owns -- on the blocking layer, or on the
# failure's transaction ($functions).
sub _owned_write ( $self, $message, $changes, $functions = undef ) {
    $functions //= $self->_functions->blocking_layer;
    my $written = GPForum::Infrastructure::SqlFunction->settled(
        $functions->row_p(
            'outbox_owned_write',
            {
                outbox_id => $message->get_column('outbox_id'),
                worker_id => $self->worker_id,
                changes   => $changes,
            }
        )
    );
    return 0 if !$written->{landed};
    $message->apply_columns($changes);

    return 1;
}

# A message this worker no longer owns: counted, logged, and left to the
# worker that does.
sub _lost ( $self, $message, $moment ) {
    if ( $self->logger ) {
        $self->logger->warn(
            sprintf 'outbox message %s: %s lost its claim %s',
            $message->get_column('outbox_id') // q{?},
            $self->worker_id, $moment
        );
    }

    return 'lost';
}

sub _claimed_message_for_row {
    my ( $self, $row ) = @_;

    return GPForum::Service::Outbox::ClaimedMessage->new( row => $row );
}

sub _done_columns ($self) {
    return {
        last_error       => undef,
        last_error_class => undef,
        locked_at        => undef,
        locked_by        => undef,
        locked_until     => undef,
        next_attempt_at  => $self->clock->now_iso8601,
        status           => $DONE_STATUS,
    };
}

# The status update and the dead-letter row are one fact about one failure,
# written in one transaction: written separately, a crash between them would
# leave a message cancelled -- terminal, never retried -- with no dead letter
# saying why. And both are this worker's to write only while it still owns
# the message, which the update's affected row count says: without it, a
# worker whose claim another had taken over, and acknowledged, would record
# a dead letter for a message that had been delivered.
sub _record_failure ( $self, $message, $exception ) {
    my $attempt_count = $self->retry->next_attempt($message);
    my $failure_type  = $self->failure_types->classify($exception);
    my $status        = $self->retry->status( $attempt_count, $failure_type );
    my $failure       = {
        attempt_count => $attempt_count,
        error_class   => ref $exception || $GENERIC_ERROR_CLASS,
        error_message => "$exception",
        failure_type  => $failure_type,
        retry_after   => blessed($exception)
          && $exception->can('retry_after') ? $exception->retry_after : 0,
    };
    my $write = sub ($scope) {
        if (
            !$self->_owned_write(
                $message, $self->_failed_columns( $status, $failure ),
                $scope
            )
          )
        {
            return 0;
        }
        if ( $self->retry->is_cancelled($status) ) {
            GPForum::Infrastructure::SqlFunction->joined(
                $self->dead_letter_recorder, $scope )
              ->create_dead_letter( $message, $failure );
        }
        return 1;
    };

    my $recorded = GPForum::Infrastructure::SqlFunction->settled(
        $self->_functions->blocking_layer->transaction_p($write) );
    if ( !$recorded ) {
        return $self->_lost( $message,
            'after it failed; the failure is left to the worker that owns it' );
    }

    return $self->retry->is_cancelled($status) ? 'dead_lettered' : 'failed';
}

sub _failed_columns ( $self, $status, $failure ) {
    my $delay = $self->retry->backoff_seconds( $failure->{attempt_count} );
    if ( ( $failure->{retry_after} // 0 ) > $delay ) {
        $delay = $failure->{retry_after};
    }
    return {
        attempt_count    => $failure->{attempt_count},
        failure_type     => $failure->{failure_type},
        last_error       => $failure->{error_message},
        last_error_class => $failure->{error_class},
        locked_at        => undef,
        locked_by        => undef,
        locked_until     => undef,
        next_attempt_at  => $self->clock->epoch_plus_iso8601($delay),
        status           => $status,
    };
}

sub _dead_letter_recorder_args ($self) {
    my %args = (
        clock     => $self->clock,
        schema    => $self->schema,
        functions => $self->functions,
    );
    if ( $self->id_service ) {
        $args{id_service} = $self->id_service;
    }

    return %args;
}

1;

__END__

=head1 NAME

GPForum::Service::Outbox::Dispatcher - Claim, dispatch, retry, and dead-letter.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $summary = $dispatcher->dispatch_pending($limit);

=head1 DESCRIPTION

Claims ready outbox rows, dispatches them through a transport, and records
retry or dead-letter outcomes. Classification lives in
L<GPForum::Service::Outbox::FailureType>, attempt policy in
L<GPForum::Service::Outbox::Retry>. On PostgreSQL the claim and every write
after it go through C<api.outbox_claim_ready> and C<api.outbox_owned_write>
(L<GPForum::Infrastructure::SqlFunction>), each written once (ADR 0177): the
claim is one body, settled on the blocking layer for L</dispatch_pending> and
awaited on a pooled connection by L</dispatch_pending_p>. A message is
handled on the blocking layer either way, in this process or in a lane's
child.

=head1 SUBROUTINES/METHODS

=head2 dispatch_pending

Claims a bounded batch and handles its messages in order, one at a time:
renews the message's claim for another C<lock_seconds>, dispatches it, and
writes its outcome at once -- C<done>, or the retry or cancellation and its
dead letter in one transaction. Each of those writes is an UPDATE on
C<locked_by> = this worker and C<status> = C<running>, so it lands only while
the message is still this worker's. A message whose claim another worker
took is not dispatched; one dispatched after that is not acknowledged; one
that failed after that records no failure and no dead letter. Each is logged
as a warning when a C<logger> is set.

Returns a hash reference of counts: C<selected>, C<dispatched> (the
transport accepted it), C<acknowledged>, C<failed> (scheduled for a retry),
C<dead_lettered> and C<lost> (a claim another worker took).

=head2 dispatch_pending_p

Claims a bounded batch asynchronously and dispatches it through at most eight
isolated worker lanes. Takes the batch limit and an optional concurrency
(default two). Messages for the same aggregate stay on one ordered lane.
Returns a promise for the same counter summary as C<dispatch_pending>.

=head2 dispatch_claimed_rows

Dispatches an already claimed row batch inside its owning worker lane. Takes
the row array reference and returns the selected, dispatched, acknowledged,
failed, dead-lettered and lost counters, preserving ownership checks.

=head2 claim_ready_batch

Claims ready pending, failed, and stale running messages, through
C<api.outbox_claim_ready> on the blocking layer, and returns them as
L<GPForum::Service::Outbox::ClaimedMessage>s.

=head1 DIAGNOSTICS

Transport exceptions are classified and persisted on the outbox row. A lost
claim logs C<outbox message ID: WORKER lost its claim ...>, saying whether it
was lost before the dispatch, after it, or after a failure.

=head1 CONFIGURATION AND ENVIRONMENT

C<max_attempts> defaults to 5. C<functions>, the SQL function layer, comes
from the schema; without one the dispatcher throws
L<GPForum::X::Unavailable>.
C<logger>, a L<Mojo::Log>, is optional: without one a lost claim is only
counted. C<worker_id> must tell this worker from every other one claiming
from the same table, since the claim is its to keep only while C<locked_by>
says so.

=head1 DEPENDENCIES

Uses L<Const::Fast>, L<Mojo::Base>, L<GPForum::Infrastructure::SqlFunction>
and the outbox helpers above.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Delivery is at-least-once. Handlers must be idempotent for replay after a
crash between dispatch and acknowledgement, and for a message whose own
dispatch outlasts its lease: another worker may claim and deliver it while
this one is still at it.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
