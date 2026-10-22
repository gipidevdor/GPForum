# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause
package main;
use v5.40;
use Carp    qw(croak);
use English qw(-no_match_vars);
our $VERSION = '0.001';
use Test::More;
use File::Temp qw(tempdir);
use List::Util qw(any);

# Core-only sampling fixtures have explicit units and resource thresholds.
use constant {    ## no critic (ValuesAndExpressions::ProhibitConstantPragma)
    MAX_CONNECTIONS            => 500,
    MEMORY_BYTES               => 17_179_869_184,
    RSS_PEAK_BYTES             => 90,
    FD_PEAK                    => 503,
    LAST_SAMPLE_SECOND         => 3,
    GENERATOR_PID              => 201,
    MEASURE_BUDGET_SECONDS     => 30,
    PREVIOUS_CONNECTIONS       => 250,
    DEGRADED_RPS               => 900,
    DEGRADED_LATENCY_MS        => 20,
    STOP_LATENCY_MS            => 2001,
    LOW_MEMORY_FRACTION        => 0.1,
    GENERATOR_BUSY_PERCENT     => 180,
    SATURATED_LATENCY_MS       => 2500,
    HOST_BUSY_PERCENT          => 95,
    SHORT_CPU_SPAN_SECONDS     => 0.5,
    HIGH_FD_PEAK               => 3500,
    HIGH_GENERATOR_CPU_PERCENT => 170,
    RECOVERY_ROUNDS            => 3,
    TINY_DEADLINE_SECONDS      => 0.01,
    COMPLETED_REQUESTS         => 100,
};
use JSON::PP;
use lib 'script/lib';
use GPForum::Performance::ExtremeLoad
  qw(measure classify stop_reason allow_1000 recovery validate_weights parse_extreme default_weights);
use GPForum::Performance::Resources;
use GPForum::Performance::HTTP    qw(which parse_wrk);
use GPForum::Performance::Support qw(root_dir monotonic run_bounded);

sub dies ( $callback, $pattern, $label ) {
    my $error;
    try { $callback->() } catch ($failure) {
        $error = $failure
    };
    like( "$error", $pattern, $label );
    return undef;
}

# The in-file fixture avoids spawning an actual HTTP server for failure cases.
package FakeServer {    ## no critic (Modules::ProhibitMultiplePackages)
    use Carp qw(croak);

    sub telemetry ($self) {
        if ( $self->{fail} ) { croak 'worker count changed'; }
        return [
            { pid => 102, reactor => $self->{reactor} },
            { pid => 103, reactor => $self->{reactor} }
        ];
    }
}

sub server {
    return bless {
        base    => 'http://127.0.0.1:9000',
        master  => 101,
        workers => 2,
        reactor => 'Mojo::Reactor::Poll'
      },
      'FakeServer';
}

sub output ( $errors = 0 ) {
    return 'GPFORUM_WRK '
      . encode_json(
        {
            completed           => 100,
            http_errors         => 0,
            transport_errors    => $errors,
            duration_seconds    => 2,
            requests_per_second => 50,
            p50_ms              => 5,
            p95_ms              => 10,
            p99_ms              => 15
        }
      )
      . "\nGPFORUM_EXTREME "
      . encode_json(
        {
            timeouts       => $errors,
            connect_errors => 0,
            read_errors    => 0,
            write_errors   => 0,
            issued_counts  => default_weights()
        }
      ) . "\n";
}

sub row ( $concurrency = MAX_CONNECTIONS ) {
    return {
        status      => 'ok',
        concurrency => $concurrency,
        metrics     => {
            requests_per_second => 1000,
            http_errors         => 0,
            transport_errors    => 0,
            timeouts            => 0,
            p95_ms              => 10
        },
        evidence => {
            resource_summary => {
                cpu_count                  => 4,
                memory_bytes               => MEMORY_BYTES,
                nofile_soft                => 4096,
                generator_cpu_percent      => 50,
                generator_threads          => 2,
                generator_cpu_span_seconds => 2,
                generator_fd_peak          => 501,
                server_fd_peak_per_process => 260,
                memory_available_fraction  => .6,
                host_busy_percent          => 60,
                host_steal_percent         => 0
            }
        }
    };
}
is_deeply( validate_weights(), default_weights(), 'default weights retained' );
for my $weights (
    {},
    { %{ default_weights() }, thread =>  51 },
    { %{ default_weights() }, search => -1 },
    { %{ default_weights() }, extra  =>  0 },
    { %{ default_weights() }, thread => JSON::PP::true }
  )
{
    dies( sub { validate_weights($weights) },
        qr/weight/msx, 'invalidweights rejected' );
}
is( parse_extreme( output(2) )->{timeouts}, 2, 'timeout separatenotaggregate' );
for my $bad ( q{}, "GPFORUM_EXTREME {}\n", output() . output() ) {
    dies(
        sub { parse_extreme($bad) },
        qr/record|metric/msx,
        'invalidmarker rejected'
    );
}
{
    my $sampler = GPForum::Performance::Resources->new(
        { server => server(), threads => 2 } );
    $sampler->{samples} = [
        {
            elapsed_seconds => 0,
            generator       => { ticks => 10, rss_bytes => 50, fds => 2 },
            server          => {},
            host            => undef
        },
        {
            elapsed_seconds => 2,
            generator       => { ticks => 110, rss_bytes => 90, fds => 503 },
            server          => {},
            host            => undef
        },
        {
            elapsed_seconds => 3,
            generator       => undef,
            server          => {},
            host            => undef
        }
    ];
    my $summary = $sampler->summary;
    is( $summary->{generator_cpu_span_seconds},
        2, 'dead generator alive span retained' );
    is( $summary->{generator_rss_peak_bytes},
        RSS_PEAK_BYTES, 'RSSsamplepeak retained' );
    is( $summary->{generator_fd_peak}, FD_PEAK, 'FDpeak retained' );
    ok( !defined $summary->{server_cpu_percent}, 'unobserved CPU null' );
}
{
    my $count   = 0;
    my $sampler = GPForum::Performance::Resources->new(
        {
            server     => server(),
            threads    => 2,
            pg_sampler => sub { $count++; return { connections => 2 } }
        }
    );
    local *GPForum::Performance::Resources::process_snapshot =
      sub { return { worker_pids => [] } };
    local *GPForum::Performance::Resources::process = sub { return undef };
    local *GPForum::Performance::Resources::host    = sub { return undef };
    for ( 0 .. LAST_SAMPLE_SECOND ) { $sampler->sample( GENERATOR_PID, $_ ); }
    is( $count, 2, 'PGsnapshot maxevery2s' );
}
{
    my $dir = tempdir( CLEANUP => 1 );
    my @commands;
    local *GPForum::Performance::ExtremeLoad::probe_url =
      sub ( $url, $options = {} ) { return ( $url, 'hit' ) };
    local *GPForum::Performance::ExtremeLoad::run_bounded =
      sub ( $argv, $options ) {
        push @commands, [ $argv, $options ];
        return output();
      };
    my $first = measure(
        server(),
        {
            scenario    => 'mixed',
            concurrency => 50,
            duration    => 2,
            deadline    => monotonic() + MEASURE_BUDGET_SECONDS,
            diagnostics => $dir
        }
    );
    my $repeat = measure(
        server(),
        {
            scenario    => 'mixed',
            concurrency => 50,
            duration    => 2,
            deadline    => monotonic() + MEASURE_BUDGET_SECONDS,
            diagnostics => $dir
        }
    );
    is( $first->{status}, 'ok', 'mixedactualmetrics' );
    my $changed_server = server();
    local *GPForum::Performance::ExtremeLoad::run_bounded = sub {
        $changed_server->{fail} = 1;
        return output();
    };
    my $postflight = measure(
        $changed_server,
        {
            scenario    => 'thread',
            concurrency => 50,
            duration    => 2,
            deadline    => monotonic() + MEASURE_BUDGET_SECONDS,
            diagnostics => $dir
        }
    );
    is( $postflight->{status}, 'failed',
        'worker change during load fails postflight validation' );
    is( $postflight->{metrics}{completed},
        COMPLETED_REQUESTS, 'completed load metrics survive postflight error' );
    is( classify( $postflight->{metrics}, $postflight->{evidence} ),
        'inconclusive', 'invalid telemetry cannot claim capacity' );
    ok( !defined $first->{metrics}{concurrency_effective},
        'wrk inflightunobserved' );
    is_deeply( $first->{evidence}{weights},
        default_weights(), 'weightsrecorded' );
    isnt(
        $first->{evidence}{diagnostic_log},
        $repeat->{evidence}{diagnostic_log},
        'logsimmutable separatecells'
    );
    ok( ( any { $_ eq q{--} } @{ $commands[0][0] } ),
        'safe Lua args delimiter' );
    my $skipped = measure(
        server(),
        {
            scenario    => 'thread',
            concurrency => 50,
            duration    => 2,
            deadline    => monotonic() + 1,
            diagnostics => $dir
        }
    );
    is( $skipped->{status}, 'skipped', 'budgetshortskip' );
    local *GPForum::Performance::ExtremeLoad::run_bounded =
      sub { return output(2) };
    my $failed = measure(
        server(),
        {
            scenario    => 'thread',
            concurrency => 50,
            duration    => 2,
            deadline    => monotonic() + MEASURE_BUDGET_SECONDS,
            diagnostics => $dir
        }
    );
    is( $failed->{status},            'failed', 'timeoutsfailed' );
    is( $failed->{metrics}{timeouts}, 2, 'timeoutactualcounter retained' );
    local $ENV{GPFORUM_DATABASE_PASSWORD} = 'canary-secret';
    local *GPForum::Performance::ExtremeLoad::run_bounded =
      sub { croak 'password=canary-secret; dbi:Pg:dbname=private;host=example' };
    $failed = measure(
        server(),
        {
            scenario    => 'thread',
            concurrency => 50,
            duration    => 2,
            deadline    => monotonic() + MEASURE_BUDGET_SECONDS,
            diagnostics => $dir
        }
    );
    unlike( encode_json($failed), qr/canary-secret|dbi:Pg:/msx,
        'failure secretandDSNredacted' );
    ok( exists $failed->{evidence}{resource_summary},
        'failedgenerator keepssamples' );
}
my $previous = row(PREVIOUS_CONNECTIONS);
my $current  = row();
ok( !defined stop_reason( $current, $previous ), 'healthyprogression' );
$current->{metrics}{requests_per_second} = DEGRADED_RPS;
$current->{metrics}{p95_ms}              = DEGRADED_LATENCY_MS;
like( stop_reason( $current, $previous ),
    qr/throughput/msx, 'rpsfall latencyrise stops' );
for my $pair ( [ 'p95_ms', STOP_LATENCY_MS ], [ 'transport_errors', 1 ] ) {
    my $point = row();
    $point->{metrics}{ $pair->[0] } = $pair->[1];
    ok( stop_reason($point), 'errors/latencystop' );
}
my $point = row();
$point->{evidence}{resource_summary}{memory_available_fraction} =
  LOW_MEMORY_FRACTION;
like( stop_reason($point), qr/memory/msx, 'memoryheadroomstop' );
$point = row();
$point->{evidence}{resource_summary}{generator_cpu_percent} =
  GENERATOR_BUSY_PERCENT;
is( classify( $point->{metrics}, $point->{evidence} ),
    'observed-capacity', 'CPUalone notsaturation' );
$point->{metrics}{p95_ms} = SATURATED_LATENCY_MS;
is( classify( $point->{metrics}, $point->{evidence} ),
    'generator-saturation', 'CPUanddegradation saturate generator' );
$point->{evidence}{resource_summary}{host_busy_percent} = HOST_BUSY_PERCENT;
is( classify( $point->{metrics}, $point->{evidence} ),
    'inconclusive', 'hostcontention inconclusive' );
$point = row();
$point->{metrics}{p95_ms} = SATURATED_LATENCY_MS;
is( classify( $point->{metrics}, $point->{evidence} ),
    'inconclusive', 'missingPG attributionunknown' );
$point->{evidence}{resource_samples} =
  [ { postgres => { saturated => JSON::PP::true } } ];
is( classify( $point->{metrics}, $point->{evidence} ),
    'database-saturation', 'explicitPGsaturation' );
$point->{evidence}{resource_samples} =
  [ { postgres => { saturated => JSON::PP::false } } ];
is( classify( $point->{metrics}, $point->{evidence} ),
    'inconclusive', 'connectionheadroom doesntproveDBCPU' );
$point->{evidence}{resource_samples}[0]{postgres}{resource_headroom_verified} =
  JSON::PP::true;
is( classify( $point->{metrics}, $point->{evidence} ),
    'application-saturation', 'verifiedPGheadroom allowsappattribution' );
ok( !( allow_1000( [ row() ] ) )[0],       '1000 requiresrepeats' );
ok( ( allow_1000( [ row(), row() ] ) )[0], '1000 withmeasuredheadroom' );
my $different_scenarios = [ row(), row() ];
$different_scenarios->[0]{scenario} = 'thread';
$different_scenarios->[1]{scenario} = 'mixed';
ok(
    !( allow_1000($different_scenarios) )[0],
    'different scenarios cannot jointly authorize 1000'
);

for my $pair (
    [ 'generator_cpu_percent',      undef ],
    [ 'generator_cpu_span_seconds', SHORT_CPU_SPAN_SECONDS ],
    [ 'cpu_count',                  2 ],
    [ 'memory_available_fraction',  LOW_MEMORY_FRACTION ],
    [ 'generator_fd_peak',          HIGH_FD_PEAK ],
    [ 'host_busy_percent',          HOST_BUSY_PERCENT ],
    [ 'generator_cpu_percent',      HIGH_GENERATOR_CPU_PERCENT ]
  )
{
    my $candidate = row();
    $candidate->{evidence}{resource_summary}{ $pair->[0] } = $pair->[1];
    ok( !( allow_1000( [ $candidate, $candidate ] ) )[0],
        "1000gate $pair->[0]" );
}
{
    local *GPForum::Performance::ExtremeLoad::probe_url =
      sub { return ( 'url', undef ) };
    local *GPForum::Performance::ExtremeLoad::sleep = sub { return undef };
    my $result = recovery( server(),
        { deadline => monotonic() + MEASURE_BUDGET_SECONDS } );
    is( $result->{status}, 'ok', 'recoverythreeconsecutiverounds' );
    is( scalar @{ $result->{attempts} },
        RECOVERY_ROUNDS, 'three rounds required' );
    local *GPForum::Performance::ExtremeLoad::probe_url =
      sub { croak 'read timeout' };
    $result =
      recovery( server(), { deadline => monotonic() + TINY_DEADLINE_SECONDS } );
    is( $result->{status}, 'failed', 'recoverytimeoutfailed' );
    is( recovery( server(), { deadline => monotonic() - 1 } )->{status},
        'skipped', 'no recoverybudget skipped' );
}
SKIP: {
    if ( !( which('luajit') ) ) {
        skip
'optional LuaJIT executable unavailable; live wrk integration verifies Lua',
          2;
    }
    my $lua          = root_dir() . '/benchmarks/wrk-extreme.lua';
    my $metrics_path = root_dir() . '/benchmarks/wrk-metrics.lua';
    my $code =
q{wrk={format=function(method,path)return method .. ' ' .. path end};local thread={set=function(self,name,value)_G[name]=value end,get=function(self,name)return _G[name] end};dofile(LUA_PATH);setup(thread);init({METRICS_PATH,'mixed','thread','50','/thread','category','20','/category','home','15','/','search','10','/search?q=performance','other','5','/categories'});local counts={};for i=1,100 do local req=request();counts[req]=(counts[req] or 0)+1 end;assert(counts['GET /thread']==50 and counts['GET /category']==20 and counts['GET /']==15 and counts['GET /search?q=performance']==10 and counts['GET /categories']==5);assert(response==nil);done({duration=1000000,requests=100,errors={status=0,connect=0,read=0,write=0,timeout=0}},{percentile=function(self,p)return 1000 end},{})};
    my $encoded = encode_json($lua);
    $code =~ s/LUA_PATH/$encoded/msx;
    $encoded = encode_json($metrics_path);
    $code =~ s/METRICS_PATH/$encoded/msx;
    my $result = run_bounded( [ 'luajit', '-e', $code ], { timeout => 3 } );
    is_deeply( parse_extreme($result)->{issued_counts},
        default_weights(), 'realLuaweightedcycle' );
    is( parse_wrk($result)->{completed},
        COMPLETED_REQUESTS, 'reusedLua done executes' );
}
done_testing;

1;
