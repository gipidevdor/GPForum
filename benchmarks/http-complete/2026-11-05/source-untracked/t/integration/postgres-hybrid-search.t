# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package main;
use v5.40;
use Test::More;
use Const::Fast;
use lib 'lib';
use lib 't/lib';
use GPForum::Infrastructure::SqlFunction;
use GPForum::Service::Search::Indexer;
use GPForum::Service::Search::Searcher;
use GPForum::Service::Search::Semantic;
use GPForum::Service::Search::PermissionEngine;
use GPForum::Service::Forum::Viewer;
use GPForum::Service::Operations::DbQueryStats;
use GPForum::Test::Embedding;
use GPForum::Test::PgDatabase;
our $VERSION = '0.001';
const my $HYBRID_READS => 3;

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'PostgreSQL is required';
}
my $database  = GPForum::Test::PgDatabase->fresh( seed => 1 );
my $schema    = $database->schema;
my $dbh       = $schema->storage->dbh;
my $embedding = GPForum::Test::Embedding->new;
my $semantic  = GPForum::Service::Search::Semantic->new(
    schema    => $schema,
    embedding => $embedding
);
my $indexer = GPForum::Service::Search::Indexer->new(
    schema   => $schema,
    semantic => $semantic
);
my $lexical_indexer =
  GPForum::Service::Search::Indexer->new( schema => $schema );
my $functions = GPForum::Infrastructure::SqlFunction->for_schema($schema);
my ( $energy, $animals ) = @{
    $dbh->selectcol_arrayref(
q{SELECT thread_id FROM threads WHERE deleted_at IS NULL AND visibility='public'}
          . q{ AND moderation_state='visible' ORDER BY thread_id LIMIT 2}
    )
};
_title( $energy,  'Risparmiare energia in casa' );
_title( $animals, 'Nozioni di zoologia' );
for my $id ( $energy, $animals ) { $indexer->index_thread($id); }
my $searcher = GPForum::Service::Search::Searcher->new(
    schema               => $schema,
    semantic             => $semantic,
    statement_timeout_ms => 1000,
    permission_engine    =>
      GPForum::Service::Search::PermissionEngine->new( schema => $schema )
);
my $anonymous = { viewer => GPForum::Service::Forum::Viewer->anonymous };

my $stats = GPForum::Service::Operations::DbQueryStats->new;
$stats->attach_to_schema($schema);
my $token = $stats->start_request( { endpoint_name => 'search' } );
my @inference_autocommit;
$embedding->before_embed(
    sub { push @inference_autocommit, $dbh->{AutoCommit} ? 1 : 0; } );
my $page = _page('bollettaelettrica');
$embedding->before_embed(undef);
my $observed = $stats->finish_request( $token, {} );
is_deeply( \@inference_autocommit, [1],
    'model inference holds no database transaction' );
is( $observed->{transactions},
    1, 'both retrieval branches share one transaction' );
is( $observed->{queries}, $HYBRID_READS,
    'one timeout setup and two bounded retrieval queries' );
is( $observed->{duplicate_queries},
    0, 'hybrid retrieval adds no duplicate statements' );
is( $page->{semantic_status}, 'ok', 'hybrid retrieval executes pgvector' );
is_deeply(
    [ map { $_->{entity_id} } @{ $page->{results} } ],
    [$energy],
'a semantic-only match is found without shared words, distant vectors excluded'
);
$dbh->do( q{UPDATE threads SET visibility='private' WHERE thread_id=?},
    undef, $energy );
is_deeply( _page('bollettaelettrica')->{results},
    [], 'live thread privacy applies before reindex' );
$dbh->do( q{UPDATE threads SET visibility='public' WHERE thread_id=?},
    undef, $energy );
my $both = _page('Risparmiare energia');
is( scalar( grep { $_->{entity_id} eq $energy } @{ $both->{results} } ),
    1, 'lexical and semantic matches are deduplicated' );
is( $both->{results}[0]{entity_id},
    $energy, 'agreement between rankings promotes the document' );
is( scalar @{ _page( 'bollettaelettrica', { limit => 1 } )->{results} },
    1, 'final limit is respected' );
is_deeply( _page( 'bollettaelettrica', { scope => 'posts' } )->{results},
    [], 'entity filter' );
is_deeply( _page( 'bollettaelettrica', { thread_id => $animals } )->{results},
    [], 'thread filter' );
is_deeply( _page( 'bollettaelettrica', { from => '2099-01-01' } )->{results},
    [], 'date filter' );
is_deeply(
    _page( 'bollettaelettrica', { tags => 'unassigned-tag' } )->{results},
    [], 'tag filter' );
is_deeply(
    _page( 'bollettaelettrica',
        { author_user_id => '00000000-0000-4000-8000-000000000001' } )
      ->{results},
    [],
    'author filter'
);
is_deeply(
    _page( 'bollettaelettrica',
        { category_id => '00000000-0000-4000-8000-000000000001' } )->{results},
    [],
    'category filter'
);

for my $query ( '"frase esatta"', 'energia -casa', 'energia OR casa' ) {
    my $calls = $embedding->calls;
    is( _page($query)->{semantic_status},
        'disabled', 'structured queries keep lexical semantics' );
    is( $embedding->calls, $calls,
        'structured query does not invoke inference' );
}

$embedding->fail(1);
my $fallback = _page('Risparmiare energia');
is( $fallback->{semantic_status},
    'degraded', 'embedding failure is observable' );
ok( grep( { $_->{entity_id} eq $energy } @{ $fallback->{results} } ),
    'lexical search survives inference failure' );
$embedding->fail(0);

$embedding->vector_override('not-a-vector');
my $sql_failure = _page('Risparmiare energia');
is( $sql_failure->{semantic_status},
    'degraded', 'semantic SQL failure rolls back its own transaction' );
ok(
    grep( { $_->{entity_id} eq $energy } @{ $sql_failure->{results} } ),
    'lexical results survive a database failure in the vector branch'
);
$embedding->vector_override(undef);
is( _page('bollettaelettrica')->{semantic_status},
    'ok', 'connection remains usable after semantic rollback' );

# A visible post with a vector disappears immediately when hidden or when
# its thread becomes private, before any indexing event has been delivered.
my ($post) = $dbh->selectrow_array(
q{SELECT post_id FROM posts WHERE thread_id=? AND moderation_state='visible' AND deleted_at IS NULL LIMIT 1},
    undef, $energy
);
$indexer->index_post($post);
ok(
    grep( { $_->{entity_id} eq $post }
        @{ _page('bollettaelettrica')->{results} } ),
    'semantic post result'
);
$dbh->do( q{UPDATE posts SET moderation_state='hidden' WHERE post_id=?},
    undef, $post );
ok(
    !grep( { $_->{entity_id} eq $post }
        @{ _page('bollettaelettrica')->{results} } ),
    'hidden post excluded before reindex'
);
$dbh->do( q{UPDATE posts SET moderation_state='visible' WHERE post_id=?},
    undef, $post );
$dbh->do( q{UPDATE threads SET visibility='private' WHERE thread_id=?},
    undef, $energy );
is_deeply( _page('bollettaelettrica')->{results},
    [], 'public post in a newly private thread is excluded' );
$dbh->do( q{UPDATE threads SET visibility='public' WHERE thread_id=?},
    undef, $energy );
$dbh->do( q{UPDATE posts SET visibility='private' WHERE post_id=?},
    undef, $post );
ok(
    !grep( { $_->{entity_id} eq $post }
        @{ _page('bollettaelettrica')->{results} } ),
    'new post privacy applies before reindex'
);
$dbh->do( q{UPDATE posts SET visibility='public' WHERE post_id=?},
    undef, $post );
$dbh->do(
    q{DELETE FROM search_documents WHERE entity_type='post' AND entity_id=?},
    undef, $post );

# Live moderation and access changes must apply before the outbox runs.
$dbh->do( q{UPDATE threads SET moderation_state='hidden' WHERE thread_id=?},
    undef, $energy );
is_deeply( _page('bollettaelettrica')->{results},
    [], 'hidden thread excluded before reindex' );
$dbh->do( q{UPDATE threads SET moderation_state='visible' WHERE thread_id=?},
    undef, $energy );
my ( $category, $space ) = $dbh->selectrow_array(
'SELECT t.category_id,c.space_id FROM threads t JOIN categories c USING(category_id) WHERE thread_id=?',
    undef, $energy
);
my ($private) = $dbh->selectrow_array(
    q{INSERT INTO categories(category_id,space_id,slug,title,visibility)}
      . q{ VALUES(gen_random_uuid(),?,'vector-private','Private','private') RETURNING category_id},
    undef, $space
);
$dbh->do( 'UPDATE threads SET category_id=? WHERE thread_id=?',
    undef, $private, $energy );
is_deeply( _page('bollettaelettrica')->{results},
    [], 'moved thread excluded before reindex' );
$indexer->index_thread($energy);
is_deeply( _page('bollettaelettrica')->{results},
    [], 'private category remains hidden after reindex' );
my ($user) = $dbh->selectrow_array('SELECT id FROM users LIMIT 1');
my $staff = {
    viewer => GPForum::Service::Forum::Viewer->new(
        member       => 1,
        user_id      => $user,
        category_ids => [$private]
    )
};
ok(
    grep( { $_->{entity_id} eq $energy }
        @{ $searcher->search( $staff, 'bollettaelettrica', {} ) } ),
    'an authorized category reader finds the semantic result'
);
$dbh->do( 'UPDATE threads SET category_id=? WHERE thread_id=?',
    undef, $category, $energy );
$indexer->index_thread($energy);

my $source = $functions->row(
    'search_embedding_source',
    {
        entity_type => 'thread',
        entity_id   => $energy,
        model_key   => 'new-model'
    }
);
my $vector = $embedding->embed('energy');
_title( $energy, 'Isolare le pareti domestiche' );
$lexical_indexer->index_thread($energy);
is( _count($energy), 0, 'lexical updates invalidate the previous embedding' );
ok(
    !$functions->row(
        'search_embedding_store',
        {
            document_id => $source->{document_id},
            fingerprint => $source->{fingerprint},
            model_key   => 'new-model',
            embedding   => $vector
        }
    )->{stored},
    'publication refuses a projection changed during inference'
);
$indexer->index_thread($energy);
is( _count($energy), 1,
    'unchanged lexical documents receive missing embeddings' );
my $calls = $embedding->calls;
$indexer->index_thread($energy);
is( $embedding->calls, $calls, 'unchanged vectors are not recalculated' );
$embedding->model_key('fixture-v2');
is_deeply( _page('bollettaelettrica')->{results},
    [], 'different model identities never mix' );
$indexer->index_thread($energy);
is( scalar @{ _page('bollettaelettrica')->{results} },
    1, 'model change can be backfilled' );

# Simulate a canonical edit committed while the model computes a vector.
$embedding->model_key('fixture-race');
$embedding->before_embed(
    sub {
        _title( $energy, 'Nuovo titolo dopo inferenza' );
        $lexical_indexer->index_thread($energy);
    }
);
$indexer->index_thread($energy);
is( _count($energy), 0, 'indexing cannot publish a stale in-flight embedding' );
$embedding->before_embed(undef);
$indexer->index_thread($energy);
is( _count($energy), 1, 'retry converges on the latest projection' );

_title( $energy, 'Documento lessicale salvato' );
$embedding->fail(1);
my $error;
try { $indexer->index_thread($energy); }
catch ($caught) { $error = "$caught"; };
like(
    $error,
    qr/embedding[ ]unavailable/msx,
    'worker inference failure propagates for retry'
);
is(
    scalar $dbh->selectrow_array(
'SELECT title FROM search_documents WHERE entity_type=\'thread\' AND entity_id=?',
        undef,
        $energy
    ),
    'Documento lessicale salvato',
    'lexical indexing commits before inference'
);
$embedding->fail(0);
$indexer->index_thread($energy);
$dbh->do(
    'DELETE FROM search_documents WHERE entity_type=\'thread\' AND entity_id=?',
    undef, $energy
);
is( _count($energy), 0, 'document removal cascades to the vector' );
done_testing();

sub _title ( $id, $title ) {
    $dbh->do( 'UPDATE threads SET title=? WHERE thread_id=?',
        undef, $title, $id );
    return;
}

sub _page ( $query, $options = undef ) {
    return $searcher->ranked_search( $anonymous, $query, $options || {} );
}

sub _count ($id) {
    return scalar $dbh->selectrow_array(
        q{SELECT count(*) FROM search_embeddings e}
          . q{ JOIN search_documents d USING(search_document_id) WHERE d.entity_id=?},
        undef, $id
    );
}
1;
