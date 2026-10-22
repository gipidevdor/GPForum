# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Carp qw(croak);
use Const::Fast;
use English       qw(-no_match_vars);
use JSON::MaybeXS qw(decode_json);
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Test::PgDatabase;

our $VERSION = '0.001';

const my @OPERATIONS => qw(
  category_index_member category_threads_member latest_threads_member home_page_member
  session_validate viewer_resolve participation permission_check rate_limit
  notification_inbox notification_badge new_thread reply post_edit mark_read
  search_ranked search_autocomplete thread_page_anonymous thread_page_member thread_page_member_deep
);

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'set GPFORUM_TEST_DSN to run the SQL function benchmark';
}

# script/bench-sql-functions, the maintainers' measure of ADR 0126, runs a
# few iterations of every operation on both paths, at the database and
# through its proxy, and leaves no database behind: a smoke test that keeps
# the harness from rotting, not a measurement.
local $ENV{GPFORUM_DATABASE_DSN} = GPForum::Test::PgDatabase->admin_dsn;
open my $run, q{-|}, $EXECUTABLE_NAME, '-Ilib', 'script/bench-sql-functions',
  qw(--json --read-iterations 2 --write-iterations 2 --warmup 1)
  or croak "cannot run the benchmark: $OS_ERROR";
my $json = do { local $INPUT_RECORD_SEPARATOR = undef; <$run> };
ok( close($run), 'the benchmark runs' );
my $report = decode_json($json);

cmp_ok(
    $report->{round_trip_ms}{proxy},
    q{>},
    $report->{round_trip_ms}{direct},
    'the proxy adds a delay'
);
for my $operation (@OPERATIONS) {
    for my $path (qw(dbic function)) {
        my $row = $report->{operations}{$operation}{$path};
        for my $mode (qw(direct proxy)) {
            cmp_ok( $row->{$mode}{median_ms},
                q{>}, 0, "$operation, $path, $mode: timed" );
        }
        ok( exists $row->{profile}{dbic_ms}, "$operation, $path: profiled" );
    }
}
is( $report->{operations}{reply}{function}{direct}{round_trips},
    2,
    'a reply through its function is two round trips: the head and the call' );
is( $report->{operations}{post_edit}{function}{direct}{round_trips},
    2, 'editing reads the combined context and then calls the atomic write' );
cmp_ok(
    $report->{operations}{reply}{dbic}{direct}{round_trips},
    q{>},
    $report->{operations}{reply}{function}{direct}{round_trips},
    'more on the DBIx::Class path'
);

my $admin = DBI->connect(
    GPForum::Test::PgDatabase->admin_dsn,
    $ENV{GPFORUM_DATABASE_USER},
    $ENV{GPFORUM_DATABASE_PASSWORD},
    { AutoCommit => 1, PrintError => 0, RaiseError => 1 }
);
is(
    scalar $admin->selectrow_array(
        q{SELECT count(*) FROM pg_database} . q{ WHERE datname = ?}, undef,
        $report->{benchmark}{database_name}
    ),
    0,
    'and drops the database it made'
);
$admin->disconnect;

my ($invalid_ok) = _run(qw(--json --read-iterations 0));
ok( !$invalid_ok,
    'invalid iteration counts fail before a database is created' );
my $check = DBI->connect(
    GPForum::Test::PgDatabase->admin_dsn,
    $ENV{GPFORUM_DATABASE_USER},
    $ENV{GPFORUM_DATABASE_PASSWORD},
    { AutoCommit => 1, PrintError => 0, RaiseError => 1 }
);
my ( $failed_ok, $failed_output, $failed_pid ) =
  _execute( '-e', _broken_catalogue(), q{--},
    qw(--json --read-iterations 2 --write-iterations 2 --warmup 1) );
ok( !$failed_ok, 'a missing stored function fails the measurement' );
like(
    $failed_output,
    qr/benchmark_missing_routine/xms,
    'the function failure is reported rather than a timing result'
);
is(
    scalar $check->selectrow_array(
        'SELECT count(*) FROM pg_database WHERE datname = ?',
        undef,
        'gpforum_bench_sqlfn_' . $failed_pid
    ),
    0,
    'a failed measurement also drops only its own database'
);
my ( $interrupted_ok, $interrupted_output, $interrupted_pid ) =
  _execute( '-e', _interrupted_catalogue(), q{--},
    qw(--json --read-iterations 2 --write-iterations 2 --warmup 1) );
ok( !$interrupted_ok, 'SIGTERM during measurement fails the benchmark' );
like(
    $interrupted_output,
    qr/SQL[ ]function[ ]benchmark[ ]interrupted[ ]by[ ]TERM/xms,
    'the interruption is reported rather than a timing result'
);
is(
    scalar $check->selectrow_array(
        'SELECT count(*) FROM pg_database WHERE datname = ?',
        undef,
        'gpforum_bench_sqlfn_' . $interrupted_pid
    ),
    0,
    'SIGTERM during measurement drops the owned database'
);
$check->disconnect;

done_testing();

sub _broken_catalogue {
    return <<'PERL';
open STDERR, '>&', STDOUT or die $!;
require GPForum::Infrastructure::SqlFunctionCatalogue;
my $original = GPForum::Infrastructure::SqlFunctionCatalogue->can('function');
{
    no warnings 'redefine';
    *GPForum::Infrastructure::SqlFunctionCatalogue::function = sub {
        my $entry = $original->(@_);
        return $entry if $_[1] ne 'search_ranked';
        my %broken = %{$entry};
        $broken{sql} =~ s/api[.]search_ranked_v[[:digit:]]+/api.benchmark_missing_routine/;
        return \%broken;
    };
}
do './script/bench-sql-functions';
die $@ || $!;
PERL
}

sub _interrupted_catalogue {
    return <<'PERL';
open STDERR, '>&', STDOUT or die $!;
require GPForum::Infrastructure::SqlFunctionCatalogue;
my $original = GPForum::Infrastructure::SqlFunctionCatalogue->can('function');
{
    no warnings 'redefine';
    *GPForum::Infrastructure::SqlFunctionCatalogue::function = sub {
        my $entry = $original->(@_);
        kill 'TERM', $$ or die 'could not terminate benchmark'
            if $_[1] eq 'search_ranked';
        return $entry;
    };
}
do './script/bench-sql-functions';
die $@ || $!;
PERL
}

sub _run (@options) {
    return _execute( 'script/bench-sql-functions', @options );
}

sub _execute (@arguments) {
    my $pid = open my $process, q{-|}, $EXECUTABLE_NAME, '-Ilib', @arguments
      or croak "cannot run the benchmark: $OS_ERROR";
    my $output = do { local $INPUT_RECORD_SEPARATOR = undef; <$process> };
    my $ok     = close $process;
    return ( $ok, $output, $pid );
}

1;
