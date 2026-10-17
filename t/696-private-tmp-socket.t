# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;
use utf8;

use Const::Fast;
use File::Temp qw(tempdir);
use Mojo::File qw(path);
use Test::More;

use lib 'lib';

use GPForum::OS;
use GPForum::Service::I18N::CliCatalog;
use GPForum::Service::Operations::Doctor;
use GPForum::Service::Operations::Findings;
use GPForum::Service::Operations::Host;
use GPForum::Service::Operations::ServiceFiles;
use GPForum::Service::Operations::ServiceUnits;

our $VERSION = '0.001';

const my $SECRET => '0123456789abcdef0123456789abcdef';

# ADR 0137: the units run with PrivateTmp=true, which gives each service a
# /tmp and a /var/tmp of its own. A PostgreSQL built from source, or one
# packaged that way, keeps its socket in /tmp: the service then found no
# socket while gpforum doctor, run outside the unit, connected. The printed
# units see a socket directory under /tmp through a read-only binding, and
# give up the private /tmp for /tmp itself, saying how to get it back;
# doctor says when an installed unit cannot see the socket.

sub _units ( $dsn, $name = 'gpforum.service' ) {
    my $files = GPForum::Service::Operations::ServiceFiles->new(
        home => '/opt/gpforum',
        host => GPForum::Service::Operations::Host->new(
            catalog =>
              GPForum::Service::I18N::CliCatalog->new( language => 'en' ),
            environment => 'production',
            os          => GPForum::OS->from_name('linux'),
        ),
        environment => { GPFORUM_DATABASE_DSN => $dsn },
    );
    my ($unit) = @{ $files->render( 'systemd', [$name] ) };

    return $unit->{text};
}

subtest 'the printed units see the socket' => sub {
    my $distribution = _units('dbi:Pg:dbname=gpforum');
    like( $distribution, qr/^PrivateTmp=true$/msx,
        q{Debian's /var/run/postgresql: the private /tmp stays} );
    unlike( $distribution, qr/^BindReadOnlyPaths=/msx, 'with no binding' );

    my $below = _units('dbi:Pg:dbname=gpforum;host=/tmp/pg;port=5433');
    like(
        $below,
        qr{^PrivateTmp=true\nBindReadOnlyPaths=/tmp/pg$}msx,
        'a directory under /tmp: bound, read-only, into the private one'
    );

    for my $directory (qw(/tmp /var/tmp)) {
        my $in = _units("dbi:Pg:dbname=gpforum;host=$directory");
        like( $in, qr/^PrivateTmp=false$/msx,
            "$directory itself: no private one, or no socket" );
        like(
            $in,
            qr/unix_socket_directories/msx,
            'and the unit says how to have it back'
        );
    }

    like( _units('dbi:Pg:dbname=gpforum;host=db.lan'),
        qr/^PrivateTmp=true$/msx, 'a database on another host: unchanged' );
    for my $name (
        qw(gpforum-outbox.service gpforum-scheduled-jobs.service
        gpforum-partition-maintenance.service)
      )
    {
        like(
            _units( 'dbi:Pg:dbname=gpforum;host=/tmp/pg', $name ),
            qr{^BindReadOnlyPaths=/tmp/pg$}msx,
            "$name, which connects too"
        );
    }
};

subtest 'doctor: an installed unit that cannot see the socket' => sub {
    my $directory = tempdir( CLEANUP => 1 );
    path( $directory, 'gpforum.service' )
      ->spew( path('deploy/systemd/gpforum.service')->slurp );
    my $text = _doctor_database( $directory, '/tmp/.s.PGSQL.5432' );
    ok(
        index( $text,
                "\N{BALLOT X} database socket: gpforum.service runs with"
              . q{ PrivateTmp=true} ) >= 0,
        q{a finding, naming the unit}
    );
    like(
        $text,
        qr/gpforum [ ] service [ ] print [ ] systemd/msx,
        'with the units that see it'
    );

    path( $directory, 'gpforum.service' )
      ->spew( _units('dbi:Pg:dbname=gpforum;host=/tmp') );
    unlike( _doctor_database( $directory, '/tmp/.s.PGSQL.5432' ),
        qr/PrivateTmp/msx, 'the printed unit is fine' );
    unlike( _doctor_database( $directory, '/var/run/postgresql/.s.PGSQL.5432' ),
        qr/PrivateTmp/msx, 'and so is a socket outside /tmp' );
};

# Doctor's database lines, on Linux, for a connection through a socket and
# the units installed in a directory.
sub _doctor_database ( $units, $socket ) {
    my $catalog = GPForum::Service::I18N::CliCatalog->new( language => 'en' );
    my $host    = GPForum::Service::Operations::Host->new(
        catalog     => $catalog,
        environment => 'production',
        os          => GPForum::OS->from_name('linux'),
    );
    my $doctor = GPForum::Service::Operations::Doctor->new(
        catalog     => $catalog,
        environment => {
            GPFORUM_ENV             => 'production',
            GPFORUM_DATABASE_DSN    => 'dbi:Pg:dbname=gpforum',
            GPFORUM_MAIL_FROM       => 'forum@forum.walk.org',
            GPFORUM_METRICS_TOKEN   => 'metrics-token',
            GPFORUM_PUBLIC_BASE_URL => 'https://forum.walk.org',
            GPFORUM_SESSION_SECRET  => $SECRET,
        },
        file  => '/etc/gpforum/gpforum.env',
        os    => GPForum::OS->from_name('linux'),
        units => GPForum::Service::Operations::ServiceUnits->new(
            directory => $units,
            host      => $host,
        ),
        probes => {
            database => sub {
                return {
                    schema  => undef,
                    version => '18.6',
                    server  => $socket,
                };
            },
            schema  => sub { return { latest => '121', pending => [] } },
            budgets => sub {
                return { missing => [], extra => [], mismatched => [] };
            },
        },
    );
    my %state = (
        config   => GPForum::Config->from_environment( $doctor->environment ),
        findings => GPForum::Service::Operations::Findings->new(
            catalog => $catalog
        ),
    );
    $doctor->_database( \%state );

    return $state{findings}->human_text( summary => 0 );
}

done_testing();

1;
