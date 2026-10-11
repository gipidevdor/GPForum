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

const my $OPTIMIZED_SEARCH_VERSION       => 6;
const my $ISOLATED_BEFORE_SEARCH_VERSION => 4;
const my $BEFORE_POST_CALLS              => 3;
const my $COMBINED_POST_CALLS            => 2;
const my $IMPLEMENTATION_REFERENCE       => 'search-v6-custom-plans';
const my $OVERRIDE_REFERENCE             => 'smoke-implementation-reference';
const my %BASELINE_COMMIT => (
    2 => '2cb9945',
    4 => '200f902',
);

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
_paired_assertions( $paired, 2, $IMPLEMENTATION_REFERENCE );
my ( $isolated_ok, $isolated_json ) = _run(
    qw(--paired-functions --before-search-version 4 --json --read-iterations 2 --write-iterations 2 --warmup 1),
    '--implementation-reference', $OVERRIDE_REFERENCE
);
ok( $isolated_ok, 'the isolated version4-to-current search benchmark runs' );
my $isolated = decode_json($isolated_json);
_paired_assertions( $isolated, $ISOLATED_BEFORE_SEARCH_VERSION,
    $OVERRIDE_REFERENCE );
my ($invalid_ok) = _run(qw(--paired --json --read-iterations 0));
ok( !$invalid_ok, 'invalid pair counts fail before a database is created' );
{
    local $ENV{GPFORUM_DATABASE_DSN} = undef;
    my ( $unsupported_ok, $unsupported_output ) =
      _run( '--paired-functions', '--before-search-version',
        $OPTIMIZED_SEARCH_VERSION );
    ok( !$unsupported_ok, 'a baseline other than retained versions2/4 fails' );
    like( $unsupported_output, qr/^Usage:/xms,
        'baseline validation runs before any database connection is required' );
}
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
is(
    scalar $check->selectrow_array(
        'SELECT count(*) FROM pg_database WHERE datname = ?', undef,
        $isolated->{benchmark}{database_name}
    ),
    0,
    'isolated search comparison drops its disposable dataset'
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
my ( $interrupted_ok, $interrupted_output, $interrupted_pid ) = _execute(
    '-e',
    _interrupted_catalogue(),
    q{--},
    qw(--paired-functions --json --read-iterations 2 --write-iterations 2 --warmup 1)
);
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

sub _paired_assertions ( $paired, $before_version, $reference ) {
    is_deeply(
        [ sort keys %{ $paired->{operations} } ],
        [qw(post_edit search_autocomplete search_ranked)],
        'paired mode measures the three complete service operations'
    );
    is(
        $paired->{comparison}{baseline_commit},
        $BASELINE_COMMIT{$before_version},
        'the retained baseline is identified'
    );
    is( $paired->{comparison}{implementation_reference},
        $reference, 'the optimization implementation reference is identified' );
    is(
        $paired->{comparison}{before}{post_preflight},
        $before_version == 2
        ? 'forum_find_post_v2 + forum_thread_page_head_v2'
        : 'forum_post_context_v2',
        'the baseline keeps its published post context path'
    );
    is( $paired->{comparison}{after}{post_preflight},
        'forum_post_context_v2',
        'the current workflow uses the combined context' );

    for my $operation (qw(search_ranked search_autocomplete)) {
        is( $paired->{comparison}{before}{$operation},
            $before_version,
            "$operation baseline uses retained version$before_version" );
        is( $paired->{comparison}{after}{$operation},
            $OPTIMIZED_SEARCH_VERSION, "$operation after uses version6" );
    }
    my @revisions;
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
                  ? (
                      $path eq 'before' && $before_version == 2
                    ? $BEFORE_POST_CALLS
                    : $COMBINED_POST_CALLS
                  )
                  : 1;
                is( $row->{statements}, $calls,
                    "$operation $path $mode sends the expected functions" );
                is( $row->{round_trips}, $calls,
                    "$operation $path $mode has the expected round trips" );
                is_deeply(
                    [ map { $_->{round_trips} } @{ $row->{samples} } ],
                    [ $calls, $calls ],
                    "$operation $path $mode sends the same calls in every pair"
                );
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

                if ( $operation eq 'post_edit' ) {
                    push @revisions,
                      map { $_->{revision_id} } @{ $row->{samples} };
                }
            }
        }
    }
    ok(
        !grep( { !defined $_ || $_ eq q{} } @revisions ),
        'every sampled post edit returns a written revision'
    );
    my %unique = map { ( $_ // q{} ) => 1 } @revisions;
    is(
        scalar keys %unique,
        scalar @revisions,
        'every sampled post edit writes a distinct revision'
    );
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
