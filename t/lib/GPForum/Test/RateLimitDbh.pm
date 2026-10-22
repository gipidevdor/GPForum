# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::RateLimitDbh;

use Const::Fast;
use Mojo::Base -base;
use v5.40;

our $VERSION = '0.001';

const my $WINDOW_STARTED_AT_BIND => 3;

has calls   => sub { return []; };
has buckets => sub { return {}; };

sub selectrow_hashref {
    my ( $self, $sql, $attributes, @bind ) = @_;

    push @{ $self->calls }, { sql => $sql, bind => \@bind };

    my $key = join q{:}, @bind[ 0 .. $WINDOW_STARTED_AT_BIND ];
    $self->buckets->{$key} ||= {
        actor_hash        => $bind[1],
        observed_count    => 0,
        window_started_at => $bind[$WINDOW_STARTED_AT_BIND],
    };
    $self->buckets->{$key}{observed_count} += 1;

    return { %{ $self->buckets->{$key} } };
}

1;
