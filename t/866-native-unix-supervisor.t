# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package main;
use v5.40;
use Carp qw(croak carp);
use Const::Fast;
use Digest::SHA qw(sha256_hex);
use English     qw(-no_match_vars);
use Errno       qw(EINTR);
use File::Temp  qw(tempdir tempfile);
use File::Copy  qw(copy);
use File::Find  qw(find);
use File::Path  qw(make_path);
use File::Spec;
use Mojo::File qw(path);
use Mojo::UserAgent;
use Mojo::Util  qw(url_escape steady_time);
use POSIX       qw(WNOHANG);
use Time::HiRes qw(sleep);
use Test::More;
use GPForum::OS::SupervisorProbe;
our $VERSION = '0.001';
const my $EXEC_FAILURE    => 127;
const my $COMMAND_SECONDS => 30;
const my $COMMAND_BYTES   => 262_144;
const my $CLIENT_SECONDS  => 8;
const my $SETTLE_SECONDS  => 1.2;
const my $CONNECT_SECONDS => 0.1;
const my $REQUEST_SECONDS => 0.3;
const my $HTTP_OK         => 200;
const my $WAIT_SECONDS    => 15;
const my $POLL_SECONDS    => 0.05;

if ( !$ENV{GPFORUM_REQUIRE_NATIVE_SUPERVISOR} ) {
    plan skip_all =>
      'opt in with GPFORUM_REQUIRE_NATIVE_SUPERVISOR=1 on a test host';
}
my $dir         = tempdir( 'gpfnativeXXXX', DIR => '/tmp', CLEANUP => 1 );
my $source_root = path(q{.})->to_abs->to_string;
my $root        = "$dir/code";
_stage( "$source_root/lib",             "$root/lib" );
_stage( "$source_root/local/lib/perl5", "$root/local/lib/perl5" );
make_path("$root/t/fixtures");
copy(
    "$source_root/t/fixtures/unix-service.pl",
    "$root/t/fixtures/unix-service.pl"
) or croak 'cannot stage native fixture';
my $probe = GPForum::OS::SupervisorProbe->new(
    directory => $dir,
    arguments => [
        $EXECUTABLE_NAME,                   '-I' . $root . '/local/lib/perl5',
        "$root/t/fixtures/unix-service.pl", $dir,
    ],
    runner => \&_command,
);
my $client;

END {
    if ( $probe && $probe->active ) {
        try { $probe->stop; } catch ($error) {
            carp $error;
        };
    }
    if ($client) { kill 'KILL', $client; waitpid $client, 0; }
}

diag(   'native='
      . $probe->platform->name
      . " perl=$OLD_PERL_VERSION runtime=$EXECUTABLE_NAME" );
for my $file (
    qw(lib/GPForum/OS/SupervisorProbe.pm lib/GPForum/OS/ServiceManager.pm lib/GPForum/Log.pm lib/GPForum/Log/File.pm t/fixtures/unix-service.pl)
  )
{
    diag( $file . ' sha256=' . sha256_hex( path( $root, $file )->slurp ) );
}
_exercise();

sub _exercise {
    my $started = $probe->start;
    is( $started->{status}, 0, 'native supervisor accepts its isolated job' )
      or BAIL_OUT( $started->{output} );
    ok(
        _until( sub { return _healthy(); } ),
        'supervised manager becomes healthy'
    ) or _fatal();
    my $first = $probe->pid;
    ok( $first, 'native job has a manager PID' );

    is( $probe->crash->{status}, 0, 'crash targets only this test job' );
    ok(
        _until(
            sub {
                return
                     $probe->pid
                  && $probe->pid != $first
                  && _healthy();
            }
        ),
        'native supervisor restarts the crashed manager'
    ) or _fatal();

    if ( $probe->supports_watchdog ) {
        my $before = $probe->pid;
        is( $probe->block->{status}, 0, 'block only the test manager' );
        ok(
            _until(
                sub {
                    return
                         $probe->pid
                      && $probe->pid != $before
                      && _healthy();
                }
            ),
            'systemd watchdog recovers the blocked manager'
        ) or _fatal();
    }

    my $pid = fork // croak 'cannot fork slow client';
    if ( !$pid ) {
        my $tx =
          _ua()->request_timeout($CLIENT_SECONDS)->get( _base() . '/slow' );
        path("$dir/response")
          ->spew( ( $tx->res->code // 0 ) . q{ } . $tx->res->body );
        POSIX::_exit(0);
    }
    $client = $pid;
    ok( _until( sub { return -f "$dir/started" } ),
        'real request is in progress' );
    is( $probe->stop->{status}, 0, 'native stop completes' );
    ok( _until( sub { return waitpid( $client, WNOHANG ) == $client } ),
        'client is reaped' );
    $client = undef;
    is( path("$dir/response")->slurp,
        '200 finished', 'native stop preserves its in-flight response' );
    ok( _until( sub { return !-e "$dir/manager.pid" } ),
        'stopped job removes its PID file' );
    sleep $SETTLE_SECONDS;
    ok( !_serving(), 'explicit native stop does not respawn the job' );
    done_testing();

    return;
}

# Capture to a private file so supervisor tools cannot deadlock on a full
# stdout/stderr pipe. Bound both execution time and diagnostic output.
sub _command (@arguments) {
    my ($capture) = tempfile( DIR => $dir, UNLINK => 1 );
    my $pid = fork // croak 'cannot fork native command';
    if ( !$pid ) {
        open STDIN,  '<',  '/dev/null' or POSIX::_exit($EXEC_FAILURE);
        open STDOUT, '>&', $capture    or POSIX::_exit($EXEC_FAILURE);
        open STDERR, '>&', $capture    or POSIX::_exit($EXEC_FAILURE);
        exec { $arguments[0] } @arguments or POSIX::_exit($EXEC_FAILURE);
    }
    my $status = _wait_command($pid);
    seek $capture, 0, 0 or croak 'cannot seek native command capture';
    my $output = q{};
    my $read   = read $capture, $output, $COMMAND_BYTES;
    defined $read  or croak 'cannot read native command capture';
    close $capture or croak 'cannot close native command capture';
    return { status => $status, output => $output };
}

sub _wait_command ($pid) {
    my $deadline = steady_time + $COMMAND_SECONDS;
    while ( steady_time < $deadline ) {
        my $reaped = waitpid $pid, WNOHANG;
        return $CHILD_ERROR                if $reaped == $pid;
        croak 'cannot reap native command' if $reaped < 0 && $ERRNO != EINTR;
        sleep $POLL_SECONDS;
    }
    kill 'KILL', $pid;
    waitpid $pid, 0;
    croak 'native command exceeded its deadline';
}

sub _healthy { return _serving() && $probe->ready; }

sub _base { return 'http+unix://' . url_escape("$dir/http.sock"); }

sub _ua {
    return Mojo::UserAgent->new->connect_timeout($CONNECT_SECONDS)
      ->request_timeout($REQUEST_SECONDS);
}

sub _serving {
    return 0 if !-S "$dir/http.sock" || !$probe->pid;
    my $tx = _ua()->get( _base() . q{/} );
    return ( $tx->res->code // 0 ) == $HTTP_OK
      && $tx->res->body eq q{} . $probe->pid;
}

sub _until ($check) {
    my $deadline = steady_time + $WAIT_SECONDS;
    while ( steady_time < $deadline ) {
        return 1 if $check->();
        sleep $POLL_SECONDS;
    }
    return 0;
}

sub _fatal {
    diag( $probe->diagnostics );
    BAIL_OUT('native supervisor did not reach the expected state');
    return;
}

sub _stage ( $source, $target ) {
    find(
        {
            no_chdir => 1,
            wanted   => sub {
                my $relative =
                  File::Spec->abs2rel( $File::Find::name, $source );
                my $destination = File::Spec->catfile( $target, $relative );
                if    ( -d $File::Find::name ) { make_path($destination); }
                elsif ( -f $File::Find::name ) {
                    copy( $File::Find::name, $destination )
                      or croak 'cannot stage native runtime';
                }
            }
        },
        $source
    );
    return;
}

1;
