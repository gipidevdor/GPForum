# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Identity::RegistrationStore;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -signatures, -async_await;
use v5.40;

use GPForum::Infrastructure::Row qw(column_of);
use GPForum::Infrastructure::SqlFunction;
use GPForum::Infrastructure::ResultRow::IdentityUser;

use GPForum::Infrastructure::UniqueConflict;
use GPForum::X::Conflict;
use GPForum::X::Unavailable;

our $VERSION = '0.001';

const my $ID_CONSTRAINT => 'users_pkey';
const my %TAKEN => (
    email    => 'email is already registered',
    username => 'username is already registered',
);

__PACKAGE__->requires(qw(audit credential_store id_service schema));

has functions => \&GPForum::Infrastructure::SqlFunction::for_service;

# Each operation is written once, as its promise method (ADR 0177).
GPForum::Infrastructure::SqlFunction->blocking_twins('create_registration');

# A username or address taken since the look-up is refused as the look-up
# refuses it. A minted user id already stored is this registration's,
# committed by an earlier attempt, or another account's, and then a new id is
# minted. The account, its credential, its event and its audit are written
# in one transaction, or a savepoint of the one $scope holds.
async sub create_registration_p (
    $self, $registration,
    $context = undef,
    $scope = undef
  )
{
    $scope //= $self->_functions;
    my $errors =
      await $self->_duplicate_errors_p( $registration->{user}, $context,
        $scope );
    return { errors => $errors, ok => 0 } if keys %{$errors};

    my ( $result, $error ) =
      await GPForum::Infrastructure::UniqueConflict->attempt_p( $scope,
        $self->_insert( $registration, $context ) );
    return { ok => 1, user => $result->{user} } if $result;

    my $conflict = GPForum::Infrastructure::UniqueConflict->conflict_of($error);
    if ( !$conflict->on($ID_CONSTRAINT) ) {
        $errors =
          await $self->_duplicate_errors_p( $registration->{user}, $context,
            $scope );
        return { errors => keys %{$errors} ? $errors : {%TAKEN}, ok => 0 };
    }

    my $stored = GPForum::Infrastructure::ResultRow::IdentityUser->from(
        await $scope->row_p(
            'identity_user_by_id', { user_id => $registration->{user}{id} },
            $context
        ),
        $scope
    );
    if ( _same_open_user( $stored, $registration->{user} ) ) {

        # The transaction that inserted the account rolled back on the
        # conflict, so the rest of the registration goes in a transaction of
        # its own (ADR 0110): a failed audit leaves neither the credential
        # nor the event behind, no registration half written.
        await $scope->transaction_p(
            sub ($transaction) {
                return $self->_complete_registration_p( $registration,
                    $context, $transaction );
            },
            $context
        );
        return { ok => 1, user => $stored };
    }

    my $reissued = {
        %{$registration},
        user => { %{ $registration->{user} }, id => $self->id_service->uuid },
    };
    my ( $created, $retry_error ) =
      await GPForum::Infrastructure::UniqueConflict->attempt_p( $scope,
        $self->_insert( $reissued, $context ) );
    return { ok => 1, user => $created->{user} } if $created;

    GPForum::Infrastructure::UniqueConflict->rethrow($retry_error);
}

# The work that inserts the account and completes the registration in the
# transaction it is given.
sub _insert ( $self, $registration, $context ) {
    return async sub ($transaction) {
        my $user       = $registration->{user};
        my $credential = $registration->{credential};
        $user->{password_hash} ||= $credential->{secret_hash};

        my $created = GPForum::Infrastructure::ResultRow::IdentityUser->from(
            await $transaction->row_p(
                'identity_insert_user', { values => $user }, $context
            ),
            $transaction
        );
        await $self->_complete_registration_p( $registration, $context,
            $transaction );

        return { user => $created };
    };
}

# The same username and address: the row is this registration's account.
sub _same_open_user ( $stored, $user ) {
    if ( !$stored ) {
        return 0;
    }
    for my $column (qw(username email_normalized)) {
        my $value = column_of( $stored, $column );
        if (   !defined $value
            || !defined $user->{$column}
            || $value ne $user->{$column} )
        {
            return 0;
        }
    }

    return 1;
}

# The account's password credential, then its event and its audit, as the
# recorder prepares them, on the registration's transaction.
async sub _complete_registration_p ( $self, $registration, $context, $scope ) {
    my $user       = $registration->{user};
    my $credential = $registration->{credential};
    await $self->credential_store->create_password_credential_p(
        {
            secret_hash => $credential->{secret_hash},
            type        => $credential->{type},
            user_id     => $user->{id},
        },
        $context, $scope
    );
    my $calls =
      $self->audit->registration_calls( $user, $self->id_service->uuid );
    await $scope->row_p( 'ops_record_event', $calls->{event}, $context );
    await $scope->row_p( 'ops_record_audit', $calls->{audit}, $context );

    return;
}

async sub _duplicate_errors_p ( $self, $user, $context, $scope ) {
    my $row = await $scope->row_p(
        'identity_registration_duplicates',
        {
            username => $user->{username},
            email    => $user->{email_normalized}
        },
        $context
    );
    return {
        ( $row->{username_taken} ? ( username => $TAKEN{username} ) : () ),
        ( $row->{email_taken}    ? ( email    => $TAKEN{email} )    : () ),
    };
}

sub _functions ($self) {
    return $self->functions // GPForum::X::Unavailable->throw(
        message => 'registrations need the PostgreSQL database' );
}

1;

__END__

=head1 NAME

GPForum::Service::Identity::RegistrationStore - Registration persistence.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $result = $store->create_registration($registration);

=head1 DESCRIPTION

Owns duplicate-account checks and transactional user/credential persistence
for prepared registrations. The identity store facade delegates
C<create_registration> so HTTP and workflow callers keep a stable API.

Each operation is written once, as its promise method, against the
PostgreSQL function layer; the blocking method is its twin (ADR 0177).
There is no fallback: without the function layer a call raises
L<GPForum::X::Unavailable>.

=head1 SUBROUTINES/METHODS

=head2 create_registration_p

Takes a prepared registration, an optional query context and an optional
call layer: the transaction the caller holds. Persists the account, its
password credential, its event and its audit inside a transaction, or a
savepoint of the caller's. Answers C<< { ok => 1, user } >> or
C<< { ok => 0, errors } >>.

=head2 create_registration

The blocking twin of L</create_registration_p> (ADR 0177): run on the
blocking call layer, answering the value instead of a promise.

=head1 DIAGNOSTICS

Duplicate usernames and emails return field errors without opening a
transaction. A unique race on insert returns the same field errors and does
not persist a second user or credential. A unique C<id> collision remints
the id once and does not return another user's account. A leftover unique
C<id> with this username and email reuses the account and inserts the
missing credential, event and audit in one transaction of their own, so a
failure there leaves none of them behind.

=head1 CONFIGURATION AND ENVIRONMENT

Requires the PostgreSQL function layer plus credential and audit
collaborators supplied by the identity store facade.

=head1 DEPENDENCIES

Uses L<GPForum::Infrastructure::SqlFunction>,
L<GPForum::Infrastructure::UniqueConflict>, L<GPForum::X::Conflict> and
the injected collaborators. The event and audit are the calls
L<GPForum::Service::Identity::Audit/registration_calls> prepares.

Extends L<GPForum::Base>: built without C<audit>, C<credential_store>,
C<id_service> or C<schema> it throws L<GPForum::X::Argument>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Does not hash passwords; C<Identity::Registration> prepares the credential
hash before this store runs.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
