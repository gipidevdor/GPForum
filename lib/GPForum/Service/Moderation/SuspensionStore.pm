# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Moderation::SuspensionStore;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -async_await;
use v5.40;

use GPForum::Infrastructure::Row qw(column_of rows_in);
use GPForum::Infrastructure::ResultRow::IdentityUser;
use GPForum::Infrastructure::ResultRow;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Infrastructure::EventRecorder;
use GPForum::Infrastructure::UniqueConflict;
use GPForum::Service::Clock;
use GPForum::Service::Identity::Support;
use GPForum::Service::Moderation::Event;
use GPForum::X::Argument;
use GPForum::X::Conflict;
use GPForum::X::Unavailable;

our $VERSION = '0.001';

const my $ID_CONSTRAINT  => 'suspensions_pkey';
const my $ENDED          => 'user.suspension_ended';
const my $DEFAULT_QUEUE  => 100;
const my $MAXIMUM_QUEUE  => 1_000;
const my $STATUS_ACTIVE  => 'active';
const my $STATUS_DELETED => 'deleted';
const my $STATUS_SUSPEND => 'suspended';
const my %STATUS_DENIALS => (
    $STATUS_DELETED => 'user_deleted',
    $STATUS_SUSPEND => 'suspended',
);

has clock      => sub { return GPForum::Service::Clock->new; };
has id_service => sub {
    require GPForum::Infrastructure::Id;
    return GPForum::Infrastructure::Id->new;
};
has recorder => \&GPForum::Infrastructure::EventRecorder::for_service;
__PACKAGE__->requires(qw(schema));
has functions => \&GPForum::Infrastructure::SqlFunction::for_service;
has events    => sub { return GPForum::Service::Moderation::Event->new; };

sub create_suspension ( $self, $input ) {
    return $self->schema->txn_do(
        sub {
            return $self->_create_or_reuse($input);
        }
    );
}

# A member already under an active suspension keeps it. A minted id already
# stored is minted once more: under the member's lock nothing else can have
# suspended them meanwhile.
sub _create_or_reuse ( $self, $input ) {
    $self->_lock_member( $input->{user_id} );
    my $user = $self->_user( $input->{user_id} );
    if ( !$user || ( column_of( $user, 'status' ) // q{} ) eq $STATUS_DELETED )
    {
        return undef;
    }

    my $active = $self->active_for_user( $input->{user_id} );
    if ($active) {
        return { ok => 1, suspension => _suspension_hash($active) };
    }

    my $insert = sub { return $self->_insert_suspension( $input, $user ); };
    my ( $created, $error ) =
      GPForum::Infrastructure::UniqueConflict->attempt( $self->schema,
        $insert );
    if ($created) {
        return $created;
    }

    my $conflict = GPForum::X::Conflict->caught($error);
    if ( !$conflict || !$conflict->on($ID_CONSTRAINT) ) {
        GPForum::Infrastructure::UniqueConflict->rethrow($error);
    }

    ( $created, $error ) =
      GPForum::Infrastructure::UniqueConflict->attempt( $self->schema,
        $insert );
    if ($created) {
        return $created;
    }

    GPForum::Infrastructure::UniqueConflict->rethrow($error);
}

sub _insert_suspension ( $self, $input, $user ) {
    my $suspension = $self->_new_suspension( $input, $user );
    if ( $self->functions ) {
        $self->functions->row( 'moderation_suspension_insert',
            { values => $suspension } );
    }
    else {
        $self->schema->resultset('Suspension')->create($suspension);
    }

    my $status = _suspended_status($suspension);
    if ($status) { $user->update($status); }
    $self->_record_event_and_audit( _suspended_record( $input, $suspension ) );

    return { ok => 1, suspension => $suspension };
}

# The suspension a member gets, stamped now, with the status it found.
sub _new_suspension ( $self, $input, $user ) {
    return {
        suspension_id => $self->id_service->uuid,
        user_id       => $input->{user_id},
        actor_user_id => $input->{actor_user_id},
        reason        => $input->{reason},
        valid_from    => $self->clock->now_iso8601,
        valid_to      => $input->{valid_to},
        revoked_at    => undef,
        metadata      => {
            previous_status => column_of( $user, 'status' ),
            source          => $input->{source} || 'moderation',
        },
    };
}

# Only an active account becomes suspended: the suspension row bars any
# account from taking part, and a pending one -- its address not
# confirmed -- stays pending, so lifting the suspension cannot make it
# active without the confirmation. Undef when the status stays.
sub _suspended_status ($suspension) {
    return undef
      if ( $suspension->{metadata}{previous_status} // $STATUS_ACTIVE ) ne
      $STATUS_ACTIVE;
    return {
        status     => $STATUS_SUSPEND,
        updated_at => $suspension->{valid_from},
    };
}

sub _suspended_record ( $input, $suspension ) {
    my $timestamp = $suspension->{valid_from};
    return {
        action         => 'user.suspended',
        actor_id       => $input->{actor_user_id},
        correlation_id => $input->{correlation_id},
        created_at     => $timestamp,
        metadata       => {
            previous_status => $suspension->{metadata}{previous_status},
            reason          => $input->{reason},
            suspension_id   => $suspension->{suspension_id},
        },
        payload => {
            reason        => $input->{reason},
            suspension_id => $suspension->{suspension_id},
            valid_from    => $timestamp,
            valid_to      => $input->{valid_to},
        },
        user_id => $input->{user_id},
    };
}

sub revoke_suspension ( $self, $suspension_id, $actor_user_id, $reason ) {
    return $self->schema->txn_do(
        sub {
            return $self->_revoke_in_txn(
                {
                    actor_user_id => $actor_user_id,
                    reason        => $reason,
                    suspension_id => $suspension_id,
                }
            );
        }
    );
}

# A suspension already revoked is answered as it stands, its member restored
# if an earlier attempt left them suspended. It is read again under its
# member's lock, so a revocation that committed while this one waited is
# answered, not stamped and audited a second time.
sub _revoke_in_txn ( $self, $input ) {
    my $suspension = $self->_suspension( $input->{suspension_id} );
    if ( !$suspension ) {
        return undef;
    }
    my $user_id = column_of( $suspension, 'user_id' );
    $self->_lock_member($user_id);
    $suspension = $self->_suspension( $input->{suspension_id} );
    my $revoked_at = column_of( $suspension, 'revoked_at' );
    if ( defined $revoked_at ) {
        $self->_restore_user_if_needed( $user_id, $revoked_at );
        return {
            suspension_id => column_of( $suspension, 'suspension_id' ),
            revoked_at    => $revoked_at,
        };
    }

    my $timestamp = $self->clock->now_iso8601;
    my $changes   = { revoked_at => $timestamp };
    if ( $self->functions ) {
        $self->functions->row(
            'moderation_suspension_update',
            {
                suspension_id => $input->{suspension_id},
                revoked_at    => $timestamp
            }
        );
        %{$suspension} = ( %{$suspension}, %{$changes} );
    }
    else {
        $suspension->update($changes);
    }
    $self->_restore_user_if_needed( $user_id, $timestamp );
    $self->_record_event_and_audit(
        _revoked_record( $input, $user_id, $timestamp ) );

    return { suspension_id => $input->{suspension_id}, %{$changes} };
}

sub _revoked_record ( $input, $user_id, $timestamp ) {
    return {
        action         => 'user.suspension_revoked',
        actor_id       => $input->{actor_user_id},
        correlation_id => undef,
        created_at     => $timestamp,
        metadata       => {
            reason        => $input->{reason},
            suspension_id => $input->{suspension_id},
        },
        payload => {
            reason        => $input->{reason},
            suspension_id => $input->{suspension_id},
            revoked_at    => $timestamp,
        },
        user_id => $user_id,
    };
}

# create_suspension in one transaction on the worker's pooled asynchronous
# connections, not a forked child with a connection of its own: the
# member's lock, the active suspension it may already have, and the insert
# in a savepoint, minted once more when its id was taken.
async sub create_suspension_p ( $self, $input, $context = undef ) {
    return $self->create_suspension($input) if !$self->functions;
    return await $self->functions->transaction_p(
        async sub ($scope) {
            await $scope->row_p( 'moderation_lock_member',
                { user_id => $input->{user_id} } );
            my $user = await _user_p( $scope, $input->{user_id} );
            return undef
              if !$user
              || ( column_of( $user, 'status' ) // q{} ) eq $STATUS_DELETED;

            my $active = await $self->_active_p( $scope, $input->{user_id} );
            return { ok => 1, suspension => _suspension_hash($active) }
              if $active;

            my $insert = async sub ($savepoint) {
                return await $self->_insert_suspension_p( $savepoint, $input,
                    $user );
            };
            for my $attempt ( 0, 1 ) {
                my ( $created, $error ) =
                  await GPForum::Infrastructure::UniqueConflict->attempt_p(
                    $scope, $insert );
                return $created if $created;
                my $conflict = GPForum::X::Conflict->caught($error);
                if ( $attempt || !$conflict || !$conflict->on($ID_CONSTRAINT) )
                {
                    GPForum::Infrastructure::UniqueConflict->rethrow($error);
                }
            }
            return undef;
        },
        $context
    );
}

async sub _insert_suspension_p ( $self, $scope, $input, $user ) {
    my $suspension = $self->_new_suspension( $input, $user );
    await $scope->row_p( 'moderation_suspension_insert',
        { values => $suspension } );
    my $status = _suspended_status($suspension);
    if ($status) { await _update_user_p( $scope, $user, $status ); }
    await $self->_record_p( $scope, _suspended_record( $input, $suspension ) );

    return { ok => 1, suspension => $suspension };
}

# revoke_suspension in one transaction on the worker's pooled asynchronous
# connections, read again under the member's lock as the blocking path
# reads it.
async sub revoke_suspension_p ( $self, $suspension_id, $actor_user_id,
    $reason, $context = undef )
{
    return $self->revoke_suspension( $suspension_id, $actor_user_id, $reason )
      if !$self->functions;
    my $input = {
        actor_user_id => $actor_user_id,
        reason        => $reason,
        suspension_id => $suspension_id,
    };
    return await $self->functions->transaction_p(
        async sub ($scope) {
            my $suspension = await _suspension_p( $scope, $suspension_id );
            return undef if !$suspension;
            my $user_id = column_of( $suspension, 'user_id' );
            await $scope->row_p( 'moderation_lock_member',
                { user_id => $user_id } );
            $suspension = await _suspension_p( $scope, $suspension_id );
            my $revoked_at = column_of( $suspension, 'revoked_at' );
            if ( defined $revoked_at ) {
                await $self->_restore_user_if_needed_p( $scope, $user_id,
                    $revoked_at );
                return {
                    suspension_id => column_of( $suspension, 'suspension_id' ),
                    revoked_at    => $revoked_at,
                };
            }

            my $timestamp = $self->clock->now_iso8601;
            await $scope->row_p(
                'moderation_suspension_update',
                {
                    suspension_id => $suspension_id,
                    revoked_at    => $timestamp
                }
            );
            await $self->_restore_user_if_needed_p( $scope, $user_id,
                $timestamp );
            await $self->_record_p( $scope,
                _revoked_record( $input, $user_id, $timestamp ) );

            return {
                suspension_id => $suspension_id,
                revoked_at    => $timestamp
            };
        },
        $context
    );
}

async sub _restore_user_if_needed_p ( $self, $scope, $user_id, $timestamp ) {
    return if !defined $user_id || !length $user_id;
    my $user = await _user_p( $scope, $user_id );
    return
      if !$user || ( column_of( $user, 'status' ) || q{} ) ne $STATUS_SUSPEND;
    return if await $self->_active_p( $scope, $user_id );

    await _update_user_p( $scope, $user,
        { status => $STATUS_ACTIVE, updated_at => $timestamp } );
    return;
}

async sub _user_p ( $scope, $user_id ) {
    return GPForum::Infrastructure::ResultRow->from(
        await $scope->row_p( 'identity_user_by_id', { user_id => $user_id } ) );
}

# The member's row changed as ResultRow::IdentityUser->update changes it.
async sub _update_user_p ( $scope, $user, $values ) {
    return await $scope->row_p( 'identity_update_user',
        { user_id => $user->{id}, changes => $values } );
}

async sub _suspension_p ( $scope, $suspension_id ) {
    return GPForum::Infrastructure::ResultRow->from(
        await $scope->row_p(
            'moderation_suspension_find', { suspension_id => $suspension_id }
        )
    );
}

async sub _active_p ( $self, $scope, $user_id ) {
    return undef if !defined $user_id || !length $user_id;
    return GPForum::Infrastructure::ResultRow->from(
        await $scope->row_p(
            'moderation_active_suspension',
            $self->_active_values($user_id)
        )
    );
}

sub _active_values ( $self, $user_id ) {
    return { user_id => $user_id, now => $self->clock->now_iso8601 };
}

# Every write of a member's suspensions takes the member's row first
# (v5.0.0-2.3.4): two on one member run one after the other, and the second
# reads what the first committed. Checked and written without it, two
# suspensions of one member both found none active and both inserted one.
# Without the function layer -- the tests' doubles -- there is one writer
# and nothing to wait for.
sub _lock_member ( $self, $user_id ) {
    return if !$self->functions;

    $self->functions->row( 'moderation_lock_member', { user_id => $user_id } );

    return;
}

# A timed suspension's end (v5.0.0-2.3.2), as the outbox delivers it a
# second after valid_to: its member is active again, audited as
# user.suspension_ended with no actor, once no suspension holds them. The
# suspension itself still in force -- this clock behind the database's --
# fails, so the outbox delivers it again; another suspension in force, or a
# member no longer marked suspended, ends nothing.
sub end_suspension ( $self, $user_id, $suspension_id ) {
    return $self->schema->txn_do(
        sub {
            return $self->_end_in_txn( $user_id, $suspension_id );
        }
    );
}

sub _end_in_txn ( $self, $user_id, $suspension_id ) {
    $self->_lock_member($user_id);
    my $user = $self->_user($user_id);
    if ( !$user || ( column_of( $user, 'status' ) || q{} ) ne $STATUS_SUSPEND )
    {
        return { ended => 0, reason => 'not_suspended' };
    }
    my $active = $self->active_for_user($user_id);
    if ($active) {
        my $holding = column_of( $active, 'suspension_id' );
        if ( $holding eq $suspension_id ) {
            GPForum::X::Unavailable->throw(
                message => "suspension $suspension_id has not ended yet" );
        }
        return { ended => 0, reason => 'suspended', suspension_id => $holding };
    }

    my $timestamp = $self->clock->now_iso8601;
    $user->update(
        {
            status     => $STATUS_ACTIVE,
            updated_at => $timestamp,
        }
    );
    $self->_record_event_and_audit(
        {
            action         => $ENDED,
            actor_id       => undef,
            correlation_id => undef,
            created_at     => $timestamp,
            metadata       => { suspension_id => $suspension_id },
            payload        => {
                ended_at      => $timestamp,
                suspension_id => $suspension_id,
            },
            user_id => $user_id,
        }
    );

    return {
        ended         => 1,
        suspension_id => $suspension_id,
        user_id       => $user_id,
    };
}

# The hourly sweep's half (scheduled-jobs suspension_ends): the end of each
# timed suspension that has none queued -- one the release before 1055
# stored, or one whose message the retention purge removed -- up to limit
# (100, at most 1,000).
sub queue_ends ( $self, $input = undef ) {
    my $limit = $input ? $input->{limit} : undef;
    if ( !defined $limit || $limit !~ /\A [[:digit:]]+ \z/amsx || $limit < 1 ) {
        $limit = $DEFAULT_QUEUE;
    }
    if ( $limit > $MAXIMUM_QUEUE ) {
        $limit = $MAXIMUM_QUEUE;
    }
    my $row = $self->functions->row( 'moderation_queue_suspension_ends',
        { now => $self->clock->now_iso8601, row_limit => $limit } );

    return { ok => 1, queued => 0 + ( $row->{queued} // 0 ) };
}

sub _user ( $self, $user_id ) {
    return $self->schema->resultset('User')->find($user_id)
      if !$self->functions;
    return GPForum::Infrastructure::ResultRow::IdentityUser->from(
        $self->functions->row( 'identity_user_by_id', { user_id => $user_id } ),
        $self->functions
    );
}

sub _suspension ( $self, $suspension_id ) {
    return $self->schema->resultset('Suspension')->find($suspension_id)
      if !$self->functions;
    return GPForum::Infrastructure::ResultRow->from(
        $self->functions->row(
            'moderation_suspension_find', { suspension_id => $suspension_id }
        )
    );
}

sub _suspension_hash ($suspension) {
    return {
        suspension_id => column_of( $suspension, 'suspension_id' ),
        user_id       => column_of( $suspension, 'user_id' ),
        actor_user_id => column_of( $suspension, 'actor_user_id' ),
        reason        => column_of( $suspension, 'reason' ),
        valid_from    => column_of( $suspension, 'valid_from' ),
        valid_to      => column_of( $suspension, 'valid_to' ),
        revoked_at    => column_of( $suspension, 'revoked_at' ),
        metadata      => column_of( $suspension, 'metadata' ),
    };
}

sub active_for_user ( $self, $user_id ) {
    return undef if !defined $user_id || !length $user_id;

    if ( $self->functions ) {
        return GPForum::Infrastructure::ResultRow->from(
            $self->functions->row(
                'moderation_active_suspension',
                $self->_active_values($user_id)
            )
        );
    }

    # Every unrevoked suspension, newest first, as
    # api.moderation_active_suspension_v3 reads them: the newest one still
    # valid is the active one. The ten-row window the first versions kept
    # could hide an open-ended suspension behind ten newer expired ones.
    my $search = $self->schema->resultset('Suspension')->search_rs(
        {
            user_id    => $user_id,
            revoked_at => undef,
        },
        {
            order_by =>
              [ { -desc => 'valid_from' }, { -desc => 'suspension_id' } ],
        }
    );

    for my $row ( rows_in($search) ) {
        return $row if $self->_suspension_is_active($row);
    }

    return undef;
}

async sub can_participate_p ( $self, $user_id, $context = undef ) {
    return $self->can_participate($user_id) if !$self->functions;
    return _participation_result(
        await $self->functions->row_p(
            'moderation_can_participate',
            { user_id => $user_id, now => $self->clock->now_iso8601 }, $context
        )
    );
}

sub can_participate ( $self, $user_id ) {
    if ( $self->functions ) {
        return _participation_result(
            $self->functions->row(
                'moderation_can_participate',
                { user_id => $user_id, now => $self->clock->now_iso8601 }
            )
        );
    }

    my $user = $self->_user($user_id);
    return { ok => 0, reason => 'user_not_found' } if !$user;

    my $status = column_of( $user, 'status' ) || $STATUS_ACTIVE;
    return { ok => 0, reason => $STATUS_DENIALS{$status} }
      if exists $STATUS_DENIALS{$status};

    my $active = $self->active_for_user($user_id);
    if ($active) {
        return {
            ok            => 0,
            reason        => 'suspended',
            suspension_id => column_of( $active, 'suspension_id' ),
        };
    }

    return { ok => 1 };
}

sub _participation_result ($row) {
    $row ||= { ok => 0, reason => 'user_not_found' };
    if ( !defined $row->{reason} )        { delete $row->{reason}; }
    if ( !defined $row->{suspension_id} ) { delete $row->{suspension_id}; }
    return $row;
}

sub _restore_user_if_needed ( $self, $user_id, $timestamp ) {
    if ( !defined $user_id || !length $user_id ) {
        return;
    }
    my $user = $self->_user($user_id);
    if ( !$user || ( column_of( $user, 'status' ) || q{} ) ne $STATUS_SUSPEND )
    {
        return;
    }
    return if $self->active_for_user($user_id);

    $user->update(
        {
            status     => $STATUS_ACTIVE,
            updated_at => $timestamp,
        }
    );

    return;
}

# Unrevoked, and open-ended or not yet past its end. The end and the clock
# are compared as the instants they name: PostgreSQL hands valid_to back as
# '2026-05-23 20:00:00+02', in its own zone, while the clock writes
# '2026-05-23T12:00:00Z', and compared as strings a space sorts before a T,
# so a suspension ending later today read as expired, the member could post
# and suspending them again inserted a second suspension.
sub _suspension_is_active ( $self, $row ) {
    if ( !$row || defined column_of( $row, 'revoked_at' ) ) {
        return 0;
    }

    my $valid_to = column_of( $row, 'valid_to' );
    if ( !defined $valid_to || !length $valid_to ) {
        return 1;
    }

    return _instant($valid_to) >= _instant( $self->clock->now_iso8601 )
      ? 1
      : 0;
}

# The epoch second a PostgreSQL timestamptz or an ISO-8601 text names. The
# column and the clock only ever hold those, so anything else is a double
# handing the store a value PostgreSQL never would, and is refused rather
# than compared as text again.
sub _instant ($value) {
    my $epoch =
      GPForum::Service::Identity::Support->epoch_from_timestamp($value);
    if ( !defined $epoch ) {
        GPForum::X::Argument->throw(
            message => "suspension instant is not a timestamp: $value" );
    }

    return $epoch;
}

sub _record_event_and_audit ( $self, $input ) {
    my ( $event, $audit ) = $self->_suspension_records($input);
    $self->recorder->record_event( %{$event} );
    $self->recorder->record_audit( %{$audit} );

    return;
}

async sub _record_p ( $self, $scope, $input ) {
    my ( $event, $audit ) = $self->_suspension_records($input);
    await $scope->row_p( 'ops_record_event',
        $self->recorder->event_call( %{$event} ) );
    await $scope->row_p( 'ops_record_audit',
        $self->recorder->audit_call( %{$audit} ) );
    return;
}

# The event and the audit entry of a suspension's change.
sub _suspension_records ( $self, $input ) {
    my $recorded = {
        %{$input},
        correlation_id => $input->{correlation_id} || $self->id_service->uuid,
    };
    return (
        $self->events->suspension_envelope($recorded),
        $self->events->suspension_audit($recorded),
    );
}

1;

__END__

=head1 NAME

GPForum::Service::Moderation::SuspensionStore - Suspend and reinstate members, and say whether one may take part.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $store =
      GPForum::Service::Moderation::SuspensionStore->new( schema => $schema );

    my $result = $store->create_suspension(
        {
            actor_user_id  => $moderator_id,
            correlation_id => $correlation_id,
            reason         => 'spam',
            user_id        => $user_id,
            valid_to       => '2026-11-01T00:00:00Z',
        }
    );

    my $gate = $store->can_participate($user_id);
    # { ok => 1 }, or { ok => 0, reason => 'suspended', ... }

    $store->revoke_suspension( $suspension_id, $moderator_id, 'appeal upheld' );

=head1 DESCRIPTION

Owns the C<suspensions> table and the user status that mirrors it. A
suspension sets the user's status to C<suspended> and records a
C<user.suspended> event and audit entry; a revocation stamps C<revoked_at>,
sets a still-suspended user back to C<active> only when no active suspension
remains, and records C<user.suspension_revoked>. A revocation never changes
an account that is now deleted or pending. A timed suspension queues its own
end in the outbox (migration 1055): delivered a second after C<valid_to>,
it sets the user back to C<active> the same way and records
C<user.suspension_ended>, with no actor. Every write of a member's
suspensions takes the member's row first, so two of them on one member run
one after the other.
Each runs in one transaction with its event and audit rows, written through
L<GPForum::Infrastructure::EventRecorder> from the envelopes of
L<GPForum::Service::Moderation::Event>.

Suspending is idempotent: a user who already has an active suspension gets
that one back instead of a second row. A suspension is active while it is
not revoked and its C<valid_to> is empty or not before the clock's now, the
two compared as instants whatever text form the column and the clock use.
An insert that loses a race on the suspension id retries once with a new
id.

=head1 SUBROUTINES/METHODS

=head2 create_suspension

Takes a hash reference with C<user_id>, C<actor_user_id>, C<reason>, and
optional C<valid_to> (ISO 8601; none means open-ended), C<source> (kept in
the row's metadata, default C<moderation>) and C<correlation_id> (a new
uuid when absent). In a transaction, returns
C<< { ok => 1, suspension => \%suspension } >> with the new row, whose
metadata also keeps the user's previous status, or the user's active one.
Returns undef when the user does not exist or is deleted.

=head2 create_suspension_p

L</create_suspension> as a promise, with an optional query context last, in one
transaction on the worker's pooled asynchronous connections.

=head2 revoke_suspension

Takes a suspension id, the acting user's id and a reason. In a transaction,
returns C<< { suspension_id, revoked_at } >>, or undef when there is no such
suspension. Revoking one that is already revoked records nothing new and
returns its original C<revoked_at>. It restores a still-suspended user only
when no other active suspension remains; other account states stay as they are.

=head2 revoke_suspension_p

L</revoke_suspension> as a promise, with an optional query context last, in one
transaction on the worker's pooled asynchronous connections.

=head2 end_suspension

Takes a user id and the id of the timed suspension that ended. In a
transaction, returns C<< { ended => 1, suspension_id, user_id } >> once the
user is active again, or C<< { ended => 0, reason } >>: C<not_suspended>
when the user is not marked suspended, C<suspended> (with C<suspension_id>)
when another suspension is in force. Throws L<GPForum::X::Unavailable> when
the named suspension is still in force by the clock, so the outbox delivers
the end again.

=head2 queue_ends

Takes an optional hash reference with C<limit> (100 by default, at most
1,000) and queues the end of that many timed suspensions of suspended
members that have none queued. Returns C<< { ok => 1, queued } >>.

=head2 active_for_user

Takes a user id. Returns the user's newest unrevoked suspension, by
C<valid_from>, whose C<valid_to> is empty or not before the clock's now;
undef when there is none or the id is empty.

=head2 can_participate

Takes a user id. Returns C<< { ok => 1 } >> when the user may take part.
Otherwise returns C<< { ok => 0, reason } >> with reason C<user_not_found>,
C<user_deleted> (status C<deleted>) or C<suspended> (status C<suspended>),
or C<suspended> together with C<suspension_id> when an active suspension
exists while the status says otherwise.

=head2 can_participate_p

Promise form of C<can_participate>, with the same live suspension check and
response shape. Persistent HTTP calls use the retained native connection;
in-memory stores retain their synchronous behavior.

=head1 DIAGNOSTICS

A missing user or suspension is returned as undef, not thrown. An error
from the insert other than a collision on the suspension id, or a second
collision, is rethrown with C<croak>; other database errors propagate.
Either rolls the transaction back. A C<valid_to> or clock value that is not
a timestamp throws L<GPForum::X::Argument>.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Infrastructure::Row>, L<GPForum::Infrastructure::EventRecorder>,
L<GPForum::Infrastructure::UniqueConflict>, L<GPForum::X::Argument>,
L<GPForum::X::Conflict>, L<GPForum::X::Unavailable>,
L<GPForum::Infrastructure::Id>,
L<GPForum::Service::Clock>, L<GPForum::Service::Identity::Support> (its
timestamp parser), L<GPForum::Service::Moderation::Event>.

Extends L<GPForum::Base>: built without C<schema> it throws
L<GPForum::X::Argument>.

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
