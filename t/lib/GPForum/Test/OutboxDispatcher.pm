# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::OutboxDispatcher;

use Mojo::Base -base;
use v5.40;

our $VERSION = '0.001';

has calls => sub { return []; };

sub dispatch_pending {
    my ( $self, $limit ) = @_;

    push @{ $self->calls }, $limit;

    return {
        selected      => 1,
        dispatched    => 1,
        failed        => 0,
        dead_lettered => 0,
    };
}

1;
