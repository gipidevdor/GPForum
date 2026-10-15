# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::RelationFunctions;

use Mojo::Base -base, -signatures;
use v5.40;

our $VERSION = '0.001';

# ADR 0130: the function layer's stand-in for the member relation store. It
# records each call and answers what the test gives it: a row, or code that
# builds one from the values.
has calls   => sub { return []; };
has answers => sub { return {}; };

sub row ( $self, $name, $values ) {
    push @{ $self->calls }, [ $name, $values ];
    my $answer = $self->answers->{$name};

    return ref $answer eq 'CODE' ? $answer->($values) : $answer;
}

sub rows ( $self, $name, $values ) {
    push @{ $self->calls }, [ $name, $values ];

    return $self->answers->{$name} // [];
}

1;
