# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use Test::Mojo;
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Service::Search::Searcher;
use GPForum::Test::SearchPermissionEngine;
use GPForum::Test::SearchResultSet;
use GPForum::Test::SearchRow;
use GPForum::Test::SearchSchema;
use GPForum::Test::TransactionFunctions;

our $VERSION = '0.001';

const my $DEFAULT_CANDIDATES => 1_000;
const my $SMALL_CAP          => 2;
const my $PAGE               => 5;
const my $TIMEOUT_MS         => 1_500;
const my $CONFIGURED_TIMEOUT => 750;
const my $CONFIGURED_CAP     => 300;

# Search is bounded two ways (quality program 8.10). It ranks only the newest
# candidate_limit matches, so a word most documents hold is not scored over
# the whole corpus; and it runs under its own statement_timeout, so whatever
# still runs long is cancelled before it holds a web worker. The plans are
# pinned against PostgreSQL in t/integration/postgres-search-plan.t; this pins
# the evidence query's shape, and the call and the transaction the timeout
# lives in.

my ( $documents, $schema ) = _search_schema( _rows($SMALL_CAP) );
my $searcher = GPForum::Service::Search::Searcher->new(
    permission_engine => GPForum::Test::SearchPermissionEngine->new,
    schema            => $schema,
);

my $ranked = $searcher->search_resultset( undef, 'forum', { limit => $PAGE } );
my $candidates = $ranked->candidate_attrs;
is( $candidates->{rows}, $DEFAULT_CANDIDATES,
    'search ranks at most 1,000 candidates by default' );
is_deeply(
    $candidates->{order_by},
    [ { -desc => 'me.source_created_at' }, { -desc => 'me.entity_id' } ],
    'the candidates are the newest matches, in the new index order'
);
is_deeply( $candidates->{join}, [qw(category space)],
    'the candidates join only what the permission condition reads' );
like( ${ $documents->last_query->{-or}[0] }->[0],
    qr/websearch_to_tsquery/msx, 'the candidates are the matches' );
is_deeply(
    $documents->last_query->{-and}[0],
    { 'me.visibility' => { -in => ['public'] } },
    'and only those the actor may read, before the cap is applied'
);

my $outer = $documents->last_attrs;
is( $outer->{rows}, $PAGE, 'the ranked query returns one page' );
like( ${ $outer->{'+select'}[0] }->[0],
    qr/ts_rank_cd/msx, 'and ranks the candidates as search always has' );
is(
    ${ $outer->{'+select'}[-1] },
    'count(*) OVER ()',
    'every row says how many candidates were ranked'
);
is( $outer->{'+as'}[-1],
    'candidate_count', 'as candidate_count, which is how the cap is detected' );

$searcher->candidate_limit($SMALL_CAP);
is(
    $searcher->search_resultset( undef, 'forum', {} )->candidate_attrs->{rows},
    $SMALL_CAP,
    'the cap is configurable'
);

# The search itself is api.search_ranked's; the double answers what the
# function would, the candidate count on every row.
my $functions = _functions( _rows($SMALL_CAP) );
my $ranking   = GPForum::Service::Search::Searcher->new(
    candidate_limit   => $SMALL_CAP,
    functions         => $functions,
    permission_engine => GPForum::Test::SearchPermissionEngine->new,
    schema            => {},
);
my $capped = $ranking->ranked_search( undef, 'forum', { limit => $PAGE } );
is( $functions->asked('search_ranked')->[0]{candidate_limit},
    $SMALL_CAP, 'the function ranks at most the cap' );
is( $capped->{ranking_capped},
    1, 'filling every candidate slot marks the ranking capped' );
is( $capped->{candidate_limit},     $SMALL_CAP, 'and says at how many' );
is( scalar @{ $capped->{results} }, $SMALL_CAP, 'with the ranked results' );
ok( !exists $capped->{results}[0]{candidate_count},
    'the count is not a result field' );

$ranking->candidate_limit($DEFAULT_CANDIDATES);
is( $ranking->ranked_search( undef, 'forum', {} )->{ranking_capped},
    0, 'fewer candidates than the cap are not capped' );
is_deeply(
    $ranking->search( undef, 'forum', {} ),
    $ranking->ranked_search( undef, 'forum', {} )->{results},
    'search returns the same results without the note'
);

my $none = GPForum::Service::Search::Searcher->new(
    functions         => _functions( [] ),
    permission_engine => GPForum::Test::SearchPermissionEngine->new,
    schema            => {},
)->ranked_search( undef, 'forum', {} );
is( $none->{ranking_capped}, 0, 'no match is not a capped ranking' );

# Without a timeout configured nothing changes: no transaction, no setting.
is_deeply( $functions->transactions, [],
    'without a search timeout search runs outside a transaction' );
is_deeply( $functions->asked('search_set_timeout'),
    [], 'and leaves statement_timeout alone' );

# Zero is not "no timeout": set_config would switch search's off, not relax it.
$ranking->statement_timeout_ms(0);
$ranking->search( undef, 'forum', {} );
is_deeply( $functions->transactions, [],
    'a zero search timeout leaves search under the connection timeout' );

$ranking->statement_timeout_ms($TIMEOUT_MS);
$ranking->search( undef, 'forum', { limit => $PAGE } );
is_deeply(
    $functions->transactions,
    [ { readonly => 1, calls => [qw(search_set_timeout search_ranked)] } ],
    'a timed search runs in a read-only transaction of its own'
);
is_deeply(
    $functions->asked('search_set_timeout'),
    [ { timeout => "$TIMEOUT_MS" } ],
    'which sets its own statement_timeout, local to it, before the query'
);

$ranking->autocomplete( undef, 'wel', {} );
is_deeply(
    $functions->transactions->[-1],
    { readonly => 1, calls => [qw(search_set_timeout search_autocomplete)] },
    'autocomplete is timed the same way, with its own statement_timeout'
);

# The database cancelling the statement is an error like any other: it leaves
# the transaction and reaches the controller, which renders the page degraded.
$functions->answers->{search_ranked} =
  sub { die "canceling statement due to statement timeout\n"; };
my $opened = @{ $functions->transactions };
my ( $failed, $cancelled ) = ( 1, q{} );
try {
    $ranking->search( undef, 'forum', {} );
}
catch ($error) {
    ( $failed, $cancelled ) = ( 0, $error );
};
ok( !$failed, 'a cancelled search fails' );
is(
    scalar @{ $functions->transactions },
    $opened + 1,
    'inside its own transaction'
);
like(
    $cancelled,
    qr/statement [ ] timeout/msx,
    'with the database error, for the controller to degrade on'
);
is( $functions->depth, 0, 'and its transaction is closed' );

# The application's searcher takes both bounds from the configuration.
{
    local $ENV{GPFORUM_SEARCH_STATEMENT_TIMEOUT_MS} = $CONFIGURED_TIMEOUT;
    local $ENV{GPFORUM_SEARCH_CANDIDATE_LIMIT}      = $CONFIGURED_CAP;

    my $application = Test::Mojo->new('GPForum')->app;
    my $configured  = $application->build_controller->gp_search_service;
    is( $configured->statement_timeout_ms,
        $CONFIGURED_TIMEOUT,
        'the search service runs under GPFORUM_SEARCH_STATEMENT_TIMEOUT_MS' );
    is( $configured->candidate_limit,
        $CONFIGURED_CAP,
        'and ranks GPFORUM_SEARCH_CANDIDATE_LIMIT candidates' );
}

done_testing();

sub _rows {
    my ($count) = @_;

    return [
        map {
            GPForum::Test::SearchRow->new(
                data => {
                    body              => 'A forum post',
                    candidate_count   => $count,
                    entity_id         => "thread-$_",
                    entity_type       => 'thread',
                    source_created_at => '2026-05-23T12:00:00Z',
                    title             => "Welcome $_",
                    title_normalized  => "welcome $_",
                    visibility        => 'public',
                }
            )
        } 1 .. $count
    ];
}

sub _search_schema {
    my ($rows) = @_;

    my $resultset = GPForum::Test::SearchResultSet->new( rows => $rows );
    my $double    = GPForum::Test::SearchSchema->new(
        resultsets => { SearchDocument => $resultset } );

    return ( $resultset, $double );
}

# The call layer, answering the ranked search and the suggestions with the
# rows' columns.
sub _functions {
    my ($rows) = @_;

    my @answer = map { +{ %{ $_->data } } } @{$rows};

    return GPForum::Test::TransactionFunctions->new(
        answers => {
            search_ranked       => \@answer,
            search_autocomplete => \@answer,
        }
    );
}

1;
