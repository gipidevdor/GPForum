# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;
use Test::More;
use Const::Fast;
use Test::Mojo;
use lib 'lib';
use lib 't/lib';
use GPForum::Benchmark::SeedDataset qw(seed_id);
use GPForum::Infrastructure::Id;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Service::Admin::AnnouncementStore;
use GPForum::Service::Admin::CategoryStore;
use GPForum::Service::Admin::Configuration;
use GPForum::Service::Moderation::ActionStore;
use GPForum::Test::PgDatabase;

our $VERSION = '0.001';
const my $HTTP_OK        => 200;
const my $HTTP_NOT_FOUND => 404;

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'temporary PostgreSQL required';
}
local $ENV{GPFORUM_MINION_ENABLED}            = 0;
local $ENV{GPFORUM_REALTIME_LISTENER_ENABLED} = 0;
my $database = GPForum::Test::PgDatabase->fresh( seed => 1 );
local $ENV{GPFORUM_DATABASE_DSN} = $database->dsn;
my $dbh = $database->dbh;
my $ids = GPForum::Infrastructure::Id->new;
my ( $thread, $category, $author, $username ) = $dbh->selectrow_array(<<'SQL');
SELECT t.thread_id,c.category_id,t.author_user_id,u.username
FROM threads t JOIN categories c USING(category_id)
JOIN spaces s USING(space_id) JOIN users u ON u.id=t.author_user_id
WHERE t.visibility='public' AND t.moderation_state='visible'
AND t.deleted_at IS NULL AND c.visibility='public' AND c.deleted_at IS NULL
AND s.visibility='public' AND s.deleted_at IS NULL
ORDER BY t.thread_id LIMIT 1
SQL
ok( $thread, 'a public seeded discussion exists' );
$dbh->do(
    'UPDATE threads SET title=? WHERE thread_id=?', undef,
    'Cache revocation secret discussion',           $thread
);
$dbh->do( 'UPDATE categories SET title=? WHERE category_id=?',
    undef, 'Cache revocation secret category', $category );
my $announcements = GPForum::Service::Admin::AnnouncementStore->new(
    schema => $database->schema );
my $announcement = $announcements->create_announcement(
    {
        actor_user_id => seed_id( user => 1 ),
        message       => 'Notice to withdraw',
    }
);
my @clients = map { Test::Mojo->new('GPForum') } 1 .. 2;
my @etags;
my @counts;

for my $client (@clients) {
    $client->get_ok('/categories')
      ->status_is($HTTP_OK)
      ->content_like(qr/Cache[ ]revocation[ ]secret[ ]category/msx);
    $client->content_like(qr/Notice[ ]to[ ]withdraw/msx);
    push @etags, _header( $client, 'ETag' );
    $client->get_ok("/c/$category")
      ->status_is($HTTP_OK)
      ->content_like(qr/Cache[ ]revocation[ ]secret[ ]discussion/msx);
    $client->get_ok("/t/$thread")->status_is($HTTP_OK);
    $client->get_ok("/t/$thread")->header_is( 'X-GPForum-Cache' => 'hit' );
    push @counts, _public_threads( $client, $username );
    $client->get_ok('/sitemap-1.xml')
      ->status_is($HTTP_OK)
      ->content_like(qr/\Q$thread\E/msx);
}

my $store =
  GPForum::Service::Moderation::ActionStore->new( schema => $database->schema );
my $command = {
    actor_user_id => seed_id( user => 1 ),
    command_id    => $ids->uuid,
    thread_id     => $thread,
    reason        => 'revoke public cached content',
};
my $epoch = _epoch();
ok( $store->hide_thread($command)->{ok}, 'normal moderation hides the thread' );
cmp_ok( _epoch(), '>', $epoch, 'its committed write advances the epoch' );
for my $index ( 0 .. $#clients ) {
    my $client = $clients[$index];
    $client->get_ok(
        "/t/$thread" => {
            'If-None-Match'     => q{*},
            'If-Modified-Since' => 'Thu, 01 Jan 2099 00:00:00 GMT',
        }
      )
      ->status_is($HTTP_NOT_FOUND)
      ->content_unlike(qr/Cache[ ]revocation[ ]secret[ ]discussion/msx);
    $client->get_ok("/c/$category")
      ->status_is($HTTP_OK)
      ->content_unlike(qr/Cache[ ]revocation[ ]secret[ ]discussion/msx);
    $client->get_ok(
        '/categories' => {
            'If-None-Match'     => $etags[$index],
            'If-Modified-Since' => 'Thu, 01 Jan 2099 00:00:00 GMT',
        }
      )
      ->status_is($HTTP_OK)
      ->header_is( 'Cache-Control' => 'public, max-age=0, must-revalidate' );
    my $count = _public_threads( $client, $username );
    is(
        $count,
        $counts[$index] - 1,
        'profile counts also discard the stale source cache'
    );
    $client->get_ok('/sitemap-1.xml')
      ->status_is($HTTP_OK)
      ->content_unlike(qr/\Q$thread\E/msx);
    $client->header_is(
        'Cache-Control' => 'public, max-age=0, must-revalidate' );
}

my $categories =
  GPForum::Service::Admin::CategoryStore->new( schema => $database->schema );
ok(
    $categories->update_category(
        {
            category_id   => $category,
            actor_user_id => seed_id( user => 1 ),
            visibility    => 'private'
        }
    ),
    'an administrator makes the category private'
);
for my $client (@clients) {
    $client->get_ok('/categories')
      ->status_is($HTTP_OK)
      ->content_unlike(qr/Cache[ ]revocation[ ]secret[ ]category/msx);
    $client->get_ok("/c/$category")->status_is($HTTP_NOT_FOUND);
}

ok(
    $announcements->retire_announcement(
        {
            actor_user_id   => seed_id( user => 1 ),
            announcement_id => $announcement->{announcement_id},
        }
    ),
    'an announcement is retired without running workers'
);
for my $client (@clients) {
    $client->get_ok('/categories')
      ->status_is($HTTP_OK)
      ->content_unlike(qr/Notice[ ]to[ ]withdraw/msx);
}

# A request whose epoch query failed must bypass both cached HTML and the
# category data cache, even while those stale entries remain in memory.
my $outage = $clients[0];
$outage->app->helper(
    gp_configuration => sub ($controller) {
        return GPForum::Service::Admin::Configuration->new(
            schema      => $controller->gp_schema,
            base_config => $controller->gp_base_config,
            state       => {
                available => 0,
                revision  => 0,
                settings  => { plugins => {}, general => {} }
            },
        );
    }
);
$outage->get_ok('/categories')->status_is($HTTP_OK);
$outage->header_is( 'X-GPForum-Cache' => undef );
$outage->header_is( 'Cache-Control'   => 'private, no-store' );
$outage->content_unlike(qr/Cache[ ]revocation[ ]secret[ ]category/msx);

# Counter/timestamp changes on normal posting do not serialize through the
# epoch row, and rollback publishes no revocation.
$epoch = _epoch();
$dbh->do(
    'UPDATE threads SET last_activity_at=clock_timestamp() WHERE thread_id=?',
    undef, $thread );
is( _epoch(), $epoch, 'activity updates do not change the revocation epoch' );
$dbh->begin_work;
$dbh->do( 'UPDATE categories SET visibility=\'public\' WHERE category_id=?',
    undef, $category );
$dbh->rollback;
is( _epoch(), $epoch,
    'a rolled-back change leaves the committed epoch unchanged' );

# A moved thread and a soft deletion are independent revocation paths.
my ( $moved, $source ) = $dbh->selectrow_array(<<'SQL');
SELECT t.thread_id,t.category_id FROM threads t JOIN categories c USING(category_id)
JOIN spaces s USING(space_id) WHERE t.visibility='public'
AND t.moderation_state='visible' AND t.deleted_at IS NULL
AND c.visibility='public' AND c.deleted_at IS NULL AND s.visibility='public' LIMIT 1
SQL
my $other = $clients[1];
$other->get_ok("/t/$moved")->status_is($HTTP_OK);
$dbh->do( 'UPDATE threads SET category_id=? WHERE thread_id=?',
    undef, $category, $moved );
$other->get_ok("/t/$moved")->status_is($HTTP_NOT_FOUND);
$dbh->do( 'UPDATE threads SET category_id=? WHERE thread_id=?',
    undef, $source, $moved );
$other->get_ok("/t/$moved")->status_is($HTTP_OK);
$dbh->do( 'UPDATE threads SET deleted_at=clock_timestamp() WHERE thread_id=?',
    undef, $moved );
$other->get_ok("/t/$moved")->status_is($HTTP_NOT_FOUND);

# A deferred revocation runs after its privileged boundary returns, during
# COMMIT as the restricted runtime role, which cannot write the epoch itself.
my $runtime        = 'gpf_cache_' . ( $ids->uuid =~ s/-//grmsx );
my $quoted_runtime = $dbh->quote_identifier($runtime);
$dbh->do("CREATE ROLE $quoted_runtime NOSUPERUSER NOINHERIT");
$dbh->do("GRANT USAGE ON SCHEMA api TO $quoted_runtime");
$dbh->do(
"GRANT EXECUTE ON FUNCTION api.admin_update_category_v2(uuid,jsonb) TO $quoted_runtime"
);
my $values =
  $dbh->selectrow_hashref( 'SELECT * FROM categories WHERE category_id=?',
    undef, $category );
$values->{title} = 'Restricted-role revocation';
my $functions =
  GPForum::Infrastructure::SqlFunction->for_schema( $database->schema );
$epoch = _epoch();
$database->schema->txn_do(
    sub {
        $dbh->do("SET LOCAL ROLE $quoted_runtime");
        ok(
            !$dbh->selectrow_array(
q{SELECT has_table_privilege(current_user,'public.public_cache_state','UPDATE')}
            ),
            'the runtime role has no direct epoch write privilege'
        );
        $functions->row( 'admin_update_category',
            { category_id => $category, values => $values } );
        is( scalar $dbh->selectrow_array('SELECT current_user'),
            $runtime,
            'the write boundary returns to the restricted role before commit' );
    }
);
cmp_ok( _epoch(), '>', $epoch,
    'the restricted-role commit advances the epoch' );
$dbh->do("DROP OWNED BY $quoted_runtime");
$dbh->do("DROP ROLE $quoted_runtime");

done_testing();

sub _epoch {
    return
      scalar $dbh->selectrow_array(
        'SELECT epoch FROM public_cache_state WHERE singleton');
}

sub _header ( $client, $name ) {
    my $headers = $client->tx->res->headers;
    return $headers->header($name);
}

sub _public_threads ( $client, $name ) {
    my $controller = $client->app->build_controller;
    return $controller->gp_profile_reader->public_profile( $name, {} )
      ->{profile}{counts}{public_threads};
}

1;
