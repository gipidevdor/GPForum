# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::RealtimePermissionEngine;

use Mojo::Base -base;
use v5.40;

use GPForum::Test::SettledTwins;

our $VERSION = '0.001';

has denied => sub { return {}; };

sub permits {
    my ( $self, @arguments ) = @_;

    my $resource = $arguments[2];

    return !$self->denied->{ $resource->{id} };
}

GPForum::Test::SettledTwins->install( __PACKAGE__, permits => 4 );

1;

