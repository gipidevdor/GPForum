# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Performance::ExtremeState;

use v5.40;
use Carp        qw(croak);
use Digest::SHA qw(sha256_hex);
use Exporter    qw(import);
use File::Path  qw(make_path);
use File::Spec;
use JSON::PP;
use List::Util qw(any);
use GPForum::Performance::Budget;
use GPForum::Performance::Evidence    qw(initial schema_validate secrets);
use GPForum::Performance::ExtremePlan qw(profiles mixed_weights);
use GPForum::Performance::Support qw(root_dir read_json write_json monotonic);

# Core constants keep failure reports available before dependency installation.
use constant {    ## no critic (ValuesAndExpressions::ProhibitConstantPragma)
    AUTH_LIMITATION => 4,
    PERCENT_TOTAL   => 100,
};

our $VERSION = '0.001';
our @EXPORT_OK =
  qw(initialize load_state save_state skip checkpoint finalize validate_state);

sub _limitations {
    return [
'Generator, Hypnotoad and PostgreSQL share a runner; observed CI capacity is not certified production capacity.',
'wrk connections are requested TCP connections, not virtual users; actual in-flight concurrency is unknown.',
'Two progressive repetitions can locate possible saturation, but cannot confirm a revision regression.',
'Mixed/soak latency is aggregate; connections restart between measured windows.',
'Authentication and writes skipped: synthetic password hashes and expired sessions are not a safe session/CSRF fixture.',
'No cross-revision baseline; ordinary performance comparisons and deterministic CI gates remain separate.',
'RSS sums double-count shared pages; sampled peaks and CPU deltas are approximate.',
'Runner loss or SIGKILL can prevent reporting; checkpoints and disposable container ownership bound the impact.',
    ];
}

sub load_state ($output) {
    return read_json( File::Spec->catfile( $output, 'extreme.json' ) );
}

sub save_state ( $output, $state ) {
    secrets($state);
    return write_json( File::Spec->catfile( $output, 'extreme.json' ), $state );
}

sub _clock ($output) {
    my $path = File::Spec->catfile( $output, 'clock.json' );
    return read_json($path) if -f $path;
    my $budget = GPForum::Performance::Budget->new;
    my $clock  = {
        schema_version                 => 1,
        kind                           => 'clock',
        source                         => 'local monotonic',
        started_monotonic              => $budget->{started},
        deadline_monotonic             => $budget->{deadline},
        measurement_deadline_monotonic => $budget->{measurement_deadline},
        limitations                    => []
    };
    write_json( $path, $clock );
    return $clock;
}

sub initialize ( $output, $profile, $commit = undef ) {
    croak 'Unknown extreme profile' if !exists profiles()->{$profile};
    make_path($output);
    croak 'Run already initialized; use a distinct run/attempt directory'
      if -e File::Spec->catfile( $output, 'extreme.json' );
    my $clock  = _clock($output);
    my $budget = GPForum::Performance::Budget->new($clock);
    my $state  = initial( 'deep', $commit );
    delete @{$state}{qw(mode history_url artifact_url)};
    $state->{kind}          = 'extreme';
    $state->{profile}       = $profile;
    $state->{status}        = 'skipped';
    $state->{configuration} = {
        plan          => profiles()->{$profile},
        workers       => 2,
        mixed_weights => mixed_weights( $ENV{EXTREME_MIX_WEIGHTS} ),
        read_only     => JSON::PP::true,
        publication   => 'immutable GitHub artifact only'
    };
    $state->{budget} = {
        maximum_seconds                => 1_800,
        report_cleanup_reserve_seconds => 240,
        clock_source                   => $clock->{source},
        elapsed_seconds                => $budget->elapsed
    };
    $state->{phases} =
      { map { $_ => { status => 'skipped', reason => 'Not executed' } }
          qw(setup progressive mixed soak spike recovery cleanup) };
    $state->{measurements} = [];
    $state->{skipped}      = [
        {
            scenario => 'authenticated_writes',
            reason   => _limitations()->[AUTH_LIMITATION]
        }
    ];
    $state->{limitations} =
      [ @{ _limitations() }, @{ $clock->{limitations} // [] } ];
    $state->{started}   = JSON::PP::false;
    $state->{finalized} = JSON::PP::false;
    return save_state( $output, $state );
}

sub skip ( $state, $scenario, $reason, $config = {} ) {
    push @{ $state->{skipped} },
      { scenario => $scenario, reason => $reason, %{$config} };
    return undef;
}

sub checkpoint ( $output, $state, $row, $phase, $repetition ) {
    @{$row}{qw(phase repetition)} = ( $phase, $repetition );
    push @{ $state->{measurements} }, $row;
    save_state( $output, $state );
    return $row;
}

sub _trends ($state) {
    my @rows = grep { $_->{phase} eq 'soak' && keys %{ $_->{metrics} } }
      @{ $state->{measurements} };
    return {
        status => 'not-comparable',
        reason => 'Fewer than two measured soak windows'
      }
      if @rows < 2;
    my ( $first, $last_metrics ) = ( $rows[0]{metrics}, $rows[-1]{metrics} );
    my %changes;
    for my $metric (qw(requests_per_second p95_ms p99_ms rss_bytes)) {
        next if !$first->{$metric} || !defined $last_metrics->{$metric};
        $changes{$metric} = 0 + sprintf '%.3f',
          PERCENT_TOTAL * ( $last_metrics->{$metric} / $first->{$metric} - 1 );
    }
    return {
        status                => 'indicative',
        windows               => scalar @rows,
        first_to_last_percent => \%changes,
        reason                =>
'Descriptive short window trend; no proof of a memory leak or production capacity'
    };
}

sub _validate_measurement ($row) {
    return 1 if $row->{status} ne 'ok';
    for my $metric (
        qw(completed duration_seconds requests_per_second p50_ms p95_ms p99_ms http_errors transport_errors timeouts concurrency_effective)
      )
    {
        croak "Successful measurement lacks recorded $metric"
          if !exists $row->{metrics}{$metric};
    }
    croak 'Successful measurement requires actual requests and duration'
      if ( $row->{metrics}{completed} // 0 ) <= 0
      || ( $row->{metrics}{duration_seconds} // 0 ) <= 0;
    return 1;
}

sub validate_state ($state) {
    schema_validate(
        $state,
        read_json(
            File::Spec->catfile(
                root_dir(), 'benchmarks/extreme-schema-v1.json'
            )
        )
    );
    secrets($state);
    if ( $state->{status} eq 'ok' ) {
        croak
          'Reduced or unverified dataset cannot complete the requested profile'
          if ( $state->{dataset}{status} // 'unverified' ) ne 'ok';
        croak 'Unexecuted phase cannot be PASS'
          if !@{ $state->{measurements} }
          || any { $_->{status} ne 'ok' } values %{ $state->{phases} };
    }
    for my $row ( @{ $state->{measurements} } ) {
        _validate_measurement($row);
    }
    return 1;
}

sub _workflow_outcomes ($state) {
    my %phases = (
        EXTREME_SETUP     => 'setup',
        EXTREME_TOOLS     => 'setup',
        EXTREME_CONTRACTS => 'setup',
        EXTREME_WORKLOAD  => 'progressive',
        EXTREME_CLEANUP   => 'cleanup',
    );
    for my $name ( sort keys %phases ) {
        my $outcome = $ENV{$name} // q{};
        next if $outcome ne 'failure' && $outcome ne 'cancelled';
        $state->{phases}{ $phases{$name} } = {
            status       => 'failed',
            failure_kind => 'infrastructure_or_harness',
            reason       => "$name: $ENV{$name}"
        };
    }
    return undef;
}

sub _summarize_phases ($state) {
    for my $phase ( sort keys %{ $state->{phases} } ) {
        next
          if $state->{phases}{$phase}{status} ne 'skipped'
          || any { $_->{scenario} eq $phase } @{ $state->{skipped} };
        skip( $state, $phase, $state->{phases}{$phase}{reason} );
    }
    my $failed =
      ( grep { !keys %{ $_->{metrics} } || $_->{evidence}{validation_error} }
          @{ $state->{measurements} } )
      || ( grep { $_->{status} eq 'failed' } values %{ $state->{phases} } );
    my $partial =
      grep { $_->{status} eq 'partial' || $_->{status} eq 'skipped' }
      values %{ $state->{phases} };
    $state->{status} =
        $failed                      ? 'failed'
      : !@{ $state->{measurements} } ? 'skipped'
      : $partial                     ? 'partial'
      :                                'ok';
    return $failed;
}

sub finalize ($output) {
    my $state = load_state($output);
    return $state if $state->{finalized};
    _workflow_outcomes($state);
    my $failed = _summarize_phases($state);
    $state->{soak_trend} = _trends($state);
    $state->{budget}{elapsed_seconds} =
      GPForum::Performance::Budget->new( _clock($output) )->elapsed;
    my $count = scalar @{ $state->{measurements} };
    $state->{conclusion} = "Collected $count observations. "
      . (
        $failed
        ? 'Infrastructure/harness or recovery failure requires inspection; valid observations remain visible.'
        : $count
        ? 'Observed stops apply to this colocated runner; no revision regression or production user capacity is established.'
        : 'No benchmark executed; no capacity evidence is available.'
      );
    $state->{finalized} = JSON::PP::true;
    validate_state($state);
    save_state( $output, $state );
    require GPForum::Performance::ExtremeReport;
    GPForum::Performance::ExtremeReport::write_report( $output, $state );
    return $state;
}

1;
