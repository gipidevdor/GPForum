# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::DeadLetteringDispatcher;

use Mojo::Base -base, -signatures;
use v5.40;

our $VERSION = '0.001';

has dead_lettered => 0;

# A dispatch that dead-letters every message it selects.
sub dispatch_pending ( $self, $limit ) {
    return {
        acknowledged  => 0,
        dead_lettered => $self->dead_lettered,
        dispatched    => 0,
        failed        => 0,
        lost          => 0,
        selected      => $self->dead_lettered,
    };
}

1;
