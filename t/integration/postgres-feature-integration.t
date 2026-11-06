# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package main;
use v5.40;
use utf8;
use Const::Fast;
use Test::More;
use Test::Mojo;
use Mojo::URL;
use Mojo::Message::Response;
use Mojo::JSON qw(encode_json);
use lib 'lib', 't/lib';
use GPForum::Benchmark::SeedDataset qw(seed_id);
use GPForum::Command::AdminBootstrap;
use GPForum::Infrastructure::Id;
use GPForum::Infrastructure::ResultRow;
use GPForum::Test::GuiDriver;
use GPForum::Test::GuiForm;
use GPForum::Test::NetworkClient;
use GPForum::Test::PgDatabase;
use GPForum::Test::PostgresHarness;
our $VERSION = '0.001';
const my $HTTP_OK             => 200;
const my $HTTP_FOUND          => 302;
const my $HTTP_BAD_REQUEST    => 400;
const my $CROSS_PAGE_POSITION => 52;
const my $HTTP_FORBIDDEN      => 403;
const my $HTTP_MISSING        => 404;
const my $TOTAL_SERVICES      => 16;
const my $REPLIES             => 60;
const my $LAST_POSITION       => 61;
const my $FIRST_PAGE          => 50;
const my $SECOND_PAGE         => 10;
const my $TOKEN_LENGTH        => 40;

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'requires PostgreSQL';
}
my $database = GPForum::Test::PgDatabase->fresh( seed => 1 );
local $ENV{GPFORUM_DATABASE_DSN}              = $database->dsn;
local $ENV{GPFORUM_MINION_ENABLED}            = 0;
local $ENV{GPFORUM_REALTIME_LISTENER_ENABLED} = 0;
my $dbh    = $database->dbh;
my $admin  = seed_id( user => 1 );
my $member = seed_id( user => 2 );
my $ids    = GPForum::Infrastructure::Id->new;
GPForum::Test::PostgresHarness::quietly(
    sub {
        return GPForum::Command::AdminBootstrap->new(
            schema => $database->schema )->run( 'grant', '--user-id', $admin );
    }
);
my $t   = Test::Mojo->new('GPForum');
my $gui = GPForum::Test::GuiDriver->new( test => $t );
$gui->install_session;
$gui->actor($admin);
my $post = $dbh->selectrow_hashref(
q{SELECT p.post_id,p.current_body_id,p.thread_id FROM posts p JOIN threads t USING(thread_id) JOIN categories c USING(category_id) JOIN spaces s USING(space_id) WHERE p.deleted_at IS NULL AND t.deleted_at IS NULL AND p.moderation_state='visible' AND t.moderation_state='visible' AND t.visibility='public' AND c.visibility='public' AND s.visibility='public' LIMIT 1}
);
my $video_id = '52a10666-3a18-4e73-93da-e8d3c12c305a';
subtest 'federated modules activate and revoke through the running GUI' => sub {
    $gui->visit('/admin/integrations');
    $t->element_count_is( '[data-integration-service]', $TOTAL_SERVICES )
      ->element_exists(
        '[data-integration-service="mastodon"][data-integration-state="setup"]')
      ->element_exists(
        '[data-integration-service="openid"][data-integration-state="setup"]');
    $gui->visit('/admin/plugins');
    $t->element_exists('#plugin-mastodon')
      ->element_exists('a[href="/admin/configuration#setting-mastodon_hosts"]');
    $gui->visit('/admin/configuration')->submit(
        'form[action="/admin/configuration"]',
        {
            GPFORUM_MASTODON_HOSTS => 'social.example.org',
            GPFORUM_PEERTUBE_HOSTS => 'video.example.org'
        }
    );
    for my $id (qw(mastodon peertube)) {
        $gui->visit('/admin/plugins')
          ->submit( 'form[action="/admin/plugins/' . $id . '"]',
            { enabled => '1' } );
    }
    $dbh->do(
        'UPDATE post_bodies SET body_source=? WHERE body_id=?',
        undef,
"https://social.example.org/\@author/123456\n\nhttps://video.example.org/w/$video_id",
        $post->{current_body_id}
    );
    $gui->visit( '/t/' . $post->{thread_id} );
    $t->element_exists('[data-integration-provider="mastodon"]')
      ->element_exists('[data-integration-provider="peertube"]');
    $t->header_like(
        'Content-Security-Policy' => qr{https://video[.]example[.]org}msx );
    my $registry = $t->app->build_controller->ui_integration_plugins;
    my $before   = $registry->cache_variant;
    $gui->visit('/admin/integrations');
    $t->element_exists(
        '[data-integration-service="mastodon"][data-integration-state="active"]'
    );
    $gui->visit('/admin/configuration')->submit(
        'form[action="/admin/configuration"]',
        {
            GPFORUM_MASTODON_HOSTS => 'people.example.org',
            GPFORUM_PEERTUBE_HOSTS => 'other-video.example.org'
        }
    );
    $gui->visit( '/t/' . $post->{thread_id} );
    $t->element_exists_not('[data-integration-provider="mastodon"]')
      ->element_exists_not('[data-integration-provider="peertube"]')
      ->header_unlike(
        'Content-Security-Policy' => qr{https://video[.]example[.]org}msx );
    $registry = $t->app->build_controller->ui_integration_plugins;
    isnt( $registry->cache_variant,
        $before, 'instance policy changes invalidate the rendered response' );
    $gui->visit('/admin/configuration')
      ->submit( 'form[action="/admin/configuration"]',
        { GPFORUM_MASTODON_HOSTS => q{}, GPFORUM_PEERTUBE_HOSTS => q{} } );
    $gui->visit('/admin/plugins');
    $t->element_exists('a[href="/admin/configuration#setting-peertube_hosts"]')
      ->element_exists_not('form[action="/admin/plugins/peertube"]');
    $registry = $t->app->build_controller->ui_integration_plugins;
    is( $registry->resolve( 'https://video.example.org/w/' . $video_id ),
        undef,
        'live allowlists reach cards players and CSP without restarting' );
};
subtest 'GUI network configuration reaches the production outbox worker' =>
  sub {
    my $webhook = 'https://discord.com/api/webhooks/123456789012345678/'
      . ( 'A' x $TOKEN_LENGTH );
    $gui->visit('/admin/configuration')->submit(
        'form[action="/admin/configuration"]',
        {
            GPFORUM_PUBLIC_BASE_URL     => 'https://forum.example.org',
            GPFORUM_DISCORD_WEBHOOK     => $webhook,
            GPFORUM_SYNDICATION_SOURCES => 'https://source.example.org/feed'
        }
    );
    $gui->visit('/admin/integrations');
    $t->element_exists(
'[data-integration-service="discord"][data-integration-state="configured"]'
      )
      ->element_exists(
'[data-integration-service="feeds"][data-integration-state="configured"]'
      )->content_unlike(qr/AAAAAAAAAAAA/msx);
    $gui->submit( 'form[action="/admin/integrations/discord"]',
        { thread_id => $post->{thread_id} }, $HTTP_OK );
    my ($announcement) = $dbh->selectrow_array(
'SELECT announcement_id FROM integration_announcements WHERE thread_id=?',
        undef, $post->{thread_id}
    );
    my $worker    = $t->app->build_controller;
    my $transport = $worker->gp_outbox_transport;
    my ($handler) =
      grep { $_->isa('GPForum::Worker::Handler::IntegrationNetwork') }
      @{ $transport->handlers };
    my $response = Mojo::Message::Response->new( code => $HTTP_OK )
      ->body( encode_json( { id => '123456789012345679' } ) );
    $response->headers->content_type('application/json');
    my $client = GPForum::Test::NetworkClient->new( responses => [$response] );
    $handler->announcements->client($client);
    my ($event) = $dbh->selectrow_array(
q{SELECT event_id FROM event_log WHERE event_type='integration.discord.requested' ORDER BY created_at DESC LIMIT 1}
    );
    my $messages = $database->schema->resultset('OutboxMessage');
    my $message  = $messages->search( { event_id => $event } )->first;
    ok( $message,
        'GUI command creates the envelope consumed by the production worker' );
    _dispatch_due( $worker, $transport, $event );
    is(
        $dbh->selectrow_array(
'SELECT status FROM integration_announcements WHERE announcement_id=?',
            undef,
            $announcement
        ),
        'sent',
'production worker delivers the GUI-selected topic with saved configuration'
    );
    is( scalar @{ $client->calls },
        1, 'exactly one controlled Discord request is made' );
    $transport->dispatch(
        GPForum::Infrastructure::ResultRow->from(
            { payload => $message->payload }
        )
    );
    is( scalar @{ $client->calls },
        1, 'replayed GUI outbox event never sends twice' );
    $gui->visit('/admin/integrations')
      ->submit( 'form[action="/admin/integrations/feeds"]', {}, $HTTP_OK );
    my $feed_response =
      Mojo::Message::Response->new( code => $HTTP_OK )
      ->body(
'<rss><channel><item><guid>gui-pipeline</guid><title>Reviewed feed topic</title><link>https://source.example.org/article</link></item></channel></rss>'
      );
    $feed_response->headers->content_type('application/rss+xml');
    my $feed_client =
      GPForum::Test::NetworkClient->new( responses => [$feed_response] );
    $handler->feeds->client($feed_client);
    my ($feed_event) = $dbh->selectrow_array(
q{SELECT event_id FROM event_log WHERE event_type='integration.feed.requested' ORDER BY created_at DESC LIMIT 1}
    );
    _dispatch_due( $worker, $transport, $feed_event );
    my $candidate = $dbh->selectrow_hashref(
q{SELECT item_id,status,thread_id FROM integration_feed_items WHERE url='https://source.example.org/article'}
    );
    is( $candidate->{status}, 'pending',
        'worker imports the GUI-authorized source into moderation' );
    is( $candidate->{thread_id},
        undef, 'imported content is unpublished before GUI review' );
    $gui->visit('/admin/integrations')->submit(
        'form[action="/admin/integrations/feeds/'
          . $candidate->{item_id} . '"]',
        { category_id => seed_id( category => 1 ) },
        $HTTP_OK,
        'button[value="published"]'
    );
    my ($published) = $dbh->selectrow_array(
        'SELECT thread_id FROM integration_feed_items WHERE item_id=?',
        undef, $candidate->{item_id} );
    ok( $published,
'GUI approval publishes the imported candidate through the forum workflow'
    );
    $gui->visit( '/t/' . $published );
    $t->content_like(qr/Reviewed[ ]feed[ ]topic/msx);
    $gui->visit('/settings');
    $t->element_exists('a[href="/settings/openid"]');
  };
subtest
  'staff choose titled discussions and messages through native controls' =>
  sub {
    my $source  = $ids->uuid;
    my $target  = $ids->uuid;
    my $foreign = $ids->uuid;
    for my $pair (
        [ $source,  'Picker source' ],
        [ $target,  'Picker target' ],
        [ $foreign, 'Picker private' ]
      )
    {
        $dbh->do(
q{INSERT INTO threads(thread_id,category_id,author_user_id,title,slug,visibility) VALUES(?,?,?,?,'picker',?)},
            undef,
            $pair->[0],
            seed_id( category => 1 ),
            $admin,
            $pair->[1],
            $pair->[0] eq $foreign ? 'private' : 'public'
        );
    }
    for my $position ( 1 .. $LAST_POSITION ) {
        $dbh->do(
'INSERT INTO posts(post_id,thread_id,author_user_id,position) VALUES(?,?,?,?)',
            undef, $ids->uuid, $source, $admin, $position
        );
    }
    $gui->visit('/moderation/transfers?q=Picker');
    my $dom      = $t->tx->res->dom;
    my $form     = $dom->at('select[name="source"]')->ancestors('form')->first;
    my ($choice) = grep {
        $_->text eq 'Picker source · '
          . $dbh->selectrow_array(
            'SELECT title FROM categories WHERE category_id=?',
            undef, seed_id( category => 1 ) )
    } $form->find('option')->each;
    ok( $choice, 'source is chosen by its displayed title' );
    my $request = GPForum::Test::GuiForm->request( $form,
        { source => $choice->attr('value') } );
    $gui->visit(
        Mojo::URL->new( $request->{action} )->query( $request->{fields} ) );
    $t->element_count_is( 'input[type="checkbox"][name="post_numbers"]',
        $FIRST_PAGE )
      ->element_exists(
        'select[name="target"] option[value="' . $target . '"]' )
      ->element_exists_not(
        'select[name="target"] option[value="' . $foreign . '"]' );
    $dom = $t->tx->res->dom;
    my $next = Mojo::URL->new('/moderation/transfers')->query(
        source         => $source,
        after_position => $FIRST_PAGE + 1
    );
    $gui->submit(
        'form[data-transfer-form]',
        { post_numbers => [2], reason => 'Selection kept across pages' },
        $HTTP_OK,
        'button[name="page_after"][value="51"]'
    );
    $t->element_exists('input[name="post_numbers"][value="2"][checked]')
      ->element_exists('input[name="post_numbers"][value="52"]')
      ->element_exists(
        'input[name="reason"][value="Selection kept across pages"]');
    is(
        $dbh->selectrow_array(
            'SELECT count(*) FROM posts WHERE thread_id=?',
            undef, $source
        ),
        $LAST_POSITION,
        'browsing selections never transfers posts'
    );
    $gui->submit(
        'form[data-transfer-form]',
        { post_numbers => [ 2, $CROSS_PAGE_POSITION ], target => q{} },
        $HTTP_BAD_REQUEST,
        'button[data-transfer-submit]'
    );
    $t->element_exists('form[data-transfer-form]')
      ->element_exists('#transfer-error[role="alert"]');
    $t->element_exists('input[name="post_numbers"][value="2"][checked]')
      ->element_exists('input[name="post_numbers"][value="52"][checked]')
      ->element_exists(
        'input[name="reason"][value="Selection kept across pages"]');
    $t->content_unlike(qr/forum[.]error_invalid/msx);
    $dom = $t->tx->res->dom;
    my $checked = $dom->find('input[name="post_numbers"][checked]');
    is_deeply(
        [ map { $_->attr('value') } $checked->each ],
        [ 2, $CROSS_PAGE_POSITION ],
        'invalid native transfer preserves both pages of selections'
    );
    $t->element_exists('#transfer-target[aria-invalid="true"]')
      ->element_exists('#transfer-target-error');
    $gui->submit(
        'form[method="post"][action="/moderation/transfers"]',
        {
            target       => $target,
            operation    => 'move',
            post_numbers => [ 2, $CROSS_PAGE_POSITION ],
            reason       => 'Selected two visible checkboxes'
        },
        $HTTP_FOUND,
        'button[data-transfer-submit]'
    );
    is(
        $dbh->selectrow_array(
            'SELECT count(*) FROM posts WHERE thread_id=?',
            undef, $target
        ),
        2,
        'native multiselection moves both selected messages'
    );
    my ($transfer) = $dbh->selectrow_array(
        'SELECT transfer_id FROM thread_transfers WHERE source_id=?',
        undef, $source );
    $gui->visit('/moderation/transfers')
      ->submit( 'form[action="/moderation/transfers/' . $transfer . '/undo"]' );
    is(
        $dbh->selectrow_array(
            'SELECT count(*) FROM posts WHERE thread_id=?',
            undef, $source
        ),
        $LAST_POSITION,
        'native undo restores both selected messages'
    );
    $gui->visit($next);
    $t->element_count_is( 'input[type="checkbox"][name="post_numbers"]',
        $SECOND_PAGE );
    $gui->visit( '/moderation/transfers?source=' . $source )->submit(
        'form[method="post"][action="/moderation/transfers"]',
        {
            target       => q{},
            operation    => 'split',
            post_numbers => 2,
            title        => 'Picker split result',
            reason       => 'Split selected message'
        },
        $HTTP_FOUND,
        'button[data-transfer-submit]'
    );
    my $split = $dbh->selectrow_hashref(
q{SELECT transfer_id,target_id FROM thread_transfers WHERE source_id=? AND operation='split' ORDER BY created_at DESC LIMIT 1},
        undef, $source
    );
    ok( $split, 'native selection creates a split discussion' );
    $gui->visit( '/moderation/transfers?source=' . $split->{target_id} )
      ->submit(
        'form[method="post"][action="/moderation/transfers"]',
        {
            target    => $source,
            operation => 'merge',
            reason    => 'Merge complete split discussion'
        },
        $HTTP_FOUND,
        'button[data-transfer-submit]'
      );
    is(
        $dbh->selectrow_array(
            'SELECT count(*) FROM posts WHERE thread_id=?',
            undef, $source
        ),
        $LAST_POSITION,
        'native merge includes the source opening message'
    );
    my ($merge) = $dbh->selectrow_array(
q{SELECT transfer_id FROM thread_transfers WHERE source_id=? AND operation='merge' ORDER BY created_at DESC LIMIT 1},
        undef, $split->{target_id}
    );
    $gui->visit('/moderation/transfers')
      ->submit( 'form[action="/moderation/transfers/' . $merge . '/undo"]' );
    $gui->visit('/moderation/transfers')
      ->submit( 'form[action="/moderation/transfers/'
          . $split->{transfer_id}
          . '/undo"]' );
    is(
        $dbh->selectrow_array(
            'SELECT count(*) FROM posts WHERE thread_id=?',
            undef, $source
        ),
        $LAST_POSITION,
        'native split and merge remain independently reversible'
    );
    $gui->visit( '/moderation/transfers?source=' . $foreign, $HTTP_MISSING );
    $gui->actor($member)
      ->visit( '/moderation/transfers', $HTTP_FORBIDDEN )
      ->actor($admin);
  };
done_testing;

sub _dispatch_due ( $worker, $transport, $event ) {

    # Isolate the selected envelope from unrelated seed jobs in this fixture.
    $dbh->do(
q{UPDATE outbox_messages SET next_attempt_at='infinity',available_at='infinity' WHERE event_id<>?},
        undef, $event
    );
    $dbh->do(
q{UPDATE outbox_messages SET next_attempt_at=now()-interval '1 minute',available_at=now()-interval '1 minute' WHERE event_id=?},
        undef, $event
    );
    my $dispatcher = $worker->gp_outbox_dispatcher;
    $dispatcher->transport($transport);
    return $dispatcher->dispatch_pending(1);
}

1;
