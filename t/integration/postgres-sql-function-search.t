# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;
use Const::Fast;
use Digest::SHA qw(sha1_hex);
use Test::More;
use List::Util qw(all);

use lib 'lib';
use lib 't/lib';

use GPForum::Service::Forum::Viewer;
use GPForum::Service::Search::Indexer;
use GPForum::Service::Search::PermissionEngine;
use GPForum::Service::Search::Searcher;
use GPForum::Test::FixedClock;
use GPForum::Test::PgDatabase;

our $VERSION = '0.001';

const my $CANDIDATE_LIMIT => 5;
const my $BATCH_SIZE      => 7;
const my $ROW_LIMIT       => 3;

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'set GPFORUM_TEST_DSN to compare search functions';
}

my $database = GPForum::Test::PgDatabase->fresh( seed => 1 );
my $schema   = $database->schema;
my $dbh      = $database->dbh;
$dbh->do(q{SET client_min_messages = 'warning'});
my $clock   = GPForum::Test::FixedClock->new;
my $indexer = GPForum::Service::Search::Indexer->new(
    schema             => $schema,
    clock              => $clock,
    rebuild_batch_size => $BATCH_SIZE,
);

# A rebuild from nothing indexes every live source -- a thread visible or
# locked, a visible post in such a thread -- under the id derived from it.
$dbh->do('DELETE FROM search_documents');
my ($live) = $dbh->selectrow_array(
        q{SELECT (SELECT count(*) FROM threads WHERE deleted_at IS NULL}
      . q{ AND moderation_state IN ('visible', 'locked'))}
      . q{ + (SELECT count(*) FROM posts p JOIN threads t USING (thread_id)}
      . q{ WHERE p.deleted_at IS NULL AND p.moderation_state = 'visible'}
      . q{ AND t.deleted_at IS NULL}
      . q{ AND t.moderation_state IN ('visible', 'locked'))} );
ok( $live, 'the fixture has live sources' );
my $rebuilt = $indexer->rebuild( { entity_type => 'all' } );
is_deeply(
    [ @{$rebuilt}{qw(indexed pruned unchanged)} ],
    [ $live, 0, 0 ],
    'a rebuild from nothing indexes each live source once'
);
my $documents = _documents();
is( scalar @{$documents}, $live, 'one document per live source' );
is_deeply(
    [ map { $_->{search_document_id} } @{$documents} ],
    [ map { _document_id($_) } @{$documents} ],
    'each under the id derived from its entity'
);
my ($vectors) = $dbh->selectrow_array(
    'SELECT count(*) FROM search_documents WHERE search_vector IS NOT NULL');
is( $vectors, $live, 'each with its search vector' );
my $unchanged = $indexer->rebuild( { entity_type => 'all' } );
is( $unchanged->{indexed}, 0,
    'repeating the rebuild writes no changed document' );
is( $unchanged->{unchanged}, $live, 'every unchanged document is recognized' );
is_deeply( _documents(), $documents, 'and the projection is as it was' );

my $source = $dbh->selectrow_hashref(
        q{SELECT t.thread_id, t.category_id, t.author_user_id, c.space_id}
      . q{ FROM threads t JOIN categories c USING (category_id)}
      . q{ WHERE t.deleted_at IS NULL AND t.moderation_state = 'visible'}
      . q{ ORDER BY t.thread_id LIMIT 1} );
$dbh->do(
    q{UPDATE threads SET title = 'Performance vacuum differential',}
      . q{ version = version + 1 WHERE thread_id = ?},
    undef, $source->{thread_id}
);
$indexer->index_thread( $source->{thread_id} );
$indexer->index_thread_posts( $source->{thread_id} );
my %viewers = (
    anonymous => GPForum::Service::Forum::Viewer->anonymous,
    member    => GPForum::Service::Forum::Viewer->new(
        member  => 1,
        user_id => $source->{author_user_id}
    ),
    suspended => GPForum::Service::Forum::Viewer->new(
        user_id => $source->{author_user_id}
    ),
    category_grant => GPForum::Service::Forum::Viewer->new(
        category_ids => [ $source->{category_id} ]
    ),
    space_grant => GPForum::Service::Forum::Viewer->new(
        member    => 1,
        space_ids => [ $source->{space_id} ]
    ),
    global => GPForum::Service::Forum::Viewer->new(
        member      => 1,
        global_read => 1
    ),
    global_without_member => GPForum::Service::Forum::Viewer->new(
        global_read => 1
    ),
);
my $permissions = GPForum::Service::Search::PermissionEngine->new;
my $searcher    = GPForum::Service::Search::Searcher->new(
    schema            => $schema,
    permission_engine => $permissions,
    candidate_limit   => $CANDIDATE_LIMIT,
);

# Who may read the source thread's category at each level. A grant to the
# category reads it when it is private, not when it is for members, where
# membership is what counts; a global grant without membership is not
# shown a members-only post (the render check refuses what the search
# function's condition lets through, as the forum lists do: see the TODO in
# postgres-sql-function-forum-reads.t).
my %readers = (
    public  => { map { $_ => 1 } keys %viewers },
    members => { map { $_ => 1 } qw(global member space_grant) },
    private => {
        map { $_ => 1 }
          qw(category_grant global global_without_member space_grant)
    },
);
subtest 'each viewer finds only what it may read, at every level' => \&_readers;
my $global = { viewer => $viewers{global} };
subtest 'queries'      => \&_queries;
subtest 'filters'      => \&_filters;
subtest 'autocomplete' => \&_autocomplete;

# A scope narrows search to one kind of document.
for my $scope ( [ threads => 'thread' ], [ posts => 'post' ] ) {
    my ( $asked, $entity_type ) = @{$scope};
    my $results = $searcher->ranked_search( { viewer => $viewers{global} },
        'performance', { limit => $ROW_LIMIT, scope => $asked } )->{results};
    ok( scalar @{$results}, "a $asked scope finds $entity_type documents" );
    ok( ( all { $_->{entity_type} eq $entity_type } @{$results} ),
        'and only those' );
}

my $scoped = $searcher->ranked_search( { viewer => $viewers{global} },
    'performance',
    { limit => 1, thread_id => $source->{thread_id}, scope => 'posts' } )
  ->{results};
ok( @{$scoped}, 'thread scope finds a post with a one-row limit' );
for my $hit ( @{$scoped} ) {
    is(
        $dbh->selectrow_array(
            'SELECT thread_id FROM posts WHERE post_id = ?', undef,
            $hit->{entity_id}
        ),
        $source->{thread_id},
        'scope is applied before the candidate and result limits'
    );
}
is_deeply(
    $searcher->ranked_search(
        { viewer => $viewers{global} },
        'performance',
        { thread_id => 'ffffffff-ffff-ffff-ffff-ffffffffffff' }
    )->{results},
    [],
    'nonexistent thread cannot widen search to the whole community'
);

done_testing();

# The search document id of an entity: a UUID read from the front of the
# SHA-1 of its name.
sub _document_id ($document) {
    my $hex = sha1_hex( join q{:}, 'search_document',
        @{$document}{qw(entity_type entity_id)} );
    return join q{-}, unpack 'A8 A4 A4 A4 A12', $hex;
}

sub _documents {
    return $dbh->selectall_arrayref(
        'SELECT * FROM search_documents ORDER BY entity_type, entity_id',
        { Slice => {} } );
}

sub _readers {
    for my $level (qw(public members private)) {
        $dbh->do( 'UPDATE categories SET visibility = ? WHERE category_id = ?',
            undef, $level, $source->{category_id} );
        for my $name ( sort keys %viewers ) {
            my $actor    = { viewer => $viewers{$name} };
            my $readable = $readers{$level}{$name} ? 1 : 0;
            my $page     = $searcher->ranked_search(
                $actor,
                'performance vacuum',
                { limit => $ROW_LIMIT }
            );
            is( scalar @{ $page->{results} },
                $ROW_LIMIT,
                "$level/$name: a page of other categories' matches" );
            ok(
                $readable || _outside_source( $page->{results} ),
                "$level/$name: none from a category the viewer may not read"
            );
            my $posts = $searcher->ranked_search(
                $actor,
                'performance vacuum',
                {
                    limit     => $ROW_LIMIT,
                    thread_id => $source->{thread_id},
                    scope     => 'posts'
                }
            )->{results};
            is(
                scalar @{$posts},
                $readable ? $ROW_LIMIT : 0,
                "$level/$name thread-scoped: "
                  . ( $readable ? 'a page of its posts' : 'nothing' )
            );
            ok(
                ( all { _in_source_thread($_) } @{$posts} ),
                "$level/$name thread-scoped: only the thread's posts"
            );
            ok(
                $readable || _outside_source(
                    $searcher->autocomplete(
                        $actor, 'performance', { limit => $ROW_LIMIT }
                    )
                ),
                "$level/$name autocomplete offers no thread it may not read"
            );
        }
    }
    $dbh->do(
        q{UPDATE categories SET visibility = 'public' WHERE category_id = ?},
        undef, $source->{category_id} );

    return;
}

sub _queries {
    my %found = (
        q{the}            => 0,    # a stop word matches nothing
        q{perfomance}     => 1,    # a misspelt title is still similar
        q{unfindableword} => 0,
        q{  }             => 1,    # a blank query lists the newest documents
        q{%}              => 0,    # LIKE wildcards are literal
        q{_}              => 0,
    );
    for my $query ( sort keys %found ) {
        my $page =
          $searcher->ranked_search( $global, $query, { limit => $ROW_LIMIT } );
        is(
            scalar @{ $page->{results} },
            $found{$query} ? $ROW_LIMIT : 0,
            "query [$query] finds " . ( $found{$query} ? 'a page' : 'nothing' )
        );
        is( $page->{ranking_capped},
            $found{$query},
            "query [$query] reports whether its candidates filled the cap" );
    }

    return;
}

sub _filters {
    my ($day) = $dbh->selectrow_array(
q{SELECT to_char(created_at, 'YYYY-MM-DD') FROM threads WHERE thread_id = ?},
        undef, $source->{thread_id}
    );
    my ($instant) = $dbh->selectrow_array(
        q{SELECT to_char(created_at, 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')}
          . q{ FROM threads WHERE thread_id = ?},
        undef, $source->{thread_id}
    );
    my $unfiltered = _found( {} );
    ok( @{$unfiltered}, 'performance finds documents' );
    my @filters = (
        [
            { scope => 'threads' },
            sub ($hit) { $hit->{entity_type} eq 'thread' }
        ],
        [ { scope => 'posts' }, sub ($hit) { $hit->{entity_type} eq 'post' } ],
        [
            { category_id => $source->{category_id} },
            sub ($hit) { $hit->{category_id} eq $source->{category_id} }
        ],
        [
            { author_user_id => $source->{author_user_id} },
            sub ($hit) {
                ( $hit->{author_user_id} // q{} ) eq $source->{author_user_id};
            }
        ],
        [
            { from => $day, to => $day },
            sub ($hit) { _created_at( $hit, 'YYYY-MM-DD' ) eq $day }
        ],
        [
            { from => $instant, to => $instant },
            sub ($hit) {
                _created_at( $hit, 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"' ) eq
                  $instant;
            }
        ],
    );
    for my $index ( 0 .. $#filters ) {
        my ( $filter, $holds ) = @{ $filters[$index] };
        my $hits = _found_rows($filter);
        ok( ( all { $holds->($_) } @{$hits} ),
            "filters/$index: every result satisfies the filter" );
        if ( !exists $filter->{from} ) {
            ok( scalar @{$hits}, "filters/$index: and some are found" );
        }
    }
    is_deeply( _found( { scope => 'everything' } ),
        $unfiltered, 'any other scope is no scope' );
    is_deeply(
        _found(
            {
                category_id    => 'invalid',
                author_user_id => 'invalid',
                from           => 'garbage',
                to             => '2026-02-30'
            }
        ),
        $unfiltered,
        'malformed filters are no filters'
    );

    return;
}

sub _autocomplete {
    my $suggested = $searcher->autocomplete( $global, 'Performance', {} );
    ok(
        ( grep { $_->{entity_id} eq $source->{thread_id} } @{$suggested} ),
        'autocomplete offers the source thread by its title'
    );
    ok( ( all { $_->{title} =~ /\A Performance/msx } @{$suggested} ),
        'and only titles that start with the prefix' );
    ok( ( all { $_->{entity_type} eq 'thread' } @{$suggested} ),
        'only threads are suggested' );
    is_deeply( $searcher->autocomplete( $global, q{}, {} ),
        $suggested, 'an empty prefix offers every thread title' );

    for my $prefix ( q{%}, q{_} ) {
        is_deeply( $searcher->autocomplete( $global, $prefix, {} ),
            [], "autocomplete prefix [$prefix] is literal" );
    }

    return;
}

# What a global reader finds for performance under a filter, and its ids.
sub _found_rows ($filter) {
    return $searcher->ranked_search( { viewer => $viewers{global} },
        'performance', { %{$filter}, limit => $ROW_LIMIT } )->{results};
}

sub _found ($filter) {
    return [ map { "$_->{entity_type}:$_->{entity_id}" }
          @{ _found_rows($filter) } ];
}

sub _outside_source ($hits) {
    return all { $_->{category_id} ne $source->{category_id} } @{$hits};
}

sub _in_source_thread ($hit) {
    return $hit->{entity_type} eq 'post'
      && $dbh->selectrow_array( 'SELECT thread_id FROM posts WHERE post_id = ?',
        undef, $hit->{entity_id} ) eq $source->{thread_id};
}

# A result's time as PostgreSQL renders it in the format given.
sub _created_at ( $hit, $format ) {
    return scalar $dbh->selectrow_array(
        'SELECT to_char(?::timestamptz, ?)', undef,
        $hit->{source_created_at},           $format
    );
}

1;
