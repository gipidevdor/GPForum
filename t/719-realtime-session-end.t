# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use Mojo::JSON qw(decode_json);
use Mojolicious;
use Test::Mojo;
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Config;
use GPForum::Service::Operations::SecurityTelemetry;
use GPForum::Service::Realtime::ChannelAuthorizer;
use GPForum::Service::Realtime::ConnectionRegistry;
use GPForum::Service::Realtime::Hub;
use GPForum::Test::AllowLimiter;
use GPForum::Test::Id;
use GPForum::Test::LiveSessions;
use GPForum::Test::RealtimePermissionEngine;
use GPForum::Test::RealtimeSupervisorIOLoop;

our $VERSION = '0.001';

const my $HTTP_OK        => 200;
const my $SESSION_ENDED  => 1008;
const my $CHECK_SECONDS  => 30;
const my $LIVE_SESSION   => '018f1000-0000-7000-8000-000000000601';
const my $ENDED_SESSION  => '018f1000-0000-7000-8000-000000000602';
const my $SESSION_CHECKS => 3;

# A realtime socket outlived the session it was opened in: signing out, a
# password change or a sign-out everywhere ended the session, and the
# socket kept receiving the member's notification badges and the threads
# they followed. The hub now asks, every half minute and in one call for
# all its sockets, which of their sessions are still live, and closes the
# others; signing out closes that session's sockets on its own worker at
# once.
my $sessions = GPForum::Test::LiveSessions->new(
    live => { $LIVE_SESSION => 1, $ENDED_SESSION => 1 } );
my $loop = GPForum::Test::RealtimeSupervisorIOLoop->new;
my $hub  = GPForum::Service::Realtime::Hub->new(
    authorizer => GPForum::Service::Realtime::ChannelAuthorizer->new(
        permission_engine => GPForum::Test::RealtimePermissionEngine->new,
    ),
    ioloop        => $loop,
    registry      => GPForum::Service::Realtime::ConnectionRegistry->new,
    session_store => $sessions,
);
my $application = _application($hub);
my $live        = _connected( $application, 'user-1', $LIVE_SESSION );
my $ended       = _connected( $application, 'user-2', $ENDED_SESSION );
my $unknown     = _connected( $application, 'user-3', undef );
is( $hub->connection_count, $SESSION_CHECKS, 'three sockets are open' );
is_deeply( [ map { $_->{interval} } @{ $loop->recurring_calls } ],
    [$CHECK_SECONDS],
    'one check is scheduled for them all, every half minute' );

delete $sessions->live->{$ENDED_SESSION};
is( $hub->close_ended_sessions,
    2, 'the check closes the sockets whose session has ended' );
is_deeply(
    $sessions->asked,
    [ [ $LIVE_SESSION, $ENDED_SESSION ] ],
    'asking for the sessions of all its sockets in one call'
);
$ended->finished_ok( $SESSION_ENDED, 'a socket of an ended session closes' );
$unknown->finished_ok( $SESSION_ENDED, 'so does one opened with no session' );
is( $hub->connection_count, 1, 'the live session keeps its socket' );

$sessions->broken(1);
is( $hub->close_ended_sessions, 0,
    'a store that cannot answer closes nothing' );
is( $hub->connection_count, 1, 'its socket stays' );
$sessions->broken(0);

is( $hub->close_session($LIVE_SESSION),
    1, 'signing out closes the sockets of that session' );
$live->finished_ok( $SESSION_ENDED, 'with the same code' );
is( $hub->connection_count, 0, 'and none is left' );
is_deeply( $loop->removed, ['recurring-1'],
    'the check stops with the last socket' );

done_testing();

sub _connected ( $app, $user_id, $session_id ) {
    my $client = Test::Mojo->new($app);
    my $path   = "/sign-in/$user_id";
    if ( defined $session_id ) {
        $path .= "/$session_id";
    }
    $client->get_ok($path)->status_is($HTTP_OK);
    $client->websocket_ok('/realtime');
    $client->message_ok;
    is( decode_json( $client->message->[1] )->{type},
        'realtime.connected', "$user_id connects" );

    return $client;
}

sub _application ($realtime_hub) {
    my $app = Mojolicious->new;
    $app->secrets( ['realtime-session-end'] );
    $app->log->level('fatal');
    push @{ $app->routes->namespaces }, 'GPForum::Controller';

    my $id        = GPForum::Test::Id->new;
    my $config    = GPForum::Config->new;
    my $limiter   = GPForum::Test::AllowLimiter->new;
    my $telemetry = GPForum::Service::Operations::SecurityTelemetry->new;
    $app->helper( gp_config             => sub { return $config; } );
    $app->helper( gp_id                 => sub { return $id; } );
    $app->helper( gp_realtime_hub       => sub { return $realtime_hub; } );
    $app->helper( gp_rate_limiter       => sub { return $limiter; } );
    $app->helper( gp_security_telemetry => sub { return $telemetry; } );
    $app->routes->get(
        '/sign-in/:user_id/*session_id' => { session_id => undef } => sub {
            my ($controller) = @_;

            $controller->session( user_id => $controller->param('user_id') );
            if ( defined $controller->param('session_id') ) {
                $controller->session(
                    session_id => $controller->param('session_id') );
            }
            return $controller->render( text => 'signed in' );
        }
    );
    $app->routes->websocket('/realtime')->to('Realtime#stream');

    return $app;
}

1;
