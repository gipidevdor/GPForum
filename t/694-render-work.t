# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;
use lib 'lib', 't/lib';
use Const::Fast;
use Test::Mojo;
use Test::More;

use GPForum::Service::I18N::Catalog;
use GPForum::Test::CommandIdempotency;
use GPForum::Test::PostFragmentServices;
use GPForum::Theme::Registry;
use GPForum::Service::I18N::Locale;

our $VERSION = '0.001';

# What a page's render does, counted rather than timed: a clock on a shared
# machine says little, a count says what was done. The signed-in thread page
# is rendered twice and the second render is counted. Each number here is
# work the templates used to repeat: a render of its own for every partial,
# a call for every translation, a composed message for every time and
# count, a theme's palettes and a locale's table rebuilt for every question,
# a session read and a context built for every timestamp.

const my $OK                => 200;
const my $TRANSLATION_CALLS => 16;

my $test     = Test::Mojo->new('GPForum');
my $app      = $test->app;
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
    $app->helper( $helper => sub { return $services; } );
}
$app->helper(
    gp_command_idempotency => sub {
        return GPForum::Test::CommandIdempotency->new;
    }
);
$app->routes->get('/__work/session/:user')->to(
    cb => sub ($c) {
        $c->session( user_id => $c->param('user') );
        return $c->render( text => 'ready' );
    }
);

my %count;
my $translate = $app->renderer->helpers->{t};
$app->helper(
    t => sub (@arguments) {
        ++$count{t};
        return $translate->(@arguments);
    }
);
my $include = $app->renderer->helpers->{include};
$app->helper(
    include => sub (@arguments) {
        ++$count{include};
        return $include->(@arguments);
    }
);
$app->hook( before_render => sub (@) { ++$count{render} } );

$test->get_ok('/__work/session/user-1')->status_is($OK);
$test->get_ok('/t/thread-1')->status_is($OK);
my $page  = $test->tx->res->dom;
my $posts = $page->find('article.post')->size;
ok( $posts, 'the thread page lists posts' );

my $fragments = $app->build_controller->ui_presenter->post_fragments;
my %before    = %{ $fragments->stats };
%count = ();

# The builders counted here are private: that they are not called again is
# what this test is for.
## no critic (Variables::ProtectPrivateVars)
{
    my $interpolate = \&GPForum::Service::I18N::Catalog::interpolate;
    my $contracts   = \&GPForum::Theme::Registry::_built_contracts;
    my $registry    = \&GPForum::Service::I18N::Locale::_built_registry;
    my $context     = \&GPForum::Bootstrap::UI::_time_context;
    local *GPForum::Service::I18N::Catalog::interpolate = sub (@arguments) {
        ++$count{interpolate};
        return $interpolate->(@arguments);
    };
    local *GPForum::Theme::Registry::_built_contracts = sub (@arguments) {
        ++$count{contracts};
        return $contracts->(@arguments);
    };
    local *GPForum::Service::I18N::Locale::_built_registry = sub (@arguments) {
        ++$count{registry};
        return $registry->(@arguments);
    };
    local *GPForum::Bootstrap::UI::_time_context = sub (@arguments) {
        ++$count{time_context};
        return $context->(@arguments);
    };
    $test->get_ok('/t/thread-1')->status_is($OK);
}
## use critic

is( $count{render}, 1,
    'the page is one render: its partials are not renders of their own' );
cmp_ok( $count{include}, '>', $posts, 'while it includes its partials' );

# The page asked t for about 80 messages; the partials now write their plain
# messages from the locale's table. What is left is the page's and the
# layout's own (three), the theme selector's labels (four), a default
# argument and two titles handed to sheets.
cmp_ok( $count{t} // 0,
    '<', $TRANSLATION_CALLS,
    'a partial calls t only for a message it does not write on its own' );
cmp_ok(
    $count{interpolate} // 0,
    '<=',
    $count{t} // 0,
    'and no counted message (a time, a like count) is composed again'
);
is( $count{contracts} // 0, 0, 'no theme rebuilds its palettes' );
is( $count{registry}  // 0, 0, 'no locale rebuilds its table' );
is( $count{time_context}, 1,
    'the times read the reader\'s standing, locale and zone once' );
is( $fragments->stats->{misses},
    $before{misses}, 'no post presentation is rendered again' );
is( $fragments->stats->{hits} - $before{hits},
    $posts, 'each post\'s presentation is one lookup' );

done_testing();

1;
