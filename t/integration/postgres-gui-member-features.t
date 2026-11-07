# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package main;
use v5.40;
use Test::More;
use Const::Fast;
const my $HTTP_FORBIDDEN => 403;
const my $HTTP_FOUND     => 302;
const my $HTTP_ACCEPTED  => 202;
const my $FIXTURE_USERS  => 5;
use Test::Mojo;
use lib 'lib';
use lib 't/lib';
use GPForum::Benchmark::SeedDataset qw(seed_id);
use GPForum::Command::AdminBootstrap;
use GPForum::Service::Identity::MailToken;
use GPForum::Test::GuiDriver;
use GPForum::Test::PgDatabase;
use GPForum::Test::PostgresHarness;
our $VERSION = '0.001';
my $password = 'Feature password original 2026!';
my $changed  = 'Feature password changed 2026!';
my $reset    = 'Feature password recovered 2026!';

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'requires PostgreSQL';
}
my $database = GPForum::Test::PgDatabase->fresh( seed => 1 );
local $ENV{GPFORUM_DATABASE_DSN}              = $database->dsn;
local $ENV{GPFORUM_MINION_ENABLED}            = 0;
local $ENV{GPFORUM_REALTIME_LISTENER_ENABLED} = 0;
my $dbh = $database->dbh;
my ( $admin, $member, $target, $unverified, $erase ) =
  map { seed_id( user => $_ ) } ( 1 .. $FIXTURE_USERS );
GPForum::Test::PostgresHarness::quietly(
    sub {
        return GPForum::Command::AdminBootstrap->new(
            schema => $database->schema )->run( 'grant', '--user-id', $admin );
    }
);
my $t   = Test::Mojo->new('GPForum');
my $gui = GPForum::Test::GuiDriver->new( test => $t );
$gui->install_session;
my $controller = $t->app->build_controller;
my $hasher     = $controller->gp_password;
my $hash       = $hasher->hash_password($password);
$dbh->do(
q{UPDATE users SET password_hash=?,status='active',email_verified_at=now() WHERE id=?},
    undef, $hash, $member
);
$dbh->do(
q{UPDATE credentials SET secret_hash=? WHERE user_id=? AND type='password' AND revoked_at IS NULL},
    undef, $hash, $member
);
$dbh->do(
q{INSERT INTO credentials(id,user_id,type,secret_hash) SELECT gen_random_uuid(),?,'password',? WHERE NOT EXISTS (SELECT 1 FROM credentials WHERE user_id=? AND type='password' AND revoked_at IS NULL)},
    undef, $member, $hash, $member
);
my ( $username, $email ) = $dbh->selectrow_array(
    q{SELECT username,email_normalized FROM users WHERE id=?},
    undef, $member );
my ($target_name) =
  $dbh->selectrow_array( q{SELECT username FROM users WHERE id=?},
    undef, $target );
$gui->actor($member);
subtest 'feature: follow, list and unfollow a member from their profile' =>
  sub {
    $gui->visit( '/u/' . $target_name )
      ->submit( 'form[action="/u/' . $target_name . '/follow"]',
        {}, $HTTP_FOUND, 'button[value="follow"]' );
    is(
        $dbh->selectrow_array(
q{SELECT count(*) FROM subscriptions WHERE user_id=? AND target_type='user' AND target_id=? AND revoked_at IS NULL},
            undef,
            $member,
            $target
        ),
        1,
        'GUI follow persists an active user subscription'
    );
    $gui->visit('/following');
    $t->element_exists( 'a[href="/u/' . $target_name . '"]' );
    $gui->visit( '/u/' . $target_name )
      ->submit( 'form[action="/u/' . $target_name . '/follow"]',
        {}, $HTTP_FOUND, 'button[value="remove"]' );
    is(
        $dbh->selectrow_array(
q{SELECT count(*) FROM subscriptions WHERE user_id=? AND target_type='user' AND target_id=? AND revoked_at IS NULL},
            undef,
            $member,
            $target
        ),
        0,
        'GUI unfollow revokes the user subscription'
    );
  };
subtest 'feature: profile and discussion reports reach the moderation queue' =>
  sub {
    $gui->visit( '/u/' . $target_name )->submit(
        'form[action="/u/' . $target_name . '/report"]',
        { reason => 'spam', details => 'Profile report from GUI' }
    );
    is(
        $dbh->selectrow_array(
q{SELECT count(*) FROM reports WHERE reporter_user_id=? AND target_type='user' AND target_id=?},
            undef,
            $member,
            $target
        ),
        1,
        'GUI profile report persists its selected target'
    );
    my ($thread) = $dbh->selectrow_array(
q{SELECT thread_id FROM threads WHERE author_user_id<>? AND visibility='public' AND moderation_state='visible' AND deleted_at IS NULL LIMIT 1},
        undef, $member
    );
    $gui->visit( '/t/' . $thread )
      ->submit( 'form[action="/t/' . $thread . '/report"]',
        { reason => 'spam', details => 'Thread report from GUI' } );
    is(
        $dbh->selectrow_array(
q{SELECT count(*) FROM reports WHERE reporter_user_id=? AND target_type='thread' AND target_id=?},
            undef,
            $member,
            $thread
        ),
        1,
        'GUI thread report persists its selected target'
    );
  };
subtest 'feature: bookmarks can be filed through the bookmark page' => sub {
    my ($bookmark) = $dbh->selectrow_array(
q{SELECT bookmark_id FROM bookmarks WHERE user_id=? AND deleted_at IS NULL LIMIT 1},
        undef, $member
    );
    ok( $bookmark, 'seeded bookmark for GUI filing' );
    $gui->visit('/bookmarks')
      ->submit( 'form[action="/bookmarks/' . $bookmark . '/folder"]',
        { folder => 'GUI reading list' } );
    is(
        $dbh->selectrow_array(
            q{SELECT folder FROM bookmark_folders WHERE bookmark_id=?}, undef,
            $bookmark
        ),
        'GUI reading list',
        'GUI folder edit persists its name'
    );
};
subtest
  'feature: one notification and all remaining notifications can be marked read'
  => sub {
    $dbh->do(
        q{UPDATE notification_inbox SET read_at=NULL WHERE recipient_user_id=?},
        undef, $member
    );
    my ($notice) = $dbh->selectrow_array(
q{SELECT notification_id FROM notification_inbox WHERE recipient_user_id=? LIMIT 1},
        undef, $member
    );
    ok( $notice, 'seeded notification for GUI read' );
    $gui->visit('/notifications')
      ->submit( 'form[action="/notifications/' . $notice . '/read"]' );
    ok(
        $dbh->selectrow_array(
q{SELECT read_at IS NOT NULL FROM notification_inbox WHERE recipient_user_id=? AND notification_id=?},
            undef,
            $member,
            $notice
        ),
        'GUI notification read persists its read time'
    );
    $dbh->do(
        q{UPDATE notification_inbox SET read_at=NULL WHERE recipient_user_id=?},
        undef, $member
    );
    $gui->visit('/notifications')
      ->submit('form[action="/notifications/read-all"]');
    is(
        $dbh->selectrow_array(
q{SELECT count(*) FROM notification_inbox WHERE recipient_user_id=? AND read_at IS NULL},
            undef,
            $member
        ),
        0,
        'GUI read-all leaves no unread notification'
    );
  };
subtest
  'feature: an author moves a discussion through its category selector' => sub {
    my ( $thread, $before ) = $dbh->selectrow_array(
q{SELECT thread_id,category_id FROM threads WHERE author_user_id=? AND deleted_at IS NULL AND moderation_state='visible' AND visibility='public' LIMIT 1},
        undef, $member
    );
    my ($after) = $dbh->selectrow_array(
q{SELECT category_id FROM categories WHERE category_id<>? AND visibility='public' AND deleted_at IS NULL LIMIT 1},
        undef, $before
    );
    ok( $thread && $after, 'owned discussion and allowed destination' );
    $gui->visit( '/t/' . $thread )
      ->submit( 'form[action="/t/' . $thread . '/move"]',
        { category_id => $after } );
    is(
        $dbh->selectrow_array(
            q{SELECT category_id FROM threads WHERE thread_id=?}, undef,
            $thread
        ),
        $after,
        'GUI move persists the destination category'
    );
  };
subtest 'feature: changing a password uses the rendered credentials form' =>
  sub {
    $gui->visit('/settings')->submit( 'form[action="/settings/password"]',
        { current_password => $password, new_password => $changed } );
    my ($stored) = $dbh->selectrow_array(
q{SELECT secret_hash FROM credentials WHERE user_id=? AND type='password' AND revoked_at IS NULL},
        undef, $member
    );
    ok(
        $hasher->verify_password( $changed, $stored ),
        'GUI password change updates the active credential'
    );
    ok(
        !$hasher->verify_password( $password, $stored ),
        'the previous password no longer authenticates'
    );
  };
subtest 'feature: email changes require confirmation of the mailed token' =>
  sub {
    $gui->actor($member)
      ->visit('/settings')
      ->submit( 'form[action="/settings/email"]',
        { current_password => $changed, email => 'gui-updated@example.test' } );
    is(
        $dbh->selectrow_array(
            q{SELECT email_normalized FROM users WHERE id=?}, undef,
            $member
        ),
        $email,
        'GUI email request does not bypass confirmation'
    );
    my $token = _token( 'email_change', 'gui-updated@example.test' );
    ok( $token, 'GUI email request queues a sealed confirmation token' );
    $gui->visit( '/email/confirm/' . $token )
      ->submit( 'form[action="/email/confirm"]', {}, $HTTP_ACCEPTED );
    is(
        $dbh->selectrow_array(
            q{SELECT email_normalized FROM users WHERE id=?}, undef,
            $member
        ),
        'gui-updated@example.test',
        'GUI confirmation updates the verified email'
    );
  };
subtest 'feature: password recovery completes through both rendered forms' =>
  sub {
    $gui->visit('/password/reset')->submit(
        'form[action="/password/reset"]',
        { identifier => $username },
        $HTTP_ACCEPTED
    );
    my $token = _token( 'password_reset', 'gui-updated@example.test' );
    ok( $token, 'GUI recovery queues the sealed reset token' );
    $gui->visit( '/password/reset/' . $token )->submit(
        'form[action="/password/reset/complete"]',
        { password => $reset },
        $HTTP_ACCEPTED
    );
    my ($stored) = $dbh->selectrow_array(
q{SELECT secret_hash FROM credentials WHERE user_id=? AND type='password' AND revoked_at IS NULL},
        undef, $member
    );
    ok(
        $hasher->verify_password( $reset, $stored ),
        'GUI recovery persists the new credential'
    );
  };
subtest
  'feature: email verification can be requested and completed from its link' =>
  sub {
    $dbh->do(
        q{UPDATE users SET status='pending',email_verified_at=NULL WHERE id=?},
        undef, $unverified
    );
    my ( $name, $address ) = $dbh->selectrow_array(
        q{SELECT username,email_normalized FROM users WHERE id=?},
        undef, $unverified );
    $gui->visit('/email/verify')->submit(
        'form[action="/email/verify/request"]',
        { identifier => $name },
        $HTTP_ACCEPTED
    );
    my $token = _token( 'email_verification', $address );
    ok( $token, 'GUI verification request queues a sealed token' );
    $gui->visit( '/email/verify/' . $token )
      ->submit( 'form[action="/email/verify/complete"]', {}, $HTTP_ACCEPTED );
    ok(
        $dbh->selectrow_array(
            q{SELECT email_verified_at IS NOT NULL FROM users WHERE id=?},
            undef, $unverified
        ),
        'GUI verification confirms the intended address'
    );
  };
subtest
'feature: deletion request, hold, release, approval and erasure use their GUI controls'
  => sub {
    $gui->actor($erase)
      ->visit('/privacy')
      ->submit( 'form[action="/privacy/deletion"]',
        { reason => 'Delete this disposable feature fixture' } );
    my ($request) = $dbh->selectrow_array(
q{SELECT deletion_request_id FROM deletion_requests WHERE requester_user_id=? AND status='pending'},
        undef, $erase
    );
    ok( $request, 'GUI deletion request persists for review' );
    $gui->actor($admin)
      ->visit('/admin/privacy')
      ->submit( 'form[action="/admin/privacy/deletions/' . $request . '/hold"]',
        { reason => 'Feature test legal hold' } );
    my ($hold) = $dbh->selectrow_array(
q{SELECT retention_hold_id FROM retention_holds WHERE resource_id=? AND ends_at IS NULL},
        undef, $erase
    );
    ok( $hold, 'GUI hold creates the active retention hold' );
    $gui->visit('/admin/privacy')
      ->submit( 'form[action="/admin/privacy/holds/' . $hold . '/release"]',
        { reason => 'Feature test release' } );
    ok(
        $dbh->selectrow_array(
q{SELECT ends_at IS NOT NULL FROM retention_holds WHERE retention_hold_id=?},
            undef,
            $hold
        ),
        'GUI release ends the hold'
    );
    $gui->visit('/admin/privacy')->submit(
        'form[action="/admin/privacy/deletions/' . $request . '/approve"]',
        { reason => 'Confirmed disposable fixture', confirm => '1' }
    );
    my ($job) = $dbh->selectrow_array(
        q{SELECT erasure_job_id FROM erasure_jobs WHERE deletion_request_id=?},
        undef, $request
    );
    ok( $job, 'GUI approval creates its erasure job' );
    $dbh->do(
q{UPDATE erasure_jobs SET scheduled_at=now()-interval '1 day' WHERE erasure_job_id=?},
        undef, $job
    );
    $gui->visit('/admin/privacy')
      ->submit( 'form[action="/admin/privacy/erasure/' . $job . '/run"]',
        { confirm => '1' } );
    is(
        $dbh->selectrow_array(
            q{SELECT status FROM users WHERE id=?},
            undef, $erase
        ),
        'deleted',
        'GUI erasure deletes the approved disposable account'
    );
  };
done_testing();

sub _token( $kind, $address ) {
    my ( $sealed, $token_id ) = $dbh->selectrow_array(
q{SELECT payload->'mail'->>'sealed_token',payload->'mail'->>'token_id' FROM outbox_messages WHERE payload->'mail'->>'kind'=? AND payload->'mail'->>'to'=? ORDER BY created_at DESC,outbox_id DESC LIMIT 1},
        undef, $kind, $address
    );
    return GPForum::Service::Identity::MailToken->new->unseal( $sealed,
        $token_id );
}
1;
