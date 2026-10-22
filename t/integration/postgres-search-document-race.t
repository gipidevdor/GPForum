# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Service::Search::Indexer;
use GPForum::Test::InterleavedClock;
use GPForum::Test::PostgresHarness;
use GPForum::X::Conflict;

our $VERSION = '0.001';

if ( !$ENV{GPFORUM_DATABASE_DSN} ) {
    plan skip_all =>
      'set GPFORUM_DATABASE_DSN to run the search document race test';
}

# A search document's id is derived from its entity, so a second insert of
# one entity collides on the primary key and the entity key alike. Either
# constraint may be reported; the indexer must preserve the winning document.
my $database =
  GPForum::Test::PostgresHarness::create_database( $ENV{GPFORUM_DATABASE_DSN} );
local $ENV{GPFORUM_DATABASE_DSN} = $database->{dsn};
my $prepared = GPForum::Test::PostgresHarness::prepare_database();
is( $prepared->{migrate}, 0, 'migrations apply' );
is( $prepared->{seed},    0, 'the seed loads' );

my $schema      = GPForum::Test::PostgresHarness::connect_schema();
my $rival       = GPForum::Test::PostgresHarness::connect_schema();
my $dbh         = $rival->storage->dbh;
my ($thread_id) = $dbh->selectrow_array(
        q{SELECT thread_id FROM threads WHERE deleted_at IS NULL}
      . q{ AND visibility = 'public' AND moderation_state = 'visible'}
      . q{ ORDER BY thread_id LIMIT 1} );

my $indexed = GPForum::Service::Search::Indexer->new( schema => $schema )
  ->index_thread($thread_id);
ok( $indexed->{search_document_id}, 'the thread is indexed' );

# The stored document, kept aside by the rival connection so that it can
# write it again: every column but the generated one.
my $columns = join q{, },
  @{
    $dbh->selectcol_arrayref(
            q{SELECT column_name FROM information_schema.columns}
          . q{ WHERE table_name = 'search_documents'}
          . q{ AND is_generated = 'NEVER' ORDER BY ordinal_position}
    )
  };
$dbh->do(
    'CREATE TEMPORARY TABLE held AS SELECT * FROM search_documents'
      . ' WHERE search_document_id = ?',
    undef, $indexed->{search_document_id}
);
my $insert_held =
  "INSERT INTO search_documents ($columns) SELECT $columns FROM held";

my ( $conflict, $insert_error );
try {
    $dbh->do($insert_held);
}
catch ($error) {
    $insert_error = $error;
    $conflict     = GPForum::X::Conflict->from_error( $error, $rival );
};
ok(
    $conflict && ( $conflict->on('search_documents_pkey')
        || $conflict->on('search_documents_entity_key') ),
    'PostgreSQL rejects the duplicate through a document uniqueness constraint'
) or diag( $insert_error // 'duplicate insertion raised no error' );
is(
    scalar $dbh->selectrow_array(
        'SELECT count(*) FROM search_documents WHERE entity_id = ?', undef,
        $thread_id
    ),
    1,
    'the rejected insert leaves exactly one document'
);

# The rival commits its document immediately before the indexer's function
# call, at the moment the indexer reads its clock.
$dbh->do( 'DELETE FROM search_documents WHERE search_document_id = ?',
    undef, $indexed->{search_document_id} );
my $clock = GPForum::Test::InterleavedClock->new(
    before_next_read => sub { $dbh->do($insert_held); } );
my ( $raced, $failure );
try {
    $raced = GPForum::Service::Search::Indexer->new(
        clock  => $clock,
        schema => $schema,
    )->index_thread($thread_id);
}
catch ($error) {
    $failure = $error;
};
is( $failure, undef, 'a race on the primary key is recovered' );
ok( $raced && $raced->{skipped}, 'by keeping the document the rival stored' );
is(
    scalar $dbh->selectrow_array(
        'SELECT count(*) FROM search_documents WHERE entity_id = ?', undef,
        $thread_id
    ),
    1,
    'and no second document is written'
);

# Independent sessions contend for the same document lock. One builds the
# projection and the other recognizes that exact projection without rewriting.
$dbh->do( 'DELETE FROM search_documents WHERE entity_id = ?',
    undef, $thread_id );
my @workers = GPForum::Test::PostgresHarness::race(
    sub ($slot) {
        return GPForum::Service::Search::Indexer->new(
            schema => GPForum::Test::PostgresHarness::connect_schema() )
          ->index_thread($thread_id);
    }
);
for my $slot ( 0 .. $#workers ) {
    ok(
        $workers[$slot]{ok} && $workers[$slot]{result},
        "simultaneous indexer $slot succeeds"
    );
}
is( scalar( grep { $_->{result}{skipped} } @workers ),
    1, 'exactly one simultaneous writer skips the winning projection' );
is(
    scalar $dbh->selectrow_array(
        'SELECT count(*) FROM search_documents WHERE entity_id = ?', undef,
        $thread_id
    ),
    1,
    'simultaneous indexers leave exactly one document'
);

$rival->storage->disconnect;
$schema->storage->disconnect;
GPForum::Test::PostgresHarness::drop_database($database);

done_testing();

1;
