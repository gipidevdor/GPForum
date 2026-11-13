# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::FlakyReadability;

use Mojo::Base -base;
use v5.40;

use GPForum::Test::SettledTwins;

our $VERSION = '0.001';

# Thread or post ids whose readers cannot be asked: readers_list dies for
# them, as Readability does when its query fails. Everyone reads the rest.
has unreachable => sub { return {}; };

sub readers_list {
    my ( $self, undef, $id, @readers ) = @_;

    if ( $self->unreachable->{$id} ) {
        die "readability query failed\n";
    }

    return \@readers;
}

GPForum::Test::SettledTwins->install( __PACKAGE__, readers_list => undef );

1;
