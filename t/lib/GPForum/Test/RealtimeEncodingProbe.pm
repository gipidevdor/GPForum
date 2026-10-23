# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::RealtimeEncodingProbe;

use Mojo::Base -base, -signatures;
use v5.40;

our $VERSION = '0.001';
has calls => 0;

# JSON's conversion hook makes redundant serialization observable.
sub TO_JSON ($self) {
    $self->calls( $self->calls + 1 );
    return { message => 'one encoding per broadcast' };
}

1;
