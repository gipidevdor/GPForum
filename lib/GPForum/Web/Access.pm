# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Web::Access;

use Const::Fast;
use Mojo::Base -base, -signatures;
use v5.40;

use GPForum::Web::Responder;

our $VERSION = '0.001';

# Backslashes are normalised to forward slashes by browsers, so "/\evil.test"
# would leave the site as a protocol-relative URL. Control characters cover
# header splitting and the NUL, tab, and vertical-tab variants of the same
# trick.
const my $UNSAFE_RETURN_TO => qr/[[:cntrl:]\\]/msx;

sub csrf_invalid ( $self, $controller ) {
    if ( $controller->validation->csrf_protect->has_error('csrf_token') ) {
        return 1;
    }

    return 0;
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
CSRF token validity, cookie-session user id, JSON negotiation, non-empty
text, and whether a submitted return path stays on this site. It does
not render errors; L<GPForum::Web::Guard> keeps that responsibility. It
does not talk to stores or DBIx::Class.

=head1 SUBROUTINES/METHODS

=head2 csrf_invalid

Returns true when Mojolicious CSRF protection reports a missing or invalid
token.

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

None.

=head1 DEPENDENCIES

Uses L<GPForum::Web::Responder>.

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
