# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;
use utf8;
use Test::More;
use Const::Fast;
use Test::Mojo;
use lib 'lib';
use lib 't/lib';
use GPForum::Benchmark::SeedDataset qw(seed_id);
use GPForum::Config;
use GPForum::Infrastructure::Id;
use GPForum::Service::Admin::Configuration;
use GPForum::Service::Integration::Registry;
use GPForum::Test::PgDatabase;

our $VERSION = '0.001';
const my $HTTP_OK              => 200;
const my $HTTP_REDIRECT        => 302;
const my $HTTP_UNAUTHORIZED    => 401;
const my $HTTP_FORBIDDEN       => 403;
const my $HTTP_CONFLICT        => 409;
const my $HTTP_INVALID         => 422;
const my $SAVED_CHANGES        => 4;
const my $REV_BEFORE_RESET     => 3;
const my $MODULE_COUNT         => 13;
const my $OWNER_TEST_MIB       => 512;
const my $OWNER_TEST_PENDING   => 7;
const my $REQUEST_HASH_LENGTH  => 64;
const my $NETWORK_SECRET_BYTES => 192;
const my $WEBHOOK_TOKEN_BYTES  => 100;

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'temporary PostgreSQL required';
}
my $database = GPForum::Test::PgDatabase->fresh( seed => 1 );
my $dbh      = $database->dbh;
my $ids      = GPForum::Infrastructure::Id->new;
my $config   = GPForum::Config->from_environment( { GPFORUM_ENV => 'test' } );
my $admin    = seed_id( user => 1 );
my $member   = seed_id( user => 2 );
$dbh->do(
    'UPDATE role_bindings SET space_id=NULL,resource_id=NULL WHERE user_id=?',
    undef, $admin );

for my $action (qw(view manage)) {
    my $permission = $ids->uuid;
    $dbh->do(
'INSERT INTO permissions(permission_id,name,resource_type,action) VALUES(?,?,?,?)',
        undef,
        $permission,
        "configuration.$action",
        'admin_console',
        $action
    );
    $dbh->do( 'INSERT INTO role_permissions(role_id,permission_id) VALUES(?,?)',
        undef, seed_id( role => 1 ), $permission );
}

sub store {
    return GPForum::Service::Admin::Configuration->new(
        schema      => $database->schema,
        base_config => $config
    );
}
my $initial = store()->state;
is( $initial->{revision}, 0, 'configuration starts with a known revision' );
my $command = $ids->uuid;
my $change  = {
    actor    => $admin,
    command  => $command,
    expected => 0,
    plugin   => 'spotify',
    enabled  => 0,
    mode     => 'link'
};
is( store()->save_plugin($change)->{status},
    'ok', 'administrator configures an independent module' );
is( store()->save_plugin($change)->{status},
    'ok', 'command retry is idempotent' );
is( store()->state->{revision}, 1, 'a retry advances no revision' );
is( store()->save_plugin( { %{$change}, enabled => 1 } )->{status},
    'conflict', 'a command id cannot change its payload' );
is(
    store()
      ->save_plugin( { %{$change}, command => $ids->uuid, expected => 0 } )
      ->{status},
    'conflict',
    'a stale administrator form cannot overwrite a newer change'
);
is(
    store()->save_plugin(
        { %{$change}, actor => $member, command => $ids->uuid, expected => 1 }
    )->{status},
    'forbidden',
    'ordinary members cannot change configuration'
);
is(
    store()->save_plugin(
        {
            %{$change},
            command  => $ids->uuid,
            expected => 1,
            plugin   => 'instagram',
            enabled  => 1,
            mode     => 'embed'
        }
    )->{status},
    'invalid',
    'undeclared embed capability cannot be granted by the GUI'
);

my $input = {
    actor    => $admin,
    command  => $ids->uuid,
    expected => 1,
    values   => {
        GPFORUM_SITE_NAME        => 'Officina',
        GPFORUM_SITE_DESCRIPTION => 'Discussioni e musica',
        GPFORUM_SMTP_USERNAME    => 'private-user',
        GPFORUM_SMTP_PASSWORD    => 'private-password',
    }
};
is( store()->save_general($input)->{status},
    'ok', 'related general settings save atomically' );
is( store()->save_general($input)->{status},
    'ok', 'secret sealing does not break idempotent retry' );
is( store()->effective_config->site_name,
    'Officina', 'a new request or process reads durable overrides' );
is( store()->effective_config->smtp_password,
    'private-password', 'SMTP secret opens only inside core configuration' );
my ($stored) =
  $dbh->selectrow_array('SELECT settings::text FROM forum_configuration');
unlike(
    $stored,
    qr/private-password|private-user/msx,
    'no plaintext credential is persisted'
);
my $page = store()->general_page;
my @secrets =
  grep { $_->{secret} } map { @{ $_->{fields} } } @{ $page->{groups} };
ok(
    !( grep { length $_->{value} } @secrets ),
    'GUI values never expose stored credentials'
);
is(
    store()->save_general(
        {
            %{$input},
            command  => $ids->uuid,
            expected => 2,
            values   =>
              { GPFORUM_SMTP_PASSWORD => q{}, GPFORUM_SITE_NAME => 'Nuovo' }
        }
    )->{status},
    'ok',
    'blank secret keeps the protected value'
);
is( store()->effective_config->smtp_password,
    'private-password', 'blank input did not erase the password' );
is(
    store()->save_general(
        {
            %{$input},
            command  => $ids->uuid,
            expected => 3,
            values   => { GPFORUM_SITE_NAME => q{} }
        }
    )->{status},
    'invalid',
    'invalid general configuration never commits'
);
is( store()->state->{revision},
    $REV_BEFORE_RESET, 'failed validation advances no revision' );
is(
    store()->save_general(
        {
            %{$input},
            command  => $ids->uuid,
            expected => 3,
            values   => { GPFORUM_DATABASE_PASSWORD => 'forbidden' }
        }
    )->{status},
    'invalid',
    'host bootstrap credentials are outside forum settings authority'
);
is(
    store()->reset_general(
        {
            actor    => $admin,
            command  => $ids->uuid,
            expected => 3,
            key      => 'GPFORUM_SITE_NAME'
        }
    )->{status},
    'ok',
    'GUI can restore the installation value'
);
is( store()->effective_config->site_name,
    'Forum', 'reset restores the original installation default' );
my ($audits) = $dbh->selectrow_array(
    q{SELECT count(*) FROM audit_log WHERE action='admin.configuration'});
is( $audits, $SAVED_CHANGES,
    'each successful change has exactly one audit record' );
my ($audit) = $dbh->selectrow_array(
q{SELECT string_agg(metadata::text,' ') FROM audit_log WHERE action='admin.configuration'}
);
unlike(
    $audit,
    qr/private-password|private-user/msx,
    'audit records contain setting identifiers, never secrets'
);

subtest 'administrator GUI, CSRF and settings applied on subsequent pages' =>
  sub {
    local $ENV{GPFORUM_ENV} = 'test';
    my $test = Test::Mojo->new('GPForum');
    $test->app->helper( gp_schema      => sub { return $database->schema; } );
    $test->app->helper( gp_base_config => sub { return $config; } );
    my $routes = $test->app->routes;
    $routes->get('/__test/configuration-session')->to(
        cb => sub ($c) {
            $c->session( user_id => $admin );
            return $c->render( text => 'ok' );
        }
    );
    $test->get_ok('/admin/plugins')->status_is($HTTP_UNAUTHORIZED);
    $test->get_ok('/__test/configuration-session')->status_is($HTTP_OK);
    $test->get_ok('/admin/plugins')->status_is($HTTP_OK);
    my $dom = $test->tx->res->dom;
    is( $dom->find('.admin-plugin-card')->size,
        $MODULE_COUNT,
        'all thirteen installed modules are discoverable on one page' );
    $test->element_exists('form[action="/admin/plugins/spotify"]');
    $test->element_exists('form[action="/admin/plugins/apple_music"]');
    $test->element_exists('form[action="/admin/plugins/wikipedia"]');
    $test->element_exists_not('iframe');
    my $form  = $dom->at('form[action="/admin/plugins/spotify"]');
    my %input = map { $_->attr('name') => $_->attr('value') }
      @{ $form->find('input[name]')->to_array };
    $input{enabled} = 1;
    $input{mode}    = 'embed';
    $test->post_ok(
        '/admin/plugins/spotify' => form => { %input, csrf_token => 'bad' } )
      ->status_is($HTTP_FORBIDDEN);
    is( store()->state->{revision},
        $SAVED_CHANGES, 'CSRF failure makes no change' );
    $test->post_ok( '/admin/plugins/spotify' => form => \%input )
      ->status_is($HTTP_REDIRECT);
    $test->get_ok('/admin/plugins')->status_is($HTTP_OK);
    $test->element_exists(
        'form[action="/admin/plugins/spotify"] input[name="enabled"][checked]');
    $test->get_ok('/admin/configuration')->status_is($HTTP_OK);
    $test->element_exists('input#setting-site_name');
    $test->element_exists(
        'input#setting-attachment_owner_max_mib[type="number"]');
    $test->element_exists(
        'input#setting-attachment_owner_max_pending[type="number"]');
    $test->element_exists('input#setting-smtp_password[type="password"]');
    $test->content_unlike(qr/private-password|private-user/msx);
    $dom   = $test->tx->res->dom;
    $form  = $dom->at('form[data-admin-configuration]');
    %input = map { $_->attr('name') => $_->attr('value') }
      @{ $form->find('input[type="hidden"][name]')->to_array };
    $input{GPFORUM_SITE_NAME} = 'Pannello GUI';
    $test->post_ok( '/admin/configuration' => form => \%input )
      ->status_is($HTTP_REDIRECT);
    $test->get_ok('/admin/configuration')->status_is($HTTP_OK);
    $test->element_exists('input#setting-site_name[value="Pannello GUI"]');
    $test->text_like( 'title' => qr/Pannello[ ]GUI/msx );
    $test->text_is(
        '.brand__name' => 'Pannello GUI',
        'site branding follows the live GUI setting'
    );
    $test->header_like( 'Cache-Control' => qr/no-store/msx );
    $dom   = $test->tx->res->dom;
    $form  = $dom->at('form[data-admin-configuration]');
    %input = map { $_->attr('name') => $_->attr('value') }
      @{ $form->find('input[type="hidden"][name]')->to_array };
    my $revision = store()->state->{revision};
    is(
        store()->save_plugin(
            {
                actor    => $admin,
                command  => $ids->uuid,
                expected => $revision,
                plugin   => 'youtube',
                enabled  => 0,
                mode     => 'link'
            }
        )->{status},
        'ok',
        'another administrator edits while the form is open'
    );
    $input{GPFORUM_SITE_NAME} = 'Scelta conservata';
    $test->post_ok( '/admin/configuration' => form => \%input )
      ->status_is($HTTP_CONFLICT);
    $test->element_exists('input#setting-site_name[value="Scelta conservata"]');
    is( store()->effective_config->site_name,
        'Pannello GUI',
        'a stale GUI form did not overwrite the current value' );
    $dom   = $test->tx->res->dom;
    $form  = $dom->at('form[data-admin-configuration]');
    %input = map { $_->attr('name') => $_->attr('value') }
      @{ $form->find('input[type="hidden"][name]')->to_array };
    $input{GPFORUM_SITE_NAME}        = 'Scelta conservata';
    $input{GPFORUM_DEFAULT_TIMEZONE} = 'Moon/Base';
    $test->post_ok( '/admin/configuration' => form => \%input )
      ->status_is($HTTP_INVALID);
    $test->element_exists(
        'input#setting-default_timezone[aria-invalid="true"]');
    $test->element_exists('input#setting-site_name[value="Scelta conservata"]');
    my $unicode = {
        actor    => $admin,
        command  => $ids->uuid,
        expected => store()->state->{revision},
        values   => {
            GPFORUM_SITE_NAME     => 'Officina 🛠',
            GPFORUM_SMTP_PASSWORD => 'pàss-🔑'
        }
    };
    is( store()->save_general($unicode)->{status},
        'ok', 'Unicode settings and secrets save without lossy encoding' );
    is( store()->effective_config->smtp_password,
        'pàss-🔑', 'a Unicode secret round-trips through sealed storage' );

    is(
        store()->save_general(
            {
                actor    => $admin,
                command  => $ids->uuid,
                expected => store()->state->{revision},
                values   => {
                    GPFORUM_DEFAULT_LOCALE   => 'it',
                    GPFORUM_DEFAULT_TIMEZONE => 'Europe/Rome'
                }
            }
        )->{status},
        'ok',
        'presentation defaults can change without restarting'
    );
    $test->get_ok( '/admin/configuration' => { 'Accept-Language' => 'fr-FR' } )
      ->status_is($HTTP_OK);
    $test->element_exists('html[lang="it"]');
    $test->text_is(
        '.brand__name' => 'Officina 🛠',
        'live branding survives language negotiation'
    );

    $test->content_unlike(qr/private-password|private-user/msx);
    $test->get_ok('/admin/plugins')->status_is($HTTP_OK);
    $dom   = $test->tx->res->dom;
    $form  = $dom->at('form[action="/admin/plugins/probe/link"]');
    %input = map { $_->attr('name') => $_->attr('value') }
      @{ $form->find('input[type="hidden"][name]')->to_array };
    $input{url} = 'https://it.m.wikipedia.org/wiki/Alan_Turing#Biografia';
    $test->post_ok( '/admin/plugins/probe/link' => form => \%input )
      ->status_is($HTTP_OK);
    $test->element_exists(
'[data-integration-provider="wikipedia"] a[href="https://it.wikipedia.org/wiki/Alan_Turing#Biografia"]'
    );
    $dom   = $test->tx->res->dom;
    $form  = $dom->at('form[action="/admin/plugins/wikipedia"]');
    %input = map { $_->attr('name') => $_->attr('value') }
      @{ $form->find('input[type="hidden"][name]')->to_array };
    $test->post_ok( '/admin/plugins/wikipedia' => form => \%input )
      ->status_is($HTTP_REDIRECT);
    ok(
        !store()->state->{settings}{plugins}{wikipedia}{enabled},
        'Wikipedia can be disabled through the GUI and persisted'
    );
    $test->get_ok('/admin/plugins')->status_is($HTTP_OK);
    $test->element_exists_not(
        'form[action="/admin/plugins/wikipedia"] input[name="enabled"][checked]'
    );
    $dom   = $test->tx->res->dom;
    $form  = $dom->at('form[action="/admin/plugins/wikipedia"]');
    %input = map { $_->attr('name') => $_->attr('value') }
      @{ $form->find('input[type="hidden"][name]')->to_array };
    $input{enabled} = 1;
    $input{mode}    = 'embed';
    $test->post_ok( '/admin/plugins/wikipedia' => form => \%input )
      ->status_is($HTTP_INVALID);
    ok(
        !store()->state->{settings}{plugins}{wikipedia}{enabled},
        'a forged player mode cannot enable unsupported Wikipedia embeds'
    );
    $input{command_id} = $ids->uuid;
    $input{mode}       = 'link';
    $test->post_ok( '/admin/plugins/wikipedia' => form => \%input )
      ->status_is($HTTP_REDIRECT);
    ok(
        store()->state->{settings}{plugins}{wikipedia}{enabled},
        'Wikipedia can be re-enabled through the GUI'
    );
    $test->get_ok('/admin/plugins')->status_is($HTTP_OK);
    $test->element_exists('form[action="/admin/plugins/mathematics"]');
    $test->element_exists(
'script[src^="/page-enhancements.js?v="][data-katex^="/katex.min.js?v="][data-mathematics^="/mathematics.js?v="]'
    );
    $dom   = $test->tx->res->dom;
    $form  = $dom->at('form[action="/admin/plugins/probe/math"]');
    %input = map { $_->attr('name') => $_->attr('value') }
      @{ $form->find('input[type="hidden"][name]')->to_array };
    $input{source} = q{$$\frac{-b\pm\sqrt{b^2-4ac}}{2a}$$};
    $test->post_ok( '/admin/plugins/probe/math' => form => \%input )
      ->status_is($HTTP_OK);
    $test->text_is(
        '.math-expression code' => q{\frac{-b\pm\sqrt{b^2-4ac}}{2a}},
        'the GUI equation tester uses the same source-preserving plugin'
    );
    $dom   = $test->tx->res->dom;
    $form  = $dom->at('form[action="/admin/plugins/mathematics"]');
    %input = map { $_->attr('name') => $_->attr('value') }
      @{ $form->find('input[type="hidden"][name]')->to_array };
    $test->post_ok( '/admin/plugins/mathematics' => form => \%input )
      ->status_is($HTTP_REDIRECT);
    $test->get_ok('/admin/plugins')->status_is($HTTP_OK);
    $test->element_exists_not('script[src^="/katex.min.js"]');
    $test->element_exists_not('script[data-katex], script[data-mathematics]');
    $test->element_exists_not(
'form[action="/admin/plugins/mathematics"] input[name="enabled"][checked]'
    );
    ok(
        !store()->state->{settings}{plugins}{mathematics}{enabled},
        'GUI deactivation persists and removes the local renderer'
    );
  };

subtest 'owner upload allowances are configurable and validated' => sub {
    my $fields  = store()->fields;
    my %by_name = map { $_->{name} => $_ } @{$fields};
    ok( $by_name{attachment_owner_max_mib},
        'retained-byte quota is exposed in the administrator form' );
    ok( $by_name{attachment_owner_max_pending},
        'pending quota is exposed in the administrator form' );
    my $revision         = store()->state->{revision};
    my $allowance_change = {
        actor    => $admin,
        command  => $ids->uuid,
        expected => $revision,
        values   => {
            GPFORUM_ATTACHMENT_OWNER_MAX_MIB     => "$OWNER_TEST_MIB",
            GPFORUM_ATTACHMENT_OWNER_MAX_PENDING => "$OWNER_TEST_PENDING"
        },
    };
    is( store()->save_general($allowance_change)->{status},
        'ok', 'administrator saves both owner allowances' );
    is( store()->effective_config->attachment_owner_max_mib,
        $OWNER_TEST_MIB,
        'retained-byte quota round trips through the SQL allowlist' );
    is( store()->effective_config->attachment_owner_max_pending,
        $OWNER_TEST_PENDING,
        'pending quota round trips through durable configuration' );

    for my $bad ( '0', '-1', 'one', '1.5' ) {
        is(
            store()->save_general(
                {
                    %{$allowance_change},
                    command  => $ids->uuid,
                    expected => store()->state->{revision},
                    values   => { GPFORUM_ATTACHMENT_OWNER_MAX_PENDING => $bad }
                }
            )->{status},
            'invalid',
            "invalid pending quota $bad is refused"
        );
    }
    is(
        store()->save_general(
            {
                %{$allowance_change},
                command  => $ids->uuid,
                expected => store()->state->{revision},
                values   => { GPFORUM_ATTACHMENT_OWNER_MAX_MIB => '0' }
            }
        )->{status},
        'invalid',
        'zero retained-byte quota is refused'
    );
    for my $key (
        qw(GPFORUM_ATTACHMENT_OWNER_MAX_MIB GPFORUM_ATTACHMENT_OWNER_MAX_PENDING)
      )
    {
        is(
            store()->reset_general(
                {
                    actor    => $admin,
                    command  => $ids->uuid,
                    expected => store()->state->{revision},
                    key      => $key
                }
            )->{status},
            'ok',
            "$key can reset to its installation value"
        );
    }
    is(
        store()->effective_config->attachment_owner_max_mib,
        $config->attachment_owner_max_mib,
        'retained-byte quota resets to the installation default'
    );
    is(
        store()->effective_config->attachment_owner_max_pending,
        $config->attachment_owner_max_pending,
        'pending quota resets to the installation default'
    );
};

subtest
  'expanded integrations persist through the administrator SQL boundary' =>
  sub {
    my $presentation = store()->general_page;
    my %values       = map { $_->{env} => q{} . $_->{value} }
      map { @{ $_->{fields} } } @{ $presentation->{groups} };
    $values{GPFORUM_MASTODON_HOSTS} = 'social.example.org people.example.org';
    $values{GPFORUM_PEERTUBE_HOSTS} = 'video.example.org';
    $values{GPFORUM_SYNDICATION_SOURCES} =
      'https://example.org/feed https://example.org/atom';
    is(
        store()->save_general(
            {
                actor    => $admin,
                command  => $ids->uuid,
                expected => store()->state->{revision},
                values   => \%values
            }
        )->{status},
        'ok',
        'complete expanded configuration form saves atomically'
    );
    is_deeply(
        store()->effective_config->mastodon_hosts,
        [ 'social.example.org', 'people.example.org' ],
        'multiple instance hosts round trip'
    );
    is_deeply(
        store()->effective_config->syndication_sources,
        [ 'https://example.org/feed', 'https://example.org/atom' ],
        'multiple exact sources round trip'
    );

    for my $plugin (qw(vimeo gitlab codeberg mastodon peertube)) {
        my $mode =
          $plugin eq 'vimeo' || $plugin eq 'peertube' ? 'embed' : 'link';
        is(
            store()->save_plugin(
                {
                    actor    => $admin,
                    command  => $ids->uuid,
                    expected => store()->state->{revision},
                    plugin   => $plugin,
                    enabled  => '1',
                    mode     => $mode
                }
            )->{status},
            'ok',
            "$plugin preference persists"
        );
    }
    my $unsafe = store()->functions->row(
        'admin_configuration_change',
        {
            actor        => $admin,
            command      => $ids->uuid,
            expected     => store()->state->{revision},
            section      => 'general',
            key          => 'GPFORUM_DISCORD_WEBHOOK',
            operation    => 'set',
            value        => '"unsealed-secret"',
            request_hash => 'a' x $REQUEST_HASH_LENGTH
        }
    );
    is( $unsafe->{result}{status},
        'invalid', 'SQL refuses unsealed network credentials' );
  };

subtest 'network secrets support full webhooks and fail closed' => sub {
    my $webhook =
      'https://discord.com/api/v10/webhooks/123456789012345678901234/'
      . ( 'x' x $WEBHOOK_TOKEN_BYTES );
    my $secret         = 's' x $NETWORK_SECRET_BYTES;
    my $network_change = {
        actor    => $admin,
        command  => $ids->uuid,
        expected => store()->state->{revision},
        values   => {
            GPFORUM_DISCORD_WEBHOOK    => $webhook,
            GPFORUM_OIDC_CLIENT_SECRET => $secret
        }
    };
    is( store()->save_general($network_change)->{status},
        'ok', 'full webhook and client secret save' );
    is( store()->effective_config->discord_webhook,
        $webhook, 'long webhook opens from sealed storage' );
    is( store()->effective_config->oidc_client_secret,
        $secret, 'bounded client secret opens from sealed storage' );
    my %fields = map { $_->{name} => $_ } @{ store()->fields };
    is( $fields{discord_webhook}{secret_max_length},
        $NETWORK_SECRET_BYTES, 'webhook form accepts the server limit' );
    is(
        store()->save_general(
            {
                %{$network_change},
                command  => $ids->uuid,
                expected => store()->state->{revision},
                values   => { GPFORUM_OIDC_CLIENT_SECRET => $secret . 'x' }
            }
        )->{status},
        'invalid',
        'oversized secret rejected before sealing'
    );
    is(
        store()->save_general(
            {
                %{$network_change},
                command  => $ids->uuid,
                expected => store()->state->{revision},
                values   => { GPFORUM_DISCORD_WEBHOOK => q{} }
            }
        )->{status},
        'ok',
        'blank secret keeps current destination'
    );
    is( store()->effective_config->discord_webhook,
        $webhook, 'blank edit never loses webhook' );
    my $fallback = GPForum::Config->new(
        discord_webhook             => $webhook,
        oidc_issuer                 => 'https://login.example.org',
        oidc_authorization_endpoint => 'https://login.example.org/authorize',
        oidc_token_endpoint         => 'https://login.example.org/token',
        oidc_jwks_uri               => 'https://login.example.org/keys',
        oidc_client_id              => 'forum',
        oidc_client_secret          => 'deployment-secret'
    );

    for my $env (qw(GPFORUM_DISCORD_WEBHOOK GPFORUM_OIDC_CLIENT_SECRET)) {
        my $state = store()->state;
        $state->{settings}{general}{$env} = 'unreadable-sealed-secret';
        my $damaged = GPForum::Service::Admin::Configuration->new(
            schema      => $database->schema,
            base_config => $fallback,
            state       => $state
        )->effective_config;
        is( $damaged->discord_webhook, q{},
            'unreadable network secret cannot revive deployment webhook' );
        is( $damaged->oidc_issuer, q{},
            'unreadable network secret disables external identity' );
    }
    for my $key (qw(GPFORUM_DISCORD_WEBHOOK GPFORUM_OIDC_CLIENT_SECRET)) {
        is(
            store()->reset_general(
                {
                    actor    => $admin,
                    command  => $ids->uuid,
                    expected => store()->state->{revision},
                    key      => $key
                }
            )->{status},
            'ok',
            'network secret resets to deployment default'
        );
    }
    is( store()->effective_config->discord_webhook,
        q{}, 'reset disables a destination absent from deployment' );
};

done_testing();

1;
