# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use Mojo::JSON qw(decode_json);
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Infrastructure::SqlFunction;
use GPForum::Service::Notification::DigestQueue;
use GPForum::Service::Notification::PreferenceStore;
use GPForum::Test::DigestClock;
use GPForum::Test::PgDatabase;

our $VERSION = '0.001';

const my $NOON    => 1_792_065_600;           # 2026-10-15T12:00:00Z, a Thursday
const my $AT_0015 => 1_792_023_300;           # 2026-10-15T00:15:00Z
const my $NOW     => '2026-10-15T12:00:00Z';
const my $DIGEST     => 'notification.digest.requested';
const my $PAGE_LIMIT => 2;
const my $ALL        => 1_000;
const my $MEMBERS    => 3;
const my $LONGEST    => 3;

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'set GPFORUM_TEST_DSN for the email digest windows';
}

# ADR 0078, amendment of 2026-10-17, on a migrated PostgreSQL: a digest
# covers the window from the member's last digest to the end of their last
# complete period, at most 14 days back, so a missed run or a member not
# reached in time is caught up once and every member is reached; a period
# settles before it is due; a switch of frequency re-reports nothing; a
# suspended member gets none; a muted thread of a followed category is
# left out.
local $ENV{GPFORUM_MINION_ENABLED}            = 0;
local $ENV{GPFORUM_REALTIME_LISTENER_ENABLED} = 0;
my $database  = GPForum::Test::PgDatabase->fresh( seed => 1 );
my $schema    = $database->schema;
my $dbh       = $database->dbh;
my $functions = GPForum::Infrastructure::SqlFunction->new( schema => $schema );

my $author = _user('window_author');
my ($category) =
  $dbh->selectrow_array( q{SELECT c.category_id FROM categories c}
      . q{ JOIN spaces s ON s.space_id = c.space_id}
      . q{ WHERE c.deleted_at IS NULL AND c.visibility = 'public'}
      . q{ AND s.visibility = 'public' ORDER BY c.category_id LIMIT 1} );
my $thread   = _thread( 'Window news', '2026-10-14 20:00:00+00' );
my $position = 0;

for my $day (qw(2026-10-12 2026-10-13 2026-10-14)) {
    _post( $thread, ++$position, "$day 08:00:00+00" );
}

subtest 'every member is reached, the longest waiting first' => sub {
    my @members = map { _member( "window_member_$_", 'daily' ) } 1 .. $MEMBERS;
    for my $member (@members) {
        _follow( $member, 'thread', $thread );
    }

    # All three had the digest of the 12th; the runs of the 14th were
    # missed. The third waits longest: its last digest ended on the 10th.
    for my $member ( @members[ 0, 1 ] ) {
        _record( $member, '2026-10-12', '2026-10-13' );
    }
    _record( $members[2], '2026-10-09', '2026-10-10' );
    my @pages = _pages( $NOW, $PAGE_LIMIT, \@members );
    is( scalar @pages, 2, 'the due list is paged by its key' );
    is_deeply(
        [ map { $_->{user_id} } map { @{$_} } @pages ],
        [ $members[2], sort @members[ 0, 1 ] ],
        'each member once, the oldest window first'
    );
    my %window = map { $_->{user_id} => $_ } map { @{$_} } @pages;
    like(
        $window{ $members[0] }{period_start},
        qr/\A 2026-10-13/msx,
        'a missed day is caught up'
    );
    like(
        $window{ $members[0] }{period_end},
        qr/\A 2026-10-15/msx,
        'to the end of the last complete day'
    );
    like(
        $window{ $members[2] }{period_start},
        qr/\A 2026-10-10/msx,
        'from where the last digest ended'
    );

    my $queue = GPForum::Service::Notification::DigestQueue->new(
        schema    => $schema,
        functions => $functions,
        clock     => GPForum::Test::DigestClock->new( epoch => $NOON ),
    );
    my $summary = $queue->run( { limit => 1 } );
    is( $summary->{ok}, 1, 'one run with a page of one' );
    is_deeply(
        [ map { _new_posts($_) } @members ],
        [ 2, 2, $LONGEST ],
        'queues every member, each with all they missed'
    );
    is( _due_for( $NOW, @members ), 0, 'and leaves none of them due' );
};

subtest 'the window goes back at most 14 days' => sub {
    my $member = _member( 'window_returning', 'daily' );
    _record( $member, '2026-08-01', '2026-08-02' );
    my ($row) =
      grep { $_->{user_id} eq $member } @{ _due( $NOW, undef, undef, $ALL ) };
    like( $row->{period_start}, qr/\A 2026-10-01/msx, 'fourteen days' );
};

subtest 'a period is due once it has settled' => sub {
    my $member = _member( 'window_settled', 'daily' );
    _record( $member, '2026-10-13', '2026-10-14' );
    is( _due_for( '2026-10-15T00:05:00Z', $member ),
        0, 'not five minutes after midnight' );

    # A post stamped before midnight, committed after it.
    _follow( $member, 'thread', $thread );
    _post( $thread, ++$position, '2026-10-14 23:59:59+00' );
    my ($row) = grep { $_->{user_id} eq $member }
      @{ _due( '2026-10-15T00:15:00Z', undef, undef, $ALL ) };
    like(
        $row->{period_start},
        qr/\A 2026-10-14/msx,
        'ten minutes after, the day is due'
    );
    GPForum::Service::Notification::DigestQueue->new(
        schema    => $schema,
        functions => $functions,
        clock     => GPForum::Test::DigestClock->new( epoch => $AT_0015 ),
    )->run( { limit => 1000 } );
    is( _new_posts($member), 2, 'and names the late post' );
};

subtest 'switching to weekly re-reports nothing' => sub {
    my $member = _member( 'window_switch', 'daily' );
    _record( $member, '2026-10-14', '2026-10-15' );
    _member( 'window_switch', 'weekly', $member );
    my ($row) = grep { $_->{user_id} eq $member }
      @{ _due( '2026-10-19T12:00:00Z', undef, undef, $ALL ) };
    like(
        $row->{period_start},
        qr/\A 2026-10-15/msx,
        'the week starts where the daily digest ended'
    );
    is( _record( $member, '2026-10-12', '2026-10-19', 'weekly' ),
        'duplicate', 'and a week overlapping it is refused' );
};

subtest 'a suspended member gets no digest' => sub {
    my $member = _member( 'window_suspended', 'daily' );
    my $store  = GPForum::Service::Notification::PreferenceStore->new(
        schema    => $schema,
        functions => $functions,
        clock     => GPForum::Test::DigestClock->new( epoch => $NOON ),
    );
    my ($suspension) = $dbh->selectrow_array(
        q{INSERT INTO suspensions (suspension_id, user_id, actor_user_id,}
          . q{ reason, valid_from) VALUES (gen_random_uuid(), ?, ?, 'spam',}
          . q{ '2026-10-01') RETURNING suspension_id},
        undef, $member, $author
    );
    is( _due_for( $NOW, $member ),              0, 'is not due' );
    is( $store->digest_plan($member)->{digest}, 0, 'nor sent one queued' );
    $dbh->do(
        q{UPDATE suspensions SET revoked_at = '2026-10-02'}
          . q{ WHERE suspension_id = ?},
        undef, $suspension
    );
    is( _due_for( $NOW, $member ), 1, 'until the suspension is lifted' );
    is( $store->digest_plan($member)->{digest}, 1, 'and the plan says so' );
};

subtest 'a muted thread of a followed category is left out' => sub {
    my $member = _member( 'window_muted', 'daily' );
    my $muted  = _thread( 'Muted news', '2026-10-14 21:00:00+00' );
    my $quiet  = _thread( 'Quiet news', '2026-10-14 22:00:00+00' );
    _post( $muted, 1, '2026-10-14 09:00:00+00' );
    _post( $quiet, 1, '2026-10-14 10:00:00+00' );
    _follow( $member, 'category', $category );
    _follow( $member, 'thread',   $muted, 'all', 'now()' );
    _follow( $member, 'thread',   $quiet, 'none' );
    my $items = $functions->rows(
        'notification_digest_items',
        {
            user_id      => $member,
            period_start => '2026-10-14 00:00:00+00',
            period_end   => '2026-10-15 00:00:00+00',
            member       => 1,
            global_read  => 0,
            category_ids => [],
            space_ids    => [],
            row_limit    => $ALL,
        }
    );
    my %named = map { $_->{thread_id} => 1 } @{$items};
    ok( $named{$thread}, 'the category is followed' );
    ok( !$named{$muted}, 'a thread muted is not named' );
    ok( !$named{$quiet}, 'nor one turned down' );
};

done_testing;

sub _due ( $now, $after_start, $after_user_id, $limit ) {
    return $functions->rows(
        'notification_digest_due',
        {
            now           => $now,
            after_start   => $after_start,
            after_user_id => $after_user_id,
            row_limit     => $limit,
        }
    );
}

sub _due_for ( $now, @members ) {
    my %wanted = map { $_ => 1 } @members;

    return
      scalar grep { $wanted{ $_->{user_id} } }
      @{ _due( $now, undef, undef, $ALL ) };
}

# The pages of the due list holding the members named, page by page.
sub _pages ( $now, $limit, $members ) {
    my %wanted = map { $_ => 1 } @{$members};
    my ( @pages, $start, $user );
    while (1) {
        my $page = _due( $now, $start, $user, $limit );
        my @mine = grep { $wanted{ $_->{user_id} } } @{$page};
        if (@mine) {
            push @pages, \@mine;
        }
        last if @{$page} < $limit;
        ( $start, $user ) = @{ $page->[-1] }{qw(period_start user_id)};
    }

    return @pages;
}

# How many new posts the member's queued digest names in the thread.
sub _new_posts ($member) {
    my ($payload) = $dbh->selectrow_array(
        q{SELECT payload FROM event_log WHERE event_type = ?}
          . q{ AND aggregate_id = ? ORDER BY created_at DESC LIMIT 1},
        undef, $DIGEST, $member
    );
    return 0 if !$payload;
    my $stored = decode_json($payload);
    my $digest =
      ref $stored->{payload} eq 'HASH' ? $stored->{payload} : $stored;
    my ($item) = grep { $_->{thread_id} eq $thread } @{ $digest->{items} };

    return $item ? $item->{new_posts} : 0;
}

sub _record ( $member, $start, $end, $frequency = 'daily' ) {
    return $functions->row(
        'notification_digest_record',
        {
            user_id       => $member,
            frequency     => $frequency,
            period_start  => "$start 00:00:00+00",
            period_end    => "$end 00:00:00+00",
            thread_count  => 0,
            now           => $NOW,
            event         => undef,
            outbox_id     => undef,
            outbox_extras => undef,
            explicit      => 0,
        }
    )->{status};
}

sub _follow ( $member, $type, $target, $preference = 'all', $muted = 'NULL' ) {
    $dbh->do(
        q{INSERT INTO subscriptions (subscription_id, user_id, target_type,}
          . q{ target_id, preference, muted_at) VALUES (gen_random_uuid(),}
          . qq{ ?, ?, ?, ?, $muted)},
        undef, $member, $type, $target, $preference
    );

    return;
}

# A member with the digest on at the frequency, or an existing one
# switched to it.
sub _member ( $name, $frequency, $id = _user($name) ) {
    $dbh->do(
        q{INSERT INTO notification_preferences (user_id, channel, enabled,}
          . q{ digest_frequency, updated_at) VALUES (?, 'digest', true, ?,}
          . q{ now()) ON CONFLICT (user_id, channel) DO UPDATE SET}
          . q{ enabled = true, digest_frequency = excluded.digest_frequency},
        undef, $id, $frequency
    );

    return $id;
}

sub _post ( $thread_id, $at_position, $at ) {
    $dbh->do(
        q{INSERT INTO posts (post_id, thread_id, author_user_id, position,}
          . q{ moderation_state, created_at, updated_at) VALUES}
          . q{ (gen_random_uuid(), ?, ?, ?, 'visible', ?, ?)},
        undef, $thread_id, $author, $at_position, $at, $at
    );

    return;
}

sub _thread ( $title, $activity ) {
    my ($id) = $dbh->selectrow_array(
        q{INSERT INTO threads (thread_id, category_id, author_user_id, title,}
          . q{ slug, visibility, last_activity_at) VALUES (gen_random_uuid(),}
          . q{ ?, ?, ?, ?, 'public', ?) RETURNING thread_id},
        undef,
        $category,
        $author,
        $title,
        lc( $title =~ s/\s+/-/gmsxr ),
        $activity
    );

    return $id;
}

sub _user ($name) {
    my ($id) = $dbh->selectrow_array(
        q{INSERT INTO users (id, username, display_name, email_normalized,}
          . q{ password_hash, status, email_verified_at) VALUES}
          . q{ (gen_random_uuid(), ?, ?, ?, 'x', 'active', now())}
          . q{ RETURNING id},
        undef, $name, $name, "$name\@example.test"
    );

    return $id;
}

1;
