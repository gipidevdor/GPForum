# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Controller::Identity;

use Const::Fast;
use GPForum::Web::CookieSession;
use GPForum::Web::ErrorPayload;
use GPForum::Web::SecurityEvent;
use Mojo::Base 'GPForum::Controller::Identity::Base', -signatures;
use v5.40;
use Time::HiRes qw(time);

our $VERSION = '0.001';

const my $HTTP_OK           => 200;
const my $HTTP_ACCEPTED     => 202;
const my $HTTP_BAD_REQUEST  => 400;
const my $HTTP_UNAUTHORIZED => 401;
const my $HTTP_TOO_MANY     => 429;

# The pages a reader passes through to sign in, up or out: none of them is
# where they were going.
const my $IDENTITY_PATH =>
qr{\A / (?: login | logout | register | password | email ) (?: [/?] | \z )}msx;

sub register_form ($self) {
    return $self->render(
        template   => 'identity/register',
        command_id => $self->gp_id->uuid,
        %{ $self->gp_identity_view_model->register_form },
    );
}

sub register ($self) {
    my $blocked = $self->identity_post_guard('identity.register');
    if ($blocked) {
        return $blocked;
    }

    my $result = $self->gp_identity_workflow->register(
        {
            command_id   => $self->command_id_param,
            display_name => $self->param('display_name'),
            email        => $self->param('email'),
            password     => $self->param('password'),
            username     => $self->param('username'),
        }
    );
    if ( $result->{status} eq 'invalid' ) {
        return $self->render(
            template   => 'identity/register',
            command_id => $self->gp_id->uuid,
            status     => $HTTP_BAD_REQUEST,
            %{
                $self->gp_identity_view_model->register_form(
                    errors => $result->{errors},
                    values => $result->{stored}{values},
                )
            },
        );
    }
    if ( !$result->{ok} ) {
        return $self->identity_write_failure($result);
    }

    return $self->render(
        template     => 'identity/register_accepted',
        status       => $HTTP_ACCEPTED,
        registration => $result->{stored}{registration},
    );
}

sub login_form ($self) {
    return $self->render(
        template   => 'identity/login',
        command_id => $self->gp_id->uuid,
        %{ $self->gp_identity_view_model->login_form },
    );
}

sub login ($self) {
    my $blocked = $self->identity_post_guard('identity.login')
      || $self->_account_login_guard;
    if ($blocked) {
        return $blocked;
    }

    my $result = $self->gp_identity_workflow->login(
        {
            command_id      => $self->command_id_param,
            identifier      => $self->param('identifier'),
            password        => $self->param('password'),
            request_address => $self->request_address,
            user_agent      => $self->req->headers->user_agent || 'unknown',
        }
    );
    if ( $result->{status} eq 'invalid' ) {
        return $self->_render_login_form( $HTTP_BAD_REQUEST,
            $result->{errors} );
    }
    if ( ( $result->{error} || q{} ) eq 'unverified' ) {
        return $self->_render_login_form( $HTTP_UNAUTHORIZED,
            { login => $self->t('auth.login_unverified') },
        );
    }
    if ( $result->{ok} ) {
        $self->_remember_device;
        return $self->_accept_login( $result->{stored} );
    }
    if ( $result->{status} eq 'second_factor' ) {
        $self->_remember_device;
        return $self->_ask_second_step( $result->{stored} );
    }
    if ( $result->{status} eq 'second_factor_locked' ) {
        return $self->_second_step_locked;
    }
    if ( ( $result->{status} || q{} ) eq 'failed' ) {
        return $self->identity_unavailable;
    }

    return $self->_invalid_login;
}

# Logins are limited per address, and per account too: from many addresses,
# each under its own limit, one account could take thousands of guesses.
# ADR 0147: the account's limit does not apply to a browser that has signed
# in to it, so nobody can lock a member out of the browsers they use by
# guessing from elsewhere; only its address's limit does.
sub _account_login_guard ($self) {
    my $identifier = $self->_login_identifier;
    if ( !length $identifier ) {
        return;
    }
    my $access = $self->identity_access;
    if (
        $access->device_knows(
            scalar $self->signed_cookie( $access->device_cookie_name ),
            $identifier
        )
      )
    {
        return;
    }

    my $decision = $self->gp_rate_limiter->check(
        $self->identity_access->write_rate_input(
            {
                action   => 'identity.login_account',
                actor_id => "account:$identifier",
            }
        )
    );
    if ( $decision->{ok} ) {
        return;
    }

    return $self->_rate_limited;
}

sub _login_identifier ($self) {
    return lc $self->_trim( $self->param(q{identifier}) );
}

# ADR 0147: the password was right, so this browser is one the member signs
# in from.
sub _remember_device ($self) {
    my $identifier = $self->_login_identifier;
    if ( !length $identifier ) {
        return;
    }
    my $access = $self->identity_access;
    $self->signed_cookie(
        $access->device_cookie_name => $access->device_marks_with(
            scalar $self->signed_cookie( $access->device_cookie_name ),
            $identifier
        ),
        $access->device_cookie_options( time, $self->app->sessions->secure ),
    );

    return;
}

# ADR 0142: the second step of a sign-in, for a member with two-step
# sign-in on whose password verified. The challenge's token is in the
# signed cookie; without one there is nothing to answer.
sub second_factor_form ($self) {
    if ( !$self->_challenge_token ) {
        return $self->redirect_to('login');
    }

    return $self->_render_second_step( $HTTP_OK, undef );
}

sub second_factor ($self) {
    my $blocked = $self->identity_post_guard('identity.second_factor');
    if ($blocked) {
        return $blocked;
    }
    my $token = $self->_challenge_token;
    if ( !$token ) {
        return $self->_second_step_expired;
    }

    my $result = $self->gp_identity_workflow->complete_second_factor(
        {
            challenge_token => $token,
            code            => $self->param('code'),
            request_address => $self->request_address,
            user_agent      => $self->req->headers->user_agent || 'unknown',
        }
    );
    my $status = $result->{status} // 'failed';
    if ( $result->{ok} ) {
        my $return_to = $self->session('second_factor_return_to');
        $self->_forget_challenge;
        if ( ( $result->{stored}{method} // q{} ) eq 'recovery' ) {
            $self->flash(
                warning => $self->t(
                    'auth.second_factor_recovery_used',
                    { count => $result->{stored}{recovery_left} // 0 }
                )
            );
        }
        return $self->_accept_login( $result->{stored}, $return_to );
    }
    if ( $status eq 'wrong' ) {
        return $self->_wrong_second_step( $result->{attempts_left} );
    }
    if ( $status eq 'locked' ) {
        $self->_forget_challenge;
        return $self->_second_step_locked;
    }
    if ( $status eq 'failed' ) {
        return $self->identity_unavailable;
    }

    return $self->_second_step_expired;
}

sub _ask_second_step ( $self, $stored ) {
    $self->session(
        second_factor_challenge => $stored->{challenge_token},
        second_factor_return_to => $self->_after_login,
    );
    if ( $self->_wants_json ) {
        return $self->render(
            json => {
                status => 'second_factor',
                next   => $self->url_for('login_second_factor')->to_string,
            },
            status => $HTTP_ACCEPTED,
        );
    }

    return $self->redirect_to('login_second_factor');
}

sub _challenge_token ($self) {
    my $token = $self->session('second_factor_challenge');

    return defined $token && length $token ? $token : undef;
}

sub _forget_challenge ($self) {
    delete $self->session->{second_factor_challenge};
    delete $self->session->{second_factor_return_to};

    return;
}

sub _wrong_second_step ( $self, $attempts_left ) {
    GPForum::Web::SecurityEvent->new->record_event(
        $self,
        'auth_denial',
        {
            action => 'identity.second_factor',
            status => $HTTP_UNAUTHORIZED,
        }
    );
    if ( !$attempts_left ) {
        return $self->_second_step_expired;
    }
    if ( $self->_wants_json ) {
        return $self->render(
            json => {
                status        => 'wrong',
                attempts_left => 0 + $attempts_left,
            },
            status => $HTTP_UNAUTHORIZED,
        );
    }

    return $self->_render_second_step(
        $HTTP_UNAUTHORIZED,
        $self->t(
            'auth.second_factor_wrong_code',
            { count => 0 + $attempts_left }
        )
    );
}

sub _second_step_expired ($self) {
    $self->_forget_challenge;
    if ( $self->_wants_json ) {
        return $self->render(
            json   => { status => 'expired' },
            status => $HTTP_UNAUTHORIZED,
        );
    }

    $self->flash( error => $self->t('auth.second_factor_expired') );
    return $self->redirect_to('login');
}

sub _second_step_locked ($self) {
    GPForum::Web::SecurityEvent->new->record_event(
        $self,
        'auth_denial',
        {
            action => 'identity.second_factor',
            status => $HTTP_TOO_MANY,
        }
    );
    if ( $self->_wants_json ) {
        return $self->render(
            json   => { status => 'locked' },
            status => $HTTP_TOO_MANY,
        );
    }

    return $self->_render_login_form( $HTTP_TOO_MANY,
        { login => $self->t('auth.second_factor_locked') } );
}

sub _render_second_step ( $self, $status, $error ) {
    $self->res->headers->cache_control('private, no-store');

    return $self->render(
        template => 'identity/second_factor',
        status   => $status,
        error    => $error,
        digits   => $self->gp_second_factor->codes->digits,
    );
}

sub logout ($self) {
    my $blocked = $self->identity_post_guard('identity.logout');
    if ($blocked) {
        return $blocked;
    }

    my $result = $self->gp_identity_workflow->logout(
        {
            command_id => $self->command_id_param,
            session_id => $self->session('session_id'),
            user_id    => $self->current_user_id,
        }
    );
    if ( !$result->{ok} ) {
        return $self->identity_write_failure($result);
    }

    $self->_record_identity_audit(
        'record_logout_request',
        {
            actor_id        => $self->current_user_id,
            request_address => $self->request_address,
        }
    );
    GPForum::Web::CookieSession->new->sign_out($self);

    return $self->render(
        template => 'identity/logout_accepted',
        status   => $HTTP_ACCEPTED,
    );
}

sub _accept_login ( $self, $authenticated, $return_to = undef ) {
    $self->_apply_login_session($authenticated);
    $self->_record_identity_audit(
        'record_login_request',
        {
            actor_id        => $authenticated->{user_id},
            identifier      => $self->param('identifier'),
            outcome         => 'accepted',
            request_address => $self->request_address,
        }
    );

    # A client that asked for JSON keeps the answer it always had. A reader
    # is sent on: to a page that says "you are signed in" they would have to
    # leave at once, they prefer the page they were on.
    if ( $self->_wants_json ) {
        return $self->render(
            template => 'identity/login_accepted',
            status   => $HTTP_ACCEPTED,
        );
    }

    # ADR 0142: staff the policy requires two-step sign-in of, who have
    # none, are sent to set it up; the staff consoles refuse them until then.
    if ( $self->_second_step_owed( $authenticated->{user_id} ) ) {
        $self->flash( error => $self->t('auth.second_factor_staff_required') );
        return $self->redirect_to('settings_security');
    }

    $self->flash( success => $self->t('auth.login_accepted_title') );
    return $self->redirect_to(
        defined $return_to
        ? $self->safe_return_to($return_to)
        : $self->_after_login
    );
}

sub _second_step_owed ( $self, $user_id ) {
    my $status;
    try {
        $status = $self->gp_second_factor->status($user_id);
    }
    catch ($error) {
        $self->app->log->warn("second factor status degraded: $error");
        return 0;
    };

    return $status->{staff_required} && $status->{state} ne 'active' ? 1 : 0;
}

# Where a reader goes once signed in: back to the page the login form was
# reached from, when it carried one and that is a page of this forum which
# is not itself part of signing in; the home page otherwise.
sub _after_login ($self) {
    my $return_to = $self->safe_return_to( $self->param('return_to') );

    return $return_to =~ $IDENTITY_PATH ? q{/} : $return_to;
}

sub _apply_login_session ( $self, $authenticated ) {
    my $cookies          = GPForum::Web::CookieSession->new;
    my $preferred_locale = $self->login_preferred_locale($authenticated);
    my $preferred_theme  = $self->login_preferred_theme($authenticated);

    # A member's stored zone, if they chose one; none leaves the forum's
    # default.
    my $zone = $authenticated->{preferred_timezone};
    if ( !$self->i18n_service->formats->valid_time_zone($zone) ) {
        $zone = undef;
    }

    $cookies->replace_login(
        $self,
        {
            expires_at         => $cookies->expires_at(time),
            preferred_locale   => $preferred_locale,
            preferred_theme    => $preferred_theme,
            preferred_timezone => $zone,
            rotation           => $self->gp_id->uuid,
            session_id         => $authenticated->{session_id},
            session_token      => $authenticated->{session_token},
            user_id            => $authenticated->{user_id},
        }
    );
    if ( defined $preferred_locale ) {
        $self->set_locale_cookie($preferred_locale);
    }
    if ( defined $preferred_theme ) {
        $self->set_theme_cookie($preferred_theme);
    }

    return;
}

sub _record_identity_audit ( $self, $method, $input ) {
    my $result;
    try {
        $result = $self->gp_identity_security_audit->$method($input);
    }
    catch ($error) {
        $self->app->log->warn("identity audit degraded: $error");
        return undef;
    };

    return $result || undef;
}

sub _render_login_form ( $self, $status, $errors ) {
    return $self->render(
        template   => 'identity/login',
        command_id => $self->gp_id->uuid,
        status     => $status,
        %{
            $self->gp_identity_view_model->login_form(
                errors => $errors,
                values => {
                    identifier => $self->param('identifier') || q{},
                },
            )
        },
    );
}

sub _invalid_login ($self) {
    GPForum::Web::SecurityEvent->new->record_event(
        $self,
        'auth_denial',
        {
            action => 'identity.login',
            status => $HTTP_UNAUTHORIZED,
        }
    );

    if ( $self->_wants_json ) {
        return $self->render(
            json   => GPForum::Web::ErrorPayload->identity_invalid_login,
            status => $HTTP_UNAUTHORIZED,
        );
    }

    return $self->_render_login_form( $HTTP_UNAUTHORIZED,
        { login => 'login request could not be accepted' },
    );
}

1;

__END__

=head1 NAME

GPForum::Controller::Identity - Registration, login, and logout.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    $routes->get('/register')->to('Identity#register_form');

=head1 DESCRIPTION

Handles public registration and session lifecycle. Cookie-session duration
lives on L<GPForum::Web::CookieSession>. Password, email, settings, and
profile routes live in sibling controllers.

=head1 SUBROUTINES/METHODS

=head2 register_form

Renders the registration form.

=head2 register

Creates a registration after CSRF and rate-limit checks.

=head2 login_form

Renders the login form.

=head2 login

Authenticates a member and establishes a server session.

=head2 second_factor_form

Renders the second step of a sign-in (ADR 0142) while the signed cookie
holds a challenge's token; sends the reader to the login form otherwise.

=head2 second_factor

Answers the challenge with a code from the authenticator app or a recovery
code, after CSRF and rate-limit checks. A right answer signs the member in
as L</login> does; a wrong one says how many tries are left; an expired or
spent challenge sends the reader back to the login form.

=head2 logout

Revokes the current session. Requires C<command_id>.

=head1 DIAGNOSTICS

Invalid CSRF tokens render C<403>; invalid submitted forms render C<400>.

=head1 CONFIGURATION AND ENVIRONMENT

Uses identity helpers registered during application startup.

=head1 DEPENDENCIES

Uses L<GPForum::Controller::Identity::Base>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Password reset, email change, settings, and profile rendering are owned by
sibling identity controllers.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause
license.

=cut
