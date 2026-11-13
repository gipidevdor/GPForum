# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;
use lib 'lib', 't/lib';
use Const::Fast;
use Test::Mojo;
use Test::More;
use GPForum::Test::ReplacedSubs qw(with_replaced_subs);
use GPForum::Test::CommunityFunctions;
use GPForum::Test::CommandIdempotency;
use GPForum::Test::PostFragmentServices;

our $VERSION = '0.001';
const my $OK => 200;

my $test     = Test::Mojo->new('GPForum');
my $services = GPForum::Test::PostFragmentServices->new;
for my $helper (
    qw(gp_category_reader gp_thread_reader gp_thread_detail_reader
    gp_thread_composer gp_thread_store gp_post_reader gp_post_composer
    gp_post_store gp_thread_read_state gp_mention_store gp_mention_reader
    gp_bookmark_store gp_bookmark_folders gp_like_store gp_reaction_store
    gp_reply_links gp_thread_tags gp_subscription_store gp_notification_dispatcher gp_report_store
    gp_search_service gp_rate_limiter gp_suspension_store gp_attachment_store)
  )
{
    $test->app->helper( $helper => sub { return $services; } );
}
GPForum::Test::CommunityFunctions->install( $test->app, sink => $services );
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

sub assert_degraded_toolbar($client) {
    $client->element_exists('#thread-toolbar .ui-alert[role="status"]');
    $client->element_exists_not(
        '#thread-toolbar form[action="/t/thread-1/bookmark"]');
    $client->element_exists_not(
        '#thread-toolbar form[action="/t/thread-1/bookmark/remove"]');
    $client->element_exists_not(
        '#thread-toolbar form[action^="/t/thread-1/subscribe"]');
    $client->element_exists(
        '#thread-toolbar form[action="/t/thread-1/report"]');
    my $response = $client->tx->res;
    my $dom      = $response->dom;
    my @commands =
      $dom->find('[name="command_id"]')->map( sub { $_->attr('value') } )->each;
    my %seen;
    my @invalid = grep { !defined $_ || !length $_ || $seen{$_}++ } @commands;
    is_deeply( \@invalid, [],
        'every rendered action has a nonempty distinct command' );
    return;
}

$test->get_ok('/__reaction/session/user-2')->status_is($OK);
with_replaced_subs(
    'GPForum::ViewModel::Forum::Page',
    {
        _engagement_lookup => sub { die "read failed\n"; },
    },
    sub {
        $test->get_ok('/t/thread-1')->status_is($OK);
        assert_degraded_toolbar($test);
        my $dom  = $test->tx->res->dom;
        my $csrf = $dom->at('input[name="csrf_token"]')->attr('value');
        my $report =
          $dom->at('form[action="/t/thread-1/report"] input[name="command_id"]')
          ->attr('value');
        $test->element_exists('form[action="/t/thread-1/replies"]');
        $test->element_exists('form[action="/p/post-1/like/remove"]');
        $test->post_ok(
            '/t/thread-1/report' => { Accept => 'application/json' } => form =>
              {
                csrf_token => $csrf,
                command_id => $report,
                reason     => 'spam',
                details    => 'Report during read failure',
              }
        )->status_is($OK)->json_is( '/status' => 'reported' );
        $test->get_ok( '/t/thread-1' => { Accept => 'application/json' } )
          ->status_is($OK);
        $test->json_is( '/engagement/status'               => 'degraded' );
        $test->json_is( '/engagement/subscribe_command_id' => q{} );
        my $payload = $test->tx->res->json;
        ok(
            length $payload->{engagement}{thread_report_command_id},
            'JSON retains its independent report command'
        );
        $test->post_ok(
            '/t/thread-1/subscribe' => { 'HX-Request' => 'true' } => form => {
                csrf_token => $csrf,
                command_id => 'already-issued-subscribe',
                preference => 'all',
            }
        )->status_is($OK);
        assert_degraded_toolbar($test);
        $test->element_exists_not('html');
    }
);
$test->get_ok('/t/thread-1')->status_is($OK);
$test->element_exists_not('#thread-toolbar .ui-alert');
$test->element_exists('#thread-toolbar form[action="/t/thread-1/subscribe"]');
$test->element_exists('#thread-toolbar form[action="/t/thread-1/bookmark"]');

done_testing();
1;
