# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package main;
use v5.40;
use lib 'lib';
use Const::Fast;
use Mojo::IOLoop::Stream;
use Mojo::Transaction::WebSocket;
use Mojo::WebSocket qw(build_frame WS_PING WS_TEXT);
use GPForum::Web::BoundedRealtimeStream;
use Test::More;
use Socket qw(AF_UNIX SOCK_STREAM PF_UNSPEC);
use Carp   qw(croak);
our $VERSION = '0.001';
const my $LIMIT       => 32;
const my $BYTES       => 262_144;
const my $FLOOD       => 10_000;
const my $PING_BYTES  => 125;
const my $EVENT_BYTES => 256;

subtest 'native protocol replies share the real socket bound' => sub {
    my ( $tx, $stream ) = stalled();
    my $wire = build_frame( 1, 1, 0, 0, 0, WS_PING, 'p' x $PING_BYTES );
    for ( 1 .. $FLOOD ) { $tx->server_read($wire); }
    ok( $stream->realtime_overloaded,
        'native automatic PONGs close a stalled stream' );
    cmp_ok( $stream->bytes_waiting, '<=', $BYTES,
        'protocol output stays bounded' );
    is( $stream->realtime_pending_writes,
        $LIMIT, 'only bounded writes admitted' );
};

subtest 'transaction drain cannot release socket pressure' => sub {
    my ( $tx, $stream ) = stalled();
    my $drains = 0;
    for ( 1 .. $LIMIT ) {
        $tx->send( { text => 'e' x $EVENT_BYTES }, sub (@) { ++$drains; } );

        # Exactly the daemon transfer: an empty transaction emits drain even
        # though previously transferred bytes remain in the stalled stream.
        $tx->server_read( build_frame( 1, 1, 0, 0, 0, WS_TEXT, '{}' ) );
    }
    cmp_ok( $drains, '>', 0, 'native transaction drain really occurred' );
    is( $stream->realtime_pending_writes,
        $LIMIT, 'actual stream still owns its budget' );
    $tx->send( { text => 'e' } );
    ok( $stream->realtime_overloaded,
        'next write cannot exploit premature drain' );
    cmp_ok( $stream->bytes_waiting, '<=', $BYTES,
        'event output stays bounded' );
};

subtest 'exact byte allowance and ordinary drain' => sub {
    my $stream =
      GPForum::Web::BoundedRealtimeStream->protect( Mojo::IOLoop::Stream->new );
    $stream->write( 'x' x $BYTES );
    is( $stream->bytes_waiting, $BYTES, 'exact byte limit accepted' );
    $stream->write('x');
    ok( $stream->realtime_overloaded, 'one extra byte closes' );
    is( $stream->bytes_waiting, $BYTES, 'refused write adds no bytes' );
    my ( $reader, $writer );
    socketpair $reader, $writer, AF_UNIX, SOCK_STREAM, PF_UNSPEC
      or croak 'cannot create local stream pair';
    my $normal = GPForum::Web::BoundedRealtimeStream->protect(
        Mojo::IOLoop::Stream->new($writer) );
    $normal->start;
    my $callbacks = 0;
    $normal->write( 'hello', sub (@) { ++$callbacks; } );

    $normal->reactor->one_tick;
    is( $normal->realtime_pending_writes, 0, 'socket drain releases budget' );
    is( $callbacks, 1, 'native completion callback preserved' );
    $normal->write('next');
    ok( !$normal->realtime_overloaded, 'healthy connection can continue' );
    $normal->close;
    close $reader or croak 'cannot close local stream pair';
};
done_testing;

sub stalled {
    my $stream =
      GPForum::Web::BoundedRealtimeStream->protect( Mojo::IOLoop::Stream->new );
    my $tx = Mojo::Transaction::WebSocket->new( established => 1 );

    # Same public transfer calls as Mojo::Server::Daemon::_write, but with
    # no OS drain: every transaction resume can append to the socket queue.
    $tx->on(
        resume => sub ($connection) {
            $stream->write( $connection->server_write );
        }
    );
    return ( $tx, $stream );
}
1;
