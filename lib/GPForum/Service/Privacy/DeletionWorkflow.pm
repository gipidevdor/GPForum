# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Privacy::DeletionWorkflow;

use Const::Fast;
use GPForum::Infrastructure::EventRecorder;
use GPForum::Infrastructure::Storage;
use GPForum::Infrastructure::UniqueConflict;
use GPForum::Service::Clock;
use GPForum::Service::Identity::Support;
use GPForum::Service::Privacy::Completion;
use GPForum::Service::Privacy::ErasedExports;
use GPForum::Service::Privacy::Erasure;
use GPForum::Service::Privacy::Event;
use GPForum::Service::Privacy::Record;
use GPForum::X::Argument;
use GPForum::X::Conflict;
use Mojo::Base 'GPForum::Base', -signatures, -async_await;
use v5.40;

use GPForum::Infrastructure::SqlFunction;

has functions => \&GPForum::Infrastructure::SqlFunction::for_service;

our $VERSION = '0.001';

const my $STATUS_PENDING         => 'pending';
const my $STATUS_APPROVED        => 'approved';
const my $STATUS_COMPLETED       => 'completed';
const my $STATUS_HELD            => 'held';
const my $JOB_PENDING            => 'pending';
const my $JOB_DONE               => 'done';
const my $LEGAL_HOLD             => 'legal hold';
const my $DELETION_ID_CONSTRAINT => 'deletion_requests_pkey';
const my $OPEN_DELETION_CONSTRAINT =>
  'idx_deletion_requests_open_resource_unique';
const my $ERASURE_ID_CONSTRAINT      => 'erasure_jobs_pkey';
const my $ERASURE_REQUEST_CONSTRAINT => 'idx_erasure_jobs_request_unique';
const my $ACTION_ID_CONSTRAINT       => 'deletion_actions_pkey';

# What an erasure revokes beyond the credentials, the account and its
# sessions, in the order it revokes them (the function layer only).
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

has clock      => sub { return GPForum::Service::Clock->new; };
has id_service => sub {
    require GPForum::Infrastructure::Id;
    return GPForum::Infrastructure::Id->new;
};
has recorder => sub {
    my ($self) = @_;

    return GPForum::Infrastructure::EventRecorder->new(
        id_service => $self->id_service,
        schema     => $self->schema,
        functions  => $self->functions,
    );
};
__PACKAGE__->requires(qw(schema));

# ADR 0144: the profile pictures (Service::Community::Avatars), whose stored
# files erasure deletes before the rows.
has avatars    => undef;    # optional: without it only the rows go
has record     => sub { return GPForum::Service::Privacy::Record->new; };
has completion => sub {
    my ($self) = @_;

    return GPForum::Service::Privacy::Completion->new( record => $self->record,
    );
};
has erasure => sub {
    my ($self) = @_;

    return GPForum::Service::Privacy::Erasure->new( record => $self->record );
};
has events => sub {
    my ($self) = @_;

    return GPForum::Service::Privacy::Event->new( record => $self->record );
};
has erased_exports => sub {
    my ($self) = @_;

    return GPForum::Service::Privacy::ErasedExports->new(
        record    => $self->record,
        schema    => $self->schema,
        functions => $self->functions,
    );
};

# Under a lock on the resource's open requests, an open request is reused;
# otherwise a new one is inserted. A concurrent insert of the same open
# request, or a minted id already stored, is answered by the request then
# found; a minted id with no such request is minted once more.
sub request_deletion ( $self, $input ) {
    return $self->schema->txn_do(
        sub {
            my $dbh = GPForum::Infrastructure::Storage->dbh_of( $self->schema );
            if ( $dbh && !$self->functions ) {
                $dbh->selectrow_array(
'SELECT deletion_request_id FROM deletion_requests WHERE resource_type = ? AND resource_id = ? AND request_type = ? AND status IN (?, ?, ?) FOR UPDATE',
                    undef,
                    $input->{resource_type},
                    $input->{resource_id},
                    $input->{request_type},
                    $STATUS_PENDING,
                    $STATUS_APPROVED,
                    $STATUS_HELD,
                );
            }
            my $existing = $self->_open_deletion_hash($input);
            if ($existing) {
                return $self->_finish_leftover_deletion($existing);
            }

            my $create = sub {
                my $request = $self->_new_request($input);
                $self->_insert_privacy_row( 'DeletionRequest', $request );
                $self->_record_privacy_event_and_audit(
                    $self->_requested($request) );

                return $request;
            };
            my ( $created, $error ) =
              GPForum::Infrastructure::UniqueConflict->attempt( $self->schema,
                $create );
            if ($created) {
                return $created;
            }

            my ( $id_taken, $reread ) =
              _lost_race( $error, $DELETION_ID_CONSTRAINT,
                $OPEN_DELETION_CONSTRAINT );
            if ($reread) {
                $existing = $self->_open_deletion_hash($input);
                if ($existing) {
                    return $self->_finish_leftover_deletion($existing);
                }
                if ($id_taken) {
                    return GPForum::Infrastructure::UniqueConflict->once_more(
                        $self->schema, $create );
                }
            }

            GPForum::Infrastructure::UniqueConflict->rethrow($error);
        }
    );
}

# Under a lock on the request, an approval whose job an earlier attempt
# already scheduled finishes that attempt; a request under an active hold is
# held instead; otherwise the request is approved and its erasure job
# scheduled.
sub approve_request ( $self, $request_id, $actor_id, $reason ) {
    return $self->schema->txn_do(
        sub {
            my $dbh = GPForum::Infrastructure::Storage->dbh_of( $self->schema );
            if ( $dbh && !$self->functions ) {
                $dbh->selectrow_array(
'SELECT deletion_request_id FROM deletion_requests WHERE deletion_request_id = ? FOR UPDATE',
                    undef, $request_id
                );
            }
            my $request =
              $self->_find_privacy_row( 'DeletionRequest', $request_id, 1 );
            if ( !$request ) {
                return undef;
            }

            my $input =
              $self->_approval( $request_id, $actor_id, $reason, $request );
            my $existing = $self->_existing_job_for($request_id);
            if ($existing) {
                return $self->_finish_leftover_approval( $input, $existing );
            }

            my $hold = $self->_active_hold_for_request($request);
            if ($hold) {
                return $self->_hold_request(
                    $self->_approval_hold( $input, $hold ) );
            }

            $self->_set_request_status( $request, $STATUS_APPROVED );
            my $inserted = $self->_insert_or_reuse_job($input);
            if ( $inserted->{reused} ) {
                return $self->_finish_leftover_approval( $input,
                    $inserted->{job} );
            }

            return $self->_emit_approval( $input, $inserted->{job} );
        }
    );
}

# A job done by an earlier attempt is replayed, its request completed if
# that attempt left it open. Otherwise an active hold on the request blocks
# the erasure, and without one the subject is erased.
#
# The deletion request is locked first, as an approval and a hold lock it,
# and the job and the holds are read after the lock: a hold placed while an
# erasure was under way, or a second run of the same job, waits for it, and
# then finds the request held or the job done. Both were read unlocked: a
# hold committed meanwhile was overrun, and two runs both erased.
sub complete_job ( $self, $erasure_job_id, $actor_id ) {
    return $self->schema->txn_do(
        sub {
            my $found =
              $self->_find_privacy_row( 'ErasureJob', $erasure_job_id );
            if ( !$found ) {
                return undef;
            }
            my $request = $self->_find_privacy_row( 'DeletionRequest',
                $self->record->column( $found, 'deletion_request_id' ), 1 );
            my $job = $self->_find_privacy_row( 'ErasureJob', $erasure_job_id );
            if ( $self->completion->job_done($job) ) {
                if ($request) {
                    $self->_complete_request_row( $request,
                        $self->_job_completed_at($job) );
                }
                return $self->completion->completion_replay($erasure_job_id);
            }
            if ( !$request ) {
                return undef;
            }

            my $input =
              $self->_erasure( $erasure_job_id, $actor_id, $job, $request );
            my $hold = $self->_active_hold_for_request($request);
            if ($hold) {
                $input->{hold} = $hold;
                return $self->_block_erasure($input);
            }

            return $self->_finish_erasure($input);
        }
    );
}

# Holds a request under its lock. The hold itself is made by $make_hold,
# given the locked request, in the same transaction: a request completed or
# rejected is closed, and refused before any hold is made, where a hold on
# it -- a stale review page, or a hold that raced the erasure -- put an
# erased member's request back to held.
sub hold_request ( $self, $request_id, $actor_id, $reason, $make_hold ) {
    return $self->schema->txn_do(
        sub {
            my $request =
              $self->_find_privacy_row( 'DeletionRequest', $request_id, 1 );
            if ( !$request ) {
                return undef;
            }
            if ( !$self->_open_request($request) ) {
                return _closed($request_id);
            }

            my $held = $self->_hold_request(
                $self->_held_input(
                    $actor_id, $reason, $request, $make_hold->($request)
                )
            );

            return { %{$held}, error => undef, ok => 1 };
        }
    );
}

# Ends a hold, and gives the request it held back to where the hold found
# it: approved when its erasure job waits, pending otherwise. Nothing ended
# a hold, so a held request could never be approved or erased. The held
# request is locked before the hold ends (api.privacy_release_hold), the
# order holding a request takes them in. Answers undef for a hold that is
# not, or no longer, in force.
sub release_hold ( $self, $hold_id, $actor_id, $reason ) {
    if ( !$self->functions ) {
        GPForum::X::Argument->throw(
            message => 'releasing a hold needs the SQL function layer' );
    }

    return $self->schema->txn_do(
        sub {
            my $timestamp = $self->clock->now_iso8601;
            my $released  = $self->functions->row( 'privacy_release_hold',
                _release_values( $hold_id, $timestamp ) );
            return undef if !$released;

            my $request = $released->{request};
            return _released_alone($released) if !$request;

            my $input = _release(
                {
                    actor_id => $actor_id,
                    hold_id  => $hold_id,
                    job      => $self->_existing_job_for(
                        $request->{deletion_request_id}
                    ),
                    reason    => $reason,
                    released  => $released,
                    timestamp => $timestamp,
                }
            );
            $self->_set_request_status( $request, $input->{status} );
            my $action = $self->_record_action( $input->{request_id},
                _hold_ended_action($input) );
            $self->_record_privacy_event_and_audit(
                $self->events->hold_ended($input) );

            return _released_answer( $input, $action );
        }
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

# Whether an insert lost its minted id, and whether a reread may find the
# row that won the other constraint or the id.
sub _lost_race ( $error, $id_constraint, $other_constraint = undef ) {
    my $conflict = GPForum::X::Conflict->caught($error);
    my $id_taken = $conflict && $conflict->on($id_constraint) ? 1 : 0;
    my $other =
         $conflict
      && defined $other_constraint
      && $conflict->on($other_constraint) ? 1 : 0;

    return ( $id_taken, $id_taken || $other );
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

sub _closed ($request_id) {
    return {
        error      => 'deletion request is closed',
        ok         => 0,
        request_id => $request_id,
    };
}

sub _held_input ( $self, $actor_id, $reason, $request, $hold ) {
    return {
        actor_id  => $actor_id,
        hold      => $hold,
        reason    => $reason || $LEGAL_HOLD,
        request   => $request,
        timestamp => $self->clock->now_iso8601,
    };
}

sub _held_action ( $self, $input ) {
    return {
        action_type => 'held',
        actor_id    => $input->{actor_id},
        created_at  => $input->{timestamp},
        metadata    => {
            reason            => $input->{reason},
            retention_hold_id =>
              $self->record->column( $input->{hold}, 'retention_hold_id' ),
        },
    };
}

sub _held ( $request_id, $action ) {
    return {
        action     => $action,
        error      => 'retention_hold_active',
        ok         => 0,
        request_id => $request_id,
    };
}

sub _release_values ( $hold_id, $timestamp ) {
    return { hold_id => $hold_id, ended_at => $timestamp };
}

sub _released_alone ($released) {
    return { error => undef, hold => $released->{hold}, ok => 1 };
}

# The request a released hold held goes back to approved when its erasure
# job waits, to pending otherwise.
sub _release ($found) {
    my $released = $found->{released};
    return {
        actor_id   => $found->{actor_id},
        hold       => $released->{hold},
        hold_id    => $found->{hold_id},
        reason     => $found->{reason},
        request    => $released->{request},
        request_id => $released->{request}{deletion_request_id},
        status     => $found->{job} ? $STATUS_APPROVED : $STATUS_PENDING,
        timestamp  => $found->{timestamp},
    };
}

sub _hold_ended_action ($input) {
    return {
        action_type => 'hold_ended',
        actor_id    => $input->{actor_id},
        created_at  => $input->{timestamp},
        metadata    => {
            reason            => $input->{reason},
            retention_hold_id => $input->{hold_id},
            status            => $input->{status},
        },
    };
}

sub _released_answer ( $input, $action ) {
    return {
        action     => $action,
        error      => undef,
        hold       => $input->{hold},
        ok         => 1,
        request_id => $input->{request_id},
        status     => $input->{status},
    };
}

# An earlier attempt may have committed the request without its event.
sub _finish_leftover_deletion ( $self, $existing ) {
    if ( !$self->recorder->event_recorded( _requested_key($existing) ) ) {
        $self->_record_privacy_event_and_audit( $self->_requested($existing) );
    }

    return $existing;
}

sub _finish_leftover_approval ( $self, $input, $job ) {
    my $released = $self->_latest_row( _released_query($input) );
    if ($released) {
        return $self->completion->approval_replay( $input->{request_id}, $job );
    }

    $self->_set_request_status( $input->{request}, $STATUS_APPROVED );
    return $self->_emit_approval( $input, $job );
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

sub _emit_approval ( $self, $input, $job ) {
    my $action =
      $self->_record_action( $input->{request_id}, _approval_action($input) );
    $self->_record_privacy_event_and_audit(
        $self->events->approved(
            { %{$input}, action => $action, job => $job }
        )
    );

    return $self->_approved( $input, $action, $job );
}

# A concurrent approval's job, or a minted id already stored, is answered by
# the request's job then found; a minted id with no such job is minted once
# more.
sub _insert_or_reuse_job ( $self, $input ) {
    my $create = sub {
        my $job = $self->_new_job($input);
        $self->_insert_privacy_row( 'ErasureJob', $job );

        return $job;
    };
    my ( $created, $error ) =
      GPForum::Infrastructure::UniqueConflict->attempt( $self->schema,
        $create );
    if ($created) {
        return { job => $created, reused => 0 };
    }

    my ( $id_taken, $reread ) =
      _lost_race( $error, $ERASURE_ID_CONSTRAINT, $ERASURE_REQUEST_CONSTRAINT );
    if ($reread) {
        my $existing = $self->_existing_job_for( $input->{request_id} );
        if ($existing) {
            return { job => $existing, reused => 1 };
        }
        if ($id_taken) {
            return {
                job => GPForum::Infrastructure::UniqueConflict->once_more(
                    $self->schema, $create
                ),
                reused => 0
            };
        }
    }

    GPForum::Infrastructure::UniqueConflict->rethrow($error);
}

# A request already held whose job already carries the hold's error is a
# replay. Otherwise both are marked; the action and the event are recorded
# only by the attempt that found neither marked.
sub _block_erasure ( $self, $input ) {
    my $held    = $self->_already_held( $input->{request} );
    my $blocked = $self->_job_blocked( $input->{job} );
    if ( $held && $blocked ) {
        return $self->completion->hold_block_replay( $input->{erasure_job_id} );
    }

    $self->_set_request_status( $input->{request}, $STATUS_HELD );
    if ( !$blocked ) {
        $self->_update_privacy_row( 'ErasureJob', $input->{job},
            { last_error => $self->events->block_error } );
    }
    if ( $held || $blocked ) {
        return $self->_blocked_result($input);
    }

    my $action = $self->_record_action( $self->_request_id_of($input),
        $self->_blocked_action($input) );
    $self->_record_privacy_event_and_audit(
        $self->events->blocked( { %{$input}, action => $action } ) );

    return $self->_blocked_result( $input, $action );
}

sub _job_blocked ( $self, $job ) {
    return ( $self->record->column( $job, 'last_error' ) || q{} ) eq
      $self->events->block_error;
}

sub _request_id_of ( $self, $input ) {
    return $self->record->column( $input->{request}, 'deletion_request_id' );
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
sub _finish_erasure ( $self, $input ) {
    my $anonymized =
      $self->_anonymize_request_subject( $input->{request},
        $input->{timestamp} );
    $input->{discarded_exports} =
      defined $anonymized->{user_id}
      ? $self->erased_exports->discard( $anonymized->{user_id} )
      : [];
    $self->_update_privacy_row( 'ErasureJob', $input->{job},
        _done_job($input) );
    $self->_complete_request_row( $input->{request}, $input->{timestamp} );

    my $action = $self->_record_action( $self->_request_id_of($input),
        _anonymized_action( $input, $anonymized ) );
    $self->_record_privacy_event_and_audit(
        $self->events->completed(
            { %{$input}, action => $action, anonymized => $anonymized }
        )
    );

    return _erased( $input, $action, $anonymized );
}

sub _open_deletion_hash ( $self, $input ) {
    my $row = $self->_latest_row( _open_deletion_query($input) );
    if ( !$row ) {
        return undef;
    }

    return $self->record->request_hash($row);
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

sub _new_action ( $self, $request_id, $input ) {
    return {
        action_type         => $input->{action_type},
        actor_id            => $input->{actor_id},
        created_at          => $input->{created_at},
        deletion_action_id  => $self->id_service->uuid,
        deletion_request_id => $request_id,
        metadata            => $input->{metadata} || {},
    };
}

# A minted action id already stored is minted once more.
sub _record_action ( $self, $request_id, $input ) {
    my $create = sub {
        my $action = $self->_new_action( $request_id, $input );
        $self->_insert_privacy_row( 'DeletionAction', $action );

        return $action;
    };
    my ( $created, $error ) =
      GPForum::Infrastructure::UniqueConflict->attempt( $self->schema,
        $create );
    if ($created) {
        return $created;
    }

    my ($id_taken) = _lost_race( $error, $ACTION_ID_CONSTRAINT );
    if ($id_taken) {
        return GPForum::Infrastructure::UniqueConflict->once_more(
            $self->schema, $create );
    }

    GPForum::Infrastructure::UniqueConflict->rethrow($error);
}

# A request already held only reports the hold; otherwise it is held, and
# the action and the event are recorded.
sub _hold_request ( $self, $input ) {
    my $request    = $input->{request};
    my $request_id = $self->_request_id_of($input);
    my $action;
    if ( !$self->_already_held($request) ) {
        $self->_set_request_status( $request, $STATUS_HELD );
        $action =
          $self->_record_action( $request_id, $self->_held_action($input) );
        $self->_record_privacy_event_and_audit( $self->events->held($input) );
    }

    return _held( $request_id, $action );
}

sub _already_held ( $self, $request ) {
    return $self->_same_request_status( $request, $STATUS_HELD );
}

# Pending, approved or held: a request a hold can still act on.
sub _open_request ( $self, $request ) {
    my $status = $self->record->column( $request, 'status' ) || q{};

    return
         $status eq $STATUS_PENDING
      || $status eq $STATUS_APPROVED
      || $status eq $STATUS_HELD ? 1 : 0;
}

sub _same_request_status ( $self, $request, $status ) {
    my $held = $self->record->column( $request, 'status' ) || q{};
    if ( $held eq $status ) {
        return 1;
    }

    return 0;
}

sub _set_request_status ( $self, $request, $status ) {
    if ( $self->_same_request_status( $request, $status ) ) {
        return;
    }

    $self->_update_privacy_row( 'DeletionRequest', $request,
        { status => $status } );

    return;
}

sub _complete_request_row ( $self, $request, $timestamp ) {
    if ( $self->_same_request_status( $request, $STATUS_COMPLETED ) ) {
        return;
    }

    $self->_update_privacy_row(
        'DeletionRequest',
        $request,
        {
            completed_at => $timestamp,
            status       => $STATUS_COMPLETED,
        }
    );

    return;
}

sub _existing_job_for ( $self, $request_id ) {
    return $self->_latest_row( _job_query($request_id) );
}

sub _job_query ($request_id) {
    return ( 'ErasureJob', { deletion_request_id => $request_id },
        'scheduled_at' );
}

sub _active_hold_for_request ( $self, $request ) {
    return $self->_latest_row( $self->_active_hold_query($request) );
}

sub _active_hold_query ( $self, $request ) {
    return (
        'RetentionHold',
        {
            ends_at       => undef,
            resource_id   => $self->record->column( $request, 'resource_id' ),
            resource_type => $self->record->column( $request, 'resource_type' ),
        },
        'created_at',
    );
}

sub _latest_row ( $self, $resultset_name, $query, $order_field ) {
    if ( $self->functions ) {
        my $row = $self->functions->row( 'privacy_latest',
            { source => $resultset_name, query => $query } );
        return $row ? $row->{document} : undef;
    }

    my $search = $self->schema->resultset($resultset_name)->search_rs(
        $query,
        {
            order_by => [ { -desc => $order_field } ],
            rows     => 1,
        }
    );
    if ( $search->can('single') ) {
        return $search->single;
    }

    my @rows = $self->record->rows($search);
    return $rows[0];
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
sub _anonymize_request_subject ( $self, $request, $timestamp ) {
    my $user_id = $self->record->column( $request, 'resource_id' );
    my $user =
        $self->erasure->is_user_resource($request)
      ? $self->_find_privacy_row( 'User', $user_id )
      : undef;
    my $skip = $self->erasure->skip_reason( $request, $user );
    if ($skip) {
        return $self->completion->skipped($skip);
    }

    $self->_revoke_user_rows( 'Credential', $user_id, $timestamp );
    if ( $self->functions ) {
        $self->_revoke_sources( $user_id, $timestamp, @TOKEN_SOURCES );
    }
    my $already = $self->erasure->already_deleted($user);
    if ( !$already ) {
        $self->_update_privacy_row( 'User', $user,
            $self->erasure->user_values( $user_id, $timestamp ) );
    }
    $self->_revoke_user_rows( 'Session', $user_id, $timestamp );
    if ( $self->functions ) {
        $self->_revoke_sources( $user_id, $timestamp, @BEFORE_AVATAR_SOURCES );
        if ( $self->avatars ) {
            $self->avatars->erase_files($user_id);
        }
        $self->_revoke_sources( $user_id, $timestamp,
            @AVATAR_AND_LATER_SOURCES );
    }

    return $self->erasure->result( $user_id, $already );
}

sub _revoke_sources ( $self, $user_id, $timestamp, @sources ) {
    for my $source (@sources) {
        $self->_revoke_user_rows( $source, $user_id, $timestamp );
    }

    return;
}

# A source that cannot be read fails the erasure, which rolls back and runs
# again. It was skipped: the account was anonymized and its credentials
# revoked while its sessions stayed signed in (t/339).
sub _revoke_user_rows ( $self, $resultset_name, $user_id, $timestamp ) {
    if ( $self->functions ) {
        $self->functions->row( 'privacy_revoke_user',
            _revoke_values( $resultset_name, $user_id, $timestamp ) );
        return undef;
    }

    my $search = $self->schema->resultset($resultset_name)->search_rs(
        {
            revoked_at => undef,
            user_id    => $user_id,
        }
    );
    for my $row ( $self->record->rows($search) ) {
        if ( $row && $row->can('update') ) {
            $row->update(
                {
                    revoked_at => _not_before_creation(
                        $timestamp, $self->record->column( $row, 'created_at' )
                    )
                }
            );
        }
    }

    return undef;
}

# The erasure's time, or the row's creation when that is later: the session
# of a login the erasure waited for was stamped after the erasure read its
# clock, or by a host whose clock is ahead, and a revocation before the
# creation is refused by the revoked_after_created checks, failing the
# erasure. Compared to the second, the creation wins a tie, since it may
# carry a fraction the erasure's time does not.
sub _not_before_creation ( $timestamp, $created_at ) {
    my $support = 'GPForum::Service::Identity::Support';
    my $created = $support->epoch_from_timestamp($created_at);
    my $revoked = $support->epoch_from_timestamp($timestamp);
    if ( defined $created && defined $revoked && $created >= $revoked ) {
        return $created_at;
    }

    return $timestamp;
}

# Each branch is a fixed function; memory doubles retain their existing rows.
sub _revoke_values ( $source, $user_id, $timestamp ) {
    return {
        source  => $source,
        user_id => $user_id,
        at      => $timestamp
    };
}

sub _find_privacy_row ( $self, $source, $id, $lock = 0 ) {
    if ( $self->functions ) {
        my $row = $self->functions->row( 'privacy_find',
            { source => $source, id => $id, lock_row => $lock } );
        return $row ? $row->{document} : undef;
    }
    return $self->schema->resultset($source)->find($id);
}

sub _insert_privacy_row ( $self, $source, $row ) {
    if ( $self->functions ) {
        return $self->functions->row( 'privacy_insert',
            { source => $source, row => $row } )->{document};
    }
    return $self->schema->resultset($source)->create($row);
}

sub _update_privacy_row ( $self, $source, $row, $changes ) {
    if ( $self->functions ) {
        $self->functions->row( 'privacy_update',
            _update_values( $source, $row, $changes ) );
        @{$row}{ keys %{$changes} } = values %{$changes};
        return $row;
    }
    return $row->update($changes);
}

sub _update_values ( $source, $row, $changes ) {
    my $id_column =
        $source eq 'User'       ? 'id'
      : $source eq 'ErasureJob' ? 'erasure_job_id'
      :                           'deletion_request_id';
    return {
        source  => $source,
        id      => $row->{$id_column},
        changes => $changes
    };
}

sub _record_privacy_event_and_audit ( $self, $input ) {
    my $correlation_id = $self->id_service->uuid;
    $self->recorder->record_event(
        %{ $self->events->envelope( $input, $correlation_id ) } );
    $self->recorder->record_audit(
        %{ $self->events->audit( $input, $correlation_id ) } );

    return;
}

# The promise twins. Each public step runs in one transaction on the
# worker's pooled asynchronous connections -- the same steps, in the same
# order, as its blocking twin, every statement on the transaction's call
# layer ($db) -- and inserts in its savepoints. Without the function layer
# (the in-memory doubles) the blocking step answers.

async sub request_deletion_p ( $self, $input, $context = undef ) {
    return $self->request_deletion($input) if !$self->functions;

    return await $self->functions->transaction_p(
        async sub ($db) {
            my $existing =
              await $self->_open_deletion_hash_p( $db, $input, $context );
            return await $self->_finish_leftover_deletion_p( $db, $existing,
                $context )
              if $existing;

            my $create = async sub ($savepoint) {
                my $request = $self->_new_request($input);
                await _insert_p( $savepoint, 'DeletionRequest', $request,
                    $context );
                await $self->_record_privacy_event_and_audit_p( $savepoint,
                    $self->_requested($request), $context );

                return $request;
            };
            my ( $created, $error ) =
              await GPForum::Infrastructure::UniqueConflict->attempt_p( $db,
                $create );
            return $created if $created;

            my ( $id_taken, $reread ) =
              _lost_race( $error, $DELETION_ID_CONSTRAINT,
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

async sub approve_request_p ( $self, $request_id, $actor_id, $reason,
    $context = undef )
{
    return $self->approve_request( $request_id, $actor_id, $reason )
      if !$self->functions;

    return await $self->functions->transaction_p(
        async sub ($db) {
            my $request =
              await _find_p( $db, 'DeletionRequest', $request_id, 1, $context );
            return undef if !$request;

            my $input =
              $self->_approval( $request_id, $actor_id, $reason, $request );
            my $existing =
              await _latest_p( $db, $context, _job_query($request_id) );
            return await $self->_finish_leftover_approval_p( $db, $input,
                $existing, $context )
              if $existing;

            my $hold = await _latest_p( $db, $context,
                $self->_active_hold_query($request) );
            return await $self->_hold_request_p( $db,
                $self->_approval_hold( $input, $hold ), $context )
              if $hold;

            await $self->_set_request_status_p( $db, $request,
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

async sub complete_job_p ( $self, $erasure_job_id, $actor_id, $context = undef )
{
    return $self->complete_job( $erasure_job_id, $actor_id )
      if !$self->functions;

    return await $self->functions->transaction_p(
        async sub ($db) {
            my $found =
              await _find_p( $db, 'ErasureJob', $erasure_job_id, 0, $context );
            return undef if !$found;

            my $request =
              await _find_p( $db, 'DeletionRequest',
                $self->record->column( $found, 'deletion_request_id' ),
                1, $context );
            my $job =
              await _find_p( $db, 'ErasureJob', $erasure_job_id, 0, $context );
            if ( $self->completion->job_done($job) ) {
                if ($request) {
                    await $self->_complete_request_row_p( $db, $request,
                        $self->_job_completed_at($job), $context );
                }
                return $self->completion->completion_replay($erasure_job_id);
            }
            return undef if !$request;

            my $input =
              $self->_erasure( $erasure_job_id, $actor_id, $job, $request );
            my $hold = await _latest_p( $db, $context,
                $self->_active_hold_query($request) );
            if ($hold) {
                $input->{hold} = $hold;
                return await $self->_block_erasure_p( $db, $input, $context );
            }

            return await $self->_finish_erasure_p( $db, $input, $context );
        },
        $context
    );
}

# hold_request as a promise: $make_hold_p takes the locked request and the
# transaction's call layer and answers a promise of the hold.
async sub hold_request_p ( $self, $request_id, $actor_id, $reason,
    $make_hold_p, $context = undef )
{
    return await $self->functions->transaction_p(
        async sub ($db) {
            my $request =
              await _find_p( $db, 'DeletionRequest', $request_id, 1, $context );
            return undef                if !$request;
            return _closed($request_id) if !$self->_open_request($request);

            my $hold = await $make_hold_p->( $request, $db );
            my $held =
              await $self->_hold_request_p( $db,
                $self->_held_input( $actor_id, $reason, $request, $hold ),
                $context );

            return { %{$held}, error => undef, ok => 1 };
        },
        $context
    );
}

async sub release_hold_p ( $self, $hold_id, $actor_id, $reason,
    $context = undef )
{
    return $self->release_hold( $hold_id, $actor_id, $reason )
      if !$self->functions;

    return await $self->functions->transaction_p(
        async sub ($db) {
            my $timestamp = $self->clock->now_iso8601;
            my $released  = await $db->row_p( 'privacy_release_hold',
                _release_values( $hold_id, $timestamp ), $context );
            return undef                      if !$released;
            return _released_alone($released) if !$released->{request};

            my $input = _release(
                {
                    actor_id => $actor_id,
                    hold_id  => $hold_id,
                    job      => await _latest_p(
                        $db,
                        $context,
                        _job_query( $released->{request}{deletion_request_id} )
                    ),
                    reason    => $reason,
                    released  => $released,
                    timestamp => $timestamp,
                }
            );
            await $self->_set_request_status_p( $db, $input->{request},
                $input->{status}, $context );
            my $action =
              await $self->_record_action_p( $db, $input->{request_id},
                _hold_ended_action($input), $context );
            await $self->_record_privacy_event_and_audit_p( $db,
                $self->events->hold_ended($input), $context );

            return _released_answer( $input, $action );
        },
        $context
    );
}

async sub _finish_leftover_deletion_p ( $self, $db, $existing, $context ) {
    my $recorded = await $db->row_p( 'ops_event_recorded',
        { key => _requested_key($existing) }, $context );
    if ( !$recorded->{recorded} ) {
        await $self->_record_privacy_event_and_audit_p( $db,
            $self->_requested($existing), $context );
    }

    return $existing;
}

async sub _open_deletion_hash_p ( $self, $db, $input, $context ) {
    my $row = await _latest_p( $db, $context, _open_deletion_query($input) );
    return $row ? $self->record->request_hash($row) : undef;
}

async sub _finish_leftover_approval_p ( $self, $db, $input, $job, $context ) {
    my $released = await _latest_p( $db, $context, _released_query($input) );
    return $self->completion->approval_replay( $input->{request_id}, $job )
      if $released;

    await $self->_set_request_status_p( $db, $input->{request},
        $STATUS_APPROVED, $context );
    return await $self->_emit_approval_p( $db, $input, $job, $context );
}

async sub _emit_approval_p ( $self, $db, $input, $job, $context ) {
    my $action = await $self->_record_action_p( $db, $input->{request_id},
        _approval_action($input), $context );
    await $self->_record_privacy_event_and_audit_p(
        $db,
        $self->events->approved(
            { %{$input}, action => $action, job => $job }
        ),
        $context
    );

    return $self->_approved( $input, $action, $job );
}

async sub _insert_or_reuse_job_p ( $self, $db, $input, $context ) {
    my $create = async sub ($savepoint) {
        my $job = $self->_new_job($input);
        await _insert_p( $savepoint, 'ErasureJob', $job, $context );

        return $job;
    };
    my ( $created, $error ) =
      await GPForum::Infrastructure::UniqueConflict->attempt_p( $db, $create );
    return { job => $created, reused => 0 } if $created;

    my ( $id_taken, $reread ) =
      _lost_race( $error, $ERASURE_ID_CONSTRAINT, $ERASURE_REQUEST_CONSTRAINT );
    if ($reread) {
        my $existing =
          await _latest_p( $db, $context, _job_query( $input->{request_id} ) );
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

async sub _block_erasure_p ( $self, $db, $input, $context ) {
    my $held    = $self->_already_held( $input->{request} );
    my $blocked = $self->_job_blocked( $input->{job} );
    return $self->completion->hold_block_replay( $input->{erasure_job_id} )
      if $held && $blocked;

    await $self->_set_request_status_p( $db, $input->{request}, $STATUS_HELD,
        $context );
    if ( !$blocked ) {
        await _update_p( $db, 'ErasureJob', $input->{job},
            { last_error => $self->events->block_error }, $context );
    }
    return $self->_blocked_result($input) if $held || $blocked;

    my $action = await $self->_record_action_p(
        $db,
        $self->_request_id_of($input),
        $self->_blocked_action($input), $context
    );
    await $self->_record_privacy_event_and_audit_p( $db,
        $self->events->blocked( { %{$input}, action => $action } ), $context );

    return $self->_blocked_result( $input, $action );
}

async sub _finish_erasure_p ( $self, $db, $input, $context ) {
    my $anonymized =
      await $self->_anonymize_request_subject_p( $db, $input->{request},
        $input->{timestamp}, $context );
    $input->{discarded_exports} =
      defined $anonymized->{user_id}
      ? await $self->erased_exports->discard_p( $anonymized->{user_id},
        $context, $db )
      : [];
    await _update_p( $db, 'ErasureJob', $input->{job}, _done_job($input),
        $context );
    await $self->_complete_request_row_p( $db, $input->{request},
        $input->{timestamp}, $context );

    my $action = await $self->_record_action_p(
        $db,
        $self->_request_id_of($input),
        _anonymized_action( $input, $anonymized ), $context
    );
    await $self->_record_privacy_event_and_audit_p(
        $db,
        $self->events->completed(
            { %{$input}, action => $action, anonymized => $anonymized }
        ),
        $context
    );

    return _erased( $input, $action, $anonymized );
}

# As _anonymize_request_subject, every statement on the transaction's call
# layer, the profile pictures' stored objects included.
async sub _anonymize_request_subject_p ( $self, $db, $request, $timestamp,
    $context )
{
    my $user_id = $self->record->column( $request, 'resource_id' );
    my $user =
      $self->erasure->is_user_resource($request)
      ? await _find_p( $db, 'User', $user_id, 0, $context )
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
        await _update_p( $db, 'User', $user,
            $self->erasure->user_values( $user_id, $timestamp ), $context );
    }
    await $revoke->( 'Session', @BEFORE_AVATAR_SOURCES );
    if ( my $avatars = $self->avatars ) {
        if ( $avatars->can('erase_files_p') ) {
            await $avatars->erase_files_p( $user_id, $context, $db );
        }
        else { $avatars->erase_files($user_id); }
    }
    await $revoke->(@AVATAR_AND_LATER_SOURCES);

    return $self->erasure->result( $user_id, $already );
}

async sub _record_action_p ( $self, $db, $request_id, $input, $context ) {
    my $create = async sub ($savepoint) {
        my $action = $self->_new_action( $request_id, $input );
        await _insert_p( $savepoint, 'DeletionAction', $action, $context );

        return $action;
    };
    my ( $created, $error ) =
      await GPForum::Infrastructure::UniqueConflict->attempt_p( $db, $create );
    return $created if $created;

    my ($id_taken) = _lost_race( $error, $ACTION_ID_CONSTRAINT );
    return await GPForum::Infrastructure::UniqueConflict->once_more_p( $db,
        $create )
      if $id_taken;

    GPForum::Infrastructure::UniqueConflict->rethrow($error);
}

async sub _hold_request_p ( $self, $db, $input, $context ) {
    my $request_id = $self->_request_id_of($input);
    my $action;
    if ( !$self->_already_held( $input->{request} ) ) {
        await $self->_set_request_status_p( $db, $input->{request},
            $STATUS_HELD, $context );
        $action = await $self->_record_action_p( $db, $request_id,
            $self->_held_action($input), $context );
        await $self->_record_privacy_event_and_audit_p( $db,
            $self->events->held($input), $context );
    }

    return _held( $request_id, $action );
}

async sub _set_request_status_p ( $self, $db, $request, $status, $context ) {
    return if $self->_same_request_status( $request, $status );

    await _update_p( $db, 'DeletionRequest', $request, { status => $status },
        $context );
    return;
}

async sub _complete_request_row_p ( $self, $db, $request, $timestamp, $context )
{
    return if $self->_same_request_status( $request, $STATUS_COMPLETED );

    await _update_p(
        $db,
        'DeletionRequest',
        $request,
        {
            completed_at => $timestamp,
            status       => $STATUS_COMPLETED,
        },
        $context
    );
    return;
}

async sub _latest_p ( $db, $context, $source, $query, $ ) {
    my $row = await $db->row_p( 'privacy_latest',
        { source => $source, query => $query }, $context );
    return $row ? $row->{document} : undef;
}

async sub _find_p ( $db, $source, $id, $lock, $context ) {
    my $row = await $db->row_p( 'privacy_find',
        { source => $source, id => $id, lock_row => $lock }, $context );
    return $row ? $row->{document} : undef;
}

async sub _insert_p ( $db, $source, $row, $context ) {
    return (
        await $db->row_p(
            'privacy_insert', { source => $source, row => $row }, $context
        )
    )->{document};
}

async sub _update_p ( $db, $source, $row, $changes, $context ) {
    await $db->row_p( 'privacy_update',
        _update_values( $source, $row, $changes ), $context );
    @{$row}{ keys %{$changes} } = values %{$changes};
    return $row;
}

# The event and the audit entry on the transaction's own call layer.
async sub _record_privacy_event_and_audit_p ( $self, $db, $input, $context ) {
    my $correlation_id = $self->id_service->uuid;
    my $recorder       = GPForum::Infrastructure::EventRecorder->new(
        id_service => $self->id_service,
        schema     => $self->schema,
        functions  => $db,
    );
    await $recorder->record_event_p(
        $self->events->envelope( $input, $correlation_id ), $context );
    await $recorder->record_audit_p(
        $self->events->audit( $input, $correlation_id ), $context );

    return;
}

1;

__END__

=head1 NAME

GPForum::Service::Privacy::DeletionWorkflow - Deletion requests, their approval, legal holds and the erasure job that anonymizes a member.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $deletion = GPForum::Service::Privacy::DeletionWorkflow->new(
        clock      => $clock,
        id_service => $id_service,
        schema     => $schema,
    );
    my $request = $deletion->request_deletion(
        {
            reason            => 'leaving the forum',
            request_type      => 'anonymize',
            requester_user_id => $user_id,
            resource_id       => $user_id,
            resource_type     => 'user',
        }
    );
    my $approved = $deletion->approve_request(
        $request->{deletion_request_id}, $admin_id, 'verified' );
    if ( $approved && $approved->{ok} ) {
        $deletion->complete_job( $approved->{job}{erasure_job_id}, $admin_id );
    }

=head1 DESCRIPTION

Owns the writes behind a member's deletion: it writes C<deletion_requests>,
C<erasure_jobs> and C<deletion_actions>, anonymizes the member when the job
runs, and records a privacy event and audit entry for each step, built by
L<GPForum::Service::Privacy::Event> and written by
L<GPForum::Infrastructure::EventRecorder>. L<GPForum::Service::Privacy::Workflow>
validates the commands and calls it. Each public method runs in one
transaction, and every step can be repeated: a step already taken is
answered from what is stored rather than done twice, and one found
half-recorded -- a request without its event, a job without its approval
action -- is finished.

A request is C<pending> until approved. A resource has at most one open
(C<pending>, C<approved> or C<held>) request of a type: asking again returns
that request, and concurrent requests are serialized by locking the open
rows and by the unique index C<idx_deletion_requests_open_resource_unique>.
Approving locks the request, then schedules one C<pending> erasure job for
it -- unless the resource is under an active retention hold (one with no
C<ends_at>), in which case the request is put on hold instead. Running the
job checks the hold again: under a hold it marks the request C<held> and the
job's C<last_error>, and erases nothing; otherwise it anonymizes the member
(when the resource is a C<user> that exists), revokes their credentials and
sessions, discards the export bundles that copy their data, and marks the
job C<done> and the request C<completed>. The credentials are revoked before
the account is anonymized, the order a login takes its locks in, so an
erasure waits for a login opening a session instead of deadlocking with it;
each credential and session is revoked at the erasure's time, or at its own
C<created_at> when that is later.

Inserts run inside savepoints. A lost race on a unique index reuses the row
the other writer inserted; a collision on a generated id is retried once
with a fresh id.

=head1 SUBROUTINES/METHODS

=head2 request_deletion

Takes a hash reference with C<requester_user_id>, C<request_type>,
C<resource_type>, C<resource_id> and an optional C<reason> (empty when
omitted). Creates a C<pending> request and records
C<privacy.deletion_requested>, or returns the open request already there.
Returns the request as a hash reference: C<deletion_request_id>,
C<request_type>, C<requester_user_id>, C<resource_type>, C<resource_id>,
C<reason>, C<status>, C<created_at> and C<completed_at>.

=head2 approve_request

Takes a request id, the approving actor's id and a reason. Returns undef
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

=head2 complete_job

Takes an erasure job id and the acting user's id. Returns undef when there
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

=head2 hold_request

Takes a request id, the acting user's id, a reason (default C<legal hold>)
and the retention hold row it is held under. Returns undef when there is no
such request. Otherwise sets the request C<held>, records a C<held>
deletion action naming the hold and C<privacy.deletion_held>, and returns
C<< { ok => 1, error => undef, request_id, action } >>; C<action> is undef
when the request was already held and nothing was written.

=head2 release_hold

Takes a retention hold id, the acting user's id and a reason. Returns undef
when no hold of that id is in force. Otherwise ends it and, when it held a
deletion request, gives the request back to C<approved> (its erasure job is
scheduled) or C<pending>, records a C<hold_ended> deletion action and
C<privacy.retention_hold_ended>, and returns
C<< { ok => 1, error => undef, hold, request_id, status, action } >>; for a
hold that held no request, C<< { ok => 1, error => undef, hold } >>. The held
request is locked before the hold ends, the order a hold takes them in.
Without the SQL function layer it throws L<GPForum::X::Argument>.

=head2 request_deletion_p

L</request_deletion> as a promise, with an optional query context last: the
same steps in one transaction on the worker's pooled asynchronous
connections, its inserts in savepoints of it, no child process. Without the
SQL function layer the blocking step answers, as for every promise twin
here.

=head2 approve_request_p

L</approve_request> as a promise, with an optional query context last, in
one transaction on the worker's pooled asynchronous connections.

=head2 complete_job_p

L</complete_job> as a promise, with an optional query context last: the
whole erasure in one transaction on the worker's pooled asynchronous
connections, the stored objects of the member's profile pictures deleted in
it through L<GPForum::Service::Community::Avatars/erase_files_p>.

=head2 hold_request_p

L</hold_request> as a promise, with an optional query context last. The hold
is made by a code reference that takes the locked request and the
transaction's call layer and answers a promise of the hold, so it is made in
the same transaction. Needs the SQL function layer.

=head2 release_hold_p

L</release_hold> as a promise, with an optional query context last, in one
transaction on the worker's pooled asynchronous connections.

=head1 DIAGNOSTICS

Croaks with the database error when an insert fails for any reason other
than a unique conflict it knows, when a conflict leaves no row to reuse,
and when the retry after an id collision fails too. Every public method
runs in C<txn_do>, so any failure, including one recording the event or
the audit entry, rolls the whole step back and propagates. A retention hold
is not a failure: it is reported as C<< ok => 0 >> with
C<< error => 'retention_hold_active' >>.

=head1 CONFIGURATION AND ENVIRONMENT

None. C<clock>, C<id_service>, C<recorder>, C<record>, C<completion>,
C<erasure>, C<erased_exports> and C<events> have defaults; the application
passes its clock and id service.

=head1 DEPENDENCIES

L<GPForum::Infrastructure::EventRecorder>, L<GPForum::Infrastructure::Id>,
L<GPForum::Infrastructure::Storage>,
L<GPForum::Infrastructure::UniqueConflict>, L<GPForum::X::Conflict>,
L<GPForum::Service::Clock>, L<GPForum::Service::Identity::Support> (to
compare timestamps), L<GPForum::Service::Privacy::Completion>,
L<GPForum::Service::Privacy::ErasedExports>,
L<GPForum::Service::Privacy::Erasure>, L<GPForum::Service::Privacy::Event>,
L<GPForum::Service::Privacy::Record>.

Extends L<GPForum::Base>: built without C<schema> it throws
L<GPForum::X::Argument>. C<avatars>, a L<GPForum::Service::Community::Avatars>, is
optional: given one, erasure deletes the stored files of the member's
profile pictures before their rows (ADR 0144).

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
