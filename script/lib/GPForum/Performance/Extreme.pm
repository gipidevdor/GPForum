# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Performance::Extreme;

use v5.40;
use Carp       qw(croak);
use File::Path qw(make_path);
use File::Spec;
use Getopt::Long qw(GetOptionsFromArray);
use JSON::PP;
use List::Util qw(min);
use GPForum::Performance::Budget;
use GPForum::Performance::ExtremeContainer qw(start_database cleanup);
use GPForum::Performance::ExtremeDatabase  qw(guard prepare sample);
use GPForum::Performance::ExtremeLoad      qw(recovery);
use GPForum::Performance::ExtremePlan      qw(profiles choose_safe);
use GPForum::Performance::ExtremeState
  qw(initialize load_state save_state skip finalize validate_state);
use GPForum::Performance::ExtremeWorkload qw(progressive windows spike);
use GPForum::Performance::HTTP            qw(wrk_version probe_reactor);
use GPForum::Performance::Server;
use GPForum::Performance::Support qw(read_json run_bounded redact);

# The initializer and partial renderer must load without the CPAN tree.
use constant {    ## no critic (ValuesAndExpressions::ProhibitConstantPragma)
    SETUP_SECONDS         => 300,
    MIGRATION_SECONDS     => 45,
    REACTOR_START_RESERVE => 35,
    REACTOR_PROBE_SECONDS => 5,
    WINDOW_RESERVE        => 12,
    RECOVERY_MINIMUM      => 5,
    RECOVERY_MAXIMUM      => 20,
};

our $VERSION = '0.001';

sub _setup ( $context, $docker ) {
    my ( $state, $budget, $output ) = @{$context}{qw(state budget output)};
    my $deadline = min( $budget->{started} + SETUP_SECONDS,
        $budget->{measurement_deadline} );
    make_path( File::Spec->catdir( $output, 'diagnostics' ) );
    $context->{environment} = {};
    if ($docker) {
        $context->{environment} = start_database( $output, $state, $deadline );
    }
    else {
        guard();
        push @{ $state->{limitations} },
'Local caller owns disposable PostgreSQL cluster; a pre-existing database is not dropped by this coordinator.';
    }
    local %ENV = ( %ENV, %{ $context->{environment} } );
    run_bounded(
        [ 'script/gpforum-carton', 'exec', 'bin/gpforum-migrate', '--apply' ],
        {
            timeout => min( MIGRATION_SECONDS, $budget->remaining($deadline) ),
            log     => File::Spec->catfile( $output, 'diagnostics/migrate.log' )
        }
    );
    my ( $dataset, $pg ) =
      prepare( $state->{profile}, File::Spec->catdir( $output, 'diagnostics' ),
        $deadline );
    $state->{dataset}  = $dataset;
    $state->{versions} = {
        %{ $state->{versions} },
        %{$pg},
        wrk => wrk_version( File::Spec->catdir( $output, 'diagnostics' ) )
    };
    my $selected = 'Poll';
    for my $backend (qw(EV Poll)) {
        croak 'No remaining budget for reactor verification'
          if $budget->remaining < REACTOR_START_RESERVE;
        if (
            probe_reactor(
                $backend, File::Spec->catdir( $output, 'diagnostics' ),
                REACTOR_PROBE_SECONDS
            )
          )
        {
            $selected = $backend;
            last;
        }
        skip( $state, "reactor_$backend",
            'Requested backend unavailable in the actual runtime probe' );
    }
    $context->{selected_reactor}               = $selected;
    $state->{configuration}{reactor_requested} = $selected;
    $state->{phases}{setup}                    = {
        status          => $dataset->{status} eq 'ok' ? 'ok' : 'partial',
        elapsed_seconds => $budget->elapsed,
        reason          =>
'Owned PostgreSQL migrated and deterministic data committed; seed time excludes HTTP. '
          . ( $dataset->{reason} // 'Requested dataset completed.' )
    };
    save_state( $output, $state );
    return undef;
}

sub _server ( $context, $cache_mode ) {
    my $server = $context->{server};
    return $server if $server && $server->{cache_mode} eq $cache_mode;
    if ($server) { $server->close; }
    $context->{server_index}++;
    $server = GPForum::Performance::Server->new(
        {
            output     => $context->{output},
            reactor    => $context->{selected_reactor},
            workers    => 2,
            cache_mode => $cache_mode,
            index      => $context->{server_index},
            deadline   => $context->{budget}{measurement_deadline}
        }
    );
    $context->{server} = $server;
    my $telemetry = $server->telemetry;
    @{ $context->{state}{versions} }{qw(perl mojolicious)} =
      @{ $telemetry->[0] }{qw(perl mojolicious)};
    @{ $context->{state}{configuration} }{qw(reactor_actual ev_backend)} =
      @{ $telemetry->[0] }{qw(reactor ev_backend)};
    save_state( $context->{output}, $context->{state} );
    return $server;
}

sub _window_phase ( $context, $phase, $concurrency ) {
    my $plan   = $context->{state}{configuration}{plan};
    my $needed = $plan->{window_seconds} +
      ( $phase eq 'mixed' ? REACTOR_START_RESERVE : WINDOW_RESERVE );
    if ( $context->{budget}->remaining < $needed ) {
        skip( $context->{state}, $phase,
            'Global deadline or server unavailable' );
        return undef;
    }
    my $server =
      $phase eq 'mixed' ? _server( $context, 'normal' ) : $context->{server};
    if ( !$server ) {
        skip( $context->{state}, $phase, 'Server unavailable' );
        return undef;
    }
    windows(
        $context,
        $server,
        $phase,
        $context->{budget}->phase( $plan->{ $phase . '_seconds' } ),
        $plan->{ $phase . '_windows' },
        $plan->{window_seconds},
        $concurrency
    );
    return undef;
}

sub _recover ($context) {
    if (  !$context->{server}
        || $context->{budget}->remaining < RECOVERY_MINIMUM )
    {
        skip( $context->{state}, 'recovery',
            'Global deadline or server unavailable' );
        return undef;
    }
    $context->{state}{phases}{recovery} = recovery(
        $context->{server},
        {
            deadline   => $context->{budget}{measurement_deadline},
            maxseconds => min( RECOVERY_MAXIMUM, $context->{budget}->remaining )
        }
    );
    return undef;
}

sub _cleanup_context ( $output, $server ) {
    local $SIG{TERM} = 'IGNORE';
    local $SIG{INT}  = 'IGNORE';
    return cleanup( $output, $server );
}

sub execute ( $output, $profile, $docker, $disposable ) {
    my $state = load_state($output);
    croak 'Immutable run already started; initialize a distinct attempt'
      if $state->{started} || $state->{finalized};
    croak 'Profile does not match initialized evidence'
      if $state->{profile} ne $profile;
    croak 'Explicit --disposable-database acknowledgement required'
      if !$disposable;
    $state->{started} = JSON::PP::true;
    save_state( $output, $state );
    my $context = {
        output => $output,
        state  => $state,
        budget => GPForum::Performance::Budget->new(
            read_json( File::Spec->catfile( $output, 'clock.json' ) )
        ),
        server_index => 0,
        pg_sampler   => sub { return sample(); }
    };
    $context->{server_for} = sub ($mode) { return _server( $context, $mode ); };
    local $ENV{GPFORUM_EXTREME_DISPOSABLE_DATABASE} = '1';
    local $SIG{TERM} = sub { croak 'Stress interrupted by SIGTERM'; };
    local $SIG{INT}  = sub { croak 'Stress interrupted by SIGINT'; };
    my ( $failure, $active ) = ( undef, 'setup' );
    try {
        _setup( $context, $docker );
        local %ENV = ( %ENV, %{ $context->{environment} } );
        $active = 'progressive';
        progressive( $context,
            $context->{budget}
              ->phase( $state->{configuration}{plan}{progressive_seconds} ) );
        my $concurrency = choose_safe( $state->{measurements} );
        $active = 'mixed';
        _window_phase( $context, 'mixed', $concurrency );
        $active = 'soak';
        _window_phase( $context, 'soak', $concurrency );
        $active = 'spike';
        spike( $context, $context->{server}, $concurrency );
        $active = 'recovery';
        _recover($context);
        save_state( $output, $state );
    }
    catch ($error) {
        $failure                  = redact($error);
        $state                    = load_state($output);
        $state->{phases}{$active} = {
            status       => 'failed',
            failure_kind => 'infrastructure_or_harness',
            reason       => $failure
        };
        push @{ $state->{limitations} },
          "Remaining phases not executed after: $failure";
        save_state( $output, $state );
    };
    _cleanup_context( $output, $context->{server} );
    return $failure ? 1 : 0;
}

sub _options (@arguments) {
    my %option = ( profile => 'reduced' );
    GetOptionsFromArray(
        \@arguments,
        'output=s'             => \$option{output},
        'profile=s'            => \$option{profile},
        'commit=s'             => \$option{commit},
        'docker!'              => \$option{docker},
        'disposable-database!' => \$option{disposable}
    ) or croak 'Invalid extreme command options';
    croak 'An output directory is required' if !$option{output} || @arguments;
    croak 'Unknown extreme profile' if !exists profiles()->{ $option{profile} };
    $option{output} = File::Spec->rel2abs( $option{output} );
    return \%option;
}

sub _check ( $output, $action ) {
    my $state = load_state($output);
    validate_state($state);
    croak 'Report not finalized'
      if !$state->{finalized}
      || !-f File::Spec->catfile( $output, 'report.md' );
    return $action eq 'check'
      && ( $state->{status} eq 'failed' || $state->{status} eq 'skipped' )
      ? 1
      : 0;
}

sub main (@arguments) {
    my $action = shift @arguments // q{};
    my %option = %{ _options(@arguments) };
    my $output = $option{output};
    return execute( $output, @option{qw(profile docker disposable)} )
      if $action eq 'run';
    return cleanup($output) ? 0 : 1 if $action eq 'cleanup';

    if ( $action eq 'init' ) {
        initialize( $output, @option{qw(profile commit)} );
        return 0;
    }
    if ( $action eq 'finalize' ) { finalize($output); return 0; }
    if ( $action eq 'validate' || $action eq 'check' ) {
        return _check( $output, $action );
    }
    croak 'Action must be init/run/cleanup/finalize/validate/check';
}

1;
