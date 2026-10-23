# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause
package main;
use v5.40;
use Const::Fast;
use Test::Mojo;
use Test::More;
use lib 'lib';
use lib 't/lib';
use GPForum::Test::ForumWebServices;
use GPForum::Test::DenyLimiter;
our $VERSION = '0.001';
const my $HTTP_OK           => 200;
const my $HTTP_UNAUTHORIZED => 401;
const my $HTTP_TOO_MANY     => 429;
my $test     = Test::Mojo->new('GPForum');
my $services = GPForum::Test::ForumWebServices->new;

for my $helper (
    qw(gp_notification_dispatcher gp_rate_limiter gp_suspension_store))
{
    $test->app->helper( $helper => sub { return $services; } );
}
my $routes = $test->app->routes;
$routes->get('/__test/session')->to(
    cb => sub ($c) {
        $c->session( user_id => 'user-1' );
        return $c->render( json => { ok => 1 } );
    }
);
$test->get_ok( '/notifications/summary' => { Accept => 'application/json' } )
  ->status_is($HTTP_UNAUTHORIZED);
$test->get_ok('/__test/session')->status_is($HTTP_OK);
$test->get_ok('/notifications/summary')->status_is($HTTP_OK);
$test->json_is( { unread_count => 1 } );
$test->header_is( 'Cache-Control' => 'private, no-store' );
$test->app->helper(
    gp_rate_limiter => sub { return GPForum::Test::DenyLimiter->new; } );
$test->get_ok('/notifications/summary')->status_is($HTTP_TOO_MANY);
$test->header_is( 'Cache-Control' => 'private, no-store' );
done_testing;
1;
