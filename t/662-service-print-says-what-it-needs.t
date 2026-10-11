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

use GPForum::Command::Service;
use GPForum::Command::Support::Words;
use GPForum::OS;
use GPForum::Service::I18N::CliCatalog;
use GPForum::Service::Operations::Host;
use GPForum::Service::Operations::ServiceFiles;

our $VERSION = '0.001';

# Walkthrough 4 (frictions 7 and 8): gpforum service print --to
# /Library/LaunchDaemons without sudo answered with Perl's own error, "Error
# in tempfile() using template ...: Permission denied"; and service print
# nginx --to, refused before certbot was installed, named only the
# certificate command, where the bare print names brew install nginx
# certbot first.

const my $EXIT_FAILURE => 1;
const my $CLOSED       => oct '555';
const my $OPEN         => oct '755';
const my $SITE         => 'https://forum.walk.org';

subtest 'a directory only root can write into: the command, with sudo' => sub {
    if ( $EFFECTIVE_USER_ID == 0 ) {
        plan skip_all => 'root writes anywhere';
    }

    my $closed = path( tempdir( CLEANUP => 1 ) );
    chmod $CLOSED, "$closed" or croak "chmod: $ERRNO";
    my $in_place =
      _run( { os => 'darwin', directories => { launchd => $closed } },
        'print', 'launchd', '--to', "$closed" );
    is( $in_place->{status}, $EXIT_FAILURE, 'refused' );
    is(
        $in_place->{errors},
        "Only root can write into $closed: run it with sudo, as sudo gpforum"
          . " service print launchd --to $closed\n",
        'saying so, with the command to type'
    );
    unlike( $in_place->{errors}, qr/tempfile|template/msx,
        q{and not Perl's own error} );

    my $below = $closed->child( 'units', 'here' );
    my $read  = _run( { os => 'linux' }, 'print', 'systemd', '--to', "$below" );
    is(
        $read->{errors},
        "Only root can write into $closed: run it with sudo, as sudo gpforum"
          . " service print systemd --to $below\n",
        'a directory not there yet: the one that would hold it'
    );

    my $italian = _run(
        {
            os          => 'darwin',
            directories => { launchd => $closed },
            language    => 'it'
        },
        'print',
        'launchd',
        '--to',
        "$closed"
    );
    is(
        $italian->{errors},
        "Solo root può scrivere in $closed: eseguilo con sudo, come sudo"
          . " gpforum service print launchd --to $closed\n",
        'in Italian'
    );
    chmod $OPEN, "$closed" or croak "chmod: $ERRNO";
};

subtest 'nginx before certbot: the packages, then the certificate' => sub {
    my %expected = (
        linux => 'sudo apt install nginx certbot python3-certbot-nginx && sudo'
          . ' certbot certonly --nginx -d forum.walk.org',
        darwin => 'brew install nginx certbot && sudo certbot certonly'
          . ' --standalone -d forum.walk.org'
          . q{ --pre-hook 'brew services stop nginx'}
          . q{ --post-hook 'brew services start nginx'},
    );
    for my $os ( sort keys %expected ) {
        my $sites   = tempdir( CLEANUP => 1 );
        my %options = (
            os          => $os,
            directories => { nginx => $sites },
            missing     => 'certbot',
        );
        my $refused = _run( \%options, 'print', 'nginx', '--to', $sites );
        is( $refused->{status}, $EXIT_FAILURE, "$os: refused" );
        like(
            $refused->{errors},
qr/take [ ] it [ ] first, [ ] with [ ] \Q$expected{$os}\E, [ ] then/msx,
            "$os: the packages that bring certbot come first"
        );

        my $installed = _run( { %options, missing => undef },
            'print', 'nginx', '--to', $sites );
        unlike(
            $installed->{errors},
            qr/install [ ] nginx/msx,
            "$os: and not once they are installed"
        );
    }
};

done_testing();

sub _run ( $options, @arguments ) {
    my $catalog =
      GPForum::Service::I18N::CliCatalog->new( language => $options->{language}
          // 'en' );
    my $host = GPForum::Service::Operations::Host->new(
        catalog     => $catalog,
        environment => 'production',
        os          => GPForum::OS->from_name( $options->{os} ),
    );
    my $missing = $options->{missing} // q{};
    my $command = GPForum::Command::Service->new(
        files => GPForum::Service::Operations::ServiceFiles->new(
            directories => $options->{directories} // {},
            environment => { GPFORUM_PUBLIC_BASE_URL => $SITE },
            host        => $host,
            home        => '/opt/gpforum',
            found       => sub ($program) { return $program ne $missing },
            exists      => sub ($file) { return -e $file ? 1 : 0 },
        ),
        words => GPForum::Command::Support::Words->new( catalog => $catalog ),
        $options->{root}
        ? (
            effective_uid   => 0,
            service_account => [ $UID, ( split q{ }, $GID )[0] ],
          )
        : ( effective_uid => $UID ),
    );

    my ( $output, $errors ) = ( q{}, q{} );
    open my $stdout, '>', \$output or croak 'capture stdout';
    open my $stderr, '>', \$errors or croak 'capture stderr';
    $command->output($stdout);
    $command->errors($stderr);
    my $status = $command->run(@arguments);
    close $stdout or croak 'close stdout';
    close $stderr or croak 'close stderr';

    return {
        status => $status,
        output => decode( 'UTF-8', $output ),
        errors => decode( 'UTF-8', $errors ),
    };
}

1;
