# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause
package GPForum::Performance::HTTP;
use v5.40;
use Carp    qw(croak);
use English qw(-no_match_vars);
our $VERSION = '0.001';
use Exporter 'import';
use JSON::PP;
use HTTP::Tiny;
use IO::Socket::INET;
use File::Path qw(make_path);
use File::Spec;
use Digest::SHA  qw(sha256_hex);
use Scalar::Util qw(looks_like_number);
use POSIX        qw(isfinite sysconf _SC_CLK_TCK _SC_OPEN_MAX uname);
use List::Util   qw(min max sum any);
use GPForum::Performance::Support
  qw(root_dir read_json write_json redact monotonic run_bounded);
our @EXPORT_OK =
  qw(scenarios free_port probe_url probe_reactor native_backend_flags wrk_version parse_wrk parse_mojo process_snapshot linux_cpu_ticks resources_between plan prepare_dataset runtime_environment wrk_measure mojo_measure main which cpu_count nofile_soft memory_bytes);
my @ORDER =
  qw(health_live home categories category thread search cache_hit cache_miss);
## no critic (ValuesAndExpressions::ProhibitConstantPragma) -- Core-only bootstrap cannot load Readonly before Carton dependencies.
use constant {
    CONCURRENCY_SMALL        => 10,
    CONCURRENCY_MEDIUM       => 50,
    CONCURRENCY_HIGH         => 100,
    CONCURRENCY_EXTENDED     => 250,
    CONCURRENCY_MAX          => 500,
    CONCURRENCY_EXPERIMENTAL => 1000,
    CONCURRENCY_STRESS       => 5000,
    MIN_FD_STRESS            => 16_384,
    DEFAULT_CLIENTS          => 2048,
    DEFAULT_BACKLOG          => 1024,
    STRESS_BACKLOG           => 8192,
    MIN_CPU_EXPERIMENTAL     => 4,
    WORKERS_MEDIUM           => 4,
    WORKERS_LARGE            => 8,
    KIB                      => 1024,
    GIB                      => 1024**3,
    MIN_GIB_EXPERIMENTAL     => 8,
    MIN_FD_EXPERIMENTAL      => 4096,
    EV_BACKEND_EPOLL         => 4,
    EV_BACKEND_KQUEUE        => 8,
    CPU_PERCENT_SCALE        => 100,
    MAX_DURATION             => 30,
    MAX_REPETITIONS          => 5,
    MIN_DEADLINE             => 30,
    MAX_DEADLINE             => 1800,
    VERSION_TIMEOUT          => 5,
    REACTOR_TIMEOUT          => 10,
    DB_SETTINGS_TIMEOUT      => 60,
    MIN_WARMUP               => 8,
    WARMUP_PER_WORKER        => 4,
    GENERATOR_MARGIN         => 8,
    STARTUP_MARGIN           => 12,
    MOJO_TIMEOUT             => 20,
    MOJO_MARGIN              => 22,
    MOJO_MIN_REQUESTS        => 100,
    MOJO_MIN_PER_CLIENT      => 10,
    RATE_LIMIT               => 100_000_000,
    CPU_USER_FIELD           => 11,
    CPU_SYSTEM_FIELD         => 12,
    ERROR_STOP_FRACTION      => .01,
    LATENCY_STOP_MS          => 2000,
    UNBOUNDED_CAP            => 1e99,
    FAILURE_SUMMARY_MAX      => 5,
    HTTP_OK                  => 200,
    HTTP_ERROR_MIN           => 400,
    REQUEST_TIMEOUT          => 3,
};
## use critic
my %SCENARIOS = (
    health_live => '/health/live',
    home        => q{/},
    categories  => '/categories',
    category    => '/c/018f1001-0001-7000-8000-000000000001',
    thread      => '/t/018f1004-0001-7000-8000-000000000001',
    search      => '/search?q=performance',
    cache_hit   => '/categories',
    cache_miss  => '/categories',
);
my %DEFAULTS = (
    pr => {
        duration    => 2,
        deadline    => 240,
        concurrency => [ 1, CONCURRENCY_SMALL ]
    },
    main => {
        duration    => 2,
        deadline    => 600,
        concurrency =>
          [ 1, CONCURRENCY_SMALL, CONCURRENCY_MEDIUM, CONCURRENCY_HIGH ]
    },
    deep => {
        duration    => 3,
        deadline    => 1200,
        concurrency => [
            1,                    CONCURRENCY_SMALL,
            CONCURRENCY_MEDIUM,   CONCURRENCY_HIGH,
            CONCURRENCY_EXTENDED, CONCURRENCY_MAX
        ],
    },
);
my $OS            = ( uname() )[0];
my %SEED_PROFILES = (
    main => {
        users              => 25,
        categories         => 8,
        threads            => 240,
        'posts-per-thread' => 20
    },
    deep => {
        users              => 40,
        categories         => 4,
        threads            => 600,
        'posts-per-thread' => 120
    },
);

sub _attempt ($callback) {
    my $result;
    try { $result = { ok => 1, value => $callback->() } }
    catch ($error) { $result = { ok => 0, error => $error } };
    return $result;
}
sub scenarios { return {%SCENARIOS} }

sub which ($name) {
    for my $dir ( File::Spec->path ) {
        my $file = File::Spec->catfile( $dir, $name );
        if ( -f $file && -x $file ) { return $file; }
    }
    return undef;
}

sub bytes ($path) {
    open my $fh, '<:raw', $path or croak "Cannot read benchmark file: $ERRNO";
    local $INPUT_RECORD_SEPARATOR = undef;
    my $data = <$fh>;
    close $fh or croak "Cannot close benchmark file: $ERRNO";
    return $data;
}

sub cpu_count {
    if ( -r '/proc/cpuinfo' ) {
        my $text  = bytes('/proc/cpuinfo');
        my $count = () = $text =~ /^processor\s*:/mgsx;
        if ($count) { return $count; }
    }
    my $value = _attempt(
        sub { run_bounded( [ 'sysctl', '-n', 'hw.ncpu' ], { timeout => 2 } ) } )
      ->{value};
    return $value && $value =~ /\A\s*(\d+)/msx ? 0 + $1 : 1;
}

sub nofile_soft {
    return _attempt( sub { sysconf(_SC_OPEN_MAX) } )->{value};
}

sub memory_bytes {
    if ( -r '/proc/meminfo' ) {
        my $text = bytes('/proc/meminfo');
        if ( $text =~ /^MemTotal:\s+(\d+)/msx ) { return KIB * $1; }
    }
    for my $name (qw(hw.memsize hw.physmem)) {
        my $value = _attempt(
            sub { run_bounded( [ 'sysctl', '-n', $name ], { timeout => 2 } ) } )
          ->{value};
        return 0 + $1 if defined $value && $value =~ /\A\s*(\d+)\s*\z/msx;
    }
    return 0;
}

sub free_port {
    my $sock = IO::Socket::INET->new(
        LocalAddr => '127.0.0.1',
        LocalPort => 0,
        Listen    => 1,
        Proto     => 'tcp'
    ) or croak "Cannot allocate loopback port: $ERRNO";
    my $port = $sock->sockport;
    close $sock or croak "Cannot close loopback socket: $ERRNO";
    return $port;
}

sub probe_url ( $url, $options = {} ) {
    if ( !( $url =~ m{\Ahttp://(?:127[.]0[.]0[.]1|localhost):\d+/}msx ) ) {
        croak 'Invalid local HTTP URL';
    }
    my $ua = HTTP::Tiny->new(
        timeout      => $options->{timeout} // REQUEST_TIMEOUT,
        max_redirect => 5,
        max_size     => 2 * KIB * KIB,
        http_proxy   => undef,
        https_proxy  => undef,
        proxy        => undef
    );
    my $response = $ua->get( $url, { headers => { Connection => 'close' } } );
    if ( !( $response->{status} == HTTP_OK ) ) {
        croak "endpoint returned HTTP $response->{status}: "
          . redact( $response->{reason} );
    }
    return ( $response->{url} // $url,
        $response->{headers}{'x-gpforum-cache'} );
}

sub metric ($value) {
    return
         defined($value)
      && !ref($value)
      && looks_like_number($value)
      && isfinite( 0 + $value )
      && $value >= 0;
}

sub parse_wrk ($output) {
    my @records = $output =~ /^GPFORUM_WRK[ ]([{][^\n]+[}])$/mgsx;
    if ( !( @records == 1 ) ) {
        croak 'wrk did not return one complete metrics record';
    }
    my $result = decode_json( $records[0] );
    for my $key (
        qw(completed http_errors transport_errors duration_seconds requests_per_second p50_ms p95_ms p99_ms)
      )
    {
        if ( !( metric( $result->{$key} ) ) ) {
            croak "invalid wrk metric $key";
        }
        $result->{$key} = 0 + $result->{$key};
    }
    if ( !( $result->{duration_seconds} > 0 && $result->{completed} > 0 ) ) {
        croak 'wrk completed no requests';
    }
    return $result;
}

sub parse_mojo ($output) {
    my $raw = decode_json($output);
    if ( !( exists $raw->{completed} ) ) {
        croak 'Mojo generator returned no measurements';
    }
    my $codes  = $raw->{status_codes} // {};
    my $result = {
        completed   => $raw->{completed},
        http_errors => sum(
            map { $codes->{$_} }
            grep {
                /\A[[:digit:]]+\z/msx
                  && ( $_ < HTTP_OK || $_ >= HTTP_ERROR_MIN )
              }
              keys $codes->%*
        ) // 0,
        transport_errors      => $codes->{error} // 0,
        duration_seconds      => $raw->{wall_seconds},
        requests_per_second   => $raw->{req_per_sec},
        p50_ms                => $raw->{p50_ms},
        p95_ms                => $raw->{p95_ms},
        p99_ms                => $raw->{p99_ms},
        concurrency_effective => $raw->{peak_inflight}
    };
    for my $key ( keys $result->%* ) {
        if ( !( metric( $result->{$key} ) ) ) {
            croak "invalid Mojo metric $key";
        }
        $result->{$key} = 0 + $result->{$key};
    }
    if ( !( $result->{completed} > 0 && $result->{duration_seconds} > 0 ) ) {
        croak 'Mojo completed no requests';
    }
    return $result;
}

sub wrk_version ( $diagnostics = undef ) {
    my $output = run_bounded(
        [ 'wrk', '--version' ],
        {
            timeout => VERSION_TIMEOUT,
            log     => defined($diagnostics)
            ? "$diagnostics/wrk-version.log"
            : undef,
            accepted_codes => [ 0, 1 ]
        }
    );
    if ( $output =~ /^(wrk[ ][[:digit:]]+(?:[.][[:digit:]]+)+[^\n]*)/msx ) {
        return $1;
    }
    if ( !( $output =~ /^wrk(?:[ \t]|$)/msx ) ) {
        croak 'wrk did not identify itself in its version output';
    }
    if ( which('dpkg-query') ) {
        my $package = _attempt(
            sub {
                run_bounded(
                    [
                        'dpkg-query', '--show', '--showformat=${Version}',
                        'wrk'
                    ],
                    {
                        timeout => VERSION_TIMEOUT,
                        log     => defined($diagnostics)
                        ? "$diagnostics/wrk-package-version.log"
                        : undef
                    }
                );
            }
        )->{value};
        if ( defined $package ) {
            $package =~ s/\A\s+|\s+\z//gmsx;
            if ( $package =~ /\A[[:digit:]][[:alnum:].+:~_-]*\z/msx ) {
                return
"wrk (distribution package $package; CLI upstream unspecified)";
            }
        }
    }
    return
'wrk (CLI upstream version unspecified; distribution package unavailable)';
}

sub _plan_cell ( $scenario, $concurrency, $workers ) {
    return {
        scenario    => $scenario,
        endpoint    => $SCENARIOS{$scenario},
        workers     => $workers,
        concurrency => $concurrency,
        cache_mode  => $scenario eq 'cache_miss' ? 'miss' : 'normal',
    };
}

sub _worker_plan ( $mode, $levels, $cpus ) {
    if ( $mode eq 'pr' ) { return []; }
    my @workers = (WORKERS_MEDIUM);
    if ( $mode eq 'deep' && $cpus >= MIN_CPU_EXPERIMENTAL ) {
        push @workers, WORKERS_LARGE;
    }
    my $higher = $mode eq 'deep' ? CONCURRENCY_EXTENDED : CONCURRENCY_HIGH;
    my @levels = grep { $_ == CONCURRENCY_MEDIUM || $_ == $higher } $levels->@*;
    my @cells;
    for my $workers (@workers) {
        for my $scenario (qw(thread search cache_hit)) {
            push @cells, map { _plan_cell( $scenario, $_, $workers ) } @levels;
        }
    }
    return \@cells;
}

sub plan ( $mode, $levels = undef, $cpus = undef ) {
    if ( !$DEFAULTS{$mode} ) { croak 'Unsupported HTTP mode'; }
    $levels //= $DEFAULTS{$mode}{concurrency};
    $cpus   //= cpu_count();
    my %high_load = map { $_ => 1 } qw(health_live thread search cache_hit);
    my @cells;
    for my $scenario (@ORDER) {
        my @loads = grep { $_ <= CONCURRENCY_MEDIUM || $high_load{$scenario} }
          $levels->@*;
        push @cells, map { _plan_cell( $scenario, $_, 2 ) } @loads;
    }
    push @cells, _worker_plan( $mode, $levels, $cpus )->@*;
    return \@cells;
}

sub process_snapshot ($master) {
    my $result = _attempt(
        sub {
            run_bounded( [ 'ps', '-axo', 'pid=,ppid=,pcpu=,rss=' ],
                { timeout => 2 } );
        }
    )->{value};
    if ( !( defined $result ) ) {
        return {
            cpu_percent    => undef,
            rss_bytes      => undef,
            workers_actual => undef,
            worker_pids    => []
        };
    }
    my ( @children, $cpu, $rss );
    $cpu = $rss = 0;
    for my $line ( split /\n/msx, $result ) {
        my ( $pid, $ppid, $pcpu, $resident ) =
          $line =~ /\A\s*(\d+)\s+(\d+)\s+([\d.]+)\s+(\d+)\s*\z/msx;
        if ( !defined $pid )                            { next; }
        if ( !( $pid == $master || $ppid == $master ) ) { next; }
        if ( $ppid == $master ) { push @children, 0 + $pid; }
        $cpu += $pcpu;
        $rss += $resident * KIB;
    }
    return {
        cpu_percent    => $cpu,
        rss_bytes      => $rss,
        workers_actual => scalar @children,
        worker_pids    => \@children
    };
}

sub linux_cpu_ticks ($master) {
    if ( !( $OS eq 'Linux' ) ) { return undef; }
    my $snapshot = process_snapshot($master);
    my %ticks;
    my $ok = _attempt(
        sub {
            for my $pid ( $master, @{ $snapshot->{worker_pids} } ) {
                my $stat = bytes("/proc/$pid/stat");
                $stat =~ s/\A.*[)]\s*//smx;
                my @fields = split /\s+/msx, $stat;
                $ticks{$pid} =
                  $fields[CPU_USER_FIELD] + $fields[CPU_SYSTEM_FIELD];
            }
            return 1;
        }
    );
    return $ok->{ok} ? \%ticks : undef;
}

sub resources_between ( $before, $after, $duration, $snapshot ) {
    my $cpu    = $snapshot->{cpu_percent};
    my $source = 'ps lifetime average; indicative';
    if (   $before
        && $after
        && join( q{,}, sort keys $before->%* ) eq
        join( q{,}, sort keys $after->%* )
        && $duration > 0 )
    {
        $cpu =
          CPU_PERCENT_SCALE *
          ( ( sum( values $after->%* ) // 0 ) -
              ( sum( values $before->%* ) // 0 ) ) /
          sysconf(_SC_CLK_TCK) /
          $duration;
        $source =
'Linux /proc manager+workers CPU time delta / generator wall duration';
    }
    return (
        {
            cpu_percent => defined($cpu) ? 0 + sprintf( '%.3f', $cpu ) : undef,
            rss_bytes   => $snapshot->{rss_bytes}
        },
        $source
    );
}

sub native_backend_flags {
    return EV_BACKEND_EPOLL  if $OS eq 'Linux';
    return EV_BACKEND_KQUEUE if $OS eq 'Darwin' || $OS eq 'FreeBSD';

    croak "No supported native event backend for $OS";
}

sub probe_reactor ( $reactor, $diagnostics, $timeout ) {
    croak 'Native EV reactor required' if $reactor ne 'EV';
    my %env = %ENV;
    $env{MOJO_REACTOR} = "Mojo::Reactor::$reactor";
    $env{LIBEV_FLAGS}  = native_backend_flags();
    my $code =
q{my $class=ref Mojo::IOLoop->singleton->reactor; print $class; print ':' . EV::backend() if $class eq 'Mojo::Reactor::EV'};
    my $output = run_bounded(
        [
            'script/gpforum-carton', 'exec', 'perl', '-MMojo::IOLoop', '-e',
            $code
        ],
        {
            timeout => $timeout,
            log     => "$diagnostics/probe-$reactor.log",
            env     => \%env
        }
    );
    $output =~ s/\s+\z//msx;
    return $output eq "Mojo::Reactor::$reactor:" . native_backend_flags();
}

sub prepare_dataset ( $mode, $diagnostics, $timeout ) {
    my $deadline = monotonic() + $timeout;
    my @options =
      $mode eq 'pr'
      ? qw(--profile small)
      : map { ( "--$_", $SEED_PROFILES{$mode}{$_} ) }
      qw(users categories threads posts-per-thread);
    my $seed = decode_json(
        run_bounded(
            [ 'bin/gpforum', 'performance-seed', '--json', @options ],
            {
                timeout => $deadline - monotonic(),
                log     => "$diagnostics/seed.log"
            }
        )
    );
    run_bounded(
        [ 'bin/gpforum', 'budgets', '--sync' ],
        {
            timeout => min( MAX_DURATION, $deadline - monotonic() ),
            log     => "$diagnostics/query-budget-sync.log"
        }
    );
    my $code =
q{use GPForum::Config; use GPForum::Schema; use JSON::MaybeXS qw(encode_json);my $schema=GPForum::Schema->connect_from_config(GPForum::Config->from_environment);my $db=$schema->storage->dbh;$db->do('ANALYZE');my %settings;for my $name (@ARGV){$settings{$name}=$db->selectrow_array('SELECT current_setting(?)',undef,$name)}print encode_json({postgres=>$db->selectrow_array('SHOW server_version'),database_settings=>\%settings});};
    my $pg = decode_json(
        run_bounded(
            [
                'script/gpforum-carton',
                'exec',
                'perl',
                '-Ilib',
                '-e',
                $code,
                qw(shared_buffers work_mem effective_cache_size max_connections random_page_cost jit synchronous_commit effective_io_concurrency)
            ],
            {
                timeout => min( DB_SETTINGS_TIMEOUT, $deadline - monotonic() ),
                log     => "$diagnostics/postgres-metadata.log"
            }
        )
    );
    my $dataset = {
        profile               => $seed->{profile},
        counts                => $seed->{dataset},
        seed_version          => 'SeedDataset-v1',
        mode                  => $mode,
        implementation_sha256 => {
            map { $_ => sha256_hex( bytes( root_dir() . "/$_" ) ) }
              qw(lib/GPForum/Benchmark/SeedDataset.pm lib/GPForum/Command/PerformanceSeed.pm)
        }
    };
    $dataset->{signature} =
      sha256_hex( JSON::PP->new->canonical->encode($dataset) );
    return ( $dataset, $pg );
}

sub runtime_environment ( $pg, $dataset, $args ) {
    my %env = %ENV;
    delete @env{qw(MOJO_REACTOR LIBEV_FLAGS)};
    my $code =
q{use v5.40;my $reactor=ref Mojo::IOLoop->singleton->reactor;my $version;try {require EV;$version="$EV::VERSION"}catch($error){};print encode_json({perl=>"$^V",mojolicious=>$Mojolicious::VERSION,ev=>$version,default_reactor=>$reactor,default_ev_backend=>$reactor eq 'Mojo::Reactor::EV'?EV::backend():undef})};
    my $versions = decode_json(
        run_bounded(
            [
                'script/gpforum-carton', 'exec', 'perl', '-MMojolicious',
                '-MMojo::IOLoop', '-MJSON::MaybeXS=encode_json', '-e', $code
            ],
            { timeout => REACTOR_TIMEOUT, env => \%env }
        )
    );
    my $configuration = {
        default_reactor       => delete( $versions->{default_reactor} ),
        default_ev_backend    => delete( $versions->{default_ev_backend} ),
        http_duration_seconds => $args->{duration},
        http_repetitions      => $args->{repetitions},
        http_concurrency      => $args->{levels}
          // $DEFAULTS{ $args->{mode} }{concurrency},
        cache =>
          'local-only; 4096 entries; SSR TTL 3600s; miss harness TTL -1s',
        cache_miss_policy =>
          'SSR store expires immediately; category model cache remains warm',
        read_rate_limit   => RATE_LIMIT,
        database_settings => $pg->{database_settings},
        backlog => $args->{allow_5000} ? STRESS_BACKLOG : DEFAULT_BACKLOG,
        clients_per_worker => $args->{allow_5000}
        ? CONCURRENCY_STRESS
        : DEFAULT_CLIENTS,
        http_scenarios => $args->{scenarios} // [@ORDER],
        fixed_workers  => $args->{workers},
        mojo_requests  => 'at least 100 total; at least 10 per client'
    };
    $versions->{postgres} = $pg->{postgres};
    $versions->{wrk}      = undef;
    return {
        versions      => $versions,
        dataset       => $dataset,
        configuration => $configuration
    };
}
sub canonical_path ($url) { $url =~ s{\Ahttps?://[^/]+}{}msx; return $url }

sub wrk_measure ( $server, $cell, $args, $log, $deadline ) {
    my ($canonical) = probe_url( $server->{base} . $cell->{endpoint} );
    my $expected =
        $cell->{cache_mode} eq 'miss'    ? 'miss'
      : $cell->{scenario} eq 'cache_hit' ? 'hit'
      :                                    undef;
    my $warmed = 0;
    for ( 1 .. MOJO_MIN_REQUESTS ) {
        if ( monotonic() + $args->{duration} + GENERATOR_MARGIN > $deadline ) {
            croak 'suite deadline during cache warmup';
        }
        my ( undef, $state ) = probe_url($canonical);
        $warmed =
          !$expected || ( $state // q{} ) eq $expected ? $warmed + 1 : 0;
        if ( $warmed >=
            max( MIN_WARMUP, $server->{workers} * WARMUP_PER_WORKER ) )
        {
            last;
        }
    }
    if (   $expected
        && $warmed < max( MIN_WARMUP, $server->{workers} * WARMUP_PER_WORKER ) )
    {
        croak "cache policy $expected could not be verified";
    }
    my $telemetry = $server->telemetry;
    my $before    = linux_cpu_ticks( $server->{master} );
    my $started   = monotonic();
    my $raw       = run_bounded(
        [
            'wrk',       '--latency',
            '-t',        min( 2, $cell->{concurrency} ),
            '-c',        $cell->{concurrency},
            '-d',        "$args->{duration}s",
            '--timeout', '3s',
            '-s',        root_dir() . '/benchmarks/wrk-metrics.lua',
            $canonical
        ],
        {
            timeout =>
              min( $args->{duration} + GENERATOR_MARGIN, $deadline - $started ),
            log => $log
        }
    );
    my $elapsed  = monotonic() - $started;
    my $after    = linux_cpu_ticks( $server->{master} );
    my $snapshot = process_snapshot( $server->{master} );
    my $metrics  = parse_wrk($raw);
    $metrics->{concurrency_effective} = undef;
    my ( $resources, $source ) =
      resources_between( $before, $after, $elapsed, $snapshot );
    $metrics->@{ keys $resources->%* } = values $resources->%*;
    my ( $cache, $validation );
    try {
        my ( undef, $observed ) = probe_url($canonical);
        $cache = $observed;
        $server->telemetry;
        if ( $expected && ( $cache // q{} ) ne $expected ) {
            croak 'cache policy changed after measurement';
        }
    }
    catch ($error) { $validation = redact($error) };
    return (
        $metrics,
        {
            canonical_endpoint => canonical_path($canonical),
            cache_observed     => $cache,
            workers_actual     => $snapshot->{workers_actual},
            worker_telemetry   => $telemetry,
            cpu_source         => $source,
            rss_source => 'ps manager+workers resident memory at end; not peak',
            validation_error       => $validation,
            generator_wall_seconds => $elapsed
        }
    );
}

sub mojo_measure ( $server, $cell, $args, $log, $deadline ) {
    my ($canonical) = probe_url( $server->{base} . $cell->{endpoint} );
    my $expected =
        $cell->{cache_mode} eq 'miss'    ? 'miss'
      : $cell->{scenario} eq 'cache_hit' ? 'hit'
      :                                    undef;
    my $observed;
    for ( 1 .. $server->{workers} * MIN_WARMUP ) {
        ( undef, $observed ) = probe_url($canonical);
    }
    if ( $expected && ( $observed // q{} ) ne $expected ) {
        croak "cache policy $expected could not be verified";
    }
    my $route   = canonical_path($canonical);
    my $before  = linux_cpu_ticks( $server->{master} );
    my $started = monotonic();
    my %env     = (
        %ENV,
        MOJO_REACTOR => 'Mojo::Reactor::EV',
        LIBEV_FLAGS  => native_backend_flags(),
    );
    my $requests = max(
        MOJO_MIN_PER_CLIENT,
        int(
            ( MOJO_MIN_REQUESTS + $cell->{concurrency} - 1 ) /
              $cell->{concurrency}
        )
    );
    my $raw = run_bounded(
        [
            qw(bin/gpforum stress-load --profile smoke --json),
            '--base-url',
            $server->{base},
            '--route',
            $route,
            '--concurrency',
            $cell->{concurrency},
            '--requests-per-client',
            $requests,
            '--request-timeout',
            REQUEST_TIMEOUT,
        ],
        {
            timeout => min( MOJO_TIMEOUT, $deadline - $started ),
            log     => $log,
            env     => \%env
        }
    );
    my $elapsed  = monotonic() - $started;
    my $metrics  = parse_mojo($raw);
    my $snapshot = process_snapshot( $server->{master} );
    my ( $resources, $source ) =
      resources_between( $before, linux_cpu_ticks( $server->{master} ),
        $elapsed, $snapshot );
    $metrics->@{ keys $resources->%* } = values $resources->%*;
    return (
        $metrics,
        {
            workers_actual => $snapshot->{workers_actual},
            cpu_source     => $source,
            rss_source => 'ps manager+workers resident memory at end; not peak',
            worker_telemetry   => $server->telemetry,
            canonical_endpoint => $route,
            capacity_class     =>
              'indicative fixed-request Mojo comparison; not sustained capacity'
        }
    );
}

sub suite_status ( $output, $status, $reason, $skips ) {
    my $path = "$output/suite-status.json";
    my $data = -f $path ? read_json($path) : {};
    $data->{http} = { status => $status, reason => $reason, skipped => $skips };
    write_json( $path, $data );
    return undef;
}

sub _parse_options (@argv) {
    require Getopt::Long;
    my %args = ( mode => 'pr', repetitions => 3, generator => 'auto' );
    Getopt::Long::Configure( 'no_auto_abbrev', 'no_ignore_case' );
    my $ok = Getopt::Long::GetOptionsFromArray(
        \@argv,
        'output=s'             => \$args{output},
        'mode=s'               => \$args{mode},
        'duration=i'           => \$args{duration},
        'repetitions=i'        => \$args{repetitions},
        'deadline=i'           => \$args{deadline},
        'concurrency=s'        => \$args{concurrency},
        'allow-1000!'          => \$args{allow_1000},
        'allow-5000!'          => \$args{allow_5000},
        'scenario=s@'          => \$args{scenarios},
        'workers=i'            => \$args{workers},
        'disposable-database!' => \$args{disposable_database},
        'generator=s'          => \$args{generator},
        'dry-run!'             => \$args{dry_run},
        'help'                 => \$args{help},
    );
    if ( $args{help} ) { return \%args; }
    my %generators = map { $_ => 1 } qw(auto wrk mojo);
    if (  !$ok
        || @argv
        || !$args{output}
        || !$DEFAULTS{ $args{mode} }
        || !$generators{ $args{generator} } )
    {
        croak 'Invalid HTTP CLI options';
    }
    $args{duration} //= $DEFAULTS{ $args{mode} }{duration};
    $args{deadline} //= $DEFAULTS{ $args{mode} }{deadline};
    _validate_options( \%args );
    return \%args;
}

sub _validate_options ($args) {
    _validate_workers($args);
    if ( any { !exists $SCENARIOS{$_} } @{ $args->{scenarios} // [] } ) {
        croak 'unknown HTTP scenario';
    }
    if (   $args->{duration} < 1
        || $args->{duration} > MAX_DURATION
        || $args->{repetitions} < 1
        || $args->{repetitions} > MAX_REPETITIONS
        || $args->{deadline} < MIN_DEADLINE
        || $args->{deadline} > MAX_DEADLINE )
    {
        croak 'duration 1..30, repetitions 1..5 and deadline 30..1800 required';
    }
    return _connection_levels($args);
}

sub _validate_workers ($args) {
    return if !defined $args->{workers};
    croak 'workers 1..8 and mode pr required for a fixed worker comparison'
      if $args->{workers} < 1
      || $args->{workers} > WORKERS_LARGE
      || $args->{mode} ne 'pr';
    return;
}

sub _connection_levels ($args) {
    if ( !defined $args->{concurrency} ) { return undef; }
    if ( $args->{concurrency} !~ /\A\d+(?:,\d+)*\z/msx ) {
        croak 'invalid concurrency list';
    }
    my %seen;
    my @levels = sort { $a <=> $b } grep { !$seen{$_}++ } split /,/msx,
      $args->{concurrency};
    my $maximum =
        $args->{allow_5000} ? CONCURRENCY_STRESS
      : $args->{allow_1000} ? CONCURRENCY_EXPERIMENTAL
      :                       CONCURRENCY_MAX;
    if ( any { $_ < 1 || $_ > $maximum } @levels ) {
        croak
'concurrency must be 1..500 (1000 requires --allow-1000; 5000 requires --allow-5000)';
    }
    $args->{levels} = \@levels;
    return undef;
}

sub _planned_skips ($args) {
    my @skips = (
        {
            scenario => 'authenticated',
            reason   =>
              'read-only anonymous suite; safe durable auth fixture unavailable'
        },
        {
            scenario => 'full_cartesian_matrix',
            reason   =>
'bounded targeted plan: every endpoint at low load; high concurrency on health/thread/search/cache_hit; extra workers only thread/search/cache_hit'
        },
    );
    if ( $args->{mode} ne 'deep' ) {
        push @skips,
          {
            scenario => 'concurrency_250_500',
            reason   => 'bounded PR/main modes; use deep sweep'
          };
    }
    if ( $args->{mode} eq 'pr' && !defined $args->{workers} ) {
        push @skips,
          {
            scenario => 'workers_4_8',
            reason   =>
              'PR smoke fixes two workers; worker scaling runs on main/deep'
          };
    }
    if ( $args->{mode} eq 'main' ) {
        push @skips,
          {
            scenario => 'workers_8',
            reason   => 'eight-worker sweep reserved for capable deep runners'
          };
    }
    if ( $args->{mode} eq 'deep' && cpu_count() < MIN_CPU_EXPERIMENTAL ) {
        push @skips,
          {
            scenario => 'workers_8',
            reason   => 'runner has fewer than four CPUs'
          };
    }
    return \@skips;
}

sub _experimental_plan ( $args, $cells, $skips ) {
    if ( $args->{allow_5000} ) {
        croak '5000 connections require the independent wrk generator'
          if $args->{generator} ne 'wrk';
        croak '5000 connections require at least 16384 file descriptors'
          if ( nofile_soft() // 0 ) < MIN_FD_STRESS;
        return $cells;
    }
    if ( !$args->{allow_1000} ) {
        push $skips->@*,
          {
            scenario => 'concurrency_1000',
            reason   => 'requires explicit --allow-1000 and capable runner'
          };
        return $cells;
    }
    if (   cpu_count() < MIN_CPU_EXPERIMENTAL
        || memory_bytes() < MIN_GIB_EXPERIMENTAL * GIB
        || ( nofile_soft() // 0 ) < MIN_FD_EXPERIMENTAL )
    {
        push $skips->@*,
          {
            scenario => 'concurrency_1000',
            reason   =>
              'requires Linux >=4 CPUs, 8GiB memory, 4096 file descriptors'
          };
        return [ grep { $_->{concurrency} != CONCURRENCY_EXPERIMENTAL }
              $cells->@* ];
    }
    return $cells;
}

sub _database_is_disposable ($args) {
    my ($name) =
      ( $ENV{GPFORUM_DATABASE_DSN} // q{} ) =~ /(?:dbi:Pg:|;)dbname=([^;]+)/msx;
    return
         $args->{disposable_database}
      && $name
      && ( $name =~ /\Agpforum_perf_/msx || $name eq 'gpforum_test' );
}

sub _dry_run ($state) {
    my $args = $state->{args};
    suite_status(
        $args->{output},
        'skipped',
        'dry-run; no measurements executed',
        [
            $state->{skips}->@*,
            {
                scenario => 'http_plan',
                reason   => 'dry-run',
                plan     => $state->{cells}
            }
        ]
    );
    print encode_json( { status => 'skipped', plan => $state->{cells} } ) . "\n"
      or croak "Cannot write plan: $ERRNO";
    return 0;
}

sub _wrk_environment ( $state, $environment ) {
    if ( !$state->{available} ) { return undef; }
    my $version_probe =
      _attempt( sub { wrk_version( $state->{diagnostics} ) } );
    my $version = $version_probe->{value};
    if ( !$version_probe->{ok} ) {
        if ( $state->{generator} eq 'wrk' ) { croak $version_probe->{error}; }
        push $state->{skips}->@*,
          {
            scenario => 'wrk_version',
            reason   => 'unused optional wrk probe failed: '
              . redact( $version_probe->{error} )
          };
    }
    $environment->{versions}{wrk} = $version;
    if ( $version && $version =~ /CLI[ ]upstream/msx ) {
        push $state->{skips}->@*,
          { scenario => 'wrk_upstream_version', reason => $version };
        my $binary = which('wrk');
        if ( !$binary || !-f $binary ) {
            croak 'cannot fingerprint wrk with unspecified upstream version';
        }
        $environment->{configuration}{wrk_binary_sha256} =
          sha256_hex( bytes($binary) );
    }
    $environment->{configuration}{wrk_upstream_version_verified} =
      $version && $version =~ /\Awrk[ ][[:digit:]]+(?:[.][[:digit:]]+)+/msx
      ? JSON::PP::true
      : JSON::PP::false;
    write_json( "$state->{args}{output}/http-environment.json", $environment );
    return undef;
}

sub _reactors ($state) {
    croak 'Required native EV reactor/backend unavailable'
      if !probe_reactor( 'EV', $state->{diagnostics}, REACTOR_TIMEOUT );

    return ['EV'];
}

sub _checkpoint ($state) {
    if ( !$state->{measurements}->@* ) { return undef; }
    write_json(
        "$state->{args}{output}/http.json",
        {
            schema_version => 1,
            kind           => 'http',
            status         => 'partial',
            measurements   => $state->{measurements},
            limitations    => [],
        }
    );
    return undef;
}

sub _mark_errors ( $state, $row, $context ) {
    my $metrics = $row->{metrics};
    my $errors  = $metrics->{http_errors} + $metrics->{transport_errors};
    if ($errors) {
        $row->{status}       = 'failed';
        $row->{failure_kind} = 'http_or_transport_errors';
        push $state->{failures}->@*, "$context returned errors";
    }
    if ( $row->{validation_error} ) {
        $row->{status}       = 'failed';
        $row->{failure_kind} = 'infrastructure_or_harness';
        push $state->{failures}->@*, $row->{validation_error};
    }
    return $errors;
}

sub _cell ( $state, $group, $cell ) {
    my $server = $group->{server};
    my $args   = $state->{args};
    my $stop   = join q{:}, $cell->{scenario}, $group->{reactor},
      $group->{workers};
    if ( $cell->{concurrency} > ( $state->{saturation}{$stop} // UNBOUNDED_CAP )
        || $state->{deadline} - monotonic() <
        $args->{duration} + GENERATOR_MARGIN )
    {
        push $state->{skips}->@*,
          {
            $cell->%*,
            reactor    => $server->{reactor},
            repetition => $group->{repetition},
            reason     => 'stopped after errors/saturation or suite deadline'
          };
        return undef;
    }
    my $row = {
        $cell->%*,
        generator        => $state->{generator},
        reactor          => $server->{reactor},
        repetition       => $group->{repetition},
        status           => 'ok',
        evidence_quality => $state->{generator} eq 'mojo'
        ? 'indicative'
        : 'measured-comparative',
    };
    my $success = _attempt(
        sub {
            my $log = "$state->{diagnostics}/measure-$state->{server_index}-"
              . $group->{index}++ . '.log';
            my ( $metrics, $details ) =
              $state->{generator} eq 'wrk'
              ? wrk_measure( $server, $cell, $args, $log, $state->{deadline} )
              : mojo_measure( $server, $cell, $args, $log, $state->{deadline} );
            $row->@{ keys $details->%* } = values $details->%*;
            $row->{metrics} = $metrics;
            my $context =
"$cell->{scenario} $group->{reactor}/$group->{workers}/$cell->{concurrency}";
            my $errors = _mark_errors( $state, $row, $context );
            if (
                $errors > max( 1,
                    ( $metrics->{completed} + $metrics->{transport_errors} ) *
                      ERROR_STOP_FRACTION )
                || $metrics->{p95_ms} > LATENCY_STOP_MS
              )
            {
                $state->{saturation}{$stop} = min( $cell->{concurrency},
                    $state->{saturation}{$stop} // UNBOUNDED_CAP );
            }
            push $state->{measurements}->@*, $row;
            _checkpoint($state);
            printf "http %s %s workers=%d c=%d rep=%d %s rps=%.2f\n",
              $cell->{scenario}, $group->{reactor}, $group->{workers},
              $cell->{concurrency},
              $group->{repetition}, $row->{status},
              $metrics->{requests_per_second}
              or croak "Cannot write progress: $ERRNO";
            return 1;
        }
    );
    if ( !$success->{ok} ) {
        my $reason = redact( $success->{error} );
        push $state->{failures}->@*, $reason;
        push $state->{skips}->@*,
          {
            $row->%*,
            status       => 'failed',
            reason       => $reason,
            failure_kind => 'infrastructure_or_harness'
          };
    }
    return undef;
}

sub _mojo_comparisons ( $state, $group ) {
    if (   $state->{generator} ne 'wrk'
        || $group->{reactor} ne 'EV'
        || $group->{workers} != 2
        || $group->{cache_mode} ne 'normal' )
    {
        return undef;
    }
    for my $scenario (qw(health_live thread)) {
        if ( $state->{deadline} - monotonic() < MOJO_MARGIN ) {
            push $state->{skips}->@*,
              { scenario => "mojo_$scenario", reason => 'suite deadline' };
            next;
        }
        my $cell = _plan_cell( $scenario, CONCURRENCY_SMALL, 2 );
        my ( $metrics, $details ) =
          mojo_measure( $group->{server}, $cell, $state->{args},
            "$state->{diagnostics}/mojo-$state->{server_index}-$scenario.log",
            $state->{deadline} );
        my $row = {
            $cell->%*, $details->%*,
            generator        => 'mojo',
            reactor          => $group->{server}{reactor},
            repetition       => $group->{repetition},
            status           => 'ok',
            evidence_quality => 'indicative',
            metrics          => $metrics,
        };
        _mark_errors( $state, $row, "Mojo comparison $scenario" );
        push $state->{measurements}->@*, $row;
        _checkpoint($state);
    }
    return undef;
}

sub _skip_group ( $state, $group, $reason, $failed = 0 ) {
    push $state->{skips}->@*, map {
        +{
            $_->%*,
            reactor    => "Mojo::Reactor::$group->{reactor}",
            repetition => $group->{repetition},
            reason     => $reason,
            (
                $failed
                ? (
                    status       => 'failed',
                    failure_kind => 'infrastructure_or_harness'
                  )
                : ()
            ),
        }
    } $group->{cells}->@*;
    return undef;
}

sub _group ( $state, $group ) {
    if ( $state->{deadline} - monotonic() <
        $state->{args}{duration} + STARTUP_MARGIN )
    {
        _skip_group( $state, $group, 'suite wall-clock deadline' );
        return undef;
    }
    my $success = _attempt(
        sub {
            $group->{server} = GPForum::Performance::Server->new(
                {
                    output     => $state->{args}{output},
                    reactor    => $group->{reactor},
                    workers    => $group->{workers},
                    cache_mode => $group->{cache_mode},
                    index      => ++$state->{server_index},
                    deadline   => $state->{deadline},
                    clients => $state->{args}{allow_5000} ? CONCURRENCY_STRESS
                    : DEFAULT_CLIENTS,
                    backlog => $state->{args}{allow_5000} ? STRESS_BACKLOG
                    : DEFAULT_BACKLOG,
                }
            );
            $group->{index} = 0;
            for my $cell ( $group->{cells}->@* ) {
                _cell( $state, $group, $cell );
            }
            _mojo_comparisons( $state, $group );
            return 1;
        }
    );
    if ( !$success->{ok} ) {
        my $reason = redact( $success->{error} );
        push $state->{failures}->@*, $reason;
        _skip_group( $state, $group, $reason, 1 );
    }
    if ( $group->{server} ) { $group->{server}->close; }
    return undef;
}

sub _matrix ($state) {
    require GPForum::Performance::Server;
    my $reactors = _reactors($state);
    my %groups;
    for my $cell ( $state->{cells}->@* ) {
        my $key = join q{:}, $cell->{workers}, $cell->{cache_mode};
        push $groups{$key}->@*, $cell;
    }
    local $OUTPUT_AUTOFLUSH = 1;
    for my $repetition ( 1 .. $state->{args}{repetitions} ) {
        my @reactors = $repetition % 2 ? $reactors->@* : reverse $reactors->@*;
        my @keys     = sort keys %groups;
        if ( $repetition % 2 == 0 ) { @keys = reverse @keys; }
        for my $reactor (@reactors) {
            for my $key (@keys) {
                my ( $workers, $cache_mode ) = split /:/msx, $key;
                _group(
                    $state,
                    {
                        workers    => $workers,
                        cache_mode => $cache_mode,
                        reactor    => $reactor,
                        repetition => $repetition,
                        cells      => $groups{$key},
                    }
                );
            }
        }
    }
    return undef;
}

sub _finish ($state) {
    my $incomplete = $state->{failures}->@*
      || any { $_->{reason} =~ /deadline/msx } $state->{skips}->@*;
    my $status =
      !$state->{measurements}->@* ? 'failed' : $incomplete ? 'partial' : 'ok';
    my @limitations = (
'Shared runner and load generator share the host; values are comparative evidence, not production capacity.',
'wrk uses closed-loop fixed connections and corrected latency histograms; in-flight concurrency is not measured.',
'RSS is end-of-sample manager+workers residency, not peak; PostgreSQL and generator resources are separate.',
'Cache hits/misses verified by probes; warmed worker-local SSR cache; cache miss uses harness-only expiry policy.',
'Only anonymous GETs; migrations, seed and rate-limit accounting write only the dedicated disposable database.',
    );
    if ( $state->{generator} ne 'wrk' ) {
        push @limitations,
'Independent generator unavailable: fixed-request Mojo rows are indicative, not measured sustained capacity.';
    }
    if ( $state->{measurements}->@* ) {
        write_json(
            "$state->{args}{output}/http.json",
            {
                schema_version => 1,
                kind           => 'http',
                status         => $status,
                measurements   => $state->{measurements},
                limitations    => \@limitations,
            }
        );
    }
    my @short = $state->{failures}
      ->@[ 0 .. min( FAILURE_SUMMARY_MAX - 1, $state->{failures}->$#* ) ];
    suite_status(
        $state->{args}{output},
        $status,
        $state->{failures}->@*
        ? join( '; ', @short )
        : 'completed planned HTTP measurements',
        $state->{skips}
    );
    return $state->{failures}->@* || !$state->{measurements}->@* ? 1 : 0;
}

sub _selected_plan ( $args, $skips ) {
    my $cells =
      _experimental_plan( $args, plan( $args->{mode}, $args->{levels} ),
        $skips );
    if ( $args->{scenarios} ) {
        my %selected = map { $_ => 1 } $args->{scenarios}->@*;
        $cells = [ grep { $selected{ $_->{scenario} } } $cells->@* ];
    }
    if ( defined $args->{workers} ) {
        for my $cell ( $cells->@* ) {
            $cell->{workers} = $args->{workers};
        }
    }
    return $cells;
}

sub main (@argv) {
    my $args = _parse_options(@argv);
    if ( $args->{help} ) {
        print
"Usage: script/performance-http --output DIR --mode pr|main|deep [--generator wrk|mojo|auto] --disposable-database [--duration 1..30 --repetitions 1..5 --deadline 30..1800 --concurrency 1,10,... --allow-1000 --allow-5000 --scenario NAME --workers 1..8 (pr only) --dry-run]\n"
          or croak "Cannot write help: $ERRNO";
        return 0;
    }
    $args->{output} = File::Spec->rel2abs( $args->{output} );
    make_path( $args->{output} );
    my $state = {
        args         => $args,
        skips        => _planned_skips($args),
        measurements => [],
        failures     => [],
        saturation   => {},
        server_index => 0,
    };
    $state->{cells} = _selected_plan( $args, $state->{skips} );
    if ( $args->{dry_run} ) { return _dry_run($state); }
    if ( !_database_is_disposable($args) ) {
        suite_status(
            $args->{output},
            'failed',
'requires --disposable-database and dedicated gpforum_perf_* / gpforum_test DB',
            $state->{skips}
        );
        return 2;
    }
    $state->{available} = !!which('wrk');
    $state->{generator} =
      $args->{generator} eq 'auto'
      ? ( $state->{available} ? 'wrk' : 'mojo' )
      : $args->{generator};
    if ( $state->{generator} eq 'wrk' && !$state->{available} ) {
        suite_status( $args->{output}, 'failed',
            'independent wrk generator unavailable',
            $state->{skips} );
        return 1;
    }
    if ( $state->{generator} ne 'wrk' ) {
        push $state->{skips}->@*,
          {
            scenario => 'independent_wrk',
            reason   =>
              'wrk unavailable or explicitly disabled; Mojo evidence indicative'
          };
    }
    $state->{deadline}    = monotonic() + $args->{deadline};
    $state->{diagnostics} = "$args->{output}/diagnostics";
    make_path( $state->{diagnostics} );
    my $success = _attempt(
        sub {
            my ( $dataset, $pg ) =
              prepare_dataset( $args->{mode}, $state->{diagnostics},
                $state->{deadline} - monotonic() );
            my $environment = runtime_environment( $pg, $dataset, $args );
            write_json( "$args->{output}/http-environment.json", $environment );
            _wrk_environment( $state, $environment );
            _matrix($state);
            return 1;
        }
    );
    if ( !$success->{ok} ) {
        push $state->{failures}->@*, redact( $success->{error} );
    }
    return _finish($state);
}
1;
