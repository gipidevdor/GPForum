# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use Test::More;

use lib 'lib';

use GPForum::Infrastructure::ResultRow::Thread;
use GPForum::Service::Discovery::CanonicalUrl;
use GPForum::Service::Discovery::FeedBuilder;
use GPForum::Service::Discovery::MetadataBuilder;
use GPForum::Service::Discovery::RobotsPolicy;
use GPForum::Service::Discovery::SitemapBuilder;
use GPForum::Service::Discovery::VisibilityPolicy;
use GPForum::ViewModel::Discovery::Presenter;

our $VERSION = '0.001';

const my $EXPECTED_TESTS       => 44;
const my $VISIBLE_THREAD_COUNT => 1;
const my $LEGAL_PAGE_COUNT     => 3;
const my $ROBOT_RULE_COUNT     => 6;
const my $CATEGORY_ID          => '018f1001-0001-7000-8000-000000000001';

plan tests => $EXPECTED_TESTS;

my $canonical =
  GPForum::Service::Discovery::CanonicalUrl->new(
    base_url => 'https://forum.gp' );

is(
    $canonical->category_url( { category_id => $CATEGORY_ID, slug => 'news' } ),
    "https://forum.gp/c/$CATEGORY_ID",
    q{a category's canonical url is its page, by id: no route takes a slug}
);
is(
    $canonical->thread_url(
        {
            thread_id => 'thread-1',
            slug      => 'welcome',
        }
    ),
    'https://forum.gp/t/thread-1/welcome',
    'canonical thread url includes id and slug'
);
is(
    $canonical->thread_url( { thread_id => 'thread-2' } ),
    'https://forum.gp/t/thread-2/untitled',
    'canonical thread url handles missing slug'
);
is(
    $canonical->thread_url(
        {
            thread_id => 'thread-3',
            slug      => "perch\N{LATIN SMALL LETTER E WITH ACUTE}"
        }
    ),
    'https://forum.gp/t/thread-3/perch%C3%A9',
    'an accented slug is percent-encoded as UTF-8: a URI, not an IRI'
);
is(
    $canonical->legal_url('terms'),
    'https://forum.gp/legal/terms',
    'canonical terms url is stable'
);
is(
    $canonical->legal_url('privacy'),
    'https://forum.gp/legal/privacy',
    'canonical privacy url is stable'
);
ok( !$canonical->legal_url('unknown'),
    'canonical legal url rejects an unknown page' );

my $metadata =
  GPForum::Service::Discovery::MetadataBuilder->new(
    canonical_url => $canonical );
my $visible_thread = {
    thread_id        => 'thread-1',
    slug             => 'welcome',
    title            => 'Welcome',
    visibility       => 'public',
    moderation_state => 'visible',
    last_activity_at => '2026-05-23T12:00:00Z',
};
my $thread_metadata = $metadata->thread_metadata(
    $visible_thread,
    {
        safe_text => '<p>Hello safe public world</p>',
    }
);
is( $thread_metadata->{title}, 'Welcome', 'metadata exposes safe title' );
is(
    $thread_metadata->{description},
    'Hello safe public world',
    'metadata strips html from description'
);
is(
    $thread_metadata->{canonical},
    'https://forum.gp/t/thread-1/welcome',
    'metadata includes canonical url'
);
is( $thread_metadata->{robots}, 'index,follow',
    'public metadata is indexable' );
is( $thread_metadata->{open_graph}{title},
    'Welcome', 'metadata includes safe OpenGraph title' );
is(
    $thread_metadata->{open_graph}{description},
    'Hello safe public world',
    'metadata includes safe OpenGraph description'
);
is(
    $thread_metadata->{open_graph}{url},
    'https://forum.gp/t/thread-1/welcome',
    'metadata includes safe OpenGraph url'
);

my $private_metadata = $metadata->thread_metadata(
    {
        %{$visible_thread}, visibility => 'private',
    },
    {
        safe_text => 'secret',
    }
);
is( $private_metadata->{robots},
    'noindex,nofollow', 'private thread metadata is noindex' );
ok(
    !exists $private_metadata->{description},
    'private thread metadata does not leak description'
);
ok( !exists $private_metadata->{open_graph},
    'private thread metadata does not leak OpenGraph data' );

my $visibility_policy = GPForum::Service::Discovery::VisibilityPolicy->new;
ok(
    $visibility_policy->is_public($visible_thread),
    'visibility policy allows visible public resources'
);
ok(
    !$visibility_policy->is_public(
        { %{$visible_thread}, hidden_at => 'now' }
    ),
    'visibility policy blocks hidden resources'
);
ok(
    !$visibility_policy->is_public(
        { %{$visible_thread}, deleted_at => 'now' }
    ),
    'visibility policy blocks deleted resources'
);

# ADR 0102: a thread page's thread carries its category and space, and the
# page is public only if all three are -- a public thread in a members-only
# category is not indexed, even for a member reading it.
ok(
    !$visibility_policy->is_public(
        { %{$visible_thread}, category_visibility => 'members' }
    ),
    'visibility policy blocks a public thread in a members-only category'
);
ok(
    !$visibility_policy->is_public(
        { %{$visible_thread}, space_visibility => undef }
    ),
    'and one whose space visibility is unknown'
);
ok(
    $visibility_policy->is_public(
        {
            %{$visible_thread},
            category_visibility => 'public',
            space_visibility    => 'public'
        }
    ),
    'and allows one public all the way up'
);

my $robots = GPForum::Service::Discovery::RobotsPolicy->new(
    sitemap_url => 'https://forum.gp/sitemap.xml', );
my $rules = $robots->rules( ['/preview'] );
is( scalar @{$rules},
    $ROBOT_RULE_COUNT, 'robots policy combines default rules' );
ok( grep { $_ eq '/admin' } @{$rules}, 'robots policy disallows admin routes' );
ok(
    grep { $_ eq '/search' } @{$rules},
    'robots policy disallows search routes'
);
ok( grep { $_ eq '/preview' } @{$rules}, 'robots policy accepts extra rules' );
my $robots_text = $robots->render( ['/preview'] );
like(
    $robots_text,
    qr/User-agent: [ ] [*]/msx,
    'robots text declares user agent'
);
like(
    $robots_text,
    qr/Disallow: [ ] \/admin/msx,
    'robots text renders admin rule'
);
like(
    $robots_text,
    qr/Sitemap: [ ] https:\/\/forum[.]gp\/sitemap[.]xml/msx,
    'robots text renders sitemap location'
);

my $sitemap =
  GPForum::Service::Discovery::SitemapBuilder->new(
    canonical_url => $canonical );
my $threads = [
    $visible_thread,
    {
        %{$visible_thread},
        thread_id        => 'thread-2',
        slug             => 'hidden',
        moderation_state => 'hidden',
    },
    {
        %{$visible_thread},
        thread_id  => 'thread-3',
        slug       => 'private',
        visibility => 'private',
    },
];
my $legal_entries = $sitemap->legal_entries;
is( scalar @{$legal_entries},
    $LEGAL_PAGE_COUNT, 'sitemap includes public legal pages' );
is(
    $legal_entries->[2]{loc},
    'https://forum.gp/legal/terms',
    'sitemap legal terms loc is canonical'
);
my $xml = $sitemap->render_xml(
    [
        {
            loc     => $canonical->thread_url($visible_thread),
            lastmod => '2026-05-23T12:00:00Z'
        }
    ]
);
like( $xml, qr/<urlset/msx, 'sitemap xml renders urlset' );
like(
    $xml,
    qr/<loc>https:\/\/forum[.]gp\/t\/thread-1\/welcome<\/loc>/msx,
    'sitemap xml renders location'
);

my $feed =
  GPForum::Service::Discovery::FeedBuilder->new( canonical_url => $canonical );
my $feed_threads = [
    +{ %{ $threads->[0] }, excerpt => '<b>Hello</b> safe &amp; public world' },
    @{$threads}[ 1 .. $#{$threads} ],
];
my $items = $feed->thread_items($feed_threads);
my $function_resources =
  GPForum::ViewModel::Discovery::Presenter->new->resources(
    [
        map { GPForum::Infrastructure::ResultRow::Thread->from( { %{$_} } ) }
          @{$feed_threads}
    ]
  );
is_deeply( $feed->thread_items($function_resources),
    $items, 'function rows preserve feed entries and visibility filtering' );
is( scalar @{$items},
    $VISIBLE_THREAD_COUNT, 'feed excludes hidden and private threads' );
is( $items->[0]{id},    'thread-1', 'feed item stores id' );
is( $items->[0]{title}, 'Welcome',  'feed item stores title' );
is(
    $items->[0]{summary},
    'Hello safe & public world',
    'feed item exposes safe excerpt only, as text'
);
ok( !defined $items->[0]{full_body},
    'feed does not expose full body by default' );
my $atom = $feed->render_atom(
    {
        id      => 'https://forum.gp/feed.atom',
        title   => 'GPForum public discussions',
        url     => 'https://forum.gp/feed.atom',
        updated => '2026-05-23T12:00:00Z',
        items   => $items,
    }
);
like(
    $atom,
    qr/<feed [^>]+ xmlns="http:\/\/www[.]w3[.]org\/2005\/Atom"/msx,
    'feed renders atom root'
);
like(
    $atom,
    qr/<title>Welcome<\/title>/msx,
    'feed renders public thread title'
);
like(
    $atom,
    qr{<summary>Hello [ ] safe [ ] &amp; [ ] public [ ] world</summary>}msx,
    'feed renders public safe excerpt, escaped once'
);
unlike(
    $atom,
    qr/secret|private [ ] text/msx,
    'feed does not render non-public content'
);

1;
