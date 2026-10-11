# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;
use Const::Fast;
use Test::More;

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
my $clock          = GPForum::Test::FixedClock->new;
my $legacy_indexer = GPForum::Service::Search::Indexer->new(
    schema             => $schema,
    clock              => $clock,
    functions          => undef,
    rebuild_batch_size => $BATCH_SIZE,
);
my $indexer = GPForum::Service::Search::Indexer->new(
    schema             => $schema,
    clock              => $clock,
    rebuild_batch_size => $BATCH_SIZE,
);
$dbh->do('DELETE FROM search_documents');
my $legacy_rebuild   = $legacy_indexer->rebuild( { entity_type => 'all' } );
my $legacy_documents = _documents();
ok( @{$legacy_documents}, 'the comparison fixture has search documents' );
$dbh->do('DELETE FROM search_documents');
is_deeply( $indexer->rebuild( { entity_type => 'all' } ),
    $legacy_rebuild, 'function and ORM rebuilds count the same sources' );
is_deeply( _documents(), $legacy_documents,
    'the entire stored projection, including vector and derived IDs, agrees' );
my $unchanged = $indexer->rebuild( { entity_type => 'all' } );
is( $unchanged->{indexed}, 0,
    'repeating the rebuild writes no changed document' );
is(
    $unchanged->{unchanged},
    scalar @{$legacy_documents},
    'every unchanged document is recognized'
);

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
my $legacy_searcher = GPForum::Service::Search::Searcher->new(
    schema            => $schema,
    permission_engine => $permissions,
    candidate_limit   => $CANDIDATE_LIMIT,
    functions         => undef,
);

for my $level (qw(public members private)) {
    $dbh->do( 'UPDATE categories SET visibility = ? WHERE category_id = ?',
        undef, $level, $source->{category_id} );
    for my $name ( sort keys %viewers ) {
        my $actor = { viewer => $viewers{$name} };
        _compare_search(
            $actor,
            'performance vacuum',
            { limit => $ROW_LIMIT },
            "$level/$name"
        );
        is_deeply(
            $searcher->autocomplete(
                $actor, 'performance', { limit => $ROW_LIMIT }
            ),
            $legacy_searcher->autocomplete(
                $actor, 'performance', { limit => $ROW_LIMIT }
            ),
            "$level/$name autocomplete agrees"
        );
    }
}
$dbh->do( q{UPDATE categories SET visibility = 'public' WHERE category_id = ?},
    undef, $source->{category_id} );
for my $query ( q{the}, q{perfomance}, q{unfindableword}, q{  }, q{%}, q{_} ) {
    _compare_search(
        { viewer => $viewers{global} },
        $query,
        { limit => $ROW_LIMIT },
        "query [$query]"
    );
}
my ($day) = $dbh->selectrow_array(
q{SELECT to_char(created_at, 'YYYY-MM-DD') FROM threads WHERE thread_id = ?},
    undef, $source->{thread_id}
);
my ($instant) = $dbh->selectrow_array(
    q{SELECT to_char(created_at, 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')}
      . q{ FROM threads WHERE thread_id = ?},
    undef, $source->{thread_id}
);
my @filters = (
    { category_id    => $source->{category_id} },
    { author_user_id => $source->{author_user_id} },
    { from           => $day,     to => $day },
    { from           => $instant, to => $instant },
    {
        category_id    => 'invalid',
        author_user_id => 'invalid',
        from           => 'garbage',
        to             => '2026-02-30'
    },
);
for my $index ( 0 .. $#filters ) {
    _compare_search(
        { viewer                       => $viewers{global} }, 'performance',
        { %{ $filters[$index] }, limit => $ROW_LIMIT },       "filters/$index"
    );
}
for my $prefix ( q{}, q{%}, q{_}, q{Performance} ) {
    my $actor = { viewer => $viewers{global} };
    is_deeply(
        $searcher->autocomplete( $actor, $prefix, {} ),
        $legacy_searcher->autocomplete( $actor, $prefix, {} ),
        "autocomplete prefix [$prefix] agrees"
    );
}

done_testing();

sub _documents {
    return $dbh->selectall_arrayref(
        'SELECT * FROM search_documents ORDER BY entity_type, entity_id',
        { Slice => {} } );
}

sub _compare_search {
    my ( $actor, $query, $options, $name ) = @_;
    is_deeply(
        $searcher->ranked_search( $actor, $query, $options ),
        $legacy_searcher->ranked_search( $actor, $query, $options ),
        "$name exact ranking, bounds, snippets and cap metadata agree"
    );
    return;
}

1;
