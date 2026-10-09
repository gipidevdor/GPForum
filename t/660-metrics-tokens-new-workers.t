# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Carp qw(croak);
use Const::Fast;
use English    qw(-no_match_vars);
use File::Temp qw(tempdir);
use Mojo::File qw(path);
use Mojo::IOLoop::Server;
use Mojo::Server::Daemon;
use Mojo::Server::Prefork;
use Mojo::UserAgent;
use POSIX       qw(_exit);
use Time::HiRes qw(sleep time);
use Test::Mojo;
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Command::Secret;
use GPForum::Service::Operations::MetricsTokens;
use GPForum::Test::MetricsSnapshot;
use GPForum::Test::ReadyHealth;

our $VERSION = '0.001';

# Token review and walkthrough 4 (friction 1), 2026-10-11: a worker
# Hypnotoad forked after gpforum secret rotate metrics --finish accepted the
# token --finish dropped. The tokens follow the environment file (ADR 0124),
# but only in the processes that answer a check: the manager serves none,
# so it kept the tokens the service started with, and a worker forked from
# it while the file could not be used -- a line that is not NAME=value, say
# -- kept them too. Rotate A to B, finish, break a line, replace the
# workers: the new ones took A and refused B. The manager now reads the
# file at each turn of its loop, so a new worker starts from the list it
# accepted last.

const my $SECRET_FILE_MODE  => oct '640';
const my $TOKEN_LENGTH      => 64;
const my $FIRST             => 'a' x $TOKEN_LENGTH;
const my $HTTP_OK           => 200;
const my $HTTP_UNAUTHORIZED => 401;
const my $MALFORMED         => "this line is not an assignment\n";
const my $EXIT_SHIFT        => 8;
const my $REFUSED_FIRST     => 1;
const my $ACCEPTED_NEW      => 2;
const my $HEARTBEAT_SECONDS => 0.2;
const my $MANAGER_TURNS     => 1.5;
const my $LONGEST_WAIT_SECS => 20;
const my $POLL              => 0.05;

local $ENV{LC_ALL}                 = 'en_US.UTF-8';
local $ENV{GPFORUM_WARMUP_ENABLED} = 0;

my $directory = tempdir( CLEANUP => 1 );

subtest 'a worker forked after --finish refuses the token it dropped' =>
  \&_forked_after_finish;
subtest 'and so does one forked once the manager found the file unusable' =>
  \&_forked_after_unusable;
subtest 'only a pre-forking server, for a followed file, is told to read' =>
  \&_only_prefork_followed;
subtest 'a running pre-forking server replaces a worker: the same' =>
  \&_running_prefork;

done_testing();

# The reviewer's sketch: the application built as Hypnotoad builds it, a
# Prefork manager told it is about to start, the file rotated and finished,
# one turn of the manager's loop, a line it cannot use, and a fork, as the
# manager forks a worker.
sub _forked_after_finish {
    my $service = _service('finish.env');
    my $new     = _rotated_and_finished( $service->{file} );

    $service->{manager}->emit('wait');
    _append( $service->{file}, $MALFORMED );

    my $answer = _in_a_worker( $service->{test}, $new );
    ok( $answer & $REFUSED_FIRST, 'the dropped token is refused' );
    ok( $answer & $ACCEPTED_NEW,  'and the one in use is accepted' );

    return;
}

sub _forked_after_unusable {
    my $service = _service('unusable.env');
    my $new     = _rotated_and_finished( $service->{file} );

    $service->{manager}->emit('wait');
    _append( $service->{file}, $MALFORMED );
    $service->{manager}->emit('wait');

    my $answer = _in_a_worker( $service->{test}, $new );
    ok( $answer & $REFUSED_FIRST,
        'the manager keeps the list it accepted last, not the start one' );
    ok( $answer & $ACCEPTED_NEW, 'and the worker inherits it' );

    return;
}

sub _only_prefork_followed {
    my $service = _service('daemon.env');
    my $tokens =
      GPForum::Service::Operations::MetricsTokens->for_config(
        $service->{test}->app->gp_config );
    ok( $tokens->following, 'the service follows its file' );
    ok(
        !$tokens->follow_in_manager( Mojo::Server::Daemon->new ),
        'a server that does not fork has no manager to read'
    );

    local $ENV{GPFORUM_ENV_FILE}      = $service->{file};
    local $ENV{GPFORUM_METRICS_TOKEN} = 'b' x $TOKEN_LENGTH;
    my $unfollowed = Test::Mojo->new('GPForum');
    my $other =
      GPForum::Service::Operations::MetricsTokens->for_config(
        $unfollowed->app->gp_config );
    ok( !$other->following, 'a file holding other tokens is not followed' );
    ok( !$other->follow_in_manager( Mojo::Server::Prefork->new ),
        'and its manager reads nothing' );

    return;
}

# A Prefork manager running in its own process, with one worker, on a free
# port, as Hypnotoad runs the units' service: the worker is stopped after
# --finish and a line it cannot use, and the manager forks the next.
sub _running_prefork {
    my $service = _service('running.env');
    my $port    = Mojo::IOLoop::Server->generate_port;
    my $spawned = path( $directory, 'spawned' );
    my $manager = fork // croak "fork: $ERRNO";
    if ( !$manager ) {
        my $server = Mojo::Server::Prefork->new(
            app                => $service->{test}->app,
            listen             => ["http://127.0.0.1:$port"],
            workers            => 1,
            heartbeat_interval => $HEARTBEAT_SECONDS,
            pid_file           => path( $directory, 'prefork.pid' )->to_string,
        );
        $server->on( spawn => sub ( $, $pid ) { $spawned->spew("$pid\n") } );
        $server->run;
        _exit(0);
    }

    my $user_agent = Mojo::UserAgent->new;
    my $scrape     = sub ($token) {
        return $user_agent->get( "http://127.0.0.1:$port/metrics" =>
              { 'X-GPForum-Metrics-Token' => $token } )->result->code;
    };
    my $first = _within( sub { _answer( $scrape, $FIRST ) == $HTTP_OK } );
    ok( $first, 'the service answers the token it started with' );
    my $worker = $spawned->slurp =~ s/\s+\z//rmsx;

    my $new = _rotated_and_finished( $service->{file} );
    is( $scrape->($new),   $HTTP_OK,           'the new token, at once' );
    is( $scrape->($FIRST), $HTTP_UNAUTHORIZED, 'finished, the first refused' );
    sleep $MANAGER_TURNS;
    _append( $service->{file}, $MALFORMED );

    kill 'TERM', $worker or croak "kill: $ERRNO";
    my $replaced = _within(
        sub {
            my $now = -e $spawned ? $spawned->slurp =~ s/\s+\z//rmsx : $worker;
            return $now ne $worker && _answer( $scrape, $new ) != 0;
        }
    );
    ok( $replaced, 'the manager forked another worker' );
    is( $scrape->($FIRST), $HTTP_UNAUTHORIZED,
        'which refuses the token --finish dropped' );
    is( $scrape->($new), $HTTP_OK, 'and accepts the one in use' );

    kill 'TERM', $manager or croak "kill: $ERRNO";
    waitpid $manager, 0;

    return;
}

# The service as bin/gpforum starts it under its unit: the file it read in
# GPFORUM_ENV_FILE, its token in the process environment.
sub _service ($name) {
    my $file = path( $directory, $name );
    _write( $file,
        "GPFORUM_ENV=production\n" . "GPFORUM_METRICS_TOKEN=$FIRST\n" );
    local $ENV{GPFORUM_ENV_FILE}      = "$file";
    local $ENV{GPFORUM_METRICS_TOKEN} = $FIRST;
    my $test = Test::Mojo->new('GPForum');
    $test->app->log->level('error');
    $test->app->helper(
        gp_metrics_snapshot => sub { GPForum::Test::MetricsSnapshot->new } );
    $test->app->helper(
        gp_readiness => sub { GPForum::Test::ReadyHealth->new } );
    my $manager = Mojo::Server::Prefork->new( app => $test->app );
    $test->app->server($manager);

    return { file => "$file", manager => $manager, test => $test };
}

# What a worker forked now answers, as bits: the first token refused, the
# one in use accepted.
sub _in_a_worker ( $test, $new ) {
    my $child = fork // croak "fork: $ERRNO";
    if ( !$child ) {
        my $code = sub ($token) {
            return $test->ua->get(
                '/metrics' => { 'X-GPForum-Metrics-Token' => $token } )
              ->result->code;
        };
        _exit( ( $code->($FIRST) == $HTTP_UNAUTHORIZED ? $REFUSED_FIRST : 0 ) |
              ( $code->($new) == $HTTP_OK ? $ACCEPTED_NEW : 0 ) );
    }
    waitpid $child, 0;

    return $CHILD_ERROR >> $EXIT_SHIFT;
}

sub _rotated_and_finished ($file) {
    _secret( $file, 'rotate', 'metrics' );
    my $new = _token($file);
    _secret( $file, 'rotate', 'metrics', '--finish' );

    return $new;
}

sub _token ($file) {
    my ($token) = path($file)->slurp =~ /^GPFORUM_METRICS_TOKEN=(\S+)$/msx;

    return $token;
}

sub _secret ( $file, @arguments ) {
    my $output = q{};
    open my $stdout, '>', \$output or croak 'capture stdout';
    local *STDOUT = $stdout;
    my $status = GPForum::Command::Secret->new(
        file               => $file,
        services_installed => 1,
        metrics_reread     => 1,
    )->run(@arguments);
    close $stdout or croak 'close stdout';
    croak "secret @arguments: $output" if $status;

    return;
}

# Replaced in one rename, as gpforum secret rotate writes it.
sub _write ( $file, $text ) {
    my $next = "$file.next";
    path($next)->spew($text);
    chmod $SECRET_FILE_MODE, $next or croak "chmod: $ERRNO";
    rename $next, "$file" or croak "rename: $ERRNO";

    return;
}

sub _append ( $file, $line ) {
    _write( $file, path($file)->slurp . $line );

    return;
}

# The status a scrape answered, or 0 while nothing listens.
sub _answer ( $scrape, $token ) {
    my $code = 0;
    try {
        $code = $scrape->($token);
    }
    catch ($error) {
        $code = 0;
    };

    return $code;
}

sub _within ($done) {
    my $deadline = time + $LONGEST_WAIT_SECS;
    while ( time < $deadline ) {
        return 1 if $done->();
        sleep $POLL;
    }

    return 0;
}

1;
