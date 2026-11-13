# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Identity::CredentialStore;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -signatures, -async_await;
use v5.40;

use GPForum::Infrastructure::SqlFunction;
use GPForum::Infrastructure::ResultRow;

use GPForum::Infrastructure::Text qw(has_text);
use GPForum::Infrastructure::UniqueConflict;
use GPForum::Service::Clock;
use GPForum::Service::Identity::Support;
use GPForum::X::Conflict;
use GPForum::X::Unavailable;

our $VERSION = '0.001';

const my @CREDENTIAL_COLUMNS =>
  qw(id user_id type secret_hash revoked_at created_at);
const my $ID_CONSTRAINT     => 'credentials_pkey';
const my $ACTIVE_CONSTRAINT => 'idx_credentials_active_password_unique';

has clock      => sub { return GPForum::Service::Clock->new; };
has id_service => sub {
    require GPForum::Infrastructure::Id;
    return GPForum::Infrastructure::Id->new;
};
__PACKAGE__->requires(qw(schema));
has support   => sub { return GPForum::Service::Identity::Support->new; };
has functions => \&GPForum::Infrastructure::SqlFunction::for_service;

# Each operation is written once, as its promise method (ADR 0177).
GPForum::Infrastructure::SqlFunction->blocking_twins(
    qw(create_password_credential active_password_credential
      hold_active_password_credential lock_active_password_credentials
      rotate_password_credential)
);

# created_at comes from the store's clock, as revoked_at does: the database
# default stamped creation by the server's clock while revocation took the
# application's, and an application clock behind the server's revoked a
# credential before it was created, which credentials_revoked_after_created
# refuses. The session and token stores stamp their rows the same way.
#
# A member's active password is answered rather than doubled, whether it was
# there before or a concurrent insert committed it first. A minted id already
# stored is this very credential, committed by an earlier attempt, or another
# one, and then a new id is minted. On $scope, the transaction the caller
# holds: each insert is tried in a savepoint of it.
async sub create_password_credential_p (
    $self, $input,
    $context = undef,
    $scope = undef
  )
{
    $scope //= $self->_functions;
    my $existing =
      await $self->active_password_credential_p( $input->{user_id}, $context,
        $scope );
    return $self->_skipped_credential($existing) if $existing;

    my $row    = $self->new_password_credential_row($input);
    my $insert = sub ($values) {
        return GPForum::Infrastructure::UniqueConflict->attempt_p(
            $scope,
            sub ($savepoint) {
                return $self->_insert_credential_p( $values, $context,
                    $savepoint );
            }
        );
    };
    my ( $created, $error ) = await $insert->($row);
    return $created if $created;

    my $conflict = GPForum::X::Conflict->caught($error);
    if ( $conflict && $conflict->on($ID_CONSTRAINT) ) {
        my $stored = GPForum::Infrastructure::ResultRow->from(
            await $scope->row_p(
                'identity_credential_by_id', { credential_id => $row->{id} },
                $context
            )
        );
        return $self->_skipped_credential($stored)
          if $self->_same_open_credential( $stored, $row );

        my ( $retried, $retry_error ) =
          await $insert->( { %{$row}, id => $self->id_service->uuid } );
        return $retried if $retried;
        GPForum::Infrastructure::UniqueConflict->rethrow($retry_error);
    }
    if ( $conflict && $conflict->on($ACTIVE_CONSTRAINT) ) {
        $existing =
          await $self->active_password_credential_p( $input->{user_id},
            $context, $scope );
        return $self->_skipped_credential($existing) if $existing;
    }

    GPForum::Infrastructure::UniqueConflict->rethrow($error);
}

# A leftover of this very insert is this member's, of this type, and still
# open. A revoked credential under the id was reused all the same: the store
# answered with it as the active password, inserted none, and left the
# member with no password at all.
sub _same_open_credential ( $self, $stored, $row ) {
    if ( !$stored || defined $self->support->column( $stored, 'revoked_at' ) ) {
        return 0;
    }
    for my $column (qw(type user_id)) {
        my $value = $self->support->column( $stored, $column );
        if (   !defined $value
            || !defined $row->{$column}
            || $value ne $row->{$column} )
        {
            return 0;
        }
    }

    return 1;
}

sub _skipped_credential ( $self, $existing ) {
    my %row =
      map { $_ => scalar $self->support->column( $existing, $_ ) }
      @CREDENTIAL_COLUMNS;

    return { %row, skipped => 1 };
}

# The member's newest open password credential. On $scope: a transaction
# the caller holds.
async sub active_password_credential_p (
    $self, $user_id,
    $context = undef,
    $scope = undef
  )
{
    return undef if !has_text($user_id);
    $scope //= $self->_functions;

    return GPForum::Infrastructure::ResultRow->from(
        await $scope->row_p(
            'identity_active_password', { user_id => $user_id }, $context
        )
    );
}

# The row create_password_credential inserts: the time, a new id, the
# secret and its type, the account. Public so a command that creates the
# credential in one call (api.identity_register_command) sends the same.
sub new_password_credential_row ( $self, $input ) {
    return {
        created_at  => $self->clock->now_iso8601,
        id          => $self->id_service->uuid,
        secret_hash => $input->{secret_hash},
        type        => $input->{type} || 'password',
        user_id     => $input->{user_id},
    };
}

# The credential a login verified, FOR SHARE, while it is still this
# member's active password; undef once a rotation revoked it. Held until the
# caller's transaction ends, so a rotation that has not reached the row yet
# waits for that transaction, and one that already has makes this wait for
# it and then find the row revoked. On $scope, the transaction that holds
# the lock until it ends.
async sub hold_active_password_credential_p (
    $self, $user_id, $credential_id,
    $context = undef,
    $scope = undef
  )
{
    return undef if !has_text($user_id) || !has_text($credential_id);
    $scope //= $self->_functions;

    return GPForum::Infrastructure::ResultRow->from(
        await $scope->row_p(
            'identity_hold_password',
            { user_id => $user_id, credential_id => $credential_id }, $context
        )
    );
}

# The member's active password credentials, locked FOR UPDATE until the
# caller's transaction ends, so the caller decides on the password the
# member has now and no other reset or change can replace it before the
# caller commits. A rotation that commits while this waits for its lock
# revokes the rows waited for, and the credential it creates is not in the
# statement's snapshot: api.identity_lock_passwords then reads again, and
# locks the new credential, up to three rounds. On $scope, the transaction
# that holds the locks until it ends: the rows in an array reference.
async sub lock_active_password_credentials_p (
    $self, $user_id,
    $context = undef,
    $scope = undef
  )
{
    $scope //= $self->_functions;

    return [
        map { GPForum::Infrastructure::ResultRow->from($_) }
          @{ await $scope->rows_p(
                'identity_lock_passwords', { user_id => $user_id },
                $context
            )
          }
    ];
}

# Every active password is revoked before the new one is created, under the
# lock above: a login holding one of them FOR SHARE opens its session before
# the rotation goes on, and the caller's revocation of the member's
# sessions, later in the same transaction, then sees it. On $scope, the
# transaction the caller holds.
async sub rotate_password_credential_p (
    $self, $input,
    $context = undef,
    $scope = undef
  )
{
    $scope //= $self->_functions;
    my $active =
      await $self->lock_active_password_credentials_p( $input->{user_id},
        $context, $scope );
    if ( @{$active} ) {
        await $scope->row_p(
            'identity_revoke_passwords',
            {
                ids => [
                    map { scalar $self->support->column( $_, 'id' ) } @{$active}
                ],
                revoked_at => $self->clock->now_iso8601
            },
            $context
        );
    }

    return await $self->create_password_credential_p(
        {
            secret_hash => $input->{secret_hash},
            type        => 'password',
            user_id     => $input->{user_id},
        },
        $context, $scope
    );
}

async sub _insert_credential_p ( $self, $values, $context, $scope ) {
    my $stored = await $scope->row_p( 'identity_insert_credential',
        { values => $values }, $context );

    return GPForum::Infrastructure::ResultRow->from(
        { map { $_ => $stored->{$_} } keys %{$values} } );
}

sub _functions ($self) {
    return $self->functions // GPForum::X::Unavailable->throw(
        message => 'credentials need the PostgreSQL database' );
}

1;

__END__

=head1 NAME

GPForum::Service::Identity::CredentialStore - Password credential persistence.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $store = GPForum::Service::Identity::CredentialStore->new(
        schema => $schema,
    );

=head1 DESCRIPTION

Creates, locates, and rotates password credentials.

Each operation is written once, as its promise method, against the
PostgreSQL function layer; the blocking methods are its twins (ADR 0177).
There is no fallback: without the function layer a call raises
L<GPForum::X::Unavailable>.

=head1 SUBROUTINES/METHODS

Every C<_p> method takes an optional query context after its arguments and
an optional call layer after it: the transaction the caller holds, or the
store's own layer.

=head2 create_password_credential_p

Inserts a password credential row, stamped C<created_at> by the store's
clock, the clock that later stamps its C<revoked_at>. An already-active
password for that user is answered with C<skipped> and is not inserted
again. A unique C<id> collision remints the id once and does not return
another user's credential, nor a revoked one. A leftover unique C<id> with
this user and type, still open, reuses the active password. Each insert is
tried in a savepoint of the transaction.

=head2 active_password_credential_p

Answers the newest non-revoked password credential for a user, or undef.

=head2 new_password_credential_row

Takes C<secret_hash>, C<type> (C<password> when omitted) and C<user_id> and
returns the row L</create_password_credential_p> would insert: the clock's
time, a new id, the secret and its type, the account. For a command that
creates the credential in one call (C<api.identity_register_command>).

=head2 hold_active_password_credential_p

Takes a user id and a credential id. Inside the caller's transaction, reads
that password credential C<FOR SHARE> while it is still the member's and not
revoked, and answers it; undef otherwise. A login holds the credential it
verified this way while it opens its session.

=head2 lock_active_password_credentials_p

Takes a user id. Inside the caller's transaction, locks the member's active
password credentials C<FOR UPDATE> and answers them in an array reference,
empty when the member has none. When a concurrent rotation commits while
this waits, the credential it created is locked instead: the caller always
holds the password the member has when it goes on. Fails when three
rotations commit in a row while it waits.

=head2 rotate_password_credential_p

Locks the member's active password credentials as
L</lock_active_password_credentials_p> does, revokes them -- at the store's
clock, or at a credential's own C<created_at> when that is later -- and
inserts a replacement, which it answers. Meant to run in the transaction
that then revokes the member's sessions, so a login holding the old
credential either commits its session first, and that session is revoked,
or finds the credential revoked and opens none.

=head2 create_password_credential, active_password_credential, hold_active_password_credential, lock_active_password_credentials, rotate_password_credential

The blocking twins: each is its C<_p> method run on the blocking call layer
(ADR 0177), answering the value instead of a promise.

=head1 DIAGNOSTICS

C<api.identity_lock_passwords> raises C<the password of ID changed 3 times
while this waited for it; try again>. Missing users yield an empty
credential. Without the function layer a call raises
L<GPForum::X::Unavailable>.

=head1 CONFIGURATION AND ENVIRONMENT

Requires the PostgreSQL function layer.

=head1 DEPENDENCIES

Uses L<GPForum::Infrastructure::SqlFunction>,
L<GPForum::Infrastructure::UniqueConflict>, L<GPForum::X::Conflict> and
L<GPForum::Service::Identity::Support>.

Extends L<GPForum::Base>: built without C<schema> it throws
L<GPForum::X::Argument>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Only password credentials are managed here.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
