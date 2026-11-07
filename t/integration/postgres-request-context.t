# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package main;
use v5.40;
use Test::More;
use Test::Mojo;
use lib 'lib', 't/lib';
use GPForum::Infrastructure::SqlFunction;
use GPForum::Infrastructure::AsyncQuery;
use GPForum::Service::Identity::SessionStore;
use GPForum::Test::PgDatabase;
use GPForum::Test::Promise qw(await_result);
our $VERSION = '0.001';
plan skip_all => 'temporary PostgreSQL required'
  if !GPForum::Test::PgDatabase->admin_dsn;
my $database = GPForum::Test::PgDatabase->fresh( seed => 1 );
local $ENV{GPFORUM_DATABASE_DSN}              = $database->dsn;
local $ENV{GPFORUM_ENV}                       = 'test';
local $ENV{GPFORUM_MINION_ENABLED}            = 0;
local $ENV{GPFORUM_REALTIME_LISTENER_ENABLED} = 0;
local $ENV{GPFORUM_WARMUP_ENABLED}            = 0;
my $schema    = $database->schema;
my $functions = GPForum::Infrastructure::SqlFunction->for_schema($schema);
my $thread    = $functions->row(
    'forum_list_public_threads',
    {
        member          => 0,
        global_read     => 0,
        category_ids    => [],
        space_ids       => [],
        after_activity  => undef,
        after_thread_id => undef,
        row_limit       => 1,
    }
);
ok( $thread, 'public fixture comes through the stored-function API' );
my $store = GPForum::Service::Identity::SessionStore->new( schema => $schema );
my $session = $store->create_session(
    { id => $thread->{author_user_id} },
    {
        request_address => '127.0.0.1',
        user_agent      => 'request context integration'
    }
);
my %input = (
    known_revision         => undef,
    session_id             => undef,
    user_id                => undef,
    token_hash             => undef,
    now                    => $store->clock->now_iso8601,
    touch_interval_seconds => 300,
    resolve_viewer         => 1
);
my $guest =
  await_result( $functions->row_p( 'admin_request_context', \%input ) );
ok(
    defined $guest->{revision} && defined $guest->{public_cache_epoch},
    'guest context contains a fresh revision and privacy epoch'
);
is( ref $guest->{settings}, 'HASH',
    'initial revision includes saved settings' );
my $known = await_result(
    $functions->row_p(
        'admin_request_context',
        {
            %input, known_revision => $guest->{revision}
        }
    )
);
ok( !defined $known->{settings},
    'same revision avoids transferring unchanged settings' );
my %member = (
    %input,
    session_id => $session->{session}->get_column('session_id'),
    user_id    => $thread->{author_user_id},
    token_hash =>
      $store->session_tokens->hash_token( $session->{session_token} )
);
my $valid =
  await_result( $functions->row_p( 'admin_request_context', \%member ) );
ok( $valid->{validation}{ok}, 'durable bearer token is validated' );
is( $valid->{viewer}{status}, 'active', 'viewer is read in the same call' );
my $wrong = await_result(
    $functions->row_p(
        'admin_request_context',
        {
            %member,
            token_hash => $store->session_tokens->hash_token('wrong token')
        }
    )
);
ok( !$wrong->{validation}{ok}, 'wrong bearer is refused' );
ok( !defined $wrong->{viewer}, 'invalid bearer receives no viewer' );
$store->revoke_session( { session_id => $member{session_id} } );
my $revoked =
  await_result( $functions->row_p( 'admin_request_context', \%member ) );
ok(
    !$revoked->{validation}{ok} && !defined $revoked->{viewer},
    'revocation is observed on the next context call'
);

subtest 'clean stored-function refusals retain a usable lease' => sub {
    my $executor = GPForum::Infrastructure::AsyncQuery->for_schema($schema);
    $executor->gate->concurrency(1);
    my $created = $executor->snapshot->{lease_stats}{created};
    for ( 1 .. 3 ) {
        my $error;
        $functions->row_p( 'forum_store_write',
            { store_type => 'invalid', command => {}, record => {} } )
          ->catch( sub ($caught) { $error = $caught; return; } )
          ->wait;
        isa_ok( $error, 'GPForum::X::Argument' );
    }
    is( $executor->snapshot->{lease_stats}{created},
        $created, 'business refusals do not reconnect' );
    ok( $executor->snapshot->{lease_stats}{reused_after_refusal} >= 3,
        'reuse is counted' );
    my $error;
    $functions->transaction_p(
        sub ($scope) {
            return $scope->row_p( 'forum_store_write',
                { store_type => 'invalid', command => {}, record => {} } );
        }
    )->catch( sub ($caught) { $error = $caught; return; } )->wait;
    isa_ok( $error, 'GPForum::X::Argument' );
    is( $executor->snapshot->{lease_stats}{created},
        $created, 'successful rollback preserves the clean lease' );
    my $next =
      await_result( $functions->row_p( 'admin_configuration_state', {} ) );
    is( $next->{revision}, $guest->{revision},
        'next statement succeeds on that lease' );
};

subtest 'public home and static fast paths preserve their HTTP contracts' =>
  sub {
    my $test = Test::Mojo->new('GPForum');
    $test->app->log->level('fatal');
    $test->get_ok('/')
      ->status_is(200)
      ->header_is( 'X-GPForum-Cache' => 'miss' );
    my $etag = $test->tx->res->headers->etag;
    $test->get_ok('/')->status_is(200)->header_is( 'X-GPForum-Cache' => 'hit' );
    is(
        $test->app->build_controller->gp_db_query_stats->last_request
          ->{queries},
        1,
        'home cache hit performs only the fresh request-context call'
    );
    $test->get_ok( '/' => { 'If-None-Match' => $etag } )
      ->status_is(304)
      ->content_is(q{});
    $test->get_ok('/htmx.min.js')->status_is(200);
    is(
        $test->app->build_controller->gp_db_query_stats->last_request
          ->{queries},
        0,
        'bundled JavaScript requires no application SQL'
    );
    $test->get_ok('/search?q=forum')->status_is(200);
    $test->get_ok('/search?q=forum')->status_is(200);
    is(
        $test->app->build_controller->gp_db_query_stats->last_request
          ->{queries},
        2,
        'search cache retains fresh context and durable rate limiting'
    );
  };
done_testing;
1;
