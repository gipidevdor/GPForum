# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use Test::Mojo;
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Infrastructure::Id;
use GPForum::Test::CommandIdempotency;
use GPForum::Test::ForumWebServices;

our $VERSION = '0.001';

const my $HTTP_OK          => 200;
const my $HTTP_FOUND       => 302;
const my $HTTP_BAD_REQUEST => 400;
const my $REPORT_FORM => '#post-post-1-report form[action="/p/post-1/report"]';

# Every post on a thread page offers a signed-in reader a report form, and
# the community workflow refuses a report without a command id. The ids
# used to be minted for the reader's own posts alone, so the form under
# every other member's post -- the ones a reader reports -- sent an empty
# command id and was answered 400, "command_id is required".
my $test = Test::Mojo->new('GPForum');
_install_forum_fakes($test);
_install_session_route($test);

# user-2 is not the author of post-1 (user-1 is).
$test->get_ok('/__test/session/user-2');
$test->get_ok('/t/thread-1')->status_is($HTTP_OK);
my $page = $test->tx->res->dom;
my $form = $page->at($REPORT_FORM);
ok( $form, 'another member\'s post has a report form' );
my $command_id = $form->at('input[name="command_id"]')->attr('value');
ok( GPForum::Infrastructure::Id->is_uuid($command_id),
    'with a command id of its own' )
  or diag( 'command_id: ' . ( $command_id // 'undef' ) );
my $csrf = $form->at('input[name="csrf_token"]')->attr('value');

# The form, sent as the page wrote it, reports the post.
$test->post_ok(
    '/p/post-1/report' => form => {
        command_id => $command_id,
        csrf_token => $csrf,
        reason     => 'spam',
        details    => 'Repeated links',
    }
)->status_is( $HTTP_FOUND, 'the report is taken' );
my $headers = $test->tx->res->headers;
like( $headers->location,
    qr{/t/thread-1}msx, 'and the reader is sent back to the thread' );

# Which is what an empty command id was refused as.
$test->post_ok(
    '/p/post-1/report' => form => {
        command_id => q{},
        csrf_token => $csrf,
        reason     => 'spam',
        details    => 'Repeated links',
    }
)->status_is( $HTTP_BAD_REQUEST, 'a report without a command id is refused' );

# The author's own posts keep theirs, and each post's id is its own.
$test->get_ok('/__test/session/user-1');
$test->get_ok('/t/thread-1')->status_is($HTTP_OK);
my $author_page = $test->tx->res->dom;
my @ids =
  $author_page->find('form[action$="/report"] input[name="command_id"]')
  ->map( attr => 'value' )
  ->each;
ok( @ids > 1, 'more than one report form on the page' );
is( scalar( grep { GPForum::Infrastructure::Id->is_uuid($_) } @ids ),
    scalar(@ids), 'every report form carries a command id' );
my %seen;

for my $id (@ids) {
    $seen{$id}++;
}
is( scalar( keys %seen ), scalar(@ids), 'no two forms share one' );

done_testing();

sub _install_forum_fakes {
    my ($test_object) = @_;

    my $services = GPForum::Test::ForumWebServices->new;
    for my $helper (
        qw(
        gp_category_reader gp_thread_reader gp_thread_detail_reader
        gp_post_reader gp_thread_read_state gp_mention_store
        gp_mention_reader gp_bookmark_store gp_bookmark_folders gp_like_store
        gp_reaction_store gp_reply_links gp_thread_tags gp_subscription_store
        gp_notification_dispatcher gp_report_store gp_search_service
        gp_rate_limiter gp_suspension_store gp_attachment_store
        )
      )
    {
        $test_object->app->helper( $helper => sub { return $services; } );
    }
    $test_object->app->helper(
        gp_command_idempotency => sub {
            return GPForum::Test::CommandIdempotency->new;
        }
    );

    return;
}

sub _install_session_route {
    my ($test_object) = @_;

    my $routes = $test_object->app->routes;
    $routes->get('/__test/session/:user_id')->to(
        cb => sub {
            my ($controller) = @_;

            $controller->session( user_id => $controller->param('user_id') );
            return $controller->render( json => { ok => 1 } );
        }
    );

    return;
}

1;
