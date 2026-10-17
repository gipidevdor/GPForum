# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use Mojo::JSON qw(decode_json encode_json);
use Test::Mojo;
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Command::AdminBootstrap;
use GPForum::Infrastructure::Id;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Service::Community::MessageStore;
use GPForum::Service::Community::RelationStore;
use GPForum::Service::Forum::PostingAutomod;
use GPForum::Service::Moderation::AutomodStore;
use GPForum::Service::Realtime::OutboxEventMapper;
use GPForum::Test::PgDatabase;
use GPForum::Test::PostgresHarness;
use GPForum::Worker::Handler::NotificationDispatch;

our $VERSION = '0.001';

const my $HTTP_OK           => 200;
const my $HTTP_CREATED      => 201;
const my $HTTP_FOUND        => 302;
const my $HTTP_INVALID      => 400;
const my $HTTP_UNAUTHORIZED => 401;
const my $HTTP_FORBIDDEN    => 403;
const my $HTTP_MISSING      => 404;
const my $HTTP_GONE         => 410;
const my $HTTP_TOO_MANY     => 429;
const my $TOO_LONG          => 5001;
const my $NEW_MEMBER_LIMIT  => 3;
const my $THREE_MESSAGES    => 3;
const my $WORD              => 'quokkamail';
const my $JSON              => { Accept => 'application/json' };
const my $NOW               => '2026-10-17T10:00:00Z';

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'set GPFORUM_TEST_DSN for direct messages';
}

# ADR 0139 on a migrated, seeded PostgreSQL: two members hold one private
# conversation, read only by them; blocks, the day's bound and the watched
# words refuse what they must; the recipient is notified once a run; a
# reported message is read by staff through an audited request only; nothing
# reaches search, feeds or another member; erasure and export cover it.
local $ENV{GPFORUM_MINION_ENABLED}            = 0;
local $ENV{GPFORUM_REALTIME_LISTENER_ENABLED} = 0;
my $database = GPForum::Test::PgDatabase->fresh( seed => 1 );
local $ENV{GPFORUM_DATABASE_DSN} = $database->dsn;
my $schema    = $database->schema;
my $dbh       = $database->dbh;
my $ids       = GPForum::Infrastructure::Id->new;
my $functions = GPForum::Infrastructure::SqlFunction->new( schema => $schema );
my $store     = GPForum::Service::Community::MessageStore->new(
    schema    => $schema,
    functions => $functions,
);
my $relations = GPForum::Service::Community::RelationStore->new(
    schema    => $schema,
    functions => $functions,
);
my $ada       = _user( 'dm_ada',   1, 0 );
my $bob       = _user( 'dm_bob',   1, 0 );
my $carol     = _user( 'dm_carol', 0, 0 );
my $dave      = _user( 'dm_dave',  1, 0 );
my $staff     = _user( 'dm_staff', 1, 1 );
my $suspended = _user( 'dm_away',  1, 0 );
my @others    = map { _user( "dm_other_$_", 1, 0 ) } 1 .. $NEW_MEMBER_LIMIT + 1;
$dbh->do(
    q{INSERT INTO suspensions (suspension_id, user_id, actor_user_id, reason)}
      . q{ VALUES (gen_random_uuid(), ?, ?, 'messages test')},
    undef, $suspended, $staff
);

my ( $conversation, $first_message, $answer );
subtest 'the store starts a conversation and refuses what it must' => sub {
    my $command = $ids->uuid;
    my $sent =
      _start( $ada, 'dm_bob', "  Hello Bob, $WORD here.\r\nLine two.  ",
        $command );
    ok( $sent->{ok}, 'the first message is sent' );
    is( $sent->{status},     'ok',     'as ok' );
    is( $sent->{message_id}, $command, 'under the form\'s command id' );
    ok( $sent->{started},      'starting the conversation' );
    ok( $sent->{first_unread}, 'the first message bob has not read' );
    is( $sent->{recipient_user_id}, $bob, 'to bob' );
    $conversation  = $sent->{conversation_id};
    $first_message = $command;
    is(
        _message($command)->{body},
        "Hello Bob, $WORD here.\nLine two.",
        'trimmed, with its line endings made one'
    );

    my $again = _start( $ada, 'dm_bob', 'Me again' );
    is( $again->{conversation_id},
        $conversation, 'the two hold one conversation' );
    ok( !$again->{started},      'which is not started twice' );
    ok( !$again->{first_unread}, 'and bob is told once a run' );
    is( _start( $ada, 'dm_bob', 'twice', $command )->{status},
        'replayed', 'the same form again sends nothing' );
    is( _start( $dave, 'dm_bob', 'taken', $command )->{status},
        'conflict', 'a message id another message holds is a conflict' );
    is( _start( $ada, 'dm_ada', 'me' )->{status},
        'self', 'nobody writes to themself' );
    is( _start( $ada, 'dm_nobody', 'hi' )->{status},
        'not_found', 'nor to a member who does not exist' );
    is_deeply(
        _start( $ada, 'dm_bob', " \n " ),
        { ok => 0, status => 'invalid', field => 'body' },
        'an empty message is refused'
    );
    is( _start( $ada, 'dm_bob', 'x' x $TOO_LONG )->{status},
        'invalid', 'and one longer than 5000 characters' );
    is(
        $functions->row(
            'community_message_start',
            {
                row => {
                    message_id             => $ids->uuid,
                    new_conversation_id    => $ids->uuid,
                    sender_user_id         => $ada,
                    username               => 'dm_bob',
                    body                   => 'x' x $TOO_LONG,
                    created_at             => $NOW,
                    event_id               => $ids->uuid,
                    correlation_id         => $ids->uuid,
                    outbox_id              => $ids->uuid,
                    daily_limit            => 1,
                    new_member_daily_limit => 1,
                    new_member_trust_below => 1,
                }
            }
        )->{status},
        'invalid',
        'the function refuses it as well'
    );
};

subtest 'replies, reads and read state' => sub {
    my $reply = $store->reply(
        {
            sender_user_id  => $bob,
            conversation_id => $conversation,
            body            => 'Hi Ada',
        }
    );
    ok( $reply->{ok} && $reply->{first_unread}, 'bob answers ada' );
    $answer = $reply->{message_id};
    is(
        $store->reply(
            {
                sender_user_id  => $carol,
                conversation_id => $conversation,
                body            => 'let me in',
            }
        )->{status},
        'not_found',
        'a member of neither side cannot write in it'
    );
    is(
        $store->reply(
            {
                sender_user_id  => $bob,
                conversation_id => 'nope',
                body            => 'x',
            }
        )->{status},
        'not_found',
        'nor in a conversation that is not one'
    );

    my $inbox = $store->inbox($bob);
    is( scalar @{ $inbox->{items} },        1, 'bob has one conversation' );
    is( $inbox->{items}[0]{other_username}, 'dm_ada', 'with ada' );
    is( $inbox->{items}[0]{unread_count}, 0,
        'answering read the conversation' );
    is( $store->inbox($ada)->{items}[0]{unread_count},
        1, 'and ada has the answer to read' );
    is( $store->inbox($ada)->{items}[0]{last_excerpt},
        'Hi Ada', 'whose start the inbox shows' );

    my $head = $store->conversation( $conversation, $ada );
    is( $head->{other_username}, 'dm_bob', 'ada reads the conversation' );
    ok( !$store->conversation( $conversation, $carol ),
        'carol does not find it' );
    is_deeply( $store->messages( $conversation, $carol )->{items},
        [], 'nor its messages' );
    my $messages = $store->messages( $conversation, $ada )->{items};
    is( scalar @{$messages},  $THREE_MESSAGES, 'ada reads every message' );
    is( $messages->[0]{body}, 'Hi Ada',        'newest first' );
    is( $store->mark_read( $conversation, $ada )->{status},
        'ok', 'reading marks it read' );
    is( $store->mark_read( $conversation, $ada )->{status},
        'unchanged', 'once' );
    is( $store->mark_read( $conversation, $carol )->{status},
        'not_found', 'and only for a member' );
};

subtest 'a block refuses messages either way' => sub {
    ok(
        $relations->set_relation(
            { owner_user_id => $bob, username => 'dm_ada', kind => 'block' }
        )->{ok},
        'bob blocks ada'
    );
    is( _start( $ada, 'dm_bob', 'still there?' )->{status},
        'blocked', 'ada cannot write to bob' );
    is( _reply( $ada, 'still there?' )->{status}, 'blocked', 'nor answer him' );
    is( _reply( $bob, 'and you?' )->{status},
        'blocked', 'and bob, who blocks her, cannot write either' );
    $relations->remove_relation(
        { owner_user_id => $bob, username => 'dm_ada' } );
    ok( _reply( $ada, 'back' )->{ok}, 'unblocked, she can' );
    $store->mark_read( $conversation, $bob );
};

subtest 'a new member starts few conversations a day' => sub {
    for my $index ( 1 .. $NEW_MEMBER_LIMIT ) {
        ok( _start( $carol, "dm_other_$index", 'hello' )->{ok},
            "carol starts conversation $index" );
    }
    my $over = $NEW_MEMBER_LIMIT + 1;
    is( _start( $carol, "dm_other_$over", 'hello' )->{status},
        'limit', 'the next one is refused' );
    ok(
        _start( $carol, 'dm_other_1', 'again' )->{ok},
        'a conversation she holds still takes messages'
    );
    ok( _start( $ada, "dm_other_$over", 'hello' )->{ok},
        'a member of trust 1 starts more' );
};

subtest 'the recipient is notified once a run, as they choose' => sub {
    my $test = _session($bob);
    my $handler =
      GPForum::Worker::Handler::NotificationDispatch->new( dispatcher =>
          $test->app->build_controller->gp_notification_dispatcher );
    my $sent = _start( $ada, 'dm_bob', 'Are you there?' );
    ok( $sent->{first_unread}, 'a new run for bob' );
    my $more = _start( $ada, 'dm_bob', 'Hello?' );
    ok( !$more->{first_unread}, 'and a message more in it' );

    my $task = $handler->handle( _event( $sent->{message_id} ) );
    ok( $task->{delivery}{ok}, 'the first is delivered' );
    my $quiet = $handler->handle( _event( $more->{message_id} ) );
    ok( !$quiet->{delivery}, 'the next is not' );
    $handler->handle( _event( $sent->{message_id} ) );
    is( _notifications( $bob, $conversation ),
        1, 'one notification, retried or not' );
    is( _email_requests($conversation),
        1, 'and one email, linking the conversation' );

    $test->get_ok( '/notifications' => $JSON )->status_is($HTTP_OK);
    my $listed = $test->tx->res->json;
    my ($notice) =
      grep { $_->{notification_type} eq 'direct_message' }
      @{ $listed->{notifications} };
    ok( $notice, 'the inbox lists it' );
    is( $notice->{payload}{conversation_id}, $conversation, 'by conversation' );
    unlike( encode_json($notice), qr/Are[ ]you/msx, 'without the text' );
    $test->get_ok('/notifications')
      ->element_exists( qq{a[href="/messages/$conversation"]},
        'linking the conversation' );
    ok( $listed->{unread_count} >= 1, 'counted unread' );

    $test->get_ok("/messages/$conversation")->status_is($HTTP_OK);
    is( _unread_notifications( $bob, $conversation ),
        0, 'reading the conversation reads its notification' );

    $relations->set_relation(
        { owner_user_id => $bob, username => 'dm_ada', kind => 'ignore' } );
    my $ignored = _start( $ada, 'dm_bob', 'Ignored?' );
    my $silent  = $handler->handle( _event( $ignored->{message_id} ) );
    is( $silent->{delivery}{skipped},
        'member_relation', 'an ignored member\'s message notifies nothing' );
    $relations->remove_relation(
        { owner_user_id => $bob, username => 'dm_ada' } );
    $store->mark_read( $conversation, $bob );
};

subtest 'realtime hints name ids on both members\' own channels' => sub {
    my $sent = _start( $ada, 'dm_bob', "Realtime $WORD" );
    my ($payload) = $dbh->selectrow_array(
        q{SELECT payload::text FROM outbox_messages}
          . q{ WHERE payload::text LIKE ? LIMIT 1},
        undef, "%$sent->{message_id}%"
    );
    ok( $payload, 'the send wrote its outbox message' );
    unlike( $payload, qr/$WORD/msx, 'which holds no text' );
    my @frames =
      GPForum::Service::Realtime::OutboxEventMapper->new->events_for_payload(
        decode_json($payload) );
    is_deeply(
        [ map { $_->{aggregate_id} } @frames ],
        [ $bob, $ada ],
        'one hint for bob, one for ada\'s other pages'
    );
    is( $frames[0]{type}, 'direct_message.update', 'of their own kind' );
    is_deeply(
        $frames[0]{payload},
        { conversation_id => $conversation, message_id => $sent->{message_id} },
        'naming the conversation and the message'
    );
    $store->mark_read( $conversation, $bob );
};

subtest 'pages and forms' => sub {
    my $anonymous = Test::Mojo->new('GPForum');
    $anonymous->get_ok( '/messages' => $JSON )->status_is($HTTP_UNAUTHORIZED);
    $anonymous->get_ok( "/messages/$conversation" => $JSON )
      ->status_is($HTTP_UNAUTHORIZED);

    my $test = _session($ada);
    $test->get_ok('/messages')
      ->status_is($HTTP_OK)
      ->header_like( 'Cache-Control' => qr/no-store/msx );
    $test->element_exists(
        qq{a[href="/messages/$conversation"]},
        'the inbox links the conversation'
    );
    $test->get_ok("/messages/$conversation")->status_is($HTTP_OK);
    $test->content_like( qr/$WORD/msx, 'the conversation shows the messages' );
    $test->element_exists( qq{form[action="/messages/$conversation"]},
        'with the answer form' )
      ->element_exists(
qq{form[action="/messages/$conversation/$answer/report"] input[name=command_id]},
        'and a report form for bob\'s message'
      )
      ->element_exists_not(
        qq{form[action="/messages/$conversation/$first_message/report"]},
        'none for her own' );
    _session($carol)
      ->get_ok("/messages/$conversation")
      ->status_is( $HTTP_MISSING, 'carol does not find it' );
    $test->get_ok('/messages/not-a-uuid')->status_is($HTTP_MISSING);

    $test->post_ok(
        "/messages/$conversation" => form => { body => 'no token' } )
      ->status_is( $HTTP_FORBIDDEN, 'a form without its token is refused' );
    my $csrf    = _csrf($test);
    my $command = $ids->uuid;
    $test->post_ok(
        "/messages/$conversation" => form => {
            csrf_token => $csrf,
            command_id => $command,
            body       => 'From the form'
        }
      )
      ->status_is($HTTP_FOUND)
      ->header_is( Location => "/messages/$conversation#message-$command" );
    is( _message($command)->{body}, 'From the form', 'the answer is sent' );
    $test->post_ok( "/messages/$conversation" => $JSON => form =>
          { csrf_token => $csrf, command_id => $command, body => 'again' } )
      ->status_is( $HTTP_OK, 'sent twice, it is sent once' )
      ->json_is( '/status' => 'replayed' );
    $test->post_ok( "/messages/$conversation" => $JSON => form =>
          { csrf_token => $csrf, body => 'As JSON' } )
      ->status_is($HTTP_CREATED)
      ->json_is( '/status' => 'sent' );
    $test->post_ok( "/messages/$conversation" => form =>
          { csrf_token => $csrf, body => q{ } } )
      ->status_is($HTTP_INVALID)
      ->element_exists( '[role=alert]', 'an empty answer says why' );

    $test->get_ok('/messages/new/dm_bob')->status_is($HTTP_FOUND)->header_is(
        Location => "/messages/$conversation",
        'writing to bob opens the conversation they hold'
    );
    $test->get_ok('/messages/new/dm_dave')
      ->status_is($HTTP_OK)
      ->element_exists(
        'form[action="/messages/new/dm_dave"] textarea[name=body]',
        'the compose form' );
    $test->get_ok('/messages/new/dm_ada')->status_is($HTTP_MISSING);
    $test->get_ok('/messages/new/dm_nobody')->status_is($HTTP_MISSING);
    $test->post_ok( '/messages/new/dm_dave' => form =>
          { csrf_token => $csrf, body => 'Hello Dave' } )
      ->status_is($HTTP_FOUND)
      ->header_like(
        Location => qr{\A/messages/[[:xdigit:]-]{36}#message-}msx );
    $test->get_ok('/u/dm_dave')
      ->element_exists( 'a[href="/messages/new/dm_dave"]',
        'a profile offers to write' );

    $relations->set_relation(
        { owner_user_id => $dave, username => 'dm_ada', kind => 'block' } );
    $test->post_ok( '/messages/new/dm_dave' => form =>
          { csrf_token => $csrf, body => 'Blocked?' } )
      ->status_is( $HTTP_FORBIDDEN, 'a block refuses the form' )
      ->content_like( qr/Blocked[?]/msx, 'which keeps what was written' );

    my $away = _session($suspended);
    $away->post_ok( '/messages/new/dm_ada' => form =>
          { csrf_token => _csrf($away), body => 'Suspended' } )
      ->status_is( $HTTP_FORBIDDEN, 'a suspended member sends nothing' );
    $away->get_ok('/messages')->status_is( $HTTP_OK, 'but reads the inbox' );

    my $newcomer = _session($carol);
    my $over     = $NEW_MEMBER_LIMIT + 1;
    $newcomer->post_ok( "/messages/new/dm_other_$over" => $JSON => form =>
          { csrf_token => _csrf($newcomer), body => 'over' } )
      ->status_is($HTTP_TOO_MANY)
      ->json_is( '/status' => 'limit' );
};

subtest 'the watched words screen a message' => sub {
    my $automod = GPForum::Service::Moderation::AutomodStore->new(
        schema    => $schema,
        functions => $functions
    );
    ok(
        $automod->add_word(
            {
                phrase        => 'blockword',
                action        => 'block',
                actor_user_id => $staff
            }
        )->{ok},
        'a word that blocks'
    );
    ok(
        $automod->add_word(
            { phrase => 'flagword', action => 'flag', actor_user_id => $staff }
        )->{ok},
        'a word that flags'
    );
    my $screened = GPForum::Service::Community::MessageStore->new(
        schema    => $schema,
        functions => $functions,
        automod   =>
          GPForum::Service::Forum::PostingAutomod->new( store => $automod ),
    );
    my $refused = $screened->reply(
        {
            sender_user_id  => $ada,
            conversation_id => $conversation,
            body            => 'a blockword here',
        }
    );
    is( $refused->{status},          'invalid', 'a blocked word refuses it' );
    is( $refused->{automod}{reason}, 'watched_word', 'naming why' );
    my $flagged = $screened->reply(
        {
            sender_user_id  => $ada,
            conversation_id => $conversation,
            body            => 'a flagword here',
        }
    );
    ok( $flagged->{ok}, 'a flagged word sends it' );
    my ($system) = $dbh->selectrow_array(
        q{SELECT count(*) FROM reports WHERE target_type = 'message'}
          . q{ AND target_id = ? AND reporter_user_id IS NULL},
        undef, $flagged->{message_id}
    );
    is( $system, 1, 'and puts it in the queue as the system\'s report' );
    my $test = _session($ada);
    $test->post_ok( "/messages/$conversation" => form =>
          { csrf_token => _csrf($test), body => 'one more blockword' } )
      ->status_is($HTTP_INVALID)
      ->content_like( qr/blockword/msx, 'the page names the word' );
    $automod->remove_word( { phrase => 'blockword', actor_user_id => $staff } );
};

my $report_id;
subtest 'a participant reports a message; staff read it audited' => sub {
    my $test = _session($ada);
    my $csrf = _csrf($test);
    $test->post_ok( "/messages/$conversation/$first_message/report" => form =>
          { csrf_token => $csrf, reason => 'abuse', command_id => $ids->uuid } )
      ->status_is( $HTTP_MISSING, 'her own message is not hers to report' );
    _session($carol)
      ->post_ok( "/messages/$conversation/$answer/report" => form =>
          { csrf_token => $csrf, reason => 'abuse' } )
      ->status_is( $HTTP_FORBIDDEN, 'nor, without her token, carol\'s' );
    my $other = _session($carol);
    $other->post_ok(
        "/messages/$conversation/$answer/report" => form => {
            csrf_token => _csrf($other),
            reason     => 'abuse',
            command_id => $ids->uuid
        }
    )->status_is( $HTTP_MISSING, 'a stranger to it finds nothing to report' );
    $test->post_ok( "/messages/$conversation/$answer/report" => form =>
          { csrf_token => $csrf, reason => 'abuse', command_id => $ids->uuid } )
      ->status_is($HTTP_FOUND)
      ->header_is( Location => "/messages/$conversation" );
    ($report_id) = $dbh->selectrow_array(
        q{SELECT report_id FROM reports WHERE target_type = 'message'}
          . q{ AND target_id = ? AND reporter_user_id = ?},
        undef, $answer, $ada
    );
    ok( $report_id, 'the report is in the queue' );

    my $staff_page = _session($staff);
    $staff_page->get_ok('/moderation/reports')->status_is($HTTP_OK);
    $staff_page->element_exists(
        qq{form[action="/moderation/reports/$report_id/message"]},
        'beside it, the form that reads the message' )
      ->content_unlike( qr/Hi[ ]Ada/msx, 'which the queue does not show' );
    $staff_page->post_ok("/moderation/reports/$report_id/message")
      ->status_is( $HTTP_FORBIDDEN, 'reading needs the token' );
    is( _audits('direct_message.report_read'), 0, 'and audits nothing' );
    my $staff_csrf = _csrf($staff_page);
    $staff_page->post_ok( "/moderation/reports/$report_id/message" => form =>
          { csrf_token => $staff_csrf } )
      ->status_is($HTTP_OK)
      ->header_like( 'Cache-Control' => qr/no-store/msx );
    $staff_page->content_like( qr/Hi[ ]Ada/msx,
        'staff read the reported message' );
    $staff_page->content_unlike( qr/$WORD/msx,
        'and nothing else of the conversation' );
    is( _audits('direct_message.report_read'), 1, 'the reading is audited' );
    unlike(
        _audit_text('direct_message.report_read'),
        qr/Hi[ ]Ada/msx,
        'without the text'
    );
    my ($other_report) = $dbh->selectrow_array(
        q{SELECT report_id FROM reports WHERE target_type <> 'message' LIMIT 1}
    );
    $staff_page->post_ok( "/moderation/reports/$other_report/message" => form =>
          { csrf_token => $staff_csrf } )
      ->status_is( $HTTP_MISSING,
        'a report about anything else reads nothing' );

    my $member = _session($bob);
    $member->post_ok( "/moderation/reports/$report_id/message" => form =>
          { csrf_token => _csrf($member) } )
      ->status_is( $HTTP_FORBIDDEN, 'a member is no staff' );
};

subtest 'nothing reaches search, feeds or anyone else' => sub {
    my $test = _session($carol);
    $test->get_ok( "/search?q=$WORD" => $JSON )
      ->status_is($HTTP_OK)
      ->json_is( '/results' => [], 'search finds nothing' );
    for my $path ( '/u/dm_ada', '/u/dm_bob', '/feed', '/notifications' ) {
        $test->get_ok($path)->content_unlike( qr/$WORD/msx, "not on $path" );
    }
    Test::Mojo->new('GPForum')
      ->get_ok( '/u/dm_ada' => $JSON )
      ->content_unlike( qr/$WORD/msx, 'nor in a profile\'s JSON' );
    for my $table (
        qw(search_documents outbox_messages event_log notifications audit_log))
    {
        is( _containing($table), 0, "nothing of the text in $table" );
    }
};

subtest 'the export holds the member\'s own messages' => sub {
    my $document =
      $functions->row( 'portability_export_parts', { user_id => $bob } )
      ->{document};
    my ($with_ada) =
      grep { $_->{with_username} eq 'dm_ada' }
      @{ $document->{direct_messages} };
    ok( $with_ada, 'bob\'s conversation with ada is exported' );
    ok( ( grep { $_->{body} eq 'Hi Ada' } @{ $with_ada->{messages} } ),
        'with what he wrote' );
    unlike( encode_json($document), qr/$WORD/msx, 'and nothing ada wrote' );
};

subtest 'erasure deletes the member\'s messages and their side' => sub {
    my $revoked =
      $functions->row( 'privacy_revoke_user',
        { source => 'DirectMessage', user_id => $bob, at => $NOW } );
    ok( $revoked->{revoked} >= 1, 'bob\'s messages are revoked' );
    is( _authored($bob), 0, 'none is left' );
    ok( _authored($ada) > 0, 'ada keeps her own' );
    $dbh->do(
        q{UPDATE users SET status = 'deleted', deleted_at = now() WHERE id = ?},
        undef, $bob
    );
    my $head = $store->conversation( $conversation, $ada );
    ok( $head->{other_gone}, 'her conversation says he is gone' );
    is( _reply( $ada, 'still?' )->{status}, 'gone', 'and takes no answer' );
    my $test = _session($ada);
    $test->get_ok("/messages/$conversation")
      ->status_is($HTTP_OK)
      ->content_unlike( qr/dm_bob/msx, 'nor names him' );
    $test->element_exists_not( qq{form[action="/messages/$conversation"]},
        'nor offers to answer' );
    $test->post_ok( "/messages/$conversation" => $JSON => form =>
          { csrf_token => _csrf($test), body => 'gone?' } )
      ->status_is($HTTP_GONE);
    my $staff_page = _session($staff);
    $staff_page->post_ok( "/moderation/reports/$report_id/message" => form =>
          { csrf_token => _csrf($staff_page) } )
      ->status_is( $HTTP_GONE, 'the reported message went with him' );
};

done_testing();

sub _start ( $sender, $username, $body, $command = undef ) {
    return $store->start(
        {
            sender_user_id => $sender,
            username       => $username,
            body           => $body,
            command_id     => $command,
        }
    );
}

sub _reply ( $sender, $body ) {
    return $store->reply(
        {
            sender_user_id  => $sender,
            conversation_id => $conversation,
            body            => $body,
        }
    );
}

sub _message ($message_id) {
    return $dbh->selectrow_hashref(
        q{SELECT * FROM direct_messages WHERE message_id = ?},
        undef, $message_id );
}

sub _authored ($user_id) {
    return
      scalar $dbh->selectrow_array(
        q{SELECT count(*) FROM direct_messages WHERE author_user_id = ?},
        undef, $user_id );
}

# The direct_message.sent event of a message, as the outbox hands it to a
# handler.
sub _event ($message_id) {
    my $row = $dbh->selectrow_hashref(
        q{SELECT event_id, event_type, actor_id, aggregate_id, payload::text}
          . q{ AS payload FROM event_log WHERE event_type = 'direct_message.sent'}
          . q{ AND payload->>'message_id' = ?},
        undef, $message_id
    );

    return {
        event_id       => $row->{event_id},
        event_type     => $row->{event_type},
        actor_id       => $row->{actor_id},
        aggregate_id   => $row->{aggregate_id},
        domain_payload => decode_json( $row->{payload} ),
    };
}

sub _notifications ( $user_id, $conversation_id ) {
    return scalar $dbh->selectrow_array(
        q{SELECT count(*) FROM notifications WHERE recipient_user_id = ?}
          . q{ AND notification_type = 'direct_message'}
          . q{ AND payload->>'conversation_id' = ?},
        undef, $user_id, $conversation_id
    );
}

sub _unread_notifications ( $user_id, $conversation_id ) {
    return scalar $dbh->selectrow_array(
        q{SELECT count(*) FROM notification_inbox i JOIN notifications n}
          . q{ ON n.notification_id = i.notification_id}
          . q{ AND n.created_at = i.created_at}
          . q{ WHERE i.recipient_user_id = ? AND i.read_at IS NULL}
          . q{ AND n.payload->>'conversation_id' = ?},
        undef, $user_id, $conversation_id
    );
}

sub _email_requests ($conversation_id) {
    return scalar $dbh->selectrow_array(
        q{SELECT count(*) FROM event_log}
          . q{ WHERE event_type = 'notification.email.requested'}
          . q{ AND payload->>'conversation_id' = ?},
        undef, $conversation_id
    );
}

sub _audits ($action) {
    return
      scalar $dbh->selectrow_array(
        q{SELECT count(*) FROM audit_log WHERE action = ?},
        undef, $action );
}

sub _audit_text ($action) {
    my $rows = $dbh->selectcol_arrayref(
        q{SELECT row_to_json(a)::text FROM audit_log a WHERE action = ?},
        undef, $action );

    return join "\n", @{$rows};
}

sub _containing ($table) {
    return
      scalar $dbh->selectrow_array(
        qq{SELECT count(*) FROM $table t WHERE row_to_json(t)::text LIKE ?},
        undef, "%$WORD%" );
}

sub _csrf ($test) {
    $test->get_ok('/settings');
    my $dom   = $test->tx->res->dom;
    my $input = $dom->at('input[name=csrf_token]');

    return $input ? $input->attr('value') : q{};
}

# A browser signed in as the user.
sub _session ($user_id) {
    my $test   = Test::Mojo->new('GPForum');
    my $routes = $test->app->routes;
    $routes->get('/__test/messages-session')->to(
        cb => sub ($c) {
            $c->session( user_id => $user_id );
            return $c->render( json => { ok => 1 } );
        }
    );
    $test->get_ok('/__test/messages-session')->status_is($HTTP_OK);

    return $test;
}

# A new active member of the trust level given, given the bootstrap
# administration role when asked.
sub _user ( $name, $trust, $administrator ) {
    my ($id) = $dbh->selectrow_array(
        q{INSERT INTO users (id, username, display_name, email_normalized,}
          . q{ password_hash, status, email_verified_at, trust_level) VALUES}
          . q{ (gen_random_uuid(), ?, ?, ?, 'x', 'active', now(), ?)}
          . q{ RETURNING id},
        undef, $name, $name, "$name\@example.test", $trust
    );
    if ($administrator) {
        GPForum::Test::PostgresHarness::quietly(
            sub {
                return GPForum::Command::AdminBootstrap->new->run( 'grant',
                    '--user-id', $id );
            }
        );
    }

    return $id;
}

1;
