# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;
use utf8;

use Const::Fast;
use Test::More;

use lib 'lib';

use GPForum::Config;
use GPForum::OS;
use GPForum::Service::I18N::CliCatalog;
use GPForum::Service::Operations::DatabaseFailure;
use GPForum::Service::Operations::Doctor;
use GPForum::Service::Operations::Findings;
use GPForum::Service::Operations::PeerAuthentication;

our $VERSION = '0.001';

# ADR 0137 with ADR 0127: over the socket, a distribution's `local all all
# peer` lets an account in only as the role of its name, so the web service
# (gpforum) was refused as gpforum_runtime and the operator's migrate as
# gpforum. The map setup prints lets in exactly those; doctor, refused,
# says which account was refused which role and repeats the lines, and it
# checks the operator's connection when the file names one.
# t/integration/postgres-peer-map.t runs the lines on a cluster.

const my $SECRET => '0123456789abcdef0123456789abcdef';
const my $REFUSED => q{DBI connect('dbname=gpforum','gpforum_runtime',...)}
  . ' failed: connection to server on socket'
  . ' "/var/run/postgresql/.s.PGSQL.5432" failed: FATAL:  Peer'
  . ' authentication failed for user "gpforum_runtime"';
const my $ITALIAN => q{DBI connect('dbname=gpforum','gpforum',...) failed:}
  . ' connessione al server sul socket "/tmp/.s.PGSQL.5432" fallita:'
  . q{ FATALE:  autenticazione peer fallita per l'utente "gpforum"};

subtest 'the lines' => sub {
    my $peer = GPForum::Service::Operations::PeerAuthentication->new(
        os       => GPForum::OS->from_name('linux'),
        operator => 'alice',
    );
    is_deeply(
        $peer->plan,
        {
            hba =>
              ['local   gpforum   gpforum,gpforum_runtime   peer map=gpforum'],
            ident => [
                'gpforum   gpforum   gpforum',
                'gpforum   gpforum   gpforum_runtime',
                'gpforum   alice   gpforum',
            ],
            reload => q{sudo -u postgres psql -c 'SELECT pg_reload_conf()'},
        },
        q{the forum's database and roles, the map, and the reload}
    );

    my $odd = GPForum::Service::Operations::PeerAuthentication->new(
        os       => GPForum::OS->from_name('linux'),
        database => 'my forum',
        owner    => 'Forum"Owner',
        operator => 'gpforum',
    );
    is_deeply(
        $odd->hba_lines,
        [
                'local   "my forum"   "Forum""Owner",gpforum_runtime'
              . '   peer map=gpforum'
        ],
        'a name either file would split is quoted'
    );
    is( scalar @{ $odd->ident_lines },
        2, q{and the service's account is no operator of its own} );
    ok( GPForum::Service::Operations::PeerAuthentication->is_refusal($REFUSED),
        'a refusal is told from other failures' );
};

subtest 'the failure, in both languages' => sub {
    my $failure = GPForum::Service::Operations::DatabaseFailure->new(
        os          => GPForum::OS->from_name('linux'),
        environment => 'production',
        language    => 'en',
    );
    my $classified = $failure->classify($REFUSED);
    is( $classified->{key}, 'database.peer', 'its own failure' );
    is( $classified->{parameters}{user},
        'gpforum_runtime', 'naming the role refused' );
    like(
        $failure->sentence($REFUSED),
        qr/refused [ ] role [ ] gpforum_runtime [ ] to [ ] this [ ] account/msx,
        'and the account it was refused to'
    );
    is( $failure->classify($ITALIAN)->{parameters}{user},
        'gpforum', 'from a server speaking Italian' );

    my $italian = GPForum::Service::Operations::DatabaseFailure->new(
        os          => GPForum::OS->from_name('linux'),
        environment => 'production',
        language    => 'it',
    );
    like(
        $italian->sentence($REFUSED),
        qr/ha [ ] rifiutato [ ] il [ ] ruolo [ ] gpforum_runtime/msx,
        'in the operator language'
    );
};

subtest 'doctor: refused by peer, the lines' => sub {
    my $text = _doctor( {}, database => sub { die "$REFUSED\n" }, );
    _has( $text, "\N{BALLOT X} database: PostgreSQL at", 'a failure' );
    _has(
        $text,
        'local   gpforum   gpforum,gpforum_runtime   peer map=gpforum',
        'with the pg_hba.conf line'
    );
    _has(
        $text,
        'gpforum   gpforum   gpforum_runtime',
        'and the pg_ident.conf ones'
    );
};

subtest q{doctor: the operator's connection} => sub {
    my $asked;
    my $fine = _doctor(
        {
            GPFORUM_DATABASE_USER       => 'gpforum_runtime',
            GPFORUM_ADMIN_DATABASE_USER => 'gpforum',
        },
        admin_database => sub { $asked = 1; return {} },
    );
    ok( $asked, 'is made when the file names a role for it' );
    _has( $fine,
        "\N{CHECK MARK} database: the operator's role gpforum connects too",
        'and said' );

    my $refused = _doctor(
        {
            GPFORUM_DATABASE_USER       => 'gpforum_runtime',
            GPFORUM_ADMIN_DATABASE_USER => 'gpforum',
        },
        admin_database => sub { die $REFUSED =~ s/_runtime//grmsx . "\n" },
    );
    _has(
        $refused,
        'refused role gpforum to this account',
        'a refusal is its own finding'
    );

    $asked = 0;
    _doctor(
        { GPFORUM_ADMIN_DATABASE_USER => 'gpforum' },
        admin_database => sub { $asked = 1; return {} },
    );
    ok( !$asked, 'and not made twice for the same role' );
};

sub _has ( $text, $literal, $name ) {
    return ok( index( $text, $literal ) >= 0, $name ) || diag $text;
}

# Doctor's database lines, on Linux in production, for a probe's answers.
sub _doctor ( $settings, %probes ) {
    my $catalog = GPForum::Service::I18N::CliCatalog->new( language => 'en' );
    my $doctor  = GPForum::Service::Operations::Doctor->new(
        catalog     => $catalog,
        environment => {
            GPFORUM_ENV             => 'production',
            GPFORUM_DATABASE_DSN    => 'dbi:Pg:dbname=gpforum',
            GPFORUM_MAIL_FROM       => 'forum@forum.walk.org',
            GPFORUM_METRICS_TOKEN   => 'metrics-token',
            GPFORUM_PUBLIC_BASE_URL => 'https://forum.walk.org',
            GPFORUM_SESSION_SECRET  => $SECRET,
            %{$settings},
        },
        file   => '/etc/gpforum/gpforum.env',
        os     => GPForum::OS->from_name('linux'),
        probes => {
            database => sub { return { schema => undef, version => '18.6' } },
            schema   => sub { return { latest => '121', pending => [] } },
            budgets  => sub {
                return { missing => [], extra => [], mismatched => [] };
            },
            %probes,
        },
    );
    my %state = (
        config   => GPForum::Config->from_environment( $doctor->environment ),
        findings =>
          GPForum::Service::Operations::Findings->new( catalog => $catalog ),
    );
    $doctor->_database( \%state );

    return $state{findings}->human_text( summary => 0 );
}

done_testing();

1;
