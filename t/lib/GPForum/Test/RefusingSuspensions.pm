# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::RefusingSuspensions;

use v5.40;

use Mojo::Promise;

our $VERSION = '0.001';

# A suspension store that refuses every target, for the reason it is given:
# staff, or the actor themselves.
sub new ( $class, %input ) { return bless {%input}, $class }

sub create_suspension_p ( $self, $input, $context = undef ) {
    return Mojo::Promise->resolve( { ok => 0, refused => $self->{refused} } );
}

1;
