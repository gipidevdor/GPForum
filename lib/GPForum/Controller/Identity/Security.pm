# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Controller::Identity::Security;

use Const::Fast;
use Mojo::Base 'GPForum::Controller::Identity::Base', -signatures;
use v5.40;

use GPForum::Web::QrCode;

our $VERSION = '0.001';

const my $ACTION           => 'identity.second_factor_settings';
const my $PAGE             => 'settings_security';
const my $HTTP_OK          => 200;
const my $HTTP_BAD_REQUEST => 400;
const my $HTTP_FORBIDDEN   => 403;
const my $HTTP_CONFLICT    => 409;
const my $HTTP_UNAVAILABLE => 503;

# ADR 0142: what each refusal answers, and what it says.
const my %STATUS => (
    active      => $HTTP_CONFLICT,
    forbidden   => $HTTP_FORBIDDEN,
    not_found   => $HTTP_CONFLICT,
    password    => $HTTP_BAD_REQUEST,
    replayed    => $HTTP_BAD_REQUEST,
    unavailable => $HTTP_UNAVAILABLE,
    wrong       => $HTTP_BAD_REQUEST,
);
const my %REFUSAL => (
    active      => 'auth.second_factor_already_on',
    forbidden   => 'auth.second_factor_forbidden',
    not_found   => 'auth.second_factor_not_on',
    password    => 'auth.second_factor_wrong_password',
    replayed    => 'auth.second_factor_replayed',
    unavailable => 'auth.second_factor_unavailable',
    wrong       => 'auth.second_factor_wrong_code_settings',
);

# The member's two-step sign-in: off with the way to set it up, pending
# with the QR code and the key to type, or on with the way to renew the
# recovery codes and to turn it off.
sub show ($self) {
    my $user_id = $self->current_user_id;
    return $self->settings_unauthorized if !$user_id;

    my $two_step = $self->gp_second_factor;
    my ( $status, $enrollment );
    try {
        $status = $two_step->status($user_id);
        $enrollment =
            $status->{state} eq 'pending'
          ? $two_step->enrollment( $user_id, $self->t('app.name') )
          : undef;
    }
    catch ($error) {
        $self->app->log->error("second factor settings failed: $error");
        return $self->settings_system_failure;
    };
    my $page = {
        state          => $status->{state},
        confirmed_at   => $status->{confirmed_at},
        recovery_left  => $status->{recovery_left},
        staff_required => $status->{staff_required},
        available      => $two_step->available,
    };
    $self->res->headers->cache_control('private, no-store');
    if ( $self->_wants_json ) {

        # The member's own key, while it is being set up, for a client that
        # draws its own QR code.
        if ($enrollment) {
            $page->{enrollment} = $enrollment;
        }
        return $self->render( json => $page, status => $HTTP_OK );
    }

    return $self->render(
        template   => 'identity/security',
        status     => $HTTP_OK,
        enrollment => $enrollment
        ? {
            secret => $enrollment->{secret},
            qr     => $self->_qr_code( $enrollment->{uri} ),
          }
        : undef,
        digits => $two_step->codes->digits,
        %{$page},
    );
}

# The link as an inline SVG QR code; without one (a link longer than the
# code holds) the page shows the key to type alone.
sub _qr_code ( $self, $uri ) {
    my $svg;
    try {
        $svg =
          GPForum::Web::QrCode->svg( $uri,
            $self->t('auth.second_factor_qr_label') );
    }
    catch ($error) {
        $self->app->log->warn("second factor QR code skipped: $error");
    };

    return $svg;
}

sub begin ($self) {
    my $user_id = $self->_writer or return;

    return $self->_answer( 'auth.second_factor_begun',
        $self->_service( begin => $user_id, $self->param('password') ) );
}

sub cancel ($self) {
    my $user_id = $self->_writer or return;

    return $self->_answer( 'auth.second_factor_cancelled',
        $self->_service( cancel => $user_id ) );
}

sub confirm ($self) {
    my $user_id = $self->_writer or return;
    my $result  = $self->_service(
        confirm => $user_id,
        $self->param('code'), $self->session('session_id')
    );

    return $self->_codes( 'auth.second_factor_enabled', $result );
}

sub renew ($self) {
    my $user_id = $self->_writer or return;

    return $self->_codes( 'auth.second_factor_renewed',
        $self->_service( renew => $user_id, $self->param('code') ) );
}

sub disable ($self) {
    my $user_id = $self->_writer or return;

    return $self->_answer(
        'auth.second_factor_disabled',
        $self->_service(
            disable => $user_id,
            $self->param('password'), $self->param('code')
        )
    );
}

# The service's answer, or undef when it failed (logged).
sub _service ( $self, $method, @arguments ) {
    my $result;
    try {
        $result = $self->gp_second_factor->$method(@arguments);
    }
    catch ($error) {
        $self->app->log->error("second factor $method failed: $error");
        return undef;
    };

    return $result;
}

# CSRF, the rate limit, then a signed-in member: undef once a refusal is
# rendered.
sub _writer ($self) {
    return undef if $self->identity_post_guard($ACTION);

    my $user_id = $self->current_user_id;
    if ( !$user_id ) {
        $self->settings_unauthorized;
        return undef;
    }

    return $user_id;
}

# The recovery codes, shown once on a page of their own that is never
# stored by a cache.
sub _codes ( $self, $done, $result ) {
    return $self->_answer( $done, $result ) if !$result || !$result->{ok};

    $self->res->headers->cache_control('private, no-store');
    if ( $self->_wants_json ) {
        return $self->render(
            json => {
                ok             => 1,
                status         => $result->{status},
                recovery_codes => $result->{recovery_codes},
            },
            status => $HTTP_OK,
        );
    }

    return $self->render(
        template       => 'identity/security_codes',
        status         => $HTTP_OK,
        message        => $self->t($done),
        recovery_codes => $result->{recovery_codes},
    );
}

sub _answer ( $self, $done, $result ) {
    return $self->settings_system_failure
      if !$result || ( $result->{status} // q{} ) eq 'failed';

    my $status = $result->{status};
    if ( $self->_wants_json ) {
        return $self->render(
            json   => { ok => $result->{ok}, status => $status },
            status => $result->{ok}
            ? $HTTP_OK
            : ( $STATUS{$status} // $HTTP_BAD_REQUEST ),
        );
    }
    if ( $result->{ok} ) {
        $self->flash( success => $self->t($done) );
    }
    else {
        $self->flash( error =>
              $self->t( $REFUSAL{$status} // 'auth.second_factor_failed' ) );
    }

    return $self->redirect_to($PAGE);
}

1;

__END__

=head1 NAME

GPForum::Controller::Identity::Security - A member's two-step sign-in settings.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    $routes->get('/settings/security')->to('Identity::Security#show');

=head1 DESCRIPTION

ADR 0142. The page where a member sets up two-step sign-in: the password
begins it, the QR code (drawn on the server) or the typed key adds it to an
authenticator app, and the first code turns it on and shows ten recovery
codes once. While it is on, a code renews the recovery codes, and the
password with a code or a recovery code turns it off. Every write takes the
CSRF token and the C<identity.second_factor_settings> rate limit; no page
is stored by a cache.

=head1 SUBROUTINES/METHODS

=head2 show

Renders the member's state; JSON gives C<state>, C<confirmed_at>,
C<recovery_left>, C<staff_required> and C<available>.

=head2 begin

Takes C<password> and begins enrollment.

=head2 cancel

Drops a pending enrollment.

=head2 confirm

Takes the first C<code>, turns two-step sign-in on, ends the member's
other sessions and shows the recovery codes.

=head2 renew

Takes a C<code> and shows ten new recovery codes.

=head2 disable

Takes C<password> and a C<code> or a recovery code and turns two-step
sign-in off.

=head1 DIAGNOSTICS

A refusal flashes its reason and returns to the page; JSON clients get the
status with C<400>, C<403>, C<409> or C<503>.

=head1 CONFIGURATION AND ENVIRONMENT

Without C<GPFORUM_SECOND_FACTOR_KEY> where the forum is deployed, the page
says two-step sign-in is not available.

=head1 DEPENDENCIES

L<GPForum::Service::Identity::SecondFactor>, L<GPForum::Web::QrCode>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

None known.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause
license.

=cut
