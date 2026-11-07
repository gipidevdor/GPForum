# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Identity::AuthStore;

use Mojo::Base 'GPForum::Base', -async_await;
use v5.40;

use GPForum::Infrastructure::SqlFunction;
use GPForum::Infrastructure::ResultRow;
use GPForum::Infrastructure::ResultRow::IdentityUser;

use GPForum::Service::Identity::SecondFactor;
use GPForum::Service::Identity::Support;

our $VERSION = '0.001';

__PACKAGE__->requires(qw(credential_store password schema session_store));
has support => sub { return GPForum::Service::Identity::Support->new; };

# ADR 0142: asked for a challenge once the password verifies; without the
# configured keys a member who has it on is asked and cannot answer.
has second_factor => sub ($self) {
    return GPForum::Service::Identity::SecondFactor->new(
        schema => $self->schema );
};

# An identifier with an @ is an address, any other a username. An unknown or
# deleted account costs the work a wrong password costs and gets its answer.
has functions => \&GPForum::Infrastructure::SqlFunction::for_service;

sub authenticate_login ( $self, $input ) {
    my $user = $self->_user_by_identifier(
        $self->support->normalize_identifier( $input->{identifier} ) );
    my $status = ( $user && $self->support->column( $user, q{status} ) ) || q{};
    if ( !$user || $status eq 'deleted' ) {
        return $self->_invalid_login_after_work( $input->{password} );
    }
    my $credential = $self->_verified_credential( $user, $input->{password} );
    if ( !$credential ) {
        return _invalid_login();
    }
    if ( $status eq 'pending' ) {
        return { error => 'unverified', ok => 0 };
    }

    return $self->_second_step( $user, $credential )
      // $self->_signed_in( $user, $credential, $input );
}

# The account an identifier names, by id, for the login's per-account rate
# limit (Controller::Identity): an address and a username both lead to the
# one account, so its limit is one budget however the member is spelled;
# each spelling used to have a budget of its own. Undef for an identifier
# that names no account, which is then limited under its own spelling.
# The login that follows looks the account up again: one indexed read beside
# the Argon2 run it then spends, kept apart so the limit is decided before
# any password work and without handing a row from the controller down.
sub account_id_for ( $self, $identifier ) {
    return $self->_account_id(
        $self->_user_by_identifier(
            $self->support->normalize_identifier($identifier)
        )
    );
}

# The login's rate-limit key read on the worker's pooled asynchronous
# connections. Without SQL functions it answers the blocking read.
async sub account_id_for_p ( $self, $identifier, $context = undef ) {
    my $normalized = $self->support->normalize_identifier($identifier);
    return $self->account_id_for($identifier)
      if !$self->functions || !length $normalized;

    return $self->_account_id(
        GPForum::Infrastructure::ResultRow::IdentityUser->from(
            await $self->functions->row_p(
                _identifier_values($normalized), $context
            ),
            $self->functions
        )
    );
}

sub _account_id ( $self, $user ) {
    return $user ? $self->support->column( $user, q{id} ) : undef;
}

sub _user_by_identifier ( $self, $identifier ) {
    return undef if !length $identifier;

    return GPForum::Infrastructure::ResultRow::IdentityUser->from(
        $self->functions->row( _identifier_values($identifier) ),
        $self->functions )
      if $self->functions;

    my $column = $identifier =~ /[@]/msx ? 'email_normalized' : 'username';
    return $self->schema->resultset('User')->find( { $column => $identifier } );
}

sub _identifier_values ($identifier) {
    return (
        'identity_user_by_identifier',
        {
            identifier => $identifier,
            by_email   => $identifier =~ /[@]/msx ? 1 : 0,
        }
    );
}

# The session a verified password opens for a member without two-step
# sign-in.
sub _signed_in ( $self, $user, $credential, $input ) {
    my $session = $self->_open_session( $user, $credential, $input );
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
sub _second_step ( $self, $user, $credential ) {
    my $user_id = $self->support->column( $user, 'id' );
    my $opened  = $self->second_factor->open_challenge( $user_id,
        $self->support->column( $credential, 'id' ) );
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
# credential that verified, as _open_session does; a wrong one is counted
# and committed. Answers ok with the session, or the refusal: expired,
# wrong (attempts_left), locked.
sub complete_second_factor ( $self, $input ) {
    my $two_step = $self->second_factor;
    my $prepared = $two_step
      && $two_step->prepare_answer( $input->{challenge_token}, $input->{code} );
    if ( !$prepared ) {
        return { error => 'expired', ok => 0 };
    }

    return $self->schema->txn_do(
        sub {
            my $answer = $two_step->answer($prepared);
            if ( !$answer->{ok} ) {
                return {
                    attempts_left => $answer->{attempts_left},
                    error         => $answer->{status},
                    ok            => 0,
                };
            }

            my $user    = $self->_user_by_id( $answer->{user_id} );
            my $session = $self->session_store->create_session( $user, $input );
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
    );
}

sub _user_by_id ( $self, $user_id ) {
    if ( !$self->functions ) {
        return { id => $user_id };
    }

    return $self->functions->row( 'identity_user_by_id',
        { user_id => $user_id } )
      || { id => $user_id };
}

# The member's active password credential, when the password verifies
# against it. An account with none costs the decoy's work.
sub _verified_credential ( $self, $user, $password ) {
    my $credential = $self->credential_store->active_password_credential(
        $self->support->column( $user, 'id' ) );
    if ( !$credential ) {
        $self->_invalid_login_after_work($password);
        return undef;
    }
    if (
        !$self->password->verify_password(
            $password, $self->support->column( $credential, 'secret_hash' )
        )
      )
    {
        return undef;
    }

    return $credential;
}

# Argon2 runs outside any transaction, so a reset or a password change can
# commit between the verification and this. Opened all the same, after the
# reset had revoked the member's sessions, the session would stay valid:
# whoever knew the old password would keep the account the reset was meant
# to take back. So the credential that verified is held FOR SHARE in
# the transaction that inserts the session, which is opened only while that
# credential is still the active one. A rotation revokes it with an UPDATE, which waits for this
# transaction and is then followed by the revocation of every session, this
# one included; a rotation that committed first leaves nothing to hold.
sub _open_session ( $self, $user, $credential, $input ) {
    return $self->schema->txn_do(
        sub {
            my $held =
              $self->credential_store->hold_active_password_credential(
                $self->support->column( $user,       'id' ),
                $self->support->column( $credential, 'id' )
              );
            if ( !$held ) {
                return undef;
            }

            return $self->session_store->create_session( $user, $input );
        }
    );
}

# The same Argon2 work as a wrong password, then the same answer: with no
# account to check, a login answered at once, and its speed said which
# usernames and addresses exist.
sub _invalid_login_after_work ( $self, $password ) {
    $self->password->verify_password( $password, $self->password->decoy_hash );

    return _invalid_login();
}

sub _invalid_login {
    return { error => 'invalid_credentials', ok => 0 };
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

=head1 SUBROUTINES/METHODS

=head2 account_id_for

Takes a login identifier, an address or a username. Returns the id of the
account it names, or C<undef> for none: the login's per-account rate limit
is keyed by it, so both spellings of one member share one budget.

=head2 account_id_for_p

L</account_id_for> as a promise, with an optional query context last, read
on the worker's pooled asynchronous connections. Without SQL functions it
answers the blocking read.

=head2 authenticate_login

Verifies a password credential and opens a server session. The Argon2
verification runs outside any transaction; the session is inserted in a
transaction that first holds the verified credential C<FOR SHARE> and opens
nothing when it is no longer the member's active password, so a login that
verified a password a concurrent reset or change replaced is refused as
C<invalid_credentials> rather than outliving the reset's revocation.

A member with two-step sign-in on (ADR 0142) is answered C<second_factor>
with the challenge's C<challenge_token> instead of a session, or
C<second_factor_locked> after ten wrong answers in the hour.

=head2 complete_second_factor

Takes C<challenge_token>, C<code>, C<request_address> and C<user_agent>;
answers the challenge and, when it is right, opens the session in the same
transaction, which holds the password credential that verified. Answers
the session as L</authenticate_login> does, with C<method> and
C<recovery_left>, or C<ok> 0 with C<error> C<expired>, C<wrong> (and
C<attempts_left>) or C<locked>.

=head1 DIAGNOSTICS

Unknown identifiers, deleted users, and wrong passwords all return
C<invalid_credentials>. Matching credentials on a pending account return
C<unverified> without opening a session.

=head1 CONFIGURATION AND ENVIRONMENT

Requires a schema with a User resultset plus credential, password, and session
collaborators supplied by the identity store facade.

=head1 DEPENDENCIES

Uses L<GPForum::Service::Identity::Support>.

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
