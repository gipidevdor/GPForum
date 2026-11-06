# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;
use v5.40;
use Const::Fast;
use Carp qw(croak);
use Test::More;
use Test::Mojo;
use File::Temp   qw(tempdir);
use Digest::SHA  qw(sha256_hex);
use MIME::Base64 qw(encode_base64url);
use Mojo::JSON   qw(encode_json);
use lib 'lib';
use lib 't/lib';
use GPForum::Test::PushProvider;
use GPForum::Config;
use GPForum::Infrastructure::Id;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Service::Notification::Dispatcher;
use GPForum::Service::Notification::PreferenceStore;
use GPForum::Service::Notification::RecipientPolicy;
use GPForum::Service::Notification::Push::Keyring;
use GPForum::Service::Notification::Push::Store;
use GPForum::Service::Notification::Push::Worker;
use GPForum::Test::PgDatabase;

our $VERSION = '0.001';
const my $DEVICE_COUNT      => 5;
const my $CONCURRENCY       => 8;
const my $KEY_BYTES         => 32;
const my $HTTP_OK           => 200;
const my $HTTP_ACCEPTED     => 202;
const my $HTTP_INVALID      => 400;
const my $HTTP_UNAUTHORIZED => 401;
const my $HTTP_FORBIDDEN    => 403;

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'set GPFORUM_TEST_DSN for Web Push integration';
}
local $ENV{GPFORUM_MINION_ENABLED}            = 0;
local $ENV{GPFORUM_REALTIME_LISTENER_ENABLED} = 0;
my $database = GPForum::Test::PgDatabase->fresh( seed => 1 );
local $ENV{GPFORUM_DATABASE_DSN} = $database->dsn;
my $dbh       = $database->dbh;
my $schema    = $database->schema;
my $functions = GPForum::Infrastructure::SqlFunction->new( schema => $schema );
my $directory = tempdir( CLEANUP => 1 );
GPForum::Service::Notification::Push::Keyring->new( directory => $directory )
  ->generate;
local $ENV{GPFORUM_PUSH_ENABLED}       = 1;
local $ENV{GPFORUM_PUSH_KEY_DIRECTORY} = $directory;
local $ENV{GPFORUM_PUSH_CONTACT}       = 'mailto:ops@example.com';
my $config = GPForum::Config->from_environment;
my $store  = GPForum::Service::Notification::Push::Store->new(
    schema => $schema,
    config => $config
);
my $id = GPForum::Infrastructure::Id->new;
my ( $user, $session, $token )              = _member('push_member');
my ( $other, $other_session, $other_token ) = _member('push_other');
my $public = $store->public_config;
my $input  = {
    endpoint => 'https://fcm.googleapis.com/push/opaque-capability',
    keys     => {
        auth   => 'BTBZMqHH6r4Tts7J_aSIgg',
        p256dh =>
'BCVxsr7N_eNgVRqvHtD0zTZsEc6-VV-JvLexhqUzORcxaOzi6-AYWXvTBHm4bjyPjs7Vd8pZGH6SRpkNtoIAiw4'
    },
    key_id => $public->{key_id},
    kinds  => [qw(reply mention moderation message)]
};
my $device;

subtest 'receipt proof and account/session ownership precede activation' =>
  sub {
    my $registered = $store->register( $user, $session, $input );
    is( $registered->{status}, 'pending', 'registration needs proof' );
    ok( !exists $registered->{nonce}, 'HTTP response cannot bypass proof' );
    $device = $registered->{subscription_id};
    my ($sealed) = $dbh->selectrow_array(
'SELECT envelope FROM notification_push_subscriptions WHERE subscription_id=?',
        undef, $device
    );
    unlike( $sealed, qr/opaque-capability/msx,
        'capability URL encrypted in storage' );
    is( $store->register( $other, $other_session, $input )->{status},
        'conflict', 'another account cannot take the endpoint' );
    is(
        $store->register(
            $other,
            $other_session,
            {
                %{$input},
                endpoint =>
                  'https://FCM.GOOGLEAPIS.COM:443/push/opaque-capability'
            }
        )->{status},
        'conflict',
        'authority aliases cannot transfer an existing receiver'
    );
    my $challenge = _challenge($device);
    is( $store->confirm( $other, $other_session, $challenge )->{status},
        'invalid', 'wrong account cannot confirm' );
    is(
        $store->confirm( $user, $session,
            { %{$challenge}, nonce => encode_base64url( 'x' x $KEY_BYTES ) } )
          ->{status},
        'invalid',
        'wrong proof refused'
    );
    is( $store->confirm( $user, $session, $challenge )->{status},
        'active', 'receiver proof activates' );
    is( $store->confirm( $user, $session, $challenge )->{status},
        'invalid', 'proof replay refused' );
    my $export =
      $functions->row( 'portability_export_parts', { user_id => $user } )
      ->{document};
    is( scalar @{ $export->{push_devices} },
        1, 'portability includes device consent' );
    is_deeply(
        [ sort keys %{ $export->{push_devices}[0] } ],
        [qw(active created_at kinds subscription_id)],
        'export omits capability URLs, keys and receipt secrets'
    );
    is( $store->revoke( $other, $device )->{status},
        'revoked', 'revocation does not disclose another device' );
    is( scalar @{ $store->devices($user) },
        1, 'other member did not revoke it' );
  };

my ($post) = $dbh->selectrow_array(
q{SELECT p.post_id FROM posts p JOIN threads t ON t.thread_id=p.thread_id JOIN categories c ON c.category_id=t.category_id JOIN spaces s ON s.space_id=c.space_id WHERE p.deleted_at IS NULL AND p.moderation_state='visible' AND t.deleted_at IS NULL AND t.moderation_state='visible' AND p.visibility='public' AND t.visibility='public' AND c.visibility='public' AND s.visibility='public' LIMIT 1}
);
my $dispatcher = GPForum::Service::Notification::Dispatcher->new(
    schema           => $schema,
    preference_store =>
      GPForum::Service::Notification::PreferenceStore->new( schema => $schema ),
    permission_engine =>
      GPForum::Service::Notification::RecipientPolicy->new( schema => $schema )
);

subtest
'Push is independent of email and inbox, transactional, coalesced and replay safe'
  => sub {
    $dbh->do(
q{INSERT INTO notification_preferences(user_id,channel,enabled) VALUES (?,'in_app',false),(?,'email',false)},
        undef, $user, $user
    );
    my $plan = $functions->row( 'notification_delivery_plan',
        { user_id => $user, notification_type => 'reply' } );
    ok( $plan->{web_push} && !$plan->{email} && !$plan->{in_app},
        'third channel independently enabled' );
    my $request = {
        recipient_user_id => $user,
        notification_type => 'reply',
        source_type       => 'post',
        source_id         => $post,
        payload           => { actor_id => $other },
        idempotency_key   => 'push-one'
    };
    my $answer = $dispatcher->create_notification($request);
    ok( $answer->{web_push_queued}, 'direct delivery enqueued' );
    is(
        _count(
q{SELECT count(*) FROM notification_push_deliveries WHERE kind='alert'}
        ),
        1,
        'one durable job'
    );
    $dispatcher->create_notification($request);
    is(
        _count(
q{SELECT count(*) FROM notification_push_deliveries WHERE kind='alert'}
        ),
        1,
        'same notification is not enqueued twice'
    );
    $schema->txn_begin;
    $dispatcher->create_notification(
        { %{$request}, idempotency_key => 'push-rolled-back' } );
    $schema->txn_rollback;
    is(
        _count(
q{SELECT count(*) FROM notification_push_deliveries WHERE kind='alert'}
        ),
        1,
        'rollback leaves no Push job'
    );
    my $call = $dispatcher->delivery_call(
        { %{$request}, idempotency_key => 'push-batched' },
        '2026-11-06T00:00:00Z' );
    my $rows = $functions->rows(
        'notification_fanout_deliver',
        {
            recipients => [
                {
                    recipient_user_id => $user,
                    %{$call},
                    in_app   => 0,
                    email    => 0,
                    web_push => 1
                }
            ]
        }
    );
    is( $rows->[0]{outcome}, 'skipped', 'inbox remains disabled' );
    is(
        _count(
q{SELECT count(*) FROM notification_push_deliveries WHERE kind='alert' AND state='pending'}
        ),
        1,
        'one pending alert per device'
    );
    is(
        _count(
q{SELECT count(*) FROM notification_push_deliveries WHERE kind='alert' AND state='cancelled'}
        ),
        1,
        'older alert coalesced'
    );
  };

subtest
  'worker rechecks readability and records acceptance separately from receipt'
  => sub {
    my $provider = GPForum::Test::PushProvider->new;
    my $worker   = GPForum::Service::Notification::Push::Worker->new(
        store     => $store,
        transport => $provider
    );
    my $result = _run($worker);
    is( $result->{accepted},         1, 'provider acceptance' );
    is( scalar @{ $provider->sent }, 1, 'only the latest alert sent' );
    is(
        _count(
q{SELECT count(*) FROM notification_push_deliveries WHERE state='accepted'}
        ),
        1,
        'stored as accepted'
    );
    my ($job) = $dbh->selectrow_array(
q{SELECT delivery_id FROM notification_push_deliveries WHERE state='accepted'}
    );
    ok(
        !$functions->row(
            'notification_push_finish',
            {
                delivery_id => $job,
                lease_id    => $id->uuid,
                outcome     => 'accepted',
                retry_after => 0
            }
        )->{changed},
        'another lease cannot acknowledge'
    );
    $dispatcher->create_notification(
        {
            recipient_user_id => $user,
            notification_type => 'reply',
            source_type       => 'post',
            source_id         => $post,
            payload           => { actor_id => $other },
            idempotency_key   => 'push-before-hide'
        }
    );
    $dbh->do( q{UPDATE posts SET moderation_state='hidden' WHERE post_id=?},
        undef, $post );
    my $stopped = _run($worker);
    is( $stopped->{cancelled}, 1, 'hidden content cancels notification' );
    is( scalar @{ $provider->sent },
        1, 'no HTTP send after the read permission was lost' );
    $dbh->do( q{UPDATE posts SET moderation_state='visible' WHERE post_id=?},
        undef, $post );
  };

subtest
  'HTTP writes require authentication, origin, CSRF and endpoint ownership' =>
  sub {
    my $browser = _browser( $user, $session, $token );
    $browser->get_ok('/push/configuration')
      ->status_is($HTTP_OK)
      ->json_is( '/enabled', 1 );
    my $configuration = $browser->tx->res->json;
    my $csrf          = $configuration->{csrf_token};
    my $body          = { csrf_token => $csrf, payload => encode_json($input) };
    $browser->post_ok(
        '/push/register' => { Origin => 'https://evil.example' } => form =>
          $body )->status_is($HTTP_FORBIDDEN);
    $browser->post_ok(
        '/push/register' => { 'Sec-Fetch-Site' => 'same-origin' } => form =>
          { payload => encode_json($input) } )->status_is($HTTP_FORBIDDEN);
    $browser->post_ok(
        '/push/register' => { 'Sec-Fetch-Site' => 'same-origin' } => form => {
            %{$body},
            payload => encode_json(
                { %{$input}, endpoint => 'https://127.0.0.1/push' }
            )
        }
    )->status_is($HTTP_INVALID);
    $browser->post_ok(
        '/push/register' => { 'Sec-Fetch-Site' => 'same-origin' } => form =>
          $body )->status_is($HTTP_ACCEPTED);
    my $registered_reply = $browser->tx->res->json;
    $device = $registered_reply->{subscription_id};
    my $challenge = _challenge($device);
    $browser->post_ok(
        '/push/confirm' => { 'Sec-Fetch-Site' => 'same-origin' } => form =>
          { csrf_token => $csrf, payload => encode_json($challenge) } )
      ->status_is($HTTP_OK)
      ->json_is( '/status', 'active' );
    $browser->get_ok('/push-worker.js')->status_is($HTTP_OK);
    $browser->header_is( 'Service-Worker-Allowed', '/push/' )
      ->header_is( 'Cache-Control', 'private, no-cache' );
    $browser->header_like( 'Content-Security-Policy',
        qr/default-src[ ]'none'/msx );
    unlike( $browser->tx->res->body,
        qr/opaque-capability/msx, 'worker is account-independent' );
    my $anonymous = Test::Mojo->new('GPForum');
    $anonymous->get_ok('/push/configuration')->status_is($HTTP_UNAUTHORIZED);
  };

subtest
  'logout revokes the device and queued jobs in the same database transaction'
  => sub {
    $dispatcher->create_notification(
        {
            recipient_user_id => $user,
            notification_type => 'reply',
            source_type       => 'post',
            source_id         => $post,
            payload           => { actor_id => $other },
            idempotency_key   => 'push-before-logout'
        }
    );
    my $provider = GPForum::Test::PushProvider->new(
        on_prepare => sub {
            $dbh->do( 'UPDATE sessions SET revoked_at=now() WHERE session_id=?',
                undef, $session );
        }
    );
    my $worker = GPForum::Service::Notification::Push::Worker->new(
        store     => $store,
        transport => $provider
    );
    my $result = _run($worker);
    is( $result->{selected}, 1,
        'job claimed before session revocation during peer preparation' );
    is( scalar @{ $provider->sent },
        0, 'fresh authorization stops HTTP after revocation' );
    is( scalar @{ $store->devices($user) }, 0, 'device removed' );
    is( _count('SELECT count(*) FROM notification_push_deliveries'),
        0, 'all device jobs removed' );
    is( _run($worker)->{selected}, 0, 'nothing claimable afterward' );

  };

subtest 'claim bounds, lease ownership and Retry-After do not extend expiry' =>
  sub {
    for my $n ( 1 .. $DEVICE_COUNT ) {
        my $registered = $store->register(
            $other,
            $other_session,
            {
                %{$input},
                endpoint => "https://fcm.googleapis.com/push/device-$n"
            }
        );
        is( $registered->{status}, 'pending', 'pending device' );
    }
    my ( $one, $two ) = ( $id->uuid, $id->uuid );
    my $first = $functions->rows( 'notification_push_claim',
        { lease_id => $one, limit => $CONCURRENCY, per_provider => 2 } );
    my $other_claim = $functions->rows( 'notification_push_claim',
        { lease_id => $two, limit => $CONCURRENCY, per_provider => 2 } );
    is( scalar @{$first}, 2, 'first worker respects provider concurrency' );
    is( scalar @{$other_claim}, 2, 'second worker gets different ready jobs' );
    my %claimed = map { $_->{delivery_id} => 1 } @{$first};
    ok( !( grep { $claimed{ $_->{delivery_id} } } @{$other_claim} ),
        'claims do not overlap' );
    my $retry = $functions->row(
        'notification_push_finish',
        {
            delivery_id => $first->[1]{delivery_id},
            lease_id    => $one,
            outcome     => 'retry',
            retry_after => 1
        }
    );
    is( $retry->{outcome}, 'retry',
        'retry counter uses the public delivery outcome' );
    my $job = $first->[0]{delivery_id};
    $dbh->do(
q{UPDATE notification_push_deliveries SET expires_at=now()+interval '1 second' WHERE delivery_id=?},
        undef, $job
    );
    ok(
        $functions->row(
            'notification_push_finish',
            {
                delivery_id => $job,
                lease_id    => $one,
                outcome     => 'retry',
                retry_after => 180
            }
        )->{changed},
        'owned outcome recorded'
    );
    my ($state) = $dbh->selectrow_array(
        'SELECT state FROM notification_push_deliveries WHERE delivery_id=?',
        undef, $job );
    is( $state, 'failed', 'expired retry is terminal' );
    $dbh->do( q{UPDATE users SET status='deleted',deleted_at=now() WHERE id=?},
        undef, $other );
    is( _count('SELECT count(*) FROM notification_push_subscriptions'),
        0, 'account deletion removes receiver secrets' );
    is( _count('SELECT count(*) FROM notification_push_deliveries'),
        0, 'and its queue' );
  };

subtest
  'device settings connect consent and revocation to the HTTP workflow' => sub {
    my ( $gui_user, $gui_session, $gui_token ) = _member('push_gui');
    my $browser = _browser( $gui_user, $gui_session, $gui_token );
    $browser->get_ok('/settings')->status_is($HTTP_OK);
    my $page = $browser->tx->res->dom;
    ok(
        $page->at('link[rel="manifest"][href="/site.webmanifest"]'),
        'GUI exposes a standalone installation manifest'
    );
    $browser->element_exists('[data-push-settings] [data-push-enable]')
      ->element_exists('[data-push-settings] [data-push-disable]');
    $browser->get_ok('/site.webmanifest')->status_is($HTTP_OK);
    $browser->header_is( 'Content-Type', 'application/manifest+json' );
    $browser->json_is( '/display', 'standalone' )
      ->json_is( '/icons/0/src', 'icon.svg' );
    $browser->get_ok('/push/configuration')->status_is($HTTP_OK);
    my $configuration = $browser->tx->res->json;
    my $csrf          = $configuration->{csrf_token};
    my $headers       = { 'Sec-Fetch-Site' => 'same-origin' };
    $browser->post_ok(
        '/push/register' => $headers => form => {
            csrf_token => $csrf,
            payload    => encode_json(
                {
                    %{$input},
                    endpoint => 'https://fcm.googleapis.com/push/gui-device'
                }
            )
        }
    )->status_is($HTTP_ACCEPTED);
    my $device_reply = $browser->tx->res->json;
    my $device_id    = $device_reply->{subscription_id};
    $browser->post_ok(
        '/push/confirm' => $headers => form => {
            csrf_token => $csrf,
            payload    => encode_json( _challenge($device_id) )
        }
    )->status_is($HTTP_OK);
    is( scalar @{ $store->devices($gui_user) },
        1, 'GUI push consent activates the owned device' );
    $browser->post_ok(
        '/push/revoke' => $headers => form => {
            csrf_token => $csrf,
            payload    => encode_json( { subscription_id => $device_id } )
        }
    )->status_is($HTTP_OK)->json_is( '/status', 'revoked' );
    is( scalar @{ $store->devices($gui_user) },
        0, 'GUI push revocation removes the device' );
  };

done_testing();

sub _member ($name) {
    my $new_user    = $id->uuid;
    my $new_session = $id->uuid;
    my $new_token   = $id->uuid;
    $dbh->do(
q{INSERT INTO users(id,username,display_name,email_normalized,password_hash,status,email_verified_at) VALUES(?,?,?,?,'x','active',now())},
        undef, $new_user, $name, $name, "$name\@example.test"
    );
    $dbh->do(
q{INSERT INTO sessions(session_id,user_id,session_hash,expires_at) VALUES(?,?,?,now()+interval '1 day')},
        undef, $new_session, $new_user, sha256_hex($new_token)
    );
    return ( $new_user, $new_session, $new_token );
}
sub _count ($sql) { return 0 + $dbh->selectrow_array($sql); }

sub _challenge ($device) {
    my ($sealed) = $dbh->selectrow_array(
'SELECT activation FROM notification_push_deliveries WHERE subscription_id=?',
        undef, $device
    );
    return $store->crypto->unseal( $store->secrets->storage,
        "activation:$device", $sealed );
}

sub _run ($worker) {
    my ( $result, $failure );
    my $pending = $worker->dispatch_p;
    $pending = $pending->then( sub ($value) { $result = $value; return; } );
    $pending->catch( sub ($error) { $failure = $error; return; } )->wait;
    croak $failure if defined $failure;
    return $result;
}

sub _browser ( $user, $session, $token ) {
    my $browser = Test::Mojo->new('GPForum');
    my $routes  = $browser->app->routes;
    $routes->get('/__push_session')->to(
        cb => sub ($c) {
            $c->session(
                user_id       => $user,
                session_id    => $session,
                session_token => $token
            );
            $c->render( text => 'session' );
        }
    );
    $browser->get_ok('/__push_session')->status_is($HTTP_OK);
    return $browser;
}

1;
