# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;
use v5.40;
use FindBin;
use lib "$FindBin::Bin/../../script/lib";
use JSON::PP qw(encode_json decode_json);
use Test::More;
use GPForum::Performance::Budget;
our $VERSION = '0.001';

# Core constants keep the budget contract runnable before CPAN setup.
use constant {    ## no critic (ValuesAndExpressions::ProhibitConstantPragma)
    CLOCK_ORIGIN        => 100.000_001,
    JOB_SECONDS         => 1_800,
    MEASUREMENT_SECONDS => 1_560,
    REAL_OVERRUN        => 0.01,
    ROUNDING_OVERRUN    => 0.000_000_5,
};

sub _clock {
    return {
        started_monotonic              => CLOCK_ORIGIN,
        deadline_monotonic             => CLOCK_ORIGIN + JOB_SECONDS,
        measurement_deadline_monotonic => CLOCK_ORIGIN + MEASUREMENT_SECONDS,
    };
}

sub _rejected ( $clock, $description ) {
    my $error;
    try { GPForum::Performance::Budget->new($clock); }
    catch ($caught) { $error = $caught; };
    like( "$error", qr/Deadline[ ]must[ ]reserve/msx, $description );
    return undef;
}

my $clock  = decode_json( encode_json( _clock() ) );
my $budget = GPForum::Performance::Budget->new($clock);
isa_ok(
    $budget,
    'GPForum::Performance::Budget',
    'a valid JSON clock roundtrip does not abort reporting'
);
cmp_ok(
    $budget->{deadline}, '<=',
    CLOCK_ORIGIN + JOB_SECONDS,
    'rounding never extends the maximum job deadline'
);
is(
    $budget->{measurement_deadline},
    $clock->{measurement_deadline_monotonic},
    'the earlier measurement deadline retains its report reserve'
);

$clock = _clock();
$clock->{deadline_monotonic} += ROUNDING_OVERRUN;
$clock->{measurement_deadline_monotonic} = $clock->{deadline_monotonic};
$budget = GPForum::Performance::Budget->new($clock);
is(
    $budget->{deadline},
    CLOCK_ORIGIN + JOB_SECONDS,
    'a microscopic upper-bound error is clamped to the exact limit'
);
is( $budget->{measurement_deadline},
    $budget->{deadline},
    'clamping cannot leave a measurement beyond the job deadline' );

$clock = _clock();
$clock->{deadline_monotonic} += REAL_OVERRUN;
_rejected( $clock, 'a real overrun beyond 30 minutes is rejected' );
$clock = _clock();
$clock->{measurement_deadline_monotonic} =
  $clock->{deadline_monotonic} + ROUNDING_OVERRUN;
_rejected( $clock, 'measurement ordering gets no rounding tolerance' );
$clock = _clock();
$clock->{measurement_deadline_monotonic} = CLOCK_ORIGIN - ROUNDING_OVERRUN;
_rejected( $clock, 'a measurement before the origin remains invalid' );

done_testing;
1;
