# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;
use v5.40;
use Carp       qw(croak);
use English    qw(-no_match_vars);
use File::Temp qw(tempdir);
use Mojo::File qw(path);
use Mojo::IOLoop;
use Mojo::UserAgent;
use Mojo::Util qw(url_escape steady_time);
use Mojolicious;
use POSIX       qw(WNOHANG);
use Time::HiRes qw(sleep);
use Const::Fast;
use Test::More;
use GPForum::OS::ServiceManager;
use GPForum::OS::UnixListener;
use GPForum::Log;
use GPForum::Config;

our $VERSION = '0.001';
const my $SLOW_SECONDS    => 0.5;
const my $CONNECT_SECONDS => 0.1;
const my $REQUEST_SECONDS => 0.2;
const my $CLIENT_SECONDS  => 5;
const my $WAIT_SECONDS    => 6;
const my $POLL_SECONDS    => 0.01;
const my $HTTP_OK         => 200;
const my $STOP_LIMIT      => 4;
const my $OVERDUE_SECONDS => 10;
my %owned;

END {
    for my $pid ( keys %owned ) {
        kill 'KILL', $pid;
        waitpid $pid, 0;
    }
}

for my $signal (qw(TERM INT QUIT)) {
    subtest "$signal drains a real HTTP request under the original PID" => sub {
        my $dir = _directory();
        my $pid = _start($dir);
        ok( _until( sub { return _get($dir) } ), 'worker answers HTTP' );
        is( path("$dir/manager.pid")->slurp,
            "$pid\n", 'the directly launched process is the manager' );
        my $client = _client($dir);
        ok( _until( sub { return -e "$dir/started" } ),
            'slow request is in progress' );
        ok( kill( $signal, $pid ), 'manager receives the stop signal' );
        is( _reap($client), 0, 'client completes successfully' );
        is( path("$dir/response")->slurp,
            '200 finished', 'the in-flight response is preserved' );
        is( _reap($pid), 0, 'manager exits cleanly' );
        ok( !-e "$dir/manager.pid", 'owned PID file is removed' );
    };
}

subtest 'a second start cannot replace the first service socket' => sub {
    my $dir = _directory();
    my $pid = _start($dir);
    ok( _until( sub { return _get($dir) } ), 'first instance is serving' );
    my $contender = _start( $dir, 'second' );
    isnt( _reap($contender), 0, 'second instance fails' );
    like(
        path("$dir/second.log")->slurp,
        qr/another[ ]service[ ]manager/msx,
        'lock refusal is observable'
    );
    ok( _get($dir), 'the first listener still answers' );
    is( path("$dir/manager.pid")->slurp,
        "$pid\n", 'the first PID remains authoritative' );
    kill 'TERM', $pid or croak 'cannot stop first manager';
    is( _reap($pid), 0, 'first manager stops normally' );
};

subtest 'a crash releases the manager lock and permits immediate recovery' =>
  sub {
    my $dir = _directory();
    my $pid = _start($dir);
    ok( _until( sub { return _get($dir) } ), 'first instance is serving' );
    kill 'KILL', $pid or croak 'cannot crash owned manager';
    isnt( _reap($pid), 0, 'manager really died unexpectedly' );
    my $next = _start( $dir, 'recovery' );
    ok(
        _until( sub { return _get( $dir, $next ) } ),
        'workers did not retain the old lock or block recovery'
    );
    is( path("$dir/manager.pid")->slurp,
        "$next\n", 'stale PID is replaced by the new owner' );
    kill 'TERM', $next or croak 'cannot stop recovered manager';
    is( _reap($next), 0, 'recovered instance drains normally' );
  };

subtest 'a worker that fails at startup fails the service' => sub {
    my $dir = _directory();
    my $pid = _start( $dir, 'failed-worker', 1 );
    isnt( _reap($pid), 0, 'the supervisor receives a failure status' );
    like(
        path("$dir/failed-worker.log")->slurp,
        qr/stopped[ ]without[ ]a[ ]graceful[ ]shutdown/msx,
        'startup failure is reported instead of a successful exit'
    );
    ok( !-e "$dir/manager.pid", 'failed startup removes its PID file' );
};

subtest 'HUP reopens logs in both manager and forked workers' => sub {
    my $dir = _directory();
    my $pid = _start($dir);
    ok( _until( sub { return _get( $dir, $pid ) } ), 'worker is serving' );
    rename "$dir/application.log", "$dir/application.log.1"
      or croak 'cannot rotate application log';
    kill 'HUP', $pid or croak 'cannot request manager rotation';
    ok(
        _until(
            sub {
                _get( $dir, $pid );
                return -f "$dir/application.log"
                  && path("$dir/application.log")->slurp =~
                  /worker[ ]request/msx;
            }
        ),
        'the worker receives the reopen request and writes to the new file'
    );
    kill 'TERM', $pid or croak 'cannot stop rotated service';
    is( _reap($pid), 0, 'rotation preserves normal lifecycle' );
    like(
        path("$dir/application.log")->slurp,
        qr/Manager[ ]\d+[ ]stopped/msx,
        'the manager also writes its shutdown to the new file'
    );
};

subtest 'an unowned live PID file survives a refused start' => sub {
    my $dir = _directory();
    path("$dir/manager.pid")->spew("$PROCESS_ID\n");
    my $pid = _start($dir);
    isnt( _reap($pid), 0, 'a live owner prevents startup' );
    is( path("$dir/manager.pid")->slurp,
        "$PROCESS_ID\n",
        'a failed candidate cannot remove another owner\'s PID file' );
};

subtest 'the graceful deadline bounds an overdue request' => sub {
    my $dir = _directory();
    my $pid = _start($dir);
    ok( _until( sub { return _get( $dir, $pid ) } ), 'worker is serving' );
    my $request = _client( $dir, '/overdue' );
    ok( _until( sub { return -e "$dir/started" } ), 'overdue request started' );
    my $began = steady_time;
    kill 'TERM', $pid or croak 'cannot stop overdue manager';
    is( _reap($pid), 0, 'the manager completes its bounded graceful stop' );
    cmp_ok( steady_time - $began,
        '<', $STOP_LIMIT, 'the configured deadline is enforced' );
    is( _reap($request), 0, 'the disconnected client is reaped' );
    like(
        path("$dir/application.log")->slurp,
        qr/Stopping[ ]worker[ ]\d+[ ]immediately/msx,
        'forced worker termination is observable'
    );
};

done_testing();

sub _directory {
    return tempdir( 'gpfdaemonXXXX', DIR => '/tmp', CLEANUP => 1 );
}

sub _start ( $dir, $name = 'service', $fail_worker = 0 ) {
    my $pid = fork // croak 'cannot fork manager';
    if ( !$pid ) {
        open STDOUT, '>',  "$dir/$name.log" or POSIX::_exit(1);
        open STDERR, '>&', \*STDOUT         or POSIX::_exit(1);
        my $app = Mojolicious->new;
        GPForum::Log->configure(
            $app,
            GPForum::Config->new(
                log_path  => "$dir/application.log",
                log_level => 'info'
            )
        );
        GPForum::OS::UnixListener->register($app);
        if ($fail_worker) {
            Mojo::IOLoop->next_tick( sub { POSIX::_exit(1) } );
        }
        my $owner = $PROCESS_ID;
        $app->routes->get(q{/})->to(
            cb => sub ($c) {
                $c->log->info('worker request');
                $c->render( text => "$owner" );
            }
        );
        $app->routes->get('/slow')->to(
            cb => sub ($c) {
                path("$dir/started")->spew('started');
                $c->render_later;
                Mojo::IOLoop->timer(
                    $SLOW_SECONDS => sub { $c->render( text => 'finished' ) } );
            }
        );
        $app->routes->get('/overdue')->to(
            cb => sub ($c) {
                path("$dir/started")->spew('started');
                $c->render_later;
                Mojo::IOLoop->timer(
                    $OVERDUE_SECONDS => sub { $c->render( text => 'late' ) } );
            }
        );
        my $manager = GPForum::OS::ServiceManager->new(
            app      => $app,
            listen   => [ 'http+unix://' . url_escape("$dir/http.sock") ],
            pid_file => "$dir/manager.pid",
            workers  => 1,
            spare    => 0,
            heartbeat_interval => $CONNECT_SECONDS,
            heartbeat_timeout  => 2,
            graceful_timeout   => 2
        );
        try { $manager->run; }
        catch ($error) {
            print {*STDERR} $error or POSIX::_exit(1);
            undef $manager;
            POSIX::_exit(1);
        };
        POSIX::_exit(0);
    }
    $owned{$pid} = 1;
    return $pid;
}

sub _get ( $dir, $owner = undef ) {
    return 0 if !-S "$dir/http.sock";
    my $ua = Mojo::UserAgent->new->connect_timeout($CONNECT_SECONDS)
      ->request_timeout($REQUEST_SECONDS);
    my $tx = $ua->get( 'http+unix://' . url_escape("$dir/http.sock") . q{/} );
    return ( $tx->res->code // 0 ) == $HTTP_OK
      && ( !defined $owner || $tx->res->body eq "$owner" );
}

sub _client ( $dir, $route = '/slow' ) {
    my $pid = fork // croak 'cannot fork client';
    if ( !$pid ) {
        my $tx = Mojo::UserAgent->new->request_timeout($CLIENT_SECONDS)
          ->get( 'http+unix://' . url_escape("$dir/http.sock") . $route );
        path("$dir/response")
          ->spew( ( $tx->res->code // 0 ) . q{ } . $tx->res->body );
        POSIX::_exit(0);
    }
    $owned{$pid} = 1;
    return $pid;
}

sub _until ($check) {
    my $deadline = steady_time + $WAIT_SECONDS;
    while ( steady_time < $deadline ) {
        return 1 if $check->();
        sleep $POLL_SECONDS;
    }
    return 0;
}

sub _reap ($pid) {
    my $done   = _until( sub { return waitpid( $pid, WNOHANG ) == $pid } );
    my $status = $CHILD_ERROR;
    if ( !$done ) {
        kill 'KILL', $pid;
        waitpid $pid, 0;
        $status = $CHILD_ERROR;
        fail('owned process exceeded its shutdown deadline');
    }
    delete $owned{$pid};
    return $status;
}

1;
