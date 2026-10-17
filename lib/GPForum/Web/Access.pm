# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Web::Access;

use Const::Fast;
use Mojo::Base -base, -signatures;
use v5.40;
use Mojo::URL;

use GPForum::Web::Responder;

our $VERSION = '0.001';

# Backslashes are normalised to forward slashes by browsers, so "/\evil.test"
# would leave the site as a protocol-relative URL. Control characters cover
# header splitting and the NUL, tab, and vertical-tab variants of the same
# trick.
const my $UNSAFE_RETURN_TO => qr/[[:cntrl:]\\]/msx;
const my $SAME_ORIGIN_SITE => 'same-origin';

# A page served from the public cache is one rendering for every visitor, so
# its forms carry no token (ADR 0141): one would be the first visitor's,
# refused for everyone else and published to all. A visitor who is not
# signed in is let through on the browser's word that the form was posted
# from this site instead. A signed-in member is never served a cached page,
# and always needs the token of their own session.
sub csrf_invalid ( $self, $controller ) {
    if ( !$controller->validation->csrf_protect->has_error('csrf_token') ) {
        return 0;
    }
    if ( !$self->user_id($controller) && $self->same_origin($controller) ) {
        return 0;
    }

    return 1;
}

# Fetch metadata when the browser sends it: only same-origin, not a sibling
# site (same-site) nor a typed or bookmarked request (none). A browser
# without it is judged by Origin, which browsers send on every POST. A
# request that says neither, or says "null", is not from this site.
sub same_origin ( $self, $controller ) {
    my $headers = $controller->req->headers;
    my $site    = $headers->header('Sec-Fetch-Site');
    if ( $self->has_text($site) ) {
        return $site eq $SAME_ORIGIN_SITE ? 1 : 0;
    }

    my $origin = $headers->header('Origin');
    if ( !$self->has_text($origin) ) {
        return 0;
    }

    return $self->origin_matches( $controller, $origin );
}

# The request's own origin, or the one the forum is published under: behind
# a proxy the request's scheme and host may not be the ones the browser saw.
sub origin_matches ( $self, $controller, $origin ) {
    if ( $origin eq $self->request_origin($controller) ) {
        return 1;
    }
    if ( $origin eq
        $self->configured_origin( $controller->gp_config->public_base_url ) )
    {
        return 1;
    }

    return 0;
}

sub request_origin ( $, $controller ) {
    my $base   = $controller->req->url->base;
    my $scheme = $base->scheme || 'http';
    my $host   = $controller->req->headers->host || $base->host || q{};

    return join q{://}, $scheme, $host;
}

sub configured_origin ( $, $public_base_url ) {
    my $url  = Mojo::URL->new($public_base_url);
    my $host = $url->host || q{};
    if ( defined $url->port ) {
        $host .= q{:} . $url->port;
    }

    return join q{://}, $url->scheme || 'http', $host;
}

sub user_id ( $self, $controller ) {
    return GPForum::Web::Responder->new->user_id($controller);
}

sub wants_json ( $self, $controller ) {
    return GPForum::Web::Responder->new->wants_json($controller);
}

sub has_text ( $, $value ) {
    if ( !defined $value ) {
        return 0;
    }

    return length $value ? 1 : 0;
}

# A submitted return_to the site may send the browser to: a path of its
# own ("/t/thread"), so neither another origin ("//evil.test", "https://")
# nor nothing. Anything else is undef, for the caller's own default.
sub safe_return_to ( $self, $return_to ) {
    if ( !$self->has_text($return_to) ) {
        return undef;
    }

    if ( $return_to =~ $UNSAFE_RETURN_TO ) {
        return undef;
    }

    if ( $return_to !~ m{\A/}msx || $return_to =~ m{\A//}msx ) {
        return undef;
    }

    return $return_to;
}

1;

__END__

=head1 NAME

GPForum::Web::Access - Shared CSRF, session, and request-shape decisions.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $access = GPForum::Web::Access->new;
    if ( $access->csrf_invalid($controller) ) {
        return GPForum::Web::Guard->new->csrf_failure($controller);
    }

=head1 DESCRIPTION

Owns the HTTP decision helpers that controllers previously duplicated:
CSRF token validity, whether a request comes from this site's origin,
cookie-session user id, JSON negotiation, non-empty
text, and whether a submitted return path stays on this site. It does
not render errors; L<GPForum::Web::Guard> keeps that responsibility. It
does not talk to stores or DBIx::Class.

=head1 SUBROUTINES/METHODS

=head2 csrf_invalid

Returns false when the request carries its session's CSRF token, as
Mojolicious CSRF protection checks it. Without one, or with another
session's, it is false only for a visitor who is not signed in whose request
L</same_origin> says comes from this site: the forms of a page served from
the public cache carry no token (ADR 0141). Otherwise true.

=head2 same_origin

True when C<Sec-Fetch-Site> is C<same-origin>; for a request without
C<Sec-Fetch-Site>, when C<Origin> passes L</origin_matches>. False for any
other C<Sec-Fetch-Site> (C<same-site>, C<cross-site>, C<none>) and for a
request that names neither.

=head2 origin_matches

Takes the controller and an origin. True when it is L</request_origin> or
the L</configured_origin> of the configuration's C<public_base_url>, read
through the controller's C<gp_config> helper.

=head2 request_origin

The request's scheme (C<http> when it has none) and C<Host>, as
C<scheme://host>.

=head2 configured_origin

Takes a base URL and returns its C<scheme://host>, with the port when the
URL names one.

=head2 user_id

Returns the cookie-session user id through L<GPForum::Web::Responder>.

=head2 wants_json

Returns true when the request prefers JSON.

=head2 has_text

Returns true when a defined non-empty string is present.

=head2 safe_return_to

Returns a submitted C<return_to> when it is a same-origin relative path:
it starts with one slash, not two, and carries no control character or
backslash. Anything else returns undef.

=head1 DIAGNOSTICS

These methods return booleans or identifiers. HTTP status mapping stays in
the calling controller or L<GPForum::Web::Guard>.

=head1 CONFIGURATION AND ENVIRONMENT

C<public_base_url>, for L</origin_matches>.

=head1 DEPENDENCIES

Uses L<Mojo::URL> and L<GPForum::Web::Responder>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Identity CSRF failures still render as text from the identity controller.
This object only reports whether the token is invalid.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause
license.

=cut
