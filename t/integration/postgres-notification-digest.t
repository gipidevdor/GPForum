# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use Email::Sender::Transport::Test;
use Mojo::JSON qw(decode_json);
use Test::Mojo;
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Infrastructure::SqlFunction;
use GPForum::Service::Identity::Mailer;
use GPForum::Service::Notification::DigestQueue;
use GPForum::Service::Notification::PreferenceStore;
use GPForum::Service::Notification::Renderer;
use GPForum::Service::Notification::UnsubscribeToken;
use GPForum::Service::Operations::ScheduledJobs;
use GPForum::Test::DigestClock;
use GPForum::Test::PgDatabase;
use GPForum::Worker::Handler::NotificationDigest;

our $VERSION = '0.001';

const my $HTTP_OK      => 200;
const my $NOW          => '2026-10-15T12:00:00Z';
const my $DAY_START    => '2026-10-14 00:00:00+00';
const my $DAY_END      => '2026-10-15 00:00:00+00';
const my $BASE         => 'https://forum.example.test';
const my $DIGEST_EVENT => 'notification.digest.requested';

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'set GPFORUM_TEST_DSN for the email digest';
}

# ADR 0078 on a migrated PostgreSQL: the members due a digest, what it
# names, queued once per period through the event log and outbox, mailed
# by the worker as text and HTML, and its unsubscribe link.
local $ENV{GPFORUM_MINION_ENABLED}            = 0;
local $ENV{GPFORUM_REALTIME_LISTENER_ENABLED} = 0;
my $database = GPForum::Test::PgDatabase->fresh( seed => 1 );
local $ENV{GPFORUM_DATABASE_DSN} = $database->dsn;
my $schema    = $database->schema;
my $dbh       = $database->dbh;
my $functions = GPForum::Infrastructure::SqlFunction->new( schema => $schema );
my $clock     = GPForum::Test::DigestClock->new;
my $store     = GPForum::Service::Notification::PreferenceStore->new(
    schema    => $schema,
    functions => $functions,
    clock     => $clock,
);

my $member     = _user( 'digest_member',     1 );
my $author     = _user( 'digest_author',     1 );
my $ignored    = _user( 'digest_ignored',    1 );
my $weekly     = _user( 'digest_weekly',     1 );
my $unverified = _user( 'digest_unverified', 0 );
my $quiet      = _user( 'digest_quiet',      1 );
_digest( $member,     'daily' );
_digest( $weekly,     'weekly' );
_digest( $unverified, 'daily' );
_digest( $quiet,      'daily' );
$dbh->do(
    q{INSERT INTO notification_preferences (user_id, channel, enabled,}
      . q{ digest_frequency, updated_at) VALUES (?, 'email', false, 'daily',}
      . q{ now())},
    undef, $quiet
);
$dbh->do(
    q{INSERT INTO member_relations (owner_user_id, other_user_id, kind,}
      . q{ created_at, updated_at) VALUES (?, ?, 'ignore', now(), now())},
    undef, $member, $ignored
);

my ( $thread, $category ) =
  $dbh->selectrow_array( q{SELECT t.thread_id, t.category_id FROM threads t}
      . q{ JOIN categories c ON c.category_id = t.category_id}
      . q{ JOIN spaces s ON s.space_id = c.space_id}
      . q{ WHERE t.deleted_at IS NULL AND t.moderation_state = 'visible'}
      . q{ AND t.visibility = 'public' AND c.visibility = 'public'}
      . q{ AND s.visibility = 'public' AND c.deleted_at IS NULL}
      . q{ ORDER BY t.thread_id LIMIT 1} );
my ($followed_category) = $dbh->selectrow_array(
    q{SELECT c.category_id FROM categories c}
      . q{ JOIN spaces s ON s.space_id = c.space_id}
      . q{ WHERE c.category_id <> ? AND c.deleted_at IS NULL}
      . q{ AND c.visibility = 'public' AND s.visibility = 'public'}
      . q{ ORDER BY c.category_id LIMIT 1},
    undef, $category
);
my $category_thread = _thread( $followed_category, 'Category news', 'public' );
my $private_thread  = _thread( $followed_category, 'Staff only',    'private' );

# Past what the seed wrote: two posts by the author (the first read), the
# member's own, one by a member they ignore, a hidden one, and one after
# the period.
my $before = _last_position($thread);
my $next   = $before;
for my $post (
    [ $author,  '2026-10-14 08:00:00+00' ],
    [ $author,  '2026-10-14 09:00:00+00' ],
    [ $member,  '2026-10-14 10:00:00+00' ],
    [ $ignored, '2026-10-14 11:00:00+00' ],
    [ $author,  '2026-10-14 12:00:00+00', 'hidden' ],
    [ $author,  '2026-10-15 01:00:00+00' ],
  )
{
    _post( $thread, $post->[0], ++$next, @{$post}[ 1 .. $#{$post} ] );
}
_post( $category_thread, $author, 1, '2026-10-14 15:00:00+00' );
_post( $private_thread,  $author, 1, '2026-10-14 16:00:00+00' );
$dbh->do(
    q{INSERT INTO thread_read_state (user_id, thread_id, last_read_position,}
      . q{ last_read_at) VALUES (?, ?, ?, now())},
    undef, $member, $thread, $before + 1
);
_follow( $member, 'thread',   $thread );
_follow( $member, 'category', $followed_category );

subtest 'the members due a digest of the last period' => sub {
    my $due =
      $functions->rows( 'notification_digest_due',
        { now => $NOW, row_limit => 100 } );
    my %due = map { $_->{user_id} => $_ } @{$due};
    is_deeply(
        [ sort keys %due ],
        [ sort $member, $weekly ],
        'with the digest and email on and a verified address'
    );
    like(
        $due{$member}{period_start},
        qr/\A 2026-10-14/msx,
        'the daily period is yesterday'
    );
    like(
        $due{$weekly}{period_start},
        qr/\A 2026-10-05/msx,
        'the weekly one last week, from Monday'
    );
    is(
        scalar @{
            $functions->rows( 'notification_digest_due',
                { now => $NOW, row_limit => 1 } )
        },
        1,
        'bounded by the limit'
    );
};

subtest 'what a digest names' => sub {
    my $items = $functions->rows(
        'notification_digest_items',
        {
            user_id      => $member,
            period_start => $DAY_START,
            period_end   => $DAY_END,
            member       => 1,
            global_read  => 0,
            category_ids => [],
            space_ids    => [],
            row_limit    => 20,
        }
    );
    is_deeply(
        [ map { [ @{$_}{qw(thread_id new_posts thread_total)} ] } @{$items} ],
        [ [ $category_thread, 1, 2 ], [ $thread, 1, 2 ] ],
        'the followed thread and the followed category, latest first'
    );
    is(
        $items->[1]{first_unread_position},
        $before + 2,
        'past the read position, not the own, ignored, hidden or later posts'
    );
    is( $items->[0]{title}, 'Category news', 'with its title' );
};

my $queue = GPForum::Service::Notification::DigestQueue->new(
    schema    => $schema,
    functions => $functions,
    clock     => $clock,
);

subtest 'queued once per member and period' => sub {
    is_deeply(
        $queue->run( { limit => 100 } ),
        { ok => 1, queued => 1, empty => 1, purged => 0 },
        'one digest queued, an empty one recorded'
    );
    is(
        _count(
            q{SELECT count(*) FROM event_log WHERE event_type = ?},
            $DIGEST_EVENT
        ),
        1,
        'the mail is one event'
    );
    is(
        _count(
            q{SELECT count(*) FROM outbox_messages o JOIN event_log e}
              . q{ ON e.event_id = o.event_id WHERE e.event_type = ?},
            $DIGEST_EVENT
        ),
        1,
        'in the outbox'
    );
    is_deeply(
        $queue->run( { limit => 100 } ),
        { ok => 1, queued => 0, empty => 0, purged => 0 },
        'a second run of the period queues nothing'
    );
    is(
        $functions->row(
            'notification_digest_record',
            {
                user_id       => $member,
                frequency     => 'daily',
                period_start  => $DAY_START,
                period_end    => $DAY_END,
                thread_count  => 0,
                now           => $NOW,
                event         => undef,
                outbox_id     => undef,
                outbox_extras => undef,
                explicit      => 0,
            }
        )->{status},
        'duplicate',
        'nor can another runner record it again'
    );
    my $jobs = GPForum::Service::Operations::ScheduledJobs->new(
        schema => $schema,
        clock  => $clock,
    );
    is_deeply(
        $jobs->run( { jobs => ['notification_digests'], limit => 10 } ),
        {
            ok                   => 1,
            notification_digests =>
              { ok => 1, queued => 0, empty => 0, purged => 0 },
        },
        'the scheduled-jobs runner runs it'
    );
};

my $transport = Email::Sender::Transport::Test->new;
my $tokens =
  GPForum::Service::Notification::UnsubscribeToken->new(
    secrets => ['integration-secret'] );
my $handler = GPForum::Worker::Handler::NotificationDigest->new(
    mailer => GPForum::Service::Identity::Mailer->new(
        transport       => $transport,
        public_base_url => "$BASE/",
        from_address    => 'forum@example.test',
    ),
    preference_store => $store,
    renderer         => GPForum::Service::Notification::Renderer->new,
    tokens           => $tokens,
);
my ( $event_id, $payload ) = $dbh->selectrow_array(
    q{SELECT event_id, payload FROM event_log WHERE event_type = ?},
    undef, $DIGEST_EVENT );
my $event = {
    event_id       => $event_id,
    event_type     => $DIGEST_EVENT,
    domain_payload => _domain( decode_json($payload) ),
};

subtest 'the worker mails it' => sub {
    ok( $handler->handle($event)->{delivered}, 'the digest is sent' );
    my ($sent) = $transport->deliveries;
    my $email = $sent->{email};
    is( $email->get_header('To'),
        'digest_member@example.test', 'to the address read as it is sent' );
    like(
        $email->get_header('Content-Type'),
        qr{\A multipart/alternative;}msx,
        'as text and HTML'
    );
    like( $email->get_body, qr/Category [ ] news/msx, 'naming the threads' );
    like( $email->get_body, qr{/t/\Q$thread\E}msx,    'with their links' );
    like(
        $email->get_header('List-Unsubscribe'),
        qr{\A <\Q$BASE\E/unsubscribe/}msx,
        'and the one-click header'
    );
};

subtest 'unsubscribing stops the digest, audited' => sub {
    is_deeply(
        $store->unsubscribe(
            { user_id => $member, scope => 'digest', via => 'link' }
        ),
        { ok => 1, status => 'ok', scope => 'digest' },
        'the digest is off'
    );
    is( $store->digest_plan($member)->{digest}, 0, 'the plan says so' );
    is(
        $store->unsubscribe( { user_id => $member, scope => 'digest' } )
          ->{status},
        'unchanged',
        'twice is no change'
    );
    is(
        _count(
            q{SELECT count(*) FROM audit_log}
              . q{ WHERE action = 'notification.email_unsubscribed'}
              . q{ AND target_id = ? AND metadata->>'scope' = 'digest'},
            $member
        ),
        1,
        'audited once'
    );
    ok(
        $handler->handle($event)->{skipped},
        'a digest queued before is not sent'
    );
    is( scalar $transport->deliveries, 1, 'nothing more went out' );

    _digest( $member, 'daily' );
    my $test  = Test::Mojo->new('GPForum');
    my $token = GPForum::Service::Notification::UnsubscribeToken->new(
        secrets => $test->app->secrets )->issue( $member, 'digest' );
    $test->get_ok("/unsubscribe/$token")
      ->status_is($HTTP_OK)
      ->element_exists('input[name="scope"][value="digest"][checked]');
    is( $store->digest_plan($member)->{digest},
        1, 'opening it changes nothing' );
    $test->post_ok(
        "/unsubscribe/$token" => form => { 'List-Unsubscribe' => 'One-Click' } )
      ->status_is($HTTP_OK);
    is( $store->digest_plan($member)->{digest},
        0, 'the one-click POST stops the digest' );
};

subtest 'old records are removed' => sub {
    $dbh->do(
        q{INSERT INTO notification_digests (user_id, frequency, period_start,}
          . q{ period_end, status, thread_count, created_at) VALUES}
          . q{ (?, 'daily', '2026-08-01', '2026-08-02', 'empty', 0, now())},
        undef, $weekly
    );
    is(
        $functions->row( 'notification_digest_purge',
            { before => '2026-09-10T00:00:00Z', row_limit => 10 } )->{deleted},
        1,
        'a period past keeping is purged'
    );
    is( _count(q{SELECT count(*) FROM notification_digests}),
        2, 'the recent ones are kept' );
};

done_testing;

# The event's own fields, as the outbox hands them to a handler.
sub _domain ($stored) {
    return $stored->{payload} if ref $stored->{payload} eq 'HASH';

    return $stored;
}

sub _count ( $sql, @binds ) {
    my ($count) = $dbh->selectrow_array( $sql, undef, @binds );

    return 0 + $count;
}

sub _digest ( $user_id, $frequency ) {
    $dbh->do(
        q{INSERT INTO notification_preferences (user_id, channel, enabled,}
          . q{ digest_frequency, updated_at) VALUES (?, 'digest', true, ?,}
          . q{ now()) ON CONFLICT (user_id, channel) DO UPDATE SET}
          . q{ enabled = true, digest_frequency = excluded.digest_frequency},
        undef, $user_id, $frequency
    );

    return;
}

sub _follow ( $user_id, $type, $target ) {
    $dbh->do(
        q{INSERT INTO subscriptions (subscription_id, user_id, target_type,}
          . q{ target_id, preference) VALUES (gen_random_uuid(), ?, ?, ?,}
          . q{ 'all')},
        undef, $user_id, $type, $target
    );

    return;
}

sub _last_position ($thread_id) {
    my ($position) =
      $dbh->selectrow_array(
        q{SELECT coalesce(max(position), 0) FROM posts WHERE thread_id = ?},
        undef, $thread_id );

    return 0 + $position;
}

sub _post ( $thread_id, $author_id, $position, $at, $state = 'visible' ) {
    $dbh->do(
        q{INSERT INTO posts (post_id, thread_id, author_user_id, position,}
          . q{ moderation_state, created_at, updated_at) VALUES}
          . q{ (gen_random_uuid(), ?, ?, ?, ?, ?, ?)},
        undef, $thread_id, $author_id, $position, $state, $at, $at
    );

    return;
}

sub _thread ( $category_id, $title, $visibility ) {
    my ($id) = $dbh->selectrow_array(
        q{INSERT INTO threads (thread_id, category_id, author_user_id, title,}
          . q{ slug, visibility, last_activity_at) VALUES (gen_random_uuid(),}
          . q{ ?, ?, ?, ?, ?, '2026-10-14 16:00:00+00') RETURNING thread_id},
        undef,
        $category_id,
        $author,
        $title,
        lc( $title =~ s/\s+/-/gmsxr ),
        $visibility
    );

    return $id;
}

# A new active member, with a verified address when asked.
sub _user ( $name, $verified ) {
    my ($id) = $dbh->selectrow_array(
        q{INSERT INTO users (id, username, display_name, email_normalized,}
          . q{ password_hash, status, email_verified_at) VALUES}
          . q{ (gen_random_uuid(), ?, ?, ?, 'x', 'active',}
          . q{ CASE WHEN ?::boolean THEN now() END) RETURNING id},
        undef, $name, $name, "$name\@example.test", $verified ? 1 : 0
    );

    return $id;
}

1;
