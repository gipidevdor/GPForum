# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;
use utf8;

use Carp qw(carp croak);
use Const::Fast;
use DBI;
use English qw(-no_match_vars);
use JSON::MaybeXS;
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Command::QueryPlanEvidence;
use GPForum::Infrastructure::Id;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Infrastructure::SqlFunctionCatalogue;
use GPForum::Schema;
use GPForum::Service::Forum::Viewer;
use GPForum::Service::Operations::ApiRole;
use GPForum::Service::Search::PermissionEngine;
use GPForum::Service::Search::Searcher;
use GPForum::Test::PgDatabase;
use GPForum::Infrastructure::SqlFunction::Retained;

our $VERSION = '0.001';

const my $OPTIMIZED_VERSION       => 6;
const my $IMPLEMENTATION_VERSION  => 5;
const my $RETAINED_VERSION        => 4;
const my $RETAINED_IMPLEMENTATION => 3;
const my $SCOPED_VERSION          => 7;
const my $SCOPE_ARGUMENTS         => 2;
const my $THREADS                 => 1_100;
const my $PLAN_THREADS            => 10_000;
const my $CANDIDATES              => 1_000;
const my $PAGE                    => 20;
const my $RARE_COUNT              => 4;
const my $BODY_COPIES             => 400;
const my $LITERAL_BACKSLASH       => chr 92;
const my $THREADS_SQL => join q{ },
  q{INSERT INTO threads (thread_id, category_id, author_user_id, title, slug,},
  q{created_at) SELECT gen_random_uuid(), ?, ?,},
  q{CASE WHEN n = 9 THEN 'D' || chr(233) || 'p Unicode'},
  q{WHEN n = 10 THEN 'Depth % literal' WHEN n = 11 THEN 'Depth _ literal'},
  q{WHEN n = 12 THEN 'Depth ' || chr(92) || ' path'},
q{ELSE 'Depth ' || CASE WHEN n <= 8 THEN 'tie' ELSE lpad(n::text, 5, '0') END END},
  q{|| CASE WHEN n % 700 = 1 THEN ' zymurgy' ELSE '' END,},
  q{'search-optimization-' || n,},
  q{timestamptz '2026-02-01 12:00:00+00' + (n / 8) * interval '1 minute'},
  q{FROM generate_series(1, ?::integer) n};
const my $POSTS_SQL => join q{ },
q{INSERT INTO posts (post_id, thread_id, author_user_id, position, created_at)},
  q{SELECT gen_random_uuid(), thread_id, author_user_id, 1, created_at},
  q{FROM threads WHERE slug LIKE 'search-optimization-%'};
const my $DOCUMENTS_SQL => join q{ },
  q{INSERT INTO search_documents (search_document_id, entity_type, entity_id,},
  q{category_id, author_user_id, space_id, visibility, permission_scope,},
  q{visibility_version, permission_version, source_version,},
  q{title, body, search_vector, source_created_at, indexed_at)},
  q{SELECT gen_random_uuid(), source.entity_type, source.entity_id,},
q{t.category_id, source.author_user_id, c.space_id, 'public', 'public', 1, 1, 1,},
  q{t.title, 'candidateword ' || repeat('wide body <mark> & plain text ', ?),},
  q{setweight(to_tsvector('simple', t.title), 'A') ||},
  q{setweight(to_tsvector('simple', 'candidateword'), 'B'),},
  q{t.created_at, timestamptz '2026-02-01 15:00:00+00'},
  q{FROM threads t JOIN categories c USING (category_id)},
q{CROSS JOIN LATERAL (SELECT 'thread' AS entity_type, t.thread_id AS entity_id,},
  q{t.author_user_id UNION ALL SELECT 'post', p.post_id, p.author_user_id},
  q{FROM posts p WHERE p.thread_id = t.thread_id) source},
  q{WHERE t.slug LIKE 'search-optimization-%'};

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'set GPFORUM_TEST_DSN to compare optimized search';
}

my $database = GPForum::Test::PgDatabase->fresh( seed => 1 );
my $schema   = $database->schema;
my $dbh      = $database->dbh;
$dbh->do(q{SET client_min_messages = 'warning'});
my $source = $dbh->selectrow_hashref(
        q{SELECT t.thread_id, t.author_user_id, c.category_id, c.space_id}
      . q{ FROM threads t JOIN categories c USING (category_id)}
      . q{ JOIN spaces s USING (space_id)}
      . q{ WHERE c.visibility = 'public' AND s.visibility = 'public'}
      . q{ AND c.deleted_at IS NULL ORDER BY t.thread_id LIMIT 1} );
_seed_corpus( $dbh, $THREADS );

my $json = JSON::MaybeXS->new( canonical => 1, utf8 => 0 );
my %functions =
  map { $_ => _functions($_) } ( 2, $RETAINED_VERSION, $OPTIMIZED_VERSION );
my $permissions = GPForum::Service::Search::PermissionEngine->new;
my %searcher    = map {
    $_ => GPForum::Service::Search::Searcher->new(
        schema            => $schema,
        permission_engine => $permissions,
        functions         => $functions{$_},
        candidate_limit   => $CANDIDATES,
    )
} ( 2, $RETAINED_VERSION, $OPTIMIZED_VERSION );
my %viewers = (
    anonymous => GPForum::Service::Forum::Viewer->anonymous,
    member    => GPForum::Service::Forum::Viewer->new(
        member  => 1,
        user_id => $source->{author_user_id},
    ),
    suspended => GPForum::Service::Forum::Viewer->new(
        user_id => $source->{author_user_id},
    ),
    category_grant => GPForum::Service::Forum::Viewer->new(
        category_ids => [ $source->{category_id} ],
    ),
    space_grant => GPForum::Service::Forum::Viewer->new(
        member    => 1,
        space_ids => [ $source->{space_id} ],
    ),
    global => GPForum::Service::Forum::Viewer->new(
        member      => 1,
        global_read => 1,
    ),
    global_without_member => GPForum::Service::Forum::Viewer->new(
        global_read => 1,
    ),
);
my $anonymous = { viewer => $viewers{anonymous} };
my $common = _compare( $anonymous, 'candidateword', {}, 'large common term' );
is( scalar @{ $common->{results} }, $PAGE, 'the common term fills the page' );
is( $common->{ranking_capped}, 1, 'the common term still reports the cap' );
my $rare = _compare( $anonymous, 'zymurgy', {}, 'rare full-text term' );
is( scalar @{ $rare->{results} }, $RARE_COUNT, 'every rare match survives' );
is( $rare->{ranking_capped},      0, 'the rare term ranks all its candidates' );

for my $query ( q{depth}, q{deph}, q{unfindableword}, q{  }, q{%}, q{_} ) {
    _compare( $anonymous, $query, {}, "query [$query]" );
}
for my $prefix ( q{}, q{D}, q{Dep}, q{Depth 00001}, q{unfindable}, q{%}, q{_},
    q{Dép}, q{Depth %}, q{Depth _}, q{Depth } . $LITERAL_BACKSLASH )
{
    _compare_autocomplete( $anonymous, $prefix, "prefix [$prefix]" );
}
my @filters = (
    { category_id    => $source->{category_id} },
    { author_user_id => $source->{author_user_id} },
    { from        => '2026-02-01',           to => '2026-02-01' },
    { from        => '2026-02-01T12:01:00Z', to => '2026-02-01T12:01:00Z' },
    { from        => '2026-02-02' },
    { category_id => 'invalid', from => 'garbage', to => '2026-02-30' },
);
for my $index ( 0 .. $#filters ) {
    _compare( $anonymous, 'candidateword', $filters[$index], "filter $index" );
}
_compare_visibility_levels();
_compare_mixed_visibility();
_compare_projection_windows();
_compare_without_permissions();
_assert_nested_plans();
_assert_runtime_role();

done_testing();

sub _seed_corpus ( $corpus_dbh, $thread_count ) {
    $corpus_dbh->do(
        $THREADS_SQL, undef,
        $source->{category_id},
        $source->{author_user_id},
        $thread_count,
    );
    $corpus_dbh->do($POSTS_SQL);
    $corpus_dbh->do( $DOCUMENTS_SQL, undef, $BODY_COPIES );
    $corpus_dbh->do('VACUUM ANALYZE search_documents');
    $corpus_dbh->do('ANALYZE');

    return;
}

sub _functions ( $version, $for_schema = $schema ) {
    my $catalogue = GPForum::Infrastructure::SqlFunctionCatalogue->new;
    my %entries   = %{ $catalogue->entries };
    for my $name (qw(search_ranked search_autocomplete)) {
        $entries{$name} = { %{ $entries{$name} }, version => $version };
    }

    # The scope (p_entity_type) came with v7, migration 110: the versions
    # before take the arguments of their day.
    if ( $version < $SCOPED_VERSION ) {
        my @parameters = @{ $entries{search_ranked}{parameters} };
        splice @parameters, -$SCOPE_ARGUMENTS;
        $entries{search_ranked}{parameters} = \@parameters;
    }

    my $class =
      $version < $SCOPED_VERSION
      ? 'GPForum::Infrastructure::SqlFunction::Retained'
      : 'GPForum::Infrastructure::SqlFunction';
    return $class->new(
        schema    => $for_schema,
        catalogue => GPForum::Infrastructure::SqlFunctionCatalogue->new(
            entries => \%entries,
        ),
    );
}

sub _compare ( $actor, $query, $options, $label ) {
    my $old = $searcher{2}->ranked_search( $actor, $query, $options );
    my $new =
      $searcher{$OPTIMIZED_VERSION}->ranked_search( $actor, $query, $options );
    my $retained =
      $searcher{$RETAINED_VERSION}->ranked_search( $actor, $query, $options );
    is_deeply( $new, $retained,
        "$label: retained API ranks, order, snippets and metadata" );
    is(
        $json->encode($new),
        $json->encode($retained),
        "$label: retained API serialized JSON"
    );
    is_deeply( $new, $old,
        "$label: exact ranks, order, snippets and metadata" );
    is( $json->encode($new), $json->encode($old), "$label: serialized JSON" );
    my ( $name, $values ) =
      @{ $searcher{$OPTIMIZED_VERSION}->ranked_call( $actor, $query, $options )
      };
    my $old_rows      = $functions{2}->rows( $name, $values );
    my $new_rows      = $functions{$OPTIMIZED_VERSION}->rows( $name, $values );
    my $retained_rows = $functions{$RETAINED_VERSION}->rows( $name, $values );
    is_deeply( $new_rows, $retained_rows,
        "$label: retained API raw typed columns and candidate counts" );
    my @columns        = keys %{ $new_rows->[0] // {} };
    my @old_projection = map { _projection( $_, \@columns ) } @{$old_rows};
    is_deeply( $new_rows, \@old_projection,
        "$label: raw typed columns and candidate counts" );

    return $new;
}

sub _projection ( $row, $columns ) {
    return { map { $_ => $row->{$_} } @{$columns} };
}

sub _compare_autocomplete ( $actor, $prefix, $label ) {
    my $old = $searcher{2}->autocomplete( $actor, $prefix, { limit => $PAGE } );
    my $new = $searcher{$OPTIMIZED_VERSION}
      ->autocomplete( $actor, $prefix, { limit => $PAGE } );
    my $retained = $searcher{$RETAINED_VERSION}
      ->autocomplete( $actor, $prefix, { limit => $PAGE } );
    is_deeply( $new, $retained, "$label: retained API autocomplete results" );
    is(
        $json->encode($new),
        $json->encode($retained),
        "$label: retained API autocomplete JSON"
    );
    is_deeply( $new, $old, "$label: exact autocomplete results" );
    is( $json->encode($new), $json->encode($old), "$label: autocomplete JSON" );

    return;
}

sub _compare_visibility_levels {
    for my $table (qw(search_documents categories spaces)) {
        for my $level (qw(public members private)) {
            my $column = $table eq 'spaces' ? 'space_id' : 'category_id';
            $dbh->do( "UPDATE $table SET visibility = ? WHERE $column = ?",
                undef, $level, $source->{$column}, );
            for my $name ( sort keys %viewers ) {
                my $actor = { viewer => $viewers{$name} };
                _compare( $actor, 'candidateword', {}, "$table/$level/$name" );
                _compare_autocomplete( $actor, 'Dep', "$table/$level/$name" );
            }
        }
        my $column = $table eq 'spaces' ? 'space_id' : 'category_id';
        $dbh->do( "UPDATE $table SET visibility = 'public' WHERE $column = ?",
            undef, $source->{$column} );
    }
    $dbh->do( 'UPDATE categories SET deleted_at = now() WHERE category_id = ?',
        undef, $source->{category_id} );
    my $deleted =
      _compare( $anonymous, 'candidateword', {}, 'deleted category' );
    is_deeply( $deleted->{results}, [], 'deleted categories remain hidden' );
    $dbh->do( 'UPDATE categories SET deleted_at = NULL WHERE category_id = ?',
        undef, $source->{category_id} );

    return;
}

sub _compare_mixed_visibility {
    $dbh->do(
q{UPDATE search_documents SET visibility = 'private' WHERE entity_id IN (}
          . q{ SELECT entity_id FROM search_documents}
          . q{ ORDER BY source_created_at DESC, entity_id DESC LIMIT ?)},
        undef, $THREADS,
    );
    my $older =
      _compare( $anonymous, 'candidateword', {}, 'denied newest candidates' );
    is( scalar @{ $older->{results} },
        $PAGE, 'older readable matches fill the page' );
    is( $older->{ranking_capped},
        1, 'readability is applied before the candidate cap' );
    _compare_autocomplete( $anonymous, 'Dep', 'mixed visibility autocomplete' );
    $dbh->do(q{UPDATE search_documents SET visibility = 'public'});

    return;
}

sub _compare_projection_windows {
    my $ids = GPForum::Infrastructure::Id->new;
    my ( $space, $category ) = ( $ids->uuid, $ids->uuid );
    $dbh->do(
        q{INSERT INTO spaces (space_id, title, slug, visibility)}
          . q{ VALUES (?, 'Moved search', 'moved-search', 'private')},
        undef, $space,
    );
    $dbh->do(
q{INSERT INTO categories (category_id, space_id, title, slug, visibility)}
          . q{ VALUES (?, ?, 'Moved search', 'moved-search', 'private')},
        undef, $category, $space,
    );
    my $global = { viewer => $viewers{global} };
    $dbh->do( 'UPDATE threads SET category_id = ? WHERE category_id = ?',
        undef, $category, $source->{category_id} );
    my $moved =
      _compare( $global, 'candidateword', {}, 'stale thread placement' );
    is_deeply( $moved->{results}, [],
        'even global readers hide stale placement' );
    _compare_autocomplete( $global, 'Dep', 'stale thread autocomplete' );
    $dbh->do( 'UPDATE search_documents SET category_id = ?, space_id = ?',
        undef, $category, $space );
    _compare( $global, 'candidateword', {}, 'reindexed thread placement' );
    _compare_autocomplete( $global, 'Dep', 'reindexed thread autocomplete' );
    $dbh->do( 'UPDATE threads SET category_id = ? WHERE category_id = ?',
        undef, $source->{category_id}, $category );
    $dbh->do(
        'UPDATE search_documents SET category_id = ?, space_id = ?',
        undef, $source->{category_id},
        $source->{space_id}
    );
    $dbh->do( 'UPDATE categories SET space_id = ? WHERE category_id = ?',
        undef, $space, $source->{category_id} );
    my $space_moved =
      _compare( $global, 'candidateword', {}, 'stale category placement' );
    is_deeply( $space_moved->{results},
        [], 'stale category space stays hidden' );
    _compare_autocomplete( $global, 'Dep', 'stale category autocomplete' );
    $dbh->do( 'UPDATE categories SET space_id = ? WHERE category_id = ?',
        undef, $source->{space_id}, $source->{category_id} );
    $dbh->do('UPDATE search_documents SET author_user_id = NULL');
    _compare( $anonymous, 'candidateword', {}, 'nullable projection author' );
    _compare_autocomplete( $anonymous, 'Dep', 'nullable author autocomplete' );
    $dbh->do( 'UPDATE search_documents SET author_user_id = ?',
        undef, $source->{author_user_id} );

    return;
}

sub _compare_without_permissions {
    my @pages = map {
        GPForum::Service::Search::Searcher->new(
            schema    => $schema,
            functions => $functions{$_},
        )->ranked_search( undef, 'candidateword', {} )
    } ( 2, $RETAINED_VERSION, $OPTIMIZED_VERSION );
    is_deeply( $pages[2], $pages[0], 'visibility-only fallback also agrees' );
    is_deeply( $pages[2], $pages[1],
        'visibility-only fallback agrees with the retained API' );

    return;
}

sub _assert_nested_plans {

    # The ACL and placement matrix deliberately changes whole tables. An
    # automatic ANALYZE can observe a temporary private/deleted state, and
    # restoring the values does not restore the statistics or remove dead
    # tuples. Measure the maintained common/rare workload independently,
    # with enough real documents to distinguish a capped index walk from
    # a scan and sort of the corpus, as the search plan gate does.
    my $plan_database = GPForum::Test::PgDatabase->fresh( seed => 1 );
    my $plan_dbh      = $plan_database->dbh;
    _seed_corpus( $plan_dbh, $PLAN_THREADS );
    my $plan_functions =
      _functions( $OPTIMIZED_VERSION, $plan_database->schema );
    my ( $name, $values ) =
      @{ $searcher{$OPTIMIZED_VERSION}
          ->ranked_call( $anonymous, 'candidateword', {} ) };
    my $statement = $plan_functions->statement( $name, $values );
    my $explained = GPForum::Command::QueryPlanEvidence::_explain_nested(    ## no critic (Subroutines::ProtectPrivateSubs) -- Exercise the same nested-plan collector as the production plan gate for this larger corpus.
        $plan_dbh, $statement, { analyze => 1 },
    );
    my ($body) =
      grep { ( $_->{'Query Text'} // q{} ) =~ /WITH [ ] ranked_page/msx }
      @{ $explained->{plan} };
    ok( $body, 'the actual optimized function body was measured' )
      or diag explain $explained;
    my @nodes = _nodes( $body->{Plan} );
    my ($candidate_scan) =
      grep { ( $_->{'Index Name'} // q{} ) eq 'idx_search_documents_created' }
      @nodes;
    ok( $candidate_scan, 'common search retains the newest-first index' )
      or diag explain $body;
    my $candidate_rows =
        $candidate_scan
      ? $candidate_scan->{'Actual Rows'} * $candidate_scan->{'Actual Loops'}
      : $PLAN_THREADS;
    cmp_ok( $candidate_rows, q{<=}, $CANDIDATES,
        'the common scan stops at the candidate boundary' )
      or diag explain $body;
    my ($ranking) = grep { $_->{'Node Type'} eq 'WindowAgg' } @nodes;
    is( $ranking->{'Actual Rows'},
        $CANDIDATES, 'ranking processes exactly the capped common candidates' );
    my ($page) =
      grep { ( $_->{'Subplan Name'} // q{} ) eq 'CTE ranked_page' } @nodes;
    is( $page->{'Actual Rows'},
        $PAGE, 'the narrow page is limited before payload joins' );
    my @payload = grep {
             ( $_->{'Alias'} // q{} ) eq 'document'
          && ( $_->{'Relation Name'} // q{} ) eq 'search_documents'
    } @nodes;
    is( scalar @payload, 1, 'the final page has one payload lookup' );
    my $payload_rows =
        @payload == 1
      ? $payload[0]{'Actual Rows'} * $payload[0]{'Actual Loops'}
      : $PAGE + 1;
    cmp_ok( $payload_rows,
        q{<=}, $PAGE, 'payload rows are loaded only after the result limit' );
    for my $version ( 2, $RETAINED_VERSION ) {
        my $previous_functions = _functions( $version, $plan_database->schema );
        my $previous = GPForum::Command::QueryPlanEvidence::_explain_nested(   ## no critic (Subroutines::ProtectPrivateSubs) -- Inspect each retained API on the same maintained corpus without planner overrides; PostgreSQL 16/17 SQL functions can retain generic plans.
            $plan_dbh, $previous_functions->statement( $name, $values ),
            { analyze => 1 },
        );
        my ($previous_body) = grep {
                 ( $_->{'Query Text'} // q{} ) =~ /WITH [ ] ranked_page/msx
              || ( $_->{'Query Text'} // q{} ) =~ /count[(][*][)][ ] OVER/msx
        } @{ $previous->{plan} };
        ok( $previous_body, "retained v$version function body was measured" )
          or diag explain $previous;
        my @previous_nodes = _nodes( $previous_body->{Plan} );
        my ($previous_ranking) =
          grep { $_->{'Node Type'} eq 'WindowAgg' } @previous_nodes;
        is( $previous_ranking->{'Actual Rows'},
            $CANDIDATES,
            "retained v$version ranks the same capped candidates" );
        is( $previous_body->{Plan}{'Actual Rows'},
            $PAGE, "retained v$version returns the same bounded result page" );
        my ($previous_scan) = grep {
                 ( $_->{'Alias'} // q{} ) eq 'me'
              && ( $_->{'Relation Name'} // q{} ) eq 'search_documents'
        } @previous_nodes;
        diag "retained v$version normal candidate scan: "
          . ( $previous_scan->{'Node Type'} // 'missing' )
          . ', index='
          . ( $previous_scan->{'Index Name'} // 'none' )
          . ', rows='
          . ( $previous_scan->{'Actual Rows'} // 'unknown' )
          . ', loops='
          . ( $previous_scan->{'Actual Loops'} // 'unknown' );
    }
    my ( $rare_name, $rare_values ) =
      @{ $searcher{$OPTIMIZED_VERSION}->ranked_call( $anonymous, 'zymurgy', {} )
      };
    my $rare_explained = GPForum::Command::QueryPlanEvidence::_explain_nested( ## no critic (Subroutines::ProtectPrivateSubs) -- Check selectivity-dependent planning through the application's actual function call.
        $plan_dbh,
        $plan_functions->statement( $rare_name, $rare_values ),
        { analyze => 1 },
    );
    my @rare_nodes = map { _nodes( $_->{Plan} ) } @{ $rare_explained->{plan} };
    ok(
        (
            scalar grep {
                ( $_->{'Index Name'} // q{} ) eq 'idx_search_documents_vector'
            } @rare_nodes
        ),
        'rare search keeps its GIN match path',
    );

    return;
}

sub _nodes ($node) {
    return () if !$node;

    return ( $node, map { _nodes($_) } @{ $node->{Plans} // [] } );
}

sub _assert_runtime_role {
    my $owner     = "gpf_search_owner_$PROCESS_ID";
    my $runtime   = "gpf_search_runtime_$PROCESS_ID";
    my $password  = GPForum::Infrastructure::Id->new->uuid;
    my $catalogue = GPForum::Infrastructure::SqlFunctionCatalogue->new;
    my $connection;
    my $runtime_schema;
    my $error;
    try {
        $dbh->do( 'CREATE ROLE '
              . $dbh->quote_identifier($owner)
              . ' NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS' );
        $dbh->do( 'CREATE ROLE '
              . $dbh->quote_identifier($runtime)
              . ' LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS'
              . ' PASSWORD '
              . $dbh->quote($password) );
        my $quoted_owner = $dbh->quote_identifier($owner);
        $dbh->do("GRANT USAGE ON SCHEMA api, public TO $quoted_owner");
        $dbh->do("GRANT ALL ON ALL TABLES IN SCHEMA public TO $quoted_owner");
        $dbh->do(
            "GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO $quoted_owner");
        $dbh->do(
"GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA api, public TO $quoted_owner"
        );
        for my $name ( @{ $catalogue->names } ) {
            my $entry = $catalogue->function($name);
            $dbh->do( 'ALTER FUNCTION '
                  . $entry->{function} . '('
                  . join( q{, }, @{ $entry->{types} } )
                  . ") OWNER TO $quoted_owner" );
        }
        my $quoted_runtime = $dbh->quote_identifier($runtime);
        for my $name (qw(search_ranked search_autocomplete)) {
            my $entry = $functions{2}->catalogue->function($name);
            $dbh->do( 'GRANT EXECUTE ON FUNCTION '
                  . $entry->{function} . '('
                  . join( q{, }, @{ $entry->{types} } )
                  . ") TO $quoted_runtime" );
        }
        GPForum::Service::Operations::ApiRole->new( dbh => $dbh )
          ->provision($runtime);
        $connection = DBI->connect( $database->dsn, $runtime, $password,
            { RaiseError => 1, PrintError => 0, AutoCommit => 1 } );
        $runtime_schema =
          GPForum::Schema->connect( $database->dsn, $runtime, $password,
            { RaiseError => 1, PrintError => 0, AutoCommit => 1 },
          );
        my $restricted = GPForum::Service::Search::Searcher->new(
            schema            => $runtime_schema,
            permission_engine => $permissions,
        );
        is_deeply(
            $restricted->ranked_search( $anonymous, 'candidateword', {} ),
            $searcher{$OPTIMIZED_VERSION}
              ->ranked_search( $anonymous, 'candidateword', {} ),
            'the restricted runtime login calls ranked v6 transitively',
        );
        is_deeply(
            $restricted->autocomplete( $anonymous, 'Dep', {} ),
            $searcher{$OPTIMIZED_VERSION}
              ->autocomplete( $anonymous, 'Dep', {} ),
            'the restricted runtime login calls autocomplete v6 transitively',
        );
        for my $version ( 1, 2, $RETAINED_IMPLEMENTATION, $RETAINED_VERSION,
            $IMPLEMENTATION_VERSION )
        {
            for my $name (qw(search_ranked search_autocomplete)) {
                my $entry    = $functions{2}->catalogue->function($name);
                my $function = "api.${name}_v$version";
                my $signature =
                  $function . '(' . join( q{, }, @{ $entry->{types} } ) . ')';
                ok(
                    !$dbh->selectrow_array(
                        'SELECT has_function_privilege(?, ?, \'EXECUTE\')',
                        undef, $runtime, $signature,
                    ),
                    "$function has no runtime execute grant after provisioning",
                );
                my $call =
                    $name eq 'search_ranked'
                  ? $searcher{2}->ranked_call( $anonymous, 'candidateword', {} )
                  : $searcher{2}->autocomplete_call( $anonymous, 'Dep', {} );
                my $statement = $functions{2}->statement( @{$call} );
                $statement->[0] =~ s/_v2[(]/_v$version(/msx;
                my ( $sql, @bind ) = @{$statement};
                my $rejected;
                try { $connection->selectall_arrayref( $sql, undef, @bind ); }
                catch ($caught) { $rejected = "$caught"; };
                like(
                    $rejected,
                    qr/permission [ ] denied [ ] for [ ] function/msx,
                    "$function direct runtime call is denied"
                );
            }
        }
    }
    catch ($caught) { $error = $caught; };
    if ($runtime_schema) { $runtime_schema->storage->disconnect; }
    if ($connection)     { $connection->disconnect; }
    for my $role ( $runtime, $owner ) {
        try {
            $dbh->do( 'DROP OWNED BY ' . $dbh->quote_identifier($role) );
            $dbh->do( 'DROP ROLE IF EXISTS ' . $dbh->quote_identifier($role) );
        }
        catch ($caught) { carp $caught; };
    }
    croak $error if defined $error;

    return;
}

1;
