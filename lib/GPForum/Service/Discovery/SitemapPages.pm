# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Discovery::SitemapPages;

use Mojo::Base 'GPForum::Base', -async_await;
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
has functions            => \&GPForum::Infrastructure::SqlFunction::for_service;

# Each document is written once, as its promise method (ADR 0177); a
# command or a test reads the same body settled on the blocking layer.
GPForum::Infrastructure::SqlFunction->blocking_twins(
    qw(sitemap_index page pages));

async sub sitemap_index_p ( $self, $context = undef ) {
    return await $self->_cached_p( 'sitemap:index',
        async sub { return $self->_index( await $self->pages_p($context) ) } );
}

# The page, or undef past the last one: a page number nobody linked builds
# nothing and fills no cache.
async sub page_p ( $self, $page, $context = undef ) {
    return undef if $page > ( await $self->pages_p($context) );

    return await $self->_cached_p(
        "sitemap:page:$page",
        async sub {
            return $self->_page(
                $page,
                await $self->functions->rows_p(
                    'forum_sitemap_page', { page => $page }, $context
                )
            );
        }
    );
}

# How many pages the sitemap has: at least one, which the legal pages fill.
async sub pages_p ( $self, $context = undef ) {
    return await $self->_cached_p(
        'sitemap:pages',
        async sub {
            my $rows = await $self->functions->rows_p( 'forum_sitemap_count',
                {}, $context );
            return ceil( $rows->[0]{total} / $PAGE_SIZE ) || 1;
        }
    );
}

# The document under $key, built by $build_p when the cache has none. The
# ticket is taken before the build, as the cache's get_or_set takes it, so
# an invalidation during the read keeps the stale document out.
async sub _cached_p ( $self, $key, $build_p ) {
    my ( $cache_key, $entry ) = $self->_cache_entry($key);
    return await $build_p->() if !defined $cache_key;

    my $cache  = $self->cache;
    my $cached = $cache->get($cache_key);
    return $cached if defined $cached;
    if ( $cache->can('ticket') ) {
        $entry->{ticket} = $cache->ticket( $entry->{tags}, { mint => 1 } );
    }
    my $value = await $build_p->();
    $cache->put( $cache_key, $value, $entry );

    return $value;
}

# The cache key and entry options, or nothing when the documents are not
# cached.
sub _cache_entry ( $self, $key ) {
    return
      if !$self->cache
      || ( $self->cache_epoch_required && !defined $self->cache_epoch );
    if ( defined $self->cache_epoch ) {
        $key .= q{:privacy:} . $self->cache_epoch;
    }

    return ( $key,
        { tags => [@CACHE_TAGS], ttl_seconds => $CACHE_TTL_SECONDS } );
}

sub _index ( $self, $pages ) {
    my $base    = $self->builder->canonical_url->base_url;
    my @entries = map { { loc => "$base/sitemap-$_.xml" } } 1 .. $pages;
    return $self->builder->render_index( \@entries );
}

sub _page ( $self, $page, $rows ) {
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

=head2 sitemap_index_p

Resolves with the sitemap index, naming every numbered 1000-resource page;
an optional query context last. C<sitemap_index> is its blocking twin.

=head2 page_p

Takes a positive page number and an optional query context. Resolves with
the page's public resource URL set, or undef past the last page. Page one
also carries the legal pages. C<page> is its blocking twin.

=head2 pages_p

Resolves with how many pages the sitemap has, at least one; an optional
query context last. C<pages> is its blocking twin.

With a C<cache>, the index, the pages and their count are kept for an hour under the tags
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
