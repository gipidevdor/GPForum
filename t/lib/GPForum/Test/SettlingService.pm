# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::SettlingService;

use Mojo::Base -base, -async_await;
use v5.40;

use GPForum::Infrastructure::SqlFunction;
use GPForum::Test::SettlingService::Layer;

our $VERSION = '0.001';

# A service written once, as its promise method (ADR 0177), against a call
# layer that says whether it blocks.
has functions => undef;    # optional: a service without one runs as it is

GPForum::Infrastructure::SqlFunction->blocking_twins('double');

async sub double_p ( $self, $value ) {
    my $layer = $self->functions;
    my $twice = $layer ? await $layer->twice_p($value) : $value * 2;

    return { blocking => $layer && $layer->blocking ? 1 : 0, value => $twice };
}

1;
