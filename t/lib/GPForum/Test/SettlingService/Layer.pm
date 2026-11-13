# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::SettlingService::Layer;

use Mojo::Base -base;
use v5.40;

use Mojo::Promise;

our $VERSION = '0.001';

# A call layer as SqlFunction's: the blocking one answers settled promises,
# the other one answers on the next turn of the event loop.
has blocking => 0;

sub blocking_layer ($self) {
    return __PACKAGE__->new( blocking => 1 );
}

sub twice_p ( $self, $value ) {
    return Mojo::Promise->resolve( $value * 2 ) if $self->blocking;
    return Mojo::Promise->timer( 0, $value * 2 );
}

1;
