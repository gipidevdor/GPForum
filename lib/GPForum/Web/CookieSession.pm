# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Web::CookieSession;

use Const::Fast;
use Mojo::Base -base, -signatures;
use v5.40;

use GPForum::Infrastructure::Text qw(has_text);
use GPForum::Web::Access;

our $VERSION = '0.001';

const my $SESSION_SECONDS => 2_592_000;

has access => sub { return GPForum::Web::Access->new; };

sub has_server_session ( $self, $controller ) {
    if ( !has_text( $controller->session('session_id') ) ) {
        return 0;
    }
    if ( !has_text( $self->access->user_id($controller) ) ) {
        return 0;
    }

    return 1;
}

sub expired ( $, $controller, $now ) {
    my $expires_at = $controller->session('session_expires_at_epoch');
    if ( !defined $expires_at ) {
        return 0;
    }

    return $expires_at > $now ? 0 : 1;
}

sub session_seconds {
    return $SESSION_SECONDS;
}

sub expires_at ( $, $now ) {
    return int( $now + $SESSION_SECONDS );
}

sub clear ( $self, $controller ) {
    $self->_delete_keys(
        $controller,
        [
            qw(user_id session_id session_token login_rotation session_expires_at_epoch expiration)
        ]
    );
    $controller->session( expires => 1 );

    return;
}

# The CSRF token goes too, at sign-in and at sign-out (ADR 0141): one
# read off a page before sign-in, or left in a browser after sign-out,
# must not be good for the session that follows. The next form drawn gets
# a new one. So does the expiry a stale session's clearing set:
# Mojolicious writes a cookie with the expiry the session holds, and a
# sign-in on the same request as the clearing -- a revoked cookie posting
# the login form -- was written into a cookie that had already expired.
sub replace_login ( $self, $controller, $input ) {
    $self->_delete_keys(
        $controller,
        [
            qw(user_id session_id session_token login_rotation session_expires_at_epoch expiration expires preferred_locale preferred_theme preferred_timezone csrf_token)
        ]
    );
    $controller->session( $self->login_values($input) );

    return;
}

# A visitor again: the cookie session keeps nothing of the member's, not
# even the token, and stays a session, so the page that says they signed
# out draws its forms with a token that session holds. Expiring the cookie
# instead would leave the member's keys to that page, drawn as theirs, with
# forms whose token no session holds any more.
sub sign_out ( $self, $controller ) {
    %{ $controller->session } = ();

    return;
}

# Mojolicious stamps the cookie with its own expiry on every response,
# one hour ahead unless the session says otherwise: a member who came back
# after an hour away was a visitor again, whatever session_expires_at_epoch
# and the server's row said. The session carries the lifetime the cookie is
# written with; the row and the epoch above still end it 30 days after
# sign-in.
sub login_values ( $self, $input ) {
    my %values = (
        expiration               => $SESSION_SECONDS,
        login_rotation           => $input->{rotation},
        session_expires_at_epoch => $input->{expires_at},
        session_id               => $input->{session_id},
        session_token            => $input->{session_token},
        user_id                  => $input->{user_id},
    );
    $self->_maybe_set( \%values, 'preferred_locale',
        $input->{preferred_locale} );
    $self->_maybe_set( \%values, 'preferred_theme', $input->{preferred_theme} );
    $self->_maybe_set( \%values, 'preferred_timezone',
        $input->{preferred_timezone} );

    return %values;
}

sub validation_reason ( $, $validation ) {
    if ( !$validation ) {
        return 'validation_failed';
    }

    return $validation->{error} || 'validation_failed';
}

sub _delete_keys ( $, $controller, $keys ) {
    my $session = $controller->session;
    delete @{$session}{ @{$keys} };

    return;
}

sub _maybe_set ( $, $values, $name, $value ) {
    if ( defined $value ) {
        $values->{$name} = $value;
    }

    return;
}

1;

__END__

=head1 NAME

GPForum::Web::CookieSession - Cookie-session field ownership.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $cookies = GPForum::Web::CookieSession->new;
    if ( $cookies->expired( $controller, time ) ) {
        $cookies->clear($controller);
    }

=head1 DESCRIPTION

Owns cookie-session presence, 30-day login duration, expiry, clearing,
sign-out, login-value assembly, and the rotation of the CSRF token at
sign-in and sign-out. It does not validate server-side session rows, render
errors, or record telemetry. Bootstrap identity and the identity controller
keep those responsibilities.

=head1 SUBROUTINES/METHODS

=head2 has_server_session

True when both C<session_id> and C<user_id> cookies are present.

=head2 expired

True when C<session_expires_at_epoch> is defined and not after C<$now>.

=head2 session_seconds

Returns the authenticated cookie-session lifetime of 2_592_000 seconds.

=head2 expires_at

Returns the integer epoch C<$now> plus the cookie-session lifetime.

=head2 clear

Deletes server-session keys and expires the Mojolicious session cookie.

=head2 replace_login

Resets login keys and the CSRF token, and writes a new authenticated cookie
session; the next form drawn gets a new token.

=head2 sign_out

Empties the cookie session, the CSRF token with it, and leaves it a session:
the page drawn next is a visitor's, with a new token.

=head2 login_values

Returns the hash written into the cookie session at login.

=head2 validation_reason

Maps a missing or failed store validation to C<validation_failed> or the
store error.

=head1 DIAGNOSTICS

These methods return booleans, hashes, or reason strings. HTTP status mapping
stays in bootstrap identity and identity controllers.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

Uses L<Const::Fast> and L<GPForum::Web::Access>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Invalidation does not delete locale and theme cookies; login replacement does.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
