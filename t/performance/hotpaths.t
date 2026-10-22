# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;
use v5.40;
use English qw(-no_match_vars);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../../script/lib";
use JSON::PP;
use Test::More;
use GPForum::Performance::Hotpaths qw(collect execute);
use GPForum::Performance::Support  qw(read_json);
our $VERSION = '0.001';
use constant {    ## no critic (ValuesAndExpressions::ProhibitConstantPragma)
    PLAN_REPETITIONS => 3,
    PLAN_ROWS        => 6,
    SQL_MS           => 0.2,
    MAIN_MESSAGES    => 3_000,
    DELIVERED        => 1_000,
};

sub fixture_runner( $failures = [] ) {
    return sub( $command, $output, $name, $options ) {
        my $failed = grep { index( $name, $_ ) == 0 } @{$failures};
        my $code   = $failed ? 1 : 0;
        my $payload;
        if ( $name eq 'query-budget' ) {
            $payload = { status => $failed ? 'fail' : 'ok', missing => [] };
        }
        if ( index( $name, 'query-plan-' ) == 0
            && $name ne 'query-plan-static' )
        {
            $payload = {
                status    => $failed ? 'fail' : 'ok',
                endpoints => [
                    {
                        endpoint  => 'home',
                        status    => $failed ? 'fail' : 'ok',
                        sql_label => 'threads_public_activity',
                        summary   =>
                          { actual_time_ms => SQL_MS, actual_rows => 25 },
                        violations => [],
                        warnings   => [],
                        plan       => 'bulky raw plan'
                    }
                ]
            };
        }
        if ( $name eq 'outbox-postgres' ) {
            $payload = {
                status  => $failed ? 'fail' : 'ok',
                results => [
                    {
                        workers             => 1,
                        repetition          => 1,
                        status              => 'ok',
                        messages_per_second => 2000,
                        duration_seconds    => 0.5,
                        delivered           => DELIVERED,
                        lost                => 0,
                        duplicates          => 0,
                        acknowledged        => DELIVERED
                    }
                ]
            };
        }
        if ( $name eq 'sql-functions' ) {
            $payload = {
                operations => {
                    search => {
                        function => {
                            direct => {
                                median_ms   => 1,
                                p95_ms      => 2,
                                statements  => 1,
                                round_trips => 1
                            }
                        }
                    }
                }
            };
        }
        return {
            payload          => $payload,
            exit_code        => $code,
            duration_seconds => 0.1,
            timed_out        => JSON::PP::false,
            diagnostic       => 'diagnostics/' . $name . '.log'
        };
    };
}

sub status($directory) {
    return read_json(
        File::Spec->catfile( $directory, 'hotpaths-status.json' ) );
}

sub payload( $directory, $kind ) {
    return read_json( File::Spec->catfile( $directory, $kind . '.json' ) );
}

sub rejected( $code, $pattern, $description ) {
    my $error;
    try { $code->(); } catch ($caught) {
        $error = $caught;
    };
    like( "$error", $pattern, $description );
    return undef;
}

subtest 'missing database is an explicit skip' => sub {
    local %ENV = %ENV;
    delete $ENV{GPFORUM_DATABASE_DSN};
    my $directory = tempdir( CLEANUP => 1 );
    is( collect( $directory, 'pr', 0, fixture_runner() ),
        0, 'static gate succeeds' );
    is( status($directory)->{database}{status},
        'skipped', 'database is skipped' );
    ok( !-e File::Spec->catfile( $directory, 'database.json' ),
        'no database measurement invented' );
    ok( !-e File::Spec->catfile( $directory, 'outbox.json' ),
        'no outbox measurement invented' );
};
subtest
  'disposable database guard rejects live names and missing acknowledgement' =>
  sub {
    local $ENV{GPFORUM_DATABASE_DSN} = 'dbi:Pg:dbname=gpforum_perf_test';
    my $directory = tempdir( CLEANUP => 1 );
    rejected( sub { collect( $directory, 'pr', 0, fixture_runner() ); },
        qr/disposable-database/msx, 'acknowledgement required' );
    local $ENV{GPFORUM_DATABASE_DSN} = 'dbi:Pg:dbname=gpforum';
    rejected(
        sub { collect( $directory, 'pr', 1, fixture_runner() ); },
        qr/dedicated\s+gpforum_perf/msx,
        'application database refused'
    );
  };
subtest 'global deadline prevents remaining subprocesses' => sub {
    local $ENV{GPFORUM_DATABASE_DSN} = 'dbi:Pg:dbname=gpforum_perf_test';
    my $directory = tempdir( CLEANUP => 1 );
    my $calls     = 0;
    is( collect( $directory, 'deep', 1, sub { $calls++; return undef; }, 0 ),
        0, 'deadline produces explicit skips' );
    is( $calls, 0, 'no subprocess started after deadline' );
    my $states = status($directory);
    is( scalar( grep { $_->{status} ne 'skipped' } values %{$states} ),
        0, 'every suite is skipped' );
    is( $states->{'database-plans-functions'}{skipped_repetitions},
        PLAN_REPETITIONS, 'skipped repetitions are counted' );
    ok(
        !-e File::Spec->catfile( $directory, 'database.json' ),
        'no database file for skipped measurements'
    );
};
subtest 'success normalizes SQL timings and preserves configuration' => sub {
    local $ENV{GPFORUM_DATABASE_DSN} = 'dbi:Pg:dbname=gpforum_perf_test';
    my $directory = tempdir( CLEANUP => 1 );
    is( collect( $directory, 'main', 1, fixture_runner() ), 0,
        'main succeeds' );
    my $data = payload( $directory, 'database' );
    is( $data->{status}, 'ok', 'normalized database status' );
    my @plans = grep { index( $_->{scenario}, 'sql-plan' ) == 0 }
      @{ $data->{measurements} };
    is( scalar @plans,
        PLAN_ROWS, 'reader/functions each have three repetitions' );
    is( $plans[0]{metrics}{sql_execution_ms},
        SQL_MS, 'SQL time retains its own metric' );
    ok(
        !exists $plans[0]{evidence}{plan},
        'permanent output excludes bulky raw plans'
    );
    is( payload( $directory, 'outbox' )->{measurements}[0]{metrics}{lost},
        0, 'verified delivery loss retained' );
    my $config =
      payload( $directory, 'hotpaths-environment' )->{configuration}{hotpaths};
    is( $config->{outbox}{messages}, MAIN_MESSAGES, 'main message count' );
    is_deeply(
        $config->{outbox}{workers},
        [ 1, 2 ],
        'main worker configurations'
    );
};
subtest 'failure preserves partial evidence and completed outbox rows' => sub {
    local $ENV{GPFORUM_DATABASE_DSN} = 'dbi:Pg:dbname=gpforum_perf_test';
    my $directory = tempdir( CLEANUP => 1 );
    is(
        collect(
            $directory, 'pr', 1,
            fixture_runner( [ 'query-plan-functions', 'outbox-postgres' ] )
        ),
        1,
        'failed helper fails collection'
    );
    is( payload( $directory, 'database' )->{status},
        'partial', 'partial SQL evidence retained' );
    is( status($directory)->{'database-plans-functions'}{failure_kind},
        'infrastructure_or_harness', 'harness failure distinguished' );
    is( payload( $directory, 'outbox' )->{measurements}[0]{status},
        'ok', 'completed outbox repetition survives later failure' );
    is( status($directory)->{'outbox-postgres'}{status},
        'failed', 'partial completed row does not imply suite PASS' );
};
subtest 'unavailable deep profiler is skipped' => sub {
    local $ENV{GPFORUM_DATABASE_DSN} = 'dbi:Pg:dbname=gpforum_perf_test';
    my $directory = tempdir( CLEANUP => 1 );
    is(
        collect(
            $directory, 'deep',
            1,          fixture_runner( ['nytprof-availability'] )
        ),
        0,
        'other deep suites succeeded'
    );
    is( status($directory)->{profiling}{status},
        'skipped', 'unavailable profiler is not PASS' );
    ok(
        scalar(
            grep { $_->{scenario} eq 'sql-function-service-function-direct' }
              @{ payload( $directory, 'database' )->{measurements} }
        ),
        'SQL function service evidence exists'
    );
};
subtest 'raw JSON is parsed before colliding secret redaction' => sub {
    local $ENV{GPFORUM_DATABASE_PASSWORD} = 'postgres';
    my $directory = tempdir( CLEANUP => 1 );
    my $result    = execute(
        [
            $EXECUTABLE_NAME,
            '-e',
q{print qq[{"postgres":"18","status":"ok","error":"password=postgres postgresql://user:other-password\@localhost"}]}
        ],
        $directory,
        'redaction',
        { timeout => 2 }
    );
    is( $result->{payload}{postgres},
        '18', 'postgres metadata key survives parse' );
    unlike( $result->{payload}{error},
        qr/other-password/msx, 'URI password removed' );
    unlike( $result->{payload}{error},
        qr/password=postgres/msx, 'environment secret removed' );
};
subtest 'nonzero command exit retains structured partial stdout' => sub {
    my $directory = tempdir( CLEANUP => 1 );
    my $result    = execute(
        [
            $EXECUTABLE_NAME,
            '-e',
q{print qq[{"status":"fail","results":[{"status":"ok","delivered":1000}]}]; exit 1;}
        ],
        $directory,
        'partial',
        { timeout => 2 }
    );
    isnt( $result->{exit_code}, 0, 'actual CLI exit fails' );
    is( $result->{payload}{results}[0]{delivered},
        DELIVERED, 'completed measurement retained from failed command' );
};
subtest 'timeout keeps diagnostics without invented measurements' => sub {
    my $directory = tempdir( CLEANUP => 1 );
    my $result    = execute( [ $EXECUTABLE_NAME, '-e', 'sleep 5;' ],
        $directory, 'timeout', { timeout => 0.01 } );
    ok( $result->{timed_out},        'actual bounded subprocess times out' );
    ok( !defined $result->{payload}, 'no payload invented' );
    isnt( $result->{exit_code}, 0, 'timeout is unsuccessful' );
    ok( -f File::Spec->catfile( $directory, $result->{diagnostic} ),
        'diagnostic still saved' );
};
done_testing();
1;
