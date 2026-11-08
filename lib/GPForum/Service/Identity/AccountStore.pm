# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Identity::AccountStore;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -signatures, -async_await;
use v5.40;
use Mojo::Util qw(secure_compare);

use GPForum::Infrastructure::SqlFunction;
use GPForum::Infrastructure::ResultRow;
use GPForum::Infrastructure::ResultRow::IdentityUser;

use GPForum::Infrastructure::Text qw(has_text);
use GPForum::Infrastructure::UniqueConflict;
use GPForum::Service::Clock;
use GPForum::Service::Identity::Support;
use GPForum::X::Conflict;

our $VERSION = '0.001';

const my $USER_AGGREGATE               => 'user';
const my $DAY_SECONDS                  => 86_400;
const my $HOUR_SECONDS                 => 3_600;
const my $PASSWORD_RESET_TOKEN_SECONDS => $HOUR_SECONDS;
const my $EMAIL_CHANGE_TOKEN_SECONDS   => $DAY_SECONDS;
const my $MINIMUM_PASSWORD_LENGTH      => 12;
const my $EMAIL_CONSTRAINT             => 'users_email_normalized_key';

__PACKAGE__->requires(
    qw(audit credential_store password schema session_store token_store));
has clock   => sub { return GPForum::Service::Clock->new; };
has support => sub { return GPForum::Service::Identity::Support->new; };

has functions => \&GPForum::Infrastructure::SqlFunction::for_service;

# Each write below has a twin, METHOD_p, on the worker's pooled
# asynchronous connections: it takes the input, an optional query context
# and an optional call layer to write on (the transaction a command log
# holds), and runs the same steps in one transaction of that layer, Argon2
# in a child of the CPU lane. Without the function layer (a double) the
# blocking write answers.

sub request_password_reset ( $self, $input ) {
    return $self->schema->txn_do(
        sub {
            return $self->_password_reset_in_txn($input);
        }
    );
}

async sub request_password_reset_p (
    $self, $input,
    $context = undef,
    $scope = undef
  )
{
    $scope //= $self->functions;
    return $self->request_password_reset($input) if !$scope;

    return await $self->_in_transaction_p(
        $scope, $context,
        sub ($transaction) {
            return $self->_password_reset_p( $input, $context, $transaction );
        }
    );
}

sub reset_password ( $self, $input ) {
    my $password_error = $self->_password_error( $input->{password} );
    if ($password_error) {
        return { error => $password_error, ok => 0 };
    }

    return $self->schema->txn_do(
        sub {
            return $self->_reset_password_in_txn($input);
        }
    );
}

async sub reset_password_p ( $self, $input, $context = undef, $scope = undef ) {
    $scope //= $self->functions;
    return $self->reset_password($input) if !$scope;
    my $password_error = $self->_password_error( $input->{password} );
    return { error => $password_error, ok => 0 } if $password_error;

    return await $self->_in_transaction_p(
        $scope, $context,
        sub ($transaction) {
            return $self->_reset_password_p( $input, $context, $transaction );
        }
    );
}

sub change_password ( $self, $input ) {
    my $password_error = $self->_password_error( $input->{new_password} );
    if ($password_error) {
        return { error => $password_error, ok => 0 };
    }
    my $user = $self->_find_user_by_id( $input->{user_id} );
    if ( !$user ) {
        return { error => 'not_found', ok => 0 };
    }
    my $verified = $self->credential_store->active_password_credential(
        $self->support->column( $user, 'id' ) );
    if ( !$self->_credential_matches( $verified, $input->{current_password} ) )
    {
        return { error => 'invalid_current_password', ok => 0 };
    }

    # The new password is hashed here, before the transaction: Argon2 under
    # the credential's lock kept a sign-in of the same member waiting for it.
    my $secret_hash =
      _same_password($input)
      ? undef
      : $self->password->hash_password( $input->{new_password} );

    return $self->schema->txn_do(
        sub {
            return $self->_change_password_in_txn( $user, $input, $verified,
                $secret_hash );
        }
    );
}

async sub change_password_p ( $self, $input, $context = undef, $scope = undef )
{
    $scope //= $self->functions;
    return $self->change_password($input) if !$scope;
    my $password_error = $self->_password_error( $input->{new_password} );
    return { error => $password_error, ok => 0 } if $password_error;
    my $user =
      await $self->_find_user_by_id_p( $input->{user_id}, $context, $scope );
    return { error => 'not_found', ok => 0 } if !$user;
    my $verified =
      await $self->credential_store->active_password_credential_p(
        $self->support->column( $user, 'id' ),
        $context, $scope );
    return { error => 'invalid_current_password', ok => 0 }
      if !await $self->_credential_matches_p( $verified,
        $input->{current_password} );

    # Hashed before the credential is locked, as change_password hashes it.
    my $secret_hash =
      _same_password($input)
      ? undef
      : await $self->password->hash_password_p( $input->{new_password} );

    return await $self->_in_transaction_p(
        $scope, $context,
        sub ($transaction) {
            return $self->_change_password_p(
                $user,        $input,   $verified,
                $secret_hash, $context, $transaction
            );
        }
    );
}

# The member's current password is checked first, as a change of password
# checks it: a session alone, one left open or stolen, moved the account to
# an address of its holder's, and from there a password reset took the rest.
# It is checked before the address is looked up, so a wrong one does not
# learn whose address is whose. An address the member already confirmed is
# skipped; one another member holds is refused before any token is issued.
sub request_email_change ( $self, $input ) {
    my $email       = $self->support->normalize_identifier( $input->{email} );
    my $email_error = $self->_email_error($email);
    if ($email_error) {
        return { error => $email_error, ok => 0 };
    }
    my $user = $self->_find_user_by_id( $input->{user_id} );
    if ( !$user ) {
        return { error => 'not_found', ok => 0 };
    }
    my $verified = $self->credential_store->active_password_credential(
        $self->support->column( $user, 'id' ) );
    if ( !$self->_credential_matches( $verified, $input->{current_password} ) )
    {
        return { error => 'invalid_current_password', ok => 0 };
    }
    return $self->schema->txn_do(
        sub {
            return $self->_request_email_change_in_txn( $user, $email, $input,
                $verified );
        }
    );
}

async sub request_email_change_p ( $self, $input, $context = undef,
    $scope = undef )
{
    $scope //= $self->functions;
    return $self->request_email_change($input) if !$scope;
    my $email       = $self->support->normalize_identifier( $input->{email} );
    my $email_error = $self->_email_error($email);
    return { error => $email_error, ok => 0 } if $email_error;
    my $user =
      await $self->_find_user_by_id_p( $input->{user_id}, $context, $scope );
    return { error => 'not_found', ok => 0 } if !$user;
    my $verified =
      await $self->credential_store->active_password_credential_p(
        $self->support->column( $user, 'id' ),
        $context, $scope );
    return { error => 'invalid_current_password', ok => 0 }
      if !await $self->_credential_matches_p( $verified,
        $input->{current_password} );

    return await $self->_in_transaction_p(
        $scope, $context,
        sub ($transaction) {
            return $self->_request_email_change_p( $user, $email, $input,
                $verified, $context, $transaction );
        }
    );
}

sub confirm_email_change ( $self, $input ) {
    return $self->schema->txn_do(
        sub {
            return $self->_confirm_email_change_in_txn($input);
        }
    );
}

async sub confirm_email_change_p ( $self, $input, $context = undef,
    $scope = undef )
{
    $scope //= $self->functions;
    return $self->confirm_email_change($input) if !$scope;

    return await $self->_in_transaction_p(
        $scope, $context,
        sub ($transaction) {
            return $self->_confirm_email_change_p( $input, $context,
                $transaction );
        }
    );
}

# The work in the transaction $scope holds, or in one of its own when
# $scope is the call layer itself.
sub _in_transaction_p ( $self, $scope, $context, $work ) {
    return $work->($scope) if $scope->async_transaction;

    return $scope->transaction_p( $work, $context );
}

# An unknown or deleted account is audited as not found and answered like a
# found one, so the answer does not tell who has an account.
sub _password_reset_in_txn ( $self, $input ) {
    my $user = $self->_find_login_user(
        $self->support->normalize_identifier( $input->{identifier} ) );
    if ( !$user || $self->_deleted_user($user) ) {
        return $self->_audit_not_found( 'identity.password_reset.requested',
            $input );
    }

    # Confirmation withdraws reset links under the credential lock. A reset
    # request takes it too, then reloads the address, so it cannot issue a
    # link to the replaced address after that withdrawal has committed.
    my $user_id = $self->support->column( $user, 'id' );
    $self->credential_store->lock_active_password_credentials($user_id);
    $user = $self->_find_user_by_id($user_id);
    if ( !$user || $self->_deleted_user($user) ) {
        return $self->_audit_not_found( 'identity.password_reset.requested',
            $input );
    }

    my $token = $self->token_store->create_token(
        $self->_reset_token_input( $user, $input ) );
    $self->_record_user_action(
        $user,
        'identity.password_reset.requested',
        $self->_issued_metadata( $input, $token )
    );
    $self->_queue_issued_mail( $user, $self->_reset_mail( $user, $token ) );

    return $self->_issued_answer( $user, $token );
}

async sub _password_reset_p ( $self, $input, $context, $scope ) {
    my $user = await $self->_find_login_user_p(
        $self->support->normalize_identifier( $input->{identifier} ),
        $context, $scope );
    if ( !$user || $self->_deleted_user($user) ) {
        return await $self->_audit_not_found_p(
            'identity.password_reset.requested',
            $input, $context, $scope );
    }

    # Locked and read again, as _password_reset_in_txn does.
    my $user_id = $self->support->column( $user, 'id' );
    await $self->credential_store->lock_active_password_credentials_p( $user_id,
        $context, $scope );
    $user = await $self->_find_user_by_id_p( $user_id, $context, $scope );
    if ( !$user || $self->_deleted_user($user) ) {
        return await $self->_audit_not_found_p(
            'identity.password_reset.requested',
            $input, $context, $scope );
    }

    my $token =
      await $self->token_store->create_token_p(
        $self->_reset_token_input( $user, $input ),
        $context, $scope );
    await $self->_record_user_action_p(
        $user,
        'identity.password_reset.requested',
        $self->_issued_metadata( $input, $token ),
        $context, $scope
    );
    await $self->_queue_issued_mail_p( $user,
        $self->_reset_mail( $user, $token ),
        $context, $scope );

    return $self->_issued_answer( $user, $token );
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

sub _issued_metadata ( $self, $input, $token ) {
    return {
        outcome              => 'issued',
        request_address_hash =>
          $self->support->hash_value( $input->{request_address} ),
        token_id => $token->{token_id},
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

sub _issued_answer ( $self, $user, $token ) {
    return {
        email_normalized => $self->support->column( $user, 'email_normalized' ),
        ok               => 1,
        token            => $token,
    };
}

sub _audit_not_found ( $self, $action, $input ) {
    $self->audit->record_action( $self->_not_found_action( $action, $input ) );

    return { ok => 1, token => undef };
}

async sub _audit_not_found_p ( $self, $action, $input, $context, $scope ) {
    await $self->audit->record_action_p(
        $self->_not_found_action( $action, $input ),
        $context, $scope );

    return { ok => 1, token => undef };
}

sub _not_found_action ( $self, $action, $input ) {
    return {
        action   => $action,
        actor_id => undef,
        metadata => {
            identifier_hash =>
              $self->support->hash_value( $input->{identifier} ),
            outcome              => 'not_found',
            request_address_hash =>
              $self->support->hash_value( $input->{request_address} ),
        },
        target_id   => undef,
        target_type => 'identity',
    };
}

# A reset to the password the member already has keeps the credential; the
# sessions are revoked either way. The password is compared with the one the
# member has under the lock the rotation takes, so a change committed in the
# meantime is the one compared and then replaced. It is hashed under the lock
# too, not before it as a change hashes it: the token is checked in this
# transaction, and hashing first would spend Argon2 on every invalid token.
sub _reset_password_in_txn ( $self, $input ) {
    my $token =
      $self->_consume_account_token( 'password_reset', $input->{token} );
    if ( !$token->{ok} ) {
        return $token;
    }
    my $user = $self->_find_user_by_id( $token->{user_id} );
    if ( !$self->_reset_address_held( $token, $user ) ) {
        return { error => 'invalid_token', ok => 0 };
    }

    my $current = $self->_locked_password($user);
    my $now     = $self->clock->now_iso8601;
    my $same    = $self->_credential_matches( $current, $input->{password} );
    if ( !$same ) {
        $self->_store_password( $user, $input->{password}, $now );
    }
    $self->session_store->revoke_user_sessions(
        $self->support->column( $user, 'id' ), $now );
    $self->_record_user_action(
        $user,
        'identity.password_reset.completed',
        {
            email_change_withdrawn => $self->_withdraw_email_change($user),
            token_id               => $token->{token_id},
        }
    );

    return {
        ok      => 1,
        skipped => $same,
        user    => $user,
    };
}

async sub _reset_password_p ( $self, $input, $context, $scope ) {
    my $token =
      await $self->_consume_account_token_p( 'password_reset', $input->{token},
        $context, $scope );
    return $token if !$token->{ok};
    my $user =
      await $self->_find_user_by_id_p( $token->{user_id}, $context, $scope );
    return { error => 'invalid_token', ok => 0 }
      if !$self->_reset_address_held( $token, $user );

    my $current = await $self->_locked_password_p( $user, $context, $scope );
    my $now     = $self->clock->now_iso8601;
    my $same =
      await $self->_credential_matches_p( $current, $input->{password} );
    if ( !$same ) {
        await $self->_store_password_p( $user, $input->{password}, $now, undef,
            $context, $scope );
    }
    await $self->session_store->revoke_user_sessions_p(
        $self->support->column( $user, 'id' ),
        $now, undef, $context, $scope );
    my $withdrawn =
      await $self->_withdraw_email_change_p( $user, $context, $scope );
    await $self->_record_user_action_p(
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

# The current password was verified before this transaction, against the
# credential active then. A reset or another change that committed in
# between replaced that credential, and the change went on all the same: it
# rotated the new password away, so whoever knew the old one -- the reason
# for a reset -- set the last password and kept the account, and a change
# that waited for another one reported success with a password that was not
# stored. It goes on only while the credential it verified is the member's,
# locked until it commits; otherwise the current password it was given is no
# longer the current one.
sub _change_password_in_txn ( $self, $user, $input, $verified, $secret_hash ) {
    my $current = $self->_locked_password($user);
    if ( !$self->_still_verified( $current, $verified ) ) {
        return { error => 'invalid_current_password', ok => 0 };
    }

    # $current is the credential the current password matched, so the new
    # password matches it exactly when it is the current one: compared as
    # text, in constant time, where verifying it against the hash was a
    # second Argon2 run (tens of milliseconds) under the row's lock.
    if ( _same_password($input) ) {
        return {
            ok      => 1,
            skipped => 1,
            user    => $user,
        };
    }

    $self->_store_password(
        $user,
        $input->{new_password},
        $self->clock->now_iso8601, $secret_hash
    );

    # A password reset already did this. A change did not, so a user who
    # changed their password because they suspected a compromise left every
    # other device signed in. The session they are typing in is kept, when the
    # caller says which one it is.
    my $revoked = $self->session_store->revoke_user_sessions(
        $self->support->column( $user, 'id' ),
        $self->clock->now_iso8601,
        $input->{keep_session_id}
    );
    $self->_record_user_action(
        $user,
        'identity.password.changed',
        {
            email_change_withdrawn => $self->_withdraw_email_change($user),
            revoked_sessions       => $revoked,
        }
    );

    return { ok => 1, revoked_sessions => $revoked, user => $user };
}

async sub _change_password_p ( $self, $user, $input, $verified,
    $secret_hash, $context, $scope )
{
    my $current = await $self->_locked_password_p( $user, $context, $scope );
    return { error => 'invalid_current_password', ok => 0 }
      if !$self->_still_verified( $current, $verified );
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
    my $revoked = await $self->session_store->revoke_user_sessions_p(
        $self->support->column( $user, 'id' ),
        $self->clock->now_iso8601,
        $input->{keep_session_id},
        $context, $scope
    );
    my $withdrawn =
      await $self->_withdraw_email_change_p( $user, $context, $scope );
    await $self->_record_user_action_p(
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
sub _store_password ( $self, $user, $password, $now, $secret_hash = undef ) {
    $secret_hash //= $self->password->hash_password($password);
    $self->credential_store->rotate_password_credential(
        {
            secret_hash => $secret_hash,
            user_id     => $self->support->column( $user, 'id' ),
        }
    );
    $self->support->update_row(
        $user,
        {
            password_hash => $secret_hash,
            updated_at    => $now,
        }
    );

    return;
}

async sub _store_password_p ( $self, $user, $password, $now,
    $secret_hash, $context, $scope )
{
    $secret_hash //= await $self->password->hash_password_p($password);
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

sub _request_email_change_in_txn ( $self, $user, $email, $input, $verified ) {
    my $current = $self->_locked_password($user);
    if ( !$self->_still_verified( $current, $verified ) ) {
        return { error => 'invalid_current_password', ok => 0 };
    }

    # A confirmation can have replaced the address while the password was
    # verified. Read it again under the credential lock, which confirmation
    # also takes, before deciding whether to issue or where to send notice.
    $user = $self->_find_user_by_id( $input->{user_id} );
    if ( !$user ) {
        return { error => 'not_found', ok => 0 };
    }
    if ( $self->_email_already_confirmed( $user, $email ) ) {
        return _confirmed_answer($email);
    }
    if ( $self->_email_taken( $email, $input->{user_id} ) ) {
        return { error => 'email_already_registered', ok => 0 };
    }

    my $token = $self->token_store->create_token(
        $self->_email_change_token_input( $user, $email, $input ) );
    $self->_record_user_action(
        $user,
        'identity.email_change.requested',
        $self->_email_change_metadata( $email, $token )
    );
    $self->_queue_issued_mail( $user,
        $self->_email_change_mail( $user, $email, $token ) );
    $self->_queue_change_notice( $user, $email, $token );

    return {
        email_normalized => $email,
        ok               => 1,
        token            => $token,
    };
}

async sub _request_email_change_p ( $self, $user, $email, $input,
    $verified, $context, $scope )
{
    my $current = await $self->_locked_password_p( $user, $context, $scope );
    return { error => 'invalid_current_password', ok => 0 }
      if !$self->_still_verified( $current, $verified );

    # Read again under the lock, as _request_email_change_in_txn reads it.
    $user =
      await $self->_find_user_by_id_p( $input->{user_id}, $context, $scope );
    return { error => 'not_found', ok => 0 } if !$user;
    return _confirmed_answer($email)
      if $self->_email_already_confirmed( $user, $email );
    return { error => 'email_already_registered', ok => 0 }
      if await $self->_email_taken_p( $email, $input->{user_id}, $context,
        $scope );

    my $token =
      await $self->token_store->create_token_p(
        $self->_email_change_token_input( $user, $email, $input ),
        $context, $scope );
    await $self->_record_user_action_p(
        $user,
        'identity.email_change.requested',
        $self->_email_change_metadata( $email, $token ),
        $context, $scope
    );
    await $self->_queue_issued_mail_p( $user,
        $self->_email_change_mail( $user, $email, $token ),
        $context, $scope );
    await $self->_queue_change_notice_p( $user, $email, $token, $context,
        $scope );

    return {
        email_normalized => $email,
        ok               => 1,
        token            => $token,
    };
}

sub _confirmed_answer ($email) {
    return {
        email_normalized => $email,
        ok               => 1,
        skipped          => 1,
    };
}

sub _email_change_token_input ( $self, $user, $email, $input ) {
    return {
        email_normalized => $email,
        metadata         => {
            request_address_hash =>
              $self->support->hash_value( $input->{request_address} ),
        },
        token_type  => 'email_change',
        ttl_seconds => $EMAIL_CHANGE_TOKEN_SECONDS,
        user_id     => $self->support->column( $user, 'id' ),
    };
}

sub _email_change_metadata ( $self, $email, $token ) {
    return {
        email_hash => $self->support->hash_value($email),
        token_id   => $token->{token_id},
    };
}

sub _email_change_mail ( $self, $user, $email, $token ) {
    return {
        kind   => 'email_change',
        locale => $self->support->column( $user, 'preferred_locale' ),
        to     => $email,
        token  => $token,
    };
}

# The address the account is leaving is told, in the member's language, and
# how to stop it: a password reset, which comes to that address for as long
# as the change is not confirmed, signs every device out and withdraws the
# change (ADR 0143). The notice carries no token: one left in a mailbox the
# member may be leaving would outlive the change.
sub _queue_change_notice ( $self, $user, $email, $token ) {
    my $notice = $self->_change_notice( $user, $email, $token ) or return;
    $self->audit->record_mail($notice);

    return;
}

async sub _queue_change_notice_p ( $self, $user, $email, $token, $context,
    $scope )
{
    my $notice = $self->_change_notice( $user, $email, $token ) or return;
    await $self->audit->record_mail_p( $notice, $context, $scope );

    return;
}

sub _change_notice ( $self, $user, $email, $token ) {
    my $current = $self->support->column( $user, 'email_normalized' );
    return undef if !has_text($current) || $current eq $email;

    return {
        kind     => 'email_change_notice',
        locale   => $self->support->column( $user, 'preferred_locale' ),
        to       => $current,
        token_id => $token->{token_id},
        user_id  => $self->support->column( $user, 'id' ),
    };
}

# A pending email change stops with the password that asked for it: a reset
# or a change of password withdraws it, so the address it named cannot take
# the account after the member took the password back.
sub _withdraw_email_change ( $self, $user ) {
    return $self->token_store->withdraw_open_token(
        $self->support->column( $user, 'id' ),
        'email_change' );
}

sub _withdraw_email_change_p ( $self, $user, $context, $scope ) {
    return $self->token_store->withdraw_open_token_p(
        $self->support->column( $user, 'id' ),
        'email_change', $context, $scope );
}

sub request_email_verification ( $self, $input ) {
    return $self->schema->txn_do(
        sub {
            return $self->_email_verification_in_txn($input);
        }
    );
}

async sub request_email_verification_p (
    $self, $input,
    $context = undef,
    $scope = undef
  )
{
    $scope //= $self->functions;
    return $self->request_email_verification($input) if !$scope;

    return await $self->_in_transaction_p(
        $scope, $context,
        sub ($transaction) {
            return $self->_email_verification_p( $input, $context,
                $transaction );
        }
    );
}

sub confirm_email_verification ( $self, $input ) {
    return $self->schema->txn_do(
        sub {
            return $self->_confirm_email_verification_in_txn($input);
        }
    );
}

async sub confirm_email_verification_p (
    $self, $input,
    $context = undef,
    $scope = undef
  )
{
    $scope //= $self->functions;
    return $self->confirm_email_verification($input) if !$scope;

    return await $self->_in_transaction_p(
        $scope, $context,
        sub ($transaction) {
            return $self->_confirm_email_verification_p( $input, $context,
                $transaction );
        }
    );
}

# The member is named by id when signed in, by username or address when not.
# Only a pending account is sent a verification; any other is audited as not
# found, like an unknown one.
# What a verification request writes for an account, prepared and not
# sent, in the order _email_verification_in_txn draws it: the token issued
# (its row for api.identity_insert_token, its raw text for the mail), the
# audit of the request, and the mail's event with its outbox payload. For
# api.identity_register_command, which records them in one call with the
# registration.
sub verification_calls ( $self, $user, $input ) {
    my $user_id = $self->support->column( $user, 'id' );
    my $email   = $self->support->column( $user, 'email_normalized' );
    my $address = $self->support->hash_value( $input->{request_address} );
    my $issue   = $self->token_store->new_token_issue(
        $self->_verification_token_input( $user, $input ) );
    my $audit = $self->audit->action_call(
        {
            action   => 'identity.email_verification.requested',
            actor_id => $user_id,
            metadata => {
                outcome              => 'issued',
                request_address_hash => $address,
                token_id             => $issue->{token_id},
            },
            target_id   => $user_id,
            target_type => $USER_AGGREGATE,
        }
    );
    my $mail = $self->audit->mail_call(
        {
            kind     => 'email_verification',
            to       => $email,
            token    => $issue->{raw_token},
            token_id => $issue->{token_id},
            user_id  => $user_id,
        }
    );
    return {
        mail      => $mail,
        raw_token => $issue->{raw_token},
        token     => $issue->{row},
        audit     => $audit,
    };
}

sub _email_verification_in_txn ( $self, $input ) {
    my $user =
      has_text( $input->{user_id} )
      ? $self->_find_user_by_id( $input->{user_id} )
      : $self->_find_login_user(
        $self->support->normalize_identifier( $input->{identifier} ) );
    if ( !$self->_verifiable($user) ) {
        return $self->_audit_not_found( 'identity.email_verification.requested',
            $input );
    }

    my $token = $self->token_store->create_token(
        $self->_verification_token_input( $user, $input ) );
    $self->_record_user_action(
        $user,
        'identity.email_verification.requested',
        $self->_issued_metadata( $input, $token )
    );
    $self->_queue_issued_mail( $user,
        $self->_verification_mail( $user, $token ) );

    return $self->_issued_answer( $user, $token );
}

async sub _email_verification_p ( $self, $input, $context, $scope ) {
    my $user =
      has_text( $input->{user_id} )
      ? await $self->_find_user_by_id_p( $input->{user_id}, $context, $scope )
      : await $self->_find_login_user_p(
        $self->support->normalize_identifier( $input->{identifier} ),
        $context, $scope );
    if ( !$self->_verifiable($user) ) {
        return await $self->_audit_not_found_p(
            'identity.email_verification.requested',
            $input, $context, $scope );
    }

    my $token =
      await $self->token_store->create_token_p(
        $self->_verification_token_input( $user, $input ),
        $context, $scope );
    await $self->_record_user_action_p(
        $user,
        'identity.email_verification.requested',
        $self->_issued_metadata( $input, $token ),
        $context, $scope
    );
    await $self->_queue_issued_mail_p( $user,
        $self->_verification_mail( $user, $token ),
        $context, $scope );

    return $self->_issued_answer( $user, $token );
}

# A pending account, neither unknown nor deleted.
sub _verifiable ( $self, $user ) {
    return
         $user
      && !$self->_deleted_user($user)
      && $self->_pending_user($user)
      ? 1
      : 0;
}

sub _verification_token_input ( $self, $user, $input ) {
    return {
        email_normalized => $self->support->column( $user, 'email_normalized' ),
        metadata         => {
            request_address_hash =>
              $self->support->hash_value( $input->{request_address} ),
        },
        token_type  => 'email_verification',
        ttl_seconds => $EMAIL_CHANGE_TOKEN_SECONDS,
        user_id     => $self->support->column( $user, 'id' ),
    };
}

sub _verification_mail ( $self, $user, $token ) {
    return {
        kind  => 'email_verification',
        to    => $self->support->column( $user, 'email_normalized' ),
        token => $token,
    };
}

sub _confirm_email_verification_in_txn ( $self, $input ) {
    my $token =
      $self->token_store->consume_token( 'email_verification',
        $input->{token} );
    if ( !$token->{ok} ) {
        return $token;
    }
    my $user = $self->_find_user_by_id( $token->{user_id} );
    if ( !$user ) {
        return { error => 'invalid_token', ok => 0 };
    }
    if ( $self->_already_verified($user) ) {
        return _skipped_answer($user);
    }

    my $now = $self->clock->now_iso8601;
    $self->support->update_row( $user, _verified_values($now) );
    $self->_record_user_action(
        $user,
        'identity.email_verification.confirmed',
        { token_id => $token->{token_id} }
    );

    return { ok => 1, user => $user };
}

async sub _confirm_email_verification_p ( $self, $input, $context, $scope ) {
    my $token =
      await $self->token_store->consume_token_p( 'email_verification',
        $input->{token}, $context, $scope );
    return $token if !$token->{ok};
    my $user =
      await $self->_find_user_by_id_p( $token->{user_id}, $context, $scope );
    return { error => 'invalid_token', ok => 0 } if !$user;
    return _skipped_answer($user) if $self->_already_verified($user);

    await $user->update_p( _verified_values( $self->clock->now_iso8601 ),
        $context, $scope );
    await $self->_record_user_action_p(
        $user,
        'identity.email_verification.confirmed',
        { token_id => $token->{token_id} },
        $context, $scope
    );

    return { ok => 1, user => $user };
}

sub _verified_values ($now) {
    return {
        email_verified_at => $now,
        status            => 'active',
        updated_at        => $now,
    };
}

sub _skipped_answer ($user) {
    return {
        ok      => 1,
        skipped => 1,
        user    => $user,
    };
}

sub _already_verified ( $self, $user ) {
    if ( $self->_pending_user($user) ) {
        return 0;
    }
    if ( !defined $self->support->column( $user, 'email_verified_at' ) ) {
        return 0;
    }

    return 1;
}

sub _pending_user ( $self, $user ) {
    my $status = $self->support->column( $user, 'status' ) || q{};
    return $status eq 'pending' ? 1 : 0;
}

sub _confirm_email_change_in_txn ( $self, $input ) {
    my $token =
      $self->_consume_account_token( 'email_change', $input->{token} );
    if ( !$token->{ok} ) {
        return $token;
    }
    my $email = $token->{email_normalized};
    if ( !$email ) {
        return { error => 'invalid_token', ok => 0 };
    }
    if ( $self->_email_taken( $email, $token->{user_id} ) ) {
        return { error => 'email_already_registered', ok => 0 };
    }
    my $user = $self->_find_user_by_id( $token->{user_id} );
    if ( !$user ) {
        return { error => 'invalid_token', ok => 0 };
    }
    if ( $self->_email_already_confirmed( $user, $email ) ) {
        return _skipped_answer($user);
    }

    return $self->_store_confirmed_email( $user, $email, $token );
}

async sub _confirm_email_change_p ( $self, $input, $context, $scope ) {
    my $token =
      await $self->_consume_account_token_p( 'email_change', $input->{token},
        $context, $scope );
    return $token if !$token->{ok};
    my $email = $token->{email_normalized};
    return { error => 'invalid_token',            ok => 0 } if !$email;
    return { error => 'email_already_registered', ok => 0 }
      if await $self->_email_taken_p( $email, $token->{user_id}, $context,
        $scope );
    my $user =
      await $self->_find_user_by_id_p( $token->{user_id}, $context, $scope );
    return { error => 'invalid_token', ok => 0 } if !$user;
    return _skipped_answer($user)
      if $self->_email_already_confirmed( $user, $email );

    return await $self->_store_confirmed_email_p( $user, $email, $token,
        $context, $scope );
}

# Password changes withdraw a pending email token while holding the
# credential. Resets and confirmations take that same lock before their
# token, or a confirmation holding the token can deadlock with a withdrawal.
# The owner lookup is only a hint for ordering locks; consume_token reads the
# token again under its own lock and keeps the used/expired error contract.
sub _consume_account_token ( $self, $type, $raw_token ) {
    my $owner = $self->token_store->token_user_id( $type, $raw_token );
    if ( has_text($owner) ) {
        $self->credential_store->lock_active_password_credentials($owner);
    }

    return _owned_token( $owner,
        $self->token_store->consume_token( $type, $raw_token ) );
}

async sub _consume_account_token_p ( $self, $type, $raw_token, $context,
    $scope )
{
    my $owner =
      await $self->token_store->token_user_id_p( $type, $raw_token, $context,
        $scope );
    if ( has_text($owner) ) {
        await $self->credential_store->lock_active_password_credentials_p(
            $owner, $context, $scope );
    }

    return _owned_token(
        $owner,
        await $self->token_store->consume_token_p(
            $type, $raw_token, $context, $scope
        )
    );
}

# A token consumed for another owner than the one locked for is refused.
sub _owned_token ( $owner, $token ) {
    if (
        $token->{ok}
        && ( !has_text($owner)
            || ( $token->{user_id} // q{} ) ne $owner )
      )
    {
        return { error => 'invalid_token', ok => 0 };
    }

    return $token;
}

# The address is looked up once more inside the savepoint, and a member who
# takes it after that is refused by the unique constraint: either way the
# address is taken. Any other failure, the audit's included, is rethrown.
sub _store_confirmed_email ( $self, $user, $email, $token ) {
    my $user_id = $self->support->column( $user, 'id' );
    my ( $stored, $error ) = GPForum::Infrastructure::UniqueConflict->attempt(
        $self->schema,
        sub {
            if ( $self->_email_taken( $email, $user_id ) ) {
                GPForum::Infrastructure::UniqueConflict->throw(
                    $EMAIL_CONSTRAINT);
            }
            my $now = $self->clock->now_iso8601;
            $self->support->update_row( $user,
                _confirmed_email_values( $email, $now ) );

            # An old address becoming current again must not revive links
            # issued during its previous ownership of account recovery.
            $self->token_store->withdraw_open_token( $user_id,
                'password_reset' );
            $self->_record_user_action(
                $user,
                'identity.email_change.confirmed',
                $self->_email_change_metadata( $email, $token )
            );

            return { ok => 1, user => $user };
        },
    );

    return _confirmed_email( $stored, $error );
}

async sub _store_confirmed_email_p ( $self, $user, $email, $token, $context,
    $scope )
{
    my $user_id = $self->support->column( $user, 'id' );
    my ( $stored, $error ) =
      await GPForum::Infrastructure::UniqueConflict->attempt_p(
        $scope,
        async sub ($savepoint) {
            if (
                await $self->_email_taken_p( $email, $user_id, $context,
                    $savepoint ) )
            {
                GPForum::Infrastructure::UniqueConflict->throw(
                    $EMAIL_CONSTRAINT);
            }
            await $user->update_p(
                _confirmed_email_values( $email, $self->clock->now_iso8601 ),
                $context, $savepoint );
            await $self->token_store->withdraw_open_token_p( $user_id,
                'password_reset', $context, $savepoint );
            await $self->_record_user_action_p(
                $user,
                'identity.email_change.confirmed',
                $self->_email_change_metadata( $email, $token ),
                $context, $savepoint
            );

            return { ok => 1, user => $user };
        }
      );

    return _confirmed_email( $stored, $error );
}

sub _confirmed_email_values ( $email, $now ) {
    return {
        email_normalized  => $email,
        email_verified_at => $now,
        updated_at        => $now,
    };
}

# The savepoint's answer, or the taken address it ended in; any other
# failure is rethrown.
sub _confirmed_email ( $stored, $error ) {
    return $stored if $stored;
    if ( !GPForum::X::Conflict->caught($error) ) {
        GPForum::Infrastructure::UniqueConflict->rethrow($error);
    }

    return { error => 'email_already_registered', ok => 0 };
}

sub _email_already_confirmed ( $self, $user, $email ) {
    if ( !$self->_already_verified($user) ) {
        return 0;
    }

    my $held = $self->support->column( $user, 'email_normalized' ) || q{};
    return $held eq $email ? 1 : 0;
}

sub _record_user_action ( $self, $user, $action, $metadata ) {
    $self->audit->record_action(
        $self->_user_action( $user, $action, $metadata ) );

    return;
}

async sub _record_user_action_p ( $self, $user, $action, $metadata, $context,
    $scope )
{
    await $self->audit->record_action_p(
        $self->_user_action( $user, $action, $metadata ),
        $context, $scope );

    return;
}

sub _user_action ( $self, $user, $action, $metadata ) {
    my $user_id = $self->support->column( $user, 'id' );
    return {
        action      => $action,
        actor_id    => $user_id,
        metadata    => $metadata,
        target_id   => $user_id,
        target_type => $USER_AGGREGATE,
    };
}

sub _queue_issued_mail ( $self, $user, $mail ) {
    my $issued = $self->_issued_mail( $user, $mail ) or return;
    $self->audit->record_mail($issued);

    return;
}

async sub _queue_issued_mail_p ( $self, $user, $mail, $context, $scope ) {
    my $issued = $self->_issued_mail( $user, $mail ) or return;
    await $self->audit->record_mail_p( $issued, $context, $scope );

    return;
}

# Mail is queued only with an address to send to and a raw token to send.
sub _issued_mail ( $self, $user, $mail ) {
    my $token = $mail->{token} || {};
    return undef
      if !has_text( $mail->{to} ) || !has_text( $token->{raw_token} );

    return {
        kind     => $mail->{kind},
        locale   => $mail->{locale},
        to       => $mail->{to},
        token    => $token->{raw_token},
        token_id => $token->{token_id},
        user_id  => $self->support->column( $user, 'id' ),
    };
}

sub _credential_matches ( $self, $credential, $password ) {
    if ( !$credential ) {
        return 0;
    }

    return $self->password->verify_password( $password,
        $self->support->column( $credential, 'secret_hash' ) ) ? 1 : 0;
}

# _credential_matches with Argon2 in a child of the CPU lane.
async sub _credential_matches_p ( $self, $credential, $password ) {
    return 0 if !$credential;

    return (
        await $self->password->verify_password_p(
            $password, $self->support->column( $credential, 'secret_hash' )
        )
    ) ? 1 : 0;
}

# The member's active password, locked until the transaction ends; undef
# when there is none. The partial unique index keeps it to one.
sub _locked_password ( $self, $user ) {
    my ($credential) =
      $self->credential_store->lock_active_password_credentials(
        $self->support->column( $user, 'id' ) );

    return $credential;
}

async sub _locked_password_p ( $self, $user, $context, $scope ) {
    my $locked =
      await $self->credential_store->lock_active_password_credentials_p(
        $self->support->column( $user, 'id' ),
        $context, $scope );

    return $locked->[0];
}

sub _find_user_by_id ( $self, $user_id ) {
    if ( !has_text($user_id) ) {
        return undef;
    }

    if ( $self->functions ) {
        return GPForum::Infrastructure::ResultRow::IdentityUser->from(
            $self->functions->row(
                'identity_user_by_id', { user_id => $user_id }
            ),
            $self->functions
        );
    }
    return $self->schema->resultset('User')->find( { id => $user_id } );
}

async sub _find_user_by_id_p ( $self, $user_id, $context, $scope ) {
    return undef if !has_text($user_id);

    return GPForum::Infrastructure::ResultRow::IdentityUser->from(
        await $scope->row_p(
            'identity_user_by_id', { user_id => $user_id }, $context
        ),
        $self->functions
    );
}

# An identifier with an @ is an address; any other is a username.
sub _find_login_user ( $self, $identifier ) {
    if ( !length $identifier ) {
        return undef;
    }

    if ( $self->functions ) {
        return GPForum::Infrastructure::ResultRow::IdentityUser->from(
            $self->functions->row(
                'identity_user_by_identifier', _login_lookup($identifier)
            ),
            $self->functions
        );
    }
    my $column = $identifier =~ /[@]/msx ? 'email_normalized' : 'username';
    return $self->schema->resultset('User')->find( { $column => $identifier } );
}

async sub _find_login_user_p ( $self, $identifier, $context, $scope ) {
    return undef if !length $identifier;

    return GPForum::Infrastructure::ResultRow::IdentityUser->from(
        await $scope->row_p(
            'identity_user_by_identifier', _login_lookup($identifier),
            $context
        ),
        $self->functions
    );
}

sub _login_lookup ($identifier) {
    return {
        identifier => $identifier,
        by_email   => $identifier =~ /[@]/msx ? 1 : 0
    };
}

sub _deleted_user ( $self, $user ) {
    my $status = $self->support->column( $user, 'status' ) || q{};
    return $status eq 'deleted' ? 1 : 0;
}

# Held by another member: the member's own address is not taken.
sub _email_taken ( $self, $email, $current_user_id ) {
    my $existing =
      $self->functions
      ? $self->functions->row( 'identity_user_by_identifier',
        { identifier => $email, by_email => 1 } )
      : $self->schema->resultset('User')
      ->find( { email_normalized => $email } );

    return $self->_held_by_another( $existing, $current_user_id );
}

async sub _email_taken_p ( $self, $email, $current_user_id, $context, $scope ) {
    return $self->_held_by_another(
        await $scope->row_p(
            'identity_user_by_identifier',
            { identifier => $email, by_email => 1 },
            $context
        ),
        $current_user_id
    );
}

sub _held_by_another ( $self, $existing, $current_user_id ) {
    if ( !$existing ) {
        return 0;
    }

    my $existing_id = $self->support->column( $existing, 'id' );
    if (   has_text($existing_id)
        && has_text($current_user_id)
        && $existing_id eq $current_user_id )
    {
        return 0;
    }

    return 1;
}

sub _email_error ( $, $email ) {
    if ( !length $email ) {
        return 'email_required';
    }
    if ( $email !~
        /\A [[:alnum:]._%+-]+ [@] [[:alnum:].-]+ [.] [[:alpha:]]{2,} \z/imsx )
    {
        return 'email_invalid';
    }

    return undef;
}

sub _password_error ( $, $password ) {
    if ( !defined $password || !length $password ) {
        return 'password_required';
    }
    if ( length $password < $MINIMUM_PASSWORD_LENGTH ) {
        return 'password_too_short';
    }

    return undef;
}

1;

__END__

=head1 NAME

GPForum::Service::Identity::AccountStore - Password and email account writes.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $result = $store->change_password(
        {
            current_password => $current,
            new_password     => $new,
            user_id          => $user_id,
        }
    );

=head1 DESCRIPTION

Owns password reset, password change, and email change persistence. The
identity store facade delegates these commands so HTTP and workflow callers
keep a stable API. Credential, session, token, and audit stores keep their
row-level ownership. Issued tokens enqueue C<identity.mail.requested> on
the outbox in the same transaction; EventLog payloads keep C<kind> and
C<token_id> only.

=head1 SUBROUTINES/METHODS

=head2 request_password_reset

Issues a reset token without revealing whether the identifier exists.

=head2 request_password_reset_p

Issues the reset as L</request_password_reset> does, on the worker's pooled asynchronous connections, with an optional query
context and an optional call layer (the transaction a command log holds)
last; its writes commit in one transaction of that layer.
Answers a promise of the same result.

=head2 reset_password

Consumes a reset token and rotates the password credential. A reset to
the same secret still consumes the token and revokes sessions, but does
not rotate the credential. The member's active credential is locked
before it is compared, so a reset that waited for a concurrent change
replaces the password that change set. It withdraws the member's pending
email change, as a change of password does, and its audit says whether
there was one (C<email_change_withdrawn>).
The token's address must still be the member's recovery address; a reset
sent to an address that an email confirmation has replaced is refused as
C<invalid_token>.

=head2 reset_password_p

Completes the reset as L</reset_password> does, on the worker's pooled asynchronous connections, with an optional query
context and an optional call layer (the transaction a command log holds)
last; its writes commit in one transaction of that layer; the new password
is hashed in a child of the CPU lane. Answers a promise of the same result.

=head2 change_password

Rotates the password for an authenticated member. A second write of the
same secret returns C<skipped> and does not rotate the credential. The
current password is verified before the transaction, against the active
credential; the transaction locks the active credential and answers
C<invalid_current_password> when it is no longer the one verified, because
a reset or another change replaced it in between. A change withdraws the
member's pending email change, as a reset does.

=head2 change_password_p

Changes the password as L</change_password> does, on the worker's pooled asynchronous connections, with an optional query
context and an optional call layer (the transaction a command log holds)
last; its writes commit in one transaction of that layer. The current
password is verified and the new one hashed in a child of the CPU lane,
before the credential is locked. Answers a promise of the same result.

=head2 request_email_change

Takes C<current_password> with the address and the member, and answers
C<invalid_current_password> when it is not the member's, before the address
is looked up, or when a concurrent password rotation replaced the credential
it verified before the transaction. Issues an email-change token when the
address is available, mailed to that address, and queues C<email_change_notice> to the address
the member has, in their C<preferred_locale>, about the same token and
carrying none (ADR 0143). A request for the member's already-verified
address returns C<skipped> and does not issue a token.

=head2 request_email_change_p

Requests the change as L</request_email_change> does, on the worker's pooled asynchronous connections, with an optional query
context and an optional call layer (the transaction a command log holds)
last; its writes commit in one transaction of that layer; the
current password is verified in a child of the CPU lane. Answers a promise
of the same result.

=head2 confirm_email_change

Consumes an email-change token and updates the user row. A second
confirmation of the same already-verified address returns C<skipped>
and does not restamp C<email_verified_at>. A unique race on
C<email_normalized> returns C<email_already_registered> and does not
restamp the user.
A successful address replacement withdraws open password-reset tokens, so
returning to an old address cannot revive links issued before it was replaced.

=head2 confirm_email_change_p

Confirms the change as L</confirm_email_change> does, on the worker's pooled asynchronous connections, with an optional query
context and an optional call layer (the transaction a command log holds)
last; its writes commit in one transaction of that layer, the address
written in a savepoint. Answers a promise of the same result.

=head2 verification_calls

Takes the user row and the request and returns what
L</request_email_verification> would write for the account, prepared and
not sent, in the order it would draw it: C<token>, the token's row;
C<raw_token>, its text for the mail; C<audit>, the request's audit call;
C<mail>, the mail's event call with its outbox payload. For a command that
records them in one call with the registration
(C<api.identity_register_command>).

=head2 request_email_verification

Issues a registration verification token for a pending user without
revealing whether the identifier exists.

=head2 request_email_verification_p

Issues the verification as L</request_email_verification> does, on the worker's pooled asynchronous connections, with an optional query
context and an optional call layer (the transaction a command log holds)
last; its writes commit in one transaction of that layer.
Answers a promise of the same result.

=head2 confirm_email_verification

Consumes a verification token, marks the email verified, and activates
the user. A second confirmation for an already-active verified user
returns C<skipped> and does not restamp C<email_verified_at>.

=head2 confirm_email_verification_p

Confirms the verification as L</confirm_email_verification> does,
on the worker's pooled asynchronous connections, with an optional query
context and an optional call layer (the transaction a command log holds)
last; its writes commit in one transaction of that layer. Answers a promise of the same result.

=head1 DIAGNOSTICS

Missing users and invalid tokens return C<not_found> or C<invalid_token>.
Weak passwords return C<password_too_short>. Duplicate emails return
C<email_already_registered>. Password reset for unknown identifiers still
returns C<ok> without a token.

=head1 CONFIGURATION AND ENVIRONMENT

Requires a schema with User resultset plus credential, session, token, and
audit collaborators supplied by the identity store facade.

=head1 DEPENDENCIES

Uses L<GPForum::Infrastructure::UniqueConflict>, L<GPForum::X::Conflict> and
L<GPForum::Service::Identity::Support>.

Extends L<GPForum::Base>: built without C<audit>, C<credential_store>,
C<password>, C<schema>, C<session_store> or C<token_store> it throws
L<GPForum::X::Argument>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Password reset remains non-enumerative: unknown identifiers succeed without
issuing a token.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
