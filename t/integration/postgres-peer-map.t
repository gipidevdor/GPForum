# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use DBI;
use English    qw(-no_match_vars);
use File::Temp qw(tempdir);
use Mojo::File qw(path);
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::OS::Linux;
use GPForum::Service::Operations::DatabaseFailure;
use GPForum::Service::Operations::PeerAuthentication;

our $VERSION = '0.001';

# ADR 0137: peer authentication over the socket, as a distribution sets it
# up -- `local all all peer`, no map -- refused the web service's runtime
# role and the operator's owner role. With the lines gpforum setup prints,
# a cluster of the test's own, on a socket of its own, lets the service's
# account in as both of the forum's roles and nobody else. The account is
# whoever runs the test, standing for gpforum.

const my $PORT_BASE  => 54_000;
const my $PORT_RANGE => 1_000;

my $required = $ENV{GPFORUM_REQUIRE_PEER_TEST};
if ( !$ENV{GPFORUM_DATABASE_DSN} && !$required ) {
    plan skip_all => 'set GPFORUM_DATABASE_DSN to run the PostgreSQL tier';
}
my $bin = _server_bin();
if ( !defined $bin || $EFFECTIVE_USER_ID == 0 ) {
    if ($required) {
        BAIL_OUT( 'GPFORUM_REQUIRE_PEER_TEST is set, but there is no initdb'
              . ' to run, or this is root' );
    }
    plan skip_all => 'needs initdb and pg_ctl, and an account other than root';
}

my $login = getpwuid $EFFECTIVE_USER_ID;
my $peer  = GPForum::Service::Operations::PeerAuthentication->new(
    os       => GPForum::OS::Linux->new,
    database => 'gpforum',
    account  => $login,
    operator => 'alice',
);

subtest 'the lines' => sub {
    is_deeply(
        $peer->hba_lines,
        ['local   gpforum   gpforum,gpforum_runtime   peer map=gpforum'],
        'one pg_hba.conf line: the forum database and roles, through the map'
    );
    is_deeply(
        $peer->ident_lines,
        [
            "gpforum   $login   gpforum",
            "gpforum   $login   gpforum_runtime",
            'gpforum   alice   gpforum',
        ],
        q{the service's account as both roles, the operator as the owner}
    );
};

# A short directory: a socket path is limited to about a hundred bytes.
my $directory = tempdir( 'gpfpeerXXXX', DIR => '/tmp', CLEANUP => 1 );
my $data      = "$directory/data";
my $port      = $PORT_BASE + $PROCESS_ID % $PORT_RANGE;
local $ENV{LC_ALL} = 'en_US.UTF-8';    # Homebrew's postmaster needs one
_run( "$bin/initdb", '-D', $data, '-U', 'postgres', '--auth=trust' );
path( $data, 'postgresql.auto.conf' )
  ->spew( "listen_addresses = ''\nunix_socket_directories = '$directory'\n"
      . "port = $port\nfsync = off\n" );
_debian_rules();
_run( "$bin/pg_ctl", '-D', $data, '-l', "$directory/log", '-w', 'start' );
my $started = 1;

my $admin = _connect( 'postgres', 'postgres' );
for my $statement (
    'CREATE ROLE gpforum LOGIN',
    'CREATE ROLE gpforum_runtime LOGIN NOINHERIT',
    'CREATE ROLE gpforum_intruder LOGIN',
    'CREATE DATABASE gpforum OWNER gpforum',
  )
{
    $admin->do($statement);
}

subtest q{a distribution's own rules refuse the forum's roles} => sub {
    for my $role (qw(gpforum gpforum_runtime)) {
        my $error = _refusal($role);
        ok(
            GPForum::Service::Operations::PeerAuthentication->is_refusal(
                $error),
            "$role: peer authentication refuses $login"
        );
        is(
            GPForum::Service::Operations::DatabaseFailure->new(
                os          => GPForum::OS::Linux->new,
                environment => 'production',
                language    => 'en',
            )->classify($error)->{key},
            'database.peer',
            "$role: and the operator reads it as such"
        );
    }
};

subtest 'with the lines setup prints, both roles and nobody else' => sub {
    path( $data, 'pg_hba.conf' )
      ->spew( join "\n", @{ $peer->hba_lines }, _debian_lines(), q{} );
    path( $data, 'pg_ident.conf' )
      ->spew( join "\n", @{ $peer->ident_lines }, q{} );
    $admin->do('SELECT pg_reload_conf()');
    my ($errors) = $admin->selectrow_array(
        'SELECT count(*) FROM pg_hba_file_rules WHERE error IS NOT NULL');
    is( $errors, 0, 'PostgreSQL reads every line' );

    for my $role (qw(gpforum gpforum_runtime)) {
        my $dbh = _connect( $role, 'gpforum' );
        is( scalar $dbh->selectrow_array('SELECT current_user'),
            $role, "$login connects as $role" );
        $dbh->disconnect;
    }
    ok( _refusal('gpforum_intruder'),      'and as no other role' );
    ok( _refusal( 'gpforum', 'postgres' ), 'nor to another database' );
};

$admin->disconnect;

END {
    if ($started) {
        system "$bin/pg_ctl", '-D', $data, '-m', 'immediate', '-s', 'stop';
    }
}

# Debian's pg_hba.conf, as far as local connections go.
sub _debian_lines {
    return ( 'local   all   postgres   trust', 'local   all   all   peer' );
}

sub _debian_rules {
    path( $data, 'pg_hba.conf' )->spew( join "\n", _debian_lines(), q{} );
    return;
}

sub _connect ( $role, $database ) {
    return DBI->connect( "dbi:Pg:dbname=$database;host=$directory;port=$port",
        $role, q{}, { AutoCommit => 1, PrintError => 0, RaiseError => 1 } );
}

# What the server said when it refused the role, or undef when it let it in.
sub _refusal ( $role, $database = 'gpforum' ) {
    my $dbh =
      DBI->connect( "dbi:Pg:dbname=$database;host=$directory;port=$port",
        $role, q{}, { AutoCommit => 1, PrintError => 0, RaiseError => 0 } );
    return 'DBI connect failed: ' . DBI->errstr if !$dbh;

    $dbh->disconnect;
    return undef;
}

# The directory initdb and pg_ctl are in: the PATH's, else the newest of
# Debian's /usr/lib/postgresql/N/bin.
sub _server_bin {
    my @candidates = (
        ( split /:/msx, $ENV{PATH} // q{} ),
        reverse sort glob '/usr/lib/postgresql/*/bin'
    );
    for my $entry (@candidates) {
        return $entry if -x "$entry/initdb" && -x "$entry/pg_ctl";
    }

    return undef;
}

# Runs a server program with its chatter in the log directory, and stops
# the test when it fails.
sub _run (@command) {
    my $status = system {'/bin/sh'} '/bin/sh', '-c',
      'exec "$@" >>"$0" 2>&1', "$directory/programs.log", @command;
    if ( $status != 0 ) {
        BAIL_OUT(
            "@command failed: " . path( $directory, 'programs.log' )->slurp );
    }

    return;
}

done_testing();

1;
