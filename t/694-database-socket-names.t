# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;
use utf8;

use Const::Fast;
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::OS::Darwin;
use GPForum::OS::FreeBSD;
use GPForum::OS::Linux;
use GPForum::Service::Operations::DatabaseFailure;
use GPForum::Service::Operations::DatabaseProvisioning;
use GPForum::Service::Operations::Doctor;

our $VERSION = '0.001';

# ADR 0137: a DSN without host= reaches PostgreSQL through libpq's socket
# directory, and the operator reads the socket's path -- not "unix:5432",
# which names nothing on the host -- and, when the socket is not there, that
# it is not there, not that a connection was refused.

const my $PROVISIONING => 'GPForum::Service::Operations::DatabaseProvisioning';
const my $MISSING => 'DBIx::Class::Storage::DBI::catch {...} (): '
  . q{DBI Connection failed: DBI connect('dbname=gpforum','gpforum',...)}
  . ' failed: connection to server on socket'
  . ' "/var/run/postgresql/.s.PGSQL.5432" failed: No such file or directory'
  . "\n\tIs the server running locally and accepting connections on that"
  . ' socket?';
const my $ITALIAN_MISSING =>
  q{DBI connect('dbname=gpforum','gpforum',...) failed: connessione al}
  . ' server sul socket "/tmp/.s.PGSQL.5432" fallita: File o directory non'
  . ' esistente';

subtest q{libpq's default socket directory, by operating system} => sub {
    is(
        GPForum::OS::Linux->new->postgresql_socket_directory,
        '/var/run/postgresql',
        'Debian, Ubuntu and Red Hat'
    );
    is( GPForum::OS::Darwin->new->postgresql_socket_directory,
        '/tmp', q{Homebrew's} );
    is( GPForum::OS::FreeBSD->new->postgresql_socket_directory,
        '/tmp', q{the ports'} );
};

subtest 'a server is named by its socket' => sub {
    my $linux = GPForum::OS::Linux->new;
    is(
        $PROVISIONING->server_name(
            $PROVISIONING->data_source('dbi:Pg:dbname=gpforum'), $linux
        ),
        '/var/run/postgresql/.s.PGSQL.5432',
        'no host: the socket in the default directory'
    );
    is(
        $PROVISIONING->server_name(
            $PROVISIONING->data_source(
                'dbi:Pg:dbname=gpforum;host=/tmp/gpfv;port=55433'),
            $linux
        ),
        '/tmp/gpfv/.s.PGSQL.55433',
        'a directory: the socket in it'
    );
    is(
        $PROVISIONING->server_name(
            $PROVISIONING->data_source('dbi:Pg:dbname=gpforum;host=db.lan'),
            $linux
        ),
        'db.lan:5432',
        'a TCP host: host and port'
    );
};

subtest 'doctor names the socket it connected through' => sub {
    my $connected = _doctor_line(
        {
            server  => '/var/run/postgresql/.s.PGSQL.5432',
            version => '18.6',
        }
    );
    like(
        $connected,
        qr{gpforum [ ] at [ ] /var/run/postgresql/[.]s[.]PGSQL[.]5432}msx,
        'the socket the connection used'
    );
    unlike( $connected, qr/unix:/msx, 'never unix:PORT' );

    like(
        _doctor_line( { version => '18.6' } ),
        qr{gpforum [ ] at [ ] /var/run/postgresql/[.]s[.]PGSQL[.]5432}msx,
        q{without one, the DSN's, in libpq's default directory}
    );
};

subtest 'a missing socket is said as missing' => sub {
    my $failure = GPForum::Service::Operations::DatabaseFailure->new(
        os          => GPForum::OS::Linux->new,
        environment => 'production',
        language    => 'en',
    );
    my $classified = $failure->classify($MISSING);
    is( $classified->{key}, 'database.no_socket', 'its own failure' );
    is(
        $failure->sentence($MISSING),
        'There is no PostgreSQL socket at /var/run/postgresql/.s.PGSQL.5432:'
          . ' start PostgreSQL with sudo systemctl start postgresql, or set'
          . ' host= in GPFORUM_DATABASE_DSN in /etc/gpforum/gpforum.env to'
          . ' the directory that holds its socket.',
        'naming the socket, not a refused connection'
    );
    is( $failure->classify($ITALIAN_MISSING)->{parameters}{server},
        '/tmp/.s.PGSQL.5432', 'and from a libpq speaking Italian' );

    my $italian = GPForum::Service::Operations::DatabaseFailure->new(
        os          => GPForum::OS::Linux->new,
        environment => 'production',
        language    => 'it',
    );
    my $expected = q{Non c'è alcun socket di PostgreSQL in}
      . ' /var/run/postgresql/.s.PGSQL.5432:';
    is( substr( $italian->sentence($MISSING), 0, length $expected ),
        $expected, 'in the operator language' );
};

# The database line doctor writes for a probe's answer, on Linux.
sub _doctor_line ($answer) {
    my $doctor = GPForum::Service::Operations::Doctor->new(
        environment => {
            GPFORUM_ENV          => 'development',
            GPFORUM_DATABASE_DSN => 'dbi:Pg:dbname=gpforum',
        },
        os     => GPForum::OS::Linux->new,
        probes => {
            database => sub { return { schema => undef, %{$answer} } },
            schema   => sub { return { latest => '121', pending => [] } },
            budgets  => sub {
                return { missing => [], extra => [], mismatched => [] };
            },
            preflight => sub { return { status => 'ok', checks => [] } },
            sizing    => sub { return {} },
        },
    );
    my %state = (
        config   => GPForum::Config->from_environment( $doctor->environment ),
        findings => GPForum::Service::Operations::Findings->new(
            catalog => $doctor->catalog
        ),
    );
    $doctor->_database( \%state );

    return $state{findings}->human_text( summary => 0 );
}

done_testing();

1;
