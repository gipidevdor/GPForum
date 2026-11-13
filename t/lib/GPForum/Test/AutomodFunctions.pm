# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::AutomodFunctions;

use Mojo::Base 'GPForum::Test::SettledCalls', -signatures;
use v5.40;

our $VERSION = '0.001';

# ADR 0133: the function layer's stand-in for the automod store. It records
# each call and answers every write as done; its promises are settled
# (GPForum::Test::SettledCalls), so a store's blocking twins run.
has calls => sub { return []; };

sub row ( $self, $name, $values ) {
    push @{ $self->calls }, [ $name, $values ];

    return { status => 'ok', removed => 1 };
}

sub rows ( $self, $name, $values ) {
    push @{ $self->calls }, [ $name, $values ];

    return [];
}

1;
