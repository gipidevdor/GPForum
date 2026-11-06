# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package main;
use v5.40;
use Test::More;
use Const::Fast;
use Mojo::IOLoop;
use Mojo::Pg;
use Mojo::Promise;
use lib 'lib', 't/lib';
use GPForum::Infrastructure::PgConnect;
use GPForum::Test::Promise qw(await_result);
our $VERSION = '0.001';
const my $TICK_SECONDS  => 0.01;
const my $OTHER_SECONDS => 0.03;
const my $MIN_TICKS     => 3;
my @streams;
my $server = Mojo::IOLoop->server(
    { address => '127.0.0.1', port => 0 } => sub ( $loop, $stream, $id ) {
        push @streams, $stream;
        $stream->timeout(0);
        return;
    }
);
my $port = Mojo::IOLoop->acceptor($server)->port;
my $pg   = Mojo::Pg->new->dsn(
    "dbi:Pg:dbname=async_probe;host=127.0.0.1;port=$port;sslmode=disable")
  ->username('async_probe');
my $connector = GPForum::Infrastructure::PgConnect->new( timeout => 0.15 );
my ( $ticks, $other, $error ) = ( 0, 0, undef );
my $timer =
  Mojo::IOLoop->recurring( $TICK_SECONDS => sub { $ticks++; return; } );
my $independent = Mojo::Promise->new;
Mojo::IOLoop->timer(
    $OTHER_SECONDS => sub { $other = 1; $independent->resolve; return; } );
my $connect = $connector->connect_p($pg)
  ->catch( sub ($failure) { $error = "$failure"; return; } );
await_result( Mojo::Promise->all( $connect, $independent ) );
Mojo::IOLoop->remove($timer);
ok( $other, 'unrelated work completes while a PostgreSQL handshake is silent' );
cmp_ok( $ticks, '>=', $MIN_TICKS,
    'connection establishment never blocks the reactor' );
like(
    $error,
    qr/connection[ ]deadline[ ]exceeded/msx,
    'a silent peer reaches the bounded handshake deadline'
);
my $ids = scalar @streams;
await_result( $connector->connect_p($pg)->catch( sub { return; } ) );
is( scalar @streams,
    $ids + 1, 'a timed-out connector can start a fresh connection' );
for my $stream (@streams) { $stream->close; }
Mojo::IOLoop->remove($server);
done_testing();

1;
