# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Performance::Hotpaths;

use v5.40;
use Carp       qw(croak);
use Exporter   qw(import);
use File::Path qw(make_path);
use File::Spec;
use JSON::PP;
use List::Util   qw(any);
use Scalar::Util qw(blessed looks_like_number);
use GPForum::Performance::Support
  qw(root_dir read_json write_json redact monotonic run_bounded);

our $VERSION   = '0.001';
our @EXPORT_OK = qw(collect execute);

# Core constants keep this module loadable before Carton installs dependencies.
use constant {    ## no critic (ValuesAndExpressions::ProhibitConstantPragma)
    PR_DEADLINE      => 180,
    MAIN_DEADLINE    => 300,
    DEEP_DEADLINE    => 600,
    GATE_TIMEOUT     => 60,
    PLAN_TIMEOUT     => 150,
    OUTBOX_TIMEOUT   => 300,
    SQL_TIMEOUT      => 240,
    PROFILE_TIMEOUT  => 120,
    PROBE_TIMEOUT    => 30,
    PR_MESSAGES      => 1_000,
    MAIN_MESSAGES    => 3_000,
    DEEP_MESSAGES    => 10_000,
    BATCH_SIZE       => 100,
    READ_ITERATIONS  => 30,
    WRITE_ITERATIONS => 10,
    WARMUP           => 5,
    PROXY_DELAY      => 0.5,
    REPETITIONS      => 3,
    MAXIMUM_WORKERS  => 4,
};
my %DEADLINES =
  ( pr => PR_DEADLINE, main => MAIN_DEADLINE, deep => DEEP_DEADLINE );

sub _path( $output, $name ) { return File::Spec->catfile( $output, $name ); }

sub _redact_values($value) {
    return { map { $_ => _redact_values( $value->{$_} ) } keys %{$value} }
      if ref $value eq 'HASH';
    return [ map { _redact_values($_) } @{$value} ] if ref $value eq 'ARRAY';
    return $value if ref $value || !defined $value || looks_like_number($value);
    return redact($value);
}

sub execute( $command, $output, $name, $options ) {
    my $started = monotonic();
    my ( $raw, $error, $payload );
    my %result;
    my $diagnostic = 'diagnostics/' . $name . '.log';
    try {
        $raw = run_bounded(
            $command,
            {
                %{$options},
                result => \%result,
                log    => _path( $output, $diagnostic )
            }
        );
    }
    catch ($caught) { $error = $caught; };
    if ( !defined $raw && defined $result{output} ) { $raw = $result{output}; }
    if ( defined $raw ) {
        try {
            my $decoded = JSON::PP->new->decode($raw);
            if ( ref $decoded eq 'HASH' ) {
                $payload = _redact_values($decoded);
            }
        }
        catch ($invalid) { $payload = undef; };
    }
    return {
        payload   => $payload,
        exit_code => defined $error
        ? ( blessed($error) ? $error->{returncode} // 1 : 1 )
        : 0,
        timed_out => blessed($error)
          && $error->{timed_out} ? JSON::PP::true : JSON::PP::false,
        duration_seconds => monotonic() - $started,
        diagnostic       => $diagnostic
    };
}

sub _numeric($values) {
    return {
        map { $_ => defined $values->{$_} ? 0 + $values->{$_} : undef }
        grep {
            !defined $values->{$_}
              || ( !ref $values->{$_} && looks_like_number( $values->{$_} ) )
        } keys %{$values}
    };
}

sub _state( $result, $success ) {
    return $result->{skipped} ? 'skipped' : $success ? 'ok' : 'failed';
}

sub _combined($states) {
    return 'failed'  if any  { $_ eq 'failed' } @{$states};
    return 'skipped' if !any { $_ ne 'skipped' } @{$states};
    return 'partial' if any  { $_ eq 'skipped' } @{$states};
    return 'ok';
}

sub _okay($result) {
    return
         defined $result->{exit_code}
      && $result->{exit_code} == 0
      && $result->{payload}
      && ( $result->{payload}{status} // q{} ) eq 'ok';
}

sub _guard($disposable) {
    my $dsn = $ENV{GPFORUM_DATABASE_DSN};
    return undef if !$dsn;
    croak
'--disposable-database is required: use an isolated migrated and seeded database'
      if !$disposable;
    my ($name) = $dsn =~ /(?:\A|[;:])dbname=([^;]+)/msx;
    croak
'--disposable-database requires a dedicated gpforum_perf_* or gpforum_test database'
      if !defined $name
      || ( $name !~ /\Agpforum_perf_/msx && $name ne 'gpforum_test' );
    return $dsn;
}

sub _configuration( $output, $mode, $deadline ) {
    my $metadata = {};
    for my $name (qw(metadata.json http-environment.json)) {
        my $path = _path( $output, $name );
        next if !-f $path;
        $metadata = { %{$metadata}, %{ read_json($path) } };
    }
    my $profile = $metadata->{dataset}{profile}
      // ( $mode eq 'pr' ? 'small' : 'medium' );
    my %profiles = map { $_ => 1 } qw(small medium hot-thread);
    if ( !$profiles{$profile} ) { $profile = 'medium'; }
    my $repeats = $mode eq 'pr' ? 1 : REPETITIONS;
    my @workers =
        $mode eq 'pr'   ? (1)
      : $mode eq 'main' ? ( 1, 2 )
      :                   ( 1, 2, MAXIMUM_WORKERS );
    my $messages =
        $mode eq 'pr'   ? PR_MESSAGES
      : $mode eq 'main' ? MAIN_MESSAGES
      :                   DEEP_MESSAGES;
    write_json(
        _path( $output, 'hotpaths-environment.json' ),
        {
            configuration => {
                hotpaths => {
                    deadline_seconds       => $deadline,
                    plan_repetitions       => $repeats,
                    plan_cli_profile_label => $profile,
                    plans                  => [ 'readers', 'functions' ],
                    analyze                => JSON::PP::true,
                    outbox                 => {
                        messages    => $messages,
                        workers     => \@workers,
                        repetitions => $repeats,
                        batch_size  => BATCH_SIZE,
                        transport   => 'recording no-op',
                        database    => 'fresh owned'
                    },
                    sql_service_comparison => {
                          enabled => $mode eq 'deep'
                        ? JSON::PP::true
                        : JSON::PP::false,
                        read_iterations  => READ_ITERATIONS,
                        write_iterations => WRITE_ITERATIONS,
                        warmup           => WARMUP,
                        proxy_delay_ms   => PROXY_DELAY
                    },
                    profiling => 'configured NYTProf deep only'
                }
            }
        }
    );
    return {
        profile  => $profile,
        repeats  => $repeats,
        workers  => \@workers,
        messages => $messages
    };
}

sub collect(
    $output, $mode,
    $disposable = 0,
    $provided   = undef,
    $deadline   = undef
  )
{
    croak 'Unknown hot-path mode' if !exists $DEADLINES{$mode};
    make_path($output);
    my $dsn = _guard($disposable);
    $deadline //= $DEADLINES{$mode};
    my $expires = monotonic() + $deadline;
    my $execute = $provided // \&execute;
    my $runner =
      sub( $command, $name, $timeout = PROFILE_TIMEOUT, $env = undef ) {
        my $remaining = $expires - monotonic();
        return {
            payload          => undef,
            exit_code        => undef,
            skipped          => JSON::PP::true,
            timed_out        => JSON::PP::false,
            duration_seconds => 0,
            diagnostic       => undef,
            reason           => 'Hot-path suite wall-clock deadline'
          }
          if $remaining <= 0;
        return $execute->(
            $command, $output, $name,
            {
                timeout => $timeout < $remaining ? $timeout : $remaining,
                ( defined $env ? ( env => $env ) : () )
            }
        );
      };
    my $configuration = _configuration( $output, $mode, $deadline );
    my ( %states, @database, @outbox );
    my %static_env = %ENV;
    delete $static_env{GPFORUM_DATABASE_DSN};
    my $static = $runner->(
        [ 'script/gpforum-carton', 'exec', 'script/query-plan-check' ],
        'query-plan-static', GATE_TIMEOUT, \%static_env
    );
    $states{'query-plan-static'} = {
        status => _state(
            $static, defined $static->{exit_code} && $static->{exit_code} == 0
        ),
        reason => $static->{reason}
          // 'Required index and forbidden OFFSET checks',
        diagnostic => $static->{diagnostic}
    };
    if ( !$dsn ) {
        for my $suite (
            qw(query-budget database-plans outbox-postgres sql-functions profiling)
          )
        {
            $states{$suite} = {
                status => 'skipped',
                reason => 'GPFORUM_DATABASE_DSN is absent'
            };
        }
    }
    else {
        _budget( $runner, \%states, \@database );
        _plans( $runner, \%states, \@database, $configuration );
        _outbox( $runner, \%states, \@outbox, $configuration, $mode );
        _optional( $runner, \%states, \@database, $output, $mode );
    }
    _write_results( $output, $mode, \%states, \@database, \@outbox );
    return scalar( grep { $_->{status} eq 'failed' } values %states ) ? 1 : 0;
}

sub _optional( $runner, $states, $database, $output, $mode ) {
    if ( $mode eq 'deep' ) {
        _sql_functions( $runner, $states, $database );
        _profile( $runner, $states, $output );
    }
    else {
        for my $suite (qw(sql-functions profiling)) {
            $states->{$suite} = {
                status => 'skipped',
                reason => 'Reserved for bounded weekly/manual deep mode'
            };
        }
    }
    return undef;
}

sub _budget( $runner, $states, $database ) {
    my $result = $runner->(
        [ 'script/query-budget', '--check', '--json' ],
        'query-budget', GATE_TIMEOUT
    );
    my $payload = $result->{payload};
    my $okay    = _okay($result);
    my $drift   = $payload && any { @{ $payload->{$_} // [] } }
      qw(extra missing mismatched);
    $states->{'query-budget'} = {
        status => _state( $result, $okay ),
        reason => $result->{reason}
          // 'Catalog drift is deterministic; N+1 request counts remain blocking in the integration tier',
        failure_kind => $drift ? 'deterministic' : $okay
          || $result->{skipped} ? undef : 'infrastructure_or_harness',
        diagnostic => $result->{diagnostic}
    };
    if ($payload) {
        push @{$database},
          {
            scenario => 'query-budget-catalog',
            status   => $okay ? 'ok' : 'failed',
            metrics  => {},
            evidence => $payload
          };
    }
    return undef;
}

sub _plans( $runner, $states, $database, $config ) {
    for my $backend (qw(readers functions)) {
        my @statuses;
        for my $repetition ( 1 .. $config->{repeats} ) {
            my @command = (
                'script/query-plan-evidence', '--check', '--json', '--analyze',
                '--profile', $config->{profile},
            );
            if ( $backend eq 'functions' ) { push @command, '--functions'; }
            my $result = $runner->(
                \@command, "query-plan-$backend-$repetition", PLAN_TIMEOUT
            );
            push @statuses, _state( $result, _okay($result) );
            next if !$result->{payload};
            for my $endpoint ( @{ $result->{payload}{endpoints} // [] } ) {
                my $summary = $endpoint->{summary} // {};
                push @{$database},
                  {
                    scenario   => 'sql-plan-' . $backend,
                    endpoint   => $endpoint->{endpoint} // 'unknown',
                    repetition => $repetition,
                    status     => ( $endpoint->{status} // q{} ) eq 'ok'
                    ? 'ok'
                    : 'failed',
                    metrics => _numeric(
                        {
                            sql_execution_ms  => $summary->{actual_time_ms},
                            actual_rows       => $summary->{actual_rows},
                            nested_statements => $summary->{nested_statements}
                        }
                    ),
                    evidence => {
                        map  { $_ => $endpoint->{$_} }
                        grep { exists $endpoint->{$_} }
                          qw(endpoint purpose sql_label summary violations warnings)
                    },
                    limitations => [
'EXPLAIN instrumentation overhead; SQL time excludes HTTP and rendering'
                    ]
                  };
            }
        }
        my $skipped    = scalar grep { $_ eq 'skipped' } @statuses;
        my $violations = grep {
            $_->{scenario} eq 'sql-plan-' . $backend
              && @{ $_->{evidence}{violations} // [] }
        } @{$database};
        $states->{ 'database-plans-' . $backend } = {
            status              => _combined( \@statuses ),
            skipped_repetitions => $skipped,
            reason => $skipped ? 'Hot-path suite wall-clock deadline'
            : 'Nested function plans require auto_explain LOAD; unavailable or unmeasured is never PASS',
            failure_kind => $violations ? 'deterministic'
            : scalar( grep { $_ eq 'failed' } @statuses )
            ? 'infrastructure_or_harness'
            : undef
        };
    }
    return undef;
}

sub _outbox( $runner, $states, $outbox, $config, $mode ) {
    my $result = $runner->(
        [
            'script/gpforum-carton',
            'exec',
            'script/performance-outbox.pl',
            '--json',
            '--messages',
            $config->{messages},
            '--workers',
            join( q{,}, @{ $config->{workers} } ),
            '--repetitions',
            $config->{repeats}
        ],
        'outbox-postgres',
        $mode eq 'deep' ? OUTBOX_TIMEOUT : PLAN_TIMEOUT
    );
    my $payload = $result->{payload};
    for my $row ( @{ ( $payload // {} )->{results} // [] } ) {
        push @{$outbox},
          {
            scenario   => 'postgres-dispatch-noop',
            workers    => $row->{workers},
            repetition => $row->{repetition},
            status     => $row->{status} eq 'ok' ? 'ok' : 'failed',
            metrics    => _numeric(
                {
                    messages_per_second => $row->{messages_per_second},
                    completed           => $row->{delivered},
                    duration_seconds    => $row->{duration_seconds},
                    p50_ms              => $row->{p50_batch_ms},
                    p95_ms              => $row->{p95_batch_ms},
                    p99_ms              => $row->{p99_batch_ms},
                    lost                => $row->{lost},
                    duplicates          => $row->{duplicates},
                    acknowledged        => $row->{acknowledged}
                }
            ),
            configuration => {
                messages   => $config->{messages},
                batch_size => BATCH_SIZE,
                transport  => 'no-op'
            },
            evidence    => $row,
            limitations => [
'Actual PostgreSQL claim/renew/ack; no-op excludes delivery cost; batch percentiles are not message latency'
            ]
          };
    }
    my $failed = grep { $_->{status} ne 'ok' } @{$outbox};
    $states->{'outbox-postgres'} = {
        status => _state( $result, _okay($result) ),
        reason => $result->{reason}
          // 'Owned database is dropped on completion or caught signals; delivery IDs verify losses and duplicates',
        failure_kind => $result->{skipped} ? undef
        : !$payload || $payload->{error} ? 'infrastructure_or_harness'
        : $failed                        ? 'deterministic'
        : undef,
        diagnostic => $result->{diagnostic}
    };
    return undef;
}

sub _sql_functions( $runner, $states, $database ) {
    my $result = $runner->(
        [
            'script/gpforum-carton',      'exec',
            'script/bench-sql-functions', '--json',
            '--read-iterations',          READ_ITERATIONS,
            '--write-iterations',         WRITE_ITERATIONS,
            '--warmup',                   WARMUP,
            '--delay-ms',                 PROXY_DELAY
        ],
        'sql-functions',
        SQL_TIMEOUT
    );
    my $payload = $result->{payload} // {};
    for my $operation ( sort keys %{ $payload->{operations} // {} } ) {
        for my $path ( sort keys %{ $payload->{operations}{$operation} } ) {
            for my $connection (qw(direct proxy)) {
                my $row =
                  $payload->{operations}{$operation}{$path}{$connection};
                next if !$row;
                push @{$database},
                  {
                    scenario => "sql-function-service-$path-$connection",
                    endpoint => $operation,
                    status   => defined $result->{exit_code}
                      && $result->{exit_code} == 0 ? 'ok' : 'failed',
                    evidence_quality => 'indicative',
                    metrics          => _numeric(
                        {
                            p50_ms         => $row->{median_ms},
                            p95_ms         => $row->{p95_ms},
                            statements     => $row->{statements},
                            round_trips    => $row->{round_trips},
                            service_cpu_ms => $row->{cpu_ms}
                        }
                    ),
                    configuration => {
                        delay_ms => $payload->{delay_ms},
                        dataset  => $payload->{benchmark}{workload}
                    },
                    limitations => [
'Service/DBI timings; diagnostic internal iterations are not independent runner repetitions'
                    ]
                  };
            }
        }
    }
    $states->{'sql-functions'} = {
        status => _state(
            $result,
            defined $result->{exit_code}
              && $result->{exit_code} == 0
              && $result->{payload}
        ),
        reason => $result->{reason}
          // 'Existing helper owns its 3000-post / 1500-thread database',
        diagnostic => $result->{diagnostic}
    };
    return undef;
}

sub _profile( $runner, $states, $output ) {
    my $path = File::Spec->catdir( $output, 'diagnostics', 'profile' );
    make_path($path);
    my %env = (
        %ENV,
        NYTPROF => 'file='
          . File::Spec->rel2abs(
            File::Spec->catfile( $path, 'route-nytprof.out' )
          )
          . ':addpid=1'
    );
    my $probe = $runner->(
        [
            'script/gpforum-carton', 'exec',
            'perl',                  '-MDevel::NYTProf',
            '-e',                    'print qq{available\n}'
        ],
        'nytprof-availability',
        PROBE_TIMEOUT
    );
    if ( defined $probe->{exit_code} && $probe->{exit_code} == 0 ) {
        my $result = $runner->(
            [
                'script/profile-nytprof', '--route',
                '/categories',            '--configured',
                '--iterations',           WRITE_ITERATIONS,
                '--warmup',               2,
                '--json'
            ],
            'nytprof',
            PROFILE_TIMEOUT,
            \%env
        );
        opendir my $directory, $path
          or croak 'open profiling diagnostics failed';
        my @binaries =
          grep { /[.]out/msx && -f File::Spec->catfile( $path, $_ ) }
          readdir $directory;
        closedir $directory or croak 'close profiling diagnostics failed';
        $states->{profiling} = {
            status => _state(
                $result,
                defined $result->{exit_code}
                  && $result->{exit_code} == 0
                  && @binaries
            ),
            reason => $result->{reason}
              // 'Configured request profile; binaries only in diagnostic artifact',
            diagnostic => $result->{diagnostic}
        };
    }
    else {
        $states->{profiling} = {
            status     => 'skipped',
            reason     => $probe->{reason} // 'Devel::NYTProf is unavailable',
            diagnostic => $probe->{diagnostic}
        };
    }
    return undef;
}

sub _write_results( $output, $mode, $states, $database, $outbox ) {
    for my $pair ( [ 'database', $database ], [ 'outbox', $outbox ] ) {
        my ( $kind, $rows ) = @{$pair};
        if ( @{$rows} ) {
            write_json(
                _path( $output, $kind . '.json' ),
                {
                    schema_version => 1,
                    kind           => $kind,
                    status => scalar( grep { $_->{status} ne 'ok' } @{$rows} )
                    ? 'partial'
                    : 'ok',
                    measurements => $rows,
                    limitations  => []
                }
            );
        }
        $states->{$kind} = {
            status => _kind_status( $kind, $states, $mode, $rows ),
            reason =>
'See individual gates and artifacts; skipped suites never imply execution'
        };
    }
    write_json( _path( $output, 'hotpaths-status.json' ), $states );
    return undef;
}

sub _kind_status( $kind, $states, $mode, $rows ) {
    my @related = map { $states->{$_} } grep {
        $kind eq 'database'
          ? /\A(?:query-|database-|sql-functions)/msx
          : /\Aoutbox/msx
    } keys %{$states};
    return 'failed'  if any { $_->{status} eq 'failed' } @related;
    return 'skipped' if !@{$rows};
    my @required = map { $states->{$_} } grep {
        $kind eq 'database'
          ? /\A(?:query-|database-)/msx
          || ( $mode eq 'deep' && $_ eq 'sql-functions' )
          : /\Aoutbox/msx
    } keys %{$states};
    return 'partial'
      if any { $_->{status} eq 'skipped' || $_->{status} eq 'partial' }
      @required;
    return 'ok';
}

1;
