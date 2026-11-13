# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::SlowRealtimeReads;

use Const::Fast;
use Mojo::Promise;
use Mojo::Base -base, -signatures;
use v5.40;

our $VERSION = '0.001';

const my $DELAY_SECONDS => 0.01;

# The hub's and the subscription policy's collaborators in one double --
# readability, authorizer and suspension store -- each read answered a
# moment later, counting how many are in flight at once.
has calls     => sub { return []; };
has denied    => sub { return {}; };    # users the authorizer refuses
has fail      => 0;                     # readable_by_p fails
has in_flight => 0;
has most      => 0;                     # the most reads in flight at once
has readers   => sub { return {}; };    # resource type => [user ids]
has suspended => 0;

sub readers_list_p ( $self, $type, $id, @users ) {
    push @{ $self->calls }, [ $type, $id, @users ];
    my %readable = map { $_ => 1 } @{ $self->readers->{$type} || [] };
    return $self->_later( [ grep { $readable{$_} } @users ] );
}

sub readable_by_p ( $self, $user_id, $type, $id ) {
    push @{ $self->calls }, [ $user_id, $type, $id ];
    return $self->_later(1)
      ->then( sub ($readable) { return $self->_readable($readable) } );
}

sub authorize_p ( $self, $actor, $channel, $context ) {
    push @{ $self->calls }, $actor->{user_id};
    return $self->_later(
        { ok => $self->denied->{ $actor->{user_id} } ? 0 : 1 } );
}

sub can_participate_p ( $self, $user_id ) {
    return $self->_later(
        $self->suspended
        ? { ok => 0, reason => 'suspended' }
        : { ok => 1 }
    );
}

sub _readable ( $self, $readable ) {
    return $readable if !$self->fail;
    return Mojo::Promise->reject("readability is down\n");
}

sub _later ( $self, $answer ) {
    $self->in_flight( $self->in_flight + 1 );
    if ( $self->in_flight > $self->most ) {
        $self->most( $self->in_flight );
    }
    return Mojo::Promise->timer($DELAY_SECONDS)->then(
        sub (@) {
            $self->in_flight( $self->in_flight - 1 );
            return $answer;
        }
    );
}

1;
