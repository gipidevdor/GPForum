# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use File::Temp qw(tempdir);
use English    qw(-no_match_vars);
use Errno      qw(EAGAIN EINTR EWOULDBLOCK);
use Carp       qw(croak);
use Mojolicious;
use Mojo::File qw(path);
use Test::More;
use Fcntl qw(:flock);
use IO::Select;
use POSIX ();
use Const::Fast;
use Time::HiRes qw(clock_gettime CLOCK_MONOTONIC);

use lib 'lib';
use lib 't/lib';

use GPForum::Config;
use GPForum::Log;
use GPForum::Test::ReplacedSubs qw(with_replaced_subs);

our $VERSION = '0.001';

# Mojolicious logs to STDERR by default and Mojo::Server::daemonize reopens
# STDERR on /dev/null before Hypnotoad forks, so a logger left on STDERR writes
# nowhere. Every shipped service unit daemonizes, which meant a production
# deployment had no application log at all. See docs/QUALITY_PROGRAM.md 3.1.
my $directory = tempdir( CLEANUP => 1 );
my $log_file  = "$directory/gpforum.log";

my $configured = Mojolicious->new;
GPForum::Log->configure( $configured,
    GPForum::Config->new( log_level => 'info', log_path => $log_file ),
);
is( $configured->log->level, 'info',    'the configured level is applied' );
is( $configured->log->path,  $log_file, 'the configured path is applied' );
$configured->log->info('incident line');
ok( -s $log_file, 'a configured destination receives the line' );
like(
    path($log_file)->slurp,
    qr/incident [ ] line/msx,
    'the line survives where an operator can read it'
);

subtest
  'HUP reopens a renamed application log without losing the old handle' => sub {
    rename $log_file, "$log_file.1" or croak 'cannot rotate test log';
    kill 'HUP', $PROCESS_ID or croak 'cannot request log reopen';
    $configured->log->info('after rotation');
    like(
        path($log_file)->slurp,
        qr/after[ ]rotation/msx,
        'the next line reaches a new file at the configured path'
    );
    unlike(
        path("$log_file.1")->slurp,
        qr/after[ ]rotation/msx,
        'the renamed file receives no further line'
    );
    rename $log_file, "$log_file.2" or croak 'cannot rotate test log again';
    mkdir $log_file or croak 'cannot block test log path';
    my $warning = q{};
    {
        local $SIG{__WARN__} = sub ($message) { $warning .= $message; };
        kill 'HUP', $PROCESS_ID or croak 'cannot request failed reopen';
        $configured->log->info('still retained');
    }
    like(
        $warning,
        qr/cannot[ ]reopen[ ]application[ ]log/msx,
        'a failed reopen is observable'
    );
    like(
        path("$log_file.2")->slurp,
        qr/still[ ]retained/msx,
        'a failed reopen preserves the previous descriptor'
    );
    rmdir $log_file or croak 'cannot unblock test log path';
    kill 'HUP', $PROCESS_ID or croak 'cannot request recovered reopen';
    $configured->log->info('recovered destination');
    like(
        path($log_file)->slurp,
        qr/recovered[ ]destination/msx,
        'a later reopen recovers normally'
    );
  };

subtest 'forked loggers acquire independent file locks' => sub {
    _forked_writers( $configured, $log_file );
};

my $bare = Mojolicious->new;
GPForum::Log->configure( $bare, GPForum::Config->new( log_level => 'warn' ) );
is( $bare->log->level, 'warn', 'the level is applied without a path' );
is( $bare->log->path, undef,
    'no path leaves the logger on STDERR for a foreground supervisor' );

# Every shipped unit has to name a destination, or the deployment it describes
# silently discards its own log.
for my $unit ( sort glob 'deploy/systemd/*.service' ) {
    like(
        path($unit)->slurp,
        qr/^Environment=GPFORUM_LOG_PATH=\S+$/msx,
        "$unit configures a log destination"
    );
}
like( path('deploy/freebsd/gpforum')->slurp,
    qr/GPFORUM_LOG_PATH=/msx,
    'the FreeBSD rc script configures a log destination' );
for my $plist ( sort glob 'deploy/launchd/*.plist' ) {
    like( path($plist)->slurp,
        qr/GPFORUM_LOG_PATH/msx, "$plist configures a log destination" );
}

done_testing();

sub _forked_writers ( $application, $file ) {
    const my $CHILD_DEADLINE => 10;
    my $handle = $application->log->handle;
    flock $handle, LOCK_EX or croak 'cannot lock parent log';
    pipe my $reader, my $writer or croak 'cannot open child signal pipe';
    my $child = fork // croak 'cannot fork log writer';
    if ( !$child ) { _child_writer( $application, $reader, $writer ); }
    close $writer or croak 'cannot close parent pipe writer';
    my $select = IO::Select->new($reader);
    my $ready  = _wait_readable( $select, $CHILD_DEADLINE );
    ok( $ready, 'the child probes its append descriptor' );

    if ($ready) {
        sysread( $reader, my $message, length "locked\n" ) == length "locked\n"
          or croak 'cannot read child readiness';
        is( $message, "locked\n",
            'the child append descriptor conflicts with the parent lock' );
    }
    flock $handle, LOCK_UN or croak 'cannot unlock parent log';
    my $finished = _wait_readable( $select, $CHILD_DEADLINE );
    ok( $finished, 'the child completes once the parent unlocks' );
    if ( !$finished ) { kill 'KILL', $child; }
    waitpid $child, 0;
    is( $CHILD_ERROR, 0, 'the child exits normally' );
    close $reader or croak 'cannot close parent reader';
    like(
        path($file)->slurp,
        qr/independent[ ]child[ ]line/msx,
        'the child line is retained'
    );
    return;
}

# SIGCHLD can interrupt select just as the child closes its pipe. Keep the
# original deadline across interruptions instead of treating EINTR as timeout.
sub _wait_readable ( $select, $seconds ) {
    my $deadline = clock_gettime(CLOCK_MONOTONIC) + $seconds;
    while (1) {
        my $remaining = $deadline - clock_gettime(CLOCK_MONOTONIC);
        return if $remaining <= 0;
        local $ERRNO = 0;
        return 1 if $select->can_read($remaining);
        return   if $ERRNO != EINTR;
    }
    return;
}

sub _child_writer ( $application, $reader, $writer ) {
    close $reader or POSIX::_exit(1);
    my $append = Mojo::Log->can('append');
    with_replaced_subs(
        'Mojo::Log',
        {
            append => sub ( $logger, @messages ) {

                # Inspect the actual descriptor after GPForum's fork reopen, at
                # the native append boundary. A nonblocking kernel lock conflict
                # proves independence without a scheduling-dependent sleep.
                my $blocked = !flock( $logger->handle, LOCK_EX | LOCK_NB )
                  && ( $ERRNO == EAGAIN || $ERRNO == EWOULDBLOCK );
                my $probe = $blocked ? "locked\n" : "shared\n";
                syswrite( $writer, $probe ) == length $probe
                  or POSIX::_exit(1);
                return $append->( $logger, @messages );
            }
        },
        sub { $application->log->info('independent child line'); }
    );
    syswrite( $writer, "done\n" ) == length "done\n" or POSIX::_exit(1);
    close $writer                                    or POSIX::_exit(1);
    return POSIX::_exit(0);
}

1;
