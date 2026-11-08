# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;
use Test::More;
use lib 'lib';
use lib 't/lib';

use GPForum::Service::Realtime::ChannelAuthorizer;
use GPForum::Service::Realtime::ConnectionRegistry;
use GPForum::Service::Realtime::Hub;
use GPForum::Test::RealtimeConnection;
use GPForum::Test::RealtimePermissionEngine;

our $VERSION = '0.001';

# A moderation or admin channel is authorised again on every broadcast: a
# moderator whose right was withdrawn while their queue page stayed open
# stops receiving it, on both paths, and receives it again once restored.
my $engine = GPForum::Test::RealtimePermissionEngine->new;
my $hub    = GPForum::Service::Realtime::Hub->new(
    registry   => GPForum::Service::Realtime::ConnectionRegistry->new,
    authorizer => GPForum::Service::Realtime::ChannelAuthorizer->new(
        permission_engine => $engine
    ),
);
my $connection = GPForum::Test::RealtimeConnection->new;
$hub->register_connection( 'connection-1', { user_id => 'moderator-1' },
    $connection );
ok(
    $hub->subscribe(
        {
            actor         => { user_id => 'moderator-1' },
            channel       => 'moderation:queue',
            connection_id => 'connection-1',
            context       => {},
        }
    )->{ok},
    'a moderator subscribes to the queue'
);

my $payload = { event_type => 'moderation.queue.invalidate' };
is( $hub->broadcast( 'moderation:queue', $payload )->{delivered},
    1, 'and receives it' );

$engine->denied( { queue => 1 } );
is( $hub->broadcast( 'moderation:queue', $payload )->{delivered},
    0, 'not once the right is withdrawn' );
my $async;
$hub->broadcast_p( 'moderation:queue', $payload )
  ->then( sub ($result) { $async = $result } )
  ->wait;
is( $async->{delivered}, 0, 'nor on the asynchronous path' );

$engine->denied( {} );
is( $hub->broadcast( 'moderation:queue', $payload )->{delivered},
    1, 'and again once it is given back, still subscribed' );

done_testing();

1;
