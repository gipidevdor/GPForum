# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use Email::Sender::Transport::Test;
use Mojo::JSON qw(false true);
use Test::Exception;
use Test::Mojo;
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Service::Identity::Mailer;
use GPForum::Service::Notification::Dispatcher;
use GPForum::Service::Notification::PreferenceStore;
use GPForum::Service::Notification::Renderer;
use GPForum::Service::Notification::UnsubscribeToken;
use GPForum::Service::Notification::Workflow;
use GPForum::Service::Outbox::HandlerIdempotency;
use GPForum::Test::NotificationPreferenceCalls;
use GPForum::Worker::Handler::NotificationMail;

our $VERSION = '0.001';

const my $MEMBER  => '0193a5c4-0000-7000-8000-000000000001';
const my $ACTOR   => '0193a5c4-0000-7000-8000-000000000002';
const my $THREAD  => '0193a5c4-0000-7000-8000-000000000003';
const my $SCHEMA  => bless {}, 'GPForum::Test::NoSchema';
const my $MISSING => 404;
const my $OK      => 200;
const my $LONG    => 200;

# ADR 0078: preferences by kind of notification, the delivery plan, the
# mail and its signed one-click unsubscribe, without a database.

subtest 'a signed token names one member and one scope' => sub {
    my $tokens = GPForum::Service::Notification::UnsubscribeToken->new(
        secrets => [ 'new-secret', 'old-secret' ] );
    my $token = $tokens->issue( $MEMBER, 'reply' );
    is_deeply(
        $tokens->verify($token),
        { user_id => $MEMBER, scope => 'reply' },
        'it verifies'
    );
    my $old = GPForum::Service::Notification::UnsubscribeToken->new(
        secrets => ['old-secret'] )->issue( $MEMBER, 'all' );
    is( $tokens->verify($old)->{scope},
        'all', 'a token signed with a previous secret still works' );
    is(
        GPForum::Service::Notification::UnsubscribeToken->new(
            secrets => ['other']
        )->verify($token),
        undef,
        'one signed with another secret does not'
    );
    my ( $claim, $signature ) = split /[.]/msx, $token;
    my $forged = MIME::Base64::encode_base64url("$ACTOR.reply");
    is( $tokens->verify("$forged.$signature"),
        undef, 'another member\'s id under the signature does not' );
    is( $tokens->verify("$claim.x$signature"), undef, 'nor a bent signature' );
    is( $tokens->verify(undef),                undef, 'nor nothing' );
    is( $tokens->verify( 'a' x $LONG ),        undef, 'nor a long string' );
    dies_ok { $tokens->issue( $MEMBER, 'quote' ) }
    'an unknown scope is not issued';
    dies_ok {
        GPForum::Service::Notification::UnsubscribeToken->new->issue( $MEMBER,
            'reply' );
    }
    'nor anything without a secret';
};

subtest 'without the function layer the defaults stand' => sub {
    my $store = GPForum::Service::Notification::PreferenceStore->new(
        schema    => $SCHEMA,
        functions => undef
    );
    my $kinds = $store->type_preferences_for_user($MEMBER);
    is_deeply(
        [ map { _choices($_) } @{$kinds} ],
        [
            qw(reply:in_app:1 reply:email:0 mention:in_app:1 mention:email:1
              moderation:in_app:1 moderation:email:1)
        ],
        'the inbox for every kind, email for mentions and moderation'
    );
    is(
        $kinds->[2]{label_key},
        'notifications.kind.moderation',
        'with the i18n keys'
    );
    is_deeply( $store->event_types, [qw(reply mention moderation)],
        'the kinds' );
    is_deeply(
        $store->unsubscribe_scopes,
        [qw(reply mention moderation all)],
        'and the unsubscribe scopes'
    );
    is(
        $store->refused_type_preferences(
            [ { event_type => 'quote', channel => 'email' } ]
        )->{status},
        'invalid',
        'an unknown kind is refused'
    );
    is(
        $store->refused_type_preferences(
            [ { event_type => 'reply', channel => 'sms' } ]
        )->{errors}{channel},
        'channel must be one of in_app, email',
        'an unknown channel too'
    );
    is( $store->refused_type_preferences('reply')->{status},
        'invalid', 'and what is not a list' );
    dies_ok {
        $store->set_type_preferences(
            {
                user_id     => $MEMBER,
                preferences => [
                    { event_type => 'reply', channel => 'email', enabled => 1 }
                ]
            }
        );
    }
    'storing a choice needs the function layer';
    is(
        $store->unsubscribe( { user_id => $MEMBER, scope => 'nope' } )
          ->{status},
        'invalid',
        'an unknown scope is invalid before anything is asked'
    );
};

subtest 'the store passes parameters and reads the answers' => sub {
    my $calls = GPForum::Test::NotificationPreferenceCalls->new(
        answers => {
            notification_set_type_preferences =>
              { status => 'ok', changed => 1 },
            notification_delivery_plan => {
                event_type    => 'mention',
                in_app        => 0,
                email         => 1,
                email_address => 'm@example.test',
                locale        => 'it',
            },
            notification_unsubscribe => { status => 'unchanged' },
        }
    );
    my $store = GPForum::Service::Notification::PreferenceStore->new(
        schema    => $SCHEMA,
        functions => $calls,
        recorder  => $calls,
    );
    is_deeply(
        $store->set_type_preferences(
            {
                user_id     => $MEMBER,
                preferences => [
                    { event_type => 'reply', channel => 'email', enabled => 1 }
                ]
            }
        ),
        { ok => 1, status => 'ok', changed => 1 },
        'a choice stored'
    );
    my ($sent) = @{ $calls->calls_to('notification_set_type_preferences') };
    is( $sent->{preferences}[0]{enabled}, true, 'as a JSON boolean' );
    is_deeply(
        $store->delivery_plan( $MEMBER, 'mention' ),
        {
            event_type    => 'mention',
            in_app        => 0,
            email         => 1,
            email_address => 'm@example.test',
            locale        => 'it',
        },
        'the plan as the function answers it'
    );
    is_deeply(
        $store->unsubscribe(
            { user_id => $MEMBER, scope => 'all', via => 'one_click' }
        ),
        { ok => 1, status => 'unchanged', scope => 'all' },
        'an unsubscribe already in place'
    );
    my ($unsubscribe) = @{ $calls->calls_to('notification_unsubscribe') };
    is_deeply(
        [ @{ $unsubscribe->{audit} }{qw(action actor_id target_id)} ],
        [ 'notification.email_unsubscribed', $MEMBER, $MEMBER ],
        'carries its audit'
    );
    is( $unsubscribe->{audit}{metadata}{via}, 'one_click', 'and how' );

    $calls->answers->{notification_delivery_plan} = undef;
    is_deeply(
        $store->delivery_plan( $MEMBER, 'mention' ),
        { in_app => 1, email => 0 },
        'an unknown member gets the inbox only'
    );
    $calls->answers->{notification_set_type_preferences} =
      { status => 'not_found', changed => 0 };
    is(
        $store->set_type_preferences(
            {
                user_id     => $MEMBER,
                preferences => []
            }
        )->{status},
        'not_found',
        'a member gone is not found'
    );
};

subtest 'the dispatcher follows the plan' => sub {
    my $calls = GPForum::Test::NotificationPreferenceCalls->new(
        answers => {
            notification_deliver =>
              sub { return { result => { ok => 1, inbox => {} } }; },
            notification_unread_count => { unread_count => 0 },
        }
    );
    my $dispatcher = GPForum::Service::Notification::Dispatcher->new(
        schema           => $SCHEMA,
        functions        => $calls,
        event_recorder   => $calls,
        preference_store => $calls,
    );
    my $input = {
        notification_type => 'mention',
        recipient_user_id => $MEMBER,
        source_type       => 'post',
        source_id         => $THREAD,
        payload           => { actor_id => $ACTOR, thread_id => $THREAD },
    };

    $calls->answers->{delivery_plan} = { in_app => 0, email => 0 };
    is_deeply(
        $dispatcher->create_notification($input),
        { ok => 0, skipped => 'channel_disabled', channel => 'in_app' },
        'neither channel: nothing'
    );

    $calls->answers->{delivery_plan} = { in_app => 0, email => 1 };
    is( $dispatcher->create_notification($input)->{email_queued},
        1, 'email only: the mail is queued' );
    is( scalar @{ $calls->calls_to('notification_deliver') },
        0, 'and the inbox not written' );
    my ($event) = @{ $calls->calls_to('record_event') };
    is( $event->{event_type}, 'notification.email.requested', 'as the event' );
    is_deeply(
        [
            @{ $event->{payload} }
              {qw(recipient_user_id notification_type thread_id)}
        ],
        [ $MEMBER, 'mention', $THREAD ],
        'naming the recipient, the type and the thread'
    );
    ok( !exists $event->{payload}{email_address}, 'never the address' );
    my $again = GPForum::Service::Notification::Dispatcher->new(
        schema           => $SCHEMA,
        functions        => $calls,
        event_recorder   => $calls,
        preference_store => $calls,
    );
    $again->create_notification($input);
    my @events = @{ $calls->calls_to('record_event') };
    is(
        $events[1]{event_id},
        $events[0]{event_id},
        'the same notification is the same event'
    );

    $calls->answers->{delivery_plan} = { in_app => 1, email => 1 };
    my $both = $dispatcher->create_notification($input);
    ok( $both->{ok} && $both->{email_queued}, 'both: the inbox and the mail' );

    $calls->answers->{delivery_plan} = sub { die "store down\n" };
    my $failed = $dispatcher->create_notification($input);
    ok(
        $failed->{ok} && !$failed->{email_queued},
        'a failed plan reads as the inbox only'
    );
};

subtest 'the workflow checks the kinds before the channels' => sub {
    my $store = GPForum::Service::Notification::PreferenceStore->new(
        schema    => $SCHEMA,
        functions => undef
    );
    my $workflow = GPForum::Service::Notification::Workflow->new(
        dispatcher       => {},
        preference_store => $store,
    );
    my $result = $workflow->set_preferences(
        {
            command_id       => 'c1',
            user_id          => $MEMBER,
            preferences      => [],
            type_preferences =>
              [ { event_type => 'quote', channel => 'email' } ],
        }
    );
    is( $result->{status}, 'invalid', 'an unknown kind is an invalid request' );
};

subtest 'the mail worker sends what the member still takes' => sub {
    my $calls = GPForum::Test::NotificationPreferenceCalls->new;
    my $tokens =
      GPForum::Service::Notification::UnsubscribeToken->new( secrets => ['s'] );
    my $handler = GPForum::Worker::Handler::NotificationMail->new(
        mailer           => $calls,
        preference_store => $calls,
        renderer         => GPForum::Service::Notification::Renderer->new,
        tokens           => $tokens,
    );
    my $event = {
        event_id       => 'e1',
        event_type     => 'notification.email.requested',
        domain_payload => {
            recipient_user_id => $MEMBER,
            notification_type => 'reply',
            thread_id         => $THREAD,
        },
    };
    ok( $handler->supports($event), 'it handles the mail event' );
    ok( !$handler->supports( { event_type => 'post.created' } ),
        'and no other' );

    $calls->answers->{delivery_plan} = {
        event_type    => 'reply',
        email         => 1,
        email_address => 'm@example.test',
        locale        => 'it',
    };
    ok( $handler->handle($event)->{delivered}, 'sent' );
    my ($mail) = @{ $calls->calls_to('send_notification_mail') };
    is( $mail->{to}, 'm@example.test', 'to the address the plan reads' );
    is(
        $mail->{subject},
        'Nuova risposta in una discussione seguita',
        'in the member\'s language'
    );
    like(
        $mail->{body},
        qr{https://forum[.]example[.]test/t/\Q$THREAD\E}msx,
        'linking the thread'
    );
    my ($token) = $mail->{unsubscribe_url} =~ m{/unsubscribe/(.+)\z}msx;
    is_deeply(
        $tokens->verify($token),
        { user_id => $MEMBER, scope => 'reply' },
        'with a link that stops reply email'
    );
    like(
        $mail->{body},
        qr/\Q$mail->{unsubscribe_url}\E/msx,
        'shown in the body as well'
    );

    $calls->answers->{delivery_plan} = { event_type => 'reply', email => 0 };
    ok(
        $handler->handle($event)->{skipped},
        'a member who stopped it since gets nothing'
    );
    ok(
        GPForum::Worker::Handler::NotificationMail->new->handle($event)
          ->{skipped},
        'nor without collaborators'
    );
    is(
        GPForum::Service::Outbox::HandlerIdempotency->new->key_for(
            $handler, { event_id => 'e1' }
        ),
        'worker.notification_mail:e1',
        'a retried event sends once'
    );
};

subtest 'the mailer adds the RFC 8058 headers' => sub {
    my $transport = Email::Sender::Transport::Test->new;
    my $mailer    = GPForum::Service::Identity::Mailer->new(
        transport    => $transport,
        from_address => 'forum@example.test',
    );
    $mailer->send_notification_mail(
        {
            to              => 'm@example.test',
            subject         => 'Nuova attività',
            body            => 'Città',
            unsubscribe_url => 'https://forum.example.test/unsubscribe/t.s',
        }
    );
    my ($sent) = $transport->deliveries;
    my $email = $sent->{email};
    is(
        $email->get_header('List-Unsubscribe'),
        '<https://forum.example.test/unsubscribe/t.s>',
        'List-Unsubscribe'
    );
    is( $email->get_header('List-Unsubscribe-Post'),
        'List-Unsubscribe=One-Click', 'List-Unsubscribe-Post' );
    like(
        $email->get_header('Subject'),
        qr/\A =[?]UTF-8[?]/msx,
        'the subject MIME-encoded'
    );
    $mailer->send_password_reset( { to => 'm@example.test', token => 'x' } );
    my ( undef, $reset ) = $transport->deliveries;
    is( $reset->{email}->get_header('List-Unsubscribe'),
        undef, 'transactional mail has none' );
};

subtest 'the unsubscribe link without a database' => sub {
    my $test   = Test::Mojo->new('GPForum');
    my $tokens = $test->app->build_controller->gp_unsubscribe_tokens;
    my $token  = $tokens->issue( $MEMBER, 'mention' );
    $test->get_ok("/unsubscribe/$token")->status_is($OK);
    $test->element_exists('form input[name="csrf_token"]')
      ->element_exists('input[name="scope"][value="mention"][checked]');
    $test->get_ok('/unsubscribe/forged.token')->status_is($MISSING);
    $test->post_ok( "/unsubscribe/${token}x" => form =>
          { 'List-Unsubscribe' => 'One-Click' } )->status_is($MISSING);
};

done_testing;

sub _choices ($kind) {
    return
      map { "$kind->{event_type}:$_->{channel}:$_->{enabled}" }
      @{ $kind->{channels} };
}

1;
