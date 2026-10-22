# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::DigestClock;

use Mojo::Base 'GPForum::Service::Clock', -signatures;
use v5.40;

our $VERSION = '0.001';

# The email digest's clock (ADR 0078): stopped at noon UTC on 2026-10-15,
# a Thursday, so the last day is the 14th and the last week began on
# Monday the 5th. now_iso8601 and epoch_plus_iso8601 follow it.
has epoch => 1_792_065_600;

sub now_epoch ($self) {
    return $self->epoch;
}

1;
