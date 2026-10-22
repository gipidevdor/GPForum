# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;
use v5.40;
use Carp qw(croak);
use FindBin;
use lib "$FindBin::Bin/../../script/lib";
use File::Spec;
use File::Temp qw(tempdir);
use JSON::PP;
use Test::More;
use GPForum::Performance::Budget;
use GPForum::Performance::Extreme;
use GPForum::Performance::ExtremeContainer qw(cleanup start_database);
use GPForum::Performance::ExtremePlan      qw(profiles mixed_weights);
use GPForum::Performance::ExtremeState
  qw(initialize load_state save_state finalize validate_state checkpoint);
use GPForum::Performance::ExtremeWorkload qw(progressive);
use GPForum::Performance::Support         qw(monotonic read_json write_json);
our $VERSION = '0.001';

# Core constants allow tests to run before application dependency installation.
use constant {    ## no critic (ValuesAndExpressions::ProhibitConstantPragma)
    INITIAL_CONCURRENCY      => 10,
    INITIAL_RATE             => 100,
    LATER_RATE               => 90,
    EXPERIMENTAL_CONCURRENCY => 1_000,
    WINDOW_LIMIT             => 30,
    PRIOR_SETUP              => 50,
    REMAINING_JOB            => 1_750,
    REMAINING_MEASUREMENTS   => 1_510,
    REQUESTED_PHASE          => 2_000,
    COMMIT_LENGTH            => 40,
    SKIPPED_SCENARIOS        => 17,
    EXPECTED_RATE_CHANGE     => -10,
    INVALID_METRIC           => -1,
};

sub _output {
    return tempdir( CLEANUP => 1 );
}

sub _clone ($data) {
    return JSON::PP->new->decode( JSON::PP->new->encode($data) );
}

sub _fails ( $code, $description ) {
    my $error;
    try { $code->(); }
    catch ($caught) { $error = $caught; };
    ok( $error, $description );
    return $error;
}

sub _measurement {
    return {
        scenario       => 'thread',
        status         => 'ok',
        concurrency    => INITIAL_CONCURRENCY,
        classification => 'observed-capacity',
        evidence       => {},
        metrics        => {
            completed             => INITIAL_RATE,
            duration_seconds      => 1,
            requests_per_second   => INITIAL_RATE,
            p50_ms                => 1,
            p95_ms                => 2,
            p99_ms                => 3,
            http_errors           => 0,
            transport_errors      => 0,
            timeouts              => 0,
            concurrency_effective => undef
        }
    };
}

is_deeply(
    mixed_weights(),
    {
        thread   => PRIOR_SETUP,
        category => 20,
        home     => 15,
        search   => INITIAL_CONCURRENCY,
        other    => 5
    },
    'default request weights'
);
for my $input (
    'thread=100',
    'thread=50,category=20,home=15,search=10,other=5,thread=0',
    'thread=50,category=20,home=15,search=10,other=-1'
  )
{
    _fails( sub { mixed_weights($input); },
        'invalid/duplicate configuration refused' );
}
is( profiles()->{full}{levels}[-1],
    EXPERIMENTAL_CONCURRENCY, 'experimental progressive level planned' );
cmp_ok( profiles()->{full}{window_seconds},
    '<=', WINDOW_LIMIT, 'mixed/soak windows fit the shared generator bound' );

my $now    = monotonic();
my $budget = GPForum::Performance::Budget->new(
    {
        started_monotonic              => $now - PRIOR_SETUP,
        deadline_monotonic             => $now + REMAINING_JOB,
        measurement_deadline_monotonic => $now + REMAINING_MEASUREMENTS
    }
);
cmp_ok( $budget->elapsed, '>=', PRIOR_SETUP,
    'setup already elapsed is included' );
cmp_ok( $budget->remaining, '<=', REMAINING_MEASUREMENTS,
    'remaining budget excludes report reserve' );
is(
    $budget->phase(REQUESTED_PHASE),
    $budget->{measurement_deadline},
    'phase clamped to global deadline'
);
_fails(
    sub {
        GPForum::Performance::Budget->new( { deadline_monotonic => 'NaN' } );
    },
    'non-finite clock rejected'
);
_fails(
    sub {
        GPForum::Performance::Budget->new(
            { started_monotonic => 0, deadline_monotonic => 1_801 } );
    },
    'over-30-minute clock rejected'
);

my $output = _output();
initialize( $output, 'reduced', 'a' x COMMIT_LENGTH );
_fails(
    sub { initialize( $output, 'reduced' ); },
    'run attempt initialization is immutable'
);
my $skipped = finalize($output);
is( $skipped->{status}, 'skipped', 'no execution never passes' );
is_deeply( $skipped->{measurements}, [], 'no invented empty measurement' );
ok( -f File::Spec->catfile( $output, 'report.md' ),
    'skipped evidence rendered' );
is_deeply( finalize($output), $skipped,
    'finalization is immutable/idempotent' );
_fails(
    sub { GPForum::Performance::Extreme::execute( $output, 'reduced', 0, 1 ); },
    'completed attempt cannot execute again'
);
is( GPForum::Performance::Extreme::main( 'check', '--output', $output ),
    1, 'unexecuted run remains nonzero' );

for my $mutation (
    sub ($state) { $state->{status}             = 'ok'; },
    sub ($state) { $state->{commit}             = 'invalid'; },
    sub ($state) { $state->{versions}{password} = 'private'; },
  )
{
    my $state = _clone($skipped);
    $mutation->($state);
    _fails( sub { validate_state($state); },
        'schema/secret/false-pass mutation refused' );
}

$output = _output();
my $state = initialize( $output, 'reduced', 'b' x COMMIT_LENGTH );
checkpoint( $output, $state, _measurement(), 'progressive', 1 );
checkpoint(
    $output, $state,
    {
        scenario       => 'thread',
        status         => 'failed',
        concurrency    => PRIOR_SETUP,
        classification => 'inconclusive',
        metrics        => {},
        evidence       => { validation_error => 'generator exited' }
    },
    'progressive',
    2
);
my $partial = finalize($output);
is( $partial->{status}, 'failed', 'generator failure remains visible' );
is( $partial->{measurements}[0]{metrics}{completed},
    INITIAL_RATE, 'valid earlier metrics preserved' );
is_deeply( $partial->{measurements}[1]{metrics},
    {}, 'failed cell has no invented metrics' );

$output = _output();
initialize( $output, 'reduced', 'c' x COMMIT_LENGTH );
{
    local $ENV{EXTREME_SETUP} = 'failure';
    my $failed = finalize($output);
    is( $failed->{status}, 'failed',
        'dependency failure without HTTP data is visible' );
    is( $failed->{phases}{setup}{status},
        'failed', 'workflow setup outcome included' );
}

$output = _output();
$state  = initialize( $output, 'reduced', 'd' x COMMIT_LENGTH );
my $context = {
    output     => $output,
    state      => $state,
    server_for => sub { croak 'expired plan must not start a server'; },
    pg_sampler => undef
};
progressive( $context, monotonic() - 1 );
is( scalar @{ $state->{measurements} },
    0, 'deadline prevents starting any generator' );
is( $state->{phases}{progressive}{status},
    'partial', 'expired progression is explicitly incomplete' );
is( scalar @{ $state->{skipped} },
    SKIPPED_SCENARIOS,
    'all 8 endpoints and 2 levels plus authentication skipped explicitly' );

$output = _output();
$state  = initialize( $output, 'reduced', 'e' x COMMIT_LENGTH );
$state->{owned_container} = 'unrelated-production';
save_state( $output, $state );
ok( !cleanup($output), 'cleanup refuses a foreign container' );
like(
    load_state($output)->{phases}{cleanup}{reason},
    qr/identity[ ]mismatch/msx,
    'cleanup mismatch retained'
);

$output = _output();
$state  = initialize( $output, 'reduced', 'f' x COMMIT_LENGTH );
for my $repetition ( 1, 2 ) {
    my $row = _measurement();
    $row->{scenario} = 'mixed';
    $row->{metrics}{requests_per_second} =
      $repetition == 1 ? INITIAL_RATE : LATER_RATE;
    checkpoint( $output, $state, $row, 'soak', $repetition );
}
my $trend = finalize($output)->{soak_trend};
is( $trend->{status}, 'indicative', 'short soak trend is descriptive' );
is( $trend->{first_to_last_percent}{requests_per_second},
    EXPECTED_RATE_CHANGE, 'actual trend delta calculated' );

$output = _output();
$state  = initialize( $output, 'reduced', 'a' x COMMIT_LENGTH );
$state->{dataset}{status} = 'ok';
for my $phase ( values $state->{phases}->%* ) {
    $phase->{status} = 'ok';
    $phase->{reason} = 'Simulated completed phase';
}
checkpoint( $output, $state, _measurement(), 'progressive', 1 );
my $successful = finalize($output);
is( $successful->{status}, 'ok',
    'complete simulated lifecycle generates valid success report' );
for my $mutation (
    sub ($value) { $value->{dataset}{status} = 'reduced'; },
    sub ($value) { $value->{measurements}[0]{metrics}{completed} = 0; },
    sub ($value) {
        $value->{measurements}[0]{metrics}{p95_ms} = INVALID_METRIC;
    },
    sub ($value) { delete $value->{measurements}[0]{metrics}{p99_ms}; },
  )
{
    my $value = _clone($successful);
    $mutation->($value);
    _fails( sub { validate_state($value); },
        'false completion or missing/corrupt metric refused' );
}

subtest
  'owned PostgreSQL uses a Unix socket and removes its owned directory' => sub {
    my $directory = _output();
    my $run       = initialize( $directory, 'reduced', 'e' x COMMIT_LENGTH );
    my @commands;
    local *GPForum::Performance::ExtremeContainer::run_bounded =
      sub ( $command, @ ) {
        push @commands, $command;
        return 'sha256:fixture' if join( q{ }, @{$command} ) =~ /Image/msx;
        return '101' if join( q{ }, @{$command} ) =~ /State[.]Pid/msx;
        return q{};
      };
    my $environment =
      start_database( $directory, $run, monotonic() + REMAINING_JOB );
    like(
        $environment->{GPFORUM_DATABASE_DSN},
        qr{host=/tmp/gpforum-extreme-pg-[[:xdigit:]]+/socket;port=5432}msx,
        'the application connects to the host-mounted socket'
    );
    my $command = join q{ }, @{ $commands[0] };
    unlike( $command, qr/--publish/msx, 'no PostgreSQL TCP port is published' );
    like( $command, qr/listen_addresses=/msx, 'the owned server disables TCP' );
    like( $command, qr{PGHOST=/gpforum-socket}msx,
        'container readiness and initialization use that same socket' );
    my $owned = $run->{owned_socket_directory};
    ok( -d $owned, 'the temporary socket directory belongs to this attempt' );
    ok( cleanup($directory), 'cleanup succeeds' );
    ok( !-e $owned,
        'the owned socket directory is removed after the container' );
  };

done_testing;
1;
