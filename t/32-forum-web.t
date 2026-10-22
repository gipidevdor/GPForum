# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use Const::Fast;
use Mojo::Base -base;
use v5.40;
use Test::Mojo;
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Test::DenyLimiter;
use GPForum::Test::CommandIdempotency;
use GPForum::Test::FailReadiness;
use GPForum::Test::ForumWebServices;
use GPForum::Test::SuspendedParticipation;

our $VERSION = '0.001';

const my $EXPECTED_TESTS       => 307;
const my $HTTP_OK              => 200;
const my $HTTP_CREATED         => 201;
const my $HTTP_BAD_REQUEST     => 400;
const my $HTTP_UNAUTHORIZED    => 401;
const my $HTTP_FORBIDDEN       => 403;
const my $HTTP_CONFLICT        => 409;
const my $HTTP_NOT_FOUND       => 404;
const my $HTTP_TOO_MANY        => 429;
const my $HTTP_NOT_MODIFIED    => 304;
const my $HTTP_SERVICE_UNAVAIL => 503;

plan tests => $EXPECTED_TESTS;

my $test  = Test::Mojo->new('GPForum');
my $fakes = _install_forum_fakes($test);
_install_test_session_route($test);

_get_json_ok( $test, '/categories' );
$test->status_is($HTTP_OK);
$test->json_is( '/categories/0/category_id' => 'category-1' );

$test->get_ok('/categories');
$test->status_is($HTTP_OK);
$test->header_like( 'Cache-Control' => qr/\bpublic\b/msx );
$test->header_like( 'ETag'          => qr/\A W\/"[[:xdigit:]]{40}" \z/msx );
$test->header_like( 'Last-Modified' => qr/\b GMT \z/msx );
$test->header_is( 'X-GPForum-Cache' => 'miss' );
my $cache_response_tx      = $test->tx;
my $public_categories_etag = $cache_response_tx->res->headers->header('ETag');
$test->get_ok(
    '/categories' => { 'If-None-Match' => $public_categories_etag } );
$test->status_is($HTTP_NOT_MODIFIED);
$test->header_is( 'X-GPForum-Cache' => 'revalidated' );
$test->content_is(q{});

$test->get_ok('/robots.txt');
$test->status_is($HTTP_OK);
$test->content_like(qr/User-agent: [ ] [*]/msx);
$test->content_like(qr/Disallow: [ ] \/search/msx);

$test->get_ok('/sitemap.xml');
$test->status_is($HTTP_OK);
$test->content_like(qr/<urlset/msx);
$test->content_like(qr/\/t\/thread-1\/welcome/msx);
$test->content_like(qr/\/legal\/terms/msx);

$test->get_ok('/feed.atom');
$test->status_is($HTTP_OK);
$test->content_like(
    qr/<feed [^>]+ xmlns="http:\/\/www[.]w3[.]org\/2005\/Atom"/msx);
$test->content_like(qr/First [ ] public [ ] post/msx);
$test->content_unlike(qr/private [ ] text [ ] must [ ] not [ ] leak/msx);

_get_json_ok( $test, '/c/category-1' );
$test->status_is($HTTP_OK);
$test->json_is( '/category/category_id'      => 'category-1' );
$test->json_is( '/threads/0/thread_id'       => 'thread-1' );
$test->json_is( '/threads/0/author_username' => 'giacomo_forum' );
$test->json_is( '/next_cursor'               => 'thread-cursor' );

_get_json_ok( $test, '/c/missing' );
$test->status_is($HTTP_NOT_FOUND);

_get_json_ok( $test, '/t/thread-1' );
$test->status_is($HTTP_OK);
$test->json_is( '/thread/thread_id'        => 'thread-1' );
$test->json_is( '/thread/author_username'  => 'giacomo_forum' );
$test->json_is( '/posts/0/body'            => '<p>First post</p>' );
$test->json_is( '/posts/0/author_username' => 'giacomo_forum' );
$test->json_is( '/next_cursor'             => 'post-cursor' );

_get_json_ok( $test, '/t/missing' );
$test->status_is($HTTP_NOT_FOUND);

_get_json_ok( $test, '/new-thread' );
$test->status_is($HTTP_OK);
$test->json_is( '/fields/0' => 'category_id' );

my $csrf_token = _json_value( $test, 'csrf_token' );

_get_json_ok( $test, '/bookmarks' );
$test->status_is($HTTP_UNAUTHORIZED);
_get_json_ok( $test, '/feed' );
$test->status_is($HTTP_UNAUTHORIZED);
_get_json_ok( $test, '/notifications' );
$test->status_is($HTTP_UNAUTHORIZED);
_get_json_ok( $test, '/mentions' );
$test->status_is($HTTP_UNAUTHORIZED);

$test->post_ok('/threads');
$test->status_is($HTTP_FORBIDDEN);
$test->post_ok('/t/thread-1/report');
$test->status_is($HTTP_FORBIDDEN);

$test->post_ok(
    '/threads' => form => {
        csrf_token  => $csrf_token,
        category_id => 'category-1',
        title       => 'A real thread',
        body_source => 'Opening post',
        visibility  => 'public',
    }
);
$test->status_is($HTTP_UNAUTHORIZED);

$test->get_ok('/__test/session/user-1');
$test->status_is($HTTP_OK);
_get_json_ok( $test, '/t/thread-1' );
$test->status_is($HTTP_OK);
$test->json_is( '/posts/0/can_edit'         => 1 );
$test->json_is( '/posts/0/can_delete'       => 1 );
$test->json_is( '/thread/can_edit_thread'   => 1 );
$test->json_is( '/thread/can_delete_thread' => 1 );
$test->json_is( '/thread/can_move_thread'   => 1 );
$test->json_is( '/posts/0/like_count'       => 2 );
$test->json_is( '/posts/0/can_like'         => 0 );
$test->json_is( '/thread/tags/0/slug'       => 'perl' );
_get_json_ok( $test, '/new-thread' );
my $session_csrf = _json_value( $test, 'csrf_token' );

$test->post_ok(
    '/threads' => { Accept => 'application/json' } => form => {
        csrf_token  => $session_csrf,
        category_id => 'category-1',
        title       => 'A real thread',
        body_source => 'Opening post',
        visibility  => 'public',
    }
);
$test->status_is($HTTP_BAD_REQUEST);
$test->json_is( '/errors/command_id' => 'command_id is required' );

$test->post_ok(
    '/t/thread-1/replies' => { Accept => 'application/json' } => form => {
        csrf_token  => $session_csrf,
        body_source => 'A reply',
        visibility  => 'public',
    }
);
$test->status_is($HTTP_BAD_REQUEST);
$test->json_is( '/errors/command_id' => 'command_id is required' );

$test->post_ok(
    '/threads' => { Accept => 'application/json' } => form => {
        csrf_token  => $session_csrf,
        category_id => 'category-1',
        command_id  => 'thread-command-1',
        tags        => 'Perl, PostgreSQL',
        title       => 'A real thread',
        body_source => 'Opening post',
        visibility  => 'public',
    }
);
$test->status_is($HTTP_CREATED);
$test->json_is( '/thread_id' => 'thread-created' );
is_deeply(
    $fakes->thread_tag_sets->[-1],
    [ 'thread-created', 'Perl, PostgreSQL' ],
    'the tags named with a new thread are set once it is made (ADR 0135)'
);

$test->post_ok(
    '/t/thread-1/replies' => { Accept => 'application/json' } => form => {
        csrf_token  => $session_csrf,
        body_source => 'A reply',
        command_id  => 'reply-command-1',
        visibility  => 'public',
    }
);
$test->status_is($HTTP_CREATED);
$test->json_is( '/post_id' => 'post-created' );

# A reply that answers a post is linked to it once made (ADR 0132).
$test->post_ok(
    '/t/thread-1/replies' => { Accept => 'application/json' } => form => {
        csrf_token       => $session_csrf,
        body_source      => 'An answer',
        command_id       => 'reply-command-2',
        reply_to_post_id => 'post-1',
        visibility       => 'public',
    }
);
$test->status_is($HTTP_CREATED);
is_deeply(
    $fakes->reply_links->[-1],
    [ 'post-created', 'post-1' ],
    'the reply is linked to the post it answers'
);

$test->post_ok(
    '/p/post-1' => { Accept => 'application/json' } => form => {
        csrf_token  => $session_csrf,
        body_source => 'Edited post',
    }
);
$test->status_is($HTTP_BAD_REQUEST);
$test->json_is( '/errors/command_id' => 'command_id is required' );

$test->post_ok(
    '/p/post-1' => { Accept => 'application/json' } => form => {
        csrf_token  => $session_csrf,
        body_source => 'Edited post',
        command_id  => 'edit-command-1',
    }
);
$test->status_is($HTTP_OK);
$test->json_is( '/post_id' => 'post-1' );
$test->json_is( '/status'  => 'updated' );

$test->post_ok(
    '/p/post-1/delete' => { Accept => 'application/json' } => form => {
        csrf_token => $session_csrf,
    }
);
$test->status_is($HTTP_BAD_REQUEST);
$test->json_is( '/errors/command_id' => 'command_id is required' );

$test->post_ok(
    '/p/post-1/delete' => { Accept => 'application/json' } => form => {
        csrf_token => $session_csrf,
        command_id => 'delete-command-1',
    }
);
$test->status_is($HTTP_OK);
$test->json_is( '/post_id'   => 'post-1' );
$test->json_is( '/status'    => 'deleted' );
$test->json_is( '/thread_id' => 'thread-1' );

$test->post_ok(
    '/p/post-deleted-1/restore' => { Accept => 'application/json' } => form => {
        csrf_token => $session_csrf,
    }
);
$test->status_is($HTTP_BAD_REQUEST);
$test->json_is( '/errors/command_id' => 'command_id is required' );

$test->post_ok(
    '/p/post-deleted-1/restore' => { Accept => 'application/json' } => form => {
        csrf_token => $session_csrf,
        command_id => 'restore-command-1',
    }
);
$test->status_is($HTTP_OK);
$test->json_is( '/post_id'   => 'post-deleted-1' );
$test->json_is( '/status'    => 'restored' );
$test->json_is( '/thread_id' => 'thread-1' );

$test->post_ok(
    '/t/thread-1/edit' => { Accept => 'application/json' } => form => {
        csrf_token => $session_csrf,
        title      => 'Edited Welcome',
    }
);
$test->status_is($HTTP_BAD_REQUEST);
$test->json_is( '/errors/command_id' => 'command_id is required' );

$test->post_ok(
    '/t/thread-1/edit' => { Accept => 'application/json' } => form => {
        csrf_token => $session_csrf,
        command_id => 'thread-edit-command-1',
        tags       => 'perl, web',
        title      => 'Edited Welcome',
    }
);
$test->status_is($HTTP_OK);
$test->json_is( '/thread_id' => 'thread-1' );
$test->json_is( '/status'    => 'updated' );
$test->json_is( '/title'     => 'Edited Welcome' );
is_deeply(
    $fakes->thread_tag_sets->[-1],
    [ 'thread-1', 'perl, web' ],
    'the tags sent with the title are set once it is saved'
);

$test->post_ok(
    '/t/thread-1/move' => { Accept => 'application/json' } => form => {
        csrf_token  => $session_csrf,
        category_id => 'category-2',
    }
);
$test->status_is($HTTP_BAD_REQUEST);
$test->json_is( '/errors/command_id' => 'command_id is required' );

$test->post_ok(
    '/t/thread-1/move' => { Accept => 'application/json' } => form => {
        csrf_token  => $session_csrf,
        category_id => 'category-2',
        command_id  => 'thread-move-command-1',
    }
);
$test->status_is($HTTP_OK);
$test->json_is( '/thread_id'   => 'thread-1' );
$test->json_is( '/status'      => 'moved' );
$test->json_is( '/category_id' => 'category-2' );

$test->post_ok(
    '/t/thread-1/delete' => { Accept => 'application/json' } => form => {
        csrf_token => $session_csrf,
        title      => 'ignored',
    }
);
$test->status_is($HTTP_BAD_REQUEST);
$test->json_is( '/errors/command_id' => 'command_id is required' );

$test->post_ok(
    '/t/thread-1/delete' => { Accept => 'application/json' } => form => {
        csrf_token => $session_csrf,
        command_id => 'thread-delete-command-1',
    }
);
$test->status_is($HTTP_OK);
$test->json_is( '/thread_id' => 'thread-1' );
$test->json_is( '/status'    => 'deleted' );

$test->post_ok(
    '/t/thread-deleted-1/restore' => { Accept => 'application/json' } =>
      form => {
        csrf_token => $session_csrf,
      }
);
$test->status_is($HTTP_BAD_REQUEST);
$test->json_is( '/errors/command_id' => 'command_id is required' );

$test->post_ok(
    '/t/thread-deleted-1/restore' => { Accept => 'application/json' } =>
      form => {
        csrf_token => $session_csrf,
        command_id => 'thread-restore-command-1',
      }
);
$test->status_is($HTTP_OK);
$test->json_is( '/thread_id' => 'thread-deleted-1' );
$test->json_is( '/status'    => 'restored' );

$test->app->helper(
    gp_command_idempotency => sub {
        return GPForum::Test::CommandIdempotency->new(
            replay_response => {
                ok        => 1,
                post_id   => 'post-original',
                status    => 'ok',
                thread_id => 'thread-original',
            }
        );
    }
);
$test->post_ok(
    '/threads' => { Accept => 'application/json' } => form => {
        csrf_token  => $session_csrf,
        category_id => 'category-1',
        command_id  => 'thread-command-2',
        title       => 'A real thread',
        body_source => 'Opening post',
        visibility  => 'public',
    }
);
$test->status_is($HTTP_CREATED);
$test->json_is( '/thread_id' => 'thread-original' );

$test->post_ok(
    '/t/thread-1/replies' => { Accept => 'application/json' } => form => {
        csrf_token  => $session_csrf,
        body_source => 'A reply',
        command_id  => 'reply-command-2',
        visibility  => 'public',
    }
);
$test->status_is($HTTP_CREATED);
$test->json_is( '/post_id' => 'post-original' );

$test->app->helper(
    gp_command_idempotency => sub {
        return GPForum::Test::CommandIdempotency->new( conflict => 1 );
    }
);
$test->post_ok(
    '/threads' => { Accept => 'application/json' } => form => {
        csrf_token  => $session_csrf,
        category_id => 'category-1',
        command_id  => 'thread-command-3',
        title       => 'Different thread',
        body_source => 'Different body',
        visibility  => 'public',
    }
);
$test->status_is($HTTP_CONFLICT);
$test->json_is( '/status' => 'conflict' );

$test->app->helper(
    gp_command_idempotency => sub {
        return GPForum::Test::CommandIdempotency->new;
    }
);

$test->app->helper(
    gp_suspension_store => sub {
        return GPForum::Test::SuspendedParticipation->new;
    }
);
$test->post_ok(
    '/threads' => { Accept => 'application/json' } => form => {
        csrf_token  => $session_csrf,
        category_id => 'category-1',
        title       => 'Suspended thread',
        body_source => 'Blocked post',
        visibility  => 'public',
    }
);
$test->status_is($HTTP_FORBIDDEN);
$test->app->helper(
    gp_suspension_store => sub {
        return GPForum::Test::ForumWebServices->new;
    }
);

$test->post_ok(
    '/t/thread-1/read' => { Accept => 'application/json' } => form => {
        csrf_token         => $session_csrf,
        last_read_position => 1,
    }
);
$test->status_is($HTTP_BAD_REQUEST);
$test->json_is( '/errors/command_id' => 'command_id is required' );

$test->post_ok(
    '/t/thread-1/read' => { Accept => 'application/json' } => form => {
        command_id         => 'read-command-1',
        csrf_token         => $session_csrf,
        last_read_position => 1,
    }
);
$test->status_is($HTTP_OK);
$test->json_is( '/read_state/last_read_position' => 1 );

_get_json_ok( $test, '/bookmarks' );
$test->status_is($HTTP_OK);
$test->json_is( '/bookmarks/0/target_id' => 'thread-1' );
$test->json_is( '/next_cursor'           => 'bookmark-cursor' );

_get_json_ok( $test, '/feed' );
$test->status_is($HTTP_OK);
$test->json_is( '/feed_items/0/item_id' => 'thread-1' );
$test->json_is( '/next_cursor'          => 'feed-cursor' );

_get_json_ok( $test, '/notifications' );
$test->status_is($HTTP_OK);
$test->json_is( '/notifications/0/notification_id'    => 'notification-1' );
$test->json_is( '/notifications/0/notification_type'  => 'mention' );
$test->json_is( '/notifications/0/payload/thread_id'  => 'thread-1' );
$test->json_is( '/notifications/0/presentation/title' => 'You were mentioned' );
$test->json_is( '/notifications/0/presentation/email/subject' =>
      'You were mentioned on GPForum' );
$test->json_is( '/next_cursor'  => 'notification-cursor' );
$test->json_is( '/unread_count' => 1 );

_get_json_ok( $test, '/mentions' );
$test->status_is($HTTP_OK);
$test->json_is( '/mentions/0/mention_id'            => 'mention-1' );
$test->json_is( '/mentions/0/actor_username'        => 'reply_author' );
$test->json_is( '/mentions/0/presentation/by_label' => 'Mention by' );
$test->json_is( '/next_cursor'                      => 'mention-cursor' );

$test->post_ok(
    '/notifications/notification-1/read' => { Accept => 'application/json' } =>
      form => {
        csrf_token => $session_csrf,
      }
);
$test->status_is($HTTP_OK);
$test->json_is( '/status'               => 'read' );
$test->json_is( '/read/notification_id' => 'notification-1' );
$test->json_is( '/unread_count'         => 0 );

$test->post_ok(
    '/notifications/read-all' => { Accept => 'application/json' } => form => {
        csrf_token => $session_csrf,
    }
);
$test->status_is($HTTP_OK);
$test->json_is( '/status'       => 'all_read' );
$test->json_is( '/marked_count' => 1 );
$test->json_is( '/unread_count' => 0 );

$test->post_ok(
    '/notifications/missing/read' => { Accept => 'application/json' } =>
      form => {
        csrf_token => $session_csrf,
      }
);
$test->status_is($HTTP_NOT_FOUND);
$test->json_is( '/status' => 'not_found' );

$test->post_ok(
    '/t/thread-1/bookmark' => { Accept => 'application/json' } => form => {
        command_id => 'bookmark-1',
        csrf_token => $session_csrf,
        folder     => 'Later',
        note       => 'Read later',
    }
);
$test->status_is($HTTP_OK);
$test->json_is( '/status'             => 'bookmarked' );
$test->json_is( '/bookmark/target_id' => 'thread-1' );
is_deeply(
    $fakes->bookmark_files->[-1],
    [ 'bookmark-1', 'user-1', 'Later' ],
    'the folder named with the save files the bookmark once stored (ADR 0136)'
);
_get_json_ok( $test, '/bookmarks?folder=Later' );
$test->status_is($HTTP_OK);
$test->json_is( '/folder'             => 'Later' );
$test->json_is( '/folders/0/folder'   => 'Later' );
$test->json_is( '/bookmarks/0/folder' => 'Later' );
$test->post_ok(
    '/bookmarks/bookmark-1/folder' => { Accept => 'application/json' } =>
      form => {
        csrf_token => $session_csrf,
        folder     => 'Perl',
      }
);
$test->status_is($HTTP_OK);
$test->json_is( '/status'          => 'bookmark_filed' );
$test->json_is( '/bookmark/folder' => 'Perl' );
$test->post_ok(
    '/bookmarks/bookmark-9/folder' => { Accept => 'application/json' } =>
      form => {
        csrf_token => $session_csrf,
        folder     => 'Perl',
      }
);
$test->status_is($HTTP_NOT_FOUND);

$test->post_ok(
    '/t/thread-1/bookmark/remove' => { Accept => 'application/json' } =>
      form => {
        command_id => 'bookmark-remove-1',
        csrf_token => $session_csrf,
      }
);
$test->status_is($HTTP_OK);
$test->json_is( '/status' => 'bookmark_removed' );

# A like: not on one's own post (user-1 wrote post-1); as another member,
# given and taken back, with the post's count; only on a post that is there.
$test->post_ok(
    '/p/post-1/like' => { Accept => 'application/json' } => form => {
        command_id => 'like-own-1',
        csrf_token => $session_csrf,
    }
);
$test->status_is($HTTP_BAD_REQUEST);
$test->json_is( '/errors/post_id' => 'a post is not liked by its author' );
$test->get_ok('/__test/session/user-2');
$test->status_is($HTTP_OK);
_get_json_ok( $test, '/t/thread-1' );
$test->json_is( '/posts/0/can_like' => 1 );
$test->json_is( '/posts/0/liked'    => 1 );
$test->post_ok(
    '/p/post-1/like' => { Accept => 'application/json' } => form => {
        command_id => 'like-1',
        csrf_token => $session_csrf,
    }
);
$test->status_is($HTTP_OK);
$test->json_is( '/status'          => 'post_liked' );
$test->json_is( '/like/like_count' => 3 );
$test->json_is( '/like/post_id'    => 'post-1' );
$test->post_ok(
    '/p/post-1/like/remove' => { Accept => 'application/json' } => form => {
        command_id => 'unlike-1',
        csrf_token => $session_csrf,
    }
);
$test->status_is($HTTP_OK);
$test->json_is( '/status'     => 'post_unliked' );
$test->json_is( '/like/liked' => 0 );

# A reaction (ADR 0145): one of four, never on one's own post, given and
# taken back with the post's count of it.
_get_json_ok( $test, '/t/thread-1' );
$test->json_is( '/posts/0/can_react'            => 1 );
$test->json_is( '/posts/0/reactions/0/reaction' => 'heart' );
$test->json_is( '/posts/0/reactions/0/count'    => 2 );
$test->json_is( '/posts/0/reactions/0/reacted'  => 1 );
$test->post_ok(
    '/p/post-1/react/heart' => { Accept => 'application/json' } => form => {
        command_id => 'react-1',
        csrf_token => $session_csrf,
    }
);
$test->status_is($HTTP_OK);
$test->json_is( '/status'                  => 'post_reacted' );
$test->json_is( '/reaction/reaction'       => 'heart' );
$test->json_is( '/reaction/reaction_count' => 3 );
$test->post_ok(
    '/p/post-1/react/heart/remove' => { Accept => 'application/json' } =>
      form => {
        command_id => 'unreact-1',
        csrf_token => $session_csrf,
      }
);
$test->status_is($HTTP_OK);
$test->json_is( '/status'           => 'post_unreacted' );
$test->json_is( '/reaction/reacted' => 0 );
$test->post_ok(
    '/p/post-1/react/frown' => { Accept => 'application/json' } => form => {
        command_id => 'react-2',
        csrf_token => $session_csrf,
    }
);
$test->status_is($HTTP_BAD_REQUEST);
$test->json_is( '/errors/reaction' => 'unknown reaction' );
$test->post_ok(
    '/p/post-missing/like' => { Accept => 'application/json' } => form => {
        command_id => 'like-missing-1',
        csrf_token => $session_csrf,
    }
);
$test->status_is($HTTP_NOT_FOUND);
$test->get_ok('/__test/session/user-1');
$test->status_is($HTTP_OK);

$test->post_ok(
    '/t/thread-1/subscribe' => { Accept => 'application/json' } => form => {
        command_id => 'subscribe-1',
        csrf_token => $session_csrf,
        preference => 'all',
    }
);
$test->status_is($HTTP_OK);
$test->json_is( '/status'                  => 'subscribed' );
$test->json_is( '/subscription/preference' => 'all' );
$test->json_is( '/subscription/target_id'  => 'thread-1' );

$test->post_ok(
    '/t/thread-1/subscribe/mute' => { Accept => 'application/json' } => form =>
      {
        command_id => 'subscribe-mute-1',
        csrf_token => $session_csrf,
      }
);
$test->status_is($HTTP_OK);
$test->json_is( '/status' => 'subscription_muted' );

$test->post_ok(
    '/t/thread-1/subscribe/remove' => { Accept => 'application/json' } =>
      form => {
        command_id => 'subscribe-remove-1',
        csrf_token => $session_csrf,
      }
);
$test->status_is($HTTP_OK);
$test->json_is( '/status' => 'unsubscribed' );

$test->post_ok(
    '/t/thread-1/report' => { Accept => 'application/json' } => form => {
        command_id => 'thread-report-1',
        csrf_token => $session_csrf,
        reason     => 'spam',
        details    => 'Thread report',
    }
);
$test->status_is($HTTP_OK);
$test->json_is( '/status'             => 'reported' );
$test->json_is( '/report/target_type' => 'thread' );

$test->post_ok(
    '/p/post-1/report' => { Accept => 'application/json' } => form => {
        command_id => 'post-report-1',
        csrf_token => $session_csrf,
        reason     => 'abuse',
        details    => 'Post report',
    }
);
$test->status_is($HTTP_OK);
$test->json_is( '/status'             => 'reported' );
$test->json_is( '/report/target_type' => 'post' );
$test->json_is( '/report/target_id'   => 'post-1' );

$test->post_ok(
    '/t/thread-1/report' => { Accept => 'application/json' } => form => {
        csrf_token => $session_csrf,
        reason     => q{},
    }
);
$test->status_is($HTTP_BAD_REQUEST);
$test->json_is( '/errors/reason' => 'reason is required' );

$test->post_ok(
    '/p/missing/report' => { Accept => 'application/json' } => form => {
        csrf_token => $session_csrf,
        reason     => 'spam',
    }
);
$test->status_is($HTTP_NOT_FOUND);

_get_json_ok( $test, '/search?q=welcome' );
$test->status_is($HTTP_OK);
$test->json_is( '/results/0/entity_id'       => 'thread-1' );
$test->json_is( '/results/0/author_username' => 'giacomo_forum' );

$test->get_ok(
'/search?q=welcome&category_id=category-1&author_user_id=user-1&from=2026-05-01&to=2026-06-01'
);
$test->status_is($HTTP_OK);
$test->element_exists(q{input[name="category_id"][value="category-1"]});
$test->element_exists(q{input[name="author_user_id"][value="user-1"]});

_get_json_ok( $test, '/search/autocomplete?q=wel' );
$test->status_is($HTTP_OK);
$test->json_is( '/suggestions/0/entity_id' => 'thread-1' );
$test->json_hasnt('/suggestions/0/body');

_get_json_ok( $test, '/search/autocomplete?q=w' );
$test->status_is($HTTP_OK);
$test->json_is( '/suggestions' => [] );

_get_json_ok( $test, '/search' );
$test->status_is($HTTP_OK);
$test->json_is( '/results' => [] );

$test->app->helper(
    gp_rate_limiter => sub { return GPForum::Test::DenyLimiter->new; } );
_get_json_ok( $test, '/search?q=welcome' );
$test->status_is($HTTP_TOO_MANY);
_get_json_ok( $test, '/search/autocomplete?q=wel' );
$test->status_is($HTTP_TOO_MANY);
_get_json_ok( $test, '/new-thread' );
my $rate_csrf = _json_value( $test, 'csrf_token' );
$test->post_ok(
    '/threads' => form => {
        csrf_token  => $rate_csrf,
        category_id => 'category-1',
        title       => 'Too fast',
        body_source => 'Opening post',
        visibility  => 'public',
    }
);
$test->status_is($HTTP_TOO_MANY);

$test->app->helper(
    gp_readiness => sub { return GPForum::Test::FailReadiness->new; } );
$test->get_ok('/health/ready');
$test->status_is($HTTP_SERVICE_UNAVAIL);
$test->json_is( '/status' => 'fail' );

sub _install_forum_fakes {
    my ($test_object) = @_;

    my $services = GPForum::Test::ForumWebServices->new;
    for my $helper (
        qw(
        gp_category_reader gp_thread_reader gp_thread_detail_reader
        gp_thread_composer gp_thread_store gp_post_reader gp_post_composer
        gp_post_store gp_post_position gp_thread_read_state gp_mention_store
        gp_mention_reader gp_bookmark_store gp_bookmark_folders gp_like_store gp_reaction_store gp_reply_links gp_thread_tags gp_subscription_store
        gp_notification_dispatcher gp_report_store gp_search_service
        gp_rate_limiter gp_suspension_store gp_attachment_store
        )
      )
    {
        $test_object->app->helper( $helper => sub { return $services; } );
    }
    $test_object->app->helper(
        gp_feed_reader => sub {
            return GPForum::Test::ForumWebServices->new( mode => 'feed' );
        }
    );
    $test_object->app->helper(
        gp_command_idempotency => sub {
            return GPForum::Test::CommandIdempotency->new;
        }
    );

    return $services;
}

sub _get_json_ok {
    my ( $test_object, $path ) = @_;

    return $test_object->get_ok( $path => { Accept => 'application/json' } );
}

sub _install_test_session_route {
    my ($test_object) = @_;

    my $routes = $test_object->app->routes;
    my $route  = $routes->get('/__test/session/:user_id');
    $route->to(
        cb => sub {
            my ($controller) = @_;

            $controller->session( user_id => $controller->param('user_id') );
            return $controller->render( json => { ok => 1 } );
        }
    );

    return;
}

sub _json_value {
    my ( $test_object, $key ) = @_;

    my $transaction = $test_object->tx;
    my $response    = $transaction->res;
    my $json        = $response->json;

    return $json->{$key};
}

1;
