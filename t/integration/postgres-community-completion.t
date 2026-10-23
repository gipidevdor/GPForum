# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;
use Const::Fast;
use Digest::SHA qw(sha256_hex);
use JSON::MaybeXS;
use Time::HiRes qw(time);
use Mojo::File  qw(path);
use Test::More;
use Test::Mojo;
use lib 'lib';
use lib 't/lib';
use GPForum::Command::AdminBootstrap;
use GPForum::Infrastructure::Id;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Service::Identity::Admission;
use GPForum::Service::Forum::Polls;
use GPForum::Service::Moderation::ThreadTransfers;
use GPForum::Test::PgDatabase;
use GPForum::Test::PostgresHarness;

our $VERSION = '0.001';
const my $HTTP_OK        => 200;
const my $HTTP_FOUND     => 302;
const my $HTTP_FORBIDDEN => 403;
const my $HTTP_CONFLICT  => 409;
const my $PASSWORD       => 'Example password long enough 2026';
const my $READ_SAMPLES   => 100;
const my $MILLISECONDS   => 1000;
const my $POSTS          => 5;
const my $REPLY          => 2;
const my $LAST           => 5;
const my $OPTIONS        => [ 'One', 'Two', 'Three' ];
const my $JSON           => { Accept => 'application/json' };

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'set GPFORUM_TEST_DSN for community completion';
}
local $ENV{GPFORUM_MINION_ENABLED}            = 0;
local $ENV{GPFORUM_REALTIME_LISTENER_ENABLED} = 0;
my $database = GPForum::Test::PgDatabase->fresh( seed => 1 );
local $ENV{GPFORUM_DATABASE_DSN} = $database->dsn;
my $schema     = $database->schema;
my $dbh        = $database->dbh;
my $ids        = GPForum::Infrastructure::Id->new;
my $functions  = GPForum::Infrastructure::SqlFunction->new( schema => $schema );
my $staff      = _user( 'completion_staff',  1 );
my $author     = _user( 'completion_author', 0 );
my $voter      = _user( 'completion_voter',  0 );
my ($category) = $dbh->selectrow_array(
q{SELECT c.category_id FROM categories c JOIN spaces s ON s.space_id=c.space_id WHERE c.visibility='public' AND s.visibility='public' AND c.deleted_at IS NULL LIMIT 1}
);
my $admission = GPForum::Service::Identity::Admission->new( schema => $schema );
my $polls     = GPForum::Service::Forum::Polls->new( schema => $schema );
my $app       = Test::Mojo->new('GPForum');
my $workflow  = $app->app->build_controller->gp_identity_workflow;
my @web_schemas = ( $schema, $app->app->build_controller->gp_schema );

subtest 'email-bound invitations and independent approval' => sub {
    is(
        _admit( 'policy', { mode => 'invite', approval_required => 1 } )
          ->{status},
        'ok',
        'invitation mode and approval enabled'
    );
    is( _register('no_invite')->{status},
        'invalid', 'registration without an invitation refused' );
    my $retry_command = $ids->uuid;
    my %issue         = (
        actor     => $staff,
        command   => $retry_command,
        operation => 'invite',
        email     => 'lost@example.test',
    );
    my $initial = $admission->change( \%issue );
    ok( $initial->{invitation}, 'invitation secret returned first time' );
    ok(
        !$admission->change( \%issue )->{invitation},
        'issue replay never returns a replacement secret'
    );
    is(
        _admit( 'revoke', { invitation_id => $initial->{invitation_id} } )
          ->{status},
        'ok',
        'invitation revoked'
    );
    is( _register( 'lost', $initial->{invitation} )->{status},
        'invalid', 'revoked invitation refused' );
    my $expired = _admit( 'invite', { email => 'expired@example.test' } );
    $dbh->do(
q{UPDATE registration_invitations SET created_at=now()-interval '2 days',expires_at=now()-interval '1 day' WHERE invitation_id=?},
        undef, $expired->{invitation_id}
    );
    is( _register( 'expired', $expired->{invitation} )->{status},
        'invalid', 'expired invitation refused' );
    my $issued = _admit( 'invite', { email => 'invited@example.test' } );
    is( $issued->{status}, 'ok', 'staff issues an invitation' );
    ok( $issued->{invitation}, 'secret shown once' );
    my $raw  = $issued->{invitation};
    my $made = _register( 'wrong_email', $raw );
    is( $made->{status}, 'invalid', 'another email cannot consume it' );
    is(
        _count(
q{SELECT count(*) FROM registration_invitations WHERE used_at IS NOT NULL}
        ),
        0,
        'failed registration did not consume it'
    );
    my $registered = _register( 'invited', $raw );
    is( $registered->{status}, 'ok', 'intended recipient accepted' )
      or diag explain $registered;
    my ($id) =
      $dbh->selectrow_array(q{SELECT id FROM users WHERE username='invited'});
    ok( $id, 'member stored' );
    is(
        _count(
q{SELECT count(*) FROM registration_reviews WHERE user_id=? AND decision='pending'},
            $id
        ),
        1,
        'separate review queued'
    );
    my $issue =
      $workflow->store->request_email_verification( { user_id => $id } );
    my $confirmed = $workflow->store->confirm_email_verification(
        { token => $issue->{token}{raw_token} } );
    ok( $confirmed->{ok}, 'real verification token consumed' );
    is( $confirmed->{user}->get_column('status'),
        'pending', 'returned user reflects enforced database status' );
    is( _scalar( q{SELECT status FROM users WHERE id=?}, $id ),
        'pending', 'email verification cannot bypass staff approval' );
    is( _admit( 'approve', { user_id => $id } )->{status},
        'ok', 'staff approves verified account' );
    is( _scalar( q{SELECT status FROM users WHERE id=?}, $id ),
        'active', 'both conditions enable the account' );
    is( _register( 'invited_again', $raw )->{status},
        'invalid', 'used invitation cannot be reused' );
    is(
        _admit( 'policy', { mode => 'open', approval_required => 1 } )
          ->{status},
        'ok',
        'open registration with review'
    );
    my $pending = _register('approval_first');
    is( $pending->{status}, 'ok', 'new account accepted' );
    my ($pending_id) = $dbh->selectrow_array(
        q{SELECT id FROM users WHERE username='approval_first'});
    is( _admit( 'approve', { user_id => $pending_id } )->{status},
        'ok', 'approval before verification is accepted' );
    is( _scalar( q{SELECT status FROM users WHERE id=?}, $pending_id ),
        'pending', 'approval does not verify the email' );
    $functions->rows(
        'identity_update_user',
        {
            user_id => $pending_id,
            changes => {
                status            => 'active',
                email_verified_at => '2026-10-23T00:00:00Z'
            }
        }
    );
    is( _scalar( q{SELECT status FROM users WHERE id=?}, $pending_id ),
        'active', 'verification after approval enables the account' );
    _register('rejected');
    my ($rejected_id) =
      $dbh->selectrow_array(q{SELECT id FROM users WHERE username='rejected'});
    is( _admit( 'reject', { user_id => $rejected_id } )->{status},
        'ok', 'staff rejects an account' );
    $functions->rows(
        'identity_update_user',
        {
            user_id => $rejected_id,
            changes => {
                status            => 'active',
                email_verified_at => '2026-10-23T00:00:00Z'
            }
        }
    );
    is( _scalar( q{SELECT status FROM users WHERE id=?}, $rejected_id ),
        'pending', 'verification never overrides rejection' );
    is(
        _admit( 'policy', { mode => 'closed', approval_required => 0 } )
          ->{status},
        'ok',
        'registration can close'
    );
    is( _register('closed_signup')->{status},
        'invalid', 'closed policy enforced' );
    is(
        $admission->change(
            {
                actor     => $author,
                command   => $ids->uuid,
                operation => 'policy',
                mode      => 'open'
            }
        )->{status},
        'forbidden',
        'ordinary member cannot change policy'
    );
    _admit( 'policy', { mode => 'open', approval_required => 0 } );
    my $purged = $functions->row(
        'ops_retention_purge',
        {
            source    => 'IdentityToken',
            cutoff    => _scalar('SELECT now()::text'),
            row_limit => 2
        }
    );
    cmp_ok( $purged->{deleted}, '<=', 2,
        'shared retention batch remains bounded' );
    is(
        _count(
q{SELECT count(*) FROM registration_invitations WHERE invitation_id=?},
            $expired->{invitation_id}
        ),
        0,
        'expired invitation purged by existing job'
    );

};

my $poll_thread = _thread( $author, $POSTS );
subtest 'poll authorization, counters, replay and closure' => sub {
    is(
        _poll(
            $voter, 'create', { question => 'Choose', options => $OPTIONS }
        )->{status},
        'forbidden',
        'only author creates a poll'
    );
    is(
        _poll(
            $author, 'create',
            { question => 'Choose', options => [ 'same', 'same' ] }
        )->{status},
        'invalid',
        'duplicate options refused'
    );
    is(
        _poll(
            $author, 'create',
            { question => 'Choose', options => $OPTIONS }
        )->{status},
        'ok',
        'author publishes'
    );
    my $command = $ids->uuid;
    my $first   = _poll( $voter, 'vote', { choice => 1 }, $command );
    is( $first->{status}, 'ok', 'member votes' );
    is_deeply( _poll( $voter, 'vote', { choice => 1 }, $command ),
        $first, 'exact response replayed' );
    is( _poll( $voter, 'vote', { choice => 2 }, $command )->{status},
        'conflict', 'same command cannot change its request' );
    is( _poll( $author, 'vote', { choice => 1 }, $command )->{status},
        'conflict', 'another actor cannot replay the command' );
    is( _poll( $voter, 'vote', { choice => 2 } )->{status},
        'ok', 'new command changes vote' );
    is(
        _count(
q{SELECT count(*) FROM poll_ballots WHERE thread_id=? AND user_id=?},
            $poll_thread,
            $voter
        ),
        1,
        'only one ballot'
    );
    is_deeply(
        $dbh->selectcol_arrayref(
q{SELECT votes FROM poll_options WHERE thread_id=? ORDER BY option_number},
            undef,
            $poll_thread
        ),
        [ 0, 1, 0 ],
        'old count decremented and new count incremented'
    );
    my $public = $polls->overview( undef, $poll_thread );
    is( $public->{status}, 'ok', 'public results readable anonymously' );
    ok( !defined $public->{poll}{choice},
        'public results contain no individual vote' );
    is( _poll( $voter, 'close', {} )->{status},
        'forbidden', 'unrelated voter cannot close' );
    is( _poll( $author, 'close', {} )->{status}, 'ok', 'author closes' );
    is( _poll( $voter,  'vote',  { choice => 1 } )->{status},
        'closed', 'closed poll rejects voting' );
    $dbh->do( q{UPDATE threads SET visibility='private' WHERE thread_id=?},
        undef, $poll_thread );
    is( $polls->overview( undef, $poll_thread )->{status},
        'not_found', 'private poll does not leak aggregate results' );
    is( $polls->overview( $author, $poll_thread )->{status},
        'ok', 'author reads own private poll' );
};

subtest 'category subscriptions use existing rows and permissions' => sub {
    my $command = $ids->uuid;
    my %input   = (
        actor       => $voter,
        command     => $command,
        category_id => $category,
        operation   => 'follow',
    );
    my $first = _call( 'notification_category_follow', \%input );
    is( $first->{status}, 'ok', 'category followed' );
    is_deeply( _call( 'notification_category_follow', \%input ),
        $first, 'same follow replayed exactly' );
    my $followed_thread = _thread( $author, $REPLY );
    is( _subscriber_count( $followed_thread, $voter ),
        1, 'category follow reaches existing thread fanout' );
    $dbh->do(
q{INSERT INTO subscriptions(subscription_id,user_id,target_type,target_id,preference) VALUES(?,?,'thread',?,'all')},
        undef, $ids->uuid, $voter, $followed_thread
    );
    is( _subscriber_count( $followed_thread, $voter ),
        1, 'thread/category follows do not duplicate delivery' );
    $dbh->do(
q{UPDATE subscriptions SET muted_at=now() WHERE user_id=? AND target_type='thread' AND target_id=?},
        undef, $voter, $followed_thread
    );
    is( _subscriber_count( $followed_thread, $voter ),
        0, 'explicit thread mute overrides category follow' );
    is(
        _count(
q{SELECT count(*) FROM subscriptions WHERE user_id=? AND target_type='category' AND target_id=?},
            $voter,
            $category
        ),
        1,
        'one subscription'
    );
    is(
        _call( 'notification_category_follow',
            { %input, command => $ids->uuid, operation => 'mute' } )->{status},
        'ok',
        'category muted'
    );
    is(
        _count(
q{SELECT count(*) FROM subscriptions WHERE user_id=? AND target_id=? AND muted_at IS NOT NULL},
            $voter,
            $category
        ),
        1,
        'mute persisted'
    );
    is(
        _call( 'notification_category_follow',
            { %input, command => $ids->uuid, operation => 'remove' } )
          ->{status},
        'ok',
        'category unfollowed'
    );
    is(
        _call( 'notification_category_follow',
            { %input, command => $ids->uuid } )->{status},
        'ok',
        'follow restores same subscription'
    );
    $dbh->do( q{UPDATE categories SET visibility='private' WHERE category_id=?},
        undef, $category );
    is(
        _call( 'notification_category_follow',
            { %input, command => $ids->uuid } )->{status},
        'not_found',
        'lost category access enforced in function'
    );
    $dbh->do( q{UPDATE categories SET visibility='public' WHERE category_id=?},
        undef, $category );
};

subtest 'transfers preserve content and positions and reverse safely' => sub {
    my $source = _thread( $author, $POSTS );
    my $target = _thread( $author, $REPLY );
    $dbh->do(
q{INSERT INTO post_replies(post_id,reply_to_post_id) SELECT child.post_id,parent.post_id FROM posts child JOIN posts parent ON parent.thread_id=child.thread_id AND parent.position=2 WHERE child.thread_id=? AND child.position IN(4,5)},
        undef, $source
    );
    my $before = _body_hash();
    my %input  = (
        actor        => $staff,
        command      => $ids->uuid,
        source_id    => $source,
        target_id    => $target,
        operation    => 'move',
        post_numbers => [ $REPLY, $LAST ],
        title        => undef,
        reason       => 'Organize discussion',
    );
    is(
        _call( 'moderation_thread_transfer',
            { %input, actor => $voter, command => $ids->uuid } )->{status},
        'forbidden',
        'member cannot transfer'
    );
    is(
        _call( 'moderation_thread_transfer',
            { %input, command => $ids->uuid, post_numbers => [1] } )->{status},
        'invalid',
        'opening post cannot move alone'
    );
    my $moved = _call( 'moderation_thread_transfer', \%input );
    is( $moved->{status}, 'ok', 'selected replies moved' )
      or diag explain $moved;
    is_deeply( _call( 'moderation_thread_transfer', \%input ),
        $moved, 'transfer replayed exactly' );
    is(
        _count( q{SELECT count(*) FROM posts WHERE thread_id=?}, $source ),
        $POSTS - $REPLY,
        'source count'
    );
    is(
        _count( q{SELECT count(*) FROM posts WHERE thread_id=?}, $target ),
        $REPLY + $REPLY,
        'destination count'
    );
    is( _body_hash(), $before, 'every body byte and id unchanged' );
    is(
        _call(
            'moderation_thread_transfer_undo',
            {
                actor       => $staff,
                command     => $ids->uuid,
                transfer_id => $input{command}
            }
        )->{status},
        'ok',
        'transfer reversed'
    );
    is_deeply(
        $dbh->selectcol_arrayref(
            q{SELECT position FROM posts WHERE thread_id=? ORDER BY position},
            undef, $source
        ),
        [ 1 .. $POSTS ],
        'original positions restored'
    );
    is(
        _count(
q{SELECT count(*) FROM post_replies r JOIN posts p ON p.post_id=r.post_id WHERE p.thread_id=?},
            $source
        ),
        2,
        'undo restores both retained and severed reply links'
    );
    my $split = _call(
        'moderation_thread_transfer',
        {
            %input,
            command   => $ids->uuid,
            target_id => undef,
            operation => 'split',
            title     => 'A separate discussion'
        }
    );
    is( $split->{status}, 'ok', 'selected posts split' );
    is(
        _count(
            q{SELECT count(*) FROM posts WHERE thread_id=?},
            $split->{target_id}
        ),
        $REPLY,
        'new thread contains exactly selected posts'
    );
    is(
        _call(
            'moderation_thread_transfer_undo',
            {
                actor       => $staff,
                command     => $ids->uuid,
                transfer_id => $split->{transfer_id}
            }
        )->{status},
        'ok',
        'split reversed'
    );
    my $merge = _call(
        'moderation_thread_transfer',
        {
            %input,
            command      => $ids->uuid,
            operation    => 'merge',
            post_numbers => []
        }
    );
    is( $merge->{status}, 'ok', 'complete merge' );
    is( _count( q{SELECT count(*) FROM posts WHERE thread_id=?}, $source ),
        0, 'source empty' );
    is(
        $functions->row( 'forum_thread_redirect',
            { actor => undef, thread_id => $source } )->{target_id},
        $target,
        'old URL resolves to readable destination'
    );
    is(
        _call(
            'moderation_thread_transfer_undo',
            {
                actor       => $staff,
                command     => $ids->uuid,
                transfer_id => $merge->{transfer_id}
            }
        )->{status},
        'ok',
        'complete merge reversed'
    );
    is( _count( q{SELECT count(*) FROM posts WHERE thread_id=?}, $source ),
        $POSTS, 'all source posts restored' );
    is(
        _scalar(
            q{SELECT reply_count FROM thread_counters WHERE thread_id=?},
            $source
        ),
        $POSTS - 1,
        'reply count reconciled'
    );
    is( _body_hash(), $before, 'split/merge/undo never changes body storage' );
    $dbh->do( q{UPDATE threads SET visibility='members' WHERE thread_id=?},
        undef, $target );
    is(
        _call(
            'moderation_thread_transfer', { %input, command => $ids->uuid }
        )->{status},
        'conflict',
        'different audiences refused'
    );
    $dbh->do( q{UPDATE threads SET visibility='public' WHERE thread_id=?},
        undef, $target );
    is(
        _call( 'moderation_thread_transfer',
            { %input, command => $ids->uuid, source_id => $poll_thread } )
          ->{status},
        'conflict',
        'poll thread cannot be transferred'
    );
    ok(
        _count(
q{SELECT count(*) FROM outbox_messages WHERE payload->>'event_type'='thread.updated'}
        ) > 0,
        'existing event machinery receives invalidation/reindex events'
    );
};

subtest 'races use independent PostgreSQL connections' =>
  \&_concurrent_commands;

subtest 'poll reads stay independent of voter count' => \&_poll_read_scaling;

subtest 'export and erasure cover votes and admission' => sub {
    my $parts =
      $functions->row( 'portability_export_parts', { user_id => $voter } )
      ->{document};
    is(
        scalar @{ $parts->{poll_ballots} },
        _count( q{SELECT count(*) FROM poll_ballots WHERE user_id=?}, $voter ),
        'own ballot exported'
    );
    $functions->rows(
        'privacy_revoke_user',
        {
            source  => 'PollBallot',
            user_id => $voter,
            at      => '2026-10-23T00:00:00Z'
        }
    );
    is(
        _count( q{SELECT count(*) FROM poll_ballots WHERE user_id=?}, $voter ),
        0,
        'erasure removes ballot'
    );
    is(
        _count(
            q{SELECT sum(votes) FROM poll_options WHERE thread_id=?},
            $poll_thread
        ),
        0,
        'erasure reconciles totals'
    );
    my ($waiting) = $dbh->selectrow_array(
        q{SELECT user_id FROM registration_reviews LIMIT 1});
    $functions->rows(
        'privacy_revoke_user',
        {
            source  => 'Admission',
            user_id => $waiting,
            at      => '2026-10-23T00:00:00Z'
        }
    );
    is(
        _count(
            q{SELECT count(*) FROM registration_reviews WHERE user_id=?},
            $waiting
        ),
        0,
        'admission review erased'
    );
};

subtest 'server-rendered surfaces and CSRF' => sub {
    my $web = _session($staff);
    $web->get_ok('/admin/registration')
      ->status_is($HTTP_OK)
      ->element_exists('select[name=mode]');
    $web->post_ok( '/admin/registration' => $JSON => form =>
          { operation => 'policy', mode => 'closed', command_id => $ids->uuid }
    )->status_is($HTTP_FORBIDDEN);
    $web->get_ok('/moderation/transfers')
      ->status_is($HTTP_OK)
      ->element_exists('input[name=source]');
    $web->get_ok( '/c/' . $category )
      ->status_is($HTTP_OK)
      ->element_exists('select[name=operation]');
    my $poll_web = _session($author);
    $poll_web->get_ok( '/t/' . $poll_thread . '/tools/poll' )
      ->status_is($HTTP_OK)
      ->element_exists('h2');
    $poll_web->post_ok( '/t/'
          . $poll_thread
          . '/tools/poll' => $JSON => form =>
          { operation => 'vote', choice => 1, command_id => $ids->uuid } )
      ->status_is($HTTP_FORBIDDEN);
    my $csrf = _csrf( $web, '/admin/registration' );
    $web->post_ok(
        '/admin/registration' => $JSON => form => {
            csrf_token => $csrf,
            command_id => $ids->uuid,
            operation  => 'policy',
            mode       => 'open'
        }
    )->status_is($HTTP_OK)->json_is( '/status', 'ok' );
    $csrf = _csrf( $web, '/c/' . $category );
    $web->post_ok(
            '/c/'
          . $category
          . '/subscription' => $JSON => form => {
            csrf_token => $csrf,
            command_id => $ids->uuid,
            operation  => 'follow'
          }
    )->status_is($HTTP_OK)->json_is( '/status', 'ok' );
    my $fresh    = _thread( $author, $REPLY );
    my $poll_url = '/t/' . $fresh . '/tools/poll';
    $csrf = _csrf( $poll_web, $poll_url );
    $poll_web->post_ok(
        $poll_url => $JSON => form => {
            csrf_token => $csrf,
            command_id => $ids->uuid,
            operation  => 'create',
            question   => 'From the form',
            options    => "One\nTwo"
        }
    )->status_is($HTTP_OK)->json_is( '/status', 'ok' );
    $csrf = _csrf( $poll_web, $poll_url );
    $poll_web->post_ok(
        $poll_url => $JSON => form => {
            csrf_token => $csrf,
            command_id => $ids->uuid,
            operation  => 'vote',
            choice     => 1
        }
    )->status_is($HTTP_OK)->json_is( '/status', 'ok' );
    $dbh->do( q{UPDATE threads SET title='Poll',slug='poll' WHERE thread_id=?},
        undef, $fresh );
    $poll_web->get_ok( '/t/' . $fresh . '/poll' )
      ->status_is($HTTP_OK)
      ->element_exists('article.thread');
    my $destination = _thread( $author, $REPLY );
    $csrf = _csrf( $web, '/moderation/transfers' );
    $web->post_ok(
        '/moderation/transfers' => $JSON => form => {
            csrf_token   => $csrf,
            command_id   => $ids->uuid,
            operation    => 'move',
            source       => '/t/' . $fresh,
            target       => '/t/' . $destination,
            post_numbers => '2',
            reason       => 'Web transfer'
        }
    )->status_is($HTTP_CONFLICT)->json_is( '/status', 'conflict' );

    # Poll-bearing discussions are refused even through the operator form.
    my $source = _thread( $author, $REPLY );
    $web->post_ok(
        '/moderation/transfers' => $JSON => form => {
            csrf_token   => $csrf,
            command_id   => $ids->uuid,
            operation    => 'move',
            source       => '/t/' . $source,
            target       => '/t/' . $destination,
            post_numbers => '2',
            reason       => 'Web transfer'
        }
    )->status_is($HTTP_OK)->json_is( '/status', 'ok' );
    $app->get_ok('/register')
      ->status_is($HTTP_OK)
      ->element_exists('input[name=invitation]');
};

done_testing();

sub _concurrent_commands {
    my $thread  = _thread( $author, $REPLY );
    my @created = GPForum::Test::PostgresHarness::race(
        sub ($slot) {
            my $calls = GPForum::Infrastructure::SqlFunction->new(
                schema => GPForum::Test::PostgresHarness::connect_schema() );
            return $calls->row(
                'forum_poll_change',
                {
                    actor     => $author,
                    command   => GPForum::Infrastructure::Id->new->uuid,
                    thread_id => $thread,
                    operation => 'create',
                    values => { question => 'Concurrent', options => $OPTIONS }
                }
            )->{result};
        }
    );
    my @successful = grep { $_->{ok} && $_->{result}{status} eq 'ok' } @created;
    is( scalar @successful, 1, 'exactly one concurrent creation succeeds' );
    my @voted = GPForum::Test::PostgresHarness::race(
        sub ($slot) {
            my $calls = GPForum::Infrastructure::SqlFunction->new(
                schema => GPForum::Test::PostgresHarness::connect_schema() );
            return $calls->row(
                'forum_poll_change',
                {
                    actor     => $voter,
                    command   => GPForum::Infrastructure::Id->new->uuid,
                    thread_id => $thread,
                    operation => 'vote',
                    values    => { choice => $slot + 1 }
                }
            )->{result};
        }
    );
    for my $outcome (@voted) {
        ok( $outcome->{ok} && $outcome->{result}{status} eq 'ok',
            'concurrent vote change commits' )
          or diag explain $outcome;
    }
    is(
        _count(
            q{SELECT count(*) FROM poll_ballots WHERE thread_id=?}, $thread
        ),
        1,
        'one ballot survives racing updates'
    );
    is(
        _count(
            q{SELECT sum(votes) FROM poll_options WHERE thread_id=?}, $thread
        ),
        1,
        'counter sum remains one'
    );
    is(
        _count(
q{SELECT count(*) FROM poll_options o JOIN poll_ballots b ON b.thread_id=o.thread_id AND b.option_number=o.option_number WHERE o.thread_id=? AND o.votes=1},
            $thread
        ),
        1,
        'counter agrees with actual ballot'
    );
    my $erased  = _user( 'racing_erasure', 0 );
    my @erasure = GPForum::Test::PostgresHarness::race(
        sub ($slot) {
            my $worker_schema =
              GPForum::Test::PostgresHarness::connect_schema();
            my $calls = GPForum::Infrastructure::SqlFunction->new(
                schema => $worker_schema );
            if ( !$slot ) {
                return $worker_schema->txn_do(
                    sub {
                        $worker_schema->storage->dbh->do(
                            q{UPDATE users SET status='deleted' WHERE id=?},
                            undef, $erased );
                        $calls->rows(
                            'privacy_revoke_user',
                            {
                                source  => 'PollBallot',
                                user_id => $erased,
                                at      => '2026-10-23T00:00:00Z'
                            }
                        );
                        return { status => 'ok' };
                    }
                );
            }
            return $calls->row(
                'forum_poll_change',
                {
                    actor     => $erased,
                    command   => GPForum::Infrastructure::Id->new->uuid,
                    thread_id => $thread,
                    operation => 'vote',
                    values    => { choice => 1 }
                }
            )->{result};
        }
    );
    for my $outcome (@erasure) {
        ok( $outcome->{ok},
            'erasure/vote race finishes without database failure' )
          or diag explain $outcome;
    }
    is(
        _count( q{SELECT count(*) FROM poll_ballots WHERE user_id=?}, $erased ),
        0,
        'no ballot can reappear after erasure'
    );
    my $source  = _thread( $author, $POSTS );
    my $target  = _thread( $author, $REPLY );
    my $command = $ids->uuid;
    my @moved   = GPForum::Test::PostgresHarness::race(
        sub ($slot) {
            my $calls = GPForum::Infrastructure::SqlFunction->new(
                schema => GPForum::Test::PostgresHarness::connect_schema() );
            return $calls->row(
                'moderation_thread_transfer',
                {
                    actor        => $staff,
                    command      => $command,
                    source_id    => $source,
                    target_id    => $target,
                    operation    => 'move',
                    post_numbers => [$REPLY],
                    title        => undef,
                    reason       => 'Concurrent transfer'
                }
            )->{result};
        }
    );
    for my $outcome (@moved) {
        ok(
            $outcome->{ok} && $outcome->{result}{status} eq 'ok',
            'concurrent repeated transfer commits or replays'
        ) or diag explain $outcome;
    }
    is(
        _count(
            q{SELECT count(*) FROM thread_transfers WHERE transfer_id=?},
            $command
        ),
        1,
        'one trace for repeated command'
    );
    is( _count( q{SELECT count(*) FROM posts WHERE thread_id=?}, $target ),
        $REPLY + 1, 'post moved once' );

    return;
}

sub _poll_read_scaling {
    my $thread = _thread( $author, $REPLY );
    is(
        _call(
            'forum_poll_change',
            {
                actor     => $author,
                command   => $ids->uuid,
                thread_id => $thread,
                operation => 'create',
                values    => { question => 'Many voters', options => $OPTIONS }
            }
        )->{status},
        'ok',
        'large ballot fixture poll'
    );
    my $bulk = $dbh->selectcol_arrayref(
q{INSERT INTO users(id,username,display_name,email_normalized,password_hash,status,email_verified_at) }
          . q{SELECT gen_random_uuid(),'ballot_fixture_' || n,'Fixture','ballot_fixture_' || n || '@example.test','x','active',now() }
          . q{FROM generate_series(1,1000) n RETURNING id} );
    $dbh->do(
q{INSERT INTO poll_ballots(thread_id,user_id,option_number) SELECT ?,u.id,1 FROM users u WHERE u.username LIKE 'ballot_fixture_%'},
        undef, $thread
    );
    $dbh->do(
q{UPDATE poll_options SET votes=1000 WHERE thread_id=? AND option_number=1},
        undef, $thread
    );
    $dbh->do('ANALYZE poll_ballots');
    my $option_sql =
q{SELECT option_number,label,votes FROM public.poll_options WHERE thread_id=? ORDER BY option_number};
    my $ballot_sql =
q{SELECT option_number FROM public.poll_ballots WHERE thread_id=? AND user_id=?};
    my $codec        = JSON::MaybeXS->new;
    my $options_plan = $codec->decode(
        _scalar(
            'EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) ' . $option_sql, $thread
        )
    );
    my $ballot_plan = $codec->decode(
        _scalar(
            'EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) ' . $ballot_sql, $thread,
            $bulk->[0]
        )
    );
    like(
        $codec->encode($ballot_plan),
        qr/(?:poll_ballots_pkey|idx_poll_ballots_user)/msx,
        'own ballot uses an indexed point lookup'
    );
    my @ms;

    for ( 1 .. $READ_SAMPLES ) {
        my $started = time;
        my $page    = $polls->overview( $bulk->[0], $thread );
        push @ms, ( time - $started ) * $MILLISECONDS;
        is(
            scalar @{ $page->{poll}{options} },
            scalar @{$OPTIONS},
            'read returns only option rows'
        );
    }
    if ( my $file = $ENV{GPFORUM_COMMUNITY_EVIDENCE} ) {
        path($file)->spurt(
            JSON::MaybeXS->new( canonical => 1, pretty => 1 )->encode(
                {
                    kind =>
'serial warm-cache integration smoke; no A/B or production capacity claim',
                    voters          => scalar @{$bulk},
                    samples_ms      => \@ms,
                    postgres        => _scalar('SHOW server_version'),
                    options_plan    => $options_plan,
                    own_ballot_plan => $ballot_plan,
                    statements      =>
                      { options => $option_sql, own_ballot => $ballot_sql },
                }
            )
        );
    }

    return;
}

sub _subscriber_count ( $thread, $user ) {
    my $rows = $functions->rows(
        'notification_subscribers',
        {
            target_type       => 'thread',
            target_id         => $thread,
            notification_type => 'reply'
        }
    );
    my @owned = grep { $_->{user_id} eq $user } @{$rows};
    return scalar @owned;
}

sub _call ( $name, $input ) {
    my $row = $functions->row( $name, $input );
    return $row ? $row->{result} : { status => 'not_found' };
}

sub _admit ( $op, $input ) {
    return $admission->change(
        { actor => $staff, command => $ids->uuid, operation => $op, %{$input} }
    );
}

sub _register ( $name, $invitation = undef ) {
    return $workflow->register(
        {
            command_id   => $ids->uuid,
            username     => $name,
            display_name => $name,
            email        => "$name\@example.test",
            password     => $PASSWORD,
            invitation   => $invitation
        }
    );
}

sub _poll ( $actor, $op, $values, $command = undef ) {
    return $polls->change(
        {
            actor     => $actor,
            command   => $command // $ids->uuid,
            thread_id => $poll_thread,
            operation => $op,
            values    => $values
        }
    );
}

sub _scalar ( $sql, @bind ) {
    return scalar $dbh->selectrow_array( $sql, undef, @bind );
}
sub _count ( $sql, @bind ) { return _scalar( $sql, @bind ) // 0; }

sub _body_hash {
    my $rows = $dbh->selectcol_arrayref(
q{SELECT body_id::text || body_source || body_rendered_safe FROM post_bodies ORDER BY body_id}
    );
    my $text = join q{}, @{$rows};
    return sha256_hex($text);
}

sub _user ( $name, $administrator ) {
    my $id = $ids->uuid;
    $dbh->do(
q{INSERT INTO users(id,username,display_name,email_normalized,password_hash,status,email_verified_at) VALUES(?,?,?,?,'x','active',now())},
        undef, $id, $name, $name, "$name\@example.test"
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

sub _thread ( $user, $count ) {
    my $id = $ids->uuid;
    $dbh->do(
q{INSERT INTO threads(thread_id,category_id,author_user_id,title,slug) VALUES(?,?,?,'Fixture','fixture')},
        undef, $id, $category, $user
    );
    for my $position ( 1 .. $count ) {
        my $post = $ids->uuid;
        my $body = $ids->uuid;
        $dbh->do(
q{INSERT INTO posts(post_id,thread_id,author_user_id,position) VALUES(?,?,?,?)},
            undef, $post, $id, $user, $position
        );
        $dbh->do(
q{INSERT INTO post_bodies(body_id,post_id,body_source,body_rendered_safe,source_hash) VALUES(?,?,'Body','<p>Body</p>','hash')},
            undef, $body, $post
        );
        $dbh->do( q{UPDATE posts SET current_body_id=? WHERE post_id=?},
            undef, $body, $post );
    }
    return $id;
}

sub _csrf ( $web, $url ) {
    $web->get_ok($url)->status_is($HTTP_OK);
    return $web->tx->res->dom->at('input[name=csrf_token]')->attr('value');
}

sub _session ($user) {
    my $web = Test::Mojo->new('GPForum');
    push @web_schemas, $web->app->build_controller->gp_schema;
    my $routes = $web->app->routes;
    $routes->get('/__test/completion-session')->to(
        cb => sub($c) {
            $c->session( user_id => $user );
            return $c->render( text => 'ok' );
        }
    );
    $web->get_ok('/__test/completion-session')->status_is($HTTP_OK);
    return $web;
}

END {
    for my $web_schema (@web_schemas) {
        $web_schema->storage->disconnect;
    }
    if ($database) {
        $database->schema->storage->disconnect;
    }
}

1;
