# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;
use Test::More;
use Const::Fast;
use lib 'lib';
use lib 't/lib';
use GPForum::Service::Operations::LocalCache;
use GPForum::Test::PublicPageController;
use GPForum::Web::PublicHttpCache;

our $VERSION = '0.001';
const my $HTTP_OK           => 200;
const my $HTTP_NOT_MODIFIED => 304;

my $cache   = GPForum::Service::Operations::LocalCache->new;
my $before  = _guarded(0);
my $after   = _guarded(1);
my $page    = GPForum::Test::PublicPageController->new;
my $options = { key => 'public:page', tags => ['forum:public-html'] };
ok( !$before->serve_cached( $page, $options ), 'the first rendering misses' );
_render( $before, $page, $options );
my $old_etag = $page->res->headers->etag;
ok( $before->serve_cached( $page, { key => 'public:page' } ),
    'a current epoch serves its cached page' );
ok(
    !$after->serve_cached( $page, { key => 'public:page' } ),
    'a committed revocation retires the old page without a purge'
);

# A rendering that began before revocation must stay under that old epoch,
# even when it is stored after the revocation committed.
_render( $before, $page, $options );
ok(
    !$after->serve_cached( $page, { key => 'public:page' } ),
    'a late old rendering cannot fill the new epoch'
);

my $conditional = GPForum::Test::PublicPageController->new(
    if_none_match     => $old_etag,
    if_modified_since => 'Thu, 01 Jan 2099 00:00:00 GMT',
);
_render( $after, $conditional, { key => 'public:page' } );
is( $conditional->last_render->{status},
    $HTTP_OK,
    'an old ETag and later date cannot validate a revoked representation' );
isnt( $conditional->res->headers->etag,
    $old_etag, 'even an unchanged body has a new validator after revocation' );
is( $conditional->res->headers->last_modified,
    undef, 'seconds-resolution dates cannot validate guarded pages' );
is(
    $conditional->res->headers->cache_control,
    'public, max-age=0, must-revalidate',
    'downstream caches must ask again'
);
my $fresh = GPForum::Test::PublicPageController->new(
    if_none_match => $conditional->res->headers->etag );
ok(
    $after->serve_cached( $fresh, { key => 'public:page' } ),
    'a current validator can still use the application cache'
);
is( $fresh->last_render->{status},
    $HTTP_NOT_MODIFIED, 'and receives a safe 304' );

my $unavailable = _guarded(undef);
my $outage      = GPForum::Test::PublicPageController->new;
ok( !$unavailable->serve_cached( $outage, { key => 'public:page' } ),
    'an unavailable epoch cannot serve a cached page' );
my $entries = scalar keys %{ $cache->entries };
_render( $unavailable, $outage, { key => 'public:page' } );
is( scalar keys %{ $cache->entries },
    $entries, 'and cannot store an unguarded rendering' );
is( $outage->last_render->{template},
    'forum/categories', 'the request renders from its source instead' );

done_testing();

sub _guarded ($epoch) {
    return GPForum::Web::PublicHttpCache->new(
        cache                => $cache,
        cache_epoch          => $epoch,
        cache_epoch_required => 1
    );
}

sub _render ( $http, $controller, $options ) {
    return $http->render(
        controller => $controller,
        template   => 'forum/categories',
        status     => $HTTP_OK,
        %{$options},
    );
}

1;
