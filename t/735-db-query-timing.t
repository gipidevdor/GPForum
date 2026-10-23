# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;
use Const::Fast;
use Test::More;
use Time::HiRes qw(usleep);

use lib 'lib';
use GPForum::Service::Operations::DbQueryStats;

our $VERSION = '0.001';
const my $QUERY_MICROSECONDS  => 20_000;
const my $RENDER_MICROSECONDS => 80_000;
const my $MINIMUM_QUERY_MS    => 35;
const my $RENDER_MARGIN_MS    => 50;

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
done_testing();

1;
