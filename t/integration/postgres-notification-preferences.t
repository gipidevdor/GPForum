# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use Email::Sender::Transport::Test;
use Mojo::JSON qw(false true);
use Test::Mojo;
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Infrastructure::SqlFunction;
use GPForum::Service::Identity::Mailer;
use GPForum::Service::Notification::Dispatcher;
use GPForum::Service::Notification::PreferenceStore;
use GPForum::Service::Notification::Renderer;
use GPForum::Service::Notification::UnsubscribeToken;
use GPForum::Test::PgDatabase;
use GPForum::Worker::Handler::NotificationMail;

our $VERSION = '0.001';

const my $HTTP_OK        => 200;
const my $HTTP_FOUND     => 302;
const my $HTTP_FORBIDDEN => 403;
const my $HTTP_MISSING   => 404;
const my $HTTP_TOO_MANY  => 429;

# The identity.unsubscribe limit: this many in five minutes.
const my $UNSUBSCRIBE_LIMIT => 60;
const my $NOW               => '2026-10-15T12:00:00Z';
const my $BASE              => 'https://forum.example.test';
const my $EMAIL_EVENT       => 'notification.email.requested';

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'set GPFORUM_TEST_DSN for notification preferences';
}

# ADR 0078 on a migrated PostgreSQL: preferences by kind of notification,
# the delivery plan fanout follows, the notification mail and its RFC 8058
# one-click unsubscribe.
local $ENV{GPFORUM_MINION_ENABLED}            = 0;
local $ENV{GPFORUM_REALTIME_LISTENER_ENABLED} = 0;
my $database = GPForum::Test::PgDatabase->fresh( seed => 1 );
local $ENV{GPFORUM_DATABASE_DSN} = $database->dsn;
my $schema    = $database->schema;
my $dbh       = $database->dbh;
my $functions = GPForum::Infrastructure::SqlFunction->new( schema => $schema );
my $store     = GPForum::Service::Notification::PreferenceStore->new(
    schema    => $schema,
    functions => $functions,
);
my $member      = _user( 'pref_member',     1 );
my $unverified  = _user( 'pref_unverified', 0 );
my $actor       = _user( 'pref_actor',      1 );
my ($thread_id) = $dbh->selectrow_array(
        q{SELECT t.thread_id FROM threads t WHERE t.deleted_at IS NULL}
      . q{ AND t.moderation_state = 'visible' AND t.visibility = 'public'}
      . q{ ORDER BY t.thread_id LIMIT 1} );
my ($post_id) =
  $dbh->selectrow_array(
    q{SELECT p.post_id FROM posts p WHERE p.thread_id = ? LIMIT 1},
    undef, $thread_id );

subtest 'every kind has its default on both channels' => sub {
    my $rows = $functions->rows( 'notification_type_preferences',
        { user_id => $member } );
    is_deeply(
        [ map { [ @{$_}{qw(event_type channel enabled stored)} ] } @{$rows} ],
        [
            [ 'reply',      'in_app', 1, 0 ],
            [ 'reply',      'email',  0, 0 ],
            [ 'mention',    'in_app', 1, 0 ],
            [ 'mention',    'email',  1, 0 ],
            [ 'moderation', 'in_app', 1, 0 ],
            [ 'moderation', 'email',  1, 0 ],
        ],
        'inbox on for all, email for mentions and moderation notices'
    );
    my $page = $store->type_preferences_for_user($member);
    is_deeply(
        [ map { $_->{event_type} } @{$page} ],
        [qw(reply mention moderation)],
        'the settings page lists the kinds in order'
    );
    is_deeply(
        $page->[0]{channels},
        [
            {
                channel   => 'in_app',
                enabled   => 1,
                label_key => 'notifications.channel.in_app'
            },
            {
                channel   => 'email',
                enabled   => 0,
                label_key => 'notifications.channel.email'
            },
        ],
        'each with its channels'
    );
};

subtest 'a member stores their choices, checked first' => sub {
    is_deeply(
        $store->set_type_preferences(
            {
                user_id     => $member,
                preferences => [
                    { event_type => 'reply', channel => 'email', enabled => 1 },
                    {
                        event_type => 'mention',
                        channel    => 'in_app',
                        enabled    => 0
                    },
                ],
            }
        ),
        { ok => 1, status => 'ok', changed => 2 },
        'two choices stored'
    );
    is(
        $store->set_type_preferences(
            {
                user_id     => $member,
                preferences => [
                    { event_type => 'reply', channel => 'email', enabled => 1 }
                ],
            }
        )->{status},
        'unchanged',
        'the same choice again changes nothing'
    );
    is(
        $store->set_type_preferences(
            {
                user_id     => $member,
                preferences => [
                    { event_type => 'quote', channel => 'email', enabled => 1 }
                ],
            }
        )->{status},
        'invalid',
        'an unknown kind is refused'
    );
    is(
        $functions->row(
            'notification_set_type_preferences',
            {
                user_id     => $member,
                preferences => [
                    {
                        event_type => 'reply',
                        channel    => 'email',
                        enabled    => true
                    },
                    {
                        event_type => 'reply',
                        channel    => 'sms',
                        enabled    => true
                    },
                ],
                now => $NOW,
            }
        )->{status},
        'invalid',
        'and by the function, which writes none of the list'
    );
    is(
        $functions->row(
            'notification_set_type_preferences',
            {
                user_id     => '00000000-0000-4000-8000-000000000000',
                preferences => [],
                now         => $NOW,
            }
        )->{status},
        'not_found',
        'an unknown member is not found'
    );
    my %stored =
      map { ( "$_->{event_type}:$_->{channel}" => $_->{enabled} ) } @{
        $functions->rows( 'notification_type_preferences',
            { user_id => $member } )
      };
    is_deeply(
        [ @stored{qw(reply:email mention:in_app mention:email)} ],
        [ 1, 0, 1 ],
        'the stored choices read back'
    );
};

subtest 'the delivery plan joins channels, kinds and the account' => sub {
    is_deeply(
        $store->delivery_plan( $member, 'mention' ),
        {
            event_type    => 'mention',
            in_app        => 0,
            email         => 1,
            email_address => 'pref_member@example.test',
            locale        => 'en',
        },
        'a mention goes by email only, as chosen'
    );
    is_deeply(
        [
            @{ $store->delivery_plan( $member, 'review_rejected' ) }
              {qw(event_type in_app email)}
        ],
        [ 'moderation', 1, 1 ],
        'a review decision is a moderation notice'
    );
    is_deeply(
        [
            @{ $store->delivery_plan( $member, 'something_else' ) }
              {qw(event_type in_app email)}
        ],
        [ undef, 1, 0 ],
        'a type no control covers follows the in-app channel, never email'
    );
    is( $store->delivery_plan( $unverified, 'mention' )->{email},
        0, 'an unverified address gets no email' );
    $store->set_preference(
        {
            user_id          => $member,
            channel          => 'email',
            enabled          => 0,
            digest_frequency => 'daily'
        }
    );
    is( $store->delivery_plan( $member, 'mention' )->{email},
        0, 'the email channel switched off stops every kind' );
    $store->set_preference(
        {
            user_id          => $member,
            channel          => 'email',
            enabled          => 1,
            digest_frequency => 'daily'
        }
    );
};

my $dispatcher = GPForum::Service::Notification::Dispatcher->new(
    schema           => $schema,
    preference_store => $store,
);

subtest 'fanout follows the plan and queues the mail once' => sub {
    my $input = {
        notification_type => 'mention',
        recipient_user_id => $member,
        source_type       => 'post',
        source_id         => $post_id,
        payload           => {
            actor_id  => $actor,
            thread_id => $thread_id,
            post_id   => $post_id,
        },
    };
    is_deeply(
        $dispatcher->create_notification($input),
        {
            ok           => 0,
            skipped      => 'channel_disabled',
            channel      => 'in_app',
            email_queued => 1,
        },
        'a mention by email only skips the inbox and queues the mail'
    );
    $dispatcher->create_notification($input);
    is( _email_events($member), 1, 'a second delivery queues no second mail' );
    is(
        _count(
            q{SELECT count(*) FROM outbox_messages o}
              . q{ WHERE o.payload->>'event_type' = ?},
            $EMAIL_EVENT
        ),
        1,
        'the outbox holds the mail'
    );
    my ($payload) = $dbh->selectrow_array(
        q{SELECT payload::text FROM event_log WHERE event_type = ?},
        undef, $EMAIL_EVENT );
    unlike( $payload, qr/example[.]test/msx, 'the event carries no address' );

    my $reply = $dispatcher->create_notification(
        { %{$input}, notification_type => 'reply', idempotency_key => 'r:1' } );
    ok( $reply->{ok} && $reply->{email_queued},
        'a reply, on in both, reaches the inbox and queues a mail' );
    is( _email_events($member), 2, 'its own mail' );
    my $other = $dispatcher->create_notification(
        { %{$input}, recipient_user_id => $actor, idempotency_key => 'm:2' } );
    ok( $other->{ok} && $other->{email_queued},
        'another member with the defaults gets the mention both ways' );
    my $quiet = $dispatcher->create_notification(
        {
            %{$input},
            recipient_user_id => $actor,
            notification_type => 'reply',
            idempotency_key   => 'r:2'
        }
    );
    ok(
        $quiet->{ok} && !$quiet->{email_queued},
        'and a reply in the inbox only, by default'
    );
};

my $tokens =
  GPForum::Service::Notification::UnsubscribeToken->new(
    secrets => ['integration-secret'] );
my $transport = Email::Sender::Transport::Test->new;
my $handler   = GPForum::Worker::Handler::NotificationMail->new(
    mailer => GPForum::Service::Identity::Mailer->new(
        transport       => $transport,
        public_base_url => "$BASE/",
        from_address    => 'forum@example.test',
    ),
    preference_store => $store,
    renderer         => GPForum::Service::Notification::Renderer->new,
    tokens           => $tokens,
);

subtest 'the worker sends the mail with its one-click headers' => sub {
    my $event = {
        event_id       => 'e1',
        event_type     => $EMAIL_EVENT,
        domain_payload => {
            recipient_user_id => $member,
            notification_type => 'mention',
            source_type       => 'post',
            source_id         => $post_id,
            thread_id         => $thread_id,
            post_id           => $post_id,
        },
    };
    ok( $handler->handle($event)->{delivered}, 'the mail is sent' );
    my ($sent) = $transport->deliveries;
    my $email = $sent->{email};
    is( $email->get_header('To'),
        'pref_member@example.test', 'to the address read as it is sent' );
    like(
        $email->get_header('List-Unsubscribe'),
        qr{\A <\Q$BASE\E/unsubscribe/[\w.-]+> \z}msx,
        'with List-Unsubscribe'
    );
    is( $email->get_header('List-Unsubscribe-Post'),
        'List-Unsubscribe=One-Click', 'and List-Unsubscribe-Post' );
    my ($token) =
      $email->get_header('List-Unsubscribe') =~ m{/unsubscribe/([^>]+)>}msx;
    is_deeply(
        $tokens->verify($token),
        { user_id => $member, scope => 'mention' },
        'whose token stops mention email'
    );
    my $body = $email->get_body;
    like(
        $body,
        qr{\Q$BASE\E/t/\Q$thread_id\E}msx,
        'the body links the thread'
    );
    like( $body, qr{\Q$BASE\E/settings}msx, 'and the settings page' );

    $store->set_type_preferences(
        {
            user_id     => $member,
            preferences =>
              [ { event_type => 'mention', channel => 'email', enabled => 0 } ],
        }
    );
    ok( $handler->handle($event)->{skipped},
        'a mail queued before an unsubscribe is not sent' );
    is( scalar $transport->deliveries, 1, 'nothing more went out' );
    $store->set_type_preferences(
        {
            user_id     => $member,
            preferences =>
              [ { event_type => 'mention', channel => 'email', enabled => 1 } ],
        }
    );
};

subtest 'unsubscribing turns one kind or all email off, audited' => sub {
    is_deeply(
        $store->unsubscribe(
            { user_id => $member, scope => 'mention', via => 'one_click' }
        ),
        { ok => 1, status => 'ok', scope => 'mention' },
        'mention email is off'
    );
    is( $store->delivery_plan( $member, 'mention' )->{email},
        0, 'and the plan says so' );
    is(
        $store->unsubscribe( { user_id => $member, scope => 'mention' } )
          ->{status},
        'unchanged',
        'twice is no change'
    );
    is(
        $store->unsubscribe( { user_id => $actor, scope => 'reply' } )
          ->{status},
        'unchanged',
        'nor is a kind already off by default'
    );
    is(
        $store->unsubscribe( { user_id => $member, scope => 'bogus' } )
          ->{status},
        'invalid',
        'an unknown scope is invalid'
    );
    is(
        $store->unsubscribe( { user_id => $member, scope => 'all' } )->{status},
        'ok',
        'all notification email is off'
    );
    is( $store->delivery_plan( $member, 'moderation' )->{email},
        0, 'every kind with it' );
    is(
        _count(
            q{SELECT count(*) FROM audit_log}
              . q{ WHERE action = 'notification.email_unsubscribed'}
              . q{ AND target_id = ?},
            $member
        ),
        2,
        'each change audited, the no-changes not'
    );
    my ($metadata) =
      $dbh->selectrow_array( q{SELECT metadata->>'via' FROM audit_log}
          . q{ WHERE action = 'notification.email_unsubscribed'}
          . q{ AND metadata->>'scope' = 'mention'} );
    is( $metadata, 'one_click', 'with how it was made' );
};

subtest 'the export carries the choices' => sub {
    my $parts =
      $functions->row( 'portability_export_parts', { user_id => $member } )
      ->{document};
    is_deeply(
        [
            map {
                "$_->{event_type}:$_->{channel}:" . ( $_->{enabled} ? 1 : 0 )
            } @{ $parts->{notification_type_preferences} }
        ],
        [qw(mention:email:0 mention:in_app:0 reply:email:1)],
        'the member\'s stored choices'
    );
};

subtest 'the settings page and the unsubscribe link' => sub {
    my $test = _session($actor);
    $test->get_ok('/settings')
      ->status_is($HTTP_OK)
      ->element_exists('input[name="notification_type_reply_email"]');
    $test->element_exists_not(
        'input[name="notification_type_reply_email"][checked]')
      ->element_exists('input[name="notification_type_mention_email"][checked]')
      ->text_is( '#settings-notification-kind-moderation-heading' =>
          'Moderation notices' );
    my $dom  = $test->tx->res->dom;
    my $form = $dom->at('form.settings-form');
    my %fields =
      map { ( $_->attr('name') => $_->attr('value') ) }
      $form->find('input[type="hidden"]')->each;
    $test->post_ok(
        '/settings' => form => {
            %fields,
            notification_in_app_enabled         => 1,
            notification_email_enabled          => 1,
            notification_type_reply_in_app      => 1,
            notification_type_reply_email       => 1,
            notification_type_mention_in_app    => 1,
            notification_type_moderation_in_app => 1,
            notification_type_moderation_email  => 1,
        }
    )->status_is($HTTP_FOUND);
    my %saved =
      map { ( "$_->{event_type}:$_->{channel}" => $_->{enabled} ) } @{
        $functions->rows( 'notification_type_preferences',
            { user_id => $actor } )
      };
    is_deeply(
        [ @saved{qw(reply:email mention:email moderation:email)} ],
        [ 1, 0, 1 ],
        'the form saved each box'
    );

    my $secrets = $test->app->secrets;
    my $token =
      GPForum::Service::Notification::UnsubscribeToken->new(
        secrets => $secrets )->issue( $actor, 'reply' );
    my $guest = Test::Mojo->new('GPForum');
    $guest->get_ok("/unsubscribe/$token")->status_is($HTTP_OK);
    $guest->element_exists('input[name="scope"][value="reply"][checked]')
      ->element_exists('input[name="scope"][value="all"]');
    is( $store->delivery_plan( $actor, 'reply' )->{email},
        1, 'opening the link changed nothing' );
    $guest->post_ok( "/unsubscribe/$token" => form => { scope => 'reply' } )
      ->status_is($HTTP_FORBIDDEN);
    is( $store->delivery_plan( $actor, 'reply' )->{email},
        1, 'nor did a form without its CSRF token' );
    $guest->post_ok(
        "/unsubscribe/$token" => form => { 'List-Unsubscribe' => 'One-Click' } )
      ->status_is($HTTP_OK);
    is( $store->delivery_plan( $actor, 'reply' )->{email},
        0, 'the one-click POST stopped reply email' );

    my $page = Test::Mojo->new('GPForum');
    $page->get_ok("/unsubscribe/$token")->status_is($HTTP_OK);
    my $answer = $page->tx->res->dom;
    my $csrf   = $answer->at('input[name="csrf_token"]')->attr('value');
    $page->post_ok( "/unsubscribe/$token" => form =>
          { csrf_token => $csrf, scope => 'all' } )
      ->status_is($HTTP_OK)
      ->content_like(
        qr/no [ ] longer [ ] receive [ ] notification [ ] email/msx);
    is( $store->delivery_plan( $actor, 'moderation' )->{email},
        0, 'the button stopped all notification email' );

    $guest->get_ok("/unsubscribe/${token}x")->status_is($HTTP_MISSING);
    $guest->post_ok( '/unsubscribe/not.valid' => form =>
          { 'List-Unsubscribe' => 'One-Click' } )->status_is($HTTP_MISSING);
};

subtest 'one-click POSTs from one mail provider are limited per member' => sub {
    my $provider = Test::Mojo->new('GPForum');
    my $tokens   = GPForum::Service::Notification::UnsubscribeToken->new(
        secrets => $provider->app->secrets );
    my $one_click = { 'List-Unsubscribe' => 'One-Click' };
    my @members =
      map { _user( "pref_provider_$_", 1 ) } 1 .. $UNSUBSCRIBE_LIMIT + 1;
    my $answered = 0;
    for my $member (@members) {
        my $token = $tokens->issue( $member, 'mention' );
        $provider->post_ok( "/unsubscribe/$token" => form => $one_click );
        $answered++ if $provider->tx->res->code == $HTTP_OK;
    }
    is(
        $answered,
        scalar @members,
        'every member\'s one-click POST from the same address lands'
    );
    is( $store->delivery_plan( $members[-1], 'mention' )->{email},
        0, 'and stops their mail' );

    my $token = $tokens->issue( $members[0], 'mention' );
    for ( 2 .. $UNSUBSCRIBE_LIMIT ) {
        $provider->post_ok( "/unsubscribe/$token" => form => $one_click );
    }
    $provider->post_ok( "/unsubscribe/$token" => form => $one_click )
      ->status_is( $HTTP_TOO_MANY, 'one member\'s link is still limited' );
};

done_testing;

sub _email_events ($user_id) {
    return _count(
        q{SELECT count(*) FROM event_log WHERE event_type = ?}
          . q{ AND aggregate_id = ?},
        $EMAIL_EVENT, $user_id
    );
}

sub _count ( $sql, @binds ) {
    my ($count) = $dbh->selectrow_array( $sql, undef, @binds );

    return 0 + $count;
}

# A browser signed in as the user.
sub _session ($user_id) {
    my $test   = Test::Mojo->new('GPForum');
    my $routes = $test->app->routes;
    $routes->get('/__test/preference-session')->to(
        cb => sub ($c) {
            $c->session( user_id => $user_id );
            return $c->render( json => { ok => 1 } );
        }
    );
    $test->get_ok('/__test/preference-session')->status_is($HTTP_OK);

    return $test;
}

# A new active member, with a verified address when asked.
sub _user ( $name, $verified ) {
    my ($id) = $dbh->selectrow_array(
        q{INSERT INTO users (id, username, display_name, email_normalized,}
          . q{ password_hash, status, email_verified_at) VALUES}
          . q{ (gen_random_uuid(), ?, ?, ?, 'x', 'active',}
          . q{ CASE WHEN ?::boolean THEN now() END) RETURNING id},
        undef, $name, $name, "$name\@example.test", $verified ? 1 : 0
    );

    return $id;
}

1;
