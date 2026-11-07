# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package main;
use v5.40;
use lib 'lib', 't/lib';
use Const::Fast;
use Test::More;
use Test::Mojo;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Service::Identity::SessionStore;
use GPForum::Test::PgDatabase;
use GPForum::Test::ReplacedSubs qw(with_replaced_subs);
use GPForum::Web::CookieSession;
our $VERSION = '0.001';
const my $HTTP_OK          => 200;
const my $FULL_ROWS        => 50;
const my $NORMAL_BUDGET    => 2;
const my $AUTHOR_BUDGET    => 3;
const my $PERMALINK_BUDGET => 5;

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'temporary PostgreSQL required';
}
my $database = GPForum::Test::PgDatabase->fresh( seed => 1 );
local $ENV{GPFORUM_DATABASE_DSN}              = $database->dsn;
local $ENV{GPFORUM_ENV}                       = 'test';
local $ENV{GPFORUM_MINION_ENABLED}            = 0;
local $ENV{GPFORUM_REALTIME_LISTENER_ENABLED} = 0;
local $ENV{GPFORUM_WARMUP_ENABLED}            = 0;
local $ENV{GPFORUM_GLIFISTORE_URL}            = q{};
local $ENV{GPFORUM_BENCHMARK_QUERY_HEADERS}   = 1;
my $dbh    = $database->dbh;
my $thread = $dbh->selectrow_hashref(<<'SQL');
    SELECT t.thread_id,t.author_user_id,p.post_id FROM threads t
    JOIN posts p ON p.thread_id=t.thread_id
    JOIN categories c USING(category_id) JOIN spaces s USING(space_id)
    JOIN users u ON u.id=t.author_user_id
    WHERE t.visibility='public' AND t.moderation_state='visible'
      AND t.deleted_at IS NULL AND t.locked_at IS NULL
      AND c.visibility='public' AND s.visibility='public' AND u.status='active'
      AND p.visibility='public' AND p.moderation_state='visible' AND p.deleted_at IS NULL
    ORDER BY t.thread_id,p.position LIMIT 1
SQL

my ($member) = $dbh->selectrow_array(<<'SQL');
    INSERT INTO users(id,username,display_name,email_normalized,password_hash,status)
    VALUES(gen_random_uuid(),'request_budget','Request budget','request_budget@example.test','!disabled','active')
    RETURNING id
SQL

my $store =
  GPForum::Service::Identity::SessionStore->new( schema => $database->schema );
my %sessions;

for my $actor ( [ 'member', $member ], [ 'author', $thread->{author_user_id} ] )
{
    my $login = $store->create_session(
        { id => $actor->[1] },
        {
            request_address => '127.0.0.1',
            user_agent      => 'thread request budget fixture'
        }
    );
    $sessions{ $actor->[0] } = {
        user_id       => $actor->[1],
        session_id    => $login->{session}->get_column('session_id'),
        session_token => $login->{session_token},
        rotation      => 1,
        expires_at    => $store->clock->now_epoch + $store->session_seconds,
    };
}
my $test = Test::Mojo->new('GPForum');
$test->app->log->level('error');
my $last_user;
$test->app->hook(
    after_dispatch => sub ($c) { $last_user = $c->session('user_id'); return; }
);
my $routes = $test->app->routes;
$routes->get('/__budget/session/:actor')->to(
    cb => sub ($c) {
        GPForum::Web::CookieSession->new->replace_login( $c,
            $sessions{ $c->param('actor') } );
        return $c->render( text => 'session installed' );
    }
);
my @cases = (
    [ 'normal', 'member', q{}, {}, $NORMAL_BUDGET, 1 ],
    [ 'author', 'author', q{}, {}, $AUTHOR_BUDGET, 1 ],
    [
        'permalink', 'member',
        '&post=' . $thread->{post_id}, {},
        $PERMALINK_BUDGET, 0
    ],
    [ 'HTMX', 'member', q{}, { 'HX-Request' => 'true' }, $NORMAL_BUDGET, 1 ],
    [
        'author HTMX',  'author', q{}, { 'HX-Request' => 'true' },
        $NORMAL_BUDGET, 1
    ],
);
my @calls;
my $capture = 0;
my $query   = Mojo::Pg::Database->can('query');
with_replaced_subs(
    'Mojo::Pg::Database',
    {
        query => sub {
            my ( $db, $sql ) = @_;
            if ($capture) { push @calls, $sql; }
            return $query->(@_);
        },
    },
    sub {
        for my $case (@cases) {
            my ( $name, $actor, $suffix, $headers, $budget, $snapshot ) =
              @{$case};
            subtest "$name has an independent request budget" => sub {
                $test->get_ok( '/__budget/session/' . $actor )
                  ->status_is($HTTP_OK);
                my $path = '/t/' . $thread->{thread_id} . '?limit=';
                $test->get_ok( $path . $FULL_ROWS . $suffix => $headers )
                  ->status_is($HTTP_OK);
                for my $limit ( 1, $FULL_ROWS ) {
                    my $controller = $test->app->build_controller;
                    my $cache      = $controller->gp_local_cache;
                    for my $tag (qw(categories forum-index forum:public-html)) {
                        $cache->invalidate_tag($tag);
                    }
                    @calls   = ();
                    $capture = 1;
                    $test->get_ok( $path . $limit . $suffix => $headers )
                      ->status_is($HTTP_OK);
                    $capture = 0;
                    is(
                        $last_user,
                        $actor eq 'author'
                        ? $thread->{author_user_id}
                        : $member,
                        'the durable session is the intended actor'
                    );

                    is(
                        scalar @calls,
                        $budget,
"$name/$limit stays at $budget SQL commands including live context"
                    );
                    $test->header_is( 'X-GPForum-DB-Queries' => $budget );
                    my $snapshots = grep {
                        /api[.]forum_thread_page_snapshot_v[[:digit:]]+/msx
                    } @calls;
                    is( $snapshots, $snapshot,
                        'the intended aggregate or permalink path was exercised'
                    );
                    $test->element_exists('article[id^="post-"]');
                    if ($snapshot) {
                        is(
                            scalar(
                                grep {
/api[.]forum_thread_page_(?:head|posts|reads)_v/msx
                                } @calls
                            ),
                            0,
'no separate head, post or ancillary read can hide within a loose budget'
                        );
                    }
                }
                return;
            };
        }
        return;
    }
);
done_testing;
1;
