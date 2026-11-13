# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;
use Const::Fast;
use English qw(-no_match_vars);
use Test::More;
use Time::HiRes qw(usleep);

use lib 'lib';
use lib 't/lib';
use GPForum::Infrastructure::CountedQuery;
use GPForum::Service::Operations::DbQueryStats;
use GPForum::Test::DbQueryStatsSchema;

our $VERSION = '0.001';
const my $QUERY_MICROSECONDS  => 20_000;
const my $RENDER_MICROSECONDS => 80_000;
const my $MINIMUM_QUERY_MS    => 35;
const my $RENDER_MARGIN_MS    => 50;
const my $CLOCK_JUMP_SECONDS  => 3_600;
const my $ELAPSED_SECONDS     => 0.125;
const my $ELAPSED_MS          => 125;

my $stats = GPForum::Service::Operations::DbQueryStats->new;
my $token = $stats->start_request( { route => 'timing' } );
$stats->query_start('SELECT api.example()');

# The outer API call can open a connection, whose own setup statements emit
# nested callbacks. Their time belongs to the outer interval only once.
$stats->query_start('SELECT connection_setup()');
usleep $QUERY_MICROSECONDS;
$stats->query_end;
usleep $QUERY_MICROSECONDS;
$stats->query_end;
usleep $RENDER_MICROSECONDS;
my $request = $stats->finish_request( $token, {} );
cmp_ok( $request->{db_duration_ms},
    '>=', $MINIMUM_QUERY_MS, 'both halves of the outer call were timed' );
cmp_ok(
    $request->{db_duration_ms},
    '<',
    $request->{duration_ms} - $RENDER_MARGIN_MS,
    'rendering time and nested callbacks do not inflate SQL time'
);
ok( !exists $request->{query_started_at} && !exists $request->{query_depth},
    'timing state does not leak in metrics' );

my $empty = $stats->start_request( { route => 'cached' } );
$stats->query_end;
my $cached = $stats->finish_request( $empty, {} );
is( $cached->{db_duration_ms},
    0, 'a cached request has zero SQL time and no previous request state' );

subtest 'failed counted reads balance their SQL observation' => sub {
    my $counted_stats = GPForum::Service::Operations::DbQueryStats->new;
    my $schema        = GPForum::Test::DbQueryStatsSchema->new;
    $counted_stats->attach_to_schema($schema);
    my $counted_token =
      $counted_stats->start_request( { route => 'counted-error' } );
    my $reached = eval {
        GPForum::Infrastructure::CountedQuery->select_row( $schema,
            'SELECT 1' );
        1;
    };
    ok( !$reached, 'the connection error still propagates' );
    like(
        $EVAL_ERROR,
        qr/test[ ]double[ ]has[ ]no[ ]database/msx,
        'the original database failure is retained'
    );
    my $failed = $counted_stats->finish_request( $counted_token, {} );
    cmp_ok( $failed->{db_duration_ms},
        '>', 0, 'the failed read ends its observation before propagating' );
};

subtest 'request duration follows a monotonic clock' => sub {
    my ( $wall, $monotonic ) = ( $CLOCK_JUMP_SECONDS, 0 );
    no warnings qw(redefine once);    ## no critic (TestingAndDebugging::ProhibitNoWarnings) -- replace only the two clocks, restored when this subtest returns
    local *GPForum::Service::Operations::DbQueryStats::time =
      sub { return $wall; };
    local *GPForum::Service::Operations::DbQueryStats::clock_gettime =
      sub { return $monotonic; };
    ## use critic
    my $elapsed_stats = GPForum::Service::Operations::DbQueryStats->new;
    for my $jump ( -$CLOCK_JUMP_SECONDS, $CLOCK_JUMP_SECONDS ) {
        my $elapsed_token =
          $elapsed_stats->start_request( { route => 'clock-adjustment' } );
        $wall      += $jump;
        $monotonic += $ELAPSED_SECONDS;
        my $elapsed_request =
          $elapsed_stats->finish_request( $elapsed_token, {} );
        is( $elapsed_request->{duration_ms},
            $ELAPSED_MS,
            'changing wall time does not change elapsed request time' );
        ok(
            !exists $elapsed_request->{started_monotonic},
            'the internal clock state is not exported'
        );
    }
};

done_testing();

1;
