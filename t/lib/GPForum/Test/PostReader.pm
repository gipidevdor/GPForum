# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::PostReader;

use Mojo::Base -base;
use v5.40;

our $VERSION = '0.001';

has post => undef;    # optional: no post found

sub find_post {
    my ($self) = @_;

    return $self->post;
}

1;
