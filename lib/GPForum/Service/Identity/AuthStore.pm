# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Identity::AuthStore;

use Mojo::Base 'GPForum::Base', -async_await;
use v5.40;

use GPForum::Infrastructure::SqlFunction;
use GPForum::Infrastructure::ResultRow::IdentityUser;

use GPForum::Service::Identity::SecondFactor;
use GPForum::Service::Identity::Support;
use GPForum::X::Unavailable;

our $VERSION = '0.001';

__PACKAGE__->requires(qw(credential_store password schema session_store));
has support => sub { return GPForum::Service::Identity::Support->new; };

# ADR 0142: asked for a challenge once the password verifies; without the
# configured keys a member who has it on is asked and cannot answer.
has second_factor => sub ($self) {
    return GPForum::Service::Identity::SecondFactor->new(
        schema => $self->schema );
};
has functions => \&GPForum::Infrastructure::SqlFunction::for_service;

# Each operation is written once, as its promise method (ADR 0177); the
# stores a login awaits block with it.
GPForum::Infrastructure::SqlFunction->blocking_twins(
    qw(authenticate_login account_id_for complete_second_factor));
GPForum::Infrastructure::SqlFunction->blocking_parts(
    qw(credential_store second_factor session_store));

# An identifier with an @ is an address, any other a username. An unknown or
# deleted account costs the work a wrong password costs and gets its answer.
# The password is never checked in a child that holds a connection: the
# reads and the session's transaction are on the call layer, Argon2 apart.
async sub authenticate_login_p ( $self, $input, $context = undef ) {
    my $user = await $self->_user_by_identifier_p(
        $self->support->normalize_identifier( $input->{identifier} ),
        $context );
    my $status = $self->_login_status($user);
    if ( !$status ) {
        return await $self->_invalid_login_after_work_p( $input->{password} );
    }
    my $credential =
      await $self->_verified_credential_p( $user, $input->{password},
        $context );
    if ( !$credential ) {
        return _invalid_login();
    }
    if ( $status eq 'pending' ) {
        return { error => 'unverified', ok => 0 };
    }

    return ( await $self->_second_step_p( $user, $credential, $context ) )
      // ( await $self->_signed_in_p( $user, $credential, $input, $context ) );
}

# The account's status, or undef for none (or a deleted one): the login
# then costs the decoy's work.
sub _login_status ( $self, $user ) {
    my $status = ( $user && $self->support->column( $user, q{status} ) ) || q{};
    return undef if !$user || $status eq 'deleted';

    return $status;
}

# The account an identifier names, by id, for the login's per-account rate
# limit (Controller::Identity): an address and a username both lead to the
# one account, so its limit is one budget however the member is spelled;
# each spelling used to have a budget of its own. Undef for an identifier
# that names no account, which is then limited under its own spelling.
# The login that follows looks the account up again: one indexed read beside
# the Argon2 run it then spends, kept apart so the limit is decided before
# any password work and without handing a row from the controller down.
async sub account_id_for_p ( $self, $identifier, $context = undef ) {
    my $user = await $self->_user_by_identifier_p(
        $self->support->normalize_identifier($identifier), $context );

    return $user ? $self->support->column( $user, q{id} ) : undef;
}

# The account an identifier names; none for an empty one, which is not
# looked up.
async sub _user_by_identifier_p ( $self, $identifier, $context ) {
    return undef if !length $identifier;

    my $functions = $self->_functions;
    return GPForum::Infrastructure::ResultRow::IdentityUser->from(
        await $functions->row_p(
            'identity_user_by_identifier',
            {
                identifier => $identifier,
                by_email   => $identifier =~ /[@]/msx ? 1 : 0,
            },
            $context
        ),
        $functions
    );
}

# The session a verified password opens for a member without two-step
# sign-in.
async sub _signed_in_p ( $self, $user, $credential, $input, $context ) {
    my $session =
      await $self->_open_session_p( $user, $credential, $input, $context );
    if ( !$session ) {
        return _invalid_login();
    }
    return {
        ok         => 1,
        session    => $session->{session},
        session_id =>
          $self->support->column( $session->{session}, 'session_id' ),
        session_token => $session->{session_token},
        user          => $user,
        user_id       => $self->support->column( $user, 'id' ),
    };
}

# ADR 0142: a member with two-step sign-in on gets a challenge rather than
# a session once the password verifies: its token goes to the signed cookie,
# its hash to the store. Ten wrong answers in an hour refuse a new one.
async sub _second_step_p ( $self, $user, $credential, $context ) {
    my $user_id = $self->support->column( $user, 'id' );
    return _challenge(
        $user_id,
        await $self->second_factor->open_challenge_p(
            $user_id, $self->support->column( $credential, 'id' ), $context
        )
    );
}

sub _challenge ( $user_id, $opened ) {
    my $status = $opened->{status};
    if ( $status eq 'none' ) {
        return undef;
    }
    if ( $status eq 'open' ) {
        return {
            challenge_token => $opened->{token},
            error           => 'second_factor',
            ok              => 0,
            user_id         => $user_id,
        };
    }
    if ( $status eq 'locked' ) {
        return { error => 'second_factor_locked', ok => 0 };
    }

    return _invalid_login();
}

# The second step of a sign-in: the code, or a recovery code, answers the
# challenge the cookie's token names. A right answer opens the session in
# the transaction that closes the challenge, which holds the password
# credential that verified, as _open_session_p does; a wrong one is counted
# and committed. Answers ok with the session, or the refusal: expired,
# wrong (attempts_left), locked.
async sub complete_second_factor_p ( $self, $input, $context = undef ) {
    my $two_step = $self->second_factor;
    my $prepared = $two_step
      && await $two_step->prepare_answer_p( $input->{challenge_token},
        $input->{code}, $context );
    if ( !$prepared ) {
        return { error => 'expired', ok => 0 };
    }

    return await $self->_functions->transaction_p(
        async sub ($scope) {
            my $answer =
              await $two_step->answer_p( $prepared, $context, $scope );
            return _wrong_answer($answer) if !$answer->{ok};

            my $user = await $scope->row_p( 'identity_user_by_id',
                { user_id => $answer->{user_id} }, $context );
            $user ||= { id => $answer->{user_id} };
            return $self->_second_step_session(
                $answer, $user,
                await $self->session_store->create_session_p(
                    $user, $input, $context, $scope
                )
            );
        },
        $context
    );
}

sub _wrong_answer ($answer) {
    return {
        attempts_left => $answer->{attempts_left},
        error         => $answer->{status},
        ok            => 0,
    };
}

sub _second_step_session ( $self, $answer, $user, $session ) {
    return {
        method        => $answer->{method},
        ok            => 1,
        recovery_left => $answer->{recovery_left},
        session       => $session->{session},
        session_id    =>
          $self->support->column( $session->{session}, 'session_id' ),
        session_token => $session->{session_token},
        user          => $user,
        user_id       => $answer->{user_id},
    };
}

# The member's active password credential, when the password verifies
# against it. An account with none costs the decoy's work.
async sub _verified_credential_p ( $self, $user, $password, $context ) {
    my $credential =
      await $self->credential_store->active_password_credential_p(
        $self->support->column( $user, 'id' ), $context );
    if ( !$credential ) {
        await $self->_invalid_login_after_work_p($password);
        return undef;
    }
    my $verified = await $self->_verify_p( $password,
        $self->support->column( $credential, 'secret_hash' ) );

    return $verified ? $credential : undef;
}

# Argon2 runs outside any transaction, so a reset or a password change can
# commit between the verification and this. Opened all the same, after the
# reset had revoked the member's sessions, the session would stay valid:
# whoever knew the old password would keep the account the reset was meant
# to take back. So the credential that verified is held FOR SHARE in the
# transaction that inserts the session, which is opened only while that
# credential is still the active one. A rotation revokes it with an UPDATE,
# which waits for this transaction and is then followed by the revocation
# of every session, this one included; a rotation that committed first
# leaves nothing to hold.
async sub _open_session_p ( $self, $user, $credential, $input, $context ) {
    return await $self->_functions->transaction_p(
        async sub ($scope) {
            my $held =
              await $self->credential_store->hold_active_password_credential_p(
                $self->support->column( $user,       'id' ),
                $self->support->column( $credential, 'id' ),
                $context, $scope
              );
            return undef if !$held;

            return await $self->session_store->create_session_p( $user, $input,
                $context, $scope );
        },
        $context
    );
}

# The same Argon2 work as a wrong password, then the same answer: with no
# account to check, a login answered at once, and its speed said which
# usernames and addresses exist.
async sub _invalid_login_after_work_p ( $self, $password ) {
    my $decoy =
        $self->_argon_in_process
      ? $self->password->decoy_hash
      : await $self->password->decoy_hash_p;
    await $self->_verify_p( $password, $decoy );

    return _invalid_login();
}

# Argon2 in a child of the CPU lane, whose answer the event loop brings; on
# the blocking layer, which waits on no event loop, in the process.
async sub _verify_p ( $self, $password, $hash ) {
    return $self->password->verify_password( $password, $hash )
      if $self->_argon_in_process;

    return await $self->password->verify_password_p( $password, $hash );
}

sub _argon_in_process ($self) {
    my $functions = $self->functions;
    return !$functions || $functions->blocking ? 1 : 0;
}

sub _invalid_login {
    return { error => 'invalid_credentials', ok => 0 };
}

sub _functions ($self) {
    return $self->functions // GPForum::X::Unavailable->throw(
        message => 'sign-in needs the PostgreSQL database' );
}

1;

__END__

=head1 NAME

GPForum::Service::Identity::AuthStore - Login credential verification.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $result = $store->authenticate_login(
        {
            identifier => $identifier,
            password   => $password,
        }
    );

=head1 DESCRIPTION

Owns login authentication and server-session creation. The identity store
facade delegates C<authenticate_login> so HTTP and workflow callers keep a
stable API. Failed logins remain non-enumerative.

Each operation is written once, as its promise method, against the
PostgreSQL function layer; the blocking methods are its twins (ADR 0177),
and the credential store, the session store and the second factor are its
parts, which block with it. Argon2 runs in a child of the CPU lane, or in
the process on the blocking layer. There is no fallback: without the
function layer a call that reads an account raises
L<GPForum::X::Unavailable>.

=head1 SUBROUTINES/METHODS

Every C<_p> method takes an optional query context after its arguments.

=head2 account_id_for_p

Takes a login identifier, an address or a username. Answers the id of the
account it names, or C<undef> for none: the login's per-account rate limit
is keyed by it, so both spellings of one member share one budget.

=head2 authenticate_login_p

Verifies a password credential and opens a server session. The Argon2
verification runs outside any transaction; the session is inserted in a
transaction that first holds the verified credential C<FOR SHARE> and opens
nothing when it is no longer the member's active password, so a login that
verified a password a concurrent reset or change replaced is refused as
C<invalid_credentials> rather than outliving the reset's revocation. An
unknown account verifies against the decoy hash, the same work.

A member with two-step sign-in on (ADR 0142) is answered C<second_factor>
with the challenge's C<challenge_token> instead of a session, or
C<second_factor_locked> after ten wrong answers in the hour.

=head2 complete_second_factor_p

Takes C<challenge_token>, C<code>, C<request_address> and C<user_agent>;
answers the challenge and, when it is right, opens the session in the same
transaction, which holds the password credential that verified. Answers
the session as L</authenticate_login_p> does, with C<method> and
C<recovery_left>, or C<ok> 0 with C<error> C<expired>, C<wrong> (and
C<attempts_left>) or C<locked>.

=head2 authenticate_login, account_id_for, complete_second_factor

The blocking twins: each is its C<_p> method run on the blocking call layer
(ADR 0177), answering the value instead of a promise.

=head1 DIAGNOSTICS

Unknown identifiers, deleted users, and wrong passwords all answer
C<invalid_credentials>. Matching credentials on a pending account answer
C<unverified> without opening a session.

=head1 CONFIGURATION AND ENVIRONMENT

Requires the PostgreSQL function layer plus credential, password, and
session collaborators supplied by the identity store facade.

=head1 DEPENDENCIES

Uses L<GPForum::Infrastructure::SqlFunction>,
L<GPForum::Service::Identity::SecondFactor> and
L<GPForum::Service::Identity::Support>.

Extends L<GPForum::Base>: built without C<credential_store>, C<password>,
C<schema> or C<session_store> it throws L<GPForum::X::Argument>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Login does not distinguish missing accounts from wrong passwords.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
