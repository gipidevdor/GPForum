# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package main;
use v5.40;
use lib 'lib';
use lib 't/lib';
use Test::More;
use GPForum::Test::PgDatabase;
use GPForum::Infrastructure::SqlFunction;
our $VERSION = '0.001';

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'set GPFORUM_TEST_DSN for following-feed privacy';
}
my $db  = GPForum::Test::PgDatabase->fresh( seed => 1 );
my $dbh = $db->dbh;
my $functions =
  GPForum::Infrastructure::SqlFunction->new( schema => $db->schema );
my ( $actor, $author ) = map {
    $dbh->selectrow_array(
q{INSERT INTO users (id,username,display_name,email_normalized,password_hash,status,email_verified_at) VALUES(gen_random_uuid(),?,?,?,'fixture','active',now()) RETURNING id},
        undef, $_, $_, $_ . '@example.test'
    )
} qw(feed_owner feed_author);
my ($category) = $dbh->selectrow_array(
q{SELECT c.category_id FROM categories c JOIN spaces s USING(space_id) WHERE c.visibility='public' AND s.visibility='public' AND c.deleted_at IS NULL AND s.deleted_at IS NULL LIMIT 1}
);
my ($thread) = $dbh->selectrow_array(
q{INSERT INTO threads (thread_id,category_id,author_user_id,title,slug,visibility,moderation_state) VALUES(gen_random_uuid(),?,?,'Followed source','followed-source','public','visible') RETURNING thread_id},
    undef, $category, $actor
);
my ($private) = $dbh->selectrow_array(
q{INSERT INTO posts (post_id,thread_id,author_user_id,position,visibility,moderation_state,created_at) VALUES(gen_random_uuid(),?,?,2,'private','visible','2026-11-01 12:00:00+00') RETURNING post_id},
    undef, $thread, $author
);
my ($public) = $dbh->selectrow_array(
q{INSERT INTO posts (post_id,thread_id,author_user_id,position,visibility,moderation_state,created_at) VALUES(gen_random_uuid(),?,?,3,'public','visible','2026-11-01 13:00:00+00') RETURNING post_id},
    undef, $thread, $author
);
$dbh->do(
q{INSERT INTO subscriptions(subscription_id,user_id,target_type,target_id,preference) VALUES(gen_random_uuid(),?,'user',?,'all')},
    undef, $actor, $author
);
for my $visibility (qw(public members)) {
    $dbh->do( q{UPDATE threads SET visibility=? WHERE thread_id=?},
        undef, $visibility, $thread );
    is_deeply( [ map { $_->{item_id} } @{ feed() } ],
        [$public],
        "$visibility thread owner cannot see followed private reply metadata" );
    is_deeply(
        feed( after_at => '2026-11-01 13:00:00+00', after_id => $public ),
        [], 'cursor page preserves the same denial' );
}
is_deeply(
    [ sort map { $_->{item_id} } @{ feed( global_read => 1 ) } ],
    [ sort $private, $public ],
    'global reader keeps authorized replies'
);
is_deeply(
    [ sort map { $_->{item_id} } @{ feed( category_ids => [$category] ) } ],
    [ sort $private, $public ],
    'category grant keeps authorized replies'
);
$dbh->do( q{UPDATE threads SET visibility='private' WHERE thread_id=?},
    undef, $thread );
is_deeply(
    [ sort map { $_->{item_id} } @{ feed() } ],
    [ sort $private, $public ],
    'private thread owner retains access to private replies'
);
done_testing;

sub feed (%extra) {
    return $functions->rows(
        'community_follow_feed',
        {
            actor        => $actor,
            member       => 1,
            global_read  => 0,
            category_ids => [],
            space_ids    => [],
            after_at     => undef,
            after_id     => undef,
            row_limit    => 10,
            %extra,
        }
    );
}
1;
