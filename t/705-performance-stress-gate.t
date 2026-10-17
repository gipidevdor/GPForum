#!/usr/bin/env perl
# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

# The 5000-connection gate measures every cell it plans, fails when one is
# missing, records how far each sample sits from the three-second budget and
# whether the runner could meet it at all, and the workflow check reads the
# gate's own summary (ADR 0063).

use v5.40;
use Carp    qw(croak);
use English qw(-no_match_vars);
use Test::More;
use File::Temp qw(tempdir);
use List::Util qw(any first);
use JSON::PP   qw(encode_json);

use lib 'script/lib';
use GPForum::Performance::HTTP qw(main parse_listen_counters connection_spread);
use GPForum::Performance::Server;
use GPForum::Performance::Support        qw(read_json write_json);
use GPForum::Performance::WorkflowStatus ();

our $VERSION = '0.001';

## no critic (ValuesAndExpressions::ProhibitMagicNumbers) -- fixture figures

sub quietly ($callback) {
    open my $silent, '>', \my $text or croak $ERRNO;
    local *STDOUT = $silent;
    my $result = $callback->();
    close $silent or croak $ERRNO;
    return $result;
}

# Runs the CI gate's command line against stubbed servers and generators:
# $measure answers each cell by its concurrency.
sub gate_run ( $measure, $options = {} ) {
    my $dir = tempdir( CLEANUP => 1 );
    my @clients;
    local $ENV{GPFORUM_DATABASE_DSN} = 'dbi:Pg:dbname=gpforum_perf_test';
    local *GPForum::Performance::HTTP::which       = sub { return '/fake/wrk' };
    local *GPForum::Performance::HTTP::nofile_soft = sub { return 32_768 };
    local *GPForum::Performance::HTTP::listen_queue_limit =
      sub { return $options->{somaxconn} // 8192 };
    local *GPForum::Performance::HTTP::prepare_dataset = sub {
        return (
            { counts   => {},   signature         => 'known' },
            { postgres => '18', database_settings => {} }
        );
    };
    local *GPForum::Performance::HTTP::probe_reactor = sub { return 1 };
    local *GPForum::Performance::HTTP::run_bounded =
      sub { return encode_json( { perl => 'v5.40', mojolicious => '9.49' } ) };
    local *GPForum::Performance::HTTP::wrk_version = sub { return 'wrk 4.2.0' };
    local *GPForum::Performance::Server::new       = sub ( $class, $args ) {
        push @clients, $args->{clients};
        return bless { reactor => 'Mojo::Reactor::EV', %{$args} }, $class;
    };
    ## no critic (NamingConventions::ProhibitAmbiguousNames) -- the public name
    local *GPForum::Performance::Server::close = sub { return undef };
    ## use critic
    local *GPForum::Performance::HTTP::wrk_measure = sub ( $server, $cell, @ ) {
        my $metrics = $measure->( $cell->{concurrency} );
        return ( $metrics,
            { connections_per_worker => [ 1500, 1500, 1200, 800 ] } );
    };
    my $exit = quietly(
        sub {
            main(
                '--output',      $dir,
                '--mode',        'pr',
                '--generator',   'wrk',
                '--concurrency', '1000,5000',
                '--allow-5000',  '--scenario',
                'health_live',   '--workers',
                4,               '--wrk-timeout',
                3,               '--duration',
                1,               '--repetitions',
                1,               '--disposable-database',
            );
        }
    );
    my $http = -e "$dir/http.json" ? read_json("$dir/http.json") : {};
    return {
        exit    => $exit,
        clients => \@clients,
        http    => $http,
        suite   => read_json("$dir/suite-status.json")->{http},
    };
}

sub sample ( $p95, $p99, $rps, $errors = 0 ) {
    return {
        completed           => 10_000,
        http_errors         => 0,
        transport_errors    => $errors,
        duration_seconds    => 10,
        requests_per_second => $rps,
        p50_ms              => $p95 / 2,
        p95_ms              => $p95,
        p99_ms              => $p99,
    };
}

subtest 'a slow 1000 no longer skips the 5000 it gates' => sub {
    my $run = gate_run(
        sub ($concurrency) {
            return $concurrency == 1000
              ? sample( 2500, 2600, 3000 )
              : sample( 2000, 2400, 3100 );
        }
    );
    is( $run->{exit}, 0, 'the gate passes when every sample is clean' );
    is_deeply(
        [ map { $_->{concurrency} } @{ $run->{http}{measurements} } ],
        [ 1000, 5000 ],
        'both planned levels were measured despite the 1000 p95'
    );
    is( $run->{suite}{status}, 'ok', 'the suite is complete' );
    is_deeply( $run->{clients}, [5000],
        'the workload stays uncapped: any worker may take every connection' );
    my $row =
      first { $_->{concurrency} == 5000 } @{ $run->{http}{measurements} };
    is( $row->{budget}{budget_ms}, 3000, 'the budget is the wrk timeout' );
    is( $row->{budget}{margin_ms}, 600,  'the p99 margin is recorded' );
    is( $row->{budget}{closed_loop_floor_ms},
        1613, 'the closed-loop floor is connections over throughput' );
    is( $row->{budget}{worst_case_ms},
        3226, 'a request that misses a turn waits two' );
    is( $row->{budget}{required_rps},
        3334, 'so two turns fit the budget from 3334 requests/s' );
    ok( !$row->{failure_kind}, 'a clean sample is not blamed on the runner' );
    ok(
        (
            any { /5000[ ]connections:[ ]p99[ ]up[ ]to[ ]2400[ ]ms/msx }
              @{ $run->{http}{limitations} }
        ),
        'the margin reaches the report'
    );
};

subtest 'a required cell that is not measured fails the gate' => sub {
    my $run = gate_run(
        sub ($concurrency) {
            croak 'generator lost' if $concurrency == 5000;
            return sample( 300, 400, 3000 );
        }
    );
    is( $run->{exit},          1,        'the gate exits non-zero' );
    is( $run->{suite}{status}, 'failed', 'and says failed, not partial' );
    like(
        $run->{suite}{reason},
        qr{health_live/4/5000[ ]repetition[ ]1[ ]was[ ]not[ ]measured}msx,
        'naming the missing cell'
    );
};

subtest 'timeouts on a runner below the bar say so' => sub {
    my $run = gate_run(
        sub ($concurrency) {
            return $concurrency == 1000
              ? sample( 700, 800, 1400 )
              : sample( 2900, 2990, 1400, 900 );
        }
    );
    is( $run->{exit}, 1, 'errors still fail the gate' );
    my $row =
      first { $_->{concurrency} == 5000 } @{ $run->{http}{measurements} };
    is( $row->{failure_kind}, 'runner_below_bar',
        'two turns over the budget make timeouts the runner, not noise' );
    ok(
        (
            any { /cannot[ ]hold[ ]5000[ ]connections/msx }
              @{ $run->{http}{limitations} }
        ),
        'and the report says the runner cannot meet the bar'
    );
};

subtest 'a listen queue shorter than the burst is refused' => sub {
    my $run = gate_run( sub ($c) { return sample( 300, 400, 3000 ) },
        { somaxconn => 4096 } );
    is( $run->{exit}, 1, 'the gate does not measure through a short queue' );
    like( $run->{suite}{reason}, qr/somaxconn/msx, 'and names the limit' );
};

subtest 'helpers' => sub {
    is_deeply(
        parse_listen_counters(
"TcpExt: SyncookiesSent ListenOverflows ListenDrops\nTcpExt: 0 7 9\nIpExt: A\nIpExt: 1\n"
        ),
        { listen_overflows => 7, listen_drops => 9 },
        'listen counters from /proc/net/netstat'
    );
    is( parse_listen_counters("IpExt: A\nIpExt: 1\n"),
        undef, 'absent counters are unknown' );
    is_deeply(
        connection_spread( { 1 => 12, 2 => 9 }, { 1 => 1512, 2 => 509 } ),
        [ 1500, 500 ],
        'connections per worker exclude the idle baseline, largest first'
    );
};

subtest 'the workflow check reads the gate summary too' => sub {
    my $main = tempdir( CLEANUP => 1 );
    my $gate = "$main/connections-5000";
    mkdir $gate or croak $ERRNO;
    write_json( "$main/summary.json", { status => 'ok' } );
    my $check = sub {
        open my $ignored, '>', \my $text or croak $ERRNO;
        my $exit = do {
            local *STDERR = $ignored;
            GPForum::Performance::WorkflowStatus::main( '--output', $main,
                '--check', '--gate', $gate );
        };
        close $ignored or croak $ERRNO;
        return $exit;
    };
    is( $check->(), 1, 'a gate without a summary did not run' );
    write_json( "$gate/summary.json", { status => 'partial' } );
    is( $check->(), 1, 'a partial gate is not a pass' );
    write_json( "$gate/summary.json", { status => 'ok' } );
    is( $check->(), 0, 'a complete gate passes' );
    write_json( "$main/summary.json", { status => 'partial' } );
    is( $check->(), 0, 'the main suite keeps its partial tolerance' );
};

done_testing;
