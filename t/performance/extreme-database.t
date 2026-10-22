# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;
use v5.40;
use Carp    qw(croak);
use English qw(-no_match_vars);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../../script/lib";
use JSON::PP;
use Test::More;
use GPForum::Performance::CommandError;
use GPForum::Performance::ExtremeDatabase qw(guard prepare sample);
our $VERSION = '0.001';

# Replace private I/O seams to exercise deadlines and SQL safety without a DB.
## no critic (Variables::ProtectPrivateVars, Subroutines::ProtectPrivateSubs)
# Named fixture values preserve core-only test execution before Carton install.
use constant {    ## no critic (ValuesAndExpressions::ProhibitConstantPragma)
    FULL_USERS          => 80,
    REDUCED_USERS       => 25,
    FULL_THREADS        => 800,
    REDUCED_THREADS     => 240,
    FULL_POSTS          => 120,
    REDUCED_POSTS       => 20,
    FULL_DEADLINE       => 1_300,
    CLOCK_START         => 1_000,
    SHA_LENGTH          => 40,
    DATABASE_BYTES      => 123_456,
    POSTS_BYTES         => 100_000,
    FULL_COUNT          => 96_000,
    SIGNATURE_LENGTH    => 64,
    FULL_ALLOCATION     => 150,
    FALLBACK_DEADLINE   => 1_210,
    SHORT_DEADLINE      => 1_059,
    EXPIRED_DEADLINE    => 999,
    REDUCED_COUNT       => 4_800,
    BOTH_SEED_SECONDS   => 152,
    MAX_CONNECTIONS     => 100,
    CONNECTION_PRESSURE => 90,
    HOST_CPUS           => 4,
    PG_CPU_PRESSURE     => 350,
    PG_CPU_HEADROOM     => 10,
    PG_MASTER           => 42,
    PG_RSS              => 1_024,
    CATEGORIES          => 8,
};

my %safe = (
    GPFORUM_DATABASE_DSN =>
      'dbi:Pg:dbname=gpforum_perf_extreme_test;host=127.0.0.1;port=5432',
    GPFORUM_EXTREME_DISPOSABLE_DATABASE => '1'
);

sub rejected( $code, $pattern, $description ) {
    my $error;
    try { $code->(); } catch ($caught) {
        $error = $caught;
    };
    like( "$error", $pattern, $description );
    return undef;
}

sub counts($profile) {
    my $full       = $profile eq 'full';
    my $users      = $full ? FULL_USERS   : REDUCED_USERS;
    my $threads    = $full ? FULL_THREADS : REDUCED_THREADS;
    my $per_thread = $full ? FULL_POSTS   : REDUCED_POSTS;
    my $posts      = $threads * $per_thread;
    return {
        users              => $users,
        categories         => CATEGORIES,
        threads            => $threads,
        posts              => $posts,
        posts_per_thread   => $per_thread,
        sessions           => $users,
        unexpired_sessions => 0,
        search_documents   => $threads,
        post_bodies        => $posts,
        post_revisions     => $posts
    };
}

sub prepared( $profile = 'full', $deadline = FULL_DEADLINE, $options = {} ) {
    local %ENV = ( %ENV, %safe );
    my $now = CLOCK_START;
    my ( $actual, @calls );
    local *GPForum::Performance::ExtremeDatabase::monotonic =
      sub { return $now; };
    local *GPForum::Performance::ExtremeDatabase::run_bounded =
      sub( $command, $arguments ) {
        push @calls, { command => $command, timeout => $arguments->{timeout} };
        croak 'Unexpected command without remaining budget'
          if $arguments->{timeout} <= 0;
        if ( ( $command->[1] // q{} ) eq 'performance-seed' ) {
            my ( undef, undef, undef, %flags ) = @{$command};
            my $current = $flags{'--users'} == FULL_USERS ? 'full' : 'reduced';
            if ( $current eq 'full' && $options->{timeout} ) {
                $now += $arguments->{timeout};
                croak GPForum::Performance::CommandError->new( 'seed deadline',
                    1, 1 );
            }
            if ( $current eq 'full' && $options->{failure} ) {
                croak GPForum::Performance::CommandError->new( 'broken seed',
                    0, 2 );
            }
            $now += 2;
            $actual = $current;
            return JSON::PP->new->encode(
                { status => 'seeded', dataset => counts($current) } );
        }
        return ( 'a' x SHA_LENGTH ) . "\n" if $command->[0] eq 'git';
        $now++;
        return q{};
      };
    local *GPForum::Performance::ExtremeDatabase::_metadata = sub($timeout) {
        $now++;
        my $counts = counts($actual);
        if ( $options->{bad_counts} ) { $counts->{posts}--; }
        return {
            counts       => $counts,
            distribution =>
              { posts_per_thread_min => $counts->{posts_per_thread} },
            postgres            => '16.15',
            application_version => '0.001',
            database_settings   => { max_connections => '100' },
            database_size_bytes => DATABASE_BYTES,
            relation_bytes      => { posts => POSTS_BYTES },
            sql_elapsed_ms      => 0.2
        };
    };
    my $directory = tempdir( CLEANUP => 1 );
    my ( $dataset, $pg ) = prepare( $profile, $directory, $deadline );
    return ( $dataset, $pg, \@calls );
}

sub metrics {
    return {
        connections         => HOST_CPUS,
        active              => 2,
        idle                => 2,
        transactions        => 2,
        idle_in_transaction => 0,
        waiting_active      => 0,
        lock_waits          => 0,
        states_unknown      => 0,
        max_connections     => MAX_CONNECTIONS,
        outbox_pending      => 0,
        outbox_retry        => 0,
        sql_elapsed_ms      => 0.3
    };
}

sub resource( $cpu = undef ) {
    return {
        cpu_percent  => $cpu,
        rss_bytes    => undef,
        span_seconds => undef,
        source       => 'fixture'
    };
}

sub observed( $values = undef, $cpu = undef ) {
    local %ENV = ( %ENV, %safe );
    local *GPForum::Performance::ExtremeDatabase::_database =
      sub { return $values // metrics(); };
    local *GPForum::Performance::ExtremeDatabase::_resources =
      sub { return resource($cpu); };
    local *GPForum::Performance::ExtremeDatabase::_cpu_count =
      sub { return HOST_CPUS; };
    return sample();
}

subtest 'full profile observes 96,000 posts and provenance' => sub {
    my ( $dataset, $pg, $calls ) = prepared();
    is( $dataset->{status}, 'ok', 'requested full profile completed' );
    is( $dataset->{counts}{posts},
        FULL_COUNT, 'larger than ordinary 72,000-post deep profile' );
    is( $dataset->{counts}{threads},  FULL_THREADS, 'actual threads' );
    is( $dataset->{counts}{sessions}, FULL_USERS, 'session presence recorded' );
    is( $dataset->{counts}{unexpired_sessions},
        0, 'expired placeholders do not imply authentication' );
    is( $dataset->{requested_counts}{posts},
        FULL_COUNT, 'requested count explicit' );
    is( $dataset->{seed_duration_seconds}, 2, 'seed time separate' );
    cmp_ok(
        $dataset->{setup_duration_seconds},
        '>',
        $dataset->{seed_duration_seconds},
        'setup includes observation and sync'
    );
    is( $pg->{code_commit}, 'a' x SHA_LENGTH, 'application commit verified' );
    is( $pg->{database_size_bytes}, DATABASE_BYTES, 'observed database size' );
    is( scalar( keys %{ $dataset->{implementation_sha256} } ),
        2, 'both existing seed implementations fingerprinted' );
    is( length( $dataset->{signature} ),
        SIGNATURE_LENGTH, 'deterministic dataset signature' );
    cmp_ok( $calls->[0]{timeout},
        '<=', FULL_ALLOCATION, 'full allocation bounded' );
    is(
        scalar(
            grep { ( $_->{command}[1] // q{} ) eq 'performance-seed' } @{$calls}
        ),
        1,
        'existing seeder runs once'
    );
};
subtest 'timeout rolls back then explicitly reduces within reserve' => sub {
    my ( $dataset, $pg, $calls ) =
      prepared( 'full', FALLBACK_DEADLINE, { timeout => 1 } );
    is( $dataset->{status},            'reduced', 'reduced status' );
    is( $dataset->{requested_profile}, 'full',    'full request retained' );
    is( $dataset->{actual_profile},    'reduced', 'actual profile separate' );
    is( $dataset->{requested_counts}{posts},
        FULL_COUNT, 'requested count retained' );
    is( $dataset->{counts}{posts}, REDUCED_COUNT, 'reduced actual data' );
    is_deeply(
        [ map { $_->{status} } @{ $dataset->{attempts} } ],
        [ 'timed_out', 'ok' ],
        'both attempts described'
    );
    is( $dataset->{seed_duration_seconds},
        BOTH_SEED_SECONDS, 'failed attempt time contributes cost' );
    is( $calls->[0]{timeout}, FULL_ALLOCATION, 'first attempt cap' );
    cmp_ok( $calls->[1]{timeout},
        '<=', SHA_LENGTH, 'fallback preserves metadata reserve' );
    like( $dataset->{reason}, qr/not\s+completed/msx,
        'full capacity not claimed' );
};
subtest 'short setup budget skips full then measures reduced' => sub {
    my ( $dataset, $pg, $calls ) = prepared( 'full', SHORT_DEADLINE );
    is( $dataset->{attempts}[0]{status},
        'skipped', 'full skipped before allocation' );
    is( $dataset->{counts}{posts}, REDUCED_COUNT, 'reduced measured' );
    my ( undef, undef, undef, %flags ) = @{ $calls->[0]{command} };
    is( $flags{'--users'}, REDUCED_USERS,
        'first actual seed uses reduced profile' );
};
subtest 'reduced request is a successful reduced measurement' => sub {
    my ($dataset) = prepared('reduced');
    is( $dataset->{status}, 'ok', 'requested reduced profile completed' );
    is( $dataset->{requested_profile}, 'reduced', 'full was not requested' );
    is( $dataset->{counts}{posts},     REDUCED_COUNT, 'actual reduced count' );
    is( scalar @{ $dataset->{attempts} }, 1, 'no unnecessary first attempt' );
};
subtest 'failure is distinct from deadline reduction' => sub {
    rejected( sub { prepared( 'full', FULL_DEADLINE, { failure => 1 } ); },
        qr/broken\s+seed/msx, 'ordinary failure not relabelled reduced' );
    rejected(
        sub { prepared( 'full', FULL_DEADLINE, { bad_counts => 1 } ); },
        qr/Observed\s+database\s+counts/msx,
        'actual counts must match committed seed'
    );
};
subtest 'expired or invalid setup deadlines do not start a command' => sub {
    local %ENV = ( %ENV, %safe );
    my $directory = tempdir( CLEANUP => 1 );
    my $calls     = 0;
    local *GPForum::Performance::ExtremeDatabase::run_bounded =
      sub { $calls++; return q{}; };
    local *GPForum::Performance::ExtremeDatabase::monotonic =
      sub { return CLOCK_START; };
    rejected( sub { prepare( 'full', $directory, EXPIRED_DEADLINE ); },
        qr/budget/msx, 'expired deadline fails before start' );
    rejected( sub { prepare( 'full', $directory, 'Inf' ); },
        qr/finite/msx, 'infinite deadline refused' );
    is( $calls, 0, 'no command started after deadline' );
};
subtest 'strict named, acknowledged, local DSN' => sub {
    local %ENV = ( %ENV, %safe );
    is( guard(), 'gpforum_perf_extreme_test',
        'owned loopback database accepted' );
    for my $host ( 'localhost', '::1', '127.0.0.1' ) {
        local $ENV{GPFORUM_DATABASE_DSN} =
          'dbi:Pg:dbname=gpforum_perf_extreme_test;host=' . $host;
        is( guard(), 'gpforum_perf_extreme_test', "loopback $host accepted" );
    }
    my $socket = tempdir( DIR => '/tmp', CLEANUP => 1 );
    local $ENV{GPFORUM_DATABASE_DSN} =
      'dbi:Pg:dbname=gpforum_perf_extreme_test;host=' . $socket;
    is( guard(), 'gpforum_perf_extreme_test',
        'owned temporary socket accepted' );
    my @unsafe = (
        'dbi:Pg:dbname=gpforum;host=127.0.0.1',
        'dbi:Pg:dbname=gpforum_perf_head;host=127.0.0.1',
        'dbi:Pg:dbname=gpforum_perf_extreme_test;dbname=gpforum;host=127.0.0.1',
'dbi:Pg:dbname=gpforum_perf_extreme_test;database=gpforum;host=127.0.0.1',
        'dbi:Pg:DBNAME=gpforum_perf_extreme_test;host=127.0.0.1',
        'postgresql://user:secret@localhost/gpforum_perf_extreme_test',
        'dbi:Pg:dbname=gpforum_perf_extreme_test;host=production.example',
'dbi:Pg:dbname=gpforum_perf_extreme_test;host=127.0.0.1;hostaddr=198.51.100.4',
'dbi:Pg:dbname=gpforum_perf_extreme_test;host=127.0.0.1;service=production',
'dbi:Pg:dbname=gpforum_perf_extreme_test;host=127.0.0.1;options=-c search_path=production',
        'dbi:Pg:dbname=gpforum_perf_extreme_test',
        'dbi:Pg:dbname=gpforum_perf_extreme_test;host=/Users',
    );
    for my $dsn (@unsafe) {
        local $ENV{GPFORUM_DATABASE_DSN} = $dsn;
        rejected(
            sub { guard(); },
            qr/extreme|Extreme|PostgreSQL/msx,
            'unsafe DSN refused'
        );
    }
    local $ENV{GPFORUM_EXTREME_DISPOSABLE_DATABASE} = '0';
    rejected( sub { guard(); },
        qr/acknowledgement/msx, 'explicit acknowledgement required' );
};
subtest
  'CPU absence leaves saturation inconclusive even with idle connections' =>
  sub {
    my $report = observed();
    is( $report->{status}, 'ok', 'SQL observer succeeded' );
    is( $report->{metrics}{connections},
        HOST_CPUS, 'observed connection count' );
    ok( !defined $report->{saturated},
        'low connections alone do not prove PostgreSQL headroom' );
    ok( !$report->{resource_headroom_verified}, 'I/O headroom unverified' );
  };
subtest 'saturation derives from measured resource pressure' => sub {
    my $report = observed( metrics(), PG_CPU_PRESSURE );
    ok( $report->{saturated}, 'PG CPU above 85% of four CPUs is saturated' );
    my $busy = metrics();
    $busy->{connections} = CONNECTION_PRESSURE;
    ok( observed($busy)->{saturated}, '90% connection limit is saturated' );
    my $headroom = observed( metrics(), PG_CPU_HEADROOM );
    ok(
        defined $headroom->{saturated} && !$headroom->{saturated},
        'measured low CPU plus no waits allows false saturation'
    );
    ok(
        !$headroom->{resource_headroom_verified},
        'low CPU does not claim unmeasured I/O headroom'
    );
    my $locked = metrics();
    $locked->{lock_waits}     = 1;
    $locked->{waiting_active} = 1;
    observed($locked);
    $locked->{waiting_active} = 2;
    ok( observed($locked)->{saturated},
        'lock waits with rising SQL backlog indicate contention' );
};
subtest 'sampling timeout and invalid metrics produce failed empty evidence' =>
  sub {
    local %ENV                                              = ( %ENV, %safe );
    local *GPForum::Performance::ExtremeDatabase::_database = sub {
        croak GPForum::Performance::CommandError->new( 'sample timeout', 1, 1 );
    };
    my $report = sample();
    is( $report->{status}, 'failed', 'timeout fails observation' );
    ok( $report->{timed_out}, 'typed timeout retained' );
    is_deeply( $report->{metrics}, {}, 'no fake zero counters' );
    {
        local *GPForum::Performance::ExtremeDatabase::_database =
          sub { return { connections => -1 }; };
        my $bad = sample();
        is( $bad->{status}, 'failed', 'invalid observation fails' );
        is_deeply( $bad->{metrics}, {}, 'invalid values are excluded' );
    }
  };
subtest 'sampling errors remove credentials' => sub {
    local %ENV = ( %ENV, %safe, GPFORUM_DATABASE_PASSWORD => 'postgres' );
    local *GPForum::Performance::ExtremeDatabase::_database = sub {
        croak
          'failed postgresql://user:other-password@localhost password=postgres';
    };
    my $report = sample();
    unlike( $report->{reason}, qr/other-password/msx,
        'URI credential removed before colliding environment redaction' );
    unlike( $report->{reason}, qr/password=postgres/msx,
        'database password removed' );
};
subtest 'resource sampler measures deltas without needing FD access' => sub {
    local $ENV{GPFORUM_EXTREME_PG_MASTER_PID} = PG_MASTER;
    my $now   = CLOCK_START;
    my $ticks = PG_CPU_HEADROOM;
    local *GPForum::Performance::ExtremeDatabase::monotonic =
      sub { return $now; };
    local *GPForum::Performance::ExtremeDatabase::_process = sub($pid) {
        return {
            ticks     => $ticks,
            started   => 1,
            rss_bytes => PG_RSS,
            children  => []
        };
    };
    my $first = GPForum::Performance::ExtremeDatabase::_resources();
    ok( !defined $first->{cpu_percent},
        'first CPU observation has no invented delta' );
    $now   += 2;
    $ticks += PG_CPU_HEADROOM;
    my $next_sample = GPForum::Performance::ExtremeDatabase::_resources();
    cmp_ok( $next_sample->{cpu_percent},
        '>', 0, 'second observation measures CPU delta' );
    is( $next_sample->{span_seconds}, 2, 'actual sampling span' );
    is( $next_sample->{rss_bytes},
        PG_RSS, 'RSS retained independently of FD permissions' );
    $ticks = 1;
    ok(
        !defined GPForum::Performance::ExtremeDatabase::_resources()
          ->{cpu_percent},
        'counter restart is not interpreted as negative CPU'
    );
};

{

    # DBI-shaped test double records every statement without opening a DB.
    package GPForum::Performance::TestDatabase;    ## no critic (Modules::ProhibitMultiplePackages)
    use v5.40;
    sub new($class) { return bless { statements => [] }, $class; }
    sub begin_work($self) { push @{ $self->{statements} }, 'BEGIN'; return 1; }

    # DBI's test double implements its real method name.
    sub do( $self, $sql ) { push @{ $self->{statements} }, $sql; return 1; }   ## no critic (Subroutines::ProhibitBuiltinHomonyms)

    sub selectrow_hashref( $self, $sql ) {
        push @{ $self->{statements} }, $sql;
        return { connections => main::HOST_CPUS() };
    }

    sub selectrow_array( $self, $sql ) {
        push @{ $self->{statements} }, $sql;
        return main::MAX_CONNECTIONS();
    }
}
subtest 'SQL sampling is read-only and scoped to its own database' => sub {
    my $database = GPForum::Performance::TestDatabase->new;
    GPForum::Performance::ExtremeDatabase::_snapshot_sql($database);
    my $sql = join "\n", @{ $database->{statements} };
    like(
        $sql,
        qr/SET\s+TRANSACTION\s+READ\s+ONLY/msx,
        'read-only transaction'
    );
    like( $sql, qr/datname=current_database[(][)]/msx, 'this database only' );
    like( $sql, qr/pid<>pg_backend_pid[(][)]/msx,      'observer excluded' );
    like( $sql, qr/statement_timeout\s+=\s+750/msx, 'query duration bounded' );
    unlike(
        $sql,
        qr/SELECT\s+query|INSERT\s|UPDATE\s|DELETE\s/msx,
        'no query text or mutations'
    );
};
done_testing();
1;
