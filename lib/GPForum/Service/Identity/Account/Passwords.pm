# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Identity::Account::Passwords;

use Const::Fast;
use Mojo::Base 'GPForum::Service::Identity::Account::Core', -async_await;
use v5.40;

use Mojo::Util qw(secure_compare);
use GPForum::Infrastructure::SqlFunction;
use GPForum::Infrastructure::Text qw(has_text);

our $VERSION = '0.001';

const my $HOUR_SECONDS                 => 3_600;
const my $PASSWORD_RESET_TOKEN_SECONDS => $HOUR_SECONDS;

# Each operation is written once, as its promise method (ADR 0177).
GPForum::Infrastructure::SqlFunction->blocking_twins(
    qw(request_password_reset reset_password change_password));

# An unknown or deleted account is audited as not found and answered like a
# found one, so the answer does not tell who has an account. On $scope: the
# transaction a command log holds, or one of its own.
async sub request_password_reset_p (
    $self, $input,
    $context = undef,
    $scope = undef
  )
{
    $scope //= $self->account_functions;

    return await $self->in_transaction_p(
        $scope, $context,
        sub ($transaction) {
            return $self->_password_reset_p( $input, $context, $transaction );
        }
    );
}

async sub _password_reset_p ( $self, $input, $context, $scope ) {
    my $user = await $self->find_login_user_p(
        $self->support->normalize_identifier( $input->{identifier} ),
        $context, $scope );
    if ( !$user || $self->deleted_user($user) ) {
        return await $self->audit_not_found_p(
            'identity.password_reset.requested',
            $input, $context, $scope );
    }

    # Confirmation withdraws reset links under the credential lock. A reset
    # request takes it too, then reloads the address, so it cannot issue a
    # link to the replaced address after that withdrawal has committed.
    my $user_id = $self->support->column( $user, 'id' );
    await $self->credential_store->lock_active_password_credentials_p( $user_id,
        $context, $scope );
    $user = await $self->find_user_by_id_p( $user_id, $context, $scope );
    if ( !$user || $self->deleted_user($user) ) {
        return await $self->audit_not_found_p(
            'identity.password_reset.requested',
            $input, $context, $scope );
    }

    my $token =
      await $self->token_store->create_token_p(
        $self->_reset_token_input( $user, $input ),
        $context, $scope );
    await $self->record_user_action_p(
        $user,
        'identity.password_reset.requested',
        $self->issued_metadata( $input, $token ),
        $context, $scope
    );
    await $self->queue_issued_mail_p( $user,
        $self->_reset_mail( $user, $token ),
        $context, $scope );

    return $self->issued_answer( $user, $token );
}

sub _reset_token_input ( $self, $user, $input ) {
    return {
        email_normalized => $self->support->column( $user, 'email_normalized' ),
        metadata         => {
            identifier_hash =>
              $self->support->hash_value( $input->{identifier} ),
            request_address_hash =>
              $self->support->hash_value( $input->{request_address} ),
        },
        token_type  => 'password_reset',
        ttl_seconds => $PASSWORD_RESET_TOKEN_SECONDS,
        user_id     => $self->support->column( $user, 'id' ),
    };
}

sub _reset_mail ( $self, $user, $token ) {
    return {
        kind   => 'password_reset',
        locale => $self->support->column( $user, 'preferred_locale' ),
        to     => $self->support->column( $user, 'email_normalized' ),
        token  => $token,
    };
}

# A password that cannot be right is refused before the database is
# reached. On $scope, as request_password_reset_p.
async sub reset_password_p ( $self, $input, $context = undef, $scope = undef ) {
    my $password_error = $self->password_error( $input->{password} );
    return { error => $password_error, ok => 0 } if $password_error;
    $scope //= $self->account_functions;

    return await $self->in_transaction_p(
        $scope, $context,
        sub ($transaction) {
            return $self->_reset_password_p( $input, $context, $transaction );
        }
    );
}

# A reset to the password the member already has keeps the credential; the
# sessions are revoked either way. The password is compared with the one the
# member has under the lock the rotation takes, so a change committed in the
# meantime is the one compared and then replaced. It is hashed under the lock
# too, not before it as a change hashes it: the token is checked in this
# transaction, and hashing first would spend Argon2 on every invalid token.
async sub _reset_password_p ( $self, $input, $context, $scope ) {
    my $token =
      await $self->consume_account_token_p( 'password_reset', $input->{token},
        $context, $scope );
    return $token if !$token->{ok};
    my $user =
      await $self->find_user_by_id_p( $token->{user_id}, $context, $scope );
    return { error => 'invalid_token', ok => 0 }
      if !$self->_reset_address_held( $token, $user );

    my $current = await $self->locked_password_p( $user, $context, $scope );
    my $now     = $self->clock->now_iso8601;
    my $same =
      await $self->credential_matches_p( $current, $input->{password}, $scope );
    if ( !$same ) {
        await $self->_store_password_p( $user, $input->{password}, $now, undef,
            $context, $scope );
    }
    await $self->session_store->revoke_user_sessions_p(
        $self->support->column( $user, 'id' ),
        $now, undef, $context, $scope );
    my $withdrawn =
      await $self->withdraw_email_change_p( $user, $context, $scope );
    await $self->record_user_action_p(
        $user,
        'identity.password_reset.completed',
        {
            email_change_withdrawn => $withdrawn,
            token_id               => $token->{token_id},
        },
        $context, $scope
    );

    return {
        ok      => 1,
        skipped => $same,
        user    => $user,
    };
}

# The token's address is still the member's recovery address.
sub _reset_address_held ( $self, $token, $user ) {
    return 0 if !$user || !has_text( $token->{email_normalized} );

    return $token->{email_normalized} eq
      ( $self->support->column( $user, 'email_normalized' ) // q{} ) ? 1 : 0;
}

# The current password is verified and the new one hashed before the
# transaction: Argon2 under the credential's lock kept a sign-in of the
# same member waiting for it. On $scope, as request_password_reset_p.
async sub change_password_p ( $self, $input, $context = undef, $scope = undef )
{
    my $password_error = $self->password_error( $input->{new_password} );
    return { error => $password_error, ok => 0 } if $password_error;
    $scope //= $self->account_functions;
    my $user =
      await $self->find_user_by_id_p( $input->{user_id}, $context, $scope );
    return { error => 'not_found', ok => 0 } if !$user;
    my $verified =
      await $self->credential_store->active_password_credential_p(
        $self->support->column( $user, 'id' ),
        $context, $scope );
    return { error => 'invalid_current_password', ok => 0 }
      if !await $self->credential_matches_p( $verified,
        $input->{current_password}, $scope );

    my $secret_hash =
      _same_password($input)
      ? undef
      : await $self->hashed_password_p( $input->{new_password}, $scope );

    return await $self->in_transaction_p(
        $scope, $context,
        sub ($transaction) {
            return $self->_change_password_p(
                $user,        $input,   $verified,
                $secret_hash, $context, $transaction
            );
        }
    );
}

# The current password was verified before this transaction, against the
# credential active then. A reset or another change that committed in
# between replaced that credential, and the change went on all the same: it
# rotated the new password away, so whoever knew the old one -- the reason
# for a reset -- set the last password and kept the account, and a change
# that waited for another one reported success with a password that was not
# stored. It goes on only while the credential it verified is the member's,
# locked until it commits; otherwise the current password it was given is no
# longer the current one.
async sub _change_password_p ( $self, $user, $input, $verified,
    $secret_hash, $context, $scope )
{
    my $current = await $self->locked_password_p( $user, $context, $scope );
    return { error => 'invalid_current_password', ok => 0 }
      if !$self->_still_verified( $current, $verified );

    # $current is the credential the current password matched, so the new
    # password matches it exactly when it is the current one: compared as
    # text, in constant time, where verifying it against the hash was a
    # second Argon2 run (tens of milliseconds) under the row's lock.
    return {
        ok      => 1,
        skipped => 1,
        user    => $user,
      }
      if _same_password($input);

    await $self->_store_password_p(
        $user,
        $input->{new_password},
        $self->clock->now_iso8601,
        $secret_hash, $context, $scope
    );

    # A user who changed their password because they suspected a compromise
    # has every other device signed out. The session they are typing in is
    # kept, when the caller says which one it is.
    my $revoked = await $self->session_store->revoke_user_sessions_p(
        $self->support->column( $user, 'id' ),
        $self->clock->now_iso8601,
        $input->{keep_session_id},
        $context, $scope
    );
    my $withdrawn =
      await $self->withdraw_email_change_p( $user, $context, $scope );
    await $self->record_user_action_p(
        $user,
        'identity.password.changed',
        {
            email_change_withdrawn => $withdrawn,
            revoked_sessions       => $revoked,
        },
        $context, $scope
    );

    return { ok => 1, revoked_sessions => $revoked, user => $user };
}

sub _same_password ($input) {
    return secure_compare( $input->{new_password}, $input->{current_password} );
}

# The credential locked now is the one the current password verified.
sub _still_verified ( $self, $current, $verified ) {
    return 0 if !$current;

    return $self->support->column( $current, 'id' ) eq
      $self->support->column( $verified, 'id' ) ? 1 : 0;
}

# The new password becomes the active credential and the user row's hash:
# the one given, or the password hashed here.
async sub _store_password_p ( $self, $user, $password, $now,
    $secret_hash, $context, $scope )
{
    $secret_hash //= await $self->hashed_password_p( $password, $scope );
    await $self->credential_store->rotate_password_credential_p(
        {
            secret_hash => $secret_hash,
            user_id     => $self->support->column( $user, 'id' ),
        },
        $context, $scope
    );
    await $user->update_p(
        {
            password_hash => $secret_hash,
            updated_at    => $now,
        },
        $context, $scope
    );

    return;
}

1;

__END__

=head1 NAME

GPForum::Service::Identity::Account::Passwords - Password reset and change.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    # Part of GPForum::Service::Identity::AccountStore; callers use that class.

=head1 DESCRIPTION

Request and complete a password reset, and change a password given the
current one. Each is written once, as its promise method; the blocking
method is its twin (ADR 0177).

GPForum::Service::Identity::AccountStore inherits it, so the object a caller builds has every method; this
file holds one part of that class so each part can be read by itself.

=head1 SUBROUTINES/METHODS

Every C<_p> method takes the input, an optional query context and an
optional call layer (the transaction a command log holds); its writes
commit in one transaction of that layer, or of the store's own.

=head2 request_password_reset_p

Issues a reset token without revealing whether the identifier exists.

=head2 reset_password_p

Consumes a reset token and rotates the password credential. A reset to
the same secret still consumes the token and revokes sessions, but does
not rotate the credential. The member's active credential is locked
before it is compared, so a reset that waited for a concurrent change
replaces the password that change set. It withdraws the member's pending
email change, as a change of password does, and its audit says whether
there was one (C<email_change_withdrawn>).
The token's address must still be the member's recovery address; a reset
sent to an address that an email confirmation has replaced is refused as
C<invalid_token>. The new password is hashed in a child of the CPU lane,
or in the process on the blocking layer.

=head2 change_password_p

Rotates the password for an authenticated member. A second write of the
same secret answers C<skipped> and does not rotate the credential. The
current password is verified and the new one hashed before the
transaction, against the active credential; the transaction locks the
active credential and answers C<invalid_current_password> when it is no
longer the one verified, because a reset or another change replaced it in
between. A change withdraws the member's pending email change, as a reset
does.

=head2 request_password_reset, reset_password, change_password

The blocking twins: each is its C<_p> method run on the blocking call layer
(ADR 0177), answering the value instead of a promise.

=head1 DIAGNOSTICS

As GPForum::Service::Identity::AccountStore.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

As GPForum::Service::Identity::AccountStore.

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
