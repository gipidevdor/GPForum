# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;
use lib 'lib', 't/lib';
use Const::Fast;
use Mojo::ByteStream;
use Test::Mojo;
use Test::More;
use GPForum::Test::PostFragmentServices;
use GPForum::Test::CommandIdempotency;
use GPForum::Web::PostFragments;

our $VERSION = '0.001';

const my $OK        => 200;
const my $NOT_FOUND => 404;
const my $FORBIDDEN => 403;

my $test     = Test::Mojo->new('GPForum');
my $services = GPForum::Test::PostFragmentServices->new;
for my $helper (
    qw(gp_category_reader gp_thread_reader gp_thread_detail_reader
    gp_thread_composer gp_thread_store gp_post_reader gp_post_composer
    gp_post_store gp_post_position gp_thread_read_state gp_mention_store
    gp_mention_reader gp_bookmark_store gp_bookmark_folders gp_like_store
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
$routes->get('/__fragment/session/:user')->to(
    cb => sub ($c) {
        $c->session( user_id => $c->param('user') );
        return $c->render( text => 'ready' );
    }
);
my $ticks = 0;
$test->app->helper(
    ui_timestamp => sub {
        return Mojo::ByteStream->new( '<time>fresh-' . ++$ticks . '</time>' );
    }
);

my $controller = $test->app->build_controller;
my $presenter  = $controller->ui_presenter;
my $cache      = $presenter->post_fragments->cache;
$test->get_ok('/__fragment/session/user-1')->status_is($OK);
$test->get_ok('/t/thread-1')->status_is($OK);
my $first   = $test->tx->res->dom;
my $csrf    = $first->at('input[name="csrf_token"]')->attr('value');
my $command = $first->at('form[action="/p/post-1"] input[name="command_id"]')
  ->attr('value');
my $time = $first->at('#post-post-1 time')->text;
my $hits = $cache->stats->{hits};
$test->get_ok('/t/thread-1')->status_is($OK);
ok( $cache->stats->{hits} > $hits, 'the warmed post presentation is reused' );
my $next_page = $test->tx->res->dom;
isnt( $next_page->at('input[name="csrf_token"]')->attr('value'),
    $csrf, 'a cache hit still gets a fresh CSRF mask' );
isnt(
    $next_page->at('form[action="/p/post-1"] input[name="command_id"]')
      ->attr('value'),
    $command, 'a cache hit still gets a fresh command identity'
);
isnt( $next_page->at('#post-post-1 time')->text,
    $time, 'relative timestamps are rendered for the current request' );

my $other = Test::Mojo->new( $test->app );
$other->get_ok('/__fragment/session/user-2')->status_is($OK);
my $before_other = $cache->stats->{hits};
$other->get_ok('/t/thread-1')->status_is($OK);
ok( $cache->stats->{hits} > $before_other,
    'another session reuses the same static post presentation' );
$other->element_exists_not('form[action="/p/post-1"]');
$other->element_exists_not('#post-post-1-edit');
$other->text_is( '#post-post-1 .forum-post-body p' => 'First post' );
my $other_page   = $other->tx->res->dom;
my $other_csrf   = $other_page->at('input[name="csrf_token"]')->attr('value');
my $like_command = 'fragment-session-like';
$other->post_ok(
    '/p/post-1/like' => { Accept => 'application/json' } => form => {
        csrf_token => $csrf,
        command_id => $like_command,
    }
)->status_is($FORBIDDEN);
is( scalar @{ $services->like_calls },
    0, 'a foreign CSRF token cannot execute an otherwise permitted action' );
$other->post_ok(
    '/p/post-1/like' => { Accept => 'application/json' } => form => {
        csrf_token => $other_csrf,
        command_id => $like_command,
    }
)->status_is($OK);
is( $services->like_calls->[0][1]{user_id},
    'user-2', 'the current session token executes the action as that user' );
$other->post_ok(
    '/p/post-1' => form => {
        csrf_token  => $csrf,
        command_id  => $command,
        body_source => 'forbidden edit'
    }
)->status_is($FORBIDDEN);

$services->source('Updated <script>alert(1)</script>');
$services->author('Changed <img src=x onerror=alert(2)>');
$test->get_ok('/t/thread-1')->status_is($OK);
$test->content_unlike(qr{<script>alert[(]1[)]</script>}msx);
$test->element_exists_not('#post-post-1 .post__author img');
$test->text_is(
    '#post-post-1 .forum-post-body p' => 'Updated <script>alert(1)</script>' );
$test->text_is(
    '#post-post-1 .post__author' => 'Changed <img src=x onerror=alert(2)>' );

my $before_denial = $cache->stats->{hits};
$services->allowed(0);
$test->get_ok('/t/thread-1')->status_is($NOT_FOUND);
$test->content_unlike(qr/Updated/msx);
is( $cache->stats->{hits},
    $before_denial,
    'a warm fragment cannot bypass the current visibility decision' );

for my $entry ( values %{ $cache->entries } ) {
    my $parts = $entry->{value};
    my $html  = join q{}, map { "$parts->{$_}" }
      grep { $_ ne 'paths' } keys %{$parts};
    unlike(
        $html,
        qr/<form\b|name="(?:csrf_token|command_id)"/msx,
        'cached presentation contains neither forms nor security tokens'
    );
    unlike( $html, qr/\Q$csrf\E|\Q$command\E/msx,
        'cached presentation contains no session or command credential' );
}

subtest 'locale, mount path and entry size remain isolated' => sub {
    my $fragments = GPForum::Web::PostFragments->new;
    my $post    = { post_id => 'post-1', position => 1, body => '<p>safe</p>' };
    my $english = $test->app->build_controller;
    $english->stash( ui_locale => 'en' );
    my $en      = $fragments->render( $english, $post );
    my $italian = $test->app->build_controller;
    $italian->stash( ui_locale => 'it' );
    my $it = $fragments->render( $italian, $post );
    isnt( "$en->{report}", "$it->{report}",
        'locales do not share translated fields' );
    my $mounted = $test->app->build_controller;
    $mounted->stash( ui_locale => 'en' );
    my $url = $mounted->req->url;
    $url->base->path('/forum/');
    my $prefixed = $fragments->render( $mounted, $post );
    is( $prefixed->{paths}{post_edit},
        '/forum/p/post-1', 'a mounted application gets its own action paths' );
    is( $en->{paths}{post_edit},
        '/p/post-1', 'the unmounted entry stays unchanged' );
    my $bounded  = GPForum::Web::PostFragments->new( max_bytes => 1 );
    my $uncached = $bounded->render( $english, $post );
    like(
        "$uncached->{header}",
        qr{id="post-post-1-heading"}msx,
        'an oversized fragment still renders normally'
    );
    is( $bounded->cache->stats->{writes},
        0, 'an oversized entry consumes no cache capacity' );
};

done_testing();

1;
