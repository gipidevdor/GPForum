#!/usr/bin/env perl
# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package main;
use v5.40;
use FindBin;
use lib "$FindBin::Bin/../../lib";
use English    qw(-no_match_vars);
use Mojo::File qw(path);
use Mojo::IOLoop;
use Mojo::Util qw(url_escape);
use Mojolicious;
use GPForum::Config;
use GPForum::Log;
use GPForum::OS::ServiceManager;
use GPForum::OS::SystemdNotify;
use GPForum::OS::UnixListener;
our $VERSION = '0.001';
my $dir = shift @ARGV;
die "choose an existing test directory\n" if !defined $dir || !-d $dir || @ARGV;
my $app = Mojolicious->new;
GPForum::Log->configure(
    $app,
    GPForum::Config->new(
        log_path  => "$dir/application.log",
        log_level => 'info'
    )
);
GPForum::OS::UnixListener->register($app);
my $owner = $PROCESS_ID;

for my $route ( q{/}, '/health/live', '/health/ready' ) {
    $app->routes->get($route)
      ->to( cb => sub($c) { $c->render( text => "$owner" ) } );
}
$app->routes->get('/slow')->to(
    cb => sub($c) {
        path("$dir/started")->spew('started');
        $c->render_later;
        Mojo::IOLoop->timer( 1 => sub { $c->render( text => 'finished' ) } );
    }
);
my $listen = 'http+unix://' . url_escape("$dir/http.sock");
if ( $ENV{NOTIFY_SOCKET} ) {
    my $notify = GPForum::OS::SystemdNotify->new( interval => 0.1 );
    $app->hook( before_server_start =>
          sub( $server, $ ) { $notify->attach( $server, $listen ) } );
}
GPForum::OS::ServiceManager->new(
    app                => $app,
    listen             => [$listen],
    pid_file           => "$dir/manager.pid",
    workers            => 1,
    spare              => 0,
    graceful_timeout   => 3,
    heartbeat_interval => 0.1,
    heartbeat_timeout  => 2,
)->run;

1;
