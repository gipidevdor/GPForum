# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Operations::PasswordCalibration;

use Mojo::Base -base, -signatures;
use v5.40;
use Const::Fast;

use GPForum::Service::Password;
use Time::HiRes qw(clock_gettime CLOCK_MONOTONIC);

our $VERSION = '0.001';

const my $MILLISECONDS                   => 1000;
const my $MINIMUM_MEMORY_MIB             => 19;
const my $DEFAULT_ITERATIONS             => 3;
const my $DEFAULT_MEMORY_MIB             => 32;
const my $MAXIMUM_CALIBRATION_ITERATIONS => 4;
const my $LARGER_MEMORY_MIB              => 64;

has target_ms => 250;
has measure   => sub {
    return sub ( $memory, $iterations ) {
        my $password = GPForum::Service::Password->new(
            memory_mib => $memory,
            iterations => $iterations
        );
        my $start = clock_gettime(CLOCK_MONOTONIC);
        $password->hash_password('gpforum calibration password');
        return $MILLISECONDS * ( clock_gettime(CLOCK_MONOTONIC) - $start );
    };
};

# Worst of three warmed measurements. Never go below the security floor,
# even when the slowest supported configuration exceeds the latency budget.
# Bound the search and its memory; this is an operator action, not startup.
sub run ($self) {
    my ( @samples, $chosen );
    for my $cost (
        [ $MINIMUM_MEMORY_MIB, 2 ],
        [ $DEFAULT_MEMORY_MIB, 2 ],
        [ $DEFAULT_MEMORY_MIB, $DEFAULT_ITERATIONS ],
        [ $LARGER_MEMORY_MIB,  $DEFAULT_ITERATIONS ],
        [ $LARGER_MEMORY_MIB,  $MAXIMUM_CALIBRATION_ITERATIONS ]
      )
    {
        my ( $memory, $iterations ) = @{$cost};
        $self->measure->( $memory, $iterations );
        my @times =
          sort { $a <=> $b }
          map  { $self->measure->( $memory, $iterations ) }
          1 .. $DEFAULT_ITERATIONS;
        my $sample = {
            memory_mib   => $memory,
            iterations   => $iterations,
            milliseconds => $times[-1]
        };
        push @samples, $sample;
        last if $times[-1] >= $self->target_ms;
        $chosen = $sample;
    }
    return {
        status         => $chosen ? 'ok' : 'degraded',
        target_ms      => $self->target_ms,
        samples        => \@samples,
        within_budget  => $chosen ? true : false,
        recommendation => $chosen // $samples[0]
    };
}

1;

__END__

=head1 NAME

GPForum::Service::Operations::PasswordCalibration - Measure host Argon2id costs.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $service = GPForum::Service::Operations::PasswordCalibration->new(...);

=head1 DESCRIPTION

Measure host Argon2id costs. See ADR 0155.

=head1 SUBROUTINES/METHODS

=head2 run

Measures warmed candidate costs and returns status, samples, target_ms, within_budget and recommendation. The worst of three measurements must stay below the budget; a slow host retains the security floor with degraded status.

=head1 DIAGNOSTICS

Exceptions propagate to the command or worker, which reports the failure.

=head1 CONFIGURATION AND ENVIRONMENT

Receives configuration or collaborators through constructor arguments. See
ADR 0155 for the operator settings and commands.

=head1 DEPENDENCIES

Uses the modules listed in the source preamble and the locked cpanfile.

=head1 INCOMPATIBILITIES

Requires Perl 5.40 or newer.

=head1 BUGS AND LIMITATIONS

See ADR 0155 for the scope and operational limits.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause
license.

=cut
