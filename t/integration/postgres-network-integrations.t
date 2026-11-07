# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;
use v5.40;
use Const::Fast;
use Test::More;
use Test::Exception;
use Carp qw(croak);
use Test::Mojo;
use Mojo::Message::Response;
use Mojo::JSON  qw(encode_json);
use Digest::SHA qw(sha256_hex);
use Crypt::PK::RSA;
use Crypt::JWT qw(encode_jwt);
use lib 'lib';
use lib 't/lib';
use GPForum::Config;
use GPForum::Command::AdminBootstrap;
use GPForum::Infrastructure::Id;
use GPForum::Infrastructure::Row;
use GPForum::Infrastructure::ResultRow;
use GPForum::Service::Integration::Announcements;
use GPForum::Service::Integration::Syndication;
use GPForum::Service::Identity::OpenID;
use GPForum::Service::Identity::SecondFactor;
use GPForum::Service::Identity::CredentialStore;
use GPForum::Service::Identity::SessionStore;
use GPForum::Service::Password;
use GPForum::Test::PgDatabase;
use GPForum::Test::ExternalSecondFactor;
use GPForum::Test::NetworkClient;
use GPForum::Test::GuiDriver;
use Mojo::URL;
use GPForum::Test::PostgresHarness;

our $VERSION = '0.001';
const my $FRACTIONAL_RETRY_SECONDS => 125.1;
const my $HTTP_FOUND               => 302;
const my $HTTP_CLIENT_ERROR        => 400;
const my $HTTP_FORBIDDEN           => 403;
const my $HTTP_OK                  => 200;
const my $HTTP_RATE_LIMITED        => 429;
const my $HTTP_UNAUTHORIZED        => 401;
const my $PASSWORD_MEMORY_MIB      => 19;
const my $ROUNDED_RETRY_SECONDS    => 126;
const my $RSA_EXPONENT             => 65_537;
const my $RSA_KEY_BYTES            => 256;
const my $TOKEN_SECONDS            => 300;
const my $WEBHOOK_TOKEN_LENGTH     => 40;

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'PostgreSQL required';
}
my $database = GPForum::Test::PgDatabase->fresh( seed => 1 );
my $schema   = $database->schema;
my $dbh      = $database->dbh;
my $ids      = GPForum::Infrastructure::Id->new;
my ( $category, $author ) = $dbh->selectrow_array(
q{SELECT t.category_id,t.author_user_id FROM threads t JOIN categories c USING(category_id) JOIN spaces s USING(space_id) WHERE t.visibility='public' AND c.visibility='public' AND s.visibility='public' AND t.deleted_at IS NULL LIMIT 1}
);
my $actor    = $ids->uuid;
my $password = GPForum::Service::Password->new(
    memory_mib => $PASSWORD_MEMORY_MIB,
    iterations => 2
);
my $secret = 'Local password for integration tests 123';
$dbh->do(
q{INSERT INTO users(id,username,display_name,email_normalized,password_hash,status,email_verified_at) VALUES(?,'integration_admin','Integration Admin','integration-admin@example.org',?,'active',now())},
    undef, $actor, $password->hash_password($secret)
);
my $credentials =
  GPForum::Service::Identity::CredentialStore->new( schema => $schema );
$credentials->create_password_credential(
    { user_id => $actor, secret_hash => $password->hash_password($secret) } );
GPForum::Test::PostgresHarness::quietly(
    sub {
        return GPForum::Command::AdminBootstrap->new( schema => $schema )
          ->run( 'grant', '--user-id', $actor );
    }
);
my $topic = sub {
    my $id = $ids->uuid;
    $dbh->do(
q{INSERT INTO threads(thread_id,category_id,author_user_id,title,slug) VALUES(?,?,?,'Public topic @everyone','public-topic')},
        undef, $id, $category, $author
    );
    return $id;
};
my $config = GPForum::Config->new(
    public_base_url => 'https://forum.example.org/base',
    discord_webhook => 'https://discord.com/api/webhooks/123456789012345678/'
      . ( 'A' x $WEBHOOK_TOKEN_LENGTH ),
    syndication_sources => ['https://example.org/feed']
);
my $client = GPForum::Test::NetworkClient->new(
    responses => [ _json( $HTTP_OK, { id => '987654321098765432' } ) ] );
my $announcements = GPForum::Service::Integration::Announcements->new(
    policy_available => 1,
    schema           => $schema,
    config           => $config,
    client           => $client
);
$announcements->policy_available(0);
throws_ok { $announcements->deliver( $ids->uuid ) } qr/policy[ ]unavailable/msx,
  'configuration outage blocks delivery before database claims or HTTP';
is( scalar @{ $client->calls }, 0, 'policy outage has no external effects' );
$announcements->policy_available(1);
my $thread    = $topic->();
my $requested = $announcements->request( $actor, $thread );
is( $requested->{status}, 'queued', 'staff explicitly queues public topic' );
is( $announcements->request( $actor, $thread )->{status},
    'unchanged', 'selection deduplicates by topic and target' );
is( $announcements->deliver( $requested->{announcement_id} )->{status},
    'sent', 'confirmed Discord response is durable' );
is( $announcements->deliver( $requested->{announcement_id} )->{status},
    'sent', 'event replay sends nothing twice' );
is( scalar @{ $client->calls }, 1, 'one remote call' );
is_deeply(
    $client->calls->[0]{input}{json}{allowed_mentions},
    { parse => [] },
    'untrusted title cannot ping users'
);
like(
    $client->calls->[0]{input}{json}{content},
    qr{https://forum[.]example[.]org/base/t/}msx,
    'canonical mount path retained'
);
ok(
    !exists $client->calls->[0]{input}{json}{embeds},
    'no private post body or embeds sent'
);
my $hidden = $topic->();
my $held   = $announcements->request( $actor, $hidden );
$dbh->do( q{UPDATE threads SET visibility='private' WHERE thread_id=?},
    undef, $hidden );
is( $announcements->deliver( $held->{announcement_id} )->{status},
    'cancelled', 'privacy change cancels queued delivery' );
is( scalar @{ $client->calls }, 1,
    'cancelled delivery has no external effect' );
my $limited = $announcements->request( $actor, $topic->() );
push @{ $client->responses },
  _json( $HTTP_RATE_LIMITED, { retry_after => $FRACTIONAL_RETRY_SECONDS } ),
  _json( $HTTP_OK,           { id          => '123456789012345679' } );
my $failure;
try { $announcements->deliver( $limited->{announcement_id} ); } catch ($error) {
    $failure = $error;
};
isa_ok( $failure, 'GPForum::X::RateLimited' );
is( $failure->retry_after, $ROUNDED_RETRY_SECONDS,
    'provider delay rounded upward' );
is( $announcements->deliver( $limited->{announcement_id} )->{status},
    'sent', 'definite rate-limit refusal retries' );
my $ambiguous = $announcements->request( $actor, $topic->() );
is( $announcements->deliver( $ambiguous->{announcement_id} )->{status},
    'uncertain', 'response loss becomes visible uncertain delivery' );
my $calls = scalar @{ $client->calls };
is( $announcements->deliver( $ambiguous->{announcement_id} )->{status},
    'uncertain', 'uncertain outcome never automatically resends' );
is( scalar @{ $client->calls }, $calls, 'no duplicate after response loss' );
is( $announcements->request( $author, $topic->() )->{status},
    'refused', 'ordinary author cannot queue external announcements' );

my $retried = $announcements->retry_checked(
    {
        actor_user_id   => $actor,
        announcement_id => $ambiguous->{announcement_id},
        checked         => '0',
        reason          => 'Remote message absent'
    }
);
is( $retried->{status}, 'refused',
    'uncertain delivery needs explicit operator confirmation' );
is(
    $announcements->retry_checked(
        {
            actor_user_id   => $actor,
            announcement_id => $ambiguous->{announcement_id},
            checked         => '1',
            reason          => 'Verified absent in Discord'
        }
    )->{status},
    'queued',
    'checked recovery creates a new outbox event'
);
push @{ $client->responses }, _json( $HTTP_OK, { id => '123456789012345680' } );
is( $announcements->deliver( $ambiguous->{announcement_id} )->{status},
    'sent', 'explicitly reviewed retry completes' );

my $rss =
'<rss><channel><item><guid>one</guid><title>Review this source</title><link>https://example.org/article</link></item><item><guid>two</guid><title>Duplicate link</title><link>https://example.org/article</link></item></channel></rss>';
my $feed_response =
  Mojo::Message::Response->new( code => $HTTP_OK )->body($rss);
$feed_response->headers->content_type('application/rss+xml')->etag('"feed-v1"');
my $feed_client = GPForum::Test::NetworkClient->new(
    responses => [ $feed_response, $feed_response ] );
my $feeds = GPForum::Service::Integration::Syndication->new(
    policy_available => 1,
    schema           => $schema,
    config           => $config,
    client           => $feed_client
);
is( $feeds->poll('https://example.org/feed')->{created},
    1, 'duplicate URLs stage once' );
is(
    $dbh->selectrow_array(
        q{SELECT count(*) FROM integration_feed_items WHERE status='pending'}),
    1,
    'import remains unpublished'
);
throws_ok { $feeds->poll('https://evil.example.org/feed') }
qr/not[ ]authorized/msx, 'unapproved source cannot be fetched';
throws_ok { $feeds->poll('https://example.org/feed') }
qr/polling[ ]interval/msx, 'source fetch rate enforced in PostgreSQL';
$dbh->do(
q{UPDATE integration_feed_sources SET next_fetch_at=now()-interval '1 second'}
);
is( $feeds->poll('https://example.org/feed')->{created},
    0, 'stable ids and URLs remain deduplicated' );
is( $feed_client->calls->[1]{input}{headers}{'If-None-Match'},
    '"feed-v1"', 'conditional fetch uses saved entity tag' );
my $item =
  $dbh->selectrow_array('SELECT item_id FROM integration_feed_items LIMIT 1');
is(
    $feeds->decide(
        { item_id => $item, actor_user_id => $actor, decision => 'rejected' },
        sub { croak 'must not publish rejected content' } )->{status},
    'ok',
    'staff rejection is durable'
);
is(
    $dbh->selectrow_array(
        q{SELECT status FROM integration_feed_items WHERE item_id=?},
        undef, $item
    ),
    'rejected',
    'rejection retained to prevent reimport'
);

my $publish_item = $ids->uuid;
$feeds->functions->row(
    'integration_feed_stage',
    {
        item          => $publish_item,
        source_hash   => sha256_hex('https://example.org/feed'),
        identity_hash => sha256_hex('publishable-entry'),
        url_hash      => sha256_hex('https://example.org/second-article'),
        title         => 'An approved feed link',
        url           => 'https://example.org/second-article'
    }
);
my $publisher_called = 0;
$feeds->policy_available(0);
throws_ok {
    $feeds->decide(
        {
            item_id       => $publish_item,
            actor_user_id => $actor,
            decision      => 'published',
            category_id   => $category
        },
        sub { $publisher_called++; return { ok => 0 }; }
    );
}
qr/policy[ ]unavailable/msx, 'policy outage refuses import decisions';
is( $publisher_called, 0, 'policy outage cannot invoke publication' );
$feeds->policy_available(1);
is(
    $feeds->decide(
        {
            item_id       => $publish_item,
            actor_user_id => $author,
            decision      => 'published',
            category_id   => $category
        },
        sub { $publisher_called++; return { ok => 0 }; }
    )->{status},
    'not_found',
    'ordinary member cannot approve an import'
);
is( $publisher_called, 0,
    'unauthorized review never invokes forum publication' );

my $oidc_config = GPForum::Config->new(
    public_base_url             => 'https://forum.example.org/base',
    oidc_issuer                 => 'https://login.example.org',
    oidc_authorization_endpoint => 'https://login.example.org/authorize',
    oidc_token_endpoint         => 'https://login.example.org/token',
    oidc_jwks_uri               => 'https://login.example.org/keys',
    oidc_client_id              => 'forum',
    oidc_client_secret          => 'confidential-test-client-secret',
    oidc_signing_algorithm      => 'RS256'
);
my $rsa = Crypt::PK::RSA->new->generate_key( $RSA_KEY_BYTES, $RSA_EXPONENT );
my $key = $rsa->export_key_jwk( 'public', 1 );
$key->{kid} = 'fixture';
my $keys        = { keys => [$key] };
my $oidc_client = GPForum::Test::NetworkClient->new;
my $second_factor =
  GPForum::Service::Identity::SecondFactor->new( schema => $schema );
my $oidc = GPForum::Service::Identity::OpenID->new(
    policy_available => 1,
    schema           => $schema,
    config           => $oidc_config,
    client           => $oidc_client,
    password         => $password,
    second_factor    => $second_factor
);
is(
    $oidc->callback_url,
    'https://forum.example.org/base/auth/oidc/callback',
    'OIDC callback is pinned to configured mount'
);
is(
    $oidc->begin( { actor_user_id => $actor, password => 'wrong' } )->{status},
    'refused',
    'linking requires local password'
);
my $link = $oidc->begin( { actor_user_id => $actor, password => $secret } );
is( $link->{status}, 'redirect', 'verified local member begins linking' );
like(
    $link->{url},
    qr/code_challenge_method=S256/msx,
    'PKCE challenge required'
);
my $reply = sub ( $flow, $subject = 'provider-subject' ) {
    my $jwt = encode_jwt(
        key           => $rsa,
        alg           => 'RS256',
        extra_headers => { kid => 'fixture' },
        payload       => {
            iss            => 'https://login.example.org',
            aud            => 'forum',
            sub            => $subject,
            nonce          => $flow->{nonce},
            iat            => time,
            exp            => time + $TOKEN_SECONDS,
            auth_time      => time,
            email          => 'integration-admin@example.org',
            email_verified => 1
        }
    );
    push @{ $oidc_client->responses }, _json( $HTTP_OK, { id_token => $jwt } ),
      _json( $HTTP_OK, $keys );
};
$reply->( $link->{flow} );
is(
    $oidc->complete(
        {
            flow          => $link->{flow},
            state         => $link->{flow}{state},
            code          => 'authorization-code',
            actor_user_id => $actor
        }
    )->{status},
    'linked',
    'verified subject explicitly binds to local member'
);
is(
    $oidc->complete(
        {
            flow          => $link->{flow},
            state         => $link->{flow}{state},
            code          => 'authorization-code',
            actor_user_id => $actor
        }
    )->{status},
    'refused',
    'browser state is consumed once'
);
my $login = $oidc->begin;
$reply->( $login->{flow} );
my $signed = $oidc->complete(
    {
        flow            => $login->{flow},
        state           => $login->{flow}{state},
        code            => 'new-code',
        request_address => '127.0.0.1',
        user_agent      => 'test'
    }
);
ok(
    $signed->{ok} && $signed->{session_id},
    'linked identity opens ordinary server session'
);
is( $signed->{user_id}, $actor, 'identity maps by issuer and subject' );
my $foreign = $oidc->begin;
$reply->( $foreign->{flow}, 'unlinked-subject' );
is(
    $oidc->complete(
        {
            flow  => $foreign->{flow},
            state => $foreign->{flow}{state},
            code  => 'different-subject'
        }
    )->{status},
    'unlinked',
    'matching verified email never links or registers an account'
);
my $mfa_login = $oidc->begin;
$reply->( $mfa_login->{flow} );
$oidc->second_factor( GPForum::Test::ExternalSecondFactor->new );
is(
    $oidc->complete(
        {
            flow  => $mfa_login->{flow},
            state => $mfa_login->{flow}{state},
            code  => 'mfa-code'
        }
    )->{status},
    'second_factor',
    'external authentication cannot bypass local MFA'
);
$oidc->second_factor($second_factor);
is(
    $oidc->remove_link(
        {
            actor_user_id => $actor,
            password      => $secret,
            session_id    => $signed->{session_id}
        }
    )->{status},
    'unlinked',
    'fresh local proof can unlink'
);
is(
    $dbh->selectrow_array(
        q{SELECT count(*) FROM oidc_account_links WHERE user_id=?},
        undef, $actor
    ),
    0,
    'binding removed'
);
is(
    $dbh->selectrow_array(
q{SELECT count(*) FROM sessions WHERE session_id=? AND revoked_at IS NULL},
        undef,
        $signed->{session_id}
    ),
    1,
    'current local session preserved'
);
my $again = $oidc->begin( { actor_user_id => $actor, password => $secret } );
$reply->( $again->{flow} );
is(
    $oidc->complete(
        {
            flow          => $again->{flow},
            state         => $again->{flow}{state},
            code          => 'relink',
            actor_user_id => $actor
        }
    )->{status},
    'linked',
    'local owner can explicitly relink'
);
my $credential_id = GPForum::Infrastructure::Row->column(
    $credentials->active_password_credential($actor), 'id' );
$dbh->do(
    q{UPDATE credentials SET revoked_at=greatest(now(),created_at) WHERE id=?},
    undef, $credential_id
);
my $after_unlink = $oidc->begin;
$reply->( $after_unlink->{flow} );
is(
    $oidc->complete(
        {
            flow  => $after_unlink->{flow},
            state => $after_unlink->{flow}{state},
            code  => 'after-unlink'
        }
    )->{status},
    'unlinked',
    'password recovery invalidates a previously linked identity'
);

local $ENV{GPFORUM_DATABASE_DSN}              = $database->dsn;
local $ENV{GPFORUM_MINION_ENABLED}            = 0;
local $ENV{GPFORUM_REALTIME_LISTENER_ENABLED} = 0;
local $ENV{GPFORUM_PUBLIC_BASE_URL}           = $config->public_base_url;
local $ENV{GPFORUM_DISCORD_WEBHOOK}           = $config->discord_webhook;
local $ENV{GPFORUM_SYNDICATION_SOURCES}       = 'https://example.org/feed';
local $ENV{GPFORUM_OIDC_ISSUER}               = $oidc_config->oidc_issuer;
local $ENV{GPFORUM_OIDC_AUTHORIZATION_ENDPOINT} =
  $oidc_config->oidc_authorization_endpoint;
local $ENV{GPFORUM_OIDC_TOKEN_ENDPOINT} = $oidc_config->oidc_token_endpoint;
local $ENV{GPFORUM_OIDC_JWKS_URI}       = $oidc_config->oidc_jwks_uri;
local $ENV{GPFORUM_OIDC_CLIENT_ID}      = $oidc_config->oidc_client_id;
local $ENV{GPFORUM_OIDC_CLIENT_SECRET}  = $oidc_config->oidc_client_secret;
local $ENV{GPFORUM_OIDC_SIGNING_ALGORITHM} =
  $oidc_config->oidc_signing_algorithm;
my $t = Test::Mojo->new('GPForum');
$t->get_ok('/admin/integrations')->status_is($HTTP_UNAUTHORIZED);
my $routes = $t->app->routes;
$routes->get('/__test/integration-session/:id')->to(
    cb => sub ($c) {
        $c->session( user_id => $c->param('id') );
        return $c->render( text => 'ok' );
    }
);
$t->get_ok( '/__test/integration-session/' . $author )->status_is($HTTP_OK);
$t->get_ok('/admin/integrations')->status_is($HTTP_FORBIDDEN);
$t->get_ok( '/__test/integration-session/' . $actor )->status_is($HTTP_OK);
$t->get_ok('/admin/integrations')->status_is($HTTP_OK);
$t->content_like(qr/Discord/msx)->content_unlike(qr/AAAAAA/msx);
my $document = $t->tx->res->dom;
my $csrf     = $document->at('input[name=csrf_token]')->attr('value');
$t->post_ok(
    '/admin/integrations/feeds/'
      . $publish_item => form => {
        csrf_token  => $csrf,
        decision    => 'published',
        category_id => $category
      }
)->status_is($HTTP_OK);
is(
    $dbh->selectrow_array(
        'SELECT status FROM integration_feed_items WHERE item_id=?', undef,
        $publish_item
    ),
    'published',
    'approved import publishes through the normal forum workflow'
);
my $published_thread = $dbh->selectrow_array(
    'SELECT thread_id FROM integration_feed_items WHERE item_id=?',
    undef, $publish_item );
ok( $published_thread, 'candidate keeps its published discussion' );
$t->post_ok( '/auth/oidc/start' => form => {} )->status_is($HTTP_FORBIDDEN);
$t->post_ok( '/admin/integrations/discord' => form => { thread_id => $thread } )
  ->status_is($HTTP_FORBIDDEN);
$t->get_ok('/settings/openid')->status_is($HTTP_OK);
$t->get_ok('/auth/oidc/callback?state=wrong&code=wrong')
  ->status_is($HTTP_CLIENT_ERROR);

my $gui = GPForum::Test::GuiDriver->new( test => $t );
$gui->install_session;
$gui->actor($actor);
subtest 'feature: network outbox commands are submitted from real forms' =>
  sub {
    my $selected = $topic->();
    $gui->visit('/admin/integrations')
      ->submit( 'form[action="/admin/integrations/discord"]',
        { thread_id => $selected }, $HTTP_OK );
    is(
        $dbh->selectrow_array(
            'SELECT status FROM integration_announcements WHERE thread_id=?',
            undef, $selected
        ),
        'queued',
        'GUI Discord selection persists its queued delivery'
    );
    my $uncertain = $announcements->request( $actor, $topic->() );
    is( $announcements->deliver( $uncertain->{announcement_id} )->{status},
        'uncertain', 'controlled lost response requires checked recovery' );
    $gui->visit('/admin/integrations')->submit(
        'form[action="/admin/integrations/discord/'
          . $uncertain->{announcement_id}
          . '/retry"]',
        {
            checked => '1',
            reason  => 'Confirmed absent with controlled provider'
        },
        $HTTP_OK
    );
    is(
        $dbh->selectrow_array(
'SELECT status FROM integration_announcements WHERE announcement_id=?',
            undef,
            $uncertain->{announcement_id}
        ),
        'queued',
        'GUI checked retry returns the uncertain delivery to the outbox'
    );
    $gui->visit('/admin/integrations')
      ->submit( 'form[action="/admin/integrations/feeds"]', {}, $HTTP_OK );
    ok(
        $dbh->selectrow_array(
q{SELECT count(*) FROM outbox_messages o JOIN event_log e USING(event_id) WHERE e.event_type='integration.feed.requested'}
        ),
        'GUI feed fetch queues the authorized source'
    );
  };
subtest
  'feature: real OpenID service links logs in and unlinks through HTTP' => sub {

    # Only the network boundary is controlled; state, JWT, PKCE, credentials,
    # account linking and session creation use the production service and DB.
    $dbh->do( 'UPDATE credentials SET revoked_at=NULL WHERE id=?',
        undef, $credential_id );
    $dbh->do( 'DELETE FROM oidc_account_links WHERE user_id=?', undef, $actor );
    require GPForum::Controller::Identity::OpenID;
    no warnings 'redefine';                                      ## no critic (TestingAndDebugging::ProhibitNoWarnings) -- inject the real service with its controlled HTTP client
    local *GPForum::Controller::Identity::OpenID::_provider =    ## no critic (Variables::ProtectPrivateVars) -- controlled transport on the real service

      sub { return $oidc; };
    $gui->actor($actor)
      ->visit('/settings/openid')
      ->submit( 'form[action="/settings/openid/link"]',
        { password => $secret } );
    my $query = _redirect_query($t);
    $reply->( { nonce => $query->param('nonce') } );
    $gui->visit(
        '/auth/oidc/callback?state='
          . $query->param('state')
          . '&code=gui-link',
        $HTTP_FOUND
    );
    is(
        $dbh->selectrow_array(
            'SELECT count(*) FROM oidc_account_links WHERE user_id=?', undef,
            $actor
        ),
        1,
        'GUI OpenID callback persists the explicitly linked identity'
    );
    $t->ua->cookie_jar->empty;
    my ($before) =
      $dbh->selectrow_array( 'SELECT count(*) FROM sessions WHERE user_id=?',
        undef, $actor );
    $gui->visit('/login')->submit('form[action="/auth/oidc/start"]');
    $query = _redirect_query($t);
    $reply->( { nonce => $query->param('nonce') } );
    $gui->visit(
        '/auth/oidc/callback?state='
          . $query->param('state')
          . '&code=gui-login',
        $HTTP_FOUND
    );
    cmp_ok(
        $dbh->selectrow_array(
            'SELECT count(*) FROM sessions WHERE user_id=?',
            undef, $actor
        ),
        '>', $before,
        'GUI OpenID login creates a normal local session'
    );
    $gui->visit('/settings/openid')
      ->submit( 'form[action="/settings/openid/unlink"]',
        { password => $secret } );
    is(
        $dbh->selectrow_array(
            'SELECT count(*) FROM oidc_account_links WHERE user_id=?', undef,
            $actor
        ),
        0,
        'GUI OpenID unlink removes the binding after local proof'
    );
  };
subtest 'incomplete public configuration never strands an announcement' => sub {
    my $pending        = $announcements->request( $actor, $topic->() );
    my $invalid_config = GPForum::Config->new( %{$config},
        public_base_url => 'http://127.0.0.1:3000' );
    my $invalid = GPForum::Service::Integration::Announcements->new(
        schema           => $schema,
        config           => $invalid_config,
        policy_available => 1,
        client           => $client
    );
    my $calls_before = scalar @{ $client->calls };
    throws_ok { $invalid->deliver( $pending->{announcement_id} ) }
    qr/complete[ ]public[ ]HTTPS/msx,
      'invalid canonical URL is rejected before taking the sending claim';
    is(
        $dbh->selectrow_array(
'SELECT status FROM integration_announcements WHERE announcement_id=?',
            undef,
            $pending->{announcement_id}
        ),
        'queued',
        'configuration failure leaves the announcement queued for correction'
    );
    is( scalar @{ $client->calls },
        $calls_before, 'configuration failure makes no external call' );
    my ($count) =
      $dbh->selectrow_array('SELECT count(*) FROM integration_announcements');
    throws_ok { $invalid->request( $actor, $topic->() ) } qr/disabled/msx,
      'incomplete configuration cannot queue a new announcement';
    is(
        $dbh->selectrow_array('SELECT count(*) FROM integration_announcements'),
        $count, 'incomplete setup leaves no undeliverable announcement'
    );
};
done_testing;

sub _json ( $code, $data ) {
    my $response =
      Mojo::Message::Response->new( code => $code )->body( encode_json($data) );
    $response->headers->content_type('application/json');
    return $response;
}

1;

sub _redirect_query ($test) {
    my $headers = $test->tx->res->headers;
    return Mojo::URL->new( $headers->location )->query;
}

1;
