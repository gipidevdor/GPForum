# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::RealtimeBadgeCounter;

use Mojo::Base -base;
use v5.40;

use GPForum::Test::SettledTwins;

our $VERSION = '0.001';

# Stands in for the notification dispatcher, whose unread count the hub's
# badge snapshots carry.
has calls  => sub { return []; };
has counts => sub { return {}; };
has fail   => 0;

sub unread_count_for_user {
    my ( $self, $user_id ) = @_;

    push @{ $self->calls }, $user_id;
    die "badge count failed\n" if $self->fail;

    return $self->counts->{$user_id} // 0;
}

GPForum::Test::SettledTwins->install( __PACKAGE__, unread_count_for_user => 1 );

1;
