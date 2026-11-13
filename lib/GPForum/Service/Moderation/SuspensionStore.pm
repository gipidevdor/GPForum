# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Moderation::SuspensionStore;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -async_await;
use v5.40;

use GPForum::Infrastructure::Row qw(column_of);
use GPForum::Infrastructure::ResultRow;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Infrastructure::EventRecorder;
use GPForum::Infrastructure::UniqueConflict;
use GPForum::Service::Clock;
use GPForum::Service::Moderation::Event;
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

has clock      => sub { return GPForum::Service::Clock->new; };
has id_service => sub {
    require GPForum::Infrastructure::Id;
    return GPForum::Infrastructure::Id->new;
};
has recorder => \&GPForum::Infrastructure::EventRecorder::for_service;
__PACKAGE__->requires(qw(schema));
has functions => \&GPForum::Infrastructure::SqlFunction::for_service;
has events    => sub { return GPForum::Service::Moderation::Event->new; };

# Each operation has one body, its promise method, written against the call
# layer (ADR 0177). The blocking method is that same body on the process's
# own connection.
GPForum::Infrastructure::SqlFunction->blocking_twins(
    qw(create_suspension revoke_suspension end_suspension active_for_user
      can_participate)
);

# A member already under an active suspension keeps it. A minted id already
# stored is minted once more: under the member's lock nothing else can have
# suspended them meanwhile. A member the actor may not suspend -- themselves,
# or staff when the actor does not manage the admin console -- is refused:
# suspended staff can no longer lift a suspension from the consoles.
async sub create_suspension_p ( $self, $input, $context = undef ) {
    return await $self->_functions->transaction_p(
        async sub ($scope) {
            await _lock_member_p( $scope, $input->{user_id} );
            my $user = await _user_p( $scope, $input->{user_id} );
            return undef
              if !$user
              || ( column_of( $user, 'status' ) // q{} ) eq $STATUS_DELETED;
            my $refused = _target_refusal(
                await $scope->row_p(
                    'moderation_suspension_target',
                    _target_of($input)
                )
            );
            return $refused if $refused;

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

# A suspension already revoked is answered as it stands, its member restored
# if an earlier attempt left them suspended. It is read again under its
# member's lock, so a revocation that committed while this one waited is
# answered, not stamped and audited a second time.
async sub revoke_suspension_p ( $self, $suspension_id, $actor_user_id,
    $reason, $context = undef )
{
    my $input = {
        actor_user_id => $actor_user_id,
        reason        => $reason,
        suspension_id => $suspension_id,
    };
    return await $self->_functions->transaction_p(
        async sub ($scope) {
            my $suspension = await _suspension_p( $scope, $suspension_id );
            return undef if !$suspension;
            my $user_id = column_of( $suspension, 'user_id' );
            await _lock_member_p( $scope, $user_id );

            # Lifting is refused as imposing is: not one's own suspension,
            # and a staff member's only by an administrator.
            my $refused = _target_refusal(
                await $scope->row_p(
                    'moderation_suspension_target',
                    _target_of(
                        {
                            actor_user_id => $actor_user_id,
                            user_id       => $user_id
                        }
                    )
                )
            );
            return $refused if $refused;
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

# A timed suspension's end (v5.0.0-2.3.2), as the outbox delivers it a
# second after valid_to: its member is active again, audited as
# user.suspension_ended with no actor, once no suspension holds them. The
# suspension itself still in force -- this clock behind the database's --
# fails, so the outbox delivers it again; another suspension in force, or a
# member no longer marked suspended, ends nothing.
async sub end_suspension_p ( $self, $user_id, $suspension_id, $context = undef )
{
    return await $self->_functions->transaction_p(
        async sub ($scope) {
            await _lock_member_p( $scope, $user_id );
            my $user = await _user_p( $scope, $user_id );
            return { ended => 0, reason => 'not_suspended' }
              if !$user
              || ( column_of( $user, 'status' ) || q{} ) ne $STATUS_SUSPEND;
            my $active = await $self->_active_p( $scope, $user_id );
            if ($active) {
                my $holding = column_of( $active, 'suspension_id' );
                if ( $holding eq $suspension_id ) {
                    GPForum::X::Unavailable->throw( message =>
                          "suspension $suspension_id has not ended yet" );
                }
                return {
                    ended         => 0,
                    reason        => 'suspended',
                    suspension_id => $holding
                };
            }

            my $timestamp = $self->clock->now_iso8601;
            await _update_user_p( $scope, $user,
                { status => $STATUS_ACTIVE, updated_at => $timestamp } );
            await $self->_record_p(
                $scope,
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
        },
        $context
    );
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
    my $row = $self->_functions->row( 'moderation_queue_suspension_ends',
        { now => $self->clock->now_iso8601, row_limit => $limit } );

    return { ok => 1, queued => 0 + ( $row->{queued} // 0 ) };
}

# The member's newest unrevoked suspension still in force, as
# api.moderation_active_suspension reads it; none without a user id.
async sub active_for_user_p ( $self, $user_id, $context = undef ) {
    return undef if !defined $user_id || !length $user_id;
    return await $self->_active_p( $self->_functions, $user_id, $context );
}

async sub can_participate_p ( $self, $user_id, $context = undef ) {
    return _participation_result(
        await $self->_functions->row_p(
            'moderation_can_participate',
            { user_id => $user_id, now => $self->clock->now_iso8601 }, $context
        )
    );
}

sub _participation_result ($row) {
    $row ||= { ok => 0, reason => 'user_not_found' };
    if ( !defined $row->{reason} )        { delete $row->{reason}; }
    if ( !defined $row->{suspension_id} ) { delete $row->{suspension_id}; }
    return $row;
}

# The call layer. Suspensions live in PostgreSQL only: a store without one is
# a configuration error, not a store with nothing in it.
sub _functions ($self) {
    return $self->functions // GPForum::X::Unavailable->throw(
        message => 'suspensions need the PostgreSQL function layer' );
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

# Every write of a member's suspensions takes the member's row first
# (v5.0.0-2.3.4): two on one member run one after the other, and the second
# reads what the first committed. Checked and written without it, two
# suspensions of one member both found none active and both inserted one.
async sub _lock_member_p ( $scope, $user_id ) {
    await $scope->row_p( 'moderation_lock_member', { user_id => $user_id } );
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

async sub _active_p ( $self, $scope, $user_id, $context = undef ) {
    return undef if !defined $user_id || !length $user_id;
    return GPForum::Infrastructure::ResultRow->from(
        await $scope->row_p(
            'moderation_active_suspension',
            { user_id => $user_id, now => $self->clock->now_iso8601 }, $context
        )
    );
}

sub _target_of ($input) {
    return { actor => $input->{actor_user_id}, user_id => $input->{user_id} };
}

# The refusal for a member this actor may not suspend, or undef.
sub _target_refusal ($target) {
    my $answer = ref $target eq 'HASH' ? $target->{result} // q{} : q{};
    return undef if $answer eq 'allowed';

    return {
        ok      => 0,
        refused => $answer eq 'self' ? 'self' : 'staff',
    };
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

=head2 end_suspension_p

L</end_suspension> as a promise, with an optional query context last.

=head2 active_for_user_p

L</active_for_user> as a promise, with an optional query context last.

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
response shape.

Each blocking method above is its promise method run on the process's own
connection (L<GPForum::Infrastructure::SqlFunction/settle>): one body per
operation. The store needs the PostgreSQL function layer and throws
L<GPForum::X::Unavailable> without one.

=head1 DIAGNOSTICS

A missing user or suspension is returned as undef, not thrown. An error
from the insert other than a collision on the suspension id, or a second
collision, is rethrown with C<croak>; other database errors propagate.
Either rolls the transaction back. A store without the PostgreSQL function
layer throws L<GPForum::X::Unavailable>.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Infrastructure::Row>, L<GPForum::Infrastructure::EventRecorder>,
L<GPForum::Infrastructure::UniqueConflict>, L<GPForum::Infrastructure::SqlFunction>,
L<GPForum::X::Conflict>, L<GPForum::X::Unavailable>,
L<GPForum::Infrastructure::Id>,
L<GPForum::Service::Clock>, L<GPForum::Service::Moderation::Event>.

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
