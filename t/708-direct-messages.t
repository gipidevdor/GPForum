# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use MIME::Base64 qw(decode_base64url encode_base64url);
use Test::Fatal;
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Service::Community::MessageStore;
use GPForum::Service::Community::RelationStore;
use GPForum::Service::Forum::PostingAutomod;
use GPForum::Service::Forum::Viewer;
use GPForum::Service::Notification::Renderer;
use GPForum::Service::Realtime::Hub;
use GPForum::Service::Realtime::OutboxEventMapper;
use GPForum::Test::MessageCalls;
use GPForum::Test::MessageMailer;
use GPForum::ViewModel::Community::Messages;
use GPForum::Web::ForumAccess;
use GPForum::Worker::Handler::NotificationDispatch;
use GPForum::Worker::Handler::NotificationMail;

our $VERSION = '0.001';

# Direct messages (ADR 0139), on stand-ins that record the calls and answer
# what the test gives: the text and the bounds, what reaches the functions,
# the screening, the pages' shapes, the notification of the first unread
# message, the realtime hints and the mail's link.

const my $ADA          => '018f2001-0001-7000-8000-000000000001';
const my $BOB          => '018f2001-0002-7000-8000-000000000002';
const my $CONVERSATION => '018f2002-0001-7000-8000-000000000001';
const my $MESSAGE      => '018f2003-0001-7000-8000-000000000001';
const my $OLDER        => '018f2003-0002-7000-8000-000000000002';
const my $REPORT       => '018f2004-0001-7000-8000-000000000001';
const my $EVENT        => '018f2005-0001-7000-8000-000000000001';
const my $MAXIMUM      => 5000;
const my $TOO_LONG     => 5001;
const my $INBOX_PAGE   => 25;
const my $DAILY        => 20;
const my $NEW_DAILY    => 3;
const my $ROWS         => 9;
const my $COPIES       => 3;
const my $TIME         => '2026-10-17 10:00:00+00';

sub fixture (%answers) {
    my $calls = GPForum::Test::MessageCalls->new( answers => \%answers );
    my $store = GPForum::Service::Community::MessageStore->new(
        schema    => $calls,
        functions => $calls,
    );

    return ( $calls, $store );
}

subtest 'a message is plain text of 1 to 5000 characters' => sub {
    my ( $calls, $store ) = fixture();
    is( $store->maximum_body, $MAXIMUM, 'the bound' );
    is_deeply(
        $store->daily_limits,
        { member => $DAILY, new_member => $NEW_DAILY, trust => 1 },
        'new conversations a day: 3 below trust level 1, 20 otherwise'
    );
    is( $store->normalize_body(" one\r\ntwo\rthree \n"),
        "one\ntwo\nthree", 'line endings made one, the ends trimmed' );
    is( $store->normalize_body(undef), q{}, 'nothing is empty' );
    for my $body ( q{ }, 'x' x $TOO_LONG ) {
        is_deeply(
            $store->start(
                { sender_user_id => $ADA, username => 'bob', body => $body }
            ),
            { ok => 0, status => 'invalid', field => 'body' },
            'an empty or too long message is refused before any call'
        );
    }
    is_deeply(
        $store->start(
            { sender_user_id => $ADA, username => q{}, body => 'Hi' }
        ),
        { ok => 0, status => 'invalid', field => 'username' },
        'so is a message to nobody'
    );
    is(
        $store->reply( { conversation_id => 'nope', body => 'Hi' } )->{status},
        'not_found',
        'and an answer in what is no conversation'
    );
    is( scalar @{ $calls->calls }, 0, 'none of them reached the functions' );
};

subtest 'a send passes its row and reads the answer' => sub {
    my ( $calls, $store ) = fixture(
        row => {
            community_message_start => {
                status            => 'ok',
                conversation_id   => $CONVERSATION,
                message_id        => $MESSAGE,
                recipient_user_id => $BOB,
                started           => 1,
                first_unread      => 1,
            },
            community_message_reply => { status => 'blocked' },
        }
    );
    my $sent = $store->start(
        {
            sender_user_id => $ADA,
            username       => 'bob',
            body           => " Hello\r\n",
            command_id     => $MESSAGE,
        }
    );
    ok( $sent->{ok}, 'the message is sent' );
    is_deeply(
        [
            @{$sent}{qw(status conversation_id message_id started first_unread)}
        ],
        [ 'ok', $CONVERSATION, $MESSAGE, 1, 1 ],
        'with what the function answered'
    );
    my ( $name, $values ) = @{ $calls->made('row')->[0] };
    is( $name, 'community_message_start', 'through the start function' );
    my $row = $values->{row};
    is( $row->{message_id}, $MESSAGE, 'the form\'s command id is the message' );
    is( $row->{body},       'Hello',  'the text as stored' );
    is_deeply(
        [
            @{$row}
              {qw(daily_limit new_member_daily_limit new_member_trust_below)}
        ],
        [ $DAILY, $NEW_DAILY, 1 ],
        'with the day\'s bounds'
    );
    is_deeply(
        [
            grep { !defined $row->{$_} }
              qw(new_conversation_id event_id correlation_id outbox_id created_at)
        ],
        [],
        'and the ids and time of the write'
    );
    $store->start(
        {
            sender_user_id => $ADA,
            username       => 'bob',
            body           => 'x',
            command_id     => 'no'
        }
    );
    isnt( $calls->made('row')->[1][1]{row}{message_id},
        'no', 'a command id that is no uuid is not used' );
    is_deeply(
        $store->reply(
            {
                sender_user_id  => $ADA,
                conversation_id => $CONVERSATION,
                body            => 'Hi'
            }
        ),
        {
            ok                => 0,
            status            => 'blocked',
            conversation_id   => undef,
            recipient_user_id => undef,
        },
        'a refusal is passed on'
    );
    my $bare = GPForum::Service::Community::MessageStore->new(
        schema    => GPForum::Test::MessageCalls->new,
        functions => undef,
    );
    ok(
        exception {
            $bare->reply(
                {
                    sender_user_id  => $ADA,
                    conversation_id => $CONVERSATION,
                    body            => 'Hi'
                }
            );
        },
        'without the function layer a send is unavailable'
    );
    is_deeply( $bare->inbox($ADA)->{items}, [], 'and the inbox is empty' );
};

subtest 'a send is screened as a reply is' => sub {
    my $automod = GPForum::Test::MessageCalls->new(
        answers => {
            rules_for => {
                words      => [ { phrase => 'casino', action => 'block' } ],
                link_limit => undef,
                review_first_posts => 0,
            },
        }
    );
    my ( $calls, $store ) = fixture(
        row => {
            community_message_reply =>
              { status => 'ok', message_id => $MESSAGE },
        }
    );
    $store->automod(
        GPForum::Service::Forum::PostingAutomod->new( store => $automod ) );
    my $refused = $store->reply(
        {
            sender_user_id  => $ADA,
            conversation_id => $CONVERSATION,
            body            => 'Visit my casino',
        }
    );
    is( $refused->{status},          'invalid', 'a blocked word refuses it' );
    is( $refused->{automod}{reason}, 'watched_word', 'naming why' );
    is_deeply( $refused->{automod}{phrases}, ['casino'], 'and the word' );
    is( scalar @{ $calls->made('row') }, 0, 'nothing was sent' );
    is( scalar @{ $automod->made('record_decisions') },
        1, 'the decision is recorded' );

    $automod->answers->{rules_for}{words} =
      [ { phrase => 'casino', action => 'flag' } ];
    my $flagged = $store->reply(
        {
            sender_user_id  => $ADA,
            conversation_id => $CONVERSATION,
            body            => 'Visit my casino',
        }
    );
    ok( $flagged->{ok}, 'a flagged word sends it' );
    is( $automod->transactions, 1, 'in one transaction with its decision' );
    my $report = $automod->made('record_decisions')->[1][0]{report};
    is_deeply(
        [ @{$report}{qw(target_type target_id)} ],
        [ 'message', $MESSAGE ],
        'which reports the message'
    );

    my $staff = GPForum::Service::Forum::Viewer->new( moderates => 1 );
    ok(
        $store->reply(
            {
                sender_user_id  => $ADA,
                conversation_id => $CONVERSATION,
                body            => 'casino',
                viewer          => $staff,
            }
        )->{ok},
        'staff who moderate are not screened'
    );
};

subtest 'reads and pages' => sub {
    my @rows = map {
        {
            conversation_id => "018f2002-0001-7000-8000-00000000000$_",
            last_message_at => $TIME,
        }
    } 1 .. $ROWS;
    my ( $calls, $store ) = fixture(
        rows => {
            community_message_inbox => sub ( $name, $values ) {
                my @all = (@rows) x $COPIES;
                return [ @all[ 0 .. $values->{row_limit} - 1 ] ];
            },
        },
        row => {
            community_message_conversation =>
              { conversation_id => $CONVERSATION },
            moderation_reported_message => {
                status          => 'ok',
                report_id       => $REPORT,
                message_id      => $MESSAGE,
                author_user_id  => $BOB,
                author_username => 'bob',
                body            => 'Hi',
                created_at      => $TIME,
            },
        },
    );
    my $page = $store->inbox($ADA);
    is( scalar @{ $page->{items} }, $INBOX_PAGE, 'a page of 25' );
    ok( $page->{has_next}, 'with more after it' );
    my ( $at, $id ) = split /[|]/msx, decode_base64url( $page->{next_cursor} );
    is_deeply(
        [ $at,   $id ],
        [ $TIME, $page->{items}[-1]{conversation_id} ],
        'whose cursor is the last one\'s time and id'
    );
    my $values = $calls->made('rows')->[0][1];
    is( $values->{row_limit}, $INBOX_PAGE + 1, 'asked one more than a page' );
    $store->inbox( $ADA, $page->{next_cursor} );
    is_deeply(
        [ @{ $calls->made('rows')->[1][1] }{qw(after_at after_id)} ],
        [ $at, $id ],
        'and the next page starts after it'
    );
    $store->inbox( $ADA, 'garbage' );
    is( $calls->made('rows')->[2][1]{after_at},
        undef, 'a cursor that does not read is the first page' );

    is( $store->conversation( 'nope', $ADA ),
        undef, 'a conversation id that is no uuid is none' );
    is( $store->conversation( $CONVERSATION, $ADA )->{conversation_id},
        $CONVERSATION, 'a member\'s conversation is read' );
    is_deeply( $store->messages( 'nope', $ADA )->{items},
        [], 'and no messages for what is none' );
    $store->messages( $CONVERSATION, $ADA, encode_base64url("$ROWS|$MESSAGE") );
    is( $calls->made('rows')->[-1][1]{before_position},
        $ROWS, 'older messages start before a position' );

    is( $store->read_reported( 'nope', $ADA )->{status},
        'not_found', 'a report id that is no uuid reads nothing' );
    my $read = $store->read_reported( $REPORT, $ADA );
    is( $read->{message}{body}, 'Hi', 'staff read the reported message' );
    my ( $name, $call ) = @{ $calls->made('row')->[-1] };
    is( $name, 'moderation_reported_message', 'through its function' );
    is( $call->{audit}{action},
        'direct_message.report_read', 'with the audit of the reading' );
    is( $call->{audit}{actor_id}, $ADA, 'naming who read it' );
    unlike( Mojo::JSON::encode_json( $call->{audit} ),
        qr/Hi/msx, 'never the text' );
};

subtest 'the pages\' shapes' => sub {
    my $view  = GPForum::ViewModel::Community::Messages->new;
    my $inbox = $view->inbox_page(
        user_id => $ADA,
        page    => {
            items => [
                {
                    conversation_id     => $CONVERSATION,
                    other_username      => 'bob',
                    other_display_name  => 'Bob',
                    other_gone          => 0,
                    last_message_at     => $TIME,
                    unread_count        => 2,
                    last_author_user_id => $ADA,
                    last_excerpt        => "Hello\nthere",
                },
                {
                    conversation_id    => $REPORT,
                    other_username     => 'deleted-user',
                    other_display_name => 'Deleted',
                    other_gone         => 1,
                },
            ],
            next_cursor => 'next',
        }
    );
    my ( $first, $gone ) = @{ $inbox->{conversations} };
    is( $first->{other}{display_name}, 'Bob',  'with whom' );
    is( $first->{unread_count},        2,      'how many wait' );
    is( $first->{last_excerpt}, 'Hello there', 'the latest on one line' );
    ok( $first->{last_is_own}, 'written by the reader' );
    ok( $gone->{other}{gone},  'an erased member is gone' );
    is( $gone->{other}{username}, undef,  'and named by none of their names' );
    is( $inbox->{next_cursor},    'next', 'with the next page' );

    my $ids  = 0;
    my $page = $view->conversation_page(
        user_id      => $ADA,
        conversation => {
            conversation_id    => $CONVERSATION,
            other_username     => 'bob',
            other_display_name => q{},
            reader_blocks      => 1,
        },
        page => {
            items => [
                {
                    message_id      => $MESSAGE,
                    author_user_id  => $BOB,
                    author_username => 'bob',
                    body            => "One\nTwo",
                },
                {
                    message_id      => $OLDER,
                    author_user_id  => $ADA,
                    author_username => 'ada',
                    body            => 'First',
                },
            ],
            next_cursor => 'older',
        },
        command_ids  => sub { return 'id-' . ++$ids; },
        maximum_body => $MAXIMUM,
    );
    my ( $older, $newer ) = @{ $page->{messages} };
    is( $older->{message_id}, $OLDER, 'oldest first' );
    ok( $older->{own}, 'the reader\'s own' );
    is( $older->{report_command_id}, q{}, 'which they do not report' );
    is_deeply( $newer->{body_lines}, [ 'One', 'Two' ], 'its lines kept' );
    is( $newer->{report_command_id}, 'id-1', 'the other\'s, reportable' );
    is( $newer->{author}{display_name},
        'bob', 'named by username without a display name' );
    ok( $page->{conversation}{reader_blocks}, 'the reader\'s block is said' );
    is( $page->{older_cursor}, 'older', 'with the older page' );
};

subtest 'the first unread message notifies, by its ids' => sub {
    my $dispatcher = GPForum::Test::MessageCalls->new(
        answers => { create_notification => { ok => 1 } } );
    my $handler = GPForum::Worker::Handler::NotificationDispatch->new(
        dispatcher => $dispatcher );
    my $event = {
        event_id       => $EVENT,
        event_type     => 'direct_message.sent',
        actor_id       => $ADA,
        domain_payload => {
            conversation_id   => $CONVERSATION,
            message_id        => $MESSAGE,
            recipient_user_id => $BOB,
            first_unread      => 0,
        },
    };
    ok( $handler->supports($event), 'the handler takes a message' );
    $handler->handle($event);
    is( scalar @{ $dispatcher->made('create_notification') },
        0, 'one more in an unread run notifies nothing' );
    $event->{domain_payload}{first_unread} = 1;
    $handler->handle($event);
    my ($notice) = @{ $dispatcher->made('create_notification')->[0] };
    is_deeply(
        $notice,
        {
            idempotency_key   => "notification.direct_message:$EVENT",
            notification_type => 'direct_message',
            recipient_user_id => $BOB,
            source_type       => 'message',
            source_id         => $MESSAGE,
            payload           => {
                conversation_id => $CONVERSATION,
                message_id      => $MESSAGE,
                event_id        => $EVENT,
                actor_id        => $ADA,
            },
        },
        'the first does, by ids'
    );
    $dispatcher->answers->{create_notification} =
      { ok => 0, status => 'failed' };
    ok(
        exception { $handler->handle($event) },
        'a failed delivery goes back to the outbox'
    );

    my $relations = GPForum::Service::Community::RelationStore->new(
        schema    => $dispatcher,
        functions => GPForum::Test::MessageCalls->new(
            answers => {
                row => { community_relation_between => { kind => 'ignore' } }
            }
        ),
    );
    ok(
        $relations->silences( $BOB, 'direct_message', $ADA ),
        'an ignored member\'s message is silenced'
    );

    my $renderer = GPForum::Service::Notification::Renderer->new;
    my $item     = $renderer->render_inbox_item( 'en',
        { notification_type => 'direct_message', payload => {} } );
    is( $item->{type_key}, 'direct_message',      'and has words of its own' );
    is( $item->{title},    'New private message', 'in the reader\'s language' );
};

subtest 'realtime hints and the mail\'s link' => sub {
    my @frames =
      GPForum::Service::Realtime::OutboxEventMapper->new->events_for_payload(
        {
            event_id       => $EVENT,
            event_type     => 'direct_message.sent',
            aggregate_id   => $CONVERSATION,
            actor_id       => $ADA,
            domain_payload => {
                conversation_id   => $CONVERSATION,
                message_id        => $MESSAGE,
                recipient_user_id => $BOB,
                sender_user_id    => $ADA,
            },
        }
      );
    is_deeply(
        [ map { [ $_->{type}, $_->{aggregate_id} ] } @frames ],
        [
            [ 'direct_message.update', $BOB ], [ 'direct_message.update', $ADA ]
        ],
        'a hint on each member\'s own channel'
    );
    is( $frames[0]{event_id}, $EVENT,
        'the recipient\'s under the event\'s id' );
    isnt( $frames[1]{event_id}, $EVENT, 'the sender\'s under its own' );
    my $hub = GPForum::Service::Realtime::Hub->new;
    is_deeply( $hub->broadcast_event( $frames[0] )->{channels},
        ["notifications:$BOB"], 'which the hub sends to that channel only' );

    my %sent;
    my $handler = GPForum::Worker::Handler::NotificationMail->new(
        mailer           => GPForum::Test::MessageMailer->new( sent => \%sent ),
        preference_store => GPForum::Test::MessageCalls->new(
            answers => {
                delivery_plan => {
                    email         => 1,
                    email_address => 'bob@example.test',
                    event_type    => 'message',
                    locale        => 'en',
                }
            }
        ),
        renderer => GPForum::Service::Notification::Renderer->new,
        tokens   => GPForum::Test::MessageMailer->new,
    );
    $handler->handle(
        {
            event_id       => $EVENT,
            event_type     => 'notification.email.requested',
            domain_payload => {
                recipient_user_id => $BOB,
                notification_type => 'direct_message',
                conversation_id   => $CONVERSATION,
            },
        }
    );
    like(
        $sent{body},
        qr{https://forum[.]test/messages/$CONVERSATION}msx,
        'the mail links the conversation'
    );
    is( $sent{subject}, 'New private message', 'and says what it is' );

    ok( GPForum::Web::ForumAccess->new->requires_participation('message.send'),
        'a suspended member sends none' );
};

done_testing();

1;
