# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;
use utf8;

use Carp qw(croak);
use Const::Fast;
use English    qw(-no_match_vars);
use File::Temp qw(tempdir);
use Mojo::File qw(path);
use Mojo::Util qw(decode);
use Test::More;

use lib 'lib';

use GPForum::CLI::start;
use GPForum::OS;
use GPForum::Service::I18N::CliCatalog;
use GPForum::Service::Operations::Doctor;
use GPForum::Service::Operations::Findings;
use GPForum::Service::Operations::Host;
use GPForum::Service::Operations::ServiceFiles;

our $VERSION = '0.001';

const my $SECRET => '0123456789abcdef0123456789abcdef';

# ADR 0137: a host set up before the socket was the default upgrades with
# what each command says. The service refuses a TCP listener in the
# operator's language, the proxy is written for the socket whatever the old
# setting said, its account is told to join the gpforum group, and doctor
# says that a DSN naming the loopback reaches this host's server over TCP.

subtest 'start --service refuses TCP, saying what to set' => sub {
    my $root = tempdir( CLEANUP => 1 );
    path( $root, 'local', 'bin' )->make_path;
    path( $root, 'local', 'bin', 'hypnotoad' )->spew("#!perl\n");

    for my $case (
        [ 'en_US.UTF-8', qr/listens [ ] only [ ] on [ ] the [ ] service's/msx ],
        [ 'it_IT.UTF-8', qr/ascolta [ ] solo [ ] sul [ ] socket [ ] Unix/msx ],
      )
    {
        my ( $language, $words ) = @{$case};
        my $said = q{};
        my $status;
        {
            local $ENV{LC_ALL} = $language;
            open my $errors, '>', \$said or croak "capture: $OS_ERROR";
            local *STDERR = $errors;
            my $start = GPForum::CLI::start->new(
                root    => $root,
                replace => sub (@) { fail('nothing is run') },
            );
            $start->app->config(
                hypnotoad => { listen => ['http://127.0.0.1:8080'] } );
            $status = $start->run('--service');
            close $errors or croak "capture: $OS_ERROR";
        }
        $said = decode( 'UTF-8', $said );
        is( $status, 1, "$language: it stops, with status 1" );
        like( $said, $words, "$language: in the operator's language" );
        like(
            $said,
            qr{http://127[.]0[.]0[.]1:8080}msx,
            "$language: naming the address"
        );
        like( $said, qr{GPFORUM_RUNTIME_LISTEN}msx,
            "$language: and the setting" );
        unlike(
            $said,
            qr/ [ ] at [ ] \S+ [ ] line [ ] \d+/msx,
            "$language: no file and line"
        );
    }
};

subtest 'the proxy is written for the socket, and its account joins' => sub {
    for my $os (qw(linux freebsd darwin)) {
        my $files = GPForum::Service::Operations::ServiceFiles->new(
            home        => '/srv/forum',
            host        => _host($os),
            environment => {
                GPFORUM_PUBLIC_BASE_URL => 'https://forum.walk.org',
                GPFORUM_RUNTIME_LISTEN  => 'http://127.0.0.1:8080',
            },
        );
        for my $proxy (qw(nginx caddy)) {
            my ($rendered) = @{ $files->render($proxy) };
            like(
                $rendered->{text},
                qr{unix[:/] /srv/forum/var/run/gpforum[.]sock}msx,
                "$os $proxy: the default socket, not the old TCP address"
            );
            unlike( $rendered->{text}, qr/127[.]0[.]0[.]1:8080/msx,
                "$os $proxy: no TCP upstream" );

            my ($group) =
              grep { $_->[0] eq 'cli.service.proxy_group' }
              @{ $files->notes($proxy) };
            ok( $group, "$os $proxy: a note says the proxy joins the group" );
            is(
                $group->[1]{socket},
                '/srv/forum/var/run/gpforum.sock',
                "$os $proxy: naming the socket"
            );
            like( $group->[1]{join},
                qr/gpforum/msx,
                "$os $proxy: with the command that adds its account" );
        }
    }

    my $text =
      GPForum::Service::I18N::CliCatalog->new( language => 'en' )->text(
        'cli.service.proxy_group',
        {
            socket  => '/opt/gpforum/var/run/gpforum.sock',
            account => 'www-data',
            proxy   => 'nginx',
            join    => 'sudo usermod -aG gpforum www-data',
        }
      );
    like(
        $text,
        qr/only [ ] the [ ] gpforum [ ] group [ ] may [ ] open/msx,
        'the note in English'
    );
};

subtest 'doctor: a deployed DSN that names the loopback' => sub {
    my $text = _doctor_database( 'production',
        'dbi:Pg:dbname=gpforum;host=127.0.0.1;port=5432' );
    _has( $text, "\n! database: reached over TCP at 127.0.0.1:5432,",
        'is a finding' );
    _has(
        $text,
        'Fix: remove host=127.0.0.1 from GPFORUM_DATABASE_DSN in'
          . q{ /etc/gpforum/gpforum.env, or set it to the server's socket}
          . ' directory, host=/var/run/postgresql',
        'with the fix, in the file the service reads'
    );

    unlike(
        _doctor_database( 'production', 'dbi:Pg:dbname=gpforum' ),
        qr/over [ ] TCP/msx,
        'the socket is fine'
    );
    unlike(
        _doctor_database( 'production', 'dbi:Pg:dbname=gpforum;host=db.lan' ),
        qr/over [ ] TCP/msx,
        'and so is a database on another host'
    );
    unlike(
        _doctor_database(
            'development', 'dbi:Pg:dbname=gpforum;host=127.0.0.1'
        ),
        qr/over [ ] TCP/msx,
        'and a development checkout'
    );
};

sub _has ( $text, $literal, $name ) {
    return ok( index( $text, $literal ) >= 0, $name ) || diag $text;
}

sub _host ($os) {
    return GPForum::Service::Operations::Host->new(
        catalog => GPForum::Service::I18N::CliCatalog->new( language => 'en' ),
        environment => 'production',
        os          => GPForum::OS->from_name($os),
    );
}

# The database lines doctor writes, on Linux, for a DSN.
sub _doctor_database ( $environment, $dsn ) {
    my $doctor = GPForum::Service::Operations::Doctor->new(
        catalog => GPForum::Service::I18N::CliCatalog->new( language => 'en' ),
        environment => {
            GPFORUM_ENV             => $environment,
            GPFORUM_DATABASE_DSN    => $dsn,
            GPFORUM_MAIL_FROM       => 'forum@forum.walk.org',
            GPFORUM_METRICS_TOKEN   => 'metrics-token',
            GPFORUM_PUBLIC_BASE_URL => 'https://forum.walk.org',
            GPFORUM_SESSION_SECRET  => $SECRET,
        },
        file   => '/etc/gpforum/gpforum.env',
        os     => GPForum::OS->from_name('linux'),
        probes => {
            database => sub { return { schema => undef, version => '18.6' } },
            schema   => sub { return { latest => '121', pending => [] } },
            budgets  => sub {
                return { missing => [], extra => [], mismatched => [] };
            },
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
