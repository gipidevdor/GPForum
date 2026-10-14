# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use English qw(-no_match_vars);
use Test::Exception;
use Test::More;

use lib 'lib';

use GPForum::Bootstrap::Config;
use GPForum::Config;
use GPForum::Config::Report;
use GPForum::Service::Admin::Settings;
use GPForum::Service::I18N::CliCatalog;
use GPForum::Service::Identity::Mailer;

our $VERSION = '0.001';

const my $SMTPS_PORT => 465;

# D11: GPFORUM_SMTP_SSL was a boolean that meant STARTTLS, off by default,
# so an SMTP relay on 587 got its password in the clear unless the operator
# knew to turn it on, and port 465 (TLS from the first byte) could not be
# used at all. GPFORUM_SMTP_TLS names the three ways and follows the port.
# Nothing was released with the old name, so it is not read.

subtest 'TLS follows the port unless it is set' => sub {
    is( _tls( {} ), 'starttls', 'STARTTLS by default, for 587' );
    is( _tls( { GPFORUM_SMTP_PORT => 465 } ),
        'implicit', 'implicit TLS on 465' );
    is( _tls( { GPFORUM_SMTP_PORT => 2525 } ),
        'starttls', 'STARTTLS on any other port' );
    is( _tls( { GPFORUM_SMTP_TLS  => 'off' } ), 'off', 'off when it says so' );
    is( _tls( { GPFORUM_SMTP_PORT => 465, GPFORUM_SMTP_TLS => 'starttls' } ),
        'starttls', 'and what it says wins over the port' );

    my $problems = _problems( { GPFORUM_SMTP_TLS => 'ssl' } );
    is( $problems->[0]{variable}, 'GPFORUM_SMTP_TLS', 'ssl is not a mode' );
    is(
        GPForum::Service::I18N::CliCatalog->new( language => 'en' )->text(
            $problems->[0]{key},
            {
                %{ $problems->[0]{parameters} },
                variable => 'GPFORUM_SMTP_TLS',
                value    => 'ssl'
            }
        ),
        q{GPFORUM_SMTP_TLS must be one of starttls, implicit, off, not 'ssl'.},
        'the sentence names the three'
    );
};

subtest 'the old GPFORUM_SMTP_SSL is not read' => sub {
    is( _tls( { GPFORUM_SMTP_SSL => 'off' } ),
        'starttls', 'GPFORUM_SMTP_SSL=off leaves the default' );
};

subtest 'a host that cannot speak TLS is told so at the start' => sub {
    my $smtp = GPForum::Config->from_environment(
        {
            GPFORUM_MAIL_TRANSPORT => 'smtp',
            GPFORUM_SMTP_HOST      => 'smtp.gpforum.test',
        }
    );
    my $problem = GPForum::Bootstrap::Config->tls_problem( $smtp, 0 );
    is_deeply(
        [ @{$problem}{qw(variable key value)} ],
        [ 'GPFORUM_SMTP_TLS', 'config.smtp_tls_module', 'starttls' ],
        'smtp with STARTTLS and no IO::Socket::SSL is a problem'
    );
    is(
        GPForum::Config::Report->sentence(
            $problem,
            GPForum::Service::I18N::CliCatalog->new( language => 'en' )
              ->translator
        ),
        'GPFORUM_SMTP_TLS=starttls encrypts mail through the Perl module'
          . ' IO::Socket::SSL, which this Perl cannot load: install it, or set'
          . ' GPFORUM_SMTP_TLS=off for a relay that takes mail in the clear.',
        'in English'
    );
    is(
        GPForum::Config::Report->sentence(
            $problem,
            GPForum::Service::I18N::CliCatalog->new( language => 'it' )
              ->translator
        ),
        'GPFORUM_SMTP_TLS=starttls cifra la posta con il modulo Perl'
          . ' IO::Socket::SSL, che questo Perl non riesce a caricare:'
          . ' installalo, oppure imposta GPFORUM_SMTP_TLS=off per un relay'
          . ' che accetta la posta in chiaro.',
        'in Italian'
    );
    is( GPForum::Bootstrap::Config->tls_problem( $smtp, 1 ),
        undef, 'a Perl that loads it is no problem' );
    is(
        GPForum::Bootstrap::Config->tls_problem(
            GPForum::Config->new(
                mail_transport => 'smtp',
                smtp_tls       => 'off'
            ),
            0
        ),
        undef,
        'nor TLS turned off'
    );
    is(
        GPForum::Bootstrap::Config->tls_problem(
            GPForum::Config->new( mail_transport => 'sendmail' ), 0
        ),
        undef,
        'nor mail that does not leave by smtp'
    );

    throws_ok {
        GPForum::Bootstrap::Config->load(
            {
                GPFORUM_MAIL_TRANSPORT => 'smtp',
                GPFORUM_SMTP_HOST      => 'smtp.gpforum.test',
            },
            can_tls => 0,
        );
    }
    'GPForum::X::Config', 'and the start stops';
    is_deeply(
        [ map { $_->{key} } @{ $EVAL_ERROR->problems } ],
        ['config.smtp_tls_module'],
        'with that problem'
    );
};

subtest 'the settings page shows it' => sub {
    my $environment = { GPFORUM_SMTP_TLS => 'starttls' };
    my $view        = GPForum::Service::Admin::Settings->new(
        config      => GPForum::Config->from_environment($environment),
        environment => $environment,
    )->view;
    my %by_env =
      map { $_->{env} => $_ }
      map { @{ $_->{settings} } } @{ $view->{sections} };
    is( $by_env{GPFORUM_SMTP_TLS}{value}, 'starttls', 'with its value' );
    is( $by_env{GPFORUM_SMTP_TLS}{source},
        'environment', 'which the environment gave it' );
};

subtest 'the mailer connects the way the setting says' => sub {
    my %expected = (
        starttls => 'starttls',
        implicit => 'ssl',
        off      => 0,
    );
    for my $tls ( sort keys %expected ) {
        my $transport = GPForum::Service::Identity::Mailer->new(
            config => GPForum::Config->new(
                mail_transport => 'smtp',
                smtp_host      => 'smtp.gpforum.test',
                smtp_tls       => $tls,
            )
        )->transport;
        is( $transport->ssl, $expected{$tls},
            "smtp_tls=$tls is Email::Sender's ssl $expected{$tls}" );
    }
    my $on_465 = GPForum::Service::Identity::Mailer->new(
        config => GPForum::Config->from_environment(
            {
                GPFORUM_MAIL_TRANSPORT => 'smtp',
                GPFORUM_SMTP_HOST      => 'smtp.gpforum.test',
                GPFORUM_SMTP_PORT      => 465,
            }
        )
    )->transport;
    is_deeply(
        [ $on_465->port, $on_465->ssl ],
        [ $SMTPS_PORT,   'ssl' ],
        'port 465 alone is TLS from the first byte'
    );
};

done_testing();

sub _tls ($environment) {
    return GPForum::Config->from_environment($environment)->smtp_tls;
}

sub _problems ($environment) {
    my $problems = [];
    eval {
        GPForum::Config->from_environment($environment);
        1;
    } or $problems = $EVAL_ERROR->problems;

    return $problems;
}

1;
