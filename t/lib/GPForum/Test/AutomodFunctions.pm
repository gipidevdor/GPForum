# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::AutomodFunctions;

use Mojo::Base -base, -signatures;
use v5.40;

use Mojo::Promise;

our $VERSION = '0.001';

# ADR 0133: the function layer's stand-in for the automod store. It records
# each call and answers every write as done. Like the blocking layer of ADR
# 0177 it answers its promises settled, so a store's blocking twins run.
has calls => sub { return []; };

sub blocking ($self) { return 1; }

sub blocking_layer ($self) { return $self; }

sub row ( $self, $name, $values ) {
    push @{ $self->calls }, [ $name, $values ];

    return { status => 'ok', removed => 1 };
}

sub rows ( $self, $name, $values ) {
    push @{ $self->calls }, [ $name, $values ];

    return [];
}

sub row_p ( $self, $name, $values, $context = undef ) {
    return Mojo::Promise->resolve( $self->row( $name, $values ) );
}

sub rows_p ( $self, $name, $values, $context = undef ) {
    return Mojo::Promise->resolve( $self->rows( $name, $values ) );
}

1;
