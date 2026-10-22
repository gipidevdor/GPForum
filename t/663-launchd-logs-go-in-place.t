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

# Walkthrough 4 (friction 3): macOS production took 10 commands, one of
# them the launchd jobs' log directory, a command of its own after
# gpforum service print --to /Library/LaunchDaemons. As root, --to makes it
# now, the service account's, 0750, and the step that made it goes.

const my $LOG_MODE   => oct '750';
const my $STAT_OWNER => 4;
const my $SITE       => 'https://forum.walk.org';

subtest 'the launchd jobs log directory goes in place with them' => sub {
    my $prefix = path( tempdir( CLEANUP => 1 ) );
    local $ENV{HOMEBREW_PREFIX} = "$prefix";
    my $daemons = path( tempdir( CLEANUP => 1 ) );
    my $logs    = $prefix->child(qw(var log gpforum));
    my %options = (
        os          => 'darwin',
        directories => { launchd => $daemons },
        root        => 1,
    );

    my $run = _run( \%options, 'print', 'launchd', '--to', "$daemons" );
    is( $run->{status}, 0, 'written as root' );
    ok( -d $logs, 'with the directory the jobs log to' );
    is( ( stat $logs )[2] & oct '777', $LOG_MODE, '0750, as the step made it' );
    is( ( stat $logs )[$STAT_OWNER],   $UID,      q{the service account's} );
    unlike( $run->{output}, qr/install [ ] -d/msx, 'so no step makes it' );
    like(
        $run->{output},
        qr/launchctl [ ] bootstrap [ ] system/msx,
        'and the next step loads the jobs'
    );

    rmdir "$logs" or croak "rmdir: $ERRNO";
    my $no_root =
      _run( { %options, root => 0 }, 'print', 'launchd', '--to', "$daemons" );
    ok( !-d $logs, 'not made without root' );
    ok(
        index( $no_root->{output},
            "sudo install -d -o gpforum -g gpforum -m 0750 $logs" ) >= 0,
        'and the step that makes it stays'
    );
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
