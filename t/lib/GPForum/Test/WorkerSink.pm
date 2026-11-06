# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::WorkerSink;

use Mojo::Base -base;
use v5.40;

our $VERSION = '0.001';

has records => sub { return []; };

sub capture {
    my ( $self, $row ) = @_;

    push @{ $self->records }, $row;

    return $row;
}

1;
