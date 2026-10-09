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
use Test::More;

use lib 'lib';

use GPForum::Command::Secret;
use GPForum::Command::Support::ServiceEnvironment;
use GPForum::Command::Support::Words;
use GPForum::OS;
use GPForum::Service::I18N::CliCatalog;
use GPForum::Service::Operations::Doctor;
use GPForum::Service::Operations::Findings;

our $VERSION = '0.001';

# Owner decision, 2026-10-10: a metrics-token rotation is three commands --
# rotate, the scrapers' new token, --finish -- because the running service
# reads the tokens from its environment file again (ADR 0124). Walkthrough 3
# (friction 6) followed four: each of rotate and --finish was followed by
# "Next: sudo systemctl restart gpforum gpforum-outbox". The session secret
# signs cookies and is read at start only: its rotation keeps the restart.

const my $SECRET_FILE_MODE => oct '640';
const my $GROUP_WRITABLE   => oct '660';
const my $OTHERS_WRITABLE  => oct '620';
const my $WORLD_READABLE   => oct '644';
const my $LONG             => 'x' x 64;
const my $RESTART => 'Next: sudo systemctl restart gpforum gpforum-outbox';

my $directory = tempdir( CLEANUP => 1 );
my $file      = path( $directory, 'forum.env' );
my $variable  = 'GPFORUM_METRICS_TOKEN';
my $made      = 0;

subtest 'rotate, give the scrapers the token, finish: no restart' => sub {
    _template();
    my $rotated = _rotate( 1, 'en', 'metrics' );
    is( $rotated->{status}, 0, 'the first token is written' );
    my $first = _lines( $rotated->{output} );
    like(
        $first->[0],
        qr/asks [ ] for [ ] it [ ] now, [ ] with [ ] no [ ] restart/msx,
        'a first token is asked for at once'
    );
    is(
        $first->[1],
        "Next: give every scraper the new $variable from $file",
        'and the step after is the scrapers'
    );
    is( scalar @{$first}, 2, 'two lines, nothing more' );

    my $again = _lines( _rotate( 1, 'en', 'metrics' )->{output} );
    is(
        $again->[0],
        "\N{CHECK MARK} A new metrics token is in $file. The one before stays"
          . ' in GPFORUM_METRICS_TOKENS, and the running service accepts both'
          . ' now, with no restart.',
        'a rotation says both are accepted, with no restart'
    );
    is(
        $again->[1],
        "Next: give every scraper the new $variable from $file, then gpforum"
          . " --env-file $file secret rotate metrics --finish",
        'the scrapers, then --finish, on the next line'
    );
    is( scalar @{$again}, 2, 'and no third' );

    my $finished =
      _lines( _rotate( 1, 'en', 'metrics', '--finish' )->{output} );
    is_deeply(
        $finished,
        [
            "\N{CHECK MARK} The previous metrics tokens are gone from $file,"
              . ' and the running service refuses them now, with no restart.'
        ],
        '--finish ends it, with nothing after'
    );

    for my $run ( $first, $again, $finished ) {
        unlike(
            join( "\n", @{$run} ),
            qr/restart [ ] gpforum|kickstart/msx,
            'no restart command anywhere'
        );
    }
};

subtest 'in Italian' => sub {
    _template();
    _rotate( 1, 'it', 'metrics' );
    my $lines = _lines( _rotate( 1, 'it', 'metrics' )->{output} );
    like(
        $lines->[0],
        qr/li [ ] accetta [ ] già [ ] entrambi, [ ] senza [ ] riavvio/msx,
        'the rotation, in the operator language'
    );
    is(
        $lines->[1],
        "Prossimo passo: dai a ogni scraper il nuovo $variable da $file, poi"
          . " gpforum --env-file $file secret rotate metrics --finish",
        'and its next step'
    );
};

subtest 'a service not known to follow the file keeps its restart' => sub {
    _template();
    _rotate( 0, 'en', 'metrics' );
    is( _next( _rotate( 0, 'en', 'metrics' )->{output} ),
        $RESTART,
        q{a file that is not the host's own: the restart, as before} );
};

subtest 'the session secret keeps its restart' => sub {
    _template();
    _rotate( 1, 'en', 'session' );
    my $run = _rotate( 1, 'en', 'session' );
    is( _next( $run->{output} ),
        $RESTART,
        'cookies are signed with the secret the service started with' );
};

# The service follows the file its web unit names: the host's own, or the
# one gpforum --env-file FILE service print wrote the unit for, which
# bin/gpforum tells the service in GPFORUM_ENV_FILE.
subtest 'the file the installed web unit names is the one it follows' => sub {
    my $units  = path( tempdir( CLEANUP => 1 ) );
    my $reread = sub ( $at, $unit ) {
        return GPForum::Command::Secret->new(
            file     => $at,
            web_unit => defined $unit ? "$unit" : undef,
        )->metrics_reread;
    };

    my $own = $units->child('gpforum.service');
    $own->spew( "EnvironmentFile=/etc/gpforum/gpforum.env\n"
          . "ExecStart=/opt/gpforum/bin/gpforum start --service\n" );
    ok( $reread->( '/etc/gpforum/gpforum.env', $own ), q{the host's own} );
    ok( !$reread->( "$file",                   $own ), 'not another file' );
    ok(
        !$reread->( '/etc/gpforum/gpforum', $own ),
        'nor a name the unit holds only the start of'
    );

    my $other = $units->child('other.service');
    $other->spew( "EnvironmentFile=$file\n"
          . "ExecStart=/opt/gpforum/bin/gpforum --env-file $file start"
          . " --service\n" );
    ok( $reread->( "$file", $other ), 'one named with --env-file' );
    ok( !$reread->( '/etc/gpforum/gpforum.env', $other ),
        q{and then not the host's own} );

    my $plist = $units->child('com.gpforum.app.plist');
    $plist->spew( "    <string>/opt/gpforum/bin/gpforum</string>\n"
          . "    <string>--env-file</string>\n    <string>$file</string>\n" );
    ok( $reread->( "$file", $plist ), 'and in a plist' );

    ok( !$reread->( "$file", undef ),
        'nor a host whose services are not installed' );
};

# Walkthrough 4 (friction 2): MetricsTokens refuses a file an account other
# than its owner may write (mode & 022), while secret rotate and doctor
# checked & 007 only. A 0660 file got "accepts both now, with no restart",
# and --finish "refuses them now", while the service kept the old token and
# refused the new one; doctor said settings were fine. One rule now judges
# the file for all three.
subtest 'a file another account may write names the restart and the chmod' =>
  sub {
    for my $mode ( $GROUP_WRITABLE, $OTHERS_WRITABLE ) {
        my $octal = sprintf '%04o', $mode;
        _template();
        _rotate( 1, 'en', 'metrics' );
        chmod $mode, "$file" or croak "chmod: $ERRNO";
        my $warning =
            "! Accounts other than its owner can write $file, so"
          . ' the running service does not read the metrics tokens from it'
          . " again: chmod 0640 $file";

        my $rotated = _lines( _rotate( 1, 'en', 'metrics' )->{output} );
        is_deeply(
            [ @{$rotated}[ 0 .. 2 ] ],
            [
                "\N{CHECK MARK} A new metrics token is in $file. The one"
                  . ' before stays in GPFORUM_METRICS_TOKENS, so no scraper is'
                  . ' refused.',
                $warning,
                $RESTART,
            ],
            "$octal: no promise of no restart, the chmod, then the restart"
        );
        my $finished =
          _lines( _rotate( 1, 'en', 'metrics', '--finish' )->{output} );
        is_deeply(
            $finished,
            [
                "\N{CHECK MARK} The previous metrics tokens are gone from"
                  . " $file; a scraper that sends one is refused.",
                $warning,
                $RESTART,
            ],
            "$octal: --finish names the restart that makes it true"
        );
        unlike(
            join( "\n", @{$rotated}, @{$finished} ),
            qr/with [ ] no [ ] restart/msx,
            "$octal: never 'with no restart'"
        );
        is( ( stat $file )[2] & oct '777', $mode, "$octal: the mode is kept" );
    }

    _template();
    _rotate( 1, 'it', 'metrics' );
    chmod $GROUP_WRITABLE, "$file" or croak "chmod: $ERRNO";
    my $italian = _lines( _rotate( 1, 'it', 'metrics' )->{output} );
    is(
        $italian->[1],
        "! Account diversi dal proprietario possono scrivere $file, quindi il"
          . ' servizio in esecuzione non ne rilegge i token delle metriche:'
          . " chmod 0640 $file",
        'in Italian'
    );
    unlike(
        $italian->[0],
        qr/senza [ ] riavvio/msx,
        'with no promise of no restart'
    );
  };

subtest 'doctor says it under !, with the chmod' => sub {
    _template();
    chmod $GROUP_WRITABLE, "$file" or croak "chmod: $ERRNO";
    my $writable = _settings_findings('en');
    my ($finding) =
      grep { $_->{message} =~ /can [ ] write/msx } @{$writable};
    ok( $finding, 'a group-writable file is a finding' )
      or diag explain $writable;
    is( $finding->{status}, 'degraded', 'under !' );
    is(
        $finding->{message},
        "settings: accounts other than its owner can write $file, so the"
          . ' running service does not read the metrics tokens from it again',
        'saying what it costs'
    );
    is_deeply( $finding->{fixes}, ["chmod 0640 $file"], 'with the chmod' );
    like(
        join( "\n", map { $_->{message} } @{ _settings_findings('it') } ),
        qr/impostazioni: [ ] account [ ] diversi [ ] dal [ ] proprietario/msx,
        'in Italian too'
    );

    chmod $WORLD_READABLE, "$file" or croak "chmod: $ERRNO";
    my ($open) =
      grep { $_->{status} eq 'degraded' && $_->{message} =~ /\Q$file\E/msx }
      @{ _settings_findings('en') };
    like(
        $open->{message},
        qr/can [ ] read/msx,
        'a file only every account may read is said as before'
    );

    chmod $SECRET_FILE_MODE, "$file" or croak "chmod: $ERRNO";
    is(
        scalar(
            grep {
                $_->{status} eq 'degraded' && $_->{message} =~ /\Q$file\E/msx
            } @{ _settings_findings('en') }
        ),
        0,
        '0640 is fine'
    );
};

done_testing();

# Doctor's settings findings for the file, as a production host's.
sub _settings_findings ($language) {
    my $catalog =
      GPForum::Service::I18N::CliCatalog->new( language => $language );
    my %environment = (
        GPFORUM_ENV             => 'production',
        GPFORUM_MAIL_FROM       => 'forum@forum.gpforum.net',
        GPFORUM_METRICS_TOKEN   => $LONG,
        GPFORUM_PUBLIC_BASE_URL => 'https://forum.gpforum.net',
        GPFORUM_SESSION_SECRET  => $LONG,
    );
    my $findings =
      GPForum::Service::Operations::Findings->new( catalog => $catalog );
    GPForum::Service::Operations::Doctor->new(
        catalog     => $catalog,
        environment => \%environment,
        file        => "$file",
        os          => GPForum::OS->from_name('linux'),
        probes      => { tls => sub { return 1 } },
    )->settings( \%environment, $findings );

    return $findings->document;
}

sub _template {
    $file->spew( path('deploy/gpforum.env.example')->slurp );
    chmod $SECRET_FILE_MODE, "$file" or croak "chmod: $ERRNO";

    return;
}

# A rotation on an installed Linux host whose running service does, or does
# not, follow the file.
sub _rotate ( $reread, $language, @arguments ) {
    local $ENV{GPFORUM_ENV} = 'production';
    GPForum::Command::Support::ServiceEnvironment->new(
        file        => "$file",
        environment => {},
    )->load;

    my $secret = GPForum::Command::Secret->new(
        generate            => sub { return $LONG . ++$made },
        services_installed  => 1,
        metrics_reread      => $reread,
        service_environment =>
          GPForum::Command::Support::ServiceEnvironment->new(
            os => GPForum::OS->from_name('linux')
          ),
        words => GPForum::Command::Support::Words->new(
            catalog =>
              GPForum::Service::I18N::CliCatalog->new( language => $language )
        ),
    );

    return _captured( sub { return $secret->run( 'rotate', @arguments ) } );
}

sub _next ($output) {
    my ($next) = grep { /\A Next: /msx } @{ _lines($output) };

    return $next // q{};
}

sub _lines ($output) {
    return [ split /\n/msx, $output ];
}

sub _captured ($code) {
    my ( $output, $errors ) = ( q{}, q{} );
    my $status;
    {
        open my $stdout, '>', \$output or croak 'capture stdout';
        open my $stderr, '>', \$errors or croak 'capture stderr';
        local *STDOUT = $stdout;
        local *STDERR = $stderr;
        $status = $code->();
        close $stdout or croak 'close stdout';
        close $stderr or croak 'close stderr';
    }
    utf8::decode($output);

    return { errors => $errors, output => $output, status => $status };
}

1;
