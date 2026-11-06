# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Discovery::SitemapPages;

use Mojo::Base 'GPForum::Base', -signatures;
use v5.40;
use Const::Fast;

use GPForum::Infrastructure::SqlFunction;

our $VERSION = '0.001';

const my $PAGE_SIZE => 1000;

# Every reader gets the same sitemap, and a page is built from every public
# category and thread, sorted: a crawler walking the pages built and sorted
# them all again for each one. The index and the pages are cached for an
# hour, and dropped with the public pages when moderation or a category
# changes what is public.
const my $CACHE_TTL_SECONDS => 3_600;
const my @CACHE_TAGS        => qw(forum:public-html categories);
__PACKAGE__->requires(qw(schema builder));
has cache => undef;    # optional: without it each request builds its document
has cache_epoch => undef;    # optional: missing required epoch bypasses cache
has cache_epoch_required => 0;
has functions            => sub ($self) {
    return GPForum::Infrastructure::SqlFunction->for_schema( $self->schema );
};

sub sitemap_index ($self) {
    return $self->_cached( 'sitemap:index', sub { return $self->_index; } );
}

# The page, or undef past the last one: a page number nobody linked builds
# nothing and fills no cache.
sub page ( $self, $page ) {
    return undef if $page > $self->pages;

    return $self->_cached( "sitemap:page:$page",
        sub { return $self->_page($page); } );
}

# How many pages the sitemap has: at least one, which the legal pages fill.
sub pages ($self) {
    return $self->_cached(
        'sitemap:pages',
        sub {
            my $count =
              $self->functions->rows( 'forum_sitemap_count', {} )->[0]{total};
            return ceil( $count / $PAGE_SIZE ) || 1;
        }
    );
}

sub _cached ( $self, $key, $build ) {
    return $build->()
      if !$self->cache
      || ( $self->cache_epoch_required && !defined $self->cache_epoch );
    if ( defined $self->cache_epoch ) {
        $key .= q{:privacy:} . $self->cache_epoch;
    }

    return $self->cache->get_or_set( $key, $build,
        { tags => [@CACHE_TAGS], ttl_seconds => $CACHE_TTL_SECONDS } );
}

sub _index ($self) {
    my $pages   = $self->pages;
    my $base    = $self->builder->canonical_url->base_url;
    my @entries = map { { loc => "$base/sitemap-$_.xml" } } 1 .. $pages;
    return $self->builder->render_index( \@entries );
}

sub _page ( $self, $page ) {
    my $rows =
      $self->functions->rows( 'forum_sitemap_page', { page => $page } );
    my $canonical = $self->builder->canonical_url;
    my @entries   = $page == 1 ? @{ $self->builder->legal_entries } : ();
    for my $row ( @{$rows} ) {
        my $url =
          $row->{kind} eq 'thread'
          ? $canonical->thread_url(
            { thread_id => $row->{resource_id}, slug => $row->{slug} } )
          : $canonical->category_url( { category_id => $row->{resource_id} } );
        push @entries, { loc => $url, lastmod => $row->{changed_at} };
    }
    return $self->builder->render_xml( \@entries );
}

1;

__END__

=head1 NAME

GPForum::Service::Discovery::SitemapPages - Public sitemap index and pages.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $service = GPForum::Service::Discovery::SitemapPages->new(...);

=head1 DESCRIPTION

Public sitemap index and pages. See ADR 0155.

=head1 SUBROUTINES/METHODS

=head2 sitemap_index

Returns the sitemap index, naming every numbered 1000-resource page.

=head2 page

Takes a positive page number and returns its public resource URL set.
Page one also carries legal pages. Past the last page it returns undef.

=head2 pages

Returns how many pages the sitemap has, at least one.

With a C<cache>, both are kept for an hour under the tags
C<forum:public-html> and C<categories>, which moderation and category
changes purge.

=head1 DIAGNOSTICS

Exceptions propagate to the command or worker, which reports the failure.

=head1 CONFIGURATION AND ENVIRONMENT

C<cache_epoch> namespaces cached source data by the request's committed
public-content revocation epoch. C<cache_epoch_required> bypasses caching
when that epoch is unavailable; production enables this guard.

Receives configuration or collaborators through constructor arguments. See
ADR 0155 for the operator settings and commands.

=head1 DEPENDENCIES

Uses the modules listed in the source preamble and the locked cpanfile.

=head1 INCOMPATIBILITIES

Requires Perl 5.40 or newer.

=head1 BUGS AND LIMITATIONS

See ADR 0155 for the scope and operational limits.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
