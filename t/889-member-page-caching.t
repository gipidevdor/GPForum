# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;
use Test::More;
use Test::Mojo;
use lib 'lib';
use lib 't/lib';

our $VERSION = '0.001';

# ASVS 5.0 14.3.2: an answer rendered for a member is kept by no cache unless
# its action chose otherwise, and every negotiated answer varies on the
# headers that choose between the page, its JSON and its htmx fragment.
my $test   = Test::Mojo->new('GPForum');
my $routes = $test->app->routes;
$routes->get(
    '/__member-page' => sub ($controller) {
        $controller->session( user_id => 'user-1' );
        $controller->render( text => 'member', format => 'html' );
    }
);
$routes->get(
    '/__guest-page' => sub ($controller) {
        $controller->render( text => 'guest', format => 'html' );
    }
);
$routes->get(
    '/__chosen-cache' => sub ($controller) {
        $controller->session( user_id => 'user-1' );
        $controller->res->headers->cache_control('public, max-age=60');
        $controller->render( json => { ok => 1 } );
    }
);
$routes->get(
    '/__member-text' => sub ($controller) {
        $controller->session( user_id => 'user-1' );
        $controller->render( text => 'plain', format => 'txt' );
    }
);

$test->get_ok('/__member-page')
  ->header_is( 'Cache-Control' => 'private, no-store' );
$test->header_like( Vary => qr/\bAccept\b/msx )
  ->header_like( Vary => qr/\bHX-Request\b/msx );
$test->get_ok('/__guest-page')->header_is(
    'Cache-Control' => 'private, no-store',
    'the session cookie the member page set still keeps this page private'
);

my $guest = Test::Mojo->new('GPForum');
$guest->app->routes->get(
    '/__guest-page' => sub ($controller) {
        $controller->render( text => 'guest', format => 'html' );
    }
);
$guest->get_ok('/__guest-page')
  ->header_is( 'Cache-Control' => undef, 'a guest page chooses nothing' )
  ->header_like( Vary => qr/\bAccept\b/msx );
$test->get_ok('/__chosen-cache')->header_is(
    'Cache-Control' => 'public, max-age=60',
    'an action that chose its caching keeps it'
);
$test->get_ok('/__member-text')->header_is(
    'Cache-Control' => undef,
    'a type that is neither a page nor JSON is left alone'
);

done_testing();

1;
