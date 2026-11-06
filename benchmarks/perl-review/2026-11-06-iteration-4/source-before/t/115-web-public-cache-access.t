# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use lib 'lib';
use lib 't/lib';

use Const::Fast;
use GPForum::Test::PublicCacheRequest;
use GPForum::Web::PublicCacheAccess;
use GPForum::Web::PublicHttpCache;
use GPForum::Service::Operations::LocalCache;
use GPForum::Test::PublicPageController;
use GPForum::Test::ReplacedSubs qw(with_replaced_subs);
use Mojo::Date;
use Test::More;

our $VERSION = '0.001';

const my $EPOCH             => 1_716_464_000;
const my $ETAG              => 'W/"abc123"';
const my $HTTP_OK           => 200;
const my $HTTP_NOT_MODIFIED => 304;

my $access = GPForum::Web::PublicCacheAccess->new;
my $get    = GPForum::Test::PublicCacheRequest->new;
ok( $access->is_cacheable($get), 'is_cacheable accepts anonymous GET' );

my $head = GPForum::Test::PublicCacheRequest->new( method => 'HEAD' );
ok( $access->is_cacheable($head), 'is_cacheable accepts anonymous HEAD' );

my $post = GPForum::Test::PublicCacheRequest->new( method => 'POST' );
ok( !$access->is_cacheable($post), 'is_cacheable rejects POST' );

my $member =
  GPForum::Test::PublicCacheRequest->new( session_user_id => 'user-1', );
ok( !$access->is_cacheable($member),
    'is_cacheable rejects an authenticated GET' );

ok(
    $access->etag_matches( $ETAG, $ETAG ),
    'etag_matches accepts the exact ETag'
);
ok( $access->etag_matches( q{*}, $ETAG ),
    'etag_matches accepts a wildcard If-None-Match' );
ok( $access->etag_matches( join( q{, }, $ETAG, 'W/"other"' ), $ETAG ),
    'etag_matches accepts a listed ETag' );
ok(
    !$access->etag_matches( 'W/"other"', $ETAG ),
    'etag_matches rejects a different ETag'
);
ok(
    !$access->etag_matches( undef, $ETAG ),
    'etag_matches rejects a missing candidate'
);

my $date = Mojo::Date->new($EPOCH)->to_string;
ok(
    $access->modified_since_matches( $date, $EPOCH ),
    'modified_since_matches accepts an equal Last-Modified'
);
ok(
    !$access->modified_since_matches( $date, $EPOCH + 1 ),
    'modified_since_matches rejects a newer cache entry'
);
ok(
    !$access->modified_since_matches( 'not-a-date', $EPOCH ),
    'modified_since_matches rejects an unparsable date'
);

for my $out_of_range (
    'Sun, 32 Jan 2026 00:00:00 GMT',
    'Sun, 06 Nov 1994 25:61:00 GMT',
    'Tue, 31 Feb 2026 00:00:00 GMT',
  )
{
    ok(
        !$access->modified_since_matches( $out_of_range, $EPOCH ),
        "modified_since_matches rejects a date out of range: $out_of_range"
    );
}

my $fresh = GPForum::Test::PublicCacheRequest->new( if_none_match => $ETAG );
ok(
    $access->client_has_fresh_copy(
        $fresh, { etag => $ETAG, last_modified_epoch => $EPOCH }
    ),
    'client_has_fresh_copy follows If-None-Match'
);

my $stale = GPForum::Test::PublicCacheRequest->new;
ok(
    !$access->client_has_fresh_copy(
        $stale, { etag => $ETAG, last_modified_epoch => $EPOCH }
    ),
    'client_has_fresh_copy is false without conditional headers'
);

is( $access->revalidated_state('hit'),
    'revalidated', 'revalidated_state labels a hit' );
is( $access->revalidated_state('miss'),
    'miss-revalidated', 'revalidated_state labels a stored miss' );

subtest 'If-None-Match uses weak comparison and quoted list members' => sub {
    for my $case (
        [ q{"abc123"},                  $ETAG,            1 ],
        [ $ETAG,                        q{"abc123"},      1 ],
        [ q{W/""},                      q{""},            1 ],
        [ q{"other", "a,b"},            q{W/"a,b"},       1 ],
        [ q{"a,b"},                     q{"a"},           0 ],
        [ q{W/"literal\tag"},           q{"literal\tag"}, 1 ],
        [ " \t*\t ",                    $ETAG,            1 ],
        [ q{,, W/"other",, "abc123", }, $ETAG,            1 ],
        [ q{garbage,"abc123"},          $ETAG,            0 ],
        [ q{"abc123",garbage},          $ETAG,            0 ],
        [ q{*, "abc123"},               $ETAG,            0 ],
        [ q{"abc123"junk},              $ETAG,            0 ],
        [ q{w/"abc123"},                $ETAG,            0 ],
        [ q{W/"ABC123"},                $ETAG,            0 ],
        [ q{garbage},                   q{garbage},       0 ],
      )
    {
        is( $access->etag_matches( $case->[0], $case->[1] ),
            $case->[2], "comparison of $case->[0] against $case->[1]" );
    }
};

subtest 'an ETag decides freshness without parsing a competing date' => sub {
    my $date_checks = 0;
    my $modified_since =
      GPForum::Web::PublicCacheAccess->can('modified_since_matches');
    with_replaced_subs(
        'GPForum::Web::PublicCacheAccess',
        {
            modified_since_matches => sub ( $self, @args ) {
                ++$date_checks;
                return $modified_since->( $self, @args );
            },
        },
        sub {
            for my $candidate ( 'W/"old"', q{}, 'malformed' ) {
                my $request = GPForum::Test::PublicCacheRequest->new(
                    if_none_match     => $candidate,
                    if_modified_since => $date,
                );
                ok(
                    !$access->client_has_fresh_copy(
                        $request,
                        { etag => $ETAG, last_modified_epoch => $EPOCH }
                    ),
                    'a nonmatching or invalid ETag cannot fall back to the date'
                );
            }
            is( $date_checks, 0,
'If-Modified-Since is never consulted while If-None-Match is present'
            );
        }
    );
    my $date_only =
      GPForum::Test::PublicCacheRequest->new( if_modified_since => $date );
    ok(
        $access->client_has_fresh_copy(
            $date_only, { etag => $ETAG, last_modified_epoch => $EPOCH }
        ),
        'date-only clients retain their validator'
    );
};

subtest 'cached responses use the same validators as direct decisions' => sub {
    my $http_cache = GPForum::Web::PublicHttpCache->new(
        cache => GPForum::Service::Operations::LocalCache->new, );
    my $page = GPForum::Test::PublicPageController->new;
    $http_cache->render(
        controller => $page,
        key        => 'page',
        template   => 'page',
        status     => $HTTP_OK
    );
    my $entry_tag      = $page->res->headers->etag;
    my $stale_response = GPForum::Test::PublicPageController->new(
        if_none_match     => 'W/"stale"',
        if_modified_since => 'Thu, 01 Jan 2099 00:00:00 GMT',
    );
    ok( $http_cache->serve_cached( $stale_response, { key => 'page' } ),
        'the cache answers the request' );
    is( $stale_response->last_render->{status},
        $HTTP_OK, 'a changed ETag receives the current representation' );
    is( $stale_response->last_render->{data},
        '<p>page</p>', 'the current body is sent' );
    my $strong = $entry_tag =~ s/\A W\///rmsx;
    my $fresh_response =
      GPForum::Test::PublicPageController->new( if_none_match => $strong );
    $http_cache->serve_cached( $fresh_response, { key => 'page' } );
    is( $fresh_response->last_render->{status},
        $HTTP_NOT_MODIFIED,
        'a strong spelling of the current weak tag revalidates' );
    is( $fresh_response->last_render->{data}, q{}, 'the 304 has no body' );
};

done_testing();

1;
