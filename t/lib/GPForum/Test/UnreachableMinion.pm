# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::UnreachableMinion;

use Mojo::Base -base;
use v5.40;

our $VERSION = '0.001';

sub backend {
    my ($self) = @_;

    return $self;
}

sub pg {
    my ($self) = @_;

    return $self;
}

sub db {
    my ($self) = @_;

    return $self;
}

sub ping {
    return 0;
}

1;
