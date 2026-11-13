# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package main;
use v5.40;
use Const::Fast;
use File::Temp qw(tempdir);
use Test::More;
use Test::Mojo;
use lib 'lib', 't/lib';
use GPForum::Infrastructure::Id;
use GPForum::Infrastructure::AsyncWork;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Test::PgDatabase;
use GPForum::Test::ReplacedSubs qw(with_replaced_subs);

our $VERSION = '0.001';
const my $HTTP_OK          => 200;
const my $HTTP_CREATED     => 201;
const my $HTTP_CONFLICT    => 409;
const my $HTTP_UNAVAILABLE => 503;
if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'requires PostgreSQL';
}
my $database = GPForum::Test::PgDatabase->fresh( seed => 1 );
local $ENV{GPFORUM_DATABASE_DSN}              = $database->dsn;
local $ENV{GPFORUM_ENV}                       = 'test';
local $ENV{GPFORUM_MINION_ENABLED}            = 0;
local $ENV{GPFORUM_REALTIME_LISTENER_ENABLED} = 0;
local $ENV{GPFORUM_WARMUP_ENABLED}            = 0;
local $ENV{GPFORUM_POST_SIGNING_KEY} = tempdir( CLEANUP => 1 ) . '/post.pem';
my $dbh = $database->dbh;
my ( $owner, $category ) = $dbh->selectrow_array(
    (
        join q{ },
q{SELECT p.author_user_id,t.category_id FROM posts p JOIN threads t USING(thread_id)},
        q{JOIN categories c USING(category_id) JOIN spaces s USING(space_id)},
        q{JOIN users u ON u.id=p.author_user_id},
q{WHERE p.visibility='public' AND p.moderation_state='visible' AND p.deleted_at IS NULL},
q{AND t.visibility='public' AND t.moderation_state='visible' AND t.deleted_at IS NULL},
q{AND c.visibility='public' AND s.visibility='public' AND u.status='active'},
        q{AND NOT api.core_product_staff_v1(u.id,'thread','moderate') LIMIT 1}
    )
);
ok( $owner, 'a non-moderator fixture author is available' );
my ($foreign_post) = $dbh->selectrow_array(
    (
        join q{ },
        q{SELECT p.post_id FROM posts p JOIN threads t USING(thread_id)},
        q{JOIN categories c USING(category_id) JOIN spaces s USING(space_id)},
q{WHERE p.author_user_id<>? AND p.visibility='public' AND p.moderation_state='visible'},
q{AND p.deleted_at IS NULL AND t.visibility='public' AND t.moderation_state='visible'},
q{AND t.deleted_at IS NULL AND c.visibility='public' AND s.visibility='public' LIMIT 1}
    ),
    undef, $owner
);
my $test   = Test::Mojo->new('GPForum');
my $routes = $test->app->routes;
$routes->get('/__native_command_session')->to(
    cb => sub($c) {
        $c->session( user_id => $owner );
        return $c->render( text => 'ready' );
    }
);
$test->get_ok('/__native_command_session')->status_is($HTTP_OK);
my $original = GPForum::Infrastructure::SqlFunction->can('rows_p');
my %called;
with_replaced_subs(
    'GPForum::Infrastructure::SqlFunction',
    {
        rows_p => sub { $called{ $_[1] }++; return $original->(@_); }
    },
    sub {
        $test->get_ok('/new-thread')->status_is($HTTP_OK);
        my $fields       = _fields('form[action="/threads"]');
        my $thread_input = {
            %{$fields},
            category_id => $category,
            title       => 'Native command transport',
            body_source =>
              'Composition and signing stay isolated from PostgreSQL.'
        };
        $test->post_ok(
            '/threads' => { Accept => 'application/json' } => form =>
              $thread_input )->status_is($HTTP_CREATED);
        my $created = $test->tx->res->json;
        my $thread  = $created->{thread_id};
        ok( $thread, 'new thread created' );
        is( $called{forum_write_command},
            1, 'thread command executes through the parent native connection' );
        $test->post_ok(
            '/threads' => { Accept => 'application/json' } => form =>
              $thread_input )->status_is($HTTP_CREATED);
        my $replayed = $test->tx->res->json;
        is( $replayed->{thread_id},
            $thread, 'native command replay returns the original thread' );
        $test->post_ok(
            '/threads' => { Accept => 'application/json' } => form => {
                %{$thread_input}, title => 'Different request with reused key'
            }
        )->status_is($HTTP_CONFLICT);
        my ($created_count) =
          $dbh->selectrow_array( 'SELECT count(*) FROM threads WHERE title=?',
            undef, $thread_input->{title} );
        is( $created_count, 1,
            'replay and conflicting key create no duplicate' );
        $test->get_ok("/t/$thread")->status_is($HTTP_OK);
        $fields = _fields( 'form[action="/t/' . $thread . '/replies"]' );
        $test->post_ok(
            "/t/$thread/replies" => { Accept => 'application/json' } => form =>
              {
                %{$fields},
                body_source =>
                  'Native reply command with the existing signature.'
              }
        )->status_is($HTTP_CREATED);
        is( $called{forum_create_reply},
            1, 'reply command executes through the parent native connection' );
        my $replied = $test->tx->res->json;
        my $post    = $replied->{post_id};
        my $csrf    = $fields->{csrf_token};

        for my $operation (
            [ "/p/$foreign_post/like",      'community_like_command',      {} ],
            [ "/t/$thread/bookmark",        'community_bookmark_command',  {} ],
            [ "/t/$thread/bookmark/remove", 'community_target_command',    {} ],
            [ "/t/$thread/subscribe",       'community_subscribe_command', {} ],
            [ "/t/$thread/subscribe/mute",  'community_target_command',    {} ],
            [ "/t/$thread/subscribe/remove", 'community_target_command',   {} ],
            [
                "/t/$thread/read", 'forum_read_marker_command',
                { last_read_position => 1 }
            ],
          )
        {
            my ( $path, $function, $extra ) = @{$operation};
            my $expected = ( $called{$function} // 0 ) + 1;
            my $form     = {
                csrf_token => $csrf,
                command_id => GPForum::Infrastructure::Id->new->uuid,
                %{$extra}
            };
            my $forks = 0;
            my $run   = GPForum::Infrastructure::AsyncWork->can('run_p');
            with_replaced_subs(
                'GPForum::Infrastructure::AsyncWork',
                { run_p => sub { $forks++; return $run->(@_); } },
                sub {
                    $test->post_ok(
                        $path => { Accept => 'application/json' } => form =>
                          $form )->status_is($HTTP_OK);
                }
            );
            is( $forks, 0, "$function and its security preflight never fork" );
            is( $called{$function}, $expected,
                "$function uses the parent native connection" );
            if ( $function eq 'community_target_command' ) {
                my $answer = $test->tx->res->json;
                $test->post_ok(
                    $path => { Accept => 'application/json' } => form => $form )
                  ->status_is($HTTP_OK);
                is_deeply( $test->tx->res->json,
                    $answer,
                    'atomic target command replays the recorded response' );
            }
        }
        _rollback_target_command( $thread, $csrf );
        my $written = $called{forum_write_command};
        cmp_ok( $called{moderation_can_participate},
            '>', 0,
            'participation checks use live native SQL in the parent process' );
        for my $operation (
            [ "/t/$thread/edit", { title => 'Edited through native SQL' } ],
            [
                "/p/$post",
                {
                    body_source      => 'Edited native reply.',
                    expected_version => 1
                }
            ],
            [ "/p/$post/delete",    {} ],
            [ "/p/$post/restore",   {} ],
            [ "/t/$thread/delete",  {} ],
            [ "/t/$thread/restore", {} ],
          )
        {
            my ( $path, $extra ) = @{$operation};
            $test->post_ok(
                $path => { Accept => 'application/json' } => form => {
                    csrf_token => $csrf,
                    command_id => GPForum::Infrastructure::Id->new->uuid,
                    %{$extra}
                }
            )->status_is($HTTP_OK);
            $written++;
            is( $called{forum_write_command},
                $written, "$path executes the atomic native command" );
        }
    }
);
done_testing();

sub _rollback_target_command ( $thread, $csrf ) {
    $test->post_ok(
        "/t/$thread/bookmark" => { Accept => 'application/json' } => form => {
            csrf_token => $csrf,
            command_id => GPForum::Infrastructure::Id->new->uuid
        }
    )->status_is($HTTP_OK);
    $dbh->do(
        join q{ },
        q{CREATE FUNCTION pg_temp.fail_community_close() RETURNS trigger},
q{LANGUAGE plpgsql AS $body$ BEGIN RAISE EXCEPTION 'command close failure'; END; $body$}
    );
    $dbh->do(
        join q{ },
        q{CREATE TRIGGER fail_community_close AFTER UPDATE ON command_log},
        q{FOR EACH ROW WHEN (NEW.command_type='community.bookmark_remove')},
        q{EXECUTE FUNCTION pg_temp.fail_community_close()}
    );
    my $key  = GPForum::Infrastructure::Id->new->uuid;
    my $form = { csrf_token => $csrf, command_id => $key };
    $test->post_ok(
        "/t/$thread/bookmark/remove" => { Accept => 'application/json' } =>
          form => $form )->status_is($HTTP_UNAVAILABLE);
    my ($deleted) = $dbh->selectrow_array(
q{SELECT deleted_at FROM bookmarks WHERE user_id=? AND target_type='thread' AND target_id=?},
        undef, $owner, $thread
    );
    is( $deleted, undef,
        'failure closing the command log rolls back target removal' );
    my ($logged) = $dbh->selectrow_array(
        q{SELECT count(*) FROM command_log WHERE idempotency_key=?},
        undef, $key );
    is( $logged, 0, 'failed atomic command leaves no recorded answer' );
    $dbh->do('DROP TRIGGER fail_community_close ON command_log');
    $dbh->do('DROP FUNCTION pg_temp.fail_community_close()');
    $test->post_ok(
        "/t/$thread/bookmark/remove" => { Accept => 'application/json' } =>
          form => $form )->status_is($HTTP_OK);
    return;
}

sub _fields($selector) {
    my $response = $test->tx->res;
    my $form     = $response->dom->at($selector);
    ok( $form, "form $selector exists" );
    return { map { $_->attr('name') => $_->attr('value') // q{} }
          $form->find('input[type="hidden"][name]')->each };
}
1;
