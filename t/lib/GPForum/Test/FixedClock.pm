# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::FixedClock;

use Mojo::Base -base;
use v5.40;

use Time::Piece ();

our $VERSION = '0.001';

has epoch   => 1_716_464_000;
has iso8601 => '2026-05-23T12:00:00Z';

sub now_epoch {
    my ($self) = @_;

    return $self->epoch;
}

sub now_iso8601 {
    my ($self) = @_;

    return $self->iso8601;
}

# $seconds after the fixed time, written as now_iso8601 writes it: what the
# outbox dispatcher asks for when it leases a message or schedules a retry.
sub epoch_plus_iso8601 {
    my ( $self, $seconds ) = @_;

    my $now = Time::Piece->strptime( $self->iso8601, q{%Y-%m-%dT%H:%M:%SZ} );

    return ( $now + $seconds )->datetime . q{Z};
}

1;
