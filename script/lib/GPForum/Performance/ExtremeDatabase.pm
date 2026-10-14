# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Performance::ExtremeDatabase;

use v5.40;
use Carp        qw(croak);
use Digest::SHA qw(sha256_hex);
use English     qw(-no_match_vars);
use Exporter    qw(import);
use File::Path  qw(make_path);
use File::Spec;
use JSON::PP;
use Scalar::Util qw(blessed looks_like_number);
use Time::HiRes  qw(alarm);
use GPForum::Performance::Support
  qw(root_dir read_json redact monotonic run_bounded);

our $VERSION   = '0.001';
our @EXPORT_OK = qw(guard prepare sample);

# Core constants keep this module loadable before Carton installs dependencies.
use constant {    ## no critic (ValuesAndExpressions::ProhibitConstantPragma)
    FULL_USERS          => 80,
    FULL_CATEGORIES     => 8,
    FULL_THREADS        => 800,
    FULL_POSTS          => 120,
    REDUCED_USERS       => 25,
    REDUCED_THREADS     => 240,
    REDUCED_POSTS       => 20,
    FULL_TIMEOUT        => 150,
    FALLBACK_RESERVE    => 60,
    FINAL_RESERVE       => 20,
    METADATA_TIMEOUT    => 15,
    SYNC_TIMEOUT        => 5,
    SYNC_RESERVE        => 12,
    MILLISECONDS        => 1_000,
    MAX_NAME            => 63,
    MAX_PORT            => 65_535,
    MAX_CONNECT         => 10,
    CPU_LIMIT           => 85,
    CONNECTION_LIMIT    => 0.9,
    MIN_CPU_SPAN        => 1,
    KIBIBYTE            => 1_024,
    PERCENT             => 100,
    CPU_USER_FIELD      => 11,
    CPU_SYSTEM_FIELD    => 12,
    PROCESS_START_FIELD => 19,
    MIN_STAT_FIELDS     => 20,
};
my %PROFILES = (
    full => {
        users            => FULL_USERS,
        categories       => FULL_CATEGORIES,
        threads          => FULL_THREADS,
        posts_per_thread => FULL_POSTS
    },
    reduced => {
        users            => REDUCED_USERS,
        categories       => FULL_CATEGORIES,
        threads          => REDUCED_THREADS,
        posts_per_thread => REDUCED_POSTS
    },
);
my @SETTINGS =
  qw(shared_buffers work_mem effective_cache_size max_connections random_page_cost jit synchronous_commit effective_io_concurrency);
my @SOURCES =
  qw(lib/GPForum/Benchmark/SeedDataset.pm lib/GPForum/Command/PerformanceSeed.pm);
my ( $previous_processes, $previous_backlog );

sub guard {
    croak 'Explicit extreme disposable-database acknowledgement is required'
      if ( $ENV{GPFORUM_EXTREME_DISPOSABLE_DATABASE} // q{} ) ne '1';
    my $dsn = $ENV{GPFORUM_DATABASE_DSN} // q{};
    croak 'An explicit PostgreSQL extreme database DSN is required'
      if $dsn !~ /\Adbi:Pg:/msx;
    $dsn =~ s/\Adbi:Pg://msx;
    my $values = _dsn_values($dsn);
    my $name   = $values->{dbname} // q{};
    _guard_name($name);
    _guard_location($values);
    return $name;
}

sub _guard_name($name) {
    my $prefix = 'gpforum_perf_extreme_';
    croak 'Extreme setup requires its own gpforum_perf_extreme_* database'
      if index( $name, $prefix ) != 0;
    my $suffix = substr $name, length $prefix;
    croak 'Extreme setup requires its own gpforum_perf_extreme_* database'
      if $suffix eq q{}
      || substr( $suffix, 0, 1 ) eq q{_}
      || $suffix =~ /[^[:lower:][:digit:]_]/msx
      || length($name) > MAX_NAME;
    return undef;
}

sub _dsn_values($dsn) {
    my %values;
    my %allowed = map { $_ => 1 }
      qw(dbname host hostaddr port connect_timeout application_name);
    for my $field ( split /;/msx, $dsn ) {
        next if $field eq q{};
        my ( $key, $value ) = split /=/msx, $field, 2;
        croak 'Ambiguous or unsupported extreme database DSN'
          if !defined $value
          || exists $values{$key}
          || !$allowed{$key};
        $values{$key} = $value;
    }
    return \%values;
}

sub _guard_location($values) {
    croak 'Extreme database host must be explicitly local'
      if !exists $values->{host} && !exists $values->{hostaddr};
    for my $key (qw(host hostaddr)) {
        next if !exists $values->{$key};
        croak
          'Extreme database host must be loopback or a temporary Unix socket'
          if !_local_host( $values->{$key}, $key eq 'host' );
    }
    _numeric_dsn_field( $values, 'port',            MAX_PORT );
    _numeric_dsn_field( $values, 'connect_timeout', MAX_CONNECT );
    croak 'Invalid application name'
      if exists $values->{application_name}
      && $values->{application_name} !~ /\A[[:alnum:]_-]+\z/msx;
    return undef;
}

sub _numeric_dsn_field( $values, $key, $maximum ) {
    return undef if !exists $values->{$key};
    croak "Invalid extreme database $key"
      if $values->{$key} !~ /\A[[:digit:]]+\z/msx
      || $values->{$key} < 1
      || $values->{$key} > $maximum;
    return undef;
}

sub _local_host ( $host, $socket_allowed ) {
    return 1 if $host eq '127.0.0.1' || $host eq '::1' || $host eq 'localhost';
    return 0 if !$socket_allowed || !File::Spec->file_name_is_absolute($host);
    require Cwd;
    my $resolved = Cwd::abs_path($host);
    return 0 if !defined $resolved;
    for my $root ( '/tmp', '/private/tmp', $ENV{RUNNER_TEMP} // q{} ) {
        next if $root eq q{};
        my $allowed = Cwd::abs_path($root);
        next if !defined $allowed;
        return 1
          if $resolved eq $allowed || index( $resolved, $allowed . q{/} ) == 0;
    }
    return 0;
}

sub _remaining ($deadline) { return _max( 0, $deadline - monotonic() ); }
sub _min  ( $a, $b ) { return $a < $b ? $a : $b; }
sub _max  ( $a, $b ) { return $a > $b ? $a : $b; }
sub _json ($value)   { return JSON::PP->new->canonical->encode($value); }

sub _command_json ( $command, $timeout, $log ) {
    croak GPForum::Performance::CommandError->new(
        'No seed setup budget remaining',
        1, undef )
      if $timeout <= 0;
    my $result = JSON::PP->new->decode(
        run_bounded( $command, { timeout => $timeout, log => $log } ) );
    croak 'Database helper did not return an object' if ref $result ne 'HASH';
    return $result;
}

sub _seed ( $profile, $diagnostics, $timeout ) {
    my @command = ( 'bin/gpforum', 'performance-seed', '--json' );
    for my $key ( sort keys %{ $PROFILES{$profile} } ) {
        ( my $option = $key ) =~ tr/_/-/;
        push @command, q{--} . $option, $PROFILES{$profile}{$key};
    }
    my $result = _command_json( \@command, $timeout,
        File::Spec->catfile( $diagnostics, "seed-$profile.log" ) );
    croak 'Seeder did not confirm its transaction committed'
      if ( $result->{status} // q{} ) ne 'seeded';
    my $planned = _planned($profile);
    for my $key ( keys %{$planned} ) {
        croak 'Seed report differs from the requested profile'
          if !defined $result->{dataset}{$key}
          || $result->{dataset}{$key} != $planned->{$key};
    }
    return $result;
}

sub _planned ($profile) {
    return {
        %{ $PROFILES{$profile} },
        posts => $PROFILES{$profile}{threads} *
          $PROFILES{$profile}{posts_per_thread}
    };
}

sub prepare ( $profile, $diagnostics, $deadline ) {
    guard();
    croak 'Extreme dataset profile must be full or reduced'
      if !exists $PROFILES{$profile};
    croak 'A finite absolute setup deadline is required'
      if !defined $deadline
      || !looks_like_number($deadline)
      || $deadline != $deadline
      || $deadline <= 0
      || "$deadline" =~ /inf/msxi;
    make_path($diagnostics);
    my $started = monotonic();
    my ( $actual, $report, @attempts ) = ( $profile, undef );
    if ( $profile eq 'full' ) {
        $report = _try_full( $diagnostics, $deadline, \@attempts );
        if ( !$report ) { $actual = 'reduced'; }
    }
    if ( !$report ) {
        my $attempt = monotonic();
        $report = _seed(
            'reduced',
            $diagnostics,
            _min(
                FALLBACK_RESERVE,
                _max( 0, _remaining($deadline) - FINAL_RESERVE )
            )
        );
        push @attempts,
          {
            profile          => 'reduced',
            status           => 'ok',
            duration_seconds => monotonic() - $attempt
          };
    }
    run_bounded(
        [ 'bin/gpforum', 'budgets', '--sync' ],
        {
            timeout => _min(
                SYNC_TIMEOUT, _max( 0, _remaining($deadline) - SYNC_RESERVE )
            ),
            log => File::Spec->catfile( $diagnostics, 'query-budget-sync.log' )
        }
    );
    my $pg     = _metadata( _min( METADATA_TIMEOUT, _remaining($deadline) ) );
    my $counts = delete $pg->{counts};
    _verify_counts( $actual, $counts );
    my $commit = run_bounded(
        [ 'git', 'rev-parse', 'HEAD' ],
        {
            timeout => _min( 2, _remaining($deadline) ),
            log => File::Spec->catfile( $diagnostics, 'database-commit.log' )
        }
    );
    $commit =~ s/\s+\z//msx;
    croak 'Application commit could not be verified'
      if $commit !~ /\A(?:[[:xdigit:]]{40}|[[:xdigit:]]{64})\z/msx;
    my $dataset =
      _dataset( $profile, $actual, $counts, $pg, \@attempts, $started );
    $pg->{code_commit} = $commit;
    $pg->{pid_namespace} =
      'Database server; backend PIDs are not assumed to be host PIDs';
    return ( $dataset, $pg );
}

sub _try_full( $diagnostics, $deadline, $attempts ) {
    my $report;
    my $timeout =
      _min( FULL_TIMEOUT, _max( 0, _remaining($deadline) - FALLBACK_RESERVE ) );
    if ( $timeout >= 1 ) {
        my $attempt = monotonic();
        try {
            $report = _seed( 'full', $diagnostics, $timeout );
            push @{$attempts},
              {
                profile          => 'full',
                status           => 'ok',
                duration_seconds => monotonic() - $attempt
              };
        }
        catch ($error) {
            croak $error if !blessed($error) || !$error->{timed_out};
            push @{$attempts},
              {
                profile          => 'full',
                status           => 'timed_out',
                duration_seconds => monotonic() - $attempt,
                reason           => 'Seed exceeded its allocation; '
                  . 'connection closure rolls back its transaction'
              };
        };
    }
    else {
        push @{$attempts},
          {
            profile          => 'full',
            status           => 'skipped',
            duration_seconds => 0,
            reason           =>
'Insufficient setup budget after reserving reduced seed and metadata'
          };
    }
    return $report;
}

sub _verify_counts ( $profile, $counts ) {
    my $expected = _planned($profile);
    for my $key (qw(users categories threads posts)) {
        croak 'Observed database counts differ from the completed seed'
          if !defined $counts->{$key} || $counts->{$key} != $expected->{$key};
    }
    for my $key (qw(sessions search_documents post_bodies post_revisions)) {
        my $number =
            $key eq 'sessions'         ? $expected->{users}
          : $key eq 'search_documents' ? $expected->{threads}
          :                              $expected->{posts};
        croak 'Observed fixture relation count differs from the completed seed'
          if !defined $counts->{$key} || $counts->{$key} != $number;
    }
    $counts->{posts_per_thread} = $expected->{posts_per_thread};
    return undef;
}

sub _dataset ( $profile, $actual, $counts, $pg, $attempts, $started ) {
    my $seed_seconds = 0;
    for my $attempt ( @{$attempts} ) {
        $seed_seconds += $attempt->{duration_seconds};
    }
    my %hashes;
    for my $source (@SOURCES) {
        open my $file, '<', File::Spec->catfile( root_dir(), $source )
          or croak 'read seed source failed';
        my $text = do { local $INPUT_RECORD_SEPARATOR = undef; <$file> };
        close $file or croak 'close seed source failed';
        $hashes{$source} = sha256_hex($text);
    }
    my $dataset = {
        profile                => 'extreme-' . $actual,
        requested_profile      => $profile,
        actual_profile         => $actual,
        status                 => $profile eq $actual ? 'ok' : 'reduced',
        counts                 => $counts,
        requested_counts       => _planned($profile),
        seed_version           => 'SeedDataset-v1',
        seed_duration_seconds  => $seed_seconds,
        setup_duration_seconds => monotonic() - $started,
        attempts               => $attempts,
        implementation_sha256  => \%hashes,
        distribution           => {
            visibility             => 'public',
            spaces                 => 1,
            categories_and_authors => 'deterministic round-robin',
            search_documents       => 'one per thread',
            content                => 'short uniform synthetic body template',
            observed               => delete $pg->{distribution}
        },
        limitations => [
'Synthetic public reads; placeholder session hashes are not an authentication harness.',
'Seed and SQL instrumentation time are separate from HTTP measurements.'
        ]
    };
    if ( $profile ne $actual ) {
        $dataset->{reason} =
'Requested 96,000-post profile was not completed; reduced 4,800-post dataset is explicitly measured instead';
    }
    $dataset->{signature} = sha256_hex(
        _json(
            {
                map { $_ => $dataset->{$_} }
                  qw(profile counts distribution seed_version implementation_sha256)
            }
        )
    );
    return $dataset;
}

sub _database ( $timeout, $code ) {
    croak 'No database observation budget remaining' if $timeout <= 0;
    require DBI;
    my ( $dbh, $result, $error );
    local $SIG{ALRM} =
      sub { die "Database observation exceeded its deadline\n"; };
    my $prior = alarm $timeout;
    try {
        my $dsn = $ENV{GPFORUM_DATABASE_DSN};
        $dsn =~ s/;connect_timeout=[[:digit:]]+//msx;
        $dsn .= ';connect_timeout=1';
        $dbh = DBI->connect(
            $dsn,
            $ENV{GPFORUM_DATABASE_USER},
            $ENV{GPFORUM_DATABASE_PASSWORD},
            { AutoCommit => 1, RaiseError => 1, PrintError => 0 }
        );
        $result = $code->($dbh);
    }
    catch ($caught) { $error = $caught; };
    alarm $prior;
    if ($dbh) {
        try {
            if ( !$dbh->{AutoCommit} ) { $dbh->rollback; }
            $dbh->disconnect;
        }
        catch ($cleanup) { $error //= $cleanup; };
    }
    croak $error if defined $error;
    return $result;
}

sub _metadata ($timeout) {
    return _database(
        $timeout,
        sub($dbh) {
            $dbh->do('SET statement_timeout = 10000');
            $dbh->do('SET lock_timeout = 250');
            $dbh->do('ANALYZE');
            $dbh->begin_work;
            $dbh->do('SET TRANSACTION READ ONLY');
            my $started = monotonic();
            my $counts  = $dbh->selectrow_hashref(<<'SQL');
SELECT
          (SELECT count(*) FROM users) AS users,(SELECT count(*) FROM categories) AS categories,
          (SELECT count(*) FROM threads) AS threads,(SELECT count(*) FROM posts) AS posts,
          (SELECT count(*) FROM sessions) AS sessions,(SELECT count(*) FROM sessions WHERE expires_at>now()) AS unexpired_sessions,
          (SELECT count(*) FROM search_documents) AS search_documents,(SELECT count(*) FROM post_bodies) AS post_bodies,
          (SELECT count(*) FROM post_revisions) AS post_revisions
SQL
            for my $value ( values %{$counts} ) { $value = 0 + $value; }
            my $distribution = $dbh->selectrow_hashref(<<'SQL');
SELECT coalesce(min(n),0) AS posts_per_thread_min,
          coalesce(max(n),0) AS posts_per_thread_max,coalesce(avg(n),0) AS posts_per_thread_mean
          FROM (SELECT count(*) AS n FROM posts GROUP BY thread_id) sizes
SQL
            my $body = $dbh->selectrow_hashref(<<'SQL');
SELECT coalesce(min(octet_length(body_source)),0) AS body_bytes_min,
          coalesce(max(octet_length(body_source)),0) AS body_bytes_max,coalesce(avg(octet_length(body_source)),0) AS body_bytes_mean FROM post_bodies
SQL

            for my $value ( values %{$distribution}, values %{$body} ) {
                $value = 0 + $value;
            }
            my ( %settings, %sizes );
            for my $setting (@SETTINGS) {
                $settings{$setting} =
                  $dbh->selectrow_array( 'SELECT current_setting(?)',
                    undef, $setting );
            }
            for my $table (
                qw(posts threads post_bodies post_revisions search_documents))
            {
                $sizes{$table} = 0 + $dbh->selectrow_array(
                    'SELECT pg_total_relation_size(?::regclass)',
                    undef, $table );
            }
            require GPForum;
            return {
                counts       => $counts,
                distribution => { %{$distribution}, %{$body} },
                postgres     => $dbh->selectrow_array('SHOW server_version'),
                application_version => GPForum->VERSION,
                database_settings   => \%settings,
                relation_bytes      => \%sizes,
                database_size_bytes => 0 + $dbh->selectrow_array(
                    'SELECT pg_database_size(current_database())'),
                sql_elapsed_ms => MILLISECONDS * ( monotonic() - $started )
            };
        }
    );
}

sub _snapshot_sql ($dbh) {
    $dbh->begin_work;
    $dbh->do('SET TRANSACTION READ ONLY');
    $dbh->do(q{SET LOCAL application_name = 'gpforum-extreme-observer'});
    $dbh->do('SET LOCAL statement_timeout = 750');
    $dbh->do('SET LOCAL lock_timeout = 200');
    my $started = monotonic();
    my $report  = $dbh->selectrow_hashref(<<'SQL');
SELECT count(*) AS connections,
      count(*) FILTER(WHERE state='active') AS active,count(*) FILTER(WHERE state='idle') AS idle,
      count(*) FILTER(WHERE state LIKE 'idle in transaction%') AS idle_in_transaction,
      count(*) FILTER(WHERE xact_start IS NOT NULL) AS transactions,count(*) FILTER(WHERE state IS NULL) AS states_unknown,
      count(*) FILTER(WHERE state='active' AND wait_event_type IS NOT NULL) AS waiting_active,
      count(*) FILTER(WHERE wait_event_type='Lock') AS lock_waits,
      coalesce(max(EXTRACT(EPOCH FROM clock_timestamp()-xact_start)),0) AS oldest_transaction_seconds
      FROM pg_stat_activity WHERE datname=current_database() AND pid<>pg_backend_pid() AND backend_type='client backend'
SQL
    for my $value ( values %{$report} ) { $value = 0 + $value; }
    $report->{max_connections} = 0 + $dbh->selectrow_array(
        q{SELECT current_setting('max_connections')::integer});
    my $outbox = $dbh->selectrow_hashref(<<'SQL');
SELECT count(*) FILTER(WHERE status='pending') AS outbox_pending,
      count(*) FILTER(WHERE status='failed') AS outbox_retry,count(*) FILTER(WHERE status='running') AS outbox_running,
      count(*) FILTER(WHERE status='running' AND locked_until<=now()) AS outbox_stale_running,
      count(*) FILTER(WHERE (status IN ('pending','failed') AND next_attempt_at<=now() AND(locked_until IS NULL OR locked_until<=now()))
        OR(status='running' AND locked_until IS NOT NULL AND locked_until<=now())) AS outbox_ready,
      coalesce(EXTRACT(EPOCH FROM now()-min(CASE WHEN status='running' AND locked_until<=now() THEN locked_until
        WHEN status IN('pending','failed') AND next_attempt_at<=now() AND(locked_until IS NULL OR locked_until<=now())
        THEN GREATEST(next_attempt_at,COALESCE(locked_until,next_attempt_at)) END)),0) AS outbox_oldest_ready_seconds FROM outbox_messages
SQL
    for my $key ( keys %{$outbox} ) { $report->{$key} = 0 + $outbox->{$key}; }
    $report->{sql_elapsed_ms} = MILLISECONDS * ( monotonic() - $started );
    return $report;
}

sub _process ($pid) {
    my $base = '/proc/' . $pid;
    open my $stat, '<', $base . '/stat' or return undef;
    my $line = <$stat>;
    close $stat or return undef;
    $line =~ s/.*[)]//msx;
    my @fields = split /\s+/msx, $line;
    if ( $fields[0] eq q{} ) { shift @fields; }
    return undef if @fields < MIN_STAT_FIELDS;
    open my $status, '<', $base . '/status' or return undef;
    my $text = do { local $INPUT_RECORD_SEPARATOR = undef; <$status> };
    close $status or return undef;
    my ($rss) = $text =~ /^VmRSS:\s+([[:digit:]]+)\s+kB/msx;
    my @children;

    if ( open my $child, '<', $base . '/task/' . $pid . '/children' ) {
        @children = split /\s+/msx,
          do { local $INPUT_RECORD_SEPARATOR = undef; <$child> };
        close $child or return undef;
    }
    return {
        ticks     => $fields[CPU_USER_FIELD] + $fields[CPU_SYSTEM_FIELD],
        started   => $fields[PROCESS_START_FIELD],
        rss_bytes => defined $rss ? $rss * KIBIBYTE : undef,
        children  => \@children
    };
}

sub _resources {
    my $master  = $ENV{GPFORUM_EXTREME_PG_MASTER_PID} // q{};
    my $unknown = {
        cpu_percent  => undef,
        rss_bytes    => undef,
        span_seconds => undef,
        source       => 'PG host process metrics unavailable'
    };
    return $unknown if $master !~ /\A[[:digit:]]+\z/msx || $master < 1;
    my ( @pending, %seen, %rows ) = ($master);
    while (@pending) {
        my $pid = shift @pending;
        next if !$pid || $seen{$pid}++;
        my $row = _process($pid);
        next if !$row;
        $rows{$pid} = $row;
        push @pending, @{ $row->{children} };
    }
    return $unknown if !exists $rows{$master};
    my $now = monotonic();
    my ( $cpu, $span );
    ( $cpu, $span ) = _cpu_delta( $master, $now, \%rows );
    $previous_processes = { master => $master, time => $now, rows => \%rows };
    my $rss     = 0;
    my $all_rss = 1;

    for my $row ( values %rows ) {
        if ( defined $row->{rss_bytes} ) { $rss += $row->{rss_bytes}; }
        else                             { $all_rss = 0; }
    }
    return {
        cpu_percent  => $cpu,
        rss_bytes    => $all_rss ? $rss : undef,
        span_seconds => $span,
        source       =>
'Linux /proc PG host master and recursive children; CPU delta; RSS sum may double-count shared pages; FD permissions ignored'
    };
}

sub _cpu_delta( $master, $now, $rows ) {
    return ( undef, undef )
      if !$previous_processes || $previous_processes->{master} ne $master;
    my $current_keys = join q{,}, sort keys %{$rows};
    my $prior_keys   = join q{,}, sort keys %{ $previous_processes->{rows} };
    return ( undef, undef ) if $current_keys ne $prior_keys;
    my $span = $now - $previous_processes->{time};
    return ( undef, $span ) if $span < MIN_CPU_SPAN;
    my $ticks = 0;
    for my $pid ( keys %{$rows} ) {
        my $before = $previous_processes->{rows}{$pid};
        return ( undef, $span )
          if $rows->{$pid}{started} != $before->{started}
          || $rows->{$pid}{ticks} < $before->{ticks};
        $ticks += $rows->{$pid}{ticks} - $before->{ticks};
    }
    require POSIX;
    my $tick_hz = POSIX::sysconf( POSIX::_SC_CLK_TCK() );
    return ( undef,                               $span ) if $tick_hz <= 0;
    return ( PERCENT * $ticks / $tick_hz / $span, $span );
}

sub _saturation ( $metrics, $resource ) {
    my $cpus      = _cpu_count();
    my $cpu_known = defined $resource->{cpu_percent} && $cpus > 0;
    my $cpu_busy  = $cpu_known && $resource->{cpu_percent} >= CPU_LIMIT * $cpus;
    my $connection_busy = $metrics->{max_connections} > 0
      && $metrics->{connections} >=
      CONNECTION_LIMIT * $metrics->{max_connections};
    my $locks_rising = _locks_rising($metrics);
    return ( JSON::PP::true,
        'Measured PostgreSQL CPU reaches at least 85% of host CPU capacity' )
      if $cpu_busy;
    return ( JSON::PP::true,
        'Observed database connections reach at least 90% of max_connections' )
      if $connection_busy;
    return ( JSON::PP::true,
        'Observed lock waits accompany a rising active SQL wait backlog' )
      if $locks_rising;
    my $no_waits = _no_waits($metrics);
    return ( JSON::PP::false,
'Measured CPU headroom, connection headroom and no observed active SQL waits'
    ) if $cpu_known && $metrics->{max_connections} > 0 && $no_waits;
    return ( undef,
        'PostgreSQL saturation is inconclusive without CPU and wait evidence' );
}

sub _locks_rising($metrics) {
    my $rising =
         $metrics->{lock_waits}
      && $previous_backlog
      && $metrics->{waiting_active} > $previous_backlog->{waiting_active};
    $previous_backlog = { waiting_active => $metrics->{waiting_active} };
    return $rising;
}

sub _no_waits($metrics) {
    return
         !$metrics->{waiting_active}
      && !$metrics->{lock_waits}
      && !$metrics->{states_unknown};
}

sub _cpu_count {
    open my $file, '<', '/proc/stat' or return 0;
    my $count = 0;
    while ( my $line = <$file> ) {
        if ( $line =~ /\Acpu[[:digit:]]+\s/msx ) { $count++; }
    }
    close $file or return 0;
    return $count;
}

sub sample ( $timeout = 2 ) {
    guard();
    my $started = monotonic();
    my ( $metrics, $error );
    try {
        $metrics = _database( $timeout, \&_snapshot_sql );
        _validate_sample($metrics);
    }
    catch ($caught) {
        $error = $caught;
    };
    return {
        status                     => 'failed',
        reason                     => redact("$error"),
        metrics                    => {},
        saturated                  => undef,
        resource_headroom_verified => JSON::PP::false,
        timed_out                  => ( blessed($error) && $error->{timed_out} )
          || "$error" =~ /deadline/msx
        ? JSON::PP::true
        : JSON::PP::false,
        duration_seconds => monotonic() - $started
      }
      if defined $error;
    my $resource = _resources();
    my ( $saturated, $reason ) = _saturation( $metrics, $resource );
    return {
        status                     => 'ok',
        metrics                    => $metrics,
        resource                   => $resource,
        saturated                  => $saturated,
        saturation_reason          => $reason,
        resource_headroom_verified => JSON::PP::false,
        duration_seconds           => monotonic() - $started,
        scope                      =>
'This database only; observer excluded; SQL elapsed time excludes HTTP; I/O headroom unverified'
    };
}

sub _validate_sample($metrics) {
    croak 'Database observation did not return an object'
      if ref $metrics ne 'HASH';
    for my $key (
        qw(connections active idle transactions idle_in_transaction waiting_active lock_waits states_unknown max_connections outbox_pending outbox_retry sql_elapsed_ms)
      )
    {
        my $value = $metrics->{$key};
        croak 'Invalid or missing database observation metric'
          if !defined $value
          || ref $value
          || !looks_like_number($value)
          || $value < 0
          || $value != $value
          || "$value" =~ /inf/msxi;
        $metrics->{$key} = 0 + $value;
    }
    return undef;
}

1;
