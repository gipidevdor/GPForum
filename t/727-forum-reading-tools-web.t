# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package main;
use v5.40;
use Const::Fast;
use Test::Mojo;
use Test::More;
use lib 'lib';
use lib 't/lib';
use GPForum::Test::ForumWebServices;
our $VERSION = '0.001';
const my $HTTP_OK => 200;
my $test     = Test::Mojo->new('GPForum');
my $services = GPForum::Test::ForumWebServices->new;

for my $helper (
    qw(gp_category_reader gp_thread_reader gp_thread_detail_reader
    gp_post_reader gp_thread_read_state gp_bookmark_store gp_bookmark_folders
    gp_like_store gp_reaction_store gp_reply_links gp_thread_tags
    gp_subscription_store gp_rate_limiter gp_suspension_store gp_attachment_store)
  )
{
    $test->app->helper( $helper => sub { return $services; } );
}
$test->get_ok('/t/thread-1?after=page-cursor')->status_is($HTTP_OK);
$test->element_exists(
'script[src^="/page-enhancements.js?v="][defer][data-thread-actions^="/thread-actions.js?v="][data-thread-navigation^="/thread-navigation.js?v="]'
);
my $page = $test->tx->res->dom;
is(
    $page->at('.post')->attr('data-page-url'),
    '/t/thread-1?after=page-cursor',
    'post carries its source page URL for copied links'
);
my $asset =
  $page->at('script[data-thread-actions]')->attr('data-thread-actions');
$test->get_ok($asset)->status_is($HTTP_OK);
$test->content_like(qr/Quote[ ]selection/msx);
$test->get_ok( '/t/thread-1?after=next-cursor' => { 'HX-Request' => 'true' } )
  ->status_is($HTTP_OK);
$page = $test->tx->res->dom;
is( $page->at('.post')->attr('data-page-url'), '/t/thread-1?after=next-cursor',
    'appended posts carry their own cursor instead of the initial page cursor'
);
done_testing;
1;
