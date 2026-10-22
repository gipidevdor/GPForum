# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Carp qw(croak);
use Const::Fast;
use English    qw(-no_match_vars);
use IPC::Open3 qw(open3);
use Symbol     qw(gensym);
use Test::More;

use lib 'lib';
use GPForum::OS::Reactor ();

our $VERSION = '0.001';

# Hypnotoad's manager loads EV, and so creates the kqueue or epoll descriptor,
# before it forks the workers. A kqueue is not inherited across fork(2): the
# worker's copy is dead until libev rebuilds it, which EV arranges with
# pthread_atfork -- "quite buggy on most BSDs", its documentation warns. If
# the handler does not run, the worker's first kevent fails and libev aborts.
# This drill forks with a watcher registered in the parent, the way a worker
# inherits the manager's loop, and requires both loops to keep working. It
# runs wherever the suite does: macOS here, FreeBSD in platform-freebsd.yml.

const my $EXIT_SHIFT => 8;

my $native = GPForum::OS::Reactor->expected_backend;
if ( !$native ) {
    plan skip_all =>
      'the native backend is required on Linux, macOS and FreeBSD';
}

const my $DRILL => <<'PERL';
use v5.40;
use GPForum::OS::Reactor;
use EV;
use POSIX ();

pipe my $reader, my $writer or die "pipe: $!";
my $seen  = 0;
my $watch = EV::io $reader, EV::READ, sub {
    sysread $reader, my $byte, 1;
    $seen++;
    EV::break;
};
my $limit = EV::timer 5, 0, sub { EV::break };

my $pid = fork // die "fork: $!";
if ( !$pid ) {
    syswrite $writer, 'w';
    EV::run;
    POSIX::_exit( $seen == 1 && EV::backend() == $ENV{LIBEV_FLAGS} ? 0 : 3 );
}
waitpid $pid, 0;
my $worker = $?;
syswrite $writer, 'm';
EV::run;
print 'worker_exit=', $worker >> 8, ' worker_signal=', $worker & 127,
  " manager_seen=$seen backend=", EV::backend();
PERL

my ( $status, $output ) = _probe($DRILL);
is( $status >> $EXIT_SHIFT, 0, 'the drill runs to the end' ) or diag $output;
like( $output, qr/worker_signal=0\b/msx, 'libev did not abort in the worker' );
like( $output, qr/worker_exit=0\b/msx,
    'the worker served an inherited watcher on its own native loop' );
like(
    $output,
    qr/manager_seen=1 [ ] backend=\Q$native->{flags}\E\z/msx,
    'the manager loop still works after the fork'
);

done_testing();

sub _probe ($code) {
    local $ENV{LIBEV_FLAGS} = $native->{flags};
    my $error = gensym;
    my $pid   = open3( my $input, my $output, $error,
        $EXECUTABLE_NAME, '-Ilib', '-e', $code );
    close $input or croak "close child input: $OS_ERROR";
    my $text = do { local $INPUT_RECORD_SEPARATOR = undef; <$output> // q{} };
    $text .= do { local $INPUT_RECORD_SEPARATOR = undef; <$error> // q{} };
    close $output or croak "close child output: $OS_ERROR";
    close $error  or croak "close child error: $OS_ERROR";
    waitpid $pid, 0;

    return $CHILD_ERROR, $text;
}

1;
