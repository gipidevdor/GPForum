# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause
package main;
use v5.40;
use Carp    qw(croak);
use English qw(-no_match_vars);
our $VERSION = '0.001';
use Test::More;
use File::Temp  qw(tempdir);
use Digest::SHA qw(sha256_hex);
use List::Util  qw(any);

# Representative fixture values are available before dependency installation.
use constant {    ## no critic (ValuesAndExpressions::ProhibitConstantPragma)
    STATUS_OK             => 200,
    STATUS_UNAVAILABLE    => 503,
    HTTP_ERRORS           => 3,
    CONNECTIONS           => 10,
    PR_CELLS              => 16,
    HIGH_WORKERS          => 8,
    SCALING_CPUS          => 4,
    HIGH_HOME_CONCURRENCY => 50,
    WORKER_ONE            => 101,
    WORKER_TWO            => 102,
    INVALID_DURATION      => 31,
    INVALID_REPEATS       => 6,
    INVALID_DEADLINE      => 1801,
    INVALID_CONNECTIONS   => 1000,
    EV_BACKEND            => 4,
    SEEDED_POSTS          => 4800,
    STRESS_CONNECTIONS    => 5000,
    STRESS_FD_LIMIT       => 16_384,
};
use JSON::PP;
use lib 'script/lib';
use GPForum::Performance::HTTP
  qw(parse_wrk parse_mojo plan main runtime_environment wrk_version probe_reactor native_backend_flags);
use GPForum::Performance::Server;
use GPForum::Performance::Support qw(read_json write_json run_bounded redact);

sub dies ( $callback, $pattern, $label ) {
    my $error;
    try { $callback->() } catch ($failure) {
        $error = $failure
    };
    like( "$error", $pattern, $label );
    return undef;
}

sub capture ($callback) {
    open my $silent, '>', \my $text or croak $ERRNO;
    local *STDOUT = $silent;
    $callback->();
    close $silent or croak $ERRNO;
    return $text;
}
my $metrics = {
    completed           => 100,
    http_errors         => 2,
    transport_errors    => 1,
    duration_seconds    => 2.001,
    requests_per_second => 49.975,
    p50_ms              => 1.01,
    p95_ms              => 3.02,
    p99_ms              => 8.03
};
my $raw = 'noise' . "\nGPFORUM_WRK " . encode_json($metrics) . "\n";
is_deeply( parse_wrk($raw), $metrics, 'wrk actual duration and percentiles' );
for my $bad ( q{}, "GPFORUM_WRK {}\n", $raw . $raw ) {
    dies( sub { parse_wrk($bad) },
        qr/wrk|metric/msx, 'incomplete or duplicated wrk rejected' );
}
dies(
    sub {
        parse_wrk(
            'GPFORUM_WRK ' . encode_json( { $metrics->%*, completed => 0 } ) );
    },
    qr/no\x20requests/msx,
    'zero completed rejected'
);
my $mojo = parse_mojo(
    encode_json(
        {
            completed     => 100,
            wall_seconds  => '1.000',
            req_per_sec   => '100.0',
            p50_ms        => '1',
            p95_ms        => '2',
            p99_ms        => '3',
            peak_inflight => 10,
            status_codes  => {
                STATUS_OK()          => 96,
                STATUS_UNAVAILABLE() => HTTP_ERRORS,
                error                => 1
            }
        }
    )
);
is_deeply(
    [ $mojo->@{qw(http_errors transport_errors concurrency_effective)} ],
    [ HTTP_ERRORS, 1, CONNECTIONS ],
    'Mojo HTTP transport actual peak separated'
);
is( scalar @{ plan( 'pr', undef, 2 ) }, PR_CELLS, 'PR16 targeted cells' );
ok( !( any { $_->{workers} == HIGH_WORKERS } @{ plan( 'deep', undef, 2 ) } ),
    'eight workers excluded below4CPU' );
ok(
    (
        any { $_->{workers} == HIGH_WORKERS }
          @{ plan( 'deep', undef, SCALING_CPUS ) }
    ),
    'eight workers targeted with4CPU'
);
ok(
    !(
        any {
                 $_->{scenario} eq 'home'
              && $_->{concurrency} > HIGH_HOME_CONCURRENCY
        } @{ plan( 'deep', undef, SCALING_CPUS ) }
    ),
    'expensive home omitted at highload'
);
{
    my $dir    = tempdir( CLEANUP => 1 );
    my $server = bless {
        directory => $dir,
        master    => 100,
        workers   => 2,
        reactor   => 'Mojo::Reactor::EV'
      },
      'GPForum::Performance::Server';
    local *GPForum::Performance::Server::process_snapshot = sub {
        return {
            workers_actual => 2,
            worker_pids    => [ WORKER_ONE, WORKER_TWO ]
        };
    };
    write_json(
        "$dir/worker-101.json",
        {
            pid        => 101,
            reactor    => $server->{reactor},
            ev_backend => native_backend_flags()
        }
    );
    dies(
        sub { $server->telemetry },
        qr/some\x20serving\x20workers/msx,
        'every serving PID required'
    );
    write_json(
        "$dir/worker-102.json",
        {
            pid        => 102,
            reactor    => $server->{reactor},
            ev_backend => native_backend_flags()
        }
    );
    is( scalar @{ $server->telemetry }, 2, 'all worker telemetry verified' );
    write_json( "$dir/worker-102.json",
        { pid => 102, reactor => 'Mojo::Reactor::Poll', ev_backend => undef } );
    dies(
        sub { $server->telemetry },
        qr/did\x20not\x20match/msx,
        'worker reactor mismatch rejected'
    );
    write_json( "$dir/worker-102.json",
        { pid => 102, reactor => $server->{reactor}, ev_backend => 1 } );
    dies(
        sub { $server->telemetry },
        qr/required [ ] native [ ] backend/msx,
        'an EV worker with select instead of the native backend is rejected'
    );
    dies(
        sub { GPForum::Performance::Server->new( { reactor => 'Poll' } ) },
        qr/Native [ ] EV [ ] reactor [ ] required/msx,
        'the harness cannot launch a Poll server'
    );
}
{
    my $seen;
    local *GPForum::Performance::HTTP::run_bounded =
      sub ( $command, $options ) {
        $seen = $options->{env};
        return 'Mojo::Reactor::EV:' . native_backend_flags();
      };
    ok( probe_reactor( 'EV', '/unused', 1 ), 'native reactor probe succeeds' );
    is( $seen->{LIBEV_FLAGS}, native_backend_flags(),
        'the probe pins epoll or kqueue before EV loads' );
    local *GPForum::Performance::HTTP::run_bounded = sub {
        return 'Mojo::Reactor::EV:1';
    };
    ok( !probe_reactor( 'EV', '/unused', 1 ), 'an EV select probe fails' );
    dies(
        sub { probe_reactor( 'Poll', '/unused', 1 ) },
        qr/Native [ ] EV [ ] reactor [ ] required/msx,
        'Poll cannot be a fallback probe'
    );
}
{
    my $dir = tempdir( CLEANUP => 1 );
    capture(
        sub {
            is( main( '--output', $dir, '--dry-run' ), 0, 'dry-run exits0' );
            is( read_json("$dir/suite-status.json")->{http}{status},
                'skipped', 'dry-run explicitly skipped' );
            ok( !-f "$dir/http.json", 'no fabricated dryrun HTTPdata' );
            local $ENV{GPFORUM_DATABASE_DSN} = 'dbi:Pg:dbname=gpforum';
            is( main( '--output', $dir, '--disposable-database' ),
                2, 'application database refused' );

            for my $pair (
                [ '--duration',    0 ],
                [ '--duration',    INVALID_DURATION ],
                [ '--repetitions', INVALID_REPEATS ],
                [ '--deadline',    INVALID_DEADLINE ],
                [ '--concurrency', INVALID_CONNECTIONS ],
              )
            {
                dies( sub { main( '--output', $dir, $pair->@* ) },
                    qr/required|concurrency/msx, 'numeric override bounded' );
            }
        }
    );
}
{
    my $dir = tempdir( CLEANUP => 1 );
    local *GPForum::Performance::HTTP::nofile_soft =
      sub { return STRESS_FD_LIMIT; };
    my @options = (
        '--output',      $dir,
        '--mode',        'pr',
        '--generator',   'wrk',
        '--concurrency', STRESS_CONNECTIONS,
        '--allow-5000',  '--scenario',
        'health_live',   '--dry-run',
    );
    my $plan = decode_json( capture( sub { main(@options); } ) )->{plan};
    is_deeply(
        [ map { [ $_->@{qw(scenario concurrency workers)} ] } $plan->@* ],
        [ [ 'health_live', STRESS_CONNECTIONS, 2 ] ],
        'the CI stress plan executes 5000 connections on the selected endpoint'
    );
    local *GPForum::Performance::HTTP::nofile_soft =
      sub { return CONNECTIONS; };
    dies(
        sub { main(@options); },
        qr/file[ ]descriptors/msx,
        'an incapable runner fails explicitly instead of silently skipping 5000'
    );
    dies(
        sub { main( @options, '--generator', 'mojo' ); },
        qr/wrk[ ]generator/msx,
        '5000 requires the independent generator'
    );
    dies(
        sub { main( @options, '--scenario', 'unknown' ); },
        qr/unknown[ ]HTTP[ ]scenario/msx,
        'an unknown endpoint cannot produce an empty successful test'
    );
}
{
    local $ENV{GPFORUM_DATABASE_PASSWORD} = 'canary-secret';
    local $ENV{PGPASSWORD}                = 'postgres';
    my $safe = redact(
        'password=canary-secret; postgresql://user:otherpassword@localhost');
    unlike(
        $safe,
        qr/canary-secret|otherpassword/msx,
        'structural secret redaction before fixture substrings'
    );
    my $dir = tempdir( CLEANUP => 1 );
    my $raw_json =
      run_bounded( [ $EXECUTABLE_NAME, '-e', 'print q({"postgres":"16.4"})' ],
        { timeout => 2, log => "$dir/log" } );
    is( decode_json($raw_json)->{postgres},
        '16.4', 'parse structuredstdout before redact' );
    dies(
        sub {
            run_bounded( [ $EXECUTABLE_NAME, '-e', 'sleep 5' ],
                { timeout => .05 } );
        },
        qr/deadline/imsx,
        'command deadline enforced'
    );
    is(
        run_bounded(
            [ $EXECUTABLE_NAME, '-e', 'print "version";exit 1' ],
            { timeout => 2, accepted_codes => [ 0, 1 ] }
        ),
        'version',
        'version probe explicitly accepts1'
    );
    dies(
        sub {
            run_bounded( [ $EXECUTABLE_NAME, '-e', 'exit 1' ],
                { timeout => 2 } );
        },
        qr/exit\x201/msx,
        'normalcommands rejectexit1'
    );
}
{
    local *GPForum::Performance::HTTP::run_bounded =
      sub { return "wrk 4.2.0 [kqueue]\nUsage: wrk" };
    is( wrk_version(), 'wrk 4.2.0 [kqueue]', 'numeric wrk banner' );
}
{
    my @outputs = ( 'wrk  Copyright (C) 2012 Will Glozer', '4.1.0-5build2' );
    local *GPForum::Performance::HTTP::run_bounded =
      sub { return shift @outputs };
    local *GPForum::Performance::HTTP::which =
      sub { return '/usr/bin/dpkg-query' };
    is(
        wrk_version(),
        'wrk (distribution package 4.1.0-5build2; CLI upstream unspecified)',
        'Ubuntu actual distributionversion'
    );
}
{
    local *GPForum::Performance::HTTP::run_bounded =
      sub { return 'wrk unspecified Copyright (C) 2012 Will Glozer' };
    local *GPForum::Performance::HTTP::which = sub { return undef };
    like(
        wrk_version(),
        qr/distribution\x20package\x20unavailable/msx,
        'unknown version explicit'
    );
    local *GPForum::Performance::HTTP::run_bounded =
      sub { return 'other-tool 4.2.0' };
    dies(
        sub { wrk_version() },
        qr/did\x20not\x20identify/msx,
        'unrecognized binary rejected'
    );
}
{
    local $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
    local $ENV{LIBEV_FLAGS}  = 2;
    my $seen;
    local *GPForum::Performance::HTTP::run_bounded = sub ( $argv, $options ) {
        $seen = $options->{env};
        ok(
            index( $argv->[-1], 'use v5.40;' ) >= 0,
            'isolated runtime probe enables native try/catch'
        );
        return encode_json(
            {
                perl               => 'v5.40',
                mojolicious        => '9.49',
                ev                 => '4.33',
                default_reactor    => 'Mojo::Reactor::EV',
                default_ev_backend => 4
            }
        );
    };
    my $env = runtime_environment(
        { postgres  => '16.4', database_settings => {} },
        { signature => 'seed' },
        { mode      => 'pr', duration => 2, repetitions => 3 }
    );
    ok( !exists $seen->{MOJO_REACTOR} && !exists $seen->{LIBEV_FLAGS},
        'defaultprobe removes forced settings' );
    is( $ENV{MOJO_REACTOR}, 'Mojo::Reactor::Poll',
        'parent settings preserved' );
    is( $env->{configuration}{default_ev_backend},
        EV_BACKEND, 'defaultbackend transported' );
    is( $env->{configuration}{default_reactor},
        'Mojo::Reactor::EV', 'defaultclass transported' );
    ok(
        !exists $env->{versions}{default_reactor},
        'selection separatefromversions'
    );
}
{
    my $dir = tempdir( CLEANUP => 1 );
    local $ENV{GPFORUM_DATABASE_DSN} = 'dbi:Pg:dbname=gpforum_perf_test';
    write_json( "$dir/suite-status.json", { database => { status => 'ok' } } );
    local *GPForum::Performance::HTTP::which = sub { return undef };
    local *GPForum::Performance::HTTP::prepare_dataset =
      sub { croak 'database unavailable' };
    is(
        main(
            '--output', $dir, '--disposable-database', '--generator', 'mojo'
        ),
        1,
        'failed seed isfailure'
    );
    my $statuses = read_json("$dir/suite-status.json");
    is( $statuses->{database}{status}, 'ok',     'other suites retained' );
    is( $statuses->{http}{status},     'failed', 'HTTPnotpassed' );
    ok( !-f "$dir/http.json", 'no fakefailedmetrics' );
}
{
    my $dir = tempdir( CLEANUP => 1 );
    local $ENV{GPFORUM_DATABASE_DSN} = 'dbi:Pg:dbname=gpforum_perf_test';
    local *GPForum::Performance::HTTP::which = sub { return '/fake/wrk' };
    local *GPForum::Performance::HTTP::prepare_dataset = sub {
        return (
            { counts   => { posts => 4800 }, signature         => 'known' },
            { postgres => '16.4',            database_settings => {} }
        );
    };
    local *GPForum::Performance::HTTP::run_bounded =
      sub { return encode_json( { perl => 'v5.40', mojolicious => '9.49' } ) };
    local *GPForum::Performance::HTTP::wrk_version =
      sub { croak 'unidentifiable wrk' };
    is(
        main( '--output', $dir, '--disposable-database', '--generator', 'wrk' ),
        1,
        'bad primaryversionfailed'
    );
    is( read_json("$dir/http-environment.json")->{dataset}{counts}{posts},
        SEEDED_POSTS, 'completed seed provenance survives optionalprobe' );
}

sub test_partial_cells {
    my $dir = tempdir( CLEANUP => 1 );
    local $ENV{GPFORUM_DATABASE_DSN} = 'dbi:Pg:dbname=gpforum_perf_test';
    local *GPForum::Performance::HTTP::which = sub { return '/fake/wrk'; };
    local *GPForum::Performance::HTTP::prepare_dataset = sub {
        return ( { counts => { posts => SEEDED_POSTS }, signature => 'known' },
            { postgres => '16.4', database_settings => {} } );
    };
    local *GPForum::Performance::HTTP::probe_reactor = sub { return 1; };
    local *GPForum::Performance::HTTP::run_bounded =
      sub { return encode_json( { perl => 'v5.40', mojolicious => '9.49' } ); };
    local *GPForum::Performance::HTTP::wrk_version =
      sub { croak 'unused optional wrk is unreadable'; };
    local *GPForum::Performance::HTTP::plan = sub {
        return [
            map {
                {
                    scenario    => $_,
                    endpoint    => "/$_",
                    workers     => 2,
                    concurrency => 1,
                    cache_mode  => 'normal'
                }
            } qw(home categories)
        ];
    };
    local *GPForum::Performance::Server::new = sub ( $class, $options ) {
        return bless {
            reactor => 'Mojo::Reactor::EV',
            workers => $options->{workers}
        }, $class;
    };

    # The existing server cleanup API must be stubbed by its exact public name.
    local *GPForum::Performance::Server::close = sub { return undef; };    ## no critic (NamingConventions::ProhibitAmbiguousNames)
    my $calls = 0;
    local *GPForum::Performance::HTTP::mojo_measure = sub {
        ++$calls;
        if ( $calls == 1 ) { croak 'single endpoint fixture failed'; }
        return ( { $metrics->%*, http_errors => 0, transport_errors => 0 },
            {} );
    };
    capture(
        sub {
            is(
                main(
                    '--output', $dir, '--disposable-database', '--generator',
                    'mojo',     '--repetitions', '1'
                ),
                1,
                'one failed cell remains visible'
            );
        }
    );
    my $payload = read_json("$dir/http.json");
    is( $payload->{status}, 'partial', 'valid cells survive one failure' );
    is( scalar $payload->{measurements}->@*,
        1, 'only real successful cell saved' );
    is( $payload->{measurements}[0]{scenario},
        'categories', 'later scenario still ran' );
    my $suite = read_json("$dir/suite-status.json")->{http};
    ok(
        ( any { $_->{scenario} eq 'wrk_version' } $suite->{skipped}->@* ),
        'unused optional wrk probe failure explicitly skipped'
    );
    my $binary = "$dir/wrk-fixture";
    my $content =
      "non-executable fixture whose bytes determine compatibility\n";
    open my $handle, '>:raw', $binary or croak $ERRNO;
    print {$handle} $content or croak $ERRNO;
    close $handle            or croak $ERRNO;
    local *GPForum::Performance::HTTP::which       = sub { return $binary; };
    local *GPForum::Performance::HTTP::wrk_version = sub {
        return 'wrk (distribution package 4.1; CLI upstream unspecified)';
    };
    local *GPForum::Performance::HTTP::mojo_measure = sub {
        return ( { $metrics->%*, http_errors => 0, transport_errors => 0 },
            {} );
    };
    capture(
        sub {
            is(
                main(
                    '--output',              "$dir/unverified",
                    '--disposable-database', '--generator',
                    'mojo',                  '--repetitions',
                    '1'
                ),
                0,
'unknown upstream version still yields honest indicative Mojo data'
            );
        }
    );
    my $environment = read_json("$dir/unverified/http-environment.json");
    is(
        $environment->{configuration}{wrk_binary_sha256},
        sha256_hex($content),
        'unknown upstream wrk compatibility uses actual binary fingerprint'
    );
    ok( !$environment->{configuration}{wrk_upstream_version_verified},
        'upstream version is explicitly unverified' );
    return undef;
}
subtest 'optional wrk and independent cell failure retain real Mojo evidence' =>
  \&test_partial_cells;
done_testing;

1;
