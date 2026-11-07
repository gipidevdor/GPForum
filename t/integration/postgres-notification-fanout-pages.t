# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package main;
use v5.40;
use Test::More;
use lib 'lib', 't/lib';
use GPForum::Infrastructure::Id;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Test::PgDatabase;
our $VERSION = '0.001';
plan skip_all => 'temporary PostgreSQL required'
  if !GPForum::Test::PgDatabase->admin_dsn;
my $database = GPForum::Test::PgDatabase->fresh( seed => 1 );
my $functions =
  GPForum::Infrastructure::SqlFunction->for_schema( $database->schema );
my $thread = $functions->row(
    'forum_list_public_threads',
    {
        member          => 0,
        global_read     => 0,
        category_ids    => [],
        space_ids       => [],
        after_activity  => undef,
        after_thread_id => undef,
        row_limit       => 1
    }
);
my $ids = GPForum::Infrastructure::Id->new;
my $dbh = $database->dbh;

# Fixture construction only; production subscriber reads stay in api.*.
my @users;
for my $number ( 1 .. 205 ) {
    my $user = $ids->uuid;
    push @users, $user;
    $dbh->do(
q{INSERT INTO users(id,username,display_name,email_normalized,password_hash,status)
        VALUES(?,?,?,?,?,'active')}, undef, $user, "fanout_$number",
        "Fanout $number",
        "fanout_$number\@example.test", '!disabled'
    );
    $dbh->do(
q{INSERT INTO subscriptions(subscription_id,user_id,target_type,target_id,preference)
        VALUES(?,?,?,?,?)}, undef, $ids->uuid, $user,
        $number <= 105 ? 'thread'             : 'category',
        $number <= 105 ? $thread->{thread_id} : $thread->{category_id},
        $number == 205 ? 'mentions'           : 'all'
    );
}
$dbh->do( q{UPDATE subscriptions SET preference='none' WHERE user_id=?},
    undef, $users[0] );
$dbh->do(
    q{INSERT INTO subscriptions(subscription_id,user_id,target_type,target_id)
    VALUES(?,?,'category',?)}, undef, $ids->uuid, $users[0],
    $thread->{category_id}
);
$dbh->do(
    q{INSERT INTO subscriptions(subscription_id,user_id,target_type,target_id)
    VALUES(?,?,'category',?)}, undef, $ids->uuid, $users[1],
    $thread->{category_id}
);
for my $type (qw(reply mention)) {
    my %scope = (
        target_type       => 'thread',
        target_id         => $thread->{thread_id},
        notification_type => $type,
        actor_id          => $thread->{author_user_id},
        excluded_user_id  => $users[2]
    );
    my $expected =
      $functions->rows( 'notification_fanout_candidates', \%scope );
    my ( $after, $through );
    my @actual;
    my $pages = 0;
    while (1) {
        my $rows = $functions->rows(
            'notification_fanout_page',
            {
                %scope,
                after_user_id   => $after,
                through_user_id => $through,
                row_limit       => 73
            }
        );
        ++$pages;
        last if !@{$rows};
        ok( @{$rows} <= 73, "$type candidate page is bounded" );
        $through //= $rows->[0]{through_user_id};
        $after = $rows->[-1]{user_id};
        delete $_->{through_user_id} for @{$rows};
        push @actual, @{$rows};
        last if @{$rows} < 73 || $after eq $through;
    }
    ok( $pages >= 3, "$type exercises several cursor pages" );
    is_deeply( \@actual, $expected,
"$type paging preserves plans, grants, overrides, exclusions and deduplication"
    );
    my @ids    = map { $_->{user_id} } @actual;
    my %unique = map { $_ => 1 } @ids;
    is( scalar keys %unique, scalar @ids, "$type has no duplicate recipients" );
    ok(
        !grep( $_ eq $users[0], @ids ),
        "$type respects the explicit thread opt-out over category subscription"
    );
}
done_testing;
1;
