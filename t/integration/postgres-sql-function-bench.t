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

const my $OPTIMIZED_SEARCH_VERSION => 4;
const my $BEFORE_POST_CALLS        => 3;

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

my ( $paired_ok, $paired_json ) = _run(
    qw(--paired-functions --json --read-iterations 2 --write-iterations 2 --warmup 1)
);
ok( $paired_ok, 'the paired stored-function benchmark runs' );
my $paired = decode_json($paired_json);
_paired_assertions($paired);
my ($invalid_ok) = _run(qw(--paired --json --read-iterations 0));
ok( !$invalid_ok, 'invalid pair counts fail before a database is created' );
my $check = DBI->connect(
    GPForum::Test::PgDatabase->admin_dsn,
    $ENV{GPFORUM_DATABASE_USER},
    $ENV{GPFORUM_DATABASE_PASSWORD},
    { AutoCommit => 1, PrintError => 0, RaiseError => 1 }
);
is(
    scalar $check->selectrow_array(
        'SELECT count(*) FROM pg_database WHERE datname = ?', undef,
        $paired->{benchmark}{database_name}
    ),
    0,
    'paired mode drops its disposable dataset'
);
my ( $failed_ok, $failed_output, $failed_pid ) = _execute(
    '-e',
    _broken_catalogue(),
    q{--},
    qw(--paired-functions --json --read-iterations 2 --write-iterations 2 --warmup 1)
);
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
$check->disconnect;

done_testing();

sub _broken_catalogue () {
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

sub _paired_assertions ($paired) {
    is_deeply(
        [ sort keys %{ $paired->{operations} } ],
        [qw(post_edit search_autocomplete search_ranked)],
        'paired mode measures only the three changed full service operations'
    );
    is( $paired->{comparison}{baseline_commit},
        '2cb9945', 'the retained baseline is identified' );
    is( $paired->{comparison}{implementation_reference},
        '27ec747', 'the optimization implementation reference is identified' );

    for my $operation (qw(search_ranked search_autocomplete)) {
        is( $paired->{comparison}{before}{$operation},
            2, "$operation baseline uses retained version2" );
        is( $paired->{comparison}{after}{$operation},
            $OPTIMIZED_SEARCH_VERSION, "$operation after uses version4" );
    }
    for my $operation (qw(post_edit search_ranked search_autocomplete)) {
        for my $mode (qw(direct proxy)) {
            for my $path (qw(before after)) {
                my $row = $paired->{operations}{$operation}{$path}{$mode};
                is( scalar @{ $row->{samples} },
                    2, "$operation $path $mode keeps both raw samples" );
                cmp_ok( $row->{median_ms}, q{>}, 0,
                    "$operation $path $mode is timed" );
                cmp_ok( $row->{cpu_ms}, q{>}, 0,
                    "$operation $path $mode measures CPU" );
                my $calls =
                  $operation eq 'post_edit'
                  ? ( $path eq 'before' ? $BEFORE_POST_CALLS : 2 )
                  : 1;
                is( $row->{statements}, $calls,
                    "$operation $path $mode sends the expected functions" );
                is( $row->{round_trips}, $calls,
                    "$operation $path $mode has the expected round trips" );
                is_deeply(
                    [ map { $_->{pair} } @{ $row->{samples} } ],
                    [ 1, 2 ],
                    'pair numbers align across paths'
                );
                is_deeply(
                    [ map { $_->{order} } @{ $row->{samples} } ],
                    $path eq 'before' ? [ 1, 2 ] : [ 2, 1 ],
                    'measurement order alternates within each pair'
                );
            }
        }
    }
    return;
}

sub _run (@options) {
    return _execute( 'script/bench-sql-functions', @options );
}

sub _execute (@arguments) {
    my $pid = open my $process, q{-|}, $EXECUTABLE_NAME, '-Ilib', @arguments
      or croak "cannot run the paired benchmark: $OS_ERROR";
    my $output = do { local $INPUT_RECORD_SEPARATOR = undef; <$process> };
    my $ok     = close $process;
    return ( $ok, $output, $pid );
}

1;
