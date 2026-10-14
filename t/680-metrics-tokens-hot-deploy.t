# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Carp qw(croak);
use Const::Fast;
use English    qw(-no_match_vars);
use File::Temp qw(tempdir);
use Mojo::File qw(path);
use Mojo::Server::Prefork;
use POSIX qw(_exit);
use Test::Mojo;
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Command::Secret;
use GPForum::Command::Support::ServiceEnvironment;
use GPForum::Service::Operations::MetricsTokens;
use GPForum::Test::MetricsSnapshot;
use GPForum::Test::ReadyHealth;

our $VERSION = '0.001';

# Metrics-token review, 2026-10-14: Hypnotoad's hot deployment -- USR2, or
# hypnotoad run against the live service, which gpforum start --service is
# -- execs a new manager with the old one's environment, and that still held
# the token the service started with. Against a live Hypnotoad: rotate A to
# B, --finish, USR2. The new manager found the file holding B, not A, so it
# did not follow the file: its workers accepted A, which --finish had
# dropped, and refused B, until a restart. The manager now writes the list
# it accepts into its environment, so the manager that replaces it starts
# from that list and follows the file.

const my $SECRET_FILE_MODE  => oct '640';
const my $TOKEN_LENGTH      => 64;
const my $FIRST             => 'a' x $TOKEN_LENGTH;
const my $HTTP_OK           => 200;
const my $HTTP_UNAUTHORIZED => 401;
const my $MALFORMED         => "this line is not an assignment\n";
const my $EXIT_SHIFT        => 8;
const my $CURRENT           => 'GPFORUM_METRICS_TOKEN';
const my $PREVIOUS          => 'GPFORUM_METRICS_TOKENS';

local $ENV{LC_ALL}                 = 'en_US.UTF-8';
local $ENV{GPFORUM_WARMUP_ENABLED} = 0;
local $ENV{GPFORUM_LOG_LEVEL}      = q{fatal};

my $directory = tempdir( CLEANUP => 1 );

subtest 'the manager keeps the list it accepted in its environment' =>
  \&_manager_hands_on;
subtest 'a manager started from it follows the file and refuses the old' =>
  \&_next_manager_follows;
subtest 'and starts from it when the file cannot be used then' =>
  \&_next_manager_unusable_file;
subtest 'a worker leaves the environment alone' => \&_worker_hands_nothing;

done_testing();

sub _manager_hands_on {
    my $file = _file('hands-on.env');
    local $ENV{GPFORUM_ENV_FILE} = $file;
    local $ENV{$CURRENT} = $FIRST;
    delete local $ENV{$PREVIOUS};
    my $manager = _manager( _app() );

    _secret( $file, 'rotate', 'metrics' );
    my $new = _token($file);
    $manager->emit('wait');
    is( $ENV{$CURRENT},  $new,   'a rotation: the new token in use' );
    is( $ENV{$PREVIOUS}, $FIRST, 'and the one before still accepted' );

    _secret( $file, 'rotate', 'metrics', '--finish' );
    $manager->emit('wait');
    is( $ENV{$CURRENT},  $new, '--finish: the token in use stays' );
    is( $ENV{$PREVIOUS}, q{},  'and none before it, set so the file cannot' );

    return;
}

sub _next_manager_follows {
    my $file = _file('follows.env');
    local $ENV{GPFORUM_ENV_FILE} = $file;
    local $ENV{$CURRENT} = $FIRST;
    delete local $ENV{$PREVIOUS};
    my $manager = _manager( _app() );
    my $new     = _rotated_and_finished( $file, $manager );

    # What the new manager is built from: the old one's environment.
    my $next = _app();
    ok(
        GPForum::Service::Operations::MetricsTokens->for_config(
            $next->app->gp_config
        )->following,
        'the next manager follows the file'
    );
    is( _code( $next, $FIRST ),
        $HTTP_UNAUTHORIZED, 'it refuses the token --finish dropped' );
    is( _code( $next, $new ), $HTTP_OK, 'and accepts the one in use' );

    _secret( $file, 'rotate', 'metrics' );
    my $third = _token($file);
    _secret( $file, 'rotate', 'metrics', '--finish' );
    is( _code( $next, $third ),
        $HTTP_OK, 'a later rotation reaches it with no restart' );
    is( _code( $next, $new ), $HTTP_UNAUTHORIZED, 'and so does its --finish' );

    return;
}

sub _next_manager_unusable_file {
    my $file = _file('unusable.env');
    local $ENV{GPFORUM_ENV_FILE} = $file;
    local $ENV{$CURRENT} = $FIRST;
    delete local $ENV{$PREVIOUS};
    my $manager = _manager( _app() );
    my $new     = _rotated_and_finished( $file, $manager );

    # The dropped token written back as an earlier one, on a file the
    # service cannot use: the next manager's bin/gpforum loads what it can
    # of it, under the environment the old manager handed on.
    _write( $file, path($file)->slurp . "$PREVIOUS=$FIRST\n" . $MALFORMED );
    local $ENV{GPFORUM_ENV} = q{development};
    GPForum::Command::Support::ServiceEnvironment->new(
        strict => 0,
        file   => $file,
    )->load;
    my $next = _app();
    ok(
        !GPForum::Service::Operations::MetricsTokens->for_config(
            $next->app->gp_config
        )->following,
        'the next manager does not follow a file it cannot use'
    );
    is( _code( $next, $FIRST ),
        $HTTP_UNAUTHORIZED, 'the token --finish dropped stays refused' );
    is( _code( $next, $new ), $HTTP_OK, 'and the one in use accepted' );

    return;
}

sub _worker_hands_nothing {
    my $file = _file('worker.env');
    local $ENV{GPFORUM_ENV_FILE} = $file;
    local $ENV{$CURRENT} = $FIRST;
    delete local $ENV{$PREVIOUS};
    my $test    = _app();
    my $manager = _manager($test);
    $manager->emit('wait');

    _secret( $file, 'rotate', 'metrics' );
    my $new   = _token($file);
    my $child = fork // croak "fork: $ERRNO";
    if ( !$child ) {
        my $accepted  = _code( $test, $new ) == $HTTP_OK    ? 1 : 0;
        my $untouched = ( $ENV{$CURRENT} // q{} ) eq $FIRST ? 2 : 0;
        _exit( $accepted | $untouched );
    }
    waitpid $child, 0;
    my $answer = $CHILD_ERROR >> $EXIT_SHIFT;
    ok( $answer & 1, 'the worker accepts the new token' );
    ok( $answer & 2, 'and leaves its environment as it was' );

    return;
}

# The service as bin/gpforum builds it under its unit, from the process
# environment and the file named in GPFORUM_ENV_FILE.
sub _app {
    my $test = Test::Mojo->new('GPForum');
    $test->app->log->level('fatal');
    $test->app->helper(
        gp_metrics_snapshot => sub { GPForum::Test::MetricsSnapshot->new } );
    $test->app->helper(
        gp_readiness => sub { GPForum::Test::ReadyHealth->new } );

    return $test;
}

# A Prefork manager told it is about to start, as Hypnotoad's is.
sub _manager ($test) {
    my $manager = Mojo::Server::Prefork->new( app => $test->app );
    $test->app->server($manager);

    return $manager;
}

sub _file ($name) {
    my $file = path( $directory, $name )->to_string;
    _write( $file, "GPFORUM_ENV=production\n$CURRENT=$FIRST\n" );

    return $file;
}

sub _rotated_and_finished ( $file, $manager ) {
    _secret( $file, 'rotate', 'metrics' );
    my $new = _token($file);
    $manager->emit('wait');
    _secret( $file, 'rotate', 'metrics', '--finish' );
    $manager->emit('wait');

    return $new;
}

sub _code ( $test, $token ) {
    return $test->ua->get(
        '/metrics' => { 'X-GPForum-Metrics-Token' => $token } )->result->code;
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
    rename $next, $file or croak "rename: $ERRNO";

    return;
}

1;
