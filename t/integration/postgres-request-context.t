# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package main;
use v5.40;
use Const::Fast;
use Test::More;
use Test::Mojo;
use lib 'lib', 't/lib';
use GPForum::Test::ReplacedSubs qw(with_replaced_subs);
use GPForum::Infrastructure::SqlFunction;
use GPForum::Infrastructure::AsyncQuery;
use GPForum::Service::Identity::SessionStore;
use GPForum::Web::CookieSession;
use GPForum::Test::PgDatabase;
use GPForum::Test::Promise qw(await_result);
our $VERSION = '0.001';
const my $HTTP_OK           => 200;
const my $REFUSALS          => 3;
const my $HTTP_NOT_MODIFIED => 304;

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'temporary PostgreSQL required';
}
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
    resolve_viewer         => 1,
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
      $store->session_tokens->hash_token( $session->{session_token} ),
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
    for ( 1 .. $REFUSALS ) {
        my $error;
        $functions->row_p( 'forum_store_write',
            { store_type => 'invalid', command => {}, record => {} } )
          ->catch( sub ($caught) { $error = $caught; return; } )
          ->wait;
        isa_ok( $error, 'GPForum::X::Argument' );
    }
    is( $executor->snapshot->{lease_stats}{created},
        $created, 'business refusals do not reconnect' );
    ok( $executor->snapshot->{lease_stats}{reused_after_refusal} >= $REFUSALS,
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
    my $http_session = $store->create_session(
        { id => $thread->{author_user_id} },
        {
            request_address => '127.0.0.1',
            user_agent      => 'HTTP context integration'
        }
    );
    my $routes = $test->app->routes;
    $routes->get('/__test/context-login')->to(
        cb => sub ($c) {
            $c->session(
                GPForum::Web::CookieSession->new->login_values(
                    {
                        user_id    => $thread->{author_user_id},
                        session_id =>
                          $http_session->{session}->get_column('session_id'),
                        session_token => $http_session->{session_token},
                        rotation      => 1,
                        expires_at    => $store->clock->now_epoch +
                          $store->session_seconds,
                    }
                )
            );
            return $c->render( text => 'session installed' );
        }
    );
    my $controller = $test->app->build_controller;
    my $stats      = $controller->gp_db_query_stats;
    my @calls;
    my $query = Mojo::Pg::Database->can('query');
    with_replaced_subs(
        'Mojo::Pg::Database',
        {
            query => sub {
                my ( $native_database, $sql ) = @_;
                my ($name) = $sql =~ /api[.]([[:alnum:]_]+)/amsx;
                if ( defined $name ) { push @calls, $name; }
                return $query->(@_);
            }
        },
        sub {
            $test->get_ok(q{/})
              ->status_is($HTTP_OK)
              ->header_is( 'X-GPForum-Cache' => 'miss' );
            my $response = $test->tx->res;
            my $etag     = $response->headers->etag;
            @calls = ();
            $test->get_ok(q{/})
              ->status_is($HTTP_OK)
              ->header_is( 'X-GPForum-Cache' => 'hit' );
            is_deeply( \@calls, ['admin_configuration_snapshot_v2'],
'HTTP cache uses the revision-aware stored snapshot without fallback reads'
            );
            is( $stats->last_request->{queries},
                1,
                'home cache hit performs only the fresh request-context call' );
            $test->get_ok( q{/} => { 'If-None-Match' => $etag } )
              ->status_is($HTTP_NOT_MODIFIED)
              ->content_is(q{});
            $test->get_ok('/htmx.min.js')->status_is($HTTP_OK);
            is( $stats->last_request->{queries},
                0, 'bundled JavaScript requires no application SQL' );
            $test->get_ok('/search?q=forum')->status_is($HTTP_OK);
            $test->get_ok('/search?q=forum')->status_is($HTTP_OK);
            is( $stats->last_request->{queries}, 2,
                'search cache retains fresh context and durable rate limiting'
            );
            $test->get_ok('/__test/context-login')->status_is($HTTP_OK);
            @calls = ();
            $test->get_ok("/t/$thread->{thread_id}/$thread->{slug}")
              ->status_is($HTTP_OK);
            is(
                scalar( grep { $_ eq 'admin_request_context_v4' } @calls ),
                1,
                'signed-in HTTP request invokes the aggregate stored context'
            );
            ok(
                !(
                    grep { /\A(?:session_validate|forum_resolve_viewer)_v/amsx }
                    @calls
                ),
'signed-in context does not fall back to separate session and viewer queries'
            );
        }
    );
  };
done_testing;
1;
