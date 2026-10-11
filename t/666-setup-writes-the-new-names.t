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
use lib 't/lib';

use GPForum::Command::Setup;
use GPForum::Command::Support::EnvironmentFileEdit;
use GPForum::Config;
use GPForum::OS;
use GPForum::Service::I18N::CliCatalog;
use GPForum::Test::SetupAccount;
use GPForum::Test::SetupDatabase;
use GPForum::Test::SetupTerminal;

our $VERSION = '0.001';

# Walkthrough 4 (friction 6): an install carrying old names --
# GPFORUM_ENV=production-medium, GPFORUM_SMTP_SSL=off and three retired
# settings -- started and listed each, and took five edits by hand: setup
# rewrote GPFORUM_ENV alone. It now writes every old name under its new one,
# keeping its value, drops each retired setting's line, and says so.

const my $NOT_ROOT => 1_000;
const my $SECRET   => 'x' x 64;
const my $OK       => "\N{CHECK MARK} ";
const my @OLD => (
    'GPFORUM_ENV=production-medium', 'GPFORUM_SMTP_SSL=off',
    'GPFORUM_WORKER_PROCESSES=4',    'GPFORUM_REALTIME_PROCESSES=2',
    'GPFORUM_OS_AFFINITY=on',
);
const my @RETIRED =>
  qw(GPFORUM_WORKER_PROCESSES GPFORUM_REALTIME_PROCESSES GPFORUM_OS_AFFINITY);

my $directory = tempdir( CLEANUP => 1 );

subtest 'every old name under its new one, every retired line gone' => sub {
    my $file = _old_file('forum.env');

    my $dry = _setup( $file, 'en', '--dry-run' );
    is( $dry->{status}, 0, 'a dry run' );
    _has(
        $dry->{lines},
        "${OK}would write GPFORUM_SMTP_TLS=off in place of the old"
          . ' GPFORUM_SMTP_SSL=off',
        'says the new name it would write, with the value kept'
    );
    _has(
        $dry->{lines},
        "${OK}GPFORUM_WORKER_PROCESSES: would drop its line, as it no longer"
          . ' has any effect',
        'and the retired line it would drop'
    );
    like( path($file)->slurp, qr/^GPFORUM_SMTP_SSL=off$/msx,
        'writing nothing' );

    my $run = _setup( $file, 'en' );
    is( $run->{status}, 0, 'setup runs' ) or diag $run->{errors};
    my $text   = path($file)->slurp;
    my %values = %{ GPForum::Command::Support::EnvironmentFileEdit->values_of(
            [ split /^/msx, $text ]
        )
    };
    is( $values{GPFORUM_ENV},      'production', 'GPFORUM_ENV=production' );
    is( $values{GPFORUM_SMTP_TLS}, 'off', 'GPFORUM_SMTP_TLS=off, kept off' );

    for my $variable ( 'GPFORUM_SMTP_SSL', @RETIRED ) {
        ok( !exists $values{$variable}, "no $variable line" );
    }
    _has( $run->{lines},
        "${OK}GPFORUM_SMTP_TLS=off, in place of the old GPFORUM_SMTP_SSL=off",
        'said' );
    _has(
        $run->{lines},
        "${OK}GPFORUM_ENV=production, in place of the old"
          . ' GPFORUM_ENV=production-medium',
        'the old value too'
    );
    for my $variable (@RETIRED) {
        _has(
            $run->{lines},
            "${OK}$variable: its line is gone, as it no longer has any effect",
            "$variable said gone"
        );
    }

    my $config = GPForum::Config->from_environment( \%values );
    is_deeply( $config->renamed_settings, [], 'the service reads no old name' );
    is_deeply( $config->retired_settings, [], 'nor a retired setting' );

    my $again = _setup( $file, 'en' );
    is(
        scalar(
            grep { /in [ ] place [ ] of | line [ ] is [ ] gone/msx }
              @{ $again->{lines} }
        ),
        0,
        'and a second run has nothing to say of them'
    );
};

subtest 'in Italian' => sub {
    my $run = _setup( _old_file('italian.env'), 'it' );
    _has(
        $run->{lines},
        "${OK}GPFORUM_SMTP_TLS=off, al posto del vecchio GPFORUM_SMTP_SSL=off",
        'the new name'
    );
    _has(
        $run->{lines},
        "${OK}GPFORUM_OS_AFFINITY: la sua riga è tolta, perché non ha più"
          . ' alcun effetto',
        'and the retired line'
    );
};

subtest 'an old variable beside its new one only goes' => sub {
    my $file = _old_file( 'both.env', 'GPFORUM_SMTP_TLS=implicit' );
    _setup( $file, 'en' );
    my %values = %{ GPForum::Command::Support::EnvironmentFileEdit->values_of(
            [ split /^/msx, path($file)->slurp ]
        )
    };
    is( $values{GPFORUM_SMTP_TLS},
        'implicit', 'the new one, which the service read, stays' );
    ok( !exists $values{GPFORUM_SMTP_SSL}, 'and the old one goes' );
};

done_testing();

# A file setup wrote, then given the old names an install of before carries.
sub _old_file ( $name, @more ) {
    my $file = "$directory/$name";
    _setup( $file, 'en' );
    my $text = path($file)->slurp =~ s/^GPFORUM_ENV=.*\n//rmsx;
    path($file)->spew( $text . join "\n", @OLD, @more, q{} );

    return $file;
}

sub _setup ( $file, $language, @arguments ) {
    my ( $output, $errors ) = ( q{}, q{} );
    my $status = GPForum::Command::Setup->new(
        catalog =>
          GPForum::Service::I18N::CliCatalog->new( language => $language ),
        os            => GPForum::OS->from_name('linux'),
        effective_uid => $NOT_ROOT,
        host_name     => 'forum.gpforum-walk4.org',
        terminal      => GPForum::Test::SetupTerminal->new( interactive => 0 ),
        account       => GPForum::Test::SetupAccount->new,
        database      => GPForum::Test::SetupDatabase->new,
        generate      => sub { return $SECRET; },
        migrate       => sub ($self) { return { status => 0 }; },
        owner_check   => sub ($self) { return 0; },
        output        => _handle( \$output ),
        prompt        => _handle( \$errors ),
      )
      ->run( '--env-file', $file, '--yes', '--database', 'create', '--mail',
        'sendmail', '--public-url', 'https://forum.gpforum-walk4.org',
        @arguments );

    return {
        status => $status,
        errors => $errors,
        lines  => [ split /\n/msx, decode( 'UTF-8', $output ) ],
    };
}

sub _has ( $lines, $line, $name ) {
    return ok( ( grep { $_ eq $line } @{$lines} ), $name )
      || diag join "\n", @{$lines};
}

sub _handle ($text) {
    open my $handle, '>>', $text or croak "output: $OS_ERROR";

    return $handle;
}

1;
