# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;
use lib 'lib', 't/lib';
use Const::Fast;
use Test::Mojo;
use Test::More;
use GPForum::Test::CommandIdempotency;
use GPForum::Test::PostFragmentServices;

our $VERSION = '0.001';
const my $OK        => 200;
const my $FOUND     => 302;
const my $FORBIDDEN => 403;
const my $REACTIONS => 4;

my $test     = Test::Mojo->new('GPForum');
my $services = GPForum::Test::PostFragmentServices->new;
for my $helper (
    qw(gp_category_reader gp_thread_reader gp_thread_detail_reader
    gp_thread_composer gp_thread_store gp_post_reader gp_post_composer
    gp_post_store gp_thread_read_state gp_mention_store gp_mention_reader
    gp_bookmark_store gp_bookmark_folders gp_like_store gp_reaction_store
    gp_reply_links gp_thread_tags gp_subscription_store gp_notification_dispatcher
    gp_search_service gp_rate_limiter gp_suspension_store gp_attachment_store)
  )
{
    $test->app->helper( $helper => sub { return $services; } );
}
$test->app->helper(
    gp_command_idempotency => sub {
        return GPForum::Test::CommandIdempotency->new;
    }
);
my $routes = $test->app->routes;
$routes->get('/__reaction/session/:user')->to(
    cb => sub ($c) {
        $c->session( user_id => $c->param('user') );
        return $c->render( text => 'ready' );
    }
);

$test->get_ok('/t/thread-1')->status_is($OK);
$test->element_exists_not('.post__reactions form');
$test->get_ok('/__reaction/session/user-1')->status_is($OK);
$test->get_ok('/t/thread-1')->status_is($OK);
$test->element_exists_not('#post-post-1 .post__reactions form');

$test->get_ok('/__reaction/session/user-2')->status_is($OK);
$test->get_ok('/t/thread-1')->status_is($OK);
my $dom   = $test->tx->res->dom;
my $group = $dom->at('#post-post-1 .post__reactions');
is( $group->find('form')->size, 1, 'four reactions share one form' );
$test->element_exists('#post-post-1 details.post-reaction-picker:not([open])');
my $form = $group->at('form');
is( $form->attr('method'), 'post', 'native submission remains POST' );
is( $form->attr('hx-boost'),
    'true', 'enhancement respects the selected reaction submitter action' );
is( $form->find('input[name="csrf_token"]')->size,
    1, 'one CSRF field covers the form' );
is( $form->find('input[name="command_id"]')->size,
    0, 'only the selected submitter sends a command' );
my @buttons = $form->find('button[name="command_id"]')->each;
is( scalar @buttons, $REACTIONS, 'every reaction has a submitter' );
my %commands;

for my $button (@buttons) {
    ok( length $button->attr('value'),
        'the submitter carries its own command identity' );
    $commands{ $button->attr('value') }++;
}
is( scalar keys %commands,
    $REACTIONS, 'different reactions never share a command identity' );
like( $buttons[0]->attr('formaction'),
    qr{/heart/remove\z}msx, 'pressed reaction removes' );
like( $buttons[1]->attr('formaction'),
    qr{/laugh\z}msx, 'unpressed reaction adds' );

my $csrf = $form->at('input[name="csrf_token"]')->attr('value');
for my $button (@buttons) {
    my $route = $button->attr('formaction');
    $test->post_ok(
        $route => { 'HX-Request' => 'true' } => form => {
            csrf_token => $csrf,
            command_id => $button->attr('value'),
        }
    )->status_is($OK);
    $test->element_exists('article.post#post-post-1');
    $test->element_exists('#flash[hx-swap-oob="true"]');
}
is( scalar @{ $services->reaction_calls },
    $REACTIONS, 'all four selected actions reach the workflow' );

$test->post_ok(
    $buttons[1]->attr('formaction') => form => {
        csrf_token => $csrf,
        command_id => 'native-reaction',
    }
)->status_is($FOUND);
my $calls = scalar @{ $services->reaction_calls };
$test->post_ok(
    $buttons[1]->attr('formaction') => form => {
        csrf_token => 'invalid',
        command_id => 'invalid-csrf-reaction',
    }
)->status_is($FORBIDDEN);
is( scalar @{ $services->reaction_calls },
    $calls, 'invalid CSRF cannot execute the action' );

$test->get_ok('/t/thread-1')->status_is($OK);
my $next_page = $test->tx->res->dom;
my $next      = $next_page->at('#post-post-1 .post__reactions form');
isnt( $next->at('input[name="csrf_token"]')->attr('value'),
    $csrf, 'next response gets a fresh CSRF mask' );
for my $button ( $next->find('button[name="command_id"]')->each ) {
    ok(
        !exists $commands{ $button->attr('value') },
        'next response gets fresh command identities'
    );
}

done_testing();

1;
