# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::ConcurrentFunctions;

use Mojo::Base -base, -signatures;
use v5.40;

use Mojo::Promise;

our $VERSION = '0.001';

# A call layer whose every read stays pending until the test answers it:
# what was started, in order, shows which reads ran together.
has started => sub { return []; };
has pending => sub { return {}; };

sub row_p ( $self, $name, @ ) { return $self->_ask($name); }

sub rows_p ( $self, $name, @ ) { return $self->_ask($name); }

sub _ask ( $self, $name ) {
    push @{ $self->started }, $name;

    return $self->pending->{$name} = Mojo::Promise->new;
}

# The reads started after the first, in the order they started.
sub started_after_first ($self) {
    my @started = @{ $self->started };
    shift @started;

    return @started;
}

sub answer ( $self, $name, $value ) {
    return $self->pending->{$name}->resolve($value);
}

1;
