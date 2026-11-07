# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;
use Test::More;
use Test::Mojo;
use Const::Fast;
use lib 'lib';
use lib 't/lib';
use GPForum::Test::ForumWebServices;
use GPForum::Test::ReplacedSubs qw(with_replaced_subs);
use GPForum::Service::Operations::LocalCache;
use GPForum::Service::Admin::Configuration;

our $VERSION = '0.001';
const my $OK => 200;
const my $LINKS =>
"https://youtu.be/dQw4w9WgXcQ\nhttps://github.com/octocat/repo/issues/42\nhttps://facebook.com/user/posts/123\nhttps://it.m.wikipedia.org/wiki/Alan_Turing#Biografia";

sub forum_test ($enabled) {
    local $ENV{GPFORUM_INTEGRATION_PLUGINS} = $enabled;
    my $test     = Test::Mojo->new('GPForum');
    my $services = GPForum::Test::ForumWebServices->new;
    $test->app->helper(
        gp_configuration => sub ($c) {
            return GPForum::Service::Admin::Configuration->new(
                schema      => {},
                base_config => $c->gp_base_config,
                state       => {
                    available => 1,
                    revision  => 0,
                    settings  => { general => {}, plugins => {} }
                }
            );
        }
    );
    for my $helper (
        qw(gp_category_reader gp_thread_reader gp_thread_detail_reader gp_post_reader gp_thread_read_state gp_attachment_store gp_rate_limiter gp_suspension_store gp_bookmark_store gp_like_store gp_reaction_store gp_reply_links gp_subscription_store)
      )
    {
        $test->app->helper( $helper => sub { return $services; } );
    }
    return $test;
}

my $fixture = GPForum::Test::ForumWebServices->new->thread_page(
    { thread_id => 'thread-1' } );
my $visible = $fixture->{posts}{items}[0];
with_replaced_subs(
    'GPForum::Test::ForumWebServices',
    {
        _visible_thread_post =>
          sub { return { %{$visible}, body_source => $LINKS }; },
    },
    sub {
        my $test  = forum_test('youtube,github,facebook,wikipedia,mathematics');
        my $cache = GPForum::Service::Operations::LocalCache->new;
        $test->app->helper( gp_local_cache => sub { return $cache; } );
        $test->get_ok('/t/thread-1')->status_is($OK);
        $test->element_exists(
'[data-integration-provider="youtube"] button[hidden][data-integration-embed="https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ"]'
        );
        $test->element_exists(
'[data-integration-provider="github"] a[href="https://github.com/octocat/repo/issues/42"]'
        );
        $test->element_exists(
'[data-integration-provider="facebook"] a[href="https://www.facebook.com/user/posts/123"]'
        );
        $test->element_exists_not('iframe');
        $test->element_exists(
'[data-integration-provider="wikipedia"] a[href="https://it.wikipedia.org/wiki/Alan_Turing#Biografia"]'
        );
        $test->text_like( '[data-integration-provider="wikipedia"] a',
            qr/Alan[ ]Turing[ ][(]IT[)]/msx );
        $test->element_exists_not('script[src^="https://"]');
        $test->element_exists_not('img[src^="https://"]');
        $test->header_like( 'Content-Security-Policy' =>
              qr/frame-src[ ]'self'[ ]https:\/\/www[.]youtube-nocookie[.]com/msx
        );
        $test->element_exists(
'script[src^="/page-enhancements.js?v="][data-integrations^="/integrations.js?v="]'
        );

        # A new process with a narrower configuration must not reuse cards from
        # source or page caches created with the old configuration.
        my $disabled = forum_test('none');
        $disabled->app->helper( gp_local_cache => sub { return $cache; } );
        $disabled->get_ok('/t/thread-1')->status_is($OK);
        $disabled->element_exists_not('.integration-card');
        $disabled->content_like(qr{https://youtu[.]be/dQw4w9WgXcQ}msx);
        $disabled->header_unlike( 'Content-Security-Policy' => qr/youtube/msx );

        my $routes = $test->app->routes;
        $routes->get('/__test/integration-session')->to(
            cb => sub ($c) {
                $c->session( user_id => 'user-1' );
                return $c->render( text => 'ok' );
            }
        );
        $test->get_ok('/__test/integration-session')->status_is($OK);
        $test->get_ok('/new-thread')->status_is($OK);
        my $dom   = $test->tx->res->dom;
        my $form  = $dom->at('form[data-composer]');
        my %input = map { $_->attr('name') => $_->attr('value') }
          @{ $form->find('input[name]')->to_array };
        $input{body_source} = $LINKS . "\n\n" . q{Equation $x_i^2$};
        $test->post_ok(
            '/composer/preview' => { Accept => 'application/json' } => form =>
              \%input )->status_is($OK);
        $test->json_is( '/ok' => 1 );
        my $preview = $test->tx->res->json;
        like(
            $preview->{html},
            qr/data-integration-provider="youtube"/msx,
            'composer preview uses the same plugin contract'
        );
        unlike( $preview->{html}, qr/<iframe|<script/msx,
            'preview makes no external content request' );
        like(
            $preview->{html},
            qr/data-integration-provider="wikipedia"/msx,
            'Wikipedia also appears in composer preview'
        );
        like( $preview->{html}, qr/class="math-expression"/msx,
            'composer preview prepares equations through the same math contract'
        );
    }
);

done_testing();

1;
