# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

# The forum's writes and reads as the web worker runs them. Without a
# METHOD_p, call_p forked a child per call that opened a PostgreSQL
# connection of its own, one child at a time per worker. Each promise here
# must answer what its blocking method answers -- the same read, or the same
# effect on a fixture of its own -- and none may reach the fork fallback.
package main;
use v5.40;
use Const::Fast;
use English qw(-no_match_vars);
use Test::More;
use Test::Mojo;
use lib 'lib';
use lib 't/lib';
use GPForum::Benchmark::SeedDataset qw(seed_id);
use GPForum::Command::AdminBootstrap;
use GPForum::Service::Discovery::WebSub;
use GPForum::Service::Forum::Polls;
use GPForum::Service::Moderation::ThreadTransfers;
use GPForum::Infrastructure::AsyncWork;
use GPForum::Infrastructure::Id;
use GPForum::Test::PgDatabase;
use GPForum::Test::PostgresHarness;
use GPForum::Test::Promise qw(await_result);
use GPForum::Test::Forks   qw(children_during);

our $VERSION = '0.001';

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'set GPFORUM_TEST_DSN to compare forum write promises';
}
my $database = GPForum::Test::PgDatabase->fresh( seed => 1 );
local $ENV{GPFORUM_DATABASE_DSN}              = $database->dsn;
local $ENV{GPFORUM_MINION_ENABLED}            = 0;
local $ENV{GPFORUM_REALTIME_LISTENER_ENABLED} = 0;
local $ENV{GPFORUM_WARMUP_ENABLED}            = 0;
my $dbh    = $database->dbh;
my $ids    = GPForum::Infrastructure::Id->new;
my $member = seed_id( user => 2 );
my $other  = seed_id( user => 3 );
my $admin  = _administrator();

my $t = Test::Mojo->new('GPForum');
my $c = $t->app->build_controller;
$c->session( user_id => $member );
my $viewer = $c->gp_forum_viewer;
my ( $thread_id, $category_id ) = $dbh->selectrow_array(<<'SQL');
SELECT t.thread_id, t.category_id FROM threads t
JOIN categories c ON c.category_id = t.category_id
JOIN spaces s ON s.space_id = c.space_id
WHERE t.deleted_at IS NULL AND t.locked_at IS NULL
  AND t.moderation_state = 'visible' AND t.visibility = 'public'
  AND c.visibility = 'public' AND s.visibility = 'public'
ORDER BY t.thread_id LIMIT 1
SQL
my ($other_category) = $dbh->selectrow_array( <<'SQL', undef, $category_id );
SELECT category_id FROM categories WHERE category_id <> ? AND deleted_at IS NULL
  AND visibility = 'public' ORDER BY category_id LIMIT 1
SQL

# Every call below runs with the children AsyncWork starts watched.
my $children = children_during( \&_subtests );
is_deeply( $children->{other}, [],
    'no forum promise forked a child for the database' );

done_testing;

sub _subtests {
    subtest 'reads answer what the blocking reads answer' => \&_reads;
    subtest 'posting writes on the pooled connections'    => \&_posting;
    subtest 'the automod screens a native write'          => \&_automod;
    subtest 'drafts, follows, tags, links and polls'      => \&_small_writes;
    subtest 'messages and notifications'                  => \&_messages;
    subtest 'reports and held posts'                      => \&_reports;
    subtest 'attachments'                                 => \&_attachments;
    return;
}

sub _reads {
    my ($post_id) = $dbh->selectrow_array(
        q{SELECT post_id FROM posts WHERE thread_id = ? ORDER BY position}
          . q{ LIMIT 1},
        undef, $thread_id
    );
    my $post =
      same_answer( $c->gp_archive, 'post', [ $post_id, $viewer ], 'archive' );
    ok( $post, 'the archive reads the post' );
    same_answer(
        $c->gp_archive, 'post',
        [ $ids->uuid, $viewer ],
        'archive of nothing'
    );
    same_answer( $c->gp_archive, 'signature',  [ plain($post) ], 'signature' );
    same_answer( $c->gp_push_store, 'devices', [$member], 'push devices' );
    same_answer(
        GPForum::Service::Moderation::ThreadTransfers->new(
            schema => $c->gp_schema
        ),
        'redirect',
        [ $member, $thread_id ],
        'merged thread redirect'
    );
    same_answer(
        $c->gp_message_store,    'reportable',
        [ $ids->uuid, $member ], 'reportable message'
    );
    my $authorizer = $c->gp_realtime_hub->authorizer;

    for my $channel (
        "thread:$thread_id",    "notifications:$member",
        "notifications:$other", 'admin:all',
        'feed:personal'
      )
    {
        same_answer(
            $authorizer, 'authorize',
            [ { user_id => $member }, $channel, {} ],
            "authorize $channel"
        );
    }
    is(
        await_result(
            $authorizer->authorize_p(
                { user_id => $member },
                "thread:$thread_id", {}
            )
        )->{reason},
        'thread_readable',
        'a readable thread channel is granted'
    );
    my $websub = GPForum::Service::Discovery::WebSub->new(
        hub_url => 'https://hub.example.test/',
        topic   => 'https://forum.example.test/feed.atom'
    );
    my $form = {
        'hub.mode'     => 'subscribe',
        'hub.topic'    => $websub->topic,
        'hub.callback' => 'https://reader.example.test/cb',
    };
    is_deeply(
        await_result( $websub->subscription_p($form) ),
        $websub->subscription($form),
        'a WebSub form is checked alike'
    );
    my $accepted = eval { await_result( $websub->subscription_p( {} ) ); 1 };
    ok( !$accepted, 'and an empty one refused' );
    my $telemetry = $c->gp_security_telemetry;
    my $before    = $telemetry->total;
    await_result(
        $telemetry->record_p( 'realtime.denied', { channel_type => 'x' } ) );
    is( $telemetry->total, $before + 1, 'telemetry counts in the worker' );
    return;
}

sub _posting {
    my $workflow = $c->gp_posting_workflow;
    my $reply    = sub ($body) {
        return {
            author_user_id => $member,
            body_source    => $body,
            command_id     => $ids->uuid,
            thread_id      => $thread_id,
            viewer         => $viewer,
        };
    };
    my $blocking = $workflow->create_reply( $reply->('A blocking reply.') );
    my $input    = $reply->('A promised reply.');
    my $promised =
      await_result( $workflow->async_call_p( 'create_reply', [$input] ) );
    is_deeply(
        [ @{$promised}{qw(ok status)} ],
        [ @{$blocking}{qw(ok status)} ],
        'a reply is stored either way'
    );
    is_deeply(
        await_result( $workflow->async_call_p( 'create_reply', [$input] ) )
          ->{stored}{post}{post_id},
        $promised->{stored}{post}{post_id},
        'the same command replays the same post'
    );
    my $missing = { %{ $reply->('No command') }, command_id => q{} };
    is_deeply(
        await_result( $workflow->async_call_p( 'create_reply', [$missing] ) ),
        $workflow->create_reply($missing),
        'a reply without a command id is refused alike'
    );
    my $post_id = $promised->{stored}{post}{post_id};
    my $edit    = sub ($body) {
        return {
            author_user_id => $member,
            body_source    => $body,
            command_id     => $ids->uuid,
            post_id        => $post_id,
            viewer         => $viewer,
        };
    };
    my $edited = await_result(
        $workflow->async_call_p( 'edit_post', [ $edit->('Edited twice.') ] ) );
    ok( $edited->{ok}, 'the edit is stored' );
    is( _body($post_id), 'Edited twice.', 'with its new body' );
    my $delete = {
        author_user_id => $member,
        command_id     => $ids->uuid,
        post_id        => $post_id,
        viewer         => $viewer,
    };
    ok(
        await_result( $workflow->async_call_p( 'delete_post', [$delete] ) )
          ->{ok},
        'the post is deleted'
    );
    ok(
        await_result(
            $workflow->async_call_p(
                'restore_post', [ +{ %{$delete}, command_id => $ids->uuid } ]
            )
        )->{ok},
        'and restored'
    );
    _mentions( $workflow, $reply, $edit );
    return;
}

# A body that mentions someone: the post, its mention and the member's
# notification commit together on the pooled connections, as the blocking
# path commits them in the command's transaction.
sub _mentions ( $workflow, $reply, $edit ) {
    my $name    = _username($other);
    my $body    = "Hello \@$name, a reply.";
    my $mention = sub ($post) {
        return [ _mention_count($post), _notified( 'mention', $post ) ];
    };
    my $blocking = $workflow->create_reply( $reply->($body) );
    my $input    = $reply->($body);
    my $promised =
      on_event_loop(
        sub { $workflow->async_call_p( 'create_reply', [$input] ) } );
    is_deeply( _shape($promised), _shape($blocking),
        'a reply that mentions someone answers alike' );
    is_deeply(
        [
            map { $mention->( $_->{stored}{post}{post_id} ) } $blocking,
            $promised
        ],
        [ [ 1, 1 ], [ 1, 1 ] ],
        'each records its mention and notifies the member once'
    );
    my $replayed =
      await_result( $workflow->async_call_p( 'create_reply', [$input] ) );
    ok( $replayed->{idempotent}, 'the same command replays' );
    is_deeply(
        $mention->( $promised->{stored}{post}{post_id} ),
        [ 1, 1 ],
        'and records nothing again'
    );

    my $thread = sub {
        return {
            author_user_id => $member,
            body_source    => "A thread for \@$name.",
            category_id    => $category_id,
            command_id     => $ids->uuid,
            title          => 'A thread that mentions someone',
            viewer         => $viewer,
        };
    };
    my $opened = $workflow->create_thread( $thread->() );
    my $native = on_event_loop(
        sub { $workflow->async_call_p( 'create_thread', [ $thread->() ] ) } );
    is_deeply( _shape($native), _shape($opened),
        'a thread that mentions someone answers alike' );
    is_deeply(
        [ map { $mention->( $_->{stored}{post}{post_id} ) } $opened, $native ],
        [ [ 1, 1 ],                                                  [ 1, 1 ] ],
        'and records its mention either way'
    );

    my $post_id = $promised->{stored}{post}{post_id};
    my $edited  = on_event_loop(
        sub {
            $workflow->async_call_p( 'edit_post',
                [ $edit->("Edited, still for \@$name.") ] );
        }
    );
    ok( $edited->{ok}, 'an edit that mentions someone is stored' )
      or diag explain $edited;
    is_deeply(
        $mention->($post_id),
        [ 1, 1 ],
        'and the member is mentioned once'
    );
    my $self_mention = await_result(
        $workflow->async_call_p(
            'create_reply',
            [ $reply->( q{@} . _username($member) . ' talks to self' ) ]
        )
    );
    is_deeply(
        $mention->( $self_mention->{stored}{post}{post_id} ),
        [ 0, 0 ],
        'an author who mentions themself is not recorded'
    );
    return;
}

# The promise awaited as the web worker awaits it: blocking PostgreSQL
# access in this process croaks, so a mention recorded on the blocking
# path would degrade and leave no row behind.
sub on_event_loop ($promise) {
    local $GPForum::Infrastructure::PgStorage::HTTP_PID = $PROCESS_ID;
    return await_result( $promise->() );
}

# An answer without what each command draws for itself.
sub _shape ($answer) {
    return {
        ok       => $answer->{ok},
        status   => $answer->{status},
        error    => $answer->{error},
        stored   => [ sort keys %{ $answer->{stored}       // {} } ],
        post     => [ sort keys %{ $answer->{stored}{post} // {} } ],
        prepared => [ sort keys %{ $answer->{prepared}     // {} } ],
    };
}

sub _mention_count ($post) {
    return scalar $dbh->selectrow_array(
        q{SELECT count(*) FROM mentions WHERE source_type = 'post'}
          . q{ AND source_id = ?},
        undef, $post
    );
}

sub _notified ( $type, $post ) {
    return scalar $dbh->selectrow_array(
        q{SELECT count(*) FROM notifications WHERE notification_type = ?}
          . q{ AND source_type = 'post' AND source_id = ?},
        undef, $type, $post
    );
}

sub _automod {
    my $store    = $c->gp_posting_workflow->automod->store;
    my $workflow = $c->gp_posting_workflow;
    $store->add_word(
        { actor_user_id => $admin, phrase => 'forbidden', action => 'block' } );
    $store->add_word(
        {
            actor_user_id => $admin,
            phrase        => 'darn',
            action        => 'replace',
            replacement   => 'gosh'
        }
    );
    $store->add_word(
        { actor_user_id => $admin, phrase => 'casino', action => 'flag' } );
    my $reply = sub ($body) {
        return [
            {
                author_user_id => $member,
                body_source    => $body,
                command_id     => $ids->uuid,
                thread_id      => $thread_id,
                viewer         => $viewer,
            }
        ];
    };
    my $posts   = _count('posts');
    my $blocked = $workflow->create_reply( @{ $reply->('Very FORBIDDEN') } );
    my $refused = await_result(
        $workflow->async_call_p( 'create_reply', $reply->('Very FORBIDDEN') ) );
    for my $answer ( $refused, $blocked ) {
        delete $answer->{prepared}{values}{command_id};
    }
    is_deeply( $refused, $blocked, 'a blocked reply is refused alike' );
    is( _count('posts'),            $posts, 'and nothing is stored' );
    is( _audits('automod.blocked'), 2,      'each block is audited' );

    my $replaced = await_result(
        $workflow->async_call_p( 'create_reply', $reply->('Well, darn.') ) );
    is( _body( $replaced->{stored}{post}{post_id} ),
        'Well, gosh.', 'a replaced word is stored replaced' );
    is( _audits('automod.replaced'), 1, 'and the replacement audited' );

    my $flagged = await_result(
        $workflow->async_call_p( 'create_reply', $reply->('A casino here') ) );
    ok( $flagged->{ok}, 'a flagged reply is stored' );
    is(
        $dbh->selectrow_array(
            q{SELECT count(*) FROM reports WHERE target_id = ?}
              . q{ AND reporter_user_id IS NULL},
            undef,
            $flagged->{stored}{post}{post_id}
        ),
        1,
        'with its system report, in the same transaction'
    );

    $c->gp_review_store->set_rule(
        { actor_user_id => $admin, first_posts => '0', flagged => 1 } );
    my $held = await_result(
        $workflow->async_call_p( 'create_reply', $reply->('More casino') ) );
    is( $held->{status}, 'held', 'a flagged reply is held when staff ask' );
    is(
        $dbh->selectrow_array(
            q{SELECT reason FROM held_posts WHERE review_id = ?}, undef,
            $held->{held}{review_id}
        ),
        'flagged',
        'and kept for review'
    );
    $c->gp_review_store->set_rule(
        { actor_user_id => $admin, first_posts => '0', flagged => 0 } );

    my $messages = $c->gp_message_store;
    my $sent     = await_result(
        $messages->start_p(
            {
                body           => 'darn, a message',
                command_id     => $ids->uuid,
                sender_user_id => $member,
                username       => _username($other),
                viewer         => $viewer,
            }
        )
    );
    ok( $sent->{ok}, 'a screened message is sent' );
    is(
        $dbh->selectrow_array(
            q{SELECT body FROM direct_messages WHERE message_id = ?}, undef,
            $sent->{message_id}
        ),
        'gosh, a message',
        'as the rules rewrote it'
    );
    $dbh->do(q{DELETE FROM watched_words});
    return;
}

sub _small_writes {
    my $drafts = $c->gp_draft_store;
    my $draft  = sub {
        return {
            owner_user_id  => $member,
            draft_id       => $ids->uuid,
            draft_revision => 0,
            kind           => 'reply',
            thread_id      => $thread_id,
            body_source    => 'draft',
            command_id     => $ids->uuid,
        };
    };
    my $saved = await_result( $drafts->save_p( $draft->() ) );
    is_deeply(
        [ @{$saved}{qw(ok status)} ],
        [ @{ $drafts->save( $draft->() ) }{qw(ok status)} ],
        'a draft is saved alike'
    );
    is_deeply(
        await_result( $drafts->save_p( { %{ $draft->() }, kind => 'x' } ) ),
        $drafts->save( { %{ $draft->() }, kind => 'x' } ),
        'an invalid draft is refused alike'
    );
    ok(
        await_result(
            $drafts->remove_p(
                {
                    owner_user_id  => $member,
                    draft_id       => $saved->{draft}{draft_id},
                    draft_revision => $saved->{draft}{draft_revision},
                }
            )
        )->{ok},
        'and removed'
    );

    my $follows = $c->gp_category_subscriptions;
    my $follow  = sub ($category) {
        return {
            actor       => $member,
            command     => $ids->uuid,
            category_id => $category,
            operation   => 'follow'
        };
    };
    is_deeply(
        await_result( $follows->change_p( $follow->($category_id) ) ),
        $follows->change( $follow->($other_category) ),
        'a category is followed alike'
    );

    my $tags = $c->gp_thread_tags;
    is_deeply(
        [
            map { $_->{slug} } @{
                await_result(
                    $tags->set_thread_tags_p( $thread_id, 'Perl, PostgreSQL' )
                )
            }
        ],
        [qw(perl postgresql)],
        'tags are set'
    );
    is_deeply(
        $tags->tags_for_threads( [$thread_id] )->{$thread_id},
        await_result(
            $tags->set_thread_tags_p( $thread_id, 'Perl, PostgreSQL' )
        ),
        'as the thread reads them'
    );

    my @posts = map { $_->[0] } @{
        $dbh->selectall_arrayref(
            q{SELECT post_id FROM posts WHERE thread_id = ? AND deleted_at}
              . q{ IS NULL ORDER BY position LIMIT 3},
            undef, $thread_id
        )
    };
    is( await_result( $c->gp_reply_links->link_reply_p( @posts[ 1, 0 ] ) ),
        1, 'a reply is linked' );
    is(
        $c->gp_reply_links->link_reply( @posts[ 2, 0 ] ),
        await_result( $c->gp_reply_links->link_reply_p( @posts[ 2, 0 ] ) ),
        'a link made twice holds alike'
    );
    is( await_result( $c->gp_reply_links->link_reply_p( 'x', $posts[0] ) ),
        0, 'a malformed id links nothing' );

    my $polls = GPForum::Service::Forum::Polls->new( schema => $c->gp_schema );
    is_deeply(
        await_result( $polls->change_p( { command => 'x' } ) ),
        $polls->change( { command => 'x' } ),
        'a poll command without an id is refused alike'
    );

    my $bookmark = $c->gp_community_workflow->save_bookmark(
        {
            command_id  => $ids->uuid,
            target_id   => $thread_id,
            target_type => 'thread',
            user_id     => $member,
        }
    );
    my $id = $bookmark->{stored}{bookmark_id};
    is_deeply(
        await_result(
            $c->gp_bookmark_folders->file_bookmark_p( $id, $member, ' Later ' )
        ),
        { bookmark_id => $id, folder => 'Later' },
        'a bookmark is filed'
    );
    return;
}

sub _messages {
    my $messages = $c->gp_message_store;
    my $start    = sub ($body) {
        return {
            body           => $body,
            command_id     => $ids->uuid,
            sender_user_id => $other,
            username       => _username($member),
        };
    };
    my $first = $messages->start( $start->('first') );
    my $again = await_result( $messages->start_p( $start->('second') ) );
    is_deeply(
        [ @{$again}{qw(ok status conversation_id)} ],
        [ 1, 'ok', $first->{conversation_id} ],
        'a message goes to the conversation the two hold'
    );
    my $reply = {
        body            => 'a reply',
        command_id      => $ids->uuid,
        conversation_id => $first->{conversation_id},
        sender_user_id  => $member,
    };
    my $replied = await_result( $messages->reply_p($reply) );
    ok( $replied->{ok}, 'a reply is sent' );
    is( await_result( $messages->reply_p($reply) )->{status},
        'replayed', 'and replayed under its command' );
    is_deeply(
        await_result( $messages->reply_p( { %{$reply}, body => q{} } ) ),
        $messages->reply( { %{$reply}, body => q{} } ),
        'an empty reply is refused alike'
    );
    my $read =
      await_result(
        $messages->mark_read_p( $first->{conversation_id}, $other ) );
    is( $read->{status}, 'ok', 'the conversation is read' );
    is_deeply(
        $messages->mark_read( $first->{conversation_id}, $other ),
        await_result(
            $messages->mark_read_p( $first->{conversation_id}, $other )
        ),
        'and read again alike'
    );
    ok(
        await_result(
            $messages->reportable_p( $replied->{message_id}, $other )
        ),
        'the other member may report the reply'
    );

    my $notifications = $c->gp_notification_workflow;
    my $marked =
      await_result( $notifications->mark_all_read_p( { user_id => $member } ) );
    is( $marked->{status}, 'ok', 'the inbox is marked read' );
    is_deeply(
        [ @{ plain($marked) }{qw(ok status)} ],
        [
            @{
                plain(
                    $notifications->mark_all_read( { user_id => $member } )
                )
            }{qw(ok status)}
        ],
        'alike'
    );

    for my $id ( 'x', $ids->uuid ) {
        is_deeply(
            await_result(
                $notifications->mark_read_p(
                    { notification_id => $id, user_id => $member }
                )
            ),
            $notifications->mark_read(
                { notification_id => $id, user_id => $member }
            ),
            "marking notification '$id' answers alike"
        );
    }
    return;
}

sub _reports {
    my $community = $c->gp_community_workflow;
    my @posts     = map { $_->[0] } @{
        $dbh->selectall_arrayref(
            q{SELECT post_id FROM posts WHERE thread_id = ? AND deleted_at}
              . q{ IS NULL AND author_user_id <> ? ORDER BY position LIMIT 2},
            undef, $thread_id, $member
        )
    };
    my $report = sub ($post) {
        return {
            command_id       => $ids->uuid,
            reporter_user_id => $member,
            target_type      => 'post',
            target_id        => $post,
            reason           => 'spam',
            details          => 'details',
        };
    };
    my $blocking = $community->create_report( $report->( $posts[0] ) );
    my $input    = $report->( $posts[1] );
    my $promised = await_result( $community->create_report_p($input) );
    is_deeply(
        [ sort keys %{ $promised->{stored} } ],
        [ sort keys %{ $blocking->{stored} } ],
        'a report is stored alike'
    );
    is( $promised->{status}, 'ok', 'and stored' );
    is_deeply( await_result( $community->create_report_p($input) ),
        $promised, 'the same command replays the report' );
    is(
        await_result(
            $community->create_report_p(
                { %{ $report->( $posts[1] ) }, command_id => $ids->uuid }
            )
        )->{stored}{report_id},
        $promised->{stored}{report_id},
        'an open report on the target is reused'
    );
    is(
        $dbh->selectrow_array(
            q{SELECT count(*) FROM event_log WHERE event_type =}
              . q{ 'report.created' AND aggregate_id = ?},
            undef,
            $promised->{stored}{report_id}
        ),
        1,
        'its event is recorded once'
    );
    is_deeply(
        await_result(
            $community->create_report_p(
                { %{ $report->( $posts[0] ) }, reason => q{} }
            )
        ),
        $community->create_report(
            { %{ $report->( $posts[0] ) }, reason => q{} }
        ),
        'a report without a reason is refused alike'
    );

    my $store = $c->gp_review_store;
    my $hold  = sub {
        return {
            author_user_id     => $member,
            command_id         => $ids->uuid,
            command_type       => 'reply.create',
            kind               => 'reply',
            thread_id          => $thread_id,
            body_source        => 'held',
            body_rendered_safe => '<p>held</p>',
            reason             => 'first_posts',
        };
    };
    my $held     = await_result( $store->hold_p( $hold->() ) );
    my $withdraw = $c->gp_review_workflow;
    is_deeply(
        [ @{$held}{qw(ok status)} ],
        [ @{ $store->hold( $hold->() ) }{qw(ok status)} ],
        'a post is held alike'
    );
    my $withdrawn = await_result(
        $withdraw->withdraw_p(
            { review_id => $held->{review_id}, author_user_id => $member }
        )
    );
    is_deeply(
        [ @{$withdrawn}{qw(ok status review_status)} ],
        [ 1, 'ok', 'withdrawn' ],
        'and withdrawn by its author'
    );
    is_deeply(
        await_result(
            $withdraw->withdraw_p(
                { review_id => $held->{review_id}, author_user_id => $member }
            )
        ),
        $withdraw->withdraw(
            { review_id => $held->{review_id}, author_user_id => $member }
        ),
        'withdrawn again alike'
    );
    return;
}

sub _attachments {
    my $workflow = $c->gp_posting_workflow;
    my $post     = $workflow->create_reply(
        {
            author_user_id => $member,
            body_source    => 'A post with files.',
            command_id     => $ids->uuid,
            thread_id      => $thread_id,
            viewer         => $viewer,
        }
    )->{stored}{post}{post_id};
    my @files   = map { _attachment($post) } 1 .. 2;
    my $uploads = same_answer(
        $c->gp_attachment_store, 'owned_uploads_for_post',
        [ $post, $member ],      'owned uploads'
    );
    is( scalar @{$uploads}, 2, 'the author lists the two files' );

    my $download = {
        attachment_id  => $files[0],
        viewer         => $viewer,
        viewer_user_id => $member,
    };
    my $files = $c->gp_attachment_workflow;
    my $metadata =
      same_answer( $files, 'download_metadata', [$download], 'download' );
    ok( $metadata->{ok}, 'the file is downloadable' );
    same_answer(
        $files, 'download_metadata',
        [ +{ %{$download}, viewer => undef, viewer_user_id => undef } ],
        'download by a visitor'
    );
    same_answer(
        $files, 'download_metadata',
        [ +{ %{$download}, attachment_id => $ids->uuid } ],
        'download of nothing'
    );

    my $delete = sub ($file) {
        return {
            actor_user_id => $member,
            attachment_id => $file,
            command_id    => $ids->uuid,
            post_id       => $post,
            viewer        => $viewer,
        };
    };
    my $blocking = $files->delete_for_post( $delete->( $files[0] ) );
    my $input    = $delete->( $files[1] );
    my $promised = await_result( $files->delete_for_post_p($input) );
    is_deeply(
        [ @{$promised}{qw(ok status)}, $promised->{stored}{attachment}{state} ],
        [ @{$blocking}{qw(ok status)}, $blocking->{stored}{attachment}{state} ],
        'a file is deleted alike'
    );
    is_deeply( await_result( $files->delete_for_post_p($input) ),
        $promised, 'the same command replays the deletion' );
    is(
        $dbh->selectrow_array(
            q{SELECT count(*) FROM event_log WHERE event_type =}
              . q{ 'attachment.deleted' AND aggregate_id = ?},
            undef,
            $files[1]
        ),
        1,
        'its event is recorded once'
    );
    is(
        await_result(
            $files->delete_for_post_p(
                { %{ $delete->( $files[1] ) }, actor_user_id => $other }
            )
        )->{status},
        'forbidden',
        'another member may not delete it'
    );
    return;
}

# Calls METHOD and METHOD_p with the same arguments and compares them.
sub same_answer ( $service, $method, $arguments, $name ) {
    my $async    = $method . '_p';
    my $blocking = $service->$method( @{$arguments} );
    my $promised = await_result( $service->$async( @{$arguments}, undef ) );
    is_deeply( plain($promised), plain($blocking),
        "$name: promise = blocking" );
    return $promised;
}

# Rows are objects of the same classes either way; compare their columns.
sub plain ($value) {
    my $type = ref $value;
    return $value                          if !$type;
    return [ map { plain($_) } @{$value} ] if $type eq 'ARRAY';
    return { map { $_ => plain( $value->{$_} ) } keys %{$value} }
      if $type eq 'HASH' || $value->isa('HASH');
    return { $value->get_columns } if $value->can('get_columns');
    return "$type";
}

sub _attachment ($post) {
    my $key = 'forum-promises/' . $ids->uuid;
    $c->gp_attachment_storage->write_object( $key, 'bytes' );
    my ($id) = $dbh->selectrow_array( <<'SQL', undef, $member, $key );
INSERT INTO attachments (attachment_id, owner_user_id, object_key,
    original_filename, media_type, byte_size, checksum, state, scan_status)
VALUES (gen_random_uuid(), ?, ?, 'file.txt', 'text/plain', 5, 'checksum',
    'available', 'clean') RETURNING attachment_id
SQL
    $dbh->do( <<'SQL', undef, $id, $post );
INSERT INTO attachment_links (attachment_link_id, attachment_id, target_type,
    target_id) VALUES (gen_random_uuid(), ?, 'post', ?)
SQL
    return $id;
}

sub _body ($post_id) {
    return scalar $dbh->selectrow_array(
        q{SELECT b.body_source FROM posts p JOIN post_bodies b}
          . q{ ON b.body_id = p.current_body_id WHERE p.post_id = ?},
        undef, $post_id
    );
}

sub _count ($table) {
    return scalar $dbh->selectrow_array("SELECT count(*) FROM $table");
}

sub _audits ($action) {
    return
      scalar $dbh->selectrow_array(
        q{SELECT count(*) FROM audit_log WHERE action = ?},
        undef, $action );
}

sub _username ($id) {
    return
      scalar $dbh->selectrow_array( q{SELECT username FROM users WHERE id = ?},
        undef, $id );
}

sub _administrator {
    my ($id) = $dbh->selectrow_array(
            q{INSERT INTO users (id, username, display_name, email_normalized,}
          . q{ password_hash, status) VALUES (gen_random_uuid(),}
          . q{ 'promise_admin', 'Promise admin', 'promise-admin@example.test',}
          . q{ 'x', 'active') RETURNING id} );
    GPForum::Test::PostgresHarness::quietly(
        sub {
            return GPForum::Command::AdminBootstrap->new->run( 'grant',
                '--user-id', $id );
        }
    );
    return $id;
}

1;
