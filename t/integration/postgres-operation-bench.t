# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;
use v5.40;
use Carp qw(croak);
use Const::Fast;
use English       qw(-no_match_vars);
use JSON::MaybeXS qw(decode_json);
use Test::More;
use lib 'lib', 't/lib';
use GPForum::Test::PgDatabase;

our $VERSION = '0.001';
const my $MINIMUM_PAGES => 25;
const my $ITERATIONS    => 2;
if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'set GPFORUM_TEST_DSN to exercise operation benchmarks';
}
local $ENV{GPFORUM_DATABASE_DSN} = GPForum::Test::PgDatabase->admin_dsn;
open my $run, q{-|}, $EXECUTABLE_NAME, '-Ilib', 'script/bench-render',
  '--json', '--iterations', $ITERATIONS, '--warmup', 1
  or croak "Cannot execute operation benchmark: $OS_ERROR";
my $output = do { local $INPUT_RECORD_SEPARATOR = undef; <$run> };
ok( close($run),
    'every fixed-seed read returns HTTP 200 through the real application' );
my $report = decode_json($output);
cmp_ok( scalar @{ $report->{pages} },
    '>=', $MINIMUM_PAGES, 'broad fixed-seed read workload' );
for my $row ( @{ $report->{pages} } ) {
    cmp_ok( $row->{request_median_ms},
        '>', 0, "$row->{page}: elapsed time measured" );
    cmp_ok( $row->{db_median_ms}, '>=', 0, "$row->{page}: SQL time observed" );
    cmp_ok(
        $row->{queries_max}, '>=',
        $row->{queries_median},
        "$row->{page}: query distribution retained"
    );
}
my %pages = map { $_->{page} => $_ } @{ $report->{pages} };
cmp_ok(
    $pages{category_archive}{bytes},
    '>',
    $pages{thread_archive}{bytes},
    'category export exercises more content than a thread export'
);
cmp_ok( $pages{settings}{queries_max},
    '>', 0, 'member settings exercise session and database reads' );
done_testing();
1;
