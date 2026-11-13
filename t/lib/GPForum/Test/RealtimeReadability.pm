# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::RealtimeReadability;

use Mojo::Base -base;
use v5.40;

use GPForum::Test::SettledTwins;

our $VERSION = '0.001';

# Thread or post id => { user id => 1 } for each reader who may read it.
has readable => sub { return {}; };

sub readable_by {
    my ( $self, $reader, $type, $id ) = @_;

    my @readers = $self->readers_of( $type, $id, $reader );
    return @readers ? 1 : 0;
}

sub readers_of {
    my ( $self, $type, $id, @readers ) = @_;

    my $can_read =
      $type eq 'thread' || $type eq 'post' ? $self->readable->{$id} || {} : {};
    return grep { defined && $can_read->{$_} } @readers;
}

sub readers_list {
    my ( $self, @arguments ) = @_;

    return [ $self->readers_of(@arguments) ];
}

GPForum::Test::SettledTwins->install(
    __PACKAGE__,
    readable_by  => 3,
    readers_list => undef
);

1;
