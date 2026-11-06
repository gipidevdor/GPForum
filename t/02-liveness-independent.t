# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;
use v5.40;
use lib 'lib', 't/lib';
use Const::Fast;
use Carp qw(croak);
use Test::More;
use Test::Mojo;
use GPForum::Test::ReplacedSubs qw(with_replaced_subs);

our $VERSION = '0.001';
const my $HTTP_OK        => 200;
const my $HTTP_NOT_FOUND => 404;
const my $USER_ID        => '018f1002-0001-7000-8000-000000000001';

my $test = Test::Mojo->new('GPForum');
my ( $lookups, $validations, @routes ) = ( 0, 0 );
$test->app->helper(
    gp_identity_store => sub {
        $validations++;
        croak 'liveness must not consult the durable session store';
    }
);
$test->app->hook(
    after_dispatch => sub ($controller) {
        push @routes, $controller->current_route;
        return;
    }
);

# Send a real signed session cookie: public liveness must remain independent
# of a durable session even when a browser is already signed in.
my $carrier = $test->app->build_controller;
$carrier->session(
    user_id       => $USER_ID,
    session_id    => 'liveness-session',
    session_token => 'liveness-session-token',
);
$test->app->sessions->store($carrier);
my ($cookie) = $carrier->res->cookies->@*;
ok( $cookie, 'the fixture carries a genuine signed session cookie' );
my $cookie_header = $cookie->name . q{=} . $cookie->value;

with_replaced_subs(
    'Mojolicious::Static',
    {
        dispatch => sub { $lookups++; return; },
    },
    sub {
        $test->get_ok( '/health/live' => { Cookie => $cookie_header } );
        $test->status_is($HTTP_OK);
        $test->json_is( '/status' => 'ok' );
        $test->json_is( '/check'  => 'live' );
        $test->header_is( 'X-Content-Type-Options' => 'nosniff' );
        $test->header_like( 'X-Request-ID' => qr/\S/msx );
        $test->head_ok('/health/live');
        $test->status_is($HTTP_OK);
        $test->content_is(q{});
        is( $lookups, 0, 'GET and HEAD avoid filesystem-backed static lookup' );
        is( $validations, 0, 'a signed session adds no durable lookup' );
        is_deeply(
            \@routes,
            [ 'health_live', 'health_live' ],
            'response observers retain the liveness route identity'
        );
        return;
    }
);

$test->ua->cookie_jar->empty;
$test->post_ok('/health/live')->status_is($HTTP_NOT_FOUND);
done_testing;

1;
