# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause
package GPForum::Performance::ExtremeLoad;
use v5.40;
use Carp    qw(croak);
use English qw(-no_match_vars);
our $VERSION = '0.001';
use Exporter 'import';
use JSON::PP;
use File::Path                    qw(make_path);
use Time::HiRes                   qw(sleep);
use List::Util                    qw(min max sum any all);
use GPForum::Performance::Support qw(root_dir redact monotonic run_bounded);
use GPForum::Performance::HTTP    qw(scenarios parse_wrk probe_url);
use GPForum::Performance::Resources;
our @EXPORT_OK =
  qw(measure classify stop_reason allow_1000 recovery validate_weights parse_extreme default_weights);

# The load harness must remain usable before Carton application dependencies.
use constant {    ## no critic (ValuesAndExpressions::ProhibitConstantPragma)
    WEIGHT_TOTAL          => 100,
    MAX_CONCURRENCY       => 1000,
    CAPABLE_CONCURRENCY   => 500,
    MAX_DURATION          => 30,
    DEADLINE_PREFLIGHT    => 5,
    GENERATOR_MARGIN      => 4,
    MIN_WARMUP            => 8,
    WARMUP_PER_WORKER     => 4,
    MIN_PROBE_TIMEOUT     => .1,
    LATENCY_STOP_MS       => 2000,
    THROUGHPUT_FALL_RATIO => .95,
    LATENCY_RISE_RATIO    => 1.2,
    HOST_BUSY_LIMIT       => 90,
    HOST_STEAL_LIMIT      => 5,
    GENERATOR_SATURATION  => 85,
    GENERATOR_HEADROOM    => 80,
    STOP_MEMORY_FRACTION  => .15,
    MIN_MEMORY_FRACTION   => .2,
    FD_USED_LIMIT         => .75,
    MIN_CPUS              => 4,
    MIN_MEMORY_BYTES      => 8 * 1024**3,
    MIN_FD_SOFT           => 4096,
    DEFAULT_RECOVERY      => 20,
    RECOVERY_SUCCESSES    => 3,
    RECOVERY_INTERVAL     => .2,
    UNBOUNDED_CAP         => 1e99,
};
my %DEFAULT =
  ( thread => 50, category => 20, home => 15, search => 10, other => 5, );
sub default_weights { return {%DEFAULT} }

sub _nonnegative_integer ($value) {
    return defined($value) && !ref($value) && $value =~ /\A\d+\z/msx;
}

sub _same_keys ($value) {
    my $expected = join q{,}, sort keys %DEFAULT;
    return ref($value) eq 'HASH'
      && join( q{,}, sort keys $value->%* ) eq $expected;
}

sub validate_weights ( $weights = undef ) {
    my $value = $weights // default_weights();
    if ( !_same_keys($value)
        || any { !_nonnegative_integer($_) || $_ > WEIGHT_TOTAL }
        values $value->%* )
    {
        croak
'mixed weights require thread/category/home/search/other integers 0..100 summing to 100';
    }
    if ( sum( values $value->%* ) != WEIGHT_TOTAL ) {
        croak 'mixed weights must sum to 100';
    }
    return { $value->%* };
}

sub parse_extreme ($raw) {
    my @records = $raw =~ /^GPFORUM_EXTREME[ ]([{][^\n]+[}])$/mgsx;
    if ( @records != 1 ) {
        croak 'wrk did not return one extreme metrics record';
    }
    my $result = decode_json( $records[0] );
    for my $key (qw(timeouts connect_errors read_errors write_errors)) {
        if ( !_nonnegative_integer( $result->{$key} ) ) {
            croak "invalid extreme metric $key";
        }
        $result->{$key} = 0 + $result->{$key};
    }
    my $counts = $result->{issued_counts};
    if ( !_same_keys($counts)
        || any { !_nonnegative_integer($_) } values $counts->%* )
    {
        croak 'invalid mixed issued counts';
    }
    return $result;
}

sub _canonical ( $server, $scenario ) {
    my $endpoint =
      scenarios()->{ $scenario eq 'other' ? 'categories' : $scenario };
    my ( $url, $cache ) = probe_url( $server->{base} . $endpoint );
    if ( index( $url, $server->{base} . q{/} ) != 0 ) {
        croak 'benchmark redirect escaped the local server';
    }
    my $path = substr $url, length $server->{base};
    if ( $path !~ m{\A/}msx || $path =~ /[\s\x00-\x1f]/msx ) {
        croak 'invalid canonical benchmark path';
    }
    return ( $url, $path, $cache );
}

sub _validate_measure ($args) {
    my ( $scenario, $concurrency, $duration ) =
      $args->@{qw(scenario concurrency duration)};
    if (   !defined($scenario)
        || ( $scenario ne 'mixed' && !exists scenarios()->{$scenario} )
        || !_nonnegative_integer($concurrency)
        || $concurrency < 1
        || $concurrency > MAX_CONCURRENCY
        || !defined($duration)
        || $duration < 1
        || $duration > MAX_DURATION )
    {
        croak 'invalid bounded extreme measurement';
    }
    return undef;
}

sub _warm_route ( $server, $name, $args ) {
    my ( $canonical, $path ) = _canonical( $server, $name );
    my $expected =
      $name eq 'cache_hit' ? 'hit' : $name eq 'cache_miss' ? 'miss' : undef;
    my $cache;
    for ( 1 .. max( MIN_WARMUP, $server->{workers} * WARMUP_PER_WORKER ) ) {
        if ( $args->{deadline} - monotonic() <
            $args->{duration} + GENERATOR_MARGIN )
        {
            croak 'phase deadline during warming';
        }
        ( undef, $cache ) = probe_url( $canonical,
            { timeout => min( 2, $args->{deadline} - monotonic() ) } );
    }
    if ( $expected && ( $cache // q{} ) ne $expected ) {
        croak "cache $expected preflight failed";
    }
    return [ $name, $canonical, $path, $expected ];
}

sub _routes ( $server, $args, $weights ) {
    my @routes;
    for my $name ( $weights ? sort keys $weights->%* : $args->{scenario} ) {
        if ( $weights && !$weights->{$name} ) { next; }
        push @routes, _warm_route( $server, $name, $args );
    }
    return \@routes;
}

sub _command ( $args, $routes, $weights ) {
    my @command = (
        'wrk',
        '--latency',
        '-t',
        min( 2, $args->{concurrency} ),
        '-c',
        $args->{concurrency},
        '-d',
        "$args->{duration}s",
        '--timeout',
        '3s',
        '-s',
        root_dir() . '/benchmarks/wrk-extreme.lua',
        $routes->[0][1],
        q{--},
        root_dir() . '/benchmarks/wrk-metrics.lua',
        $weights ? 'mixed' : 'single',
    );
    if ($weights) {
        for my $route ( $routes->@* ) {
            push @command, $route->[0], $weights->{ $route->[0] }, $route->[2];
        }
    }
    return \@command;
}

sub _transport_metrics ( $raw, $weights ) {
    my $metrics = parse_wrk($raw);
    my $extra   = parse_extreme($raw);
    if ( $weights && !sum( values $extra->{issued_counts}->%* ) ) {
        croak 'mixed generator reported no issued request distribution';
    }
    for my $name (qw(timeouts connect_errors read_errors write_errors)) {
        $metrics->{$name} = $extra->{$name};
    }
    if (
        $metrics->{transport_errors} != sum(
            map { $metrics->{$_} }
              qw(timeouts connect_errors read_errors write_errors)
        )
      )
    {
        croak 'wrk transport counters do not reconcile';
    }
    return ( $metrics, $extra );
}

sub _postflight ( $server, $args, $routes ) {
    $server->telemetry;
    for my $route ( $routes->@* ) {
        my ( undef, $url, undef, $expected ) = $route->@*;
        my ( undef, $observed ) = probe_url(
            $url,
            {
                timeout => min(
                    2, max( MIN_PROBE_TIMEOUT, $args->{deadline} - monotonic() )
                ),
            }
        );
        if ( $expected && ( $observed // q{} ) ne $expected ) {
            croak 'cache policy changed after load';
        }
    }
    return undef;
}

sub _run_measure ( $server, $args, $row, $sampler ) {
    my $weights =
      $args->{scenario} eq 'mixed'
      ? validate_weights( $args->{weights} )
      : undef;
    my $routes  = _routes( $server, $args, $weights );
    my $before  = $server->telemetry;
    my $started = monotonic();
    state $counter = 0;
    my $log =
      "wrk-$args->{scenario}-$args->{concurrency}-$PID-" . ++$counter . '.log';
    $row->{evidence}{diagnostic_log} = $log;
    my $raw = run_bounded(
        _command( $args, $routes, $weights ),
        {
            timeout => min(
                $args->{duration} + GENERATOR_MARGIN,
                $args->{deadline} - $started
            ),
            log       => "$args->{diagnostics}/$log",
            on_sample =>
              sub ( $pid, $elapsed ) { $sampler->sample( $pid, $elapsed ); },
        }
    );
    my ( $metrics, $extra ) = _transport_metrics( $raw, $weights );
    my $resources = $sampler->summary;
    $metrics->@{
        qw(concurrency_effective cpu_percent rss_bytes generator_cpu_percent generator_rss_bytes)
      } = (
        undef,
        $resources->@{
            qw(server_cpu_percent server_rss_peak_bytes generator_cpu_percent generator_rss_peak_bytes)
        }
      );
    $row->{status} =
      $metrics->{http_errors} + $metrics->{transport_errors} ? 'failed' : 'ok';
    $row->{metrics}  = $metrics;
    $row->{evidence} = {
        generator              => 'wrk',
        reactor                => $server->{reactor},
        workers                => $server->{workers},
        worker_telemetry       => $before,
        resource_samples       => $sampler->{samples},
        resource_summary       => $resources,
        generator_wall_seconds => monotonic() - $started,
        weights                => $weights,
        issued_counts          => $extra->{issued_counts},
        diagnostic_log         => $log,
        canonical_paths        => { map { $_->[0] => $_->[2] } $routes->@* },
        limitation             =>
'Connections are configured, in-flight concurrency unobserved; weights count issued requests, not users or per-page capacity.',
    };
    _postflight( $server, $args, $routes );
    return undef;
}

sub measure ( $server, $args ) {
    _validate_measure($args);
    my $row = {
        scenario    => $args->{scenario},
        status      => 'failed',
        concurrency => 0 + $args->{concurrency},
        metrics     => {},
        evidence    => {}
    };
    make_path( $args->{diagnostics} );
    if ( $args->{deadline} - monotonic() <
        $args->{duration} + DEADLINE_PREFLIGHT )
    {
        $row->{status} = 'skipped';
        $row->{reason} = 'insufficient remaining phase deadline';
        return $row;
    }
    my $sampler = GPForum::Performance::Resources->new(
        {
            server     => $server,
            threads    => min( 2, $args->{concurrency} ),
            pg_sampler => $args->{pg_sampler},
        }
    );
    try { _run_measure( $server, $args, $row, $sampler ); }
    catch ($error) {
        $row->{status}                     = 'failed';
        $row->{reason}                     = redact($error);
        $row->{evidence}{validation_error} = $row->{reason};
    };
    $row->{evidence}{resource_samples} = $sampler->{samples};
    $row->{evidence}{resource_summary} = $sampler->summary;
    return $row;
}

sub _degraded ( $metrics, $previous ) {
    if ( !$previous
        || ( $previous->{concurrency} // 0 ) >=
        ( $metrics->{concurrency} // UNBOUNDED_CAP ) )
    {
        return 0;
    }
    my $prior = $previous->{metrics} // {};
    return ( $prior->{requests_per_second} // 0 ) > 0
      && ( $metrics->{requests_per_second} // UNBOUNDED_CAP ) <
      $prior->{requests_per_second} * THROUGHPUT_FALL_RATIO
      && ( $prior->{p95_ms}   // 0 ) > 0
      && ( $metrics->{p95_ms} // 0 ) > $prior->{p95_ms} * LATENCY_RISE_RATIO;
}

sub _unhealthy ( $metrics, $previous ) {
    return
         ( $metrics->{http_errors} // 0 ) + ( $metrics->{timeouts} // 0 ) > 0
      || ( $metrics->{p95_ms} // 0 ) > LATENCY_STOP_MS
      || _degraded( $metrics, $previous );
}

sub _host_contended ($resources) {
    return ( $resources->{host_busy_percent} // 0 ) >= HOST_BUSY_LIMIT
      || ( $resources->{host_steal_percent} // 0 ) >= HOST_STEAL_LIMIT;
}

sub _generator_saturated ($resources) {
    my ( $busy, $cpu, $threads ) = $resources->@{
        qw(host_busy_percent generator_cpu_percent generator_threads)};
    return
         defined($busy)
      && defined($cpu)
      && $threads
      && $cpu >= $threads * GENERATOR_SATURATION;
}

sub _application_headroom ( $resources, $pg ) {
    my ( $cpu, $threads ) =
      $resources->@{qw(generator_cpu_percent generator_threads)};
    return
         defined($cpu)
      && $threads
      && $cpu < $threads * GENERATOR_HEADROOM
      && $pg->@*
      && all {
             exists( $_->{saturated} )
          && !$_->{saturated}
          && $_->{resource_headroom_verified}
      } $pg->@*;
}

sub _inconclusive_evidence ( $metrics, $details ) {
    return
         !keys( $metrics->%* )
      || $details->{validation_error}
      || any { $metrics->{$_} // 0 }
      qw(connect_errors read_errors write_errors);
}

sub classify ( $metrics, $details, $previous = undef ) {
    if ( _inconclusive_evidence( $metrics, $details ) ) {
        return 'inconclusive';
    }
    my $resources = $details->{resource_summary} // {};
    my $unhealthy = _unhealthy( $metrics, $previous );
    if ( _host_contended($resources) ) {
        return $unhealthy ? 'inconclusive' : 'observed-capacity';
    }
    if ( $unhealthy && _generator_saturated($resources) ) {
        return 'generator-saturation';
    }
    my @pg = map { $_->{postgres} }
      grep { $_->{postgres} } ( $details->{resource_samples} // [] )->@*;
    if ( $unhealthy && any { $_->{saturated} } @pg ) {
        return 'database-saturation';
    }
    if ( $unhealthy && _application_headroom( $resources, \@pg ) ) {
        return 'application-saturation';
    }
    return $unhealthy ? 'inconclusive' : 'observed-capacity';
}

sub _fd_limit_reached ($resources) {
    my $limit = $resources->{nofile_soft};
    return $limit && any { defined && $_ >= $limit * FD_USED_LIMIT }
      $resources->@{qw(generator_fd_peak server_fd_peak_per_process)};
}

sub stop_reason ( $row, $previous = undef ) {
    my ( $metrics, $details ) =
      ( $row->{metrics} // {}, $row->{evidence} // {} );
    if ( ( $row->{status} // q{} ) ne 'ok' ) {
        return $row->{reason} // 'measurement failed or skipped';
    }
    if (   ( $metrics->{http_errors} // 0 )
        || ( $metrics->{transport_errors} // 0 ) )
    {
        return 'HTTP/transport errors; stop higher concurrency';
    }
    if ( ( $metrics->{p95_ms} // 0 ) > LATENCY_STOP_MS ) {
        return 'p95 exceeded 2000 ms';
    }
    if (
        _degraded(
            { $metrics->%*, concurrency => $row->{concurrency} }, $previous
        )
      )
    {
        return 'throughput fell by >5% while p95 rose by >20%';
    }
    my $resources = $details->{resource_summary} // {};
    if ( defined( $resources->{memory_available_fraction} )
        && $resources->{memory_available_fraction} < STOP_MEMORY_FRACTION )
    {
        return 'host available memory below 15%';
    }
    if ( _fd_limit_reached($resources) ) {
        return 'observed file descriptors reached 75% of soft limit';
    }
    if ( classify( $metrics, $details, $previous ) eq 'generator-saturation' ) {
        return 'generator saturated; higher load would be inconclusive';
    }
    return undef;
}

sub _headroom_reason ($values) {
    if ( any { !defined $values->{$_} }
        qw(cpu_count memory_bytes nofile_soft generator_cpu_percent generator_threads generator_cpu_span_seconds generator_fd_peak server_fd_peak_per_process memory_available_fraction host_busy_percent)
      )
    {
        return 'resource headroom is unmeasured; experimental 1000 skipped';
    }
    if (   $values->{cpu_count} < MIN_CPUS
        || $values->{memory_bytes} < MIN_MEMORY_BYTES
        || $values->{nofile_soft} < MIN_FD_SOFT )
    {
        return 'requires >=4 CPUs, >=8 GiB and >=4096 soft file descriptors';
    }
    if ( $values->{generator_cpu_percent} >=
           $values->{generator_threads} * GENERATOR_HEADROOM
        || $values->{generator_cpu_span_seconds} < 1 )
    {
        return 'generator CPU headroom not demonstrated';
    }
    if ( _fd_limit_reached($values) ) {
        return 'file descriptor headroom not demonstrated';
    }
    if ( $values->{memory_available_fraction} < MIN_MEMORY_FRACTION
        || _host_contended($values) )
    {
        return 'host memory/CPU headroom not demonstrated';
    }
    return undef;
}

sub allow_1000 ( $all, $resources = undef ) {
    my @rows =
      grep { ( $_->{concurrency} // 0 ) == CAPABLE_CONCURRENCY } $all->@*;
    my %scenarios = map { ( $_->{scenario} // q{} ) => 1 } @rows;
    if ( @rows < 2 || keys(%scenarios) != 1 || any { stop_reason($_) } @rows ) {
        return ( 0,
            'requires at least two successful unsaturated measurements at 500'
        );
    }
    for my $row (@rows) {
        my $reason = _headroom_reason(
            {
                ( $resources // {} )->%*,
                ( $row->{evidence}{resource_summary} // {} )->%*
            }
        );
        if ($reason) { return ( 0, $reason ); }
    }
    return ( 1,
'two valid 500 samples demonstrate measured generator/host headroom; 1000 remains experimental'
    );
}

sub _recover_round ( $server, $until ) {
    for my $name (qw(health_live thread search)) {
        if ( monotonic() >= $until ) { croak 'recovery deadline'; }
        probe_url(
            $server->{base} . scenarios()->{$name},
            { timeout => min( 1, $until - monotonic() ) }
        );
    }
    $server->telemetry;
    return undef;
}

sub recovery ( $server, $args ) {
    my $started = monotonic();
    my $until   = min( $args->{deadline},
        $started + ( $args->{maxseconds} // DEFAULT_RECOVERY ) );
    my ( $successes, @attempts, $reason );
    $successes = 0;
    $reason    = q{};
    while ( monotonic() < $until ) {
        my $ok;
        try { _recover_round( $server, $until ); $ok = 1; }
        catch ($error) { $reason = redact($error); };
        if ($ok) {
            $successes++;
            push @attempts,
              { elapsed_seconds => monotonic() - $started, status => 'ok' };
            if ( $successes >= RECOVERY_SUCCESSES ) {
                return {
                    status          => 'ok',
                    elapsed_seconds => monotonic() - $started,
                    attempts        => \@attempts,
                    reason          =>
'three consecutive successful health/thread/search probe rounds'
                };
            }
        }
        else {
            $successes = 0;
            push @attempts,
              {
                elapsed_seconds => monotonic() - $started,
                status          => 'failed',
                reason          => $reason
              };
        }
        sleep min( RECOVERY_INTERVAL, max( 0, $until - monotonic() ) );
    }
    return {
        status          => @attempts ? 'failed' : 'skipped',
        elapsed_seconds => monotonic() - $started,
        attempts        => \@attempts,
        reason          => $reason || 'recovery deadline exhausted'
    };
}
1;
