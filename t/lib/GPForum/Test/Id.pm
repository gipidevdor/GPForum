# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::Id;

use Mojo::Base -base;
use v5.40;

our $VERSION = '0.001';

has value => 0;

sub uuid {
    my ($self) = @_;

    $self->value( $self->value + 1 );

    return 'generated-' . $self->value;
}

1;
