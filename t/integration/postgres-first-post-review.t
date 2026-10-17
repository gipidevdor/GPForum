# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use Mojo::JSON qw(decode_json);
use Test::Mojo;
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Benchmark::SeedDataset qw(seed_id);
use GPForum::Command::AdminBootstrap;
use GPForum::Infrastructure::Id;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Service::Moderation::AutomodStore;
use GPForum::Service::Moderation::ReviewStore;
use GPForum::Test::PgDatabase;
use GPForum::Test::PostgresHarness;

our $VERSION = '0.001';

const my $HTTP_OK           => 200;
const my $HTTP_ACCEPTED     => 202;
const my $HTTP_CREATED      => 201;
const my $HTTP_FOUND        => 302;
const my $HTTP_INVALID      => 400;
const my $HTTP_UNAUTHORIZED => 401;
const my $HTTP_FORBIDDEN    => 403;
const my $HTTP_MISSING      => 404;
const my $HTTP_CONFLICT     => 409;
const my $TWO               => 2;
const my $THREE             => 3;
const my $TOO_MANY          => 21;
const my $TOO_LONG          => 501;
const my $JSON              => { Accept => 'application/json' };

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'set GPFORUM_TEST_DSN for the first-post review queue';
}

# ADR 0134 on a migrated, seeded PostgreSQL: the review rule, holding a new
# member's first posts outside threads and posts, the author's list, the
# staff's queue and decisions, and that held content reaches nobody else.
local $ENV{GPFORUM_MINION_ENABLED}            = 0;
local $ENV{GPFORUM_REALTIME_LISTENER_ENABLED} = 0;
my $database = GPForum::Test::PgDatabase->fresh( seed => 1 );
local $ENV{GPFORUM_DATABASE_DSN} = $database->dsn;
my $schema    = $database->schema;
my $dbh       = $database->dbh;
my $ids       = GPForum::Infrastructure::Id->new;
my $functions = GPForum::Infrastructure::SqlFunction->new( schema => $schema );
my $store     = GPForum::Service::Moderation::ReviewStore->new(
    schema    => $schema,
    functions => $functions
);
my $automod = GPForum::Service::Moderation::AutomodStore->new(
    schema    => $schema,
    functions => $functions
);
my $admin       = _user( 'review_admin',    1 );
my $newcomer    = _user( 'review_newcomer', 0 );
my $other       = _user( 'review_other',    0 );
my $veteran     = seed_id( user => 2 );
my ($thread_id) = $dbh->selectrow_array(
        q{SELECT t.thread_id FROM threads t WHERE t.deleted_at IS NULL}
      . q{ AND t.locked_at IS NULL AND t.moderation_state = 'visible'}
      . q{ AND t.visibility = 'public' ORDER BY t.thread_id LIMIT 1} );

subtest 'staff set the review rule, every change audited' => sub {
    is_deeply( [ @{ $automod->rules_for($newcomer) }{qw(review_first_posts)} ],
        [0], 'the rule is off by default' );
    is(
        $store->set_rule(
            { actor_user_id => $admin, first_posts => '1', flagged => 0 }
        )->{status},
        'ok',
        'one first post is held'
    );
    is(
        $store->set_rule(
            { actor_user_id => $admin, first_posts => '1', flagged => 0 }
        )->{status},
        'unchanged',
        'setting it again changes nothing'
    );
    is_deeply(
        $store->set_rule(
            { actor_user_id => $admin, first_posts => $TOO_MANY }
        ),
        { ok => 0, status => 'invalid', field => 'first_posts' },
        'at most 20 posts'
    );
    is(
        $functions->row(
            'moderation_review_settings_set',
            {
                first_posts   => $TOO_MANY,
                flagged       => 0,
                actor_user_id => $admin,
                now           => '2026-10-15T00:00:00Z',
                audit         => {},
            }
        )->{status},
        'invalid',
        'and the function refuses more as well'
    );
    is( _audits('review.rule_set'), 1, 'the change is audited once' );
    my $rules = $automod->rules_for($newcomer);
    is_deeply(
        [ @{$rules}{qw(review_first_posts published_posts)} ],
        [ 1, 0 ],
        'the rules carry the rule and the author\'s published posts'
    );
    ok(
        $automod->rules_for($veteran)->{published_posts} >= 1,
        'a member who posted has published posts'
    );
};

my ( $held_reply, $body ) = ( undef, 'Hello there, zebracorn enthusiasts' );
subtest 'a new member\'s first reply is held, and reaches nobody' => sub {
    my $test   = _session($newcomer);
    my $posts  = _posts();
    my $counts = _reply_count();
    $test->get_ok("/t/$thread_id")->status_is($HTTP_OK);
    my %form = _composer($test);
    $test->post_ok( "/t/$thread_id/replies" => $JSON => form =>
          { %form, body_source => $body } )->status_is($HTTP_ACCEPTED);
    $test->json_is( '/status' => 'held' )->json_is( '/kind' => 'reply' );
    $held_reply = _answer($test)->{review_id};
    ok( $ids->is_uuid_spelling($held_reply), 'the answer names the entry' );
    is( _posts(),               $posts,  'no post is stored' );
    is( _reply_count(),         $counts, 'and the thread counts nothing' );
    is( _audits('review.held'), 1,       'the hold is audited' );
    is( _containing( 'outbox_messages', 'payload' ),
        0, 'nothing reaches the outbox (realtime, notifications, search)' );
    is( _containing( 'event_log',        'payload' ), 0, 'nor the event log' );
    is( _containing( 'search_documents', 'body' ),    0, 'nor search' );

    $test->post_ok( "/t/$thread_id/replies" => $JSON => form =>
          { %form, body_source => $body } )
      ->status_is($HTTP_ACCEPTED)
      ->json_is(
        '/review_id' => $held_reply,
        'the same submission again is the same entry'
      );

    my $reader = _session($other);
    $reader->get_ok("/t/$thread_id")
      ->status_is($HTTP_OK)
      ->content_unlike( qr/zebracorn/msx, 'another member does not see it' );
    $reader->get_ok( "/t/$thread_id" => $JSON )
      ->content_unlike( qr/zebracorn/msx, 'nor in the thread\'s JSON' );
    $reader->get_ok('/pending')
      ->status_is($HTTP_OK)
      ->content_unlike( qr/zebracorn/msx, 'nor on their own list' );
    Test::Mojo->new('GPForum')
      ->get_ok("/t/$thread_id")
      ->content_unlike( qr/zebracorn/msx, 'nor does a guest' );
    Test::Mojo->new('GPForum')
      ->get_ok('/pending')
      ->status_is($HTTP_UNAUTHORIZED);

    $test->get_ok('/pending')->status_is($HTTP_OK);
    $test->content_like( qr/zebracorn/msx, 'the author sees it' )
      ->content_like( qr/Awaiting [ ] review/msx, 'as awaiting review' );
    $test->get_ok( '/pending' => $JSON )
      ->status_is($HTTP_OK)
      ->json_is( '/held_posts/0/status' => 'pending' );

    $test->get_ok("/t/$thread_id");
    $test->post_ok( "/t/$thread_id/replies" => form =>
          { _composer_fresh($test), body_source => 'A second first post' } )
      ->status_is($HTTP_FOUND)
      ->header_like(
        Location => qr{/pending\z}msx,
        'a form is sent to the list'
      );
};

subtest 'the staff queue: members are kept out, staff decide' => sub {
    my $member = _session($newcomer);
    $member->get_ok('/moderation/review')->status_is($HTTP_FORBIDDEN);
    $member->post_ok( "/moderation/review/$held_reply/approve" => form =>
          { csrf_token => _csrf($member) } )
      ->status_is( $HTTP_FORBIDDEN, 'and decide nothing' );

    my $staff = _session($admin);
    $staff->get_ok('/moderation/review')->status_is($HTTP_OK);
    $staff->content_like( qr/zebracorn/msx, 'the queue shows the post' )
      ->content_like( qr/review_newcomer/msx, 'and its author' );
    $staff->element_exists(
        qq{form[action="/moderation/review/$held_reply/approve"]});
    $staff->get_ok( '/moderation/review' => $JSON )
      ->json_is( '/pending_total' => $TWO );

    my $posts = _posts();
    $staff->post_ok( "/moderation/review/$held_reply/approve" => form =>
          { csrf_token => _csrf($staff) } )->status_is($HTTP_FOUND);
    is( _posts(), $posts + 1, 'an approval publishes the post' );
    my $held = _held($held_reply);
    is( $held->{status}, 'approved', 'and records the decision' );
    is(
        scalar $dbh->selectrow_array(
            q{SELECT p.author_user_id FROM posts p WHERE p.post_id = ?},
            undef, $held->{post_id}
        ),
        $newcomer,
        'as the author\'s post'
    );
    is( _audits('review.approved'), 1, 'audited' );
    is( _notifications( $newcomer, 'review_approved' ),
        1, 'and the author is told' );
    $staff->post_ok(
        "/moderation/review/$held_reply/approve" => $JSON => form =>
          { csrf_token => _csrf($staff) } )
      ->status_is($HTTP_OK)
      ->json_is( '/status' => 'unchanged' );
    is( _posts(), $posts + 1, 'approving again publishes nothing more' );
    $staff->post_ok( "/moderation/review/$held_reply/reject" => $JSON => form =>
          { csrf_token => _csrf($staff) } )->status_is($HTTP_CONFLICT);

    my $test = _session($newcomer);
    $test->get_ok('/pending')->content_like(qr/Approved/msx);
    $test->get_ok("/t/$thread_id")->status_is($HTTP_OK);
    $test->post_ok( "/t/$thread_id/replies" => $JSON => form =>
          { _composer_fresh($test), body_source => 'Now a regular' } )
      ->status_is( $HTTP_CREATED,
        'with a published post the member is not held' );
};

subtest 'rejections, withdrawals and refusals' => sub {
    my $newer = _user( 'review_newer', 0 );
    my $test  = _session($newer);
    $test->get_ok('/new-thread')->status_is($HTTP_OK);
    my %thread = _composer($test);
    $test->post_ok(
        '/threads' => $JSON => form => {
            %thread,
            category_id => seed_id( category => 1 ),
            title       => 'A held thread',
            body_source => 'The opening post of a held thread',
        }
    )->status_is($HTTP_ACCEPTED)->json_is( '/kind' => 'thread' );
    my $held_thread = _answer($test)->{review_id};
    is(
        scalar $dbh->selectrow_array(
            q{SELECT count(*) FROM threads WHERE title = 'A held thread'}),
        0,
        'a held thread is no thread'
    );

    my $staff = _session($admin);
    $staff->post_ok(
        "/moderation/review/$held_thread/reject" => form => {
            csrf_token => _csrf($staff),
            reason     => 'Off topic here'
        }
    )->status_is($HTTP_FOUND);
    is( _held($held_thread)->{status}, 'rejected', 'a rejection is recorded' );
    is( _audits('review.rejected'),    1,          'and audited' );
    $test->get_ok('/pending')->content_like( qr/Off [ ] topic [ ] here/msx,
        'the author reads the reason' );
    $staff->post_ok(
        "/moderation/review/$held_thread/reject" => $JSON => form => {
            csrf_token => _csrf($staff),
            reason     => 'x' x $TOO_LONG
        }
    )->status_is( $HTTP_INVALID, 'a reason is at most 500 characters' );

    $test->get_ok("/t/$thread_id");
    $test->post_ok( "/t/$thread_id/replies" => $JSON => form =>
          { _composer_fresh($test), body_source => 'Withdraw me' } )
      ->status_is($HTTP_ACCEPTED);
    my $withdrawn = _answer($test)->{review_id};
    my $stranger  = _session($other);
    $stranger->post_ok( "/pending/$withdrawn/withdraw" => form =>
          { csrf_token => _csrf($stranger) } )
      ->status_is( $HTTP_MISSING, 'only the author withdraws a post' );
    $test->post_ok( "/pending/$withdrawn/withdraw" => form =>
          { csrf_token => _csrf($test) } )->status_is($HTTP_FOUND);
    is( _held($withdrawn)->{status}, 'withdrawn', 'the author withdrew it' );

    $test->get_ok("/t/$thread_id");
    $test->post_ok( "/t/$thread_id/replies" => $JSON => form =>
          { _composer_fresh($test), body_source => 'Too late for this' } )
      ->status_is($HTTP_ACCEPTED);
    my $late = _answer($test)->{review_id};
    $dbh->do( q{UPDATE threads SET locked_at = now() WHERE thread_id = ?},
        undef, $thread_id );
    my $posts = _posts();
    $staff->post_ok( "/moderation/review/$late/approve" => $JSON => form =>
          { csrf_token => _csrf($staff) } )
      ->status_is($HTTP_CONFLICT)
      ->json_is( '/status' => 'refused' );
    is( _posts(),               $posts,    'a locked thread takes no post' );
    is( _held($late)->{status}, 'pending', 'and the post stays pending' );
    $staff->post_ok( "/moderation/review/$late/reject" => form =>
          { csrf_token => _csrf($staff) } )->status_is($HTTP_FOUND);
    is( _notifications( $newer, 'review_rejected' ),
        1, 'a rejected reply is notified on its thread' );
    $dbh->do( q{UPDATE threads SET locked_at = NULL WHERE thread_id = ?},
        undef, $thread_id );

    $test->get_ok('/new-thread')->status_is($HTTP_OK);
    $test->post_ok(
        '/threads' => $JSON => form => {
            _composer_fresh($test),
            category_id => seed_id( category => 1 ),
            title       => 'An approved thread',
            body_source => 'The opening post, approved',
        }
    )->status_is($HTTP_ACCEPTED);
    my $approved = _answer($test)->{review_id};
    $staff->post_ok( "/moderation/review/$approved/approve" => $JSON => form =>
          { csrf_token => _csrf($staff) } )
      ->status_is($HTTP_OK)
      ->json_is( '/status' => 'ok' );
    my $thread = _answer($staff)->{thread_id};
    is(
        scalar $dbh->selectrow_array(
            q{SELECT author_user_id FROM threads WHERE thread_id = ?}
              . q{ AND title = 'An approved thread'},
            undef,
            $thread
        ),
        $newer,
        'an approved thread is published as its author\'s'
    );
    is( _notifications( $newer, 'review_approved' ), 1, 'and its author told' );
};

subtest 'flagged posts held when staff ask, and staff never held' => sub {
    $store->set_rule(
        { actor_user_id => $admin, first_posts => '0', flagged => 1 } );
    $automod->add_word(
        { actor_user_id => $admin, phrase => 'casino', action => 'flag' } );
    my $test = _session($veteran);
    $test->get_ok("/t/$thread_id");
    my $reports = _reports();
    $test->post_ok( "/t/$thread_id/replies" => $JSON => form =>
          { _composer_fresh($test), body_source => 'Visit my casino' } )
      ->status_is($HTTP_ACCEPTED);
    my $flagged = _held( _answer($test)->{review_id} );
    is( $flagged->{reason}, 'flagged', 'a flagged reply is held' );
    is_deeply( $flagged->{details}{flagged},
        ['casino'], 'with what the rules found' );
    is( _reports(), $reports, 'instead of published with a report' );

    my $staff = _session($admin);
    $staff->get_ok("/t/$thread_id");
    $staff->post_ok( "/t/$thread_id/replies" => $JSON => form =>
          { _composer_fresh($staff), body_source => 'Quoting: casino' } )
      ->status_is( $HTTP_CREATED, 'staff who moderate are not held' );
};

subtest 'the admin console sets the rule' => sub {
    my $staff = _session($admin);
    $staff->get_ok('/admin/automod')
      ->status_is($HTTP_OK)
      ->element_exists('form[action="/admin/automod/review"]');
    $staff->post_ok(
        '/admin/automod/review' => form => {
            csrf_token         => _csrf($staff),
            review_first_posts => $THREE,
        }
    )->status_is($HTTP_FOUND);
    is_deeply( [ @{ $automod->rules_for(undef) }{qw(review_first_posts)} ],
        [$THREE],
        'the form sets the rule (and an unchecked box clears flagged)' );
    ok( !$automod->rules_for(undef)->{review_flagged}, 'flagged is off' );
    my $member = _session($newcomer);
    $member->post_ok( '/admin/automod/review' => form =>
          { csrf_token => _csrf($member), review_first_posts => '0' } )
      ->status_is( $HTTP_FORBIDDEN, 'a member changes nothing' );
};

subtest 'a post whose author was suspended since is not published' => sub {
    $store->set_rule(
        { actor_user_id => $admin, first_posts => '1', flagged => 0 } );
    my $author = _user( 'review_suspended', 0 );
    my $test   = _session($author);
    $test->get_ok("/t/$thread_id");
    $test->post_ok( "/t/$thread_id/replies" => $JSON => form =>
          { _composer_fresh($test), body_source => 'Written before' } )
      ->status_is($HTTP_ACCEPTED);
    my $review_id = _answer($test)->{review_id};
    my ($suspension) = $dbh->selectrow_array(
        q{INSERT INTO suspensions (suspension_id, user_id, actor_user_id,}
          . q{ reason, valid_from) VALUES (gen_random_uuid(), ?, ?, 'spam',}
          . q{ now() - interval '1 minute') RETURNING suspension_id},
        undef, $author, $admin
    );

    my $staff = _session($admin);
    my $posts = _posts();
    $staff->post_ok( "/moderation/review/$review_id/approve" => $JSON => form =>
          { csrf_token => _csrf($staff) } )
      ->status_is($HTTP_CONFLICT)
      ->json_is( '/status' => 'refused' );
    is( _posts(), $posts, 'a suspended author\'s post is not published' );
    is( _held($review_id)->{status}, 'pending',          'and stays pending' );
    is( _notifications( $author, 'review_approved' ), 0, 'nobody is told' );

    $dbh->do(
        q{UPDATE suspensions SET revoked_at = now()}
          . q{ WHERE suspension_id = ?},
        undef, $suspension
    );
    $staff->post_ok( "/moderation/review/$review_id/approve" => $JSON => form =>
          { csrf_token => _csrf($staff) } )
      ->status_is($HTTP_OK)
      ->json_is( '/status' => 'ok' );
    is( _posts(), $posts + 1, 'once the suspension is lifted it is' );
};

subtest 'an erased member\'s held posts go, and an export has them' => sub {
    my $document =
      $functions->row( 'portability_export_parts', { user_id => $other } )
      ->{document};
    is_deeply( $document->{held_posts}, [], 'nothing held is nothing' );
    my $newer = $dbh->selectrow_array(
        q{SELECT id FROM users WHERE username = 'review_newer'});
    my $exported =
      $functions->row( 'portability_export_parts', { user_id => $newer } )
      ->{document}{held_posts};
    ok( scalar @{$exported} >= $TWO, 'the author\'s held posts are exported' );
    ok( !exists $exported->[0]{decided_by_user_id}, 'never who decided' );
    $functions->row( 'privacy_revoke_user',
        { source => 'HeldPost', user_id => $newer, at => '2026-10-15' } );
    is(
        scalar $dbh->selectrow_array(
            q{SELECT count(*) FROM held_posts WHERE author_user_id = ?},
            undef, $newer
        ),
        0,
        'erasure removes them'
    );
};

done_testing();

sub _audits ($action) {
    return
      scalar $dbh->selectrow_array(
        q{SELECT count(*) FROM audit_log WHERE action = ?},
        undef, $action );
}

sub _posts {
    return
      scalar $dbh->selectrow_array(
        q{SELECT count(*) FROM posts WHERE thread_id = ?},
        undef, $thread_id );
}

sub _reply_count {
    return
      scalar $dbh->selectrow_array(
        q{SELECT reply_count FROM thread_counters WHERE thread_id = ?},
        undef, $thread_id );
}

sub _reports {
    return scalar $dbh->selectrow_array(q{SELECT count(*) FROM reports});
}

sub _containing ( $table, $column ) {
    return
      scalar $dbh->selectrow_array(
        qq{SELECT count(*) FROM $table WHERE $column\::text LIKE ?},
        undef, '%zebracorn%' );
}

# The JSON the client was last answered.
sub _answer ($test) {
    my $response = $test->tx->res;

    return $response->json // {};
}

sub _held ($review_id) {
    my $row =
      $dbh->selectrow_hashref( q{SELECT * FROM held_posts WHERE review_id = ?},
        undef, $review_id );
    if ( $row && !ref $row->{details} ) {
        $row->{details} = decode_json( $row->{details} );
    }

    return $row;
}

sub _notifications ( $user_id, $type ) {
    return scalar $dbh->selectrow_array(
        q{SELECT count(*) FROM notifications}
          . q{ WHERE recipient_user_id = ? AND notification_type = ?},
        undef, $user_id, $type
    );
}

sub _composer ($test) {
    my $dom = $test->tx->res->dom;

    return _fields( $dom->at('form[data-composer]') );
}

# The composer of the page last read, with a fresh command id.
sub _composer_fresh ($test) {
    my %form = _composer($test);

    return ( %form, command_id => $ids->uuid );
}

sub _fields ($form) {
    return
      map { $_->attr('name') => $_->attr('value') }
      @{ $form->find('input[name]')->to_array };
}

sub _csrf ($test) {
    $test->get_ok('/settings');
    my $dom   = $test->tx->res->dom;
    my $input = $dom->at('input[name=csrf_token]');

    return $input ? $input->attr('value') : q{};
}

# A browser signed in as the user.
sub _session ($user_id) {
    my $test   = Test::Mojo->new('GPForum');
    my $routes = $test->app->routes;
    $routes->get('/__test/review-session')->to(
        cb => sub ($c) {
            $c->session( user_id => $user_id );
            return $c->render( json => { ok => 1 } );
        }
    );
    $test->get_ok('/__test/review-session')->status_is($HTTP_OK);

    return $test;
}

# A new active member, given the bootstrap administration role when asked.
sub _user ( $name, $administrator ) {
    my ($id) = $dbh->selectrow_array(
        q{INSERT INTO users (id, username, display_name, email_normalized,}
          . q{ password_hash, status, email_verified_at) VALUES}
          . q{ (gen_random_uuid(), ?, ?, ?, 'x', 'active', now()) RETURNING id},
        undef, $name, $name, "$name\@example.test"
    );
    if ($administrator) {
        GPForum::Test::PostgresHarness::quietly(
            sub {
                return GPForum::Command::AdminBootstrap->new->run( 'grant',
                    '--user-id', $id );
            }
        );
    }

    return $id;
}

1;
