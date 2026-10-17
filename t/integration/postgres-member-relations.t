# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use Test::Mojo;
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Benchmark::SeedDataset qw(seed_id);
use GPForum::Infrastructure::Id;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Service::Community::FeedReader;
use GPForum::Service::Community::MentionReader;
use GPForum::Service::Community::MentionStore;
use GPForum::Service::Community::RelationStore;
use GPForum::Service::Notification::Dispatcher;
use GPForum::Test::PgDatabase;

our $VERSION = '0.001';

const my $HTTP_OK        => 200;
const my $HTTP_FOUND     => 302;
const my $HTTP_INVALID   => 400;
const my $HTTP_FORBIDDEN => 403;
const my $HTTP_NOT_FOUND => 404;
const my $MAXIMUM        => 500;
const my $INBOX_ROWS     => 100;
const my @CANDIDATES     => ( 3, 4, 5 );
const my $JSON           => { Accept => 'application/json' };

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'set GPFORUM_TEST_DSN for member ignore and block';
}

# ADR 0130 on a migrated, seeded PostgreSQL: the list's functions, the
# notifications and mentions a relation silences, erasure, export, and the
# pages and forms of a member.
local $ENV{GPFORUM_MINION_ENABLED}            = 0;
local $ENV{GPFORUM_REALTIME_LISTENER_ENABLED} = 0;
my $database = GPForum::Test::PgDatabase->fresh( seed => 1 );
local $ENV{GPFORUM_DATABASE_DSN} = $database->dsn;
my $schema    = $database->schema;
my $dbh       = $database->dbh;
my $ids       = GPForum::Infrastructure::Id->new;
my $functions = GPForum::Infrastructure::SqlFunction->new( schema => $schema );
my $relations = GPForum::Service::Community::RelationStore->new(
    schema    => $schema,
    functions => $functions
);
my ( $thread_id, $post_id, $other ) = $dbh->selectrow_array(
    q{SELECT p.thread_id, p.post_id, p.author_user_id FROM posts p}
      . q{ WHERE p.moderation_state = 'visible' AND p.deleted_at IS NULL}
      . q{ AND p.author_user_id <> ? ORDER BY p.thread_id, p.position LIMIT 1},
    undef,
    seed_id( user => 2 )
);
my $owner        = seed_id( user => 2 );
my ($owner_name) = _username($owner);
my ($other_name) = _username($other);
my ($third) = grep { $_ ne $other } map { seed_id( user => $_ ) } @CANDIDATES;
my ($third_name) = _username($third);

subtest 'the list holds one kind per member and refuses what it cannot' => sub {
    my $relate = sub ( $username, $kind ) {
        return $relations->set_relation(
            { owner_user_id => $owner, username => $username, kind => $kind } );
    };
    my $first = $relate->( $other_name, 'ignore' );
    is_deeply(
        [ @{$first}{qw(ok status changed)}, $first->{relation}{kind} ],
        [ 1, 'ok', 1, 'ignore' ],
        'a member is ignored'
    );
    is( $first->{relation}{other_user_id}, $other, 'by their id' );
    is( $relate->( $other_name, 'ignore' )->{status},
        'unchanged', 'ignoring again changes nothing' );
    is( $relate->( $other_name, 'block' )->{status},
        'ok', 'an ignored member is blocked in place' );
    is( $relations->relation_between( $owner, $other ),
        'block', 'and the list says so' );
    ok( $relations->blocks( $owner, $other ), 'blocks agrees' );
    is( $relations->relation_between( $other, $owner ),
        undef, 'the other member holds nothing' );
    is( $relate->( $owner_name, 'ignore' )->{status},
        'self', 'nobody lists themself' );
    is( $relate->( 'nobody-at-all', 'ignore' )->{status},
        'not_found', 'an unknown member is not found' );
    is( $relate->( $other_name, 'mute' )->{status},
        'invalid', 'an unknown kind is invalid' );
    is(
        $functions->row(
            'community_relation_set',
            {
                owner_user_id => $owner,
                username      => $other_name,
                kind          => 'mute',
                now           => '2026-10-15T00:00:00Z'
            }
        )->{status},
        'invalid',
        'and the function refuses it as well'
    );
    my $list = $relations->list_for_user($owner);
    is_deeply(
        [ map { [ @{$_}{qw(username kind)} ] } @{$list} ],
        [ [ $other_name, 'block' ] ],
        'the list names the member and the kind'
    );
};

subtest 'a list holds at most 500 members' => sub {
    my @filler = map { $ids->uuid } 1 .. $MAXIMUM - 1;
    my $insert = $dbh->prepare(
            q{INSERT INTO users (id, username, display_name, email_normalized,}
          . q{ password_hash, status) VALUES (?, ?, ?, ?, 'x', 'active')} );
    my $relate =
      $dbh->prepare( q{INSERT INTO member_relations VALUES}
          . q{ (?, ?, 'ignore', now(), now())} );
    for my $index ( 0 .. $#filler ) {
        $insert->execute(
            $filler[$index], "filler_$index",
            "Filler $index",
            "filler_$index\@example.invalid"
        );
        $relate->execute( $owner, $filler[$index] );
    }
    is(
        $relations->set_relation(
            {
                owner_user_id => $owner,
                username      => $third_name,
                kind          => 'ignore'
            }
        )->{status},
        'limit',
        'the 501st member is refused'
    );
    is(
        $relations->set_relation(
            {
                owner_user_id => $owner,
                username      => $other_name,
                kind          => 'ignore'
            }
        )->{status},
        'ok',
        'a listed member still changes kind'
    );
    is( scalar @{ $relations->list_for_user($owner) },
        $MAXIMUM, 'the list reads all 500' );
    $dbh->do(q{DELETE FROM users WHERE username LIKE 'filler\_%'});
    is( scalar @{ $relations->list_for_user($owner) },
        1, 'a deleted account leaves the list' );
};

subtest 'removing a member takes them off the list' => sub {
    is(
        $relations->remove_relation(
            { owner_user_id => $owner, username => $other_name }
        )->{removed},
        1,
        'the member is removed'
    );
    is(
        $relations->remove_relation(
            { owner_user_id => $owner, username => $other_name }
        )->{removed},
        0,
        'removing again removes nothing'
    );
    is( $relations->relation_between( $owner, $other ), undef, 'none is left' );
};

subtest 'replies and mentions from a listed member stay out of sight' => sub {
    my $dispatcher = GPForum::Service::Notification::Dispatcher->new(
        schema    => $schema,
        relations => $relations,
    );
    my $notify = sub ( $type, $key ) {
        return $dispatcher->create_notification(
            {
                recipient_user_id => $owner,
                notification_type => $type,
                source_type       => 'post',
                source_id         => $post_id,
                idempotency_key   => $key,
                payload           => {
                    actor_id  => $other,
                    post_id   => $post_id,
                    thread_id => $thread_id,
                },
            }
        );
    };
    my $count = sub { return $dispatcher->unread_count_for_user($owner); };
    my $inbox = sub ($wanted) {
        return
          scalar grep { ( $_->{notification_id} // q{} ) eq $wanted }
          @{ $dispatcher->list_for_user( $owner, $INBOX_ROWS ) };
    };
    my $before    = $count->();
    my $delivered = $notify->( 'reply', 'relation:before' );
    ok( $delivered->{ok}, 'a reply notifies an unlisted member' );
    my $reply = $delivered->{notification}{notification_id};
    is( $inbox->($reply), 1,           'into the inbox' );
    is( $count->(),       $before + 1, 'and is counted' );

    $relations->set_relation(
        { owner_user_id => $owner, username => $other_name, kind => 'ignore' }
    );
    is( $count->(), $before, 'ignoring the actor takes it off the count' );
    is( $inbox->($reply), 0, 'and out of the inbox' );
    is_deeply(
        $notify->( 'reply', 'relation:ignored' ),
        { ok => 0, skipped => 'member_relation' },
        'a new reply is not delivered'
    );
    ok(
        $notify->( 'moderation_notice', 'relation:staff' )->{ok},
        'a notice that is not a member reply or mention still is'
    );

    $relations->remove_relation(
        { owner_user_id => $owner, username => $other_name } );
    is( $inbox->($reply), 1,
        'removing the member brings the earlier reply back' );
};

subtest 'a blocked member cannot mention, an ignored one is out of sight' =>
  sub {
    my $mentions = GPForum::Service::Community::MentionStore->new(
        schema    => $schema,
        relations => $relations,
    );
    my $reader =
      GPForum::Service::Community::MentionReader->new( schema => $schema );
    my $listed = sub {
        return
          scalar grep { $_->{actor_id} eq $other }
          @{ $reader->list_page_for_recipient( $owner, { limit => 50 } )
              ->{items} };
    };
    my $mention = sub ($source) {
        return $mentions->record_for_source(
            {
                actor_id    => $other,
                body_source => "hello \@$owner_name",
                source_id   => $source,
                source_type => 'post',
                thread_id   => $thread_id,
            }
        );
    };

    $relations->set_relation(
        { owner_user_id => $owner, username => $other_name, kind => 'block' } );
    my $blocked = $mention->($post_id);
    is_deeply(
        [ scalar @{ $blocked->{created} }, $blocked->{skipped}[0]{reason} ],
        [ 0,                               'blocked' ],
        'the mention of a blocker is refused'
    );

    $relations->set_relation(
        { owner_user_id => $owner, username => $other_name, kind => 'ignore' }
    );
    is( scalar @{ $mention->($post_id)->{created} },
        1, 'an ignorer is mentioned' );
    is( $listed->(), 0, 'but the mention is not on their page' );
    $relations->remove_relation(
        { owner_user_id => $owner, username => $other_name } );
    is( $listed->(), 1, 'until the member is removed' );
  };

subtest 'export carries the own list and erasure empties both sides' => sub {
    $relations->set_relation(
        { owner_user_id => $owner, username => $other_name, kind => 'block' } );
    $relations->set_relation(
        { owner_user_id => $third, username => $owner_name, kind => 'ignore' }
    );
    my $document =
      $functions->row( 'portability_export_parts', { user_id => $owner } )
      ->{document};
    is_deeply(
        [
            map { [ @{$_}{qw(username kind)} ] }
              @{ $document->{member_relations} }
        ],
        [ [ $other_name, 'block' ] ],
        'the export lists who the member listed, not who listed them'
    );
    ok( exists $document->{drafts}, 'and keeps the earlier parts' );

    is(
        $functions->row(
            'privacy_revoke_user',
            {
                source  => 'MemberRelation',
                user_id => $owner,
                at      => '2026-10-15T00:00:00Z'
            }
        )->{revoked},
        2,
        'erasure removes the member from both sides'
    );
    is( $relations->relation_between( $third, $owner ),
        undef, 'nobody lists the erased member' );
};

subtest 'the feed leaves out what a listed member wrote' => sub {
    my ( $other_thread, $third_post ) = (
        $dbh->selectrow_array(
            q{SELECT t.thread_id FROM threads t WHERE t.author_user_id = ?}
              . q{ AND t.deleted_at IS NULL ORDER BY t.thread_id LIMIT 1},
            undef,
            $other
        ),
        $dbh->selectrow_array(
            q{SELECT p.post_id FROM posts p WHERE p.author_user_id = ?}
              . q{ AND p.deleted_at IS NULL ORDER BY p.post_id LIMIT 1},
            undef,
            $third
        )
    );
    ok( $other_thread && $third_post, 'the seed has a thread and a post' );
    $dbh->do( q{DELETE FROM user_feed_items WHERE user_id = ?}, undef, $owner );
    my $insert =
        q{INSERT INTO user_feed_items (user_id, item_type, item_id,}
      . q{ created_at, visibility_version, permission_version)}
      . q{ VALUES (?, ?, ?, now() - ?::interval, 1, 1)};
    $dbh->do( $insert, undef, $owner, 'post',   $post_id,      '1 minute' );
    $dbh->do( $insert, undef, $owner, 'thread', $other_thread, '2 minutes' );
    $dbh->do( $insert, undef, $owner, 'post',   $third_post,   '3 minutes' );
    my $reader =
      GPForum::Service::Community::FeedReader->new( schema => $schema );
    my $feed = sub ($limit) {
        return [
            map { $_->{item_id} } @{
                $reader->list_page_for_user( $owner, { limit => $limit } )
                  ->{items}
            }
        ];
    };
    is_deeply(
        $feed->(3),
        [ $post_id, $other_thread, $third_post ],
        'an unlisted member\'s post and thread are in the feed'
    );

    $relations->set_relation(
        { owner_user_id => $owner, username => $other_name, kind => 'ignore' }
    );
    is_deeply( $feed->(1), [$third_post],
        'ignoring them takes both out, before the page is cut' );
    $relations->set_relation(
        { owner_user_id => $owner, username => $other_name, kind => 'block' } );
    is_deeply( $feed->(3), [$third_post], 'and so does blocking them' );

    $relations->remove_relation(
        { owner_user_id => $owner, username => $other_name } );
    is( scalar @{ $feed->(3) }, 3, 'removing them brings the items back' );
    $dbh->do( q{DELETE FROM user_feed_items WHERE user_id = ?}, undef, $owner );
};

subtest 'a member ignores, blocks and manages the list in the browser' => sub {
    my $test   = Test::Mojo->new('GPForum');
    my $routes = $test->app->routes;
    $routes->get('/__test/relation-session')->to(
        cb => sub ($c) {
            $c->session( user_id => $owner );
            return $c->render( json => { ok => 1 } );
        }
    );
    $test->get_ok('/__test/relation-session')->status_is($HTTP_OK);
    $test->get_ok("/u/$other_name");
    $test->status_is($HTTP_OK);
    $test->element_exists(qq{form[action="/u/$other_name/ignore"]});
    $test->element_exists(qq{form[action="/u/$other_name/block"]});
    my $dom  = $test->tx->res->dom;
    my $csrf = $dom->at('input[name=csrf_token]')->attr('value');

    $test->post_ok( "/u/$other_name/ignore" => form => {} )
      ->status_is($HTTP_FORBIDDEN);
    $test->post_ok( "/u/$other_name/ignore" => form => { csrf_token => $csrf } )
      ->status_is($HTTP_FOUND)
      ->header_is( Location => "/u/$other_name" );
    $test->get_ok("/u/$other_name")
      ->element_exists(qq{form[action="/u/$other_name/relation/remove"]})
      ->element_exists_not(qq{form[action="/u/$other_name/ignore"]});
    $test->get_ok("/t/$thread_id");
    $test->status_is($HTTP_OK);
    $test->element_exists("#post-$post_id details.post__ignored summary");
    $test->element_exists("#post-$post_id details .forum-post-body");

    $test->post_ok(
        "/u/$other_name/block" => $JSON => form => { csrf_token => $csrf } )
      ->status_is($HTTP_OK)
      ->json_is( '/relation/kind' => 'block' );
    $test->post_ok(
        "/u/$owner_name/ignore" => $JSON => form => { csrf_token => $csrf } )
      ->status_is($HTTP_INVALID)
      ->json_is( '/status' => 'self' );
    $test->post_ok(
        '/u/nobody-at-all/ignore' => form => { csrf_token => $csrf } )
      ->status_is($HTTP_NOT_FOUND);
    $test->get_ok('/settings/ignored');
    $test->status_is($HTTP_OK);
    $test->header_like( 'Cache-Control' => qr/no-store/msx );
    $test->text_like( "#relation-$other-heading a" => qr/\S/msx );
    $test->element_exists(
        qq{form[action="/u/$other_name/relation/remove"] input[name=return_to]}
    );
    $test->get_ok( '/settings/ignored' => $JSON );
    $test->status_is($HTTP_OK);
    $test->json_is( '/relations/0/username' => $other_name );
    $test->json_is( '/maximum_relations'    => $MAXIMUM );
    $test->get_ok('/settings')->element_exists('a[href="/settings/ignored"]');

    $test->post_ok(
        "/u/$other_name/relation/remove" => form => {
            csrf_token => $csrf,
            return_to  => '/settings/ignored'
        }
    )->status_is($HTTP_FOUND)->header_is( Location => '/settings/ignored' );
    $test->get_ok('/settings/ignored')
      ->element_exists('#relations-empty-heading');
    $test->get_ok("/t/$thread_id")
      ->element_exists_not("#post-$post_id details.post__ignored");

    my $anonymous = Test::Mojo->new( $test->app );
    $anonymous->get_ok("/u/$other_name")
      ->element_exists_not(qq{form[action="/u/$other_name/ignore"]});
    $anonymous->get_ok('/settings/ignored')->status_is($HTTP_FOUND);
};

done_testing();

sub _username ($id) {
    return $dbh->selectrow_array( q{SELECT username FROM users WHERE id = ?},
        undef, $id );
}

1;
