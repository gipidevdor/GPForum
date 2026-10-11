# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause
package GPForum::Performance::Compare;
use v5.40;
use Exporter qw(import);
use JSON::PP;
use List::Util                   qw(min max any);
use GPForum::Performance::Schema qw(is_number);

# Statistics must be available before any CPAN dependency installation.
use constant {    ## no critic (ValuesAndExpressions::ProhibitConstantPragma)
    MIN_REPEATS        => 3,
    PERCENT            => 100,
    MAD_PERCENT_FACTOR => 300,
    MIN_TOLERANCE      => 10,
    CONFIRMED_CHANGE   => 15,
    EPSILON            => 1e-12
};
our $VERSION   = '0.001';
our @EXPORT_OK = qw(key aggregate compare configuration_differences);
my @KEYS =
  qw(scenario endpoint generator reactor workers concurrency cache_mode);
my %LOWER = map { $_ => 1 }
  qw(p50_ms p95_ms p99_ms sql_execution_ms statements round_trips);
my %HIGHER = map { $_ => 1 } qw(requests_per_second messages_per_second);

sub key ( $row, $except = undef ) {
    return JSON::PP->new->encode(
        [
            map  { defined $row->{$_} ? "$row->{$_}" : q{} }
            grep { !defined $except || $_ ne $except } @KEYS
        ]
    );
}

sub _median ($values) {
    my @ordered = sort { $a <=> $b } @{$values};
    my $middle  = int( @ordered / 2 );
    return @ordered % 2
      ? $ordered[$middle]
      : ( $ordered[ $middle - 1 ] + $ordered[$middle] ) / 2;
}

sub _metrics ($rows) {
    my ( %metrics, %mad, %samples, %names );
    for my $row ( @{$rows} ) {
        for my $name (
            grep { is_number( $row->{metrics}{$_} ) }
            keys %{ $row->{metrics} // {} }
          )
        {
            $names{$name} = 1;
        }
    }
    for my $name ( sort keys %names ) {
        my @values = map { $_->{metrics}{$name} }
          grep { is_number( $_->{metrics}{$name} ) } @{$rows};
        my $center = _median( \@values );
        $metrics{$name} = $center;
        $mad{$name}     = _median( [ map { abs $_ - $center } @values ] );
        $samples{$name} = \@values;
    }
    return ( \%metrics, \%mad, \%samples );
}

sub aggregate ( $measurements, $kind ) {
    my ( %groups, @order, @results );
    for my $row ( @{$measurements} ) {
        my $group = key($row);
        if ( !exists $groups{$group} ) { push @order, $group; }
        push @{ $groups{$group} }, $row;
    }
    for my $group (@order) {
        my $rows = $groups{$group};
        my @good = grep { $_->{status} eq 'ok' } @{$rows};
        my ( $metrics, $mad, $samples ) = _metrics( \@good );
        my %result =
          map { $_ => $rows->[0]{$_} } grep { exists $rows->[0]{$_} } @KEYS;
        @result{
            qw(kind status repetitions attempted metrics mad samples evidence_quality)
          } = (
            $kind,
            @good == @{$rows} ? 'ok' : 'failed',
            scalar @good,
            scalar @{$rows},
            $metrics,
            $mad,
            $samples,
            @good >= MIN_REPEATS ? 'measured-comparative' : 'indicative',
          );
        if ( any { ( $_->{evidence_quality} // q{} ) eq 'indicative' }
            @{$rows} )
        {
            $result{evidence_quality} = 'indicative';
        }
        push @results, \%result;
    }
    return \@results;
}

sub _threshold ( $current, $baseline, $name ) {
    my $value = $current->{metrics}{$name};
    my $old   = $baseline->{metrics}{$name};
    my $noise = max( ( $current->{mad}{$name} // 0 ) / max( $value, EPSILON ),
        ( $baseline->{mad}{$name} // 0 ) / $old ) * MAD_PERCENT_FACTOR;
    return max( MIN_TOLERANCE, $noise );
}

sub _confirmed ( $current, $baseline, $name, $detrimental, $threshold ) {
    my $a = $current->{samples}{$name}  // [];
    my $b = $baseline->{samples}{$name} // [];
    return 0
      if @{$a} < MIN_REPEATS
      || @{$b} < MIN_REPEATS
      || $detrimental < max( CONFIRMED_CHANGE, $threshold );
    return $HIGHER{$name}
      ? max( @{$a} ) < min( @{$b} )
      : min( @{$a} ) > max( @{$b} );
}

sub _classification ( $changes, $improvements ) {
    return 'confirmed-regression'
      if any { $_ eq 'confirmed-regression' } @{$changes};
    return 'possible-regression' if @{$changes};
    return 'improvement'         if @{$improvements};
    return 'stable';
}

sub _measure_changes ( $current, $baseline, $result ) {
    my ( @changes, @improvements );
    for my $name ( sort keys %{ $current->{metrics} } ) {
        my $old = $baseline->{metrics}{$name};
        next if !defined $old || $old <= 0;
        my $delta = PERCENT * ( $current->{metrics}{$name} / $old - 1 );
        $result->{deltas_pct}{$name} = 0 + sprintf '%.3f', $delta;
        next if !$LOWER{$name} && !$HIGHER{$name};
        my $detrimental = $HIGHER{$name} ? -$delta : $delta;
        my $threshold   = _threshold( $current, $baseline, $name );
        if ( $detrimental > $threshold ) {
            push @changes,
              _confirmed( $current, $baseline, $name, $detrimental, $threshold )
              ? 'confirmed-regression'
              : 'possible-regression';
        }
        elsif ( $detrimental < -$threshold ) { push @improvements, $name; }
    }
    return ( \@changes, \@improvements );
}

sub compare ( $current, $baseline ) {
    my $result = {
        classification => 'not-comparable',
        deltas_pct     => {},
        reason         => 'No matching valid baseline scenario.'
    };
    return $result
      if !$baseline
      || $current->{status} ne 'ok'
      || ( $baseline->{status} // q{} ) ne 'ok';
    my ( $changes, $improvements ) =
      _measure_changes( $current, $baseline, $result );
    return $result if !keys %{ $result->{deltas_pct} };
    $result->{classification} = _classification( $changes, $improvements );
    $result->{reason} =
'Median comparison; tolerance >=10% and 3x relative MAD; confirmation needs >=3 repeats, >=15% change and separated sample ranges. Timing classifications are advisory.';
    if (
        min( $current->{repetitions} // 0, $baseline->{repetitions} // 0 ) <
        MIN_REPEATS
        && (   $result->{classification} eq 'stable'
            || $result->{classification} eq 'improvement' )
      )
    {
        $result->{classification} = 'not-comparable';
        $result->{reason} =
          'Fewer than three repetitions; deltas are indicative only.';
    }
    return $result;
}

sub configuration_differences ( $rows, $field ) {
    my @differences;
    for my $row ( @{$rows} ) {
        my @peers = grep { key( $_, $field ) eq key( $row, $field ) } @{$rows};
        @peers =
          $field eq 'workers'
          ? sort { $a->{$field} <=> $b->{$field} } @peers
          : sort {
            ( $a->{$field} ne 'Mojo::Reactor::Poll' )
              <=> ( $b->{$field} ne 'Mojo::Reactor::Poll' )
              || $a->{$field} cmp $b->{$field}
          } @peers;
        my $peer = $peers[0];
        next if $row->{$field} eq $peer->{$field};
        my %copy = map { $_ => $row->{$_} } grep { exists $row->{$_} } @KEYS;
        push @differences,
          {
            %copy,
            value          => $row->{$field},
            baseline_value => $peer->{$field},
            comparison     => compare( $row, $peer )
          };
    }
    return \@differences;
}
1;
