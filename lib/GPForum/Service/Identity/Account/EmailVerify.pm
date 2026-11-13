# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Identity::Account::EmailVerify;

use Const::Fast;
use Mojo::Base 'GPForum::Service::Identity::Account::EmailChange', -async_await;
use v5.40;

use GPForum::Infrastructure::SqlFunction;
use GPForum::Infrastructure::Text qw(has_text);

our $VERSION = '0.001';

const my $USER_AGGREGATE             => 'user';
const my $DAY_SECONDS                => 86_400;
const my $EMAIL_CHANGE_TOKEN_SECONDS => $DAY_SECONDS;

# Each operation is written once, as its promise method (ADR 0177).
GPForum::Infrastructure::SqlFunction->blocking_twins(
    qw(request_email_verification confirm_email_verification));

# The member is named by id when signed in, by username or address when not.
# Only a pending account is sent a verification; any other is audited as not
# found, like an unknown one. On $scope: the transaction a command log
# holds, or one of its own.
async sub request_email_verification_p (
    $self, $input,
    $context = undef,
    $scope = undef
  )
{
    $scope //= $self->account_functions;

    return await $self->in_transaction_p(
        $scope, $context,
        sub ($transaction) {
            return $self->_email_verification_p( $input, $context,
                $transaction );
        }
    );
}

# On $scope, as request_email_verification_p.
async sub confirm_email_verification_p (
    $self, $input,
    $context = undef,
    $scope = undef
  )
{
    $scope //= $self->account_functions;

    return await $self->in_transaction_p(
        $scope, $context,
        sub ($transaction) {
            return $self->_confirm_email_verification_p( $input, $context,
                $transaction );
        }
    );
}

# What a verification request writes for an account, prepared and not
# sent, in the order _email_verification_p draws it: the token issued (its
# row for api.identity_insert_token, its raw text for the mail), the audit
# of the request, and the mail's event with its outbox payload. For
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

async sub _email_verification_p ( $self, $input, $context, $scope ) {
    my $user =
      has_text( $input->{user_id} )
      ? await $self->find_user_by_id_p( $input->{user_id}, $context, $scope )
      : await $self->find_login_user_p(
        $self->support->normalize_identifier( $input->{identifier} ),
        $context, $scope );
    if ( !$self->_verifiable($user) ) {
        return await $self->audit_not_found_p(
            'identity.email_verification.requested',
            $input, $context, $scope );
    }

    my $token =
      await $self->token_store->create_token_p(
        $self->_verification_token_input( $user, $input ),
        $context, $scope );
    await $self->record_user_action_p(
        $user,
        'identity.email_verification.requested',
        $self->issued_metadata( $input, $token ),
        $context, $scope
    );
    await $self->queue_issued_mail_p(
        $user,
        {
            kind  => 'email_verification',
            to    => $self->support->column( $user, 'email_normalized' ),
            token => $token,
        },
        $context, $scope
    );

    return $self->issued_answer( $user, $token );
}

# A pending account, neither unknown nor deleted.
sub _verifiable ( $self, $user ) {
    return
         $user
      && !$self->deleted_user($user)
      && $self->pending_user($user)
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

async sub _confirm_email_verification_p ( $self, $input, $context, $scope ) {
    my $token =
      await $self->token_store->consume_token_p( 'email_verification',
        $input->{token}, $context, $scope );
    return $token if !$token->{ok};
    my $user =
      await $self->find_user_by_id_p( $token->{user_id}, $context, $scope );
    return { error => 'invalid_token', ok => 0 } if !$user;
    return $self->skipped_answer($user) if $self->already_verified($user);

    my $now = $self->clock->now_iso8601;
    await $user->update_p(
        {
            email_verified_at => $now,
            status            => 'active',
            updated_at        => $now,
        },
        $context, $scope
    );
    await $self->record_user_action_p(
        $user,
        'identity.email_verification.confirmed',
        { token_id => $token->{token_id} },
        $context, $scope
    );

    return { ok => 1, user => $user };
}

1;

__END__

=head1 NAME

GPForum::Service::Identity::Account::EmailVerify - Email verification.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    # Part of GPForum::Service::Identity::AccountStore; callers use that class.

=head1 DESCRIPTION

Request and confirm the verification of the address an account registered
with. Each is written once, as its promise method; the blocking method is
its twin (ADR 0177).

GPForum::Service::Identity::AccountStore inherits it, so the object a caller builds has every method; this
file holds one part of that class so each part can be read by itself.

=head1 SUBROUTINES/METHODS

Every C<_p> method takes the input, an optional query context and an
optional call layer (the transaction a command log holds); its writes
commit in one transaction of that layer, or of the store's own.

=head2 request_email_verification_p

Issues a registration verification token for a pending user without
revealing whether the identifier exists.

=head2 confirm_email_verification_p

Consumes a verification token, marks the email verified, and activates
the user. A second confirmation for an already-active verified user
answers C<skipped> and does not restamp C<email_verified_at>.

=head2 request_email_verification, confirm_email_verification

The blocking twins: each is its C<_p> method run on the blocking call layer
(ADR 0177), answering the value instead of a promise.

=head2 verification_calls

Takes the user row and the request and returns what
L</request_email_verification_p> would write for the account, prepared and
not sent, in the order it would draw it: C<token>, the token's row;
C<raw_token>, its text for the mail; C<audit>, the request's audit call;
C<mail>, the mail's event call with its outbox payload. For a command that
records them in one call with the registration
(C<api.identity_register_command>).

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
