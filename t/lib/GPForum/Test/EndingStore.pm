# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::EndingStore;

use Mojo::Base -base, -signatures;
use v5.40;

our $VERSION = '0.001';

# A suspension store as the suspension end handler and the hourly sweep use
# it: each call recorded, a suspension always ended, two ends always queued.
has calls => sub { return []; };

sub end_suspension ( $self, @arguments ) {
    push @{ $self->calls }, [ end_suspension => @arguments ];

    return { ended => 1, suspension_id => $arguments[1] };
}

sub queue_ends ( $self, $input ) {
    push @{ $self->calls }, [ queue_ends => $input ];

    return { ok => 1, queued => 2 };
}

1;
