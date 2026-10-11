# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Performance::ExtremePlan;

use v5.40;
use Carp       qw(croak);
use Exporter   qw(import);
use List::Util qw(min max);

# Configuration must load before CPAN setup.
use constant {    ## no critic (ValuesAndExpressions::ProhibitConstantPragma)
    INITIAL_CONNECTIONS  => 10,
    MIXED_CONNECTION_CAP => 50,
    CONCURRENT_100       => 100,
    CONCURRENT_250       => 250,
    CONCURRENT_500       => 500,
    EXPERIMENTAL_1000    => 1_000,
    WEIGHT_CLASSES       => 5,
    PERCENT_TOTAL        => 100,
};

our $VERSION   = '0.001';
our @EXPORT_OK = qw(profiles mixed_weights choose_safe);

sub profiles {
    return {
        full => {
            levels => [
                INITIAL_CONNECTIONS, MIXED_CONNECTION_CAP,
                CONCURRENT_100,      CONCURRENT_250,
                CONCURRENT_500,      EXPERIMENTAL_1000
            ],
            duration            => 4,
            repetitions         => 2,
            progressive_seconds => 480,
            mixed_windows       => 10,
            window_seconds      => 30,
            mixed_seconds       => 420,
            soak_windows        => 10,
            soak_seconds        => 360,
            spike_seconds       => 10
        },
        reduced => {
            levels      => [ INITIAL_CONNECTIONS, MIXED_CONNECTION_CAP ],
            duration    => 1,
            repetitions => 2,
            progressive_seconds => 180,
            mixed_windows       => 3,
            window_seconds      => 5,
            mixed_seconds       => 60,
            soak_windows        => 3,
            soak_seconds        => 60,
            spike_seconds       => 3
        },
    };
}

sub mixed_weights ( $text = undef ) {
    $text //= 'thread=50,category=20,home=15,search=10,other=5';
    my %allowed = map { $_ => 1 } qw(thread category home search other);
    my %weights;
    for my $part ( split /,/msx, $text ) {
        my ( $name, $value ) = split /=/msx, $part, 2;
        croak 'Unknown, duplicate or invalid mixed weight'
          if !$allowed{$name}
          || exists $weights{$name}
          || !defined $value
          || $value !~ /\A\d+\z/amsx
          || $value > PERCENT_TOTAL;
        $weights{$name} = 0 + $value;
    }
    my $total = 0;
    for my $value ( values %weights ) { $total += $value; }
    croak 'Five integer mixed weights must sum to 100'
      if keys(%weights) != WEIGHT_CLASSES || $total != PERCENT_TOTAL;
    return \%weights;
}

sub choose_safe ($rows) {
    my @levels = map { $_->{concurrency} } grep {
             $_->{scenario} eq 'thread'
          && $_->{status} eq 'ok'
          && $_->{classification} eq 'observed-capacity'
          && !( $_->{metrics}{http_errors}      // 1 )
          && !( $_->{metrics}{transport_errors} // 1 )
    } @{$rows};
    return max( INITIAL_CONNECTIONS,
        min( MIXED_CONNECTION_CAP, max( INITIAL_CONNECTIONS, @levels ) ) );
}

1;
