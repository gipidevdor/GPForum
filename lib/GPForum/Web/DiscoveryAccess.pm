# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Web::DiscoveryAccess;

use Const::Fast;
use Mojo::Base -base, -signatures;
use v5.40;

use Mojo::Util qw(encode);

our $VERSION = '0.001';

const my $HTTP_OK            => 200;
const my $DEFAULT_FEED_LIMIT => 25;

sub feed_limit ( $, $requested ) {
    return $requested || $DEFAULT_FEED_LIMIT;
}

# A document is text and the response bytes, in the charset every document's
# content type names: UTF-8. The feed went out as text, so a title or a
# summary with a character beyond ASCII, an ellipsis or an accented letter,
# stopped the response with "Wide character" before a byte of it was sent.
sub render_document ( $self, $controller, $document ) {
    $controller->res->headers->content_type( $document->{content_type} );

    return $controller->render(
        data   => encode( 'UTF-8', $document->{data} ),
        format => $document->{format},
        status => $self->status_code($document),
    );
}

sub status_code ( $, $document ) {
    return $document->{status} || $HTTP_OK;
}

1;

__END__

=head1 NAME

GPForum::Web::DiscoveryAccess - Discovery reader limits and document rendering.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $limit = $access->feed_limit( $controller->param('limit') );
    return $access->render_document( $controller, $document );

=head1 DESCRIPTION

Owns the Atom feed's reader limit and the content-type plus body
render for crawler documents. It does not load categories or threads.
L<GPForum::Controller::Discovery> still calls the readers and
L<GPForum::Web::DiscoveryPayload>.

=head1 SUBROUTINES/METHODS

=head2 feed_limit

Returns a requested feed limit or the default.

=head2 render_document

Sets the content type and renders the document's data, a text string,
encoded as UTF-8: the charset of every document's content type.

=head2 status_code

Returns the document status or HTTP 200.

=head1 DIAGNOSTICS

None. Missing reader data stays in the controller.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

Uses L<Const::Fast> and L<Mojo::Base>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Document XML and Atom bodies stay in L<GPForum::Web::DiscoveryPayload>.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
