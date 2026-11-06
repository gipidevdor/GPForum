# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;
use Const::Fast;
use List::Util qw(any);
use Test::More;
use Test::Fatal;
use Test::Mojo;
use lib 'lib';
use lib 't/lib';
use GPForum::Test::PgDatabase;
use GPForum::Service::Forum::ThreadTags;
use GPForum::Service::Forum::Viewer;
use GPForum::Service::Search::Searcher;
use GPForum::Service::Search::Indexer;
use GPForum::Infrastructure::Id;

our $VERSION = '0.001';
const my $PAGE_LIMIT       => 25;
const my $OVERLONG_SLUG    => 31;
const my $HTTP_OK          => 200;
const my $HTTP_BAD_REQUEST => 400;
if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'set GPFORUM_TEST_DSN for combined tag filters';
}
my $database = GPForum::Test::PgDatabase->fresh( seed => 1 );
local $ENV{GPFORUM_DATABASE_DSN}              = $database->dsn;
local $ENV{GPFORUM_REALTIME_LISTENER_ENABLED} = 0;
local $ENV{GPFORUM_MINION_ENABLED}            = 0;
my $dbh    = $database->dbh;
my $schema = $database->schema;
my $tags   = GPForum::Service::Forum::ThreadTags->new( schema => $schema );
my $viewer = GPForum::Service::Forum::Viewer->anonymous;
my $rows   = $dbh->selectall_arrayref(
q{SELECT t.thread_id, t.category_id FROM threads t JOIN categories c USING(category_id) JOIN spaces s USING(space_id) WHERE t.visibility='public' AND c.visibility='public' AND s.visibility='public' AND t.deleted_at IS NULL AND t.moderation_state='visible' ORDER BY t.thread_id LIMIT 3},
    { Slice => {} }
);
my ( $both, $one, $other ) = map { $_->{thread_id} } @{$rows};
$tags->set_thread_tags( $both,  'alpha,beta' );
$tags->set_thread_tags( $one,   'alpha' );
$tags->set_thread_tags( $other, 'gamma' );

sub listed ( $text, $match = 'all', $after = undef, $limit = $PAGE_LIMIT ) {
    return $tags->filter_page(
        {
            tags      => $text,
            tag_match => $match,
            viewer    => $viewer,
            after     => $after,
            limit     => $limit
        }
    );
}

sub ids ($page) {
    return [ sort map { $_->get_column('thread_id') } @{ $page->{items} } ];
}

subtest 'set semantics, bounds and keyset pagination' => sub {
    is_deeply( ids( listed('alpha,beta') ), [$both], 'AND requires every tag' );
    is_deeply(
        ids( listed( 'alpha,beta', 'any' ) ),
        [ sort $both, $one ],
        'OR returns each thread once'
    );
    is_deeply(
        ids( listed('alpha,alpha') ),
        [ sort $both, $one ],
        'duplicates are one requirement'
    );
    is_deeply( ids( listed('alpha,missing') ),
        [], 'unknown tag makes AND empty' );
    is_deeply(
        ids( listed( 'alpha,missing', 'any' ) ),
        [ sort $both, $one ],
        'unknown tag adds nothing to OR'
    );
    my $first = listed( 'alpha', 'all', undef, 1 );
    ok( $first->{has_next}, 'there is another page' );
    my $next = listed( 'alpha', 'all', $first->{next_cursor}, 1 );
    is_deeply(
        [ sort @{ ids($first) }, @{ ids($next) } ],
        [ sort $both,            $one ],
        'keyset pages are complete and disjoint'
    );
    ok( !$next->{has_next}, 'last page ends' );

    for my $invalid ( q{}, 'alpha,', 'a,b,c,d,e,f', 'alpha,../beta',
        'x' x $OVERLONG_SLUG )
    {
        ok( exception { listed($invalid) }, 'invalid filter is refused' );
    }
    ok( exception { listed( 'alpha', 'none' ) },
        'invalid operator is refused' );
};

subtest 'visibility and deletion are checked before the page limit' => sub {
    $dbh->do( q{UPDATE threads SET visibility='members' WHERE thread_id=?},
        undef, $both );
    is_deeply( ids( listed('alpha') ),
        [$one], 'members-only content is excluded' );
    $dbh->do( q{UPDATE threads SET visibility='public' WHERE thread_id=?},
        undef, $both );
    $dbh->do( q{UPDATE categories SET deleted_at=now() WHERE category_id=?},
        undef, $rows->[0]{category_id} );
    my %removed = map { $_->{thread_id} => 1 }
      grep { $_->{category_id} eq $rows->[0]{category_id} } @{$rows};
    ok( !any { $removed{$_} } @{ ids( listed( 'alpha', 'any' ) ) },
        'deleted category contributes no rows' );
    $dbh->do( q{UPDATE categories SET deleted_at=NULL WHERE category_id=?},
        undef, $rows->[0]{category_id} );
};

subtest 'full-text and tag-only search filter before the candidate cap' => sub {
    my $indexer = GPForum::Service::Search::Indexer->new( schema => $schema );
    for my $id ( $both, $one, $other ) {
        $dbh->do(
q{UPDATE threads SET title='tagfilterneedle discussion' WHERE thread_id=?},
            undef, $id
        );
        $indexer->index_thread($id);
    }
    my $search = GPForum::Service::Search::Searcher->new(
        schema          => $schema,
        candidate_limit => 1
    );
    my $result = $search->search( {}, 'tagfilterneedle',
        { tags => 'alpha,beta', scope => 'threads' } );
    is_deeply( [ map { $_->{entity_id} } @{$result} ],
        [$both], 'tag intersection is applied before the one-candidate cap' );
    is_deeply(
        [
            map { $_->{entity_id} } @{
                $search->search( {}, q{},
                    { tags => 'alpha,beta', scope => 'threads' } )
            }
        ],
        [$both],
        'tag-only search works'
    );
    my $legacy = GPForum::Service::Search::Searcher->new(
        schema          => $schema,
        functions       => undef,
        candidate_limit => 1
    );
    is_deeply(
        [
            map { $_->{entity_id} } @{
                $legacy->search( {}, q{},
                    { tags => 'alpha,beta', scope => 'threads' } )
            }
        ],
        [$both],
'the legacy comparison binds a valid tag array and preserves the same intersection'
    );
    is_deeply(
        $search->search( {}, 'tagfilterneedle', { tags => 'alpha,missing' } ),
        [], 'unknown AND tag gives no text results' );
};

subtest 'SSR and JSON forms preserve filters and reject malformed requests' =>
  sub {
    my $web = Test::Mojo->new('GPForum');
    $web->get_ok('/tagged?tags=alpha,beta')
      ->status_is($HTTP_OK)
      ->element_exists('form input[name=tags]');
    $web->content_like(qr/tagfilterneedle/msx);
    $web->get_ok( '/tagged?tags=alpha,beta&tag_match=any' =>
          { Accept => 'application/json' } )
      ->status_is($HTTP_OK)
      ->json_is( '/filters/tag_match' => 'any' );
    $web->get_ok('/tagged?tags=alpha,')->status_is($HTTP_BAD_REQUEST);
    $web->get_ok(
        '/search?tags=alpha,beta' => { Accept => 'application/json' } )
      ->status_is($HTTP_OK)
      ->json_is( '/filters/tags' => 'alpha,beta' );
    $web->get_ok('/search?tags=alpha&tag_match=invalid')
      ->status_is($HTTP_BAD_REQUEST);
  };
done_testing();

1;
