# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Performance::Budget;

use v5.40;
use Carp                          qw(croak);
use GPForum::Performance::Support qw(monotonic);
use List::Util                    qw(min max);

# Available before dependency installation.
use constant {    ## no critic (ValuesAndExpressions::ProhibitConstantPragma)
    MAX_JOB_SECONDS        => 1_800,
    REPORT_RESERVE_SECONDS => 240,
    CLOCK_ROUNDING_SECONDS => 0.000_001,
};

our $VERSION = '0.001';

sub new ( $class, $clock = {} ) {
    my $started = $clock->{started_monotonic}
      // $ENV{EXTREME_STARTED_MONOTONIC} // monotonic();
    my $deadline = $clock->{deadline_monotonic}
      // $ENV{EXTREME_DEADLINE_MONOTONIC} // ( $started + MAX_JOB_SECONDS );
    my $measurement = $clock->{measurement_deadline_monotonic}
      // $ENV{EXTREME_MEASURE_DEADLINE_MONOTONIC}
      // ( $deadline - REPORT_RESERVE_SECONDS );
    for my $value ( $started, $deadline, $measurement ) {
        croak 'Non-finite global deadline'
          if $value !~ /\A\d+(?:[.]\d+)?\z/amsx;
    }
    my $maximum_deadline = $started + MAX_JOB_SECONDS;
    croak 'Deadline must reserve report and remain within 30 minutes'
      if $started > $measurement
      || $measurement > $deadline
      || $deadline - $maximum_deadline > CLOCK_ROUNDING_SECONDS;

    # JSON roundtrips can move an absolute clock by a floating-point ulp.
    # Accept that rounding only at the upper bound, then clamp the stored
    # deadlines so it never grants time beyond the actual 30-minute budget.
    $deadline    = min( $deadline,    $maximum_deadline );
    $measurement = min( $measurement, $deadline );
    return bless {
        started              => 0 + $started,
        deadline             => 0 + $deadline,
        measurement_deadline => 0 + $measurement
    }, $class;
}

sub phase ( $self, $seconds ) {
    return min( monotonic() + $seconds, $self->{measurement_deadline} );
}

sub remaining ( $self, $deadline = undef ) {
    return max( 0,
        ( $deadline // $self->{measurement_deadline} ) - monotonic() );
}

sub elapsed ($self) {
    return max( 0, monotonic() - $self->{started} );
}

1;
