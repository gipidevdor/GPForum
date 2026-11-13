# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Privacy::Deletion::Erasure;

use Const::Fast;
use Mojo::Base 'GPForum::Service::Privacy::Deletion::Requests', -async_await;
use v5.40;

use GPForum::Infrastructure::SqlFunction;

our $VERSION = '0.001';

const my $STATUS_HELD => 'held';
const my $JOB_DONE    => 'done';

# What an erasure revokes beyond the credentials, the account and its
# sessions, in the order it revokes them.
#
# The member's single-use tokens go with the credentials: a reset, an email
# change with the new address in it, a verification. They stayed until they
# expired and the purge took them, the address in them too.
const my @TOKEN_SOURCES => qw(IdentityToken);

# After the sessions: drafts, likes, reactions, ballots and admission; every
# ignore and block list (ADR 0130); their posts held for review (ADR 0134);
# the staff notes about them (ADR 0138); the direct messages they wrote,
# with their side of each conversation (ADR 0139); their two-step sign-in
# secret, recovery codes and challenges (ADR 0142).
const my @BEFORE_AVATAR_SOURCES => qw(ForumDraft PostLike PostReaction
  PollBallot Admission MemberRelation HeldPost MemberNote DirectMessage
  SecondFactor);

# ADR 0144: their profile pictures, the stored files first and then these
# rows; ADR 0146: their name from the address bans they placed, edited or
# lifted; and what they followed, threads and categories alike, so no reply
# notifies the erased account; their bookmarks, with their notes and
# folders; their notification preferences and digests, and the
# notifications they were sent.
const my @AVATAR_AND_LATER_SOURCES => qw(Avatar AddressBan Subscription
  Bookmark NotificationPreference Notification);

# Each step is written once, as its promise method (ADR 0177).
GPForum::Infrastructure::SqlFunction->blocking_twins(qw(complete_job));

# A job done by an earlier attempt is replayed, its request completed if
# that attempt left it open. Otherwise an active hold on the request blocks
# the erasure, and without one the subject is erased.
#
# The deletion request is locked first, as an approval and a hold lock it,
# and the job and the holds are read after the lock: a hold placed while an
# erasure was under way, or a second run of the same job, waits for it, and
# then finds the request held or the job done. Both were read unlocked: a
# hold committed meanwhile was overrun, and two runs both erased.
async sub complete_job_p ( $self, $erasure_job_id, $actor_id, $context = undef )
{
    return await $self->call_layer->transaction_p(
        async sub ($db) {
            my $found =
              await $self->find_privacy_row_p( $db, 'ErasureJob',
                $erasure_job_id, 0, $context );
            return undef if !$found;

            my $request =
              await $self->find_privacy_row_p( $db, 'DeletionRequest',
                $self->record->column( $found, 'deletion_request_id' ),
                1, $context );
            my $job =
              await $self->find_privacy_row_p( $db, 'ErasureJob',
                $erasure_job_id, 0, $context );
            if ( $self->completion->job_done($job) ) {
                if ($request) {
                    await $self->complete_request_row_p( $db, $request,
                        $self->_job_completed_at($job), $context );
                }
                return $self->completion->completion_replay($erasure_job_id);
            }
            return undef if !$request;

            my $input =
              $self->_erasure( $erasure_job_id, $actor_id, $job, $request );
            my $hold = await $self->latest_row_p( $db, $context,
                $self->active_hold_query($request) );
            if ($hold) {
                $input->{hold} = $hold;
                return await $self->_block_erasure_p( $db, $input, $context );
            }

            return await $self->_finish_erasure_p( $db, $input, $context );
        },
        $context
    );
}

# A job done by an earlier attempt completed its request at its own time,
# or now when it kept none.
sub _job_completed_at ( $self, $job ) {
    my $completed_at = $self->record->column( $job, 'completed_at' );
    if ( !defined $completed_at || !length $completed_at ) {
        $completed_at = $self->clock->now_iso8601;
    }

    return $completed_at;
}

sub _erasure ( $self, $erasure_job_id, $actor_id, $job, $request ) {
    return {
        actor_id       => $actor_id,
        erasure_job_id => $erasure_job_id,
        job            => $job,
        request        => $request,
        timestamp      => $self->clock->now_iso8601,
    };
}

sub _blocked_action ( $self, $input ) {
    return {
        action_type => 'held',
        actor_id    => $input->{actor_id},
        created_at  => $input->{timestamp},
        metadata    => {
            erasure_job_id    => $input->{erasure_job_id},
            retention_hold_id =>
              $self->record->column( $input->{hold}, 'retention_hold_id' ),
        },
    };
}

sub _done_job ($input) {
    return {
        completed_at => $input->{timestamp},
        last_error   => undef,
        status       => $JOB_DONE,
    };
}

sub _anonymized_action ( $input, $anonymized ) {
    return {
        action_type => 'anonymized',
        actor_id    => $input->{actor_id},
        created_at  => $input->{timestamp},
        metadata    => {
            anonymized     => $anonymized,
            erasure_job_id => $input->{erasure_job_id},
        },
    };
}

sub _erased ( $input, $action, $anonymized ) {
    return {
        action         => $action,
        anonymized     => $anonymized,
        erasure_job_id => $input->{erasure_job_id},
        ok             => 1,
    };
}

# A request already held whose job already carries the hold's error is a
# replay. Otherwise both are marked; the action and the event are recorded
# only by the attempt that found neither marked.
async sub _block_erasure_p ( $self, $db, $input, $context ) {
    my $held    = $self->already_held( $input->{request} );
    my $blocked = $self->_job_blocked( $input->{job} );
    return $self->completion->hold_block_replay( $input->{erasure_job_id} )
      if $held && $blocked;

    await $self->set_request_status_p( $db, $input->{request}, $STATUS_HELD,
        $context );
    if ( !$blocked ) {
        await $self->update_privacy_row_p( $db, 'ErasureJob', $input->{job},
            { last_error => $self->events->block_error }, $context );
    }
    return $self->_blocked_result($input) if $held || $blocked;

    my $action = await $self->record_action_p(
        $db,
        $self->request_id_of($input),
        $self->_blocked_action($input), $context
    );
    await $self->record_privacy_event_and_audit_p( $db,
        $self->events->blocked( { %{$input}, action => $action } ), $context );

    return $self->_blocked_result( $input, $action );
}

sub _job_blocked ( $self, $job ) {
    return ( $self->record->column( $job, 'last_error' ) || q{} ) eq
      $self->events->block_error;
}

sub _blocked_result ( $self, $input, $action = undef ) {
    return {
        action         => $action,
        erasure_job_id => $input->{erasure_job_id},
        error          => 'retention_hold_active',
        ok             => 0,
    };
}

# A job a hold stopped keeps the hold's last_error until it runs: done, it
# is no longer blocked, and the review read it as still held. The member's
# export bundles are copies of what the erasure removes, so they go too.
async sub _finish_erasure_p ( $self, $db, $input, $context ) {
    my $anonymized =
      await $self->_anonymize_request_subject_p( $db, $input->{request},
        $input->{timestamp}, $context );
    $input->{discarded_exports} =
      defined $anonymized->{user_id}
      ? await $self->erased_exports->discard_p( $anonymized->{user_id},
        $context, $db )
      : [];
    await $self->update_privacy_row_p( $db, 'ErasureJob', $input->{job},
        _done_job($input), $context );
    await $self->complete_request_row_p( $db, $input->{request},
        $input->{timestamp}, $context );

    my $action = await $self->record_action_p(
        $db,
        $self->request_id_of($input),
        _anonymized_action( $input, $anonymized ), $context
    );
    await $self->record_privacy_event_and_audit_p(
        $db,
        $self->events->completed(
            { %{$input}, action => $action, anonymized => $anonymized }
        ),
        $context
    );

    return _erased( $input, $action, $anonymized );
}

# A user resource is erased, its credentials and sessions revoked, unless
# the erasure policy names a reason to skip it.
#
# The credentials go first, in the order a login takes its locks: it holds
# the credential it verified FOR SHARE while it inserts its session, whose
# foreign key then share-locks the account row. The erasure anonymized the
# account first -- a new username, so a FOR UPDATE lock on the row -- and
# then waited for the credential, the login waited for the account row, and
# PostgreSQL broke the deadlock by aborting one of them, mostly the erasure,
# while the login kept its session. Revoking the credentials first waits for
# that login to commit, and its session is revoked with the others.
#
# A source that cannot be revoked fails the erasure, which rolls back and
# runs again: the account is never anonymized behind sessions still signed
# in (t/integration/postgres-privacy-rollback.t). Each credential and
# session is revoked at the erasure's time, or at its own creation when
# that is later (GREATEST in api.privacy_revoke_user): the session of a
# login the erasure waited for was stamped after the erasure read its
# clock, and a revocation before the creation is refused by the
# revoked_after_created checks.
async sub _anonymize_request_subject_p ( $self, $db, $request, $timestamp,
    $context )
{
    my $user_id = $self->record->column( $request, 'resource_id' );
    my $user =
      $self->erasure->is_user_resource($request)
      ? await $self->find_privacy_row_p( $db, 'User', $user_id, 0, $context )
      : undef;
    my $skip = $self->erasure->skip_reason( $request, $user );
    return $self->completion->skipped($skip) if $skip;

    my $revoke = async sub (@sources) {
        for my $source (@sources) {
            await $db->row_p( 'privacy_revoke_user',
                _revoke_values( $source, $user_id, $timestamp ), $context );
        }
        return;
    };
    await $revoke->( 'Credential', @TOKEN_SOURCES );
    my $already = $self->erasure->already_deleted($user);
    if ( !$already ) {
        await $self->update_privacy_row_p( $db, 'User', $user,
            $self->erasure->user_values( $user_id, $timestamp ), $context );
    }
    await $revoke->( 'Session', @BEFORE_AVATAR_SOURCES );
    if ( my $avatars = $self->avatars ) {
        await $avatars->erase_files_p( $user_id, $context, $db );
    }
    await $revoke->(@AVATAR_AND_LATER_SOURCES);

    return $self->erasure->result( $user_id, $already );
}

# What api.privacy_revoke_user revokes: each source is a fixed branch of it.
sub _revoke_values ( $source, $user_id, $timestamp ) {
    return {
        source  => $source,
        user_id => $user_id,
        at      => $timestamp
    };
}

1;

__END__

=head1 NAME

GPForum::Service::Privacy::Deletion::Erasure - Completing an erasure job.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    # Part of GPForum::Service::Privacy::DeletionWorkflow; callers use that class.

=head1 DESCRIPTION

Complete the job: refuse it while a hold stands, anonymise the request's subject, revoke what the member held and close the request, written once, as its promise method (ADR 0177).

GPForum::Service::Privacy::DeletionWorkflow inherits it, so the object a caller builds has every method; this
file holds one part of that class so each part can be read by itself.

=head1 SUBROUTINES/METHODS

=head2 complete_job_p

Takes an erasure job id, the acting user's id and an optional query
context. The whole erasure runs in one transaction, the stored objects of
the member's profile pictures deleted in it through
L<GPForum::Service::Community::Avatars/erase_files_p>. Returns undef when there
is no such job, or when a job not yet done has no request. Otherwise:

=over 4

=item *

when the job is already C<done>, marks its request C<completed> if it is
not yet and returns C<< { ok => 1, idempotent => 1, erasure_job_id } >>;

=item *

under an active retention hold, sets the request C<held> and the job's
C<last_error> to C<retention hold active>, and returns
C<< { ok => 0, error => 'retention_hold_active', erasure_job_id, action } >>.
The C<held> deletion action and C<privacy.erasure_blocked> are recorded only
when the request was not yet held and the job not yet blocked; otherwise
C<action> is undef. When both were already so, it writes nothing and
returns
C<< { ok => 0, error => 'retention_hold_active', idempotent => 1, erasure_job_id } >>;

=item *

otherwise, when the resource is a C<user> that exists, anonymizes the member,
revokes their credentials and sessions, and discards their export bundles
through L<GPForum::Service::Privacy::ErasedExports> (the audit entry's
C<discarded_exports> names the requests deleted); in every case it marks the
job C<done>, clears its C<last_error> and marks the request C<completed>,
records an C<anonymized> deletion action and C<privacy.erasure_completed>,
and returns
C<< { ok => 1, erasure_job_id, action, anonymized } >>. C<anonymized> is
C<< { user_id, idempotent } >> (C<idempotent> 1 when the member was already
anonymized), or C<< { skipped => 'resource_not_user' } >> or
C<< { skipped => 'user_not_found' } >>.

=back

=head2 complete_job

The blocking twin of L</complete_job_p> (ADR 0177): the promise method run
on the blocking layer, the process's own connection and the transaction it
holds.

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
