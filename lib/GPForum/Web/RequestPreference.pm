# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Web::RequestPreference;

use Mojo::Base -base, -signatures;
use v5.40;

our $VERSION = '0.001';

sub wants_json ( $self, $controller ) {
    my $format = $controller->param('format') || q{};
    return 1 if $format eq 'json';

    my $accept = $controller->req->headers->accept // q{};
    return 0 if $accept !~ m{json|application/[*]}imsx;

    my @json = _preference( $accept, 'application', 'json' );
    return 0 if $json[0] <= 0;
    my @html = _preference( $accept, 'text', 'html' );

    # RFC 9110 12.5.1: the order of the list carries no preference, so a tie
    # in quality goes to the more specific range and then to the HTML page.
    return $json[0] > $html[0]
      || ( $json[0] == $html[0] && $json[1] > $html[1] )
      ? 1
      : 0;
}

# The quality the Accept header gives one media type, and how specific the
# range that gave it was: the type itself (3), its type/* (2) or */* (1).
# A type no range matches has quality 0 (RFC 9110 12.5.1).
sub _preference ( $accept, $type, $subtype ) {
    my %rank = ( "$type/$subtype" => 3, "$type/*" => 2, q{*/*} => 1 );
    my ( $quality, $specificity ) = ( 0, 0 );
    for my $weighted ( weighted($accept) ) {
        my ( $media, $weight ) = @{$weighted};
        next if ( $rank{$media} // 0 ) < ( $specificity || 1 );

        ( $quality, $specificity ) = ( $weight, $rank{$media} );
    }

    return ( $quality, $specificity );
}

# The members of an Accept-style header, lower-cased, each with its quality
# (RFC 9110 12.4.2): q defaults to 1.
sub weighted ($header) {
    my @weighted;
    for my $member ( split /,/msx, $header // q{} ) {
        my ( $name, @parameters ) = split /;/msx, $member;
        my ($weight) =
          map { /\A\s*q\s*=\s*([\d.]+)\s*\z/imsx ? $1 : () } @parameters;
        push @weighted,
          [ lc( $name // q{} ) =~ s/\A\s+|\s+\z//grmsx, $weight // 1 ];
    }

    return @weighted;
}

# A request the page made from its script (htmx sends HX-Request: true): it
# wants the part of the page the action changed, not the page or a redirect
# to it. A browser without the script never sends the header.
sub wants_fragment ( $, $controller ) {
    my $header = $controller->req->headers->header('HX-Request') // q{};

    return $header eq 'true' ? 1 : 0;
}

1;

__END__

=head1 NAME

GPForum::Web::RequestPreference - Whether a request asked for JSON rather than HTML.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    if ( GPForum::Web::RequestPreference->wants_json($controller) ) {
        return $controller->render( json => $payload );
    }

=head1 DESCRIPTION

One answer to one question that every page controller asks: render the JSON
form of the payload or the HTML page. A request wants JSON when its
C<format> parameter is C<json>, or when its C<Accept> header names
C<application/json>. Anything else gets HTML.

=head1 SUBROUTINES/METHODS

=head2 wants_fragment

True when the request carries C<HX-Request: true>, the header htmx sends:
the page asks for the part an action changed, not a redirect to the page.

=head2 weighted

Takes an Accept-style header (C<Accept>, C<Accept-Encoding>) and returns
its members as C<[ name, quality ]> pairs, the name lower-cased and the
quality 1 when no C<q> parameter gives one.

=head2 wants_json

Takes a Mojolicious controller. Returns 1 when the C<format> parameter is
C<json>, or when the C<Accept> header prefers C<application/json> to
C<text/html> under RFC 9110: by quality, then by the more specific range.
A tie, a C<q=0> for JSON and a type that merely contains C<json> answer 0,
the HTML page. It can be called as a class method or on an instance.

=head1 DIAGNOSTICS

None. A missing parameter or header counts as a request for HTML.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<Mojo::Base>.

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
