# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use Test::Mojo;
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Test::CommandIdempotency;
use GPForum::Test::ForumWebServices;
use GPForum::Test::IdentitySecurityAudit;
use GPForum::Test::IdentityStore;
use GPForum::Web::IdentityAccess;

our $VERSION = '0.001';

const my $HTTP_OK        => 200;
const my $HTTP_FOUND     => 302;
const my $HTTP_FORBIDDEN => 403;
const my $HTTP_ACCEPTED  => 202;
const my $SAME_ORIGIN    => { 'Sec-Fetch-Site' => 'same-origin' };
const my $CROSS_SITE     => { 'Sec-Fetch-Site' => 'cross-site' };
const my $THEME_COOKIE   => GPForum::Web::IdentityAccess->theme_cookie_name;

# A public page is rendered once and served to every anonymous visitor. It
# was rendered with the first visitor's CSRF token in its footer forms (the
# language and the theme), so every other visitor got a token that was not
# theirs and those forms failed for them, while the first visitor's token
# was published to all. And a token was not rotated at sign-in, so a token
# read off a cached page stayed good for its owner's signed-in session.
my $first     = _client();
my $neighbour = Test::Mojo->new( $first->app );

subtest 'a cached page carries no session token' => sub {
    $first->get_ok('/categories')->status_is($HTTP_OK);
    is( _header( $first, 'X-GPForum-Cache' ),
        'miss', 'the first visitor fills the cache' );
    $first->element_exists('form.locale-form');
    $first->element_exists('form.theme-form');
    $first->element_exists_not( 'input[name="csrf_token"]',
        'its forms carry no token' );
    is( _header( $first, 'Set-Cookie' ),
        undef, 'and a public response sets no session cookie' );

    $neighbour->get_ok('/categories')->status_is($HTTP_OK);
    is( _header( $neighbour, 'X-GPForum-Cache' ),
        'hit', 'the second visitor is served the same page' );
    $neighbour->element_exists_not('input[name="csrf_token"]');
};

subtest 'its forms work for each visitor from the same origin' => sub {
    for my $client ( $first, $neighbour ) {
        $client->post_ok(
            '/locale' => $SAME_ORIGIN => form => {
                locale    => 'it',
                return_to => '/categories',
            }
        )->status_is($HTTP_FOUND);
        $client->header_like( 'Set-Cookie' => qr/gpforum_locale=it/msx );
    }

    my $server = $first->ua->server->url;
    my $origin = $server->scheme . q{://} . $server->host_port;
    $first->post_ok(
        '/theme' => { Origin => $origin } => form => { theme => 'dark' } )
      ->status_is( $HTTP_FOUND,
        'a browser without fetch metadata is judged by its Origin' );
};

# The page a visitor is sent back to says what they just did: that line is
# theirs. It was stored with the page and shown to every visitor after them,
# and a visitor sent to a page already cached never saw their own.
subtest 'a page that tells a visitor what they did is theirs alone' => sub {
    my $writer = Test::Mojo->new( $first->app );
    my $reader = Test::Mojo->new( $first->app );
    $writer->post_ok(
        '/theme' => $SAME_ORIGIN => form => {
            return_to => '/categories',
            theme     => 'dark',
        }
    )->status_is($HTTP_FOUND);

    $writer->get_ok('/categories')
      ->status_is($HTTP_OK)
      ->content_like( qr/Theme \s updated/msx, 'the visitor reads the line' );
    is( _header( $writer, 'X-GPForum-Cache' ),
        undef, 'on a page drawn for them, not stored' );

    $reader->get_ok( '/categories' => { Cookie => "$THEME_COOKIE=dark" } )
      ->status_is($HTTP_OK)
      ->content_unlike( qr/Theme \s updated/msx, 'the next visitor does not' );
};

subtest 'a request from elsewhere is refused' => sub {
    $first->post_ok( '/locale' => $CROSS_SITE => form => { locale => 'it' } )
      ->status_is( $HTTP_FORBIDDEN, 'another site cannot post without one' );
    $first->post_ok( '/locale' => form => { locale => 'it' } )
      ->status_is( $HTTP_FORBIDDEN, 'nor can a request that names no origin' );
    $first->post_ok(
        '/theme' => { Origin => 'https://evil.test' } => form =>
          { theme => 'dark' } )
      ->status_is( $HTTP_FORBIDDEN, 'nor one from another origin' );
    $first->post_ok(
        '/theme' => { Origin => 'null' } => form => { theme => 'dark' } )
      ->status_is( $HTTP_FORBIDDEN, 'nor one from an opaque origin' );
    $first->post_ok(
        '/theme' => { 'Sec-Fetch-Site' => 'same-site' } => form =>
          { theme => 'dark' } )
      ->status_is( $HTTP_FORBIDDEN, 'nor one from a sibling site' );
};

subtest 'a stolen token is refused' => sub {
    $first->get_ok('/login')->status_is($HTTP_OK);
    my $token = _csrf_token($first);
    ok( length $token, 'an uncached page carries the session token' );

    $neighbour->post_ok(
        '/locale' => $CROSS_SITE => form => {
            csrf_token => $token,
            locale     => 'it',
        }
    )->status_is( $HTTP_FORBIDDEN, 'another session cannot use it' );
    $first->post_ok(
        '/locale' => $CROSS_SITE => form => {
            csrf_token => $token,
            locale     => 'it',
        }
    )->status_is( $HTTP_FOUND, 'its own session can, from anywhere' );
};

subtest 'the token is rotated at sign-in and at sign-out' => sub {
    $first->get_ok('/login')->status_is($HTTP_OK);
    my $anonymous_token = _csrf_token($first);
    $first->post_ok(
        '/login' => form => {
            command_id => _command_id( $first, '/login' ),
            csrf_token => $anonymous_token,
            identifier => 'giacomo_forum',
            password   => 'correct horse battery staple',
        }
    )->status_is($HTTP_FOUND);

    $first->get_ok('/login')->status_is($HTTP_OK);
    my $signed_in_token = _csrf_token($first);
    my $command_id      = _command_id( $first, '/locale' );
    my $logout_id       = _command_id( $first, '/logout' );
    $first->post_ok(
        '/locale' => form => {
            command_id => $command_id,
            csrf_token => $anonymous_token,
            locale     => 'it',
        }
      )
      ->status_is( $HTTP_FORBIDDEN,
        'the token from before sign-in is no longer good' );
    $first->post_ok(
        '/locale' => $SAME_ORIGIN => form => {
            command_id => $command_id,
            locale     => 'it',
        }
      )
      ->status_is( $HTTP_FORBIDDEN,
        'and a signed-in member always needs a token' );

    $first->post_ok(
        '/logout' => form => {
            command_id => $logout_id,
            csrf_token => $signed_in_token,
        }
    )->status_is($HTTP_ACCEPTED);
    $first->element_exists_not( 'form.identity-form',
        'the page after sign-out is a visitor page' );
    $first->post_ok(
        '/locale' => $CROSS_SITE => form => {
            csrf_token => $signed_in_token,
            locale     => 'it',
        }
      )
      ->status_is( $HTTP_FORBIDDEN,
        'the token from before sign-out is no longer good' );
};

done_testing();

sub _client {
    my $client   = Test::Mojo->new('GPForum');
    my $services = GPForum::Test::ForumWebServices->new;
    for my $helper (
        qw(gp_category_reader gp_thread_reader gp_rate_limiter
        gp_suspension_store gp_announcement_store)
      )
    {
        $client->app->helper( $helper => sub { return $services; } );
    }
    my $store = GPForum::Test::IdentityStore->new;
    $client->app->helper( gp_identity_store => sub { return $store; } );
    $client->app->helper(
        gp_command_idempotency => sub {
            return GPForum::Test::CommandIdempotency->new;
        }
    );
    $client->app->helper(
        gp_identity_security_audit => sub {
            return GPForum::Test::IdentitySecurityAudit->new;
        }
    );

    return $client;
}

sub _csrf_token ($client) {
    my ($token) =
      $client->tx->res->body =~ /name="csrf_token" [^>]+ value="([^"]+)"/msx;

    return $token // q{};
}

sub _command_id ( $client, $action ) {
    my $page  = $client->tx->res->dom;
    my $form  = $page->at(qq{form[action="$action"]}) // return q{};
    my $field = $form->at('input[name="command_id"]') // return q{};

    return $field->attr('value');
}

sub _header ( $client, $name ) {
    my $response = $client->tx->res;

    return $response->headers->header($name);
}

1;
