# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use Digest::SHA qw(sha256_hex);
use English     qw(-no_match_vars);
use File::Temp  qw(tempdir);
use Mojo::File  qw(path);
use Mojo::UserAgent;
use Mojo::Util qw(url_escape);
use POSIX      qw(WNOHANG);
use Test::More;
use Time::HiRes qw(sleep);

use lib 'lib';
use lib 't/lib';

use GPForum::Service::Password;
use GPForum::Test::PostgresHarness;

our $VERSION = '0.001';

const my $HTTP_FOUND            => 302;
const my $HTTP_TOO_MANY         => 429;
const my $LOGIN_LIMIT           => 10;
const my $START_POLLS           => 300;
const my $POLL_SECONDS          => 0.1;
const my $STOP_POLLS            => 100;
const my $MODE_BITS             => oct '7777';
const my $SOCKET_MODE           => oct '660';
const my $SOCKET_DIRECTORY_MODE => oct '750';
const my $PASSWORD              => 'correct horse battery';
const my $CLIENT_A              => '203.0.113.10';
const my $CLIENT_B              => '203.0.113.20';
const my $CLIENT_C              => '2001:db8::30';
const my $FORGED                => '198.51.100.99';
const my $LOGIN_AUDIT_ADDRESS => q{SELECT metadata->>'request_address_hash'}
  . q{ FROM audit_log WHERE action = 'identity.login.requested'}
  . q{ ORDER BY created_at};

if ( !$ENV{GPFORUM_DATABASE_DSN} ) {
    plan skip_all => 'set GPFORUM_DATABASE_DSN to run the Unix socket test';
}

# Hypnotoad on its Unix socket behind a proxy, as the service runs: the
# connection has no peer address, and every client used to share the
# constant the controllers fell back to -- twelve failed logins from twelve
# addresses met one 429, and the audit rows hashed 'unknown'. Each client
# is now the X-Forwarded-For entry the proxy appended.
local $ENV{GPFORUM_MINION_ENABLED}            = 0;
local $ENV{GPFORUM_REALTIME_LISTENER_ENABLED} = 0;
my $database =
  GPForum::Test::PostgresHarness::create_database( $ENV{GPFORUM_DATABASE_DSN} );
local $ENV{GPFORUM_DATABASE_DSN} = $database->{dsn};
is( GPForum::Test::PostgresHarness::prepare_database()->{migrate},
    0, 'migrations apply' );

my $schema = GPForum::Test::PostgresHarness::connect_schema();
my $dbh    = $schema->storage->dbh;
_member( $dbh, 'socketmember' );

# A short directory: a socket path is limited to about a hundred bytes.
my $directory = tempdir( 'gpfsockXXXX', DIR => '/tmp', CLEANUP => 1 );
my $socket    = "$directory/run/gpforum.sock";
my $service   = _start_service( $directory, $socket );

# The service runs under umask 027; the socket alone is the group's to write,
# since the proxy's account joins the group (GPForum::OS::UnixListener).
is( ( stat $socket )[2] & $MODE_BITS,
    $SOCKET_MODE,
    'the socket is the group\'s to read and write, nobody else\'s' );
is( ( stat "$directory/run" )[2] & $MODE_BITS,
    $SOCKET_DIRECTORY_MODE, 'and its directory the group\'s to enter only' );

for ( 1 .. $LOGIN_LIMIT ) {
    _failed_login( $socket, $CLIENT_A );
}
is( _failed_login( $socket, $CLIENT_A ),
    $HTTP_TOO_MANY, 'one client meets the login limit' );
is( _failed_login( $socket, "$FORGED, $CLIENT_A" ),
    $HTTP_TOO_MANY,
    'and an entry it forged ahead of the proxy does not free it' );
isnt( _failed_login( $socket, $CLIENT_B ),
    $HTTP_TOO_MANY, 'another client has a bucket of its own' );

is( _login( $socket, $CLIENT_B, $PASSWORD ),
    $HTTP_FOUND, 'a member signs in from one address' );
is( _login( $socket, "$FORGED, $CLIENT_C", $PASSWORD ),
    $HTTP_FOUND, 'and from another, behind a forged entry' );
is_deeply(
    $dbh->selectcol_arrayref($LOGIN_AUDIT_ADDRESS),
    [ sha256_hex($CLIENT_B), sha256_hex($CLIENT_C) ],
    'the audit rows carry the addresses the proxy saw'
);

_stop_service($service);
$schema->storage->disconnect;
GPForum::Test::PostgresHarness::drop_database($database);

done_testing();

sub _member ( $dbh, $username ) {
    my $hash = GPForum::Service::Password->new->hash_password($PASSWORD);
    my ($user) = $dbh->selectrow_array(
        q{INSERT INTO users (id, username, display_name, email_normalized,}
          . q{ password_hash, status) VALUES (gen_random_uuid(), ?, ?, ?, ?,}
          . q{ 'active') RETURNING id},
        undef, $username, $username, "$username\@example.test", $hash
    );
    $dbh->do(
        q{INSERT INTO credentials (id, user_id, type, secret_hash)}
          . q{ VALUES (gen_random_uuid(), ?, 'password', ?)},
        undef, $user, $hash
    );

    return $user;
}

sub _start_service ( $directory, $socket ) {
    path("$directory/env")->spew(q{});
    my %environment = (
        GPFORUM_ENV              => 'development',
        GPFORUM_ENV_FILE         => "$directory/env",
        GPFORUM_LOG_PATH         => "$directory/service.log",
        GPFORUM_RUNTIME_LISTEN   => 'http+unix://' . url_escape($socket),
        GPFORUM_RUNTIME_PID_FILE => "$directory/hypnotoad.pid",
        GPFORUM_WARMUP_ENABLED   => 0,
        GPFORUM_WEB_PROCESSES    => 1,
    );
    my $pid = fork // BAIL_OUT("cannot fork: $OS_ERROR");
    if ( !$pid ) {
        local @ENV{ keys %environment } = values %environment;
        open STDOUT, '>',  "$directory/service.out" or POSIX::_exit(1);
        open STDERR, '>&', \*STDOUT                 or POSIX::_exit(1);
        exec {$EXECUTABLE_NAME} $EXECUTABLE_NAME, 'bin/gpforum', 'start',
          '--service', '--foreground'
          or POSIX::_exit(1);
    }

    for ( 1 .. $START_POLLS ) {
        last if -S $socket && _status( $socket, '/health/live' );
        if ( waitpid( $pid, WNOHANG ) == $pid ) {
            BAIL_OUT( 'the service stopped: '
                  . path("$directory/service.out")->slurp );
        }
        sleep $POLL_SECONDS;
    }
    ok( -S $socket, 'Hypnotoad listens on its Unix socket' );

    return $pid;
}

sub _stop_service ($pid) {
    kill 'TERM', $pid;
    for ( 1 .. $STOP_POLLS ) {
        return if waitpid( $pid, WNOHANG ) == $pid;
        sleep $POLL_SECONDS;
    }
    kill 'KILL', $pid;
    waitpid $pid, 0;

    return;
}

# A client of the proxy: its own cookies, and the X-Forwarded-For the proxy
# sends for it.
sub _client ( $socket, $forwarded ) {
    my $ua = Mojo::UserAgent->new;
    $ua->on(
        start => sub ( $, $tx ) {
            $tx->req->headers->header( 'X-Forwarded-For' => $forwarded );
        }
    );

    return { ua => $ua, base => 'http+unix://' . url_escape($socket) };
}

sub _status ( $socket, $route ) {
    my $tx = Mojo::UserAgent->new->get(
        'http+unix://' . url_escape($socket) . $route );

    return $tx->res->code;
}

sub _failed_login ( $socket, $forwarded ) {
    return _login( $socket, $forwarded, 'not the password', 'nobody-here' );
}

sub _login ( $socket, $forwarded, $password, $identifier = 'socketmember' ) {
    my $client = _client( $socket, $forwarded );
    my $form   = $client->{ua}->get("$client->{base}/login")->res->dom;
    my $csrf   = $form->at('input[name=csrf_token]');
    my $tx     = $client->{ua}->post(
        "$client->{base}/login" => form => {
            csrf_token => $csrf ? $csrf->attr('value') : q{},
            identifier => $identifier,
            password   => $password,
        }
    );

    return $tx->res->code;
}

1;
