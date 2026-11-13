# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;
use utf8;
use Const::Fast;
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Service::Forum::Viewer;
use GPForum::Service::Search::DocumentBuilder;
use GPForum::Service::Search::Indexer;
use GPForum::Service::Search::PermissionEngine;
use GPForum::Service::Search::Searcher;
use GPForum::Test::FixedClock;
use GPForum::Test::PgDatabase;

our $VERSION = '0.001';

const my $CONFIG => GPForum::Service::Search::DocumentBuilder->search_config;
const my $TITLE =>
  'Perché la compilazione del modulo Mojolicious fallisce in città';
const my $OTHER_TITLE => 'Backup notturno del database completato';

# The baseline search configuration: what a reader types finds the forms of
# the same word, with or without accents, through the real indexing and
# search functions.

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'set GPFORUM_TEST_DSN to search in Italian';
}

my $database = GPForum::Test::PgDatabase->fresh( seed => 1 );
my $dbh      = $database->dbh;
$dbh->do(q{SET client_min_messages = 'warning'});
my $indexer = GPForum::Service::Search::Indexer->new(
    schema => $database->schema,
    clock  => GPForum::Test::FixedClock->new,
);
my $searcher = GPForum::Service::Search::Searcher->new(
    schema            => $database->schema,
    permission_engine => GPForum::Service::Search::PermissionEngine->new,
);
my $reader = { viewer => GPForum::Service::Forum::Viewer->anonymous };

my $threads = $dbh->selectcol_arrayref(
    q{SELECT t.thread_id FROM threads t JOIN categories c USING (category_id)}
      . q{ WHERE t.deleted_at IS NULL AND t.moderation_state = 'visible'}
      . q{ AND t.visibility = 'public' AND c.visibility = 'public'}
      . q{ ORDER BY t.thread_id LIMIT 2} );
is( scalar @{$threads}, 2, 'the seed has two public threads to retitle' );
my ( $thread, $other ) = @{$threads};
_retitle( $thread, $TITLE );
_retitle( $other,  $OTHER_TITLE );

my $stored = $dbh->selectrow_hashref(
    q{SELECT language, search_vector::text AS vector FROM search_documents}
      . q{ WHERE entity_type = 'thread' AND entity_id = ?},
    undef, $thread
);
is( $stored->{language}, $CONFIG,
    'the document records the configuration it was built with' );
like( $stored->{vector}, qr/'compil'/msx,
    'the vector holds the stem, not the word' );
like( $stored->{vector}, qr/'citt'/msx, 'and folds the accent' );
like( $stored->{vector}, qr/'mojolicious'/msx,
    'a word the stemmer does not know stays as written' );
unlike( $stored->{vector}, qr/'(?:la|del|in)'/msx,
    'the Italian stopwords are not indexed' );

for my $query (
    'compilato', 'Compilatore', 'compilazioni', 'citta',
    'città',     'perche',      'MODULI',       'mojolicious',
    '"compilazione del modulo"',
    'compilare -backup'
  )
{
    ok( _finds( $query, $thread ), "[$query] finds the thread" );
}
ok(
    !_finds( 'compilazione -fallisce', $thread ),
    'an excluded word leaves the thread out'
);
ok(
    _finds( 'compilazione or backup', $other ),
    'either word finds the other thread too'
);
ok( !_finds( 'backup', $thread ), 'a word it does not hold misses it' );

# The fuzzy title arms: a typo still finds a title, an operator is obeyed.
ok( _finds( 'compilazone fallise', $thread ),
    'a plain query with typos still finds the title by similarity' );
_retitle( $other, 'Errore di sintassi risolto' );
ok( _finds( 'errore di sintassi', $other ), 'the phrase finds the title' );
ok( !_finds( '"errore di sintassi" -risolto', $other ),
    'and a title similar to the query but holding the excluded word is out' );
_retitle( $other, $OTHER_TITLE );

# Rebuilding repairs documents stored under a different text-search
# configuration, without requiring a retired indexer entry point.
$dbh->do(
    q{UPDATE search_documents SET language = 'simple',}
      . q{ search_vector = to_tsvector('simple', title)}
      . q{ WHERE entity_type = 'thread' AND entity_id = ?},
    undef, $other
);
my ($simple) = $dbh->selectrow_array(
    q{SELECT count(*) FROM search_documents WHERE language = 'simple'});
is( $simple, 1, 'one document still has simple vectors' );
my $rebuild = $indexer->rebuild( { entity_type => 'thread' } );
cmp_ok( $rebuild->{indexed}, '>=', 1, 'the rebuild rewrites it' );
($simple) = $dbh->selectrow_array(
    q{SELECT count(*) FROM search_documents WHERE language <> ?},
    undef, $CONFIG );
is( $simple, 0, 'every document is in the Italian configuration again' );
ok( _finds( 'notturna', $other ), 'and found by another form of its words' );

done_testing;

sub _retitle ( $thread_id, $title ) {
    $dbh->do(
        q{UPDATE threads SET title = ?, version = version + 1}
          . q{ WHERE thread_id = ?},
        undef, $title, $thread_id
    );
    $indexer->index_thread($thread_id);
    return;
}

sub _finds ( $query, $thread_id ) {
    my $results = $searcher->search( $reader, $query, { scope => 'threads' } );
    return scalar grep { ( $_->{entity_id} // q{} ) eq $thread_id } @{$results};
}

1;
