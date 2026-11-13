# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Identity::Account::Core;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -async_await;
use v5.40;

use GPForum::Infrastructure::ResultRow::IdentityUser;
use GPForum::Infrastructure::Text qw(has_text);
use GPForum::X::Unavailable;

our $VERSION = '0.001';

const my $USER_AGGREGATE          => 'user';
const my $MINIMUM_PASSWORD_LENGTH => 12;

# The work in the transaction $scope holds, or in one of its own when
# $scope holds none.
sub in_transaction_p ( $self, $scope, $context, $work ) {
    return $work->($scope) if $scope->in_transaction;

    return $scope->transaction_p( $work, $context );
}

# Password changes withdraw a pending email token while holding the
# credential. Resets and confirmations take that same lock before their
# token, or a confirmation holding the token can deadlock with a withdrawal.
# The owner lookup is only a hint for ordering locks; consume_token_p reads
# the token again under its own lock and keeps the used/expired error
# contract.
async sub consume_account_token_p ( $self, $type, $raw_token, $context, $scope )
{
    my $owner =
      await $self->token_store->token_user_id_p( $type, $raw_token, $context,
        $scope );
    if ( has_text($owner) ) {
        await $self->credential_store->lock_active_password_credentials_p(
            $owner, $context, $scope );
    }

    return owned_token(
        $owner,
        await $self->token_store->consume_token_p(
            $type, $raw_token, $context, $scope
        )
    );
}

# A token consumed for another owner than the one locked for is refused.
sub owned_token ( $owner, $token ) {
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

async sub record_user_action_p ( $self, $user, $action, $metadata, $context,
    $scope )
{
    await $self->audit->record_action_p(
        $self->user_action( $user, $action, $metadata ),
        $context, $scope );

    return;
}

sub user_action ( $self, $user, $action, $metadata ) {
    my $user_id = $self->support->column( $user, 'id' );
    return {
        action      => $action,
        actor_id    => $user_id,
        metadata    => $metadata,
        target_id   => $user_id,
        target_type => $USER_AGGREGATE,
    };
}

async sub queue_issued_mail_p ( $self, $user, $mail, $context, $scope ) {
    my $issued = $self->issued_mail( $user, $mail ) or return;
    await $self->audit->record_mail_p( $issued, $context, $scope );

    return;
}

# Mail is queued only with an address to send to and a raw token to send.
sub issued_mail ( $self, $user, $mail ) {
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

# Whether the password matches the credential's hash: Argon2 in a child of
# the CPU lane, whose answer the event loop brings, or in the process on a
# blocking layer, which waits on no event loop.
async sub credential_matches_p ( $self, $credential, $password, $scope ) {
    return 0 if !$credential;
    my $hash = $self->support->column( $credential, 'secret_hash' );
    my $matches =
        $scope->blocking
      ? $self->password->verify_password( $password, $hash )
      : await $self->password->verify_password_p( $password, $hash );

    return $matches ? 1 : 0;
}

# The password hashed as credential_matches_p verifies one.
async sub hashed_password_p ( $self, $password, $scope ) {
    return $self->password->hash_password($password) if $scope->blocking;

    return await $self->password->hash_password_p($password);
}

# The member's active password, locked until the transaction ends; undef
# when there is none. The partial unique index keeps it to one.
async sub locked_password_p ( $self, $user, $context, $scope ) {
    my $locked =
      await $self->credential_store->lock_active_password_credentials_p(
        $self->support->column( $user, 'id' ),
        $context, $scope );

    return $locked->[0];
}

async sub find_user_by_id_p ( $self, $user_id, $context, $scope ) {
    return undef if !has_text($user_id);

    return GPForum::Infrastructure::ResultRow::IdentityUser->from(
        await $scope->row_p(
            'identity_user_by_id', { user_id => $user_id }, $context
        ),
        $scope
    );
}

# An identifier with an @ is an address; any other is a username.
async sub find_login_user_p ( $self, $identifier, $context, $scope ) {
    return undef if !length $identifier;

    return GPForum::Infrastructure::ResultRow::IdentityUser->from(
        await $scope->row_p(
            'identity_user_by_identifier',
            {
                identifier => $identifier,
                by_email   => $identifier =~ /[@]/msx ? 1 : 0
            },
            $context
        ),
        $scope
    );
}

sub deleted_user ( $self, $user ) {
    my $status = $self->support->column( $user, 'status' ) || q{};
    return $status eq 'deleted' ? 1 : 0;
}

# Held by another member: the member's own address is not taken.
async sub email_taken_p ( $self, $email, $current_user_id, $context, $scope ) {
    my $existing = await $scope->row_p( 'identity_user_by_identifier',
        { identifier => $email, by_email => 1 }, $context );
    return 0 if !$existing;

    my $existing_id = $self->support->column( $existing, 'id' );
    return 0
      if has_text($existing_id)
      && has_text($current_user_id)
      && $existing_id eq $current_user_id;

    return 1;
}

sub email_error ( $, $email ) {
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

sub password_error ( $, $password ) {
    if ( !defined $password || !length $password ) {
        return 'password_required';
    }
    if ( length $password < $MINIMUM_PASSWORD_LENGTH ) {
        return 'password_too_short';
    }

    return undef;
}

sub issued_answer ( $self, $user, $token ) {
    return {
        email_normalized => $self->support->column( $user, 'email_normalized' ),
        ok               => 1,
        token            => $token,
    };
}

sub issued_metadata ( $self, $input, $token ) {
    return {
        outcome              => 'issued',
        request_address_hash =>
          $self->support->hash_value( $input->{request_address} ),
        token_id => $token->{token_id},
    };
}

# Records that a request named no member, and answers as if it had.
async sub audit_not_found_p ( $self, $action, $input, $context, $scope ) {
    await $self->audit->record_action_p(
        {
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
        },
        $context, $scope
    );

    return { ok => 1, token => undef };
}

sub skipped_answer ( $, $user ) {
    return {
        ok      => 1,
        skipped => 1,
        user    => $user,
    };
}

# A pending email change stops with the password that asked for it: a reset
# or a change of password withdraws it, so the address it named cannot take
# the account after the member took the password back.
sub withdraw_email_change_p ( $self, $user, $context, $scope ) {
    return $self->token_store->withdraw_open_token_p(
        $self->support->column( $user, 'id' ),
        'email_change', $context, $scope );
}

sub already_verified ( $self, $user ) {
    if ( $self->pending_user($user) ) {
        return 0;
    }
    if ( !defined $self->support->column( $user, 'email_verified_at' ) ) {
        return 0;
    }

    return 1;
}

sub pending_user ( $self, $user ) {
    my $status = $self->support->column( $user, 'status' ) || q{};
    return $status eq 'pending' ? 1 : 0;
}

# The call layer the account operations write on.
sub account_functions ($self) {
    return $self->functions // GPForum::X::Unavailable->throw(
        message => 'account changes need the PostgreSQL database' );
}

1;

__END__

=head1 NAME

GPForum::Service::Identity::Account::Core - The lookups and writes the account operations share.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    # Part of GPForum::Service::Identity::AccountStore; callers use that class.

=head1 DESCRIPTION

The transaction wrapper, the user and login lookups, the credential and lock checks, the account-token and audit records, the queued mail and the input checks that the password, email-change and email-verification operations all use.

GPForum::Service::Identity::AccountStore inherits it, so the object a caller builds has every method; this
file holds one part of that class so each part can be read by itself.

Each step is written once, as a promise method on the call layer it is
given (ADR 0177); on the blocking layer it runs to its end at once.

=head1 SUBROUTINES/METHODS

=head2 in_transaction_p

Runs a piece of work in the transaction the call layer holds, or in one of
its own, with the query context.

=head2 consume_account_token_p

Spends an account token of a type once, for its owner, after locking the
owner's password credential.

=head2 owned_token

The token row, when it belongs to the member who presented it.

=head2 record_user_action_p

Records an account action for a member in the audit trail.

=head2 user_action

The audit values of one account action.

=head2 queue_issued_mail_p

Queues the mail an issued token asks for.

=head2 issued_mail

The queued-mail values for an issued token.

=head2 credential_matches_p

Whether a password matches a stored credential; Argon2 runs in a child, or
in the process on the blocking layer.

=head2 hashed_password_p

A password's Argon2 hash, made as L</credential_matches_p> verifies one.

=head2 locked_password_p

The member's active password credential, locked for the change.

=head2 find_user_by_id_p

The member with an id, or nothing.

=head2 find_login_user_p

The member a sign-in identifier names, or nothing.

=head2 deleted_user

Whether a member is deleted.

=head2 email_taken_p

Whether another member holds an address.

=head2 email_error

The refusal for an address that is empty or malformed, or nothing.

=head2 password_error

The refusal for a password that is too short, or nothing.

=head2 issued_answer

The answer when a token was issued.

=head2 issued_metadata

The audit metadata of an issued token.

=head2 audit_not_found_p

Records that a request named no member, and answers as if it had.

=head2 skipped_answer

The answer when there was nothing to do.

=head2 withdraw_email_change_p

Withdraws a member's pending email change.

=head2 already_verified

Whether the member's address is already verified.

=head2 pending_user

Whether the member is still pending verification.

=head2 account_functions

The call layer the operations write on; without one it raises
L<GPForum::X::Unavailable>.

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
