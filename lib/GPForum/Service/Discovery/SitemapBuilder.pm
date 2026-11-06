# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Discovery::SitemapBuilder;

use Mojo::Base 'GPForum::Base', -signatures;
use v5.40;

our $VERSION = '0.001';

__PACKAGE__->requires(qw(canonical_url));

sub legal_entries ($self) {
    return [ map { { loc => $self->canonical_url->legal_url($_) } }
          qw(cookies privacy terms) ];
}

sub render_xml ( $self, $entries ) {
    my @urls = map { _url_xml($_) } @{$entries};

    return join "\n", '<?xml version="1.0" encoding="UTF-8"?>',
      '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">',
      @urls, '</urlset>', q{};
}

sub render_index ( $self, $entries ) {
    return join "\n", '<?xml version="1.0" encoding="UTF-8"?>',
      '<sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">',
      (
        map { '<sitemap><loc>' . _xml_escape( $_->{loc} ) . '</loc></sitemap>' }
          @{$entries}
      ),
      '</sitemapindex>', q{};
}

sub _url_xml ($entry) {
    my $loc     = _xml_escape( $entry->{loc} );
    my $lastmod = q{};
    if ( defined $entry->{lastmod} && length $entry->{lastmod} ) {
        my $date = "$entry->{lastmod}";
        $date =~ s/[ ]/T/msx;
        if ( index( $date, 'T' ) >= 0 ) {
            $date =~ s/([+-][[:digit:]]{2})\z/$1:00/amsx;
        }
        $lastmod = '<lastmod>' . _xml_escape($date) . '</lastmod>';
    }
    return '  <url><loc>' . $loc . '</loc>' . $lastmod . '</url>';
}

sub _xml_escape ($value) {
    $value =~ s/&/&amp;/gmsx;
    $value =~ s/</&lt;/gmsx;
    $value =~ s/>/&gt;/gmsx;
    $value =~ s/"/&quot;/gmsx;

    return $value;
}

1;

__END__

=head1 NAME

GPForum::Service::Discovery::SitemapBuilder - Sitemap entries for public pages and their XML.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $builder = GPForum::Service::Discovery::SitemapBuilder->new(
        canonical_url => $canonical_url,
    );

    my @entries = (
        @{ $builder->legal_entries },
        @{ $builder->category_entries($categories) },
        @{ $builder->thread_entries($threads) },
    );
    my $xml = $builder->render_xml( \@entries );

=head1 DESCRIPTION

Renders the sitemap index and pages, and gives the legal pages' entries,
which the first page leads with. Which categories and threads appear is
the SQL function's to decide (L<GPForum::Service::Discovery::SitemapPages>,
ADR 0155); every location comes from the C<canonical_url> object (a
L<GPForum::Service::Discovery::CanonicalUrl>).

=head1 SUBROUTINES/METHODS

=head2 legal_entries

Returns an array reference of three entries, C<< { loc => ... } >>, for the
cookies, privacy and terms pages.

=head2 render_xml

Takes an array reference of entries. Returns the sitemap XML as a string, a
C<urlset> with one C<url> element per entry; C<loc> and C<lastmod> are
escaped. A missing C<lastmod> is omitted; PostgreSQL timestamps are written
as W3C datetimes.

=head2 render_index

Takes sitemap locations and returns a sitemapindex document with escaped URLs.

=head1 DIAGNOSTICS

None.

=head1 CONFIGURATION AND ENVIRONMENT

None here: C<canonical_url> carries the public base URL.

=head1 DEPENDENCIES

L<GPForum::Service::Discovery::CanonicalUrl>.

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
