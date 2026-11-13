# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Identity::Account::EmailChange;

use Const::Fast;
use Mojo::Base 'GPForum::Service::Identity::Account::Passwords', -async_await;
use v5.40;

use GPForum::Infrastructure::SqlFunction;
use GPForum::Infrastructure::Text qw(has_text);
use GPForum::Infrastructure::UniqueConflict;
use GPForum::X::Conflict;

our $VERSION = '0.001';

const my $DAY_SECONDS                => 86_400;
const my $EMAIL_CHANGE_TOKEN_SECONDS => $DAY_SECONDS;
const my $EMAIL_CONSTRAINT           => 'users_email_normalized_key';

# Each operation is written once, as its promise method (ADR 0177).
GPForum::Infrastructure::SqlFunction->blocking_twins(
    qw(request_email_change confirm_email_change));

# The member's current password is checked first, as a change of password
# checks it: a session alone, one left open or stolen, moved the account to
# an address of its holder's, and from there a password reset took the rest.
# It is checked before the address is looked up, so a wrong one does not
# learn whose address is whose. An address the member already confirmed is
# skipped; one another member holds is refused before any token is issued.
# On $scope: the transaction a command log holds, or one of its own.
async sub request_email_change_p ( $self, $input, $context = undef,
    $scope = undef )
{
    my $email       = $self->support->normalize_identifier( $input->{email} );
    my $email_error = $self->email_error($email);
    return { error => $email_error, ok => 0 } if $email_error;
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

    return await $self->in_transaction_p(
        $scope, $context,
        sub ($transaction) {
            return $self->_request_email_change_p( $user, $email, $input,
                $verified, $context, $transaction );
        }
    );
}

# On $scope, as request_email_change_p.
async sub confirm_email_change_p ( $self, $input, $context = undef,
    $scope = undef )
{
    $scope //= $self->account_functions;

    return await $self->in_transaction_p(
        $scope, $context,
        sub ($transaction) {
            return $self->_confirm_email_change_p( $input, $context,
                $transaction );
        }
    );
}

async sub _request_email_change_p ( $self, $user, $email, $input,
    $verified, $context, $scope )
{
    my $current = await $self->locked_password_p( $user, $context, $scope );
    return { error => 'invalid_current_password', ok => 0 }
      if !$self->_still_verified( $current, $verified );

    # A confirmation can have replaced the address while the password was
    # verified. Read it again under the credential lock, which confirmation
    # also takes, before deciding whether to issue or where to send notice.
    $user =
      await $self->find_user_by_id_p( $input->{user_id}, $context, $scope );
    return { error => 'not_found', ok => 0 } if !$user;
    return _confirmed_answer($email)
      if $self->_email_already_confirmed( $user, $email );
    return { error => 'email_already_registered', ok => 0 }
      if await $self->email_taken_p( $email, $input->{user_id}, $context,
        $scope );

    my $token =
      await $self->token_store->create_token_p(
        $self->_email_change_token_input( $user, $email, $input ),
        $context, $scope );
    await $self->record_user_action_p(
        $user,
        'identity.email_change.requested',
        $self->_email_change_metadata( $email, $token ),
        $context, $scope
    );
    await $self->queue_issued_mail_p( $user,
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
async sub _queue_change_notice_p ( $self, $user, $email, $token, $context,
    $scope )
{
    my $current = $self->support->column( $user, 'email_normalized' );
    return if !has_text($current) || $current eq $email;

    await $self->audit->record_mail_p(
        {
            kind     => 'email_change_notice',
            locale   => $self->support->column( $user, 'preferred_locale' ),
            to       => $current,
            token_id => $token->{token_id},
            user_id  => $self->support->column( $user, 'id' ),
        },
        $context, $scope
    );

    return;
}

async sub _confirm_email_change_p ( $self, $input, $context, $scope ) {
    my $token =
      await $self->consume_account_token_p( 'email_change', $input->{token},
        $context, $scope );
    return $token if !$token->{ok};
    my $email = $token->{email_normalized};
    return { error => 'invalid_token',            ok => 0 } if !$email;
    return { error => 'email_already_registered', ok => 0 }
      if await $self->email_taken_p( $email, $token->{user_id}, $context,
        $scope );
    my $user =
      await $self->find_user_by_id_p( $token->{user_id}, $context, $scope );
    return { error => 'invalid_token', ok => 0 } if !$user;
    return $self->skipped_answer($user)
      if $self->_email_already_confirmed( $user, $email );

    return await $self->_store_confirmed_email_p( $user, $email, $token,
        $context, $scope );
}

# The address is looked up once more inside the savepoint, and a member who
# takes it after that is refused by the unique constraint: either way the
# address is taken. Any other failure, the audit's included, is rethrown.
async sub _store_confirmed_email_p ( $self, $user, $email, $token, $context,
    $scope )
{
    my $user_id = $self->support->column( $user, 'id' );
    my ( $stored, $error ) =
      await GPForum::Infrastructure::UniqueConflict->attempt_p(
        $scope,
        async sub ($savepoint) {
            if (
                await $self->email_taken_p( $email, $user_id, $context,
                    $savepoint ) )
            {
                GPForum::Infrastructure::UniqueConflict->throw(
                    $EMAIL_CONSTRAINT);
            }
            my $now = $self->clock->now_iso8601;
            await $user->update_p(
                {
                    email_normalized  => $email,
                    email_verified_at => $now,
                    updated_at        => $now,
                },
                $context,
                $savepoint
            );

            # An old address becoming current again must not revive links
            # issued during its previous ownership of account recovery.
            await $self->token_store->withdraw_open_token_p( $user_id,
                'password_reset', $context, $savepoint );
            await $self->record_user_action_p(
                $user,
                'identity.email_change.confirmed',
                $self->_email_change_metadata( $email, $token ),
                $context, $savepoint
            );

            return { ok => 1, user => $user };
        }
      );
    return $stored if $stored;
    if ( !GPForum::X::Conflict->caught($error) ) {
        GPForum::Infrastructure::UniqueConflict->rethrow($error);
    }

    return { error => 'email_already_registered', ok => 0 };
}

sub _email_already_confirmed ( $self, $user, $email ) {
    if ( !$self->already_verified($user) ) {
        return 0;
    }

    my $held = $self->support->column( $user, 'email_normalized' ) || q{};
    return $held eq $email ? 1 : 0;
}

1;

__END__

=head1 NAME

GPForum::Service::Identity::Account::EmailChange - Email change.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    # Part of GPForum::Service::Identity::AccountStore; callers use that class.

=head1 DESCRIPTION

Request an email change, which mails the new address a token and notifies
the old one, and confirm it with that token. Each is written once, as its
promise method; the blocking method is its twin (ADR 0177).

GPForum::Service::Identity::AccountStore inherits it, so the object a caller builds has every method; this
file holds one part of that class so each part can be read by itself.

=head1 SUBROUTINES/METHODS

Every C<_p> method takes the input, an optional query context and an
optional call layer (the transaction a command log holds); its writes
commit in one transaction of that layer, or of the store's own.

=head2 request_email_change_p

Takes C<current_password> with the address and the member, and answers
C<invalid_current_password> when it is not the member's, before the address
is looked up, or when a concurrent password rotation replaced the credential
it verified before the transaction. Issues an email-change token when the
address is available, mailed to that address, and queues C<email_change_notice> to the address
the member has, in their C<preferred_locale>, about the same token and
carrying none (ADR 0143). A request for the member's already-verified
address answers C<skipped> and does not issue a token. The current password
is verified in a child of the CPU lane, or in the process on the blocking
layer.

=head2 confirm_email_change_p

Consumes an email-change token and updates the user row, in a savepoint. A
second confirmation of the same already-verified address answers C<skipped>
and does not restamp C<email_verified_at>. A unique race on
C<email_normalized> answers C<email_already_registered> and does not
restamp the user.
A successful address replacement withdraws open password-reset tokens, so
returning to an old address cannot revive links issued before it was replaced.

=head2 request_email_change, confirm_email_change

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
