# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Privacy::Deletion::Requests;

use Const::Fast;
use Mojo::Base 'GPForum::Service::Privacy::Deletion::Holds', -async_await;
use v5.40;

use GPForum::Infrastructure::SqlFunction;
use GPForum::Infrastructure::UniqueConflict;

our $VERSION = '0.001';

const my $STATUS_PENDING         => 'pending';
const my $STATUS_APPROVED        => 'approved';
const my $STATUS_HELD            => 'held';
const my $JOB_PENDING            => 'pending';
const my $DELETION_ID_CONSTRAINT => 'deletion_requests_pkey';
const my $OPEN_DELETION_CONSTRAINT =>
  'idx_deletion_requests_open_resource_unique';
const my $ERASURE_ID_CONSTRAINT      => 'erasure_jobs_pkey';
const my $ERASURE_REQUEST_CONSTRAINT => 'idx_erasure_jobs_request_unique';

# Each step is written once, as its promise method (ADR 0177): one
# transaction, every statement on its call layer ($db), the inserts in its
# savepoints.
GPForum::Infrastructure::SqlFunction->blocking_twins(
    qw(request_deletion approve_request));

# An open request on the resource is reused; otherwise a new one is
# inserted. A concurrent insert of the same open request -- the unique
# index idx_deletion_requests_open_resource_unique -- or a minted id already
# stored, is answered by the request then found; a minted id with no such
# request is minted once more.
async sub request_deletion_p ( $self, $input, $context = undef ) {
    return await $self->call_layer->transaction_p(
        async sub ($db) {
            my $existing =
              await $self->_open_deletion_hash_p( $db, $input, $context );
            return await $self->_finish_leftover_deletion_p( $db, $existing,
                $context )
              if $existing;

            my $create = async sub ($savepoint) {
                my $request = $self->_new_request($input);
                await $self->insert_privacy_row_p( $savepoint,
                    'DeletionRequest', $request, $context );
                await $self->record_privacy_event_and_audit_p( $savepoint,
                    $self->_requested($request), $context );

                return $request;
            };
            my ( $created, $error ) =
              await GPForum::Infrastructure::UniqueConflict->attempt_p( $db,
                $create );
            return $created if $created;

            my ( $id_taken, $reread ) =
              $self->lost_race( $error, $DELETION_ID_CONSTRAINT,
                $OPEN_DELETION_CONSTRAINT );
            if ($reread) {
                $existing =
                  await $self->_open_deletion_hash_p( $db, $input, $context );
                return await $self->_finish_leftover_deletion_p( $db,
                    $existing, $context )
                  if $existing;
                return
                  await GPForum::Infrastructure::UniqueConflict->once_more_p(
                    $db, $create )
                  if $id_taken;
            }

            GPForum::Infrastructure::UniqueConflict->rethrow($error);
        },
        $context
    );
}

# Under a lock on the request, an approval whose job an earlier attempt
# already scheduled finishes that attempt; a request under an active hold is
# held instead; otherwise the request is approved and its erasure job
# scheduled.
async sub approve_request_p ( $self, $request_id, $actor_id, $reason,
    $context = undef )
{
    return await $self->call_layer->transaction_p(
        async sub ($db) {
            my $request =
              await $self->find_privacy_row_p( $db, 'DeletionRequest',
                $request_id, 1, $context );
            return undef if !$request;

            my $input =
              $self->_approval( $request_id, $actor_id, $reason, $request );
            my $existing =
              await $self->latest_row_p( $db, $context,
                $self->job_query($request_id) );
            return await $self->_finish_leftover_approval_p( $db, $input,
                $existing, $context )
              if $existing;

            my $hold = await $self->latest_row_p( $db, $context,
                $self->active_hold_query($request) );
            return await $self->open_hold_p( $db,
                $self->_approval_hold( $input, $hold ), $context )
              if $hold;

            await $self->set_request_status_p( $db, $request,
                $STATUS_APPROVED, $context );
            my $inserted =
              await $self->_insert_or_reuse_job_p( $db, $input, $context );
            return await $self->_finish_leftover_approval_p( $db, $input,
                $inserted->{job}, $context )
              if $inserted->{reused};

            return await $self->_emit_approval_p( $db, $input,
                $inserted->{job}, $context );
        },
        $context
    );
}

sub _new_request ( $self, $input ) {
    return {
        completed_at        => undef,
        created_at          => $self->clock->now_iso8601,
        deletion_request_id => $self->id_service->uuid,
        reason              => $input->{reason} || q{},
        request_type        => $input->{request_type},
        requester_user_id   => $input->{requester_user_id},
        resource_id         => $input->{resource_id},
        resource_type       => $input->{resource_type},
        status              => $STATUS_PENDING,
    };
}

sub _requested ( $self, $request ) {
    return $self->events->requested(
        {
            actor_id => $request->{requester_user_id},
            request  => $request,
        }
    );
}

sub _requested_key ($request) {
    return join q{:}, 'privacy.deletion_requested',
      $request->{deletion_request_id};
}

sub _approval ( $self, $request_id, $actor_id, $reason, $request ) {
    return {
        actor_id   => $actor_id,
        reason     => $reason,
        request    => $request,
        request_id => $request_id,
        timestamp  => $self->clock->now_iso8601,
    };
}

sub _approval_hold ( $self, $input, $hold ) {
    return {
        actor_id  => $input->{actor_id},
        hold      => $hold,
        reason    => $self->completion->hold_reason( $input->{reason} ),
        request   => $input->{request},
        timestamp => $input->{timestamp},
    };
}

sub _approval_action ($input) {
    return {
        action_type => 'released',
        actor_id    => $input->{actor_id},
        created_at  => $input->{timestamp},
        metadata    => {
            reason => $input->{reason} || q{},
            status => $STATUS_APPROVED,
        },
    };
}

sub _approved ( $self, $input, $action, $job ) {
    return {
        action     => $action,
        job        => $self->record->job_hash($job),
        ok         => 1,
        request_id => $input->{request_id},
    };
}

sub _new_job ( $self, $input ) {
    return {
        completed_at        => undef,
        deletion_request_id => $input->{request_id},
        erasure_job_id      => $self->id_service->uuid,
        last_error          => undef,
        scheduled_at        => $input->{timestamp},
        status              => $JOB_PENDING,
    };
}

sub _released_query ($input) {
    return (
        'DeletionAction',
        {
            action_type         => 'released',
            deletion_request_id => $input->{request_id},
        },
        'created_at',
    );
}

sub _open_deletion_query ($input) {
    return (
        'DeletionRequest',
        {
            request_type  => $input->{request_type},
            resource_id   => $input->{resource_id},
            resource_type => $input->{resource_type},
            status        => {
                -in => [ $STATUS_PENDING, $STATUS_APPROVED, $STATUS_HELD ],
            },
        },
        'created_at',
    );
}

# An earlier attempt may have committed the request without its event.
async sub _finish_leftover_deletion_p ( $self, $db, $existing, $context ) {
    if (
        !await $self->event_recorded_p( $db, _requested_key($existing),
            $context ) )
    {
        await $self->record_privacy_event_and_audit_p( $db,
            $self->_requested($existing), $context );
    }

    return $existing;
}

async sub _open_deletion_hash_p ( $self, $db, $input, $context ) {
    my $row =
      await $self->latest_row_p( $db, $context, _open_deletion_query($input) );
    return $row ? $self->record->request_hash($row) : undef;
}

async sub _finish_leftover_approval_p ( $self, $db, $input, $job, $context ) {
    my $released =
      await $self->latest_row_p( $db, $context, _released_query($input) );
    return $self->completion->approval_replay( $input->{request_id}, $job )
      if $released;

    await $self->set_request_status_p( $db, $input->{request},
        $STATUS_APPROVED, $context );
    return await $self->_emit_approval_p( $db, $input, $job, $context );
}

async sub _emit_approval_p ( $self, $db, $input, $job, $context ) {
    my $action = await $self->record_action_p( $db, $input->{request_id},
        _approval_action($input), $context );
    await $self->record_privacy_event_and_audit_p(
        $db,
        $self->events->approved(
            { %{$input}, action => $action, job => $job }
        ),
        $context
    );

    return $self->_approved( $input, $action, $job );
}

# A concurrent approval's job, or a minted id already stored, is answered by
# the request's job then found; a minted id with no such job is minted once
# more.
async sub _insert_or_reuse_job_p ( $self, $db, $input, $context ) {
    my $create = async sub ($savepoint) {
        my $job = $self->_new_job($input);
        await $self->insert_privacy_row_p( $savepoint, 'ErasureJob', $job,
            $context );

        return $job;
    };
    my ( $created, $error ) =
      await GPForum::Infrastructure::UniqueConflict->attempt_p( $db, $create );
    return { job => $created, reused => 0 } if $created;

    my ( $id_taken, $reread ) =
      $self->lost_race( $error, $ERASURE_ID_CONSTRAINT,
        $ERASURE_REQUEST_CONSTRAINT );
    if ($reread) {
        my $existing =
          await $self->latest_row_p( $db, $context,
            $self->job_query( $input->{request_id} ) );
        return { job => $existing, reused => 1 } if $existing;
        return {
            job => await GPForum::Infrastructure::UniqueConflict->once_more_p(
                $db, $create
            ),
            reused => 0
          }
          if $id_taken;
    }

    GPForum::Infrastructure::UniqueConflict->rethrow($error);
}

1;

__END__

=head1 NAME

GPForum::Service::Privacy::Deletion::Requests - Requesting and approving a deletion.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    # Part of GPForum::Service::Privacy::DeletionWorkflow; callers use that class.

=head1 DESCRIPTION

Open a deletion request, approve it and queue its erasure job, finishing a leftover from an interrupted attempt, each written once, as its promise method (ADR 0177).

GPForum::Service::Privacy::DeletionWorkflow inherits it, so the object a caller builds has every method; this
file holds one part of that class so each part can be read by itself.

=head1 SUBROUTINES/METHODS

=head2 request_deletion_p

Takes a hash reference with C<requester_user_id>, C<request_type>,
C<resource_type>, C<resource_id> and an optional C<reason> (empty when
omitted), and an optional query context. In one transaction, creates a C<pending> request and records
C<privacy.deletion_requested>, or returns the open request already there.
Returns the request as a hash reference: C<deletion_request_id>,
C<request_type>, C<requester_user_id>, C<resource_type>, C<resource_id>,
C<reason>, C<status>, C<created_at> and C<completed_at>.

=head2 approve_request_p

Takes a request id, the approving actor's id, a reason and an optional
query context; runs in one transaction, the request locked. Returns undef
when there is no such request. Otherwise:

=over 4

=item *

with no erasure job yet and no active hold, sets the request C<approved>,
schedules the job, records a C<released> deletion action and
C<privacy.deletion_approved>, and returns
C<< { ok => 1, request_id, action, job } >>, C<job> being the job as a hash
reference;

=item *

with an active hold, holds the request as C<hold_request> does (the reason
defaulting to C<active legal hold>) and returns
C<< { ok => 0, error => 'retention_hold_active', request_id, action } >>,
C<action> being undef when the request was already held;

=item *

when the request already has a job and a C<released> action, returns
C<< { ok => 1, idempotent => 1, request_id, job } >>; with a job but no
action yet, it finishes the approval as in the first case.

=back

=head2 request_deletion, approve_request

The blocking twins of the promise methods above (ADR 0177): each runs its
promise method on the blocking layer, the process's own connection and the
transaction it holds, and returns its answer.

=head1 DIAGNOSTICS

As GPForum::Service::Privacy::DeletionWorkflow.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

As GPForum::Service::Privacy::DeletionWorkflow.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

None known.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
