# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Forum::CategoryReader;

use Const::Fast;
use Digest::SHA qw(sha256_hex);
use Mojo::Base 'GPForum::Base', -async_await;
use v5.40;

use GPForum::Infrastructure::ResultRow;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Service::Forum::Viewer;
use GPForum::Service::Forum::Visibility;
use GPForum::X::Unavailable;

our $VERSION = '0.001';

const my $DEFAULT_LIMIT             => 100;
const my $MAX_LIMIT                 => 200;
const my $DEFAULT_CACHE_TTL_SECONDS => 30;

# How much of the grants' digest names a cache entry: 64 bits of SHA-256,
# enough to tell one set of grants from another in a key kept short.
const my $DIGEST_LENGTH => 16;

# What goes on in a category, for the index, as the query-plan evidence's
# resultset reads it: how many discussions the viewer may read in it, and
# when the last of them moved. One lookup each over the category's live
# threads, as api.forum_list_categories answers them; the viewer's standing decides which visibilities count, and is
# written as one of three constant conditions, never from input.
const my $CATEGORY_THREADS => <<'SQL';
FROM threads thread
WHERE thread.category_id = me.category_id
  AND thread.deleted_at IS NULL
  AND thread.moderation_state IN ('visible', 'locked')
  AND %s
SQL
const my %THREAD_VISIBILITY => (
    anonymous => q{thread.visibility = 'public'},
    global    => q{TRUE},
    member    => q{thread.visibility IN ('public', 'members')},
);

__PACKAGE__->requires('schema');

has cache       => undef;    # optional: without it nothing is cached
has cache_epoch => undef;    # optional: missing required epoch bypasses cache
has cache_epoch_required => 0;
has cache_ttl_seconds    => sub { return $DEFAULT_CACHE_TTL_SECONDS; };
has functions            => \&GPForum::Infrastructure::SqlFunction::for_service;

# Each read is written once, as its promise method (ADR 0177).
GPForum::Infrastructure::SqlFunction->blocking_twins(
    qw(list_categories find_category));

# ADR 0102: only the categories the viewer can read, judged on the category
# and its space in the query. A request without a viewer reads as anonymous.
# Every list is cached, under the standing that decides it -- anonymous,
# member, global reader -- and, as a digest, the grants that let the viewer
# into private categories: a member whose grants change reads under another
# key at once, and what a category shows changes through the tags. Only the
# anonymous list used to be, so every signed-in reader of the index had
# every live thread of every category counted again for them.
#
# The cache holds the plain column hashes the function answers: GlifiStore
# holds JSON, and every reader of the list (the view models, the home page,
# the sitemap) takes a hash as readily as a row.
async sub list_categories_p ( $self, $request, $context = undef ) {
    my $limit = _bounded_limit( $request ? $request->{limit} : undef );
    my $call  = $self->categories_call( $limit, _viewer($request) );
    if ( !$self->_caches ) {
        return [ map { GPForum::Infrastructure::ResultRow->from($_) }
              @{ await $self->_functions->rows_p( @{$call}, $context ) } ];
    }

    my $key    = $self->_cache_key( $limit, _viewer($request) );
    my $cached = $self->cache->get($key);
    return $cached if defined $cached;
    my $options = {
        tags        => [ 'categories', 'forum-index' ],
        ttl_seconds => $self->cache_ttl_seconds
    };
    if ( $self->cache->can('ticket') ) {
        $options->{ticket} =
          $self->cache->ticket( $options->{tags}, { mint => 1 } );
    }
    my $rows = await $self->_functions->rows_p( @{$call}, $context );

    return $self->cache->put( $key, $rows, $options );
}

sub _caches ($self) {
    return $self->cache
      && ( !$self->cache_epoch_required || defined $self->cache_epoch );
}

# The category, if it exists and the viewer can read it; otherwise nothing,
# so the caller answers 404 and existence is not confirmed.
async sub find_category_p ( $self, $category_id, $viewer = undef,
    $context = undef )
{
    return undef if !defined $category_id || !length $category_id;
    my $row = GPForum::Infrastructure::ResultRow->from(
        await $self->_functions->row_p(
            'forum_find_category', { category_id => $category_id },
            $context
        )
    );
    return undef if !$row || defined $row->get_column('deleted_at');

    return _readable_category( $row, $viewer ) ? $row : undef;
}

sub _readable_category ( $row, $viewer ) {
    return GPForum::Service::Forum::Visibility->readable(
        GPForum::Service::Forum::Viewer->from($viewer),
        {
            category_id         => $row->get_column('category_id'),
            category_visibility => $row->get_column('visibility'),
            space_id            => $row->get_column('space_id'),
            space_visibility    => $row->get_column('space_visibility'),
        }
    );
}

sub _viewer ($request) {
    my $viewer = ref $request eq 'HASH' ? $request->{viewer} : undef;

    return $viewer || GPForum::Service::Forum::Viewer->anonymous;
}

sub _cache_key ( $self, $limit, $viewer ) {
    my $key = join q{:}, 'categories', 'list', _standing($viewer),
      _grants_digest($viewer), $limit;
    if ( defined $self->cache_epoch ) {
        $key .= q{:privacy:} . $self->cache_epoch;
    }

    return $key;
}

# The standing the list is decided by: which thread visibilities count, and
# which categories a reader without grants sees.
sub _standing ($viewer) {
    return 'global' if $viewer->global_read;
    return 'member' if $viewer->member;

    return 'anonymous';
}

# The grants' fingerprint: the category and space ids a viewer holds
# category.read on, sorted and hashed, so the key stays short however many
# there are; "none" without any, which every anonymous reader shares.
sub _grants_digest ($viewer) {
    my @grants = (
        ( map { "category:$_" } @{ $viewer->category_ids } ),
        ( map { "space:$_" } @{ $viewer->space_ids } ),
    );
    return 'none' if !@grants;

    return substr sha256_hex( join "\n", sort @grants ), 0, $DIGEST_LENGTH;
}

# The list's call, shared with the query-plan evidence.
sub categories_call ( $self, $limit, $viewer = undef ) {
    my $scope = $viewer || GPForum::Service::Forum::Viewer->anonymous;
    return [
        'forum_list_categories',
        {
            category_ids => $scope->category_ids,
            global_read  => $scope->global_read,
            member       => $scope->member,
            row_limit    => $limit,
            space_ids    => $scope->space_ids,
        }
    ];
}

# The list as a resultset, kept only for the query-plan evidence
# (Benchmark::QueryPlanEndpoints), which compares it with the function.
sub categories_resultset ( $self, $limit, $viewer = undef ) {
    my $readable = GPForum::Service::Forum::Visibility->readable_condition(
        $viewer || GPForum::Service::Forum::Viewer->anonymous,
        {
            category    => 'me.visibility',
            category_id => 'me.category_id',
            space       => 'space.visibility',
            space_id    => 'me.space_id',
        }
    );

    my $scope   = $viewer || GPForum::Service::Forum::Viewer->anonymous;
    my $threads = sprintf $CATEGORY_THREADS,
      $THREAD_VISIBILITY{
          $scope->global_read ? 'global'
        : $scope->member      ? 'member'
        :                       'anonymous'
      };

    return $self->schema->resultset('Category')->search_rs(
        { 'me.deleted_at' => undef, %{$readable} },
        {
            join      => 'space',
            '+select' => [
                \"(SELECT count(*) $threads)",
                \"(SELECT max(thread.last_activity_at) $threads)",
            ],
            '+as'    => [ 'thread_count', 'last_activity_at' ],
            order_by => [
                { -asc => 'me.position' },
                { -asc => 'me.title' },
                { -asc => 'me.category_id' },
            ],
            rows => $limit,
        }
    );
}

sub _functions ($self) {
    return $self->functions // GPForum::X::Unavailable->throw(
        message => 'categories need the PostgreSQL function layer' );
}

sub _bounded_limit ($requested) {
    return $DEFAULT_LIMIT if !defined $requested;
    return $DEFAULT_LIMIT if $requested !~ /\A [[:digit:]]+ \z/amsx;
    return $DEFAULT_LIMIT if $requested < 1;
    return $MAX_LIMIT     if $requested > $MAX_LIMIT;

    return int $requested;
}

1;

__END__

=head1 NAME

GPForum::Service::Forum::CategoryReader - The categories a viewer can read, each standing's list cached.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $reader = GPForum::Service::Forum::CategoryReader->new(
        cache             => $cache,
        cache_ttl_seconds => 30,
        schema            => $schema,
    );
    my $categories =
      $reader->list_categories( { limit => 50, viewer => $viewer } );
    my $category = $reader->find_category( $category_id, $viewer );
    my $rs       = $reader->categories_resultset( 100, $viewer );

=head1 DESCRIPTION

The read side of forum categories: the category index, the home page, the
sitemap, the new thread form and a thread's move form list them through this
module, the category page finds its category with it, and the posting
workflow checks with it the category a thread is created in or moved to.

Visibility follows ADR 0102. A category is listed or found only when the
viewer can read both the category and its space, judged by
L<GPForum::Service::Forum::Visibility>. The list applies that rule in the
query, before the row limit, so a page is never short of readable
categories. A deleted category (C<deleted_at> set) is never returned.

The list and lookup call C<api.forum_list_categories> and
C<api.forum_find_category>. The list returns plain column rows, with
visibility filtered before its limit; the lookup checks visibility on its
returned columns. Each read is written once, as its promise method; the
blocking methods are its twins (ADR 0177).

Every list is cached, under the standing that decides it. Each limit is its
own entry, under
C<categories:list:E<lt>standingE<gt>:E<lt>grantsE<gt>:E<lt>limitE<gt>>:
the standing C<anonymous>, C<member> or C<global> (which thread
visibilities count, and which categories a reader without grants sees),
and the grants as a digest of the category and space ids the viewer holds
C<category.read> on, C<none> without any. A member whose grants change
reads under another key at once. The entries are tagged C<categories> and
C<forum-index>, for C<cache_ttl_seconds>, with a ticket minted for the
tags when the cache issues them. The cached elements are plain hashes of
the category's columns, not rows: the shared layer (GlifiStore, through
L<GPForum::Service::Operations::TieredCache>) holds JSON. The outbox's cache
invalidation handler (L<GPForum::Worker::Handler::CacheInvalidation>) and
the console's purge (L<GPForum::Service::Admin::Maintenance>) drop the list
through those tags. A single category (L</find_category_p>) is never
cached.

=head1 SUBROUTINES/METHODS

=head2 new

Constructor (L<GPForum::Base>). C<schema>, required (without it C<new>
throws L<GPForum::X::Argument>), is the L<DBIx::Class> schema whose
C<Category> result source joins its C<space>. C<cache> is optional: any
object with C<get( $key )> and C<put( $key, $value, { tags =E<gt> [...],
ttl_seconds =E<gt> $n } )>, and C<ticket> when it issues tickets, such as L<GPForum::Service::Operations::LocalCache> or
L<GPForum::Service::Operations::TieredCache>; without one nothing is cached.
C<cache_ttl_seconds> is each list's lifetime (30 by default).

=head2 list_categories_p

Takes a hash reference with C<limit> and C<viewer>; the argument must be
passed but may be C<undef>, which reads as the default limit and an
anonymous viewer. The limit is bounded: absent, not made only of digits, or
below 1 gives 100, and above 200 gives 200. The viewer is a
L<GPForum::Service::Forum::Viewer>; none reads as anonymous.

Answers an array reference of the readable, non-deleted categories ordered
by position, title and category id. When a cache is set, the list comes
from the cache (read and stored on a miss, under the viewer's standing
and grants) and its elements are plain hashes of the category's columns;
otherwise its elements are L<GPForum::Infrastructure::ResultRow> rows. Its
readers (the view models, the home page, the sitemap) take either shape.

=head2 find_category_p

Takes a category id and an optional viewer: a
L<GPForum::Service::Forum::Viewer>, a bare user id (read as a non-member
with that id), or nothing for anonymous
(L<GPForum::Service::Forum::Viewer/from>). Answers the category row, with
its space's visibility as the extra column C<space_visibility>, when the
category exists, is not deleted and the viewer can read it and its space.
Otherwise, and for an undefined or empty id, answers C<undef>, so the caller
answers 404 and does not confirm that the category exists.

=head2 list_categories, find_category

The blocking twins: each is its C<_p> method run on the blocking call layer
(ADR 0177), answering the value instead of a promise. Each C<_p> method
takes an optional query context last.

=head2 categories_resultset

Takes a row limit and an optional L<GPForum::Service::Forum::Viewer>
(nothing reads as anonymous). Returns, unexecuted, the list as a
resultset, kept only for the query-plan evidence: non-deleted categories joined to their space,
restricted by L<GPForum::Service::Forum::Visibility/readable_condition>,
ordered by position, title and category id, with the limit as its row
count. The limit is used as given, not bounded. The query-plan evidence
(L<GPForum::Command::QueryPlanEvidence>) compares it with the function.

=head2 categories_call

Takes a limit and an optional viewer. Returns the catalogue name and bound
parameters the PostgreSQL category list executes, so nested plan evidence
can inspect the same call.

=head1 DIAGNOSTICS

Fails when the database does. Errors from the cache propagate from
L</list_categories_p>, which also fails when called with no argument, or
with a true argument that is not a hash reference. A viewer given to
L</list_categories_p> or L</categories_resultset> must be a
L<GPForum::Service::Forum::Viewer> object: only L</find_category_p>
converts a bare user id, and either method dies on one. Without the
PostgreSQL function layer each read raises L<GPForum::X::Unavailable>.

=head1 CONFIGURATION AND ENVIRONMENT

C<cache_epoch> namespaces cached source data by the request's committed
public-content revocation epoch. C<cache_epoch_required> bypasses caching
when that epoch is unavailable; production enables this guard.

None directly. L<GPForum::Bootstrap::Forum> sets C<cache> to the
application cache and C<cache_ttl_seconds> from the configuration's
C<category_cache_ttl_seconds>.

=head1 DEPENDENCIES

L<Mojo::Base>, L<Const::Fast>, L<GPForum::Service::Forum::Viewer>,
L<GPForum::Service::Forum::Visibility>, L<GPForum::Base>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

The list's shape depends on whether it came from the cache: plain hashes
for a cached anonymous list, C<Category> rows otherwise. A change to a
category whose invalidation is missed leaves the cached anonymous list stale
for up to C<cache_ttl_seconds>.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
