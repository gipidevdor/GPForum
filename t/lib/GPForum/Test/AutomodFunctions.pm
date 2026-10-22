# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::AutomodFunctions;

use Mojo::Base -base, -signatures;
use v5.40;

our $VERSION = '0.001';

# ADR 0133: the function layer's stand-in for the automod store. It records
# each call and answers every write as done.
has calls => sub { return []; };

sub row ( $self, $name, $values ) {
    push @{ $self->calls }, [ $name, $values ];

    return { status => 'ok', removed => 1 };
}

sub rows ( $self, $name, $values ) {
    push @{ $self->calls }, [ $name, $values ];

    return [];
}

1;
