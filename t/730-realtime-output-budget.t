# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;
use utf8;
use lib 'lib';
use lib 't/lib';
use Const::Fast;
use Mojo::JSON qw(decode_json encode_json);
use Mojo::Transaction::WebSocket;
use Mojo::WebSocket qw(parse_frame);
use GPForum::Controller::Realtime;
use GPForum::Service::Realtime::Hub;
use GPForum::Test::RealtimeEncodingProbe;
use Scalar::Util qw(weaken);
use Test::More;

our $VERSION = '0.001';
const my $RECIPIENTS   => 3;
const my $FRAME_LIMIT  => 32;
const my $BYTE_LIMIT   => 262_144;
const my $OPCODE_INDEX => 4;
const my $CLOSE_OPCODE => 8;
const my $RETRY_CODE   => 1013;

my @transactions;
my $hub  = GPForum::Service::Realtime::Hub->new;
my $slow = _socket();
my $fast = _socket();
for my $entry ( [ slow => $slow ], [ fast => $fast ] ) {
    $hub->register_connection( $entry->[0], 'user-1', $entry->[1] );
    $hub->registry->subscribe( $entry->[0], 'notifications:user-1' );
}
my $event = { type => 'test', payload => { text => 'Caffè, già ☕' } };
for ( 1 .. $FRAME_LIMIT ) {
    my $result = $hub->broadcast( 'notifications:user-1', $event );
    is( $result->{delivered}, 2, 'both sockets accept a bounded event' );
    _drain($fast);
}
is( $slow->realtime_pending_frames,
    $FRAME_LIMIT, 'stalled socket fills its frame budget' );
is( $fast->realtime_pending_frames,
    0, 'drained socket releases its frame budget' );
is( $fast->realtime_pending_bytes, 0, 'and its byte budget' );
my $result = $hub->broadcast( 'notifications:user-1', $event );
is( $result->{delivered}, 1, 'slow socket cannot block the healthy recipient' );
is( $result->{failed},    1, 'overload appears in delivery statistics' );
ok( $slow->realtime_overloaded, 'slow socket is closed for reconnection' );
my $wire = $slow->tx->server_write;
my @frames;

while ( length $wire ) {
    push @frames, parse_frame( \$wire, $BYTE_LIMIT );
}
is(
    scalar @frames,
    $FRAME_LIMIT + 1,
    'only accepted events and one close frame are queued'
);
is( $frames[-1][$OPCODE_INDEX], $CLOSE_OPCODE, 'last frame closes the socket' );
is( unpack( 'n', $frames[-1][-1] ),
    $RETRY_CODE, 'close asks the client to retry later' );
is_deeply( decode_json( $frames[0][-1] ),
    $event, 'shared serialization preserves Unicode on the wire' );
ok(
    !$slow->send_realtime( { text => '{}', bytes => 2 } ),
    'closed socket never accepts more events'
);
_drain($fast);
is( $fast->realtime_pending_frames, 0,
    'healthy connection continues draining' );

my $large = _socket();
ok(
    $large->send_realtime(
        { text => 'a' x $BYTE_LIMIT, bytes => $BYTE_LIMIT }
    ),
    'exact byte budget is accepted'
);
ok( !$large->send_realtime( { text => 'b', bytes => 1 } ),
    'one byte over the budget is refused' );
is( $large->realtime_pending_bytes,
    $BYTE_LIMIT, 'refused frame consumes no extra byte budget' );
my $oversized = _socket();
ok( !$oversized->send_realtime( { text => 'x', bytes => $BYTE_LIMIT + 1 } ),
    'single oversized event is refused before queuing' );
is( $oversized->realtime_pending_frames,
    0, 'oversized event consumes no frame budget' );

my $probe  = GPForum::Test::RealtimeEncodingProbe->new;
my $fanout = GPForum::Service::Realtime::Hub->new;
for my $id (qw(first second third)) {
    my $socket = _socket();
    $fanout->register_connection( $id, 'user-2', $socket );
    $fanout->registry->subscribe( $id, 'notifications:user-2' );
}
my $fanout_result =
  $fanout->broadcast( 'notifications:user-2', { payload => $probe } );
is( $fanout_result->{delivered},
    $RECIPIENTS, 'one event reaches all recipients' );
is( $probe->calls, 1,
    'JSON conversion runs once across three real transports' );
$fanout->broadcast( 'notifications:nobody', { payload => $probe } );
is( $probe->calls, 1, 'an empty channel does not serialize the payload' );

my $released = _socket();
$released->send_realtime( { text => '{}', bytes => 2 } );
weaken $released;
ok( !defined $released,
    'pending drain callback does not retain its controller' );

my $empty = $hub->broadcast( 'notifications:nobody', $event );
is( $empty->{delivered}, 0, 'empty channel has no delivery work' );
done_testing();

sub _socket {
    my $tx = Mojo::Transaction::WebSocket->new( established => 1 );
    push @transactions, $tx;
    return GPForum::Controller::Realtime->new( tx => $tx );
}

sub _drain {
    my ($controller) = @_;
    $controller->tx->server_write;
    $controller->tx->server_write;
    return;
}

1;
