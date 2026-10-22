# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use File::Temp qw(tempdir);
use Mojo::IOLoop;
use Mojo::Server::Daemon;
use Mojo::UserAgent;
use Mojo::Util qw(url_escape);
use Mojolicious;
use Test::More;

use lib 'lib';

use GPForum::OS::UnixListener;

our $VERSION = '0.001';

const my $MODE_BITS     => oct '7777';
const my $SERVICE_UMASK => oct '027';
const my $SOCKET_MODE   => oct '660';
const my $HTTP_OK       => 200;
const my $INODE         => 1;

# The service runs under umask 027, so an upload is the gpforum group's to
# read and nobody else's to write: the proxy's account is in that group. The
# proxy must still write to the socket to connect, so the socket alone is
# bound with the group's read and write, before the first worker accepts.

local $ENV{MOJO_REUSE} = q{};
my $directory = tempdir( 'gpfulXXXX', DIR => '/tmp', CLEANUP => 1 );
my $socket    = "$directory/gpforum.sock";
my $listen    = 'http+unix://' . url_escape($socket);

my $previous = umask $SERVICE_UMASK;
my $app      = Mojolicious->new;
$app->log->level('fatal');
$app->routes->get( q{/} => sub ($c) { $c->render( text => 'here' ) } );
GPForum::OS::UnixListener->register($app);

my $daemon = Mojo::Server::Daemon->new(
    app    => $app,
    listen => [$listen],
    silent => 1,
)->start;
is( ( stat $socket )[2] & $MODE_BITS,
    $SOCKET_MODE,
    'the socket is the group\'s to read and write, nobody else\'s' );
is( umask, $SERVICE_UMASK, 'and the service keeps its own umask' );
like(
    $ENV{MOJO_REUSE},
    qr/\A unix: \Q$socket\E : \d+ \z/msx,
    'the socket is handed on as Hypnotoad hands its own to an upgrade'
);

my $code;
my $ua = Mojo::UserAgent->new( ioloop => Mojo::IOLoop->singleton );
$ua->get_p("$listen/")->then( sub ($tx) { $code = $tx->res->code } )->wait;
is( $code, $HTTP_OK, 'the daemon serves on the socket it was given' );

my $inode = ( stat $socket )[$INODE];
my $again = Mojo::Server::Daemon->new(
    app    => $app,
    listen => [$listen],
    silent => 1,
);
GPForum::OS::UnixListener->bind_listeners($again);
is( ( stat $socket )[$INODE],
    $inode,
    'an upgrade keeps the socket it inherits rather than binding anew' );

my $tcp = Mojo::Server::Daemon->new(
    app    => $app,
    listen => ['http://127.0.0.1'],
    silent => 1,
);
my $reuse = $ENV{MOJO_REUSE};
GPForum::OS::UnixListener->bind_listeners($tcp);
is( $ENV{MOJO_REUSE}, $reuse, 'a TCP listener is left to Mojolicious' );

$daemon->stop;
umask $previous;

done_testing();

1;
