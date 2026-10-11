# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Performance::ExtremeWorkload;

use v5.40;
use Exporter qw(import);
use File::Spec;
use List::Util   qw(max min);
use Scalar::Util qw(looks_like_number);
use GPForum::Performance::ExtremeLoad
  qw(measure classify stop_reason allow_1000);
use GPForum::Performance::ExtremeState qw(skip checkpoint save_state);
use GPForum::Performance::Support      qw(monotonic);

# These admission limits are also needed before dependency setup in tests.
use constant {    ## no critic (ValuesAndExpressions::ProhibitConstantPragma)
    CELL_RESERVE_SECONDS           => 12,
    EXPERIMENTAL_CONNECTIONS       => 1_000,
    QUALIFYING_CONNECTIONS         => 500,
    SPIKE_RECOVERY_RESERVE_SECONDS => 45,
    SPIKE_CONNECTION_CAP           => 100,
    SPIKE_PHASE_SECONDS            => 30,
};

our $VERSION   = '0.001';
our @EXPORT_OK = qw(progressive windows spike);

sub _median (@values) {
    @values = sort { $a <=> $b } @values;
    my $middle = int( @values / 2 );
    return @values % 2
      ? $values[$middle]
      : ( $values[ $middle - 1 ] + $values[$middle] ) / 2;
}

sub _point ($rows) {
    my %point = %{ $rows->[-1] };
    my %metrics;
    my %names = map {
        map { $_ => 1 }
          keys %{ $_->{metrics} }
    } @{$rows};
    for my $name ( keys %names ) {
        my @values = map { $_->{metrics}{$name} } grep {
            defined $_->{metrics}{$name}
              && looks_like_number( $_->{metrics}{$name} )
        } @{$rows};
        if (@values) { $metrics{$name} = _median(@values); }
    }
    $point{metrics} = \%metrics;
    return \%point;
}

sub _run_point ( $context, $scenario, $concurrency, $deadline, $previous ) {
    my ( $state, $output ) = @{$context}{qw(state output)};
    my $plan = $state->{configuration}{plan};
    my ( @current, $stopped );
    for my $repetition ( 1 .. $plan->{repetitions} ) {
        if (
            $deadline - monotonic() < $plan->{duration} + CELL_RESERVE_SECONDS )
        {
            $stopped =
              'Progressive/global monotonic deadline; no new cell started';
            skip( $state, $scenario, $stopped,
                { concurrency => $concurrency, repetition => $repetition } );
            last;
        }
        my $server = $context->{server_for}
          ->( $scenario eq 'cache_miss' ? 'miss' : 'normal' );
        my $row = measure(
            $server,
            {
                scenario    => $scenario,
                concurrency => $concurrency,
                duration    => $plan->{duration},
                deadline    => $deadline,
                diagnostics => File::Spec->catdir( $output, 'diagnostics' ),
                pg_sampler  => $context->{pg_sampler}
            }
        );
        $row->{classification} =
          classify( $row->{metrics}, $row->{evidence}, $previous );
        checkpoint( $output, $state, $row, 'progressive', $repetition );
        push @current, $row;
        if ( !keys %{ $row->{metrics} } ) {
            $stopped =
'Generator or measurement infrastructure failure; later levels skipped';
            last;
        }
    }
    return ( \@current, $stopped );
}

sub _scenario ( $context, $scenario, $deadline ) {
    my ( $state, $previous, $stopped, $complete ) =
      ( $context->{state}, undef, undef, 1 );
    my $rows500 = [];
    for my $concurrency ( @{ $state->{configuration}{plan}{levels} } ) {
        if ($stopped) {
            skip( $state, $scenario, $stopped,
                { concurrency => $concurrency } );
            $complete = 0;
            next;
        }
        if ( $concurrency == EXPERIMENTAL_CONNECTIONS ) {
            my ( $allowed, $reason ) = allow_1000($rows500);
            if ( !$allowed ) {
                skip( $state, $scenario, $reason,
                    { concurrency => $concurrency } );
                $complete = 0;
                next;
            }
        }
        my ( $current, $stop ) =
          _run_point( $context, $scenario, $concurrency, $deadline, $previous );
        if ($stop) { $stopped = $stop; $complete = 0; }
        next if !@{$current};
        my $point = _point($current);
        if ( my $reason = stop_reason( $point, $previous ) ) {
            $stopped  = $reason;
            $complete = 0;
            push @{ $state->{saturation} },
              {
                scenario       => $scenario,
                concurrency    => $concurrency,
                classification => $point->{classification},
                reason         => $reason
              };
        }
        $previous = $point;
        if ( $concurrency == QUALIFYING_CONNECTIONS ) { $rows500 = $current; }
    }
    return $complete;
}

sub progressive ( $context, $deadline ) {
    my $complete = 1;
    for my $scenario (
        qw(health_live home categories category thread search cache_hit cache_miss)
      )
    {
        if ( !_scenario( $context, $scenario, $deadline ) ) { $complete = 0; }
        save_state( $context->{output}, $context->{state} );
    }
    $context->{state}{phases}{progressive} = {
        status => $complete ? 'ok' : 'partial',
        reason =>
'Separate real endpoints; bounded progression; skipped levels and observed stops are explicit'
    };
    save_state( $context->{output}, $context->{state} );
    return undef;
}

sub windows ( $context, $server, $phase, $deadline, $count, $duration,
    $concurrency )
{
    my ( $completed, $stopped ) = ( 0, 0 );
    for my $index ( 1 .. $count ) {
        if ( $deadline - monotonic() < $duration + CELL_RESERVE_SECONDS ) {
            skip(
                $context->{state}, $phase,
                'Phase/global deadline; no new window started',
                { remaining_windows => $count - $completed }
            );
            last;
        }
        my $row = measure(
            $server,
            {
                scenario    => 'mixed',
                concurrency => $concurrency,
                duration    => $duration,
                deadline    => $deadline,
                diagnostics =>
                  File::Spec->catdir( $context->{output}, 'diagnostics' ),
                weights    => $context->{state}{configuration}{mixed_weights},
                pg_sampler => $context->{pg_sampler}
            }
        );
        $row->{classification} = classify( $row->{metrics}, $row->{evidence} );
        checkpoint( $context->{output}, $context->{state}, $row, $phase,
            $index );
        $completed++;
        if ( my $reason = stop_reason($row) ) {
            skip(
                $context->{state}, $phase,
                "Later windows stopped: $reason",
                { remaining_windows => $count - $completed }
            );
            $stopped = 1;
            last;
        }
    }
    $context->{state}{phases}{$phase} = {
        status => $completed == $count
          && !$stopped ? 'ok' : $completed ? 'partial' : 'skipped',
        completed_windows => $completed,
        planned_windows   => $count,
        concurrency       => $concurrency,
        reason            =>
          'Windowed weighted anonymous reads; connections reset between windows'
    };
    save_state( $context->{output}, $context->{state} );
    return undef;
}

sub spike ( $context, $server, $concurrency ) {
    my $state    = $context->{state};
    my $duration = $state->{configuration}{plan}{spike_seconds};
    if (  !$server
        || $context->{budget}->remaining <
        $duration + SPIKE_RECOVERY_RESERVE_SECONDS )
    {
        skip( $state, 'spike', 'Insufficient budget for spike plus recovery' );
        return undef;
    }
    my @valid =
      map  { $_->{concurrency} }
      grep { $_->{status} eq 'ok' && $_->{scenario} eq 'thread' }
      @{ $state->{measurements} };
    my $peak = min( SPIKE_CONNECTION_CAP, max( $concurrency, @valid ) );
    my $row  = measure(
        $server,
        {
            scenario    => 'mixed',
            concurrency => $peak,
            duration    => $duration,
            deadline    => $context->{budget}->phase(SPIKE_PHASE_SECONDS),
            diagnostics =>
              File::Spec->catdir( $context->{output}, 'diagnostics' ),
            weights    => $state->{configuration}{mixed_weights},
            pg_sampler => $context->{pg_sampler}
        }
    );
    $row->{classification} = classify( $row->{metrics}, $row->{evidence} );
    checkpoint( $context->{output}, $state, $row, 'spike', 1 );
    $state->{phases}{spike} = {
          status => $row->{status} eq 'ok' ? 'ok'
        : keys %{ $row->{metrics} } ? 'partial'
        : 'failed',
        reason      => 'Bounded spike below an already tested connection count',
        concurrency => $peak
    };
    return undef;
}

1;
