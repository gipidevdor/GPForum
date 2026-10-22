# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use JSON::MaybeXS;
use POSIX qw(strftime);
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Benchmark::SeedDataset qw(seed_id);
use GPForum::Infrastructure::SqlFunctionCatalogue;
use GPForum::Service::Community::BookmarkStore;
use GPForum::Service::Community::LikeStore;
use GPForum::Service::Community::Workflow;
use GPForum::Service::Moderation::ReportStore;
use GPForum::Service::Notification::SubscriptionStore;
use GPForum::Service::Operations::CommandIdempotency;
use GPForum::Test::LogLines;
use GPForum::Test::PgDatabase;

our $VERSION = '0.001';

# ADR 0129 against the migrated schema: a like is one row, counted when
# read; given twice it is one; the author's own post refuses it, a hidden
# one too; taken back it is gone, with its event; erasure deletes a member's
# likes and the export lists them.

const my $OTHERS_SQL => join q{ },
  'SELECT p.post_id, p.thread_id FROM posts p',
  q{WHERE p.deleted_at IS NULL AND p.moderation_state = 'visible'},
  q{AND p.visibility = 'public' AND p.author_user_id <> ?},
  'ORDER BY p.post_id LIMIT 2';
const my $OWN_SQL => join q{ },
  'SELECT p.post_id FROM posts p',
  q{WHERE p.deleted_at IS NULL AND p.moderation_state = 'visible'},
  'AND p.author_user_id = ? ORDER BY p.post_id LIMIT 1';
const my $LIKES_SQL =>
  'SELECT count(*) FROM post_likes WHERE post_id = ? AND user_id = ?';
const my $EVENTS_SQL =>
  'SELECT count(*) FROM event_log WHERE event_type = ? AND aggregate_id = ?';
const my $OUTBOX_SQL => join q{ },
  'SELECT count(*) FROM outbox_messages o',
  'JOIN event_log e ON e.event_id = o.event_id',
  'WHERE e.event_type = ? AND e.aggregate_id = ?';
const my $HIDE_SQL =>
  q{UPDATE posts SET moderation_state = 'hidden' WHERE post_id = ?};

# The erasure and the export the release calls, as the catalogue names them.
my $catalogue = GPForum::Infrastructure::SqlFunctionCatalogue->new;
const my $REVOKE_SQL => q{SELECT revoked FROM }
  . $catalogue->function('privacy_revoke_user')->{function}
  . q{('PostLike', ?, ?)};
const my $EXPORT_SQL => q{SELECT document FROM }
  . $catalogue->function('portability_export_parts')->{function} . q{(?)};

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'set GPFORUM_TEST_DSN for the post likes test';
}

my $json     = JSON::MaybeXS->new( canonical => 1 );
my $now      = strftime( '%Y-%m-%dT%H:%M:%SZ', gmtime );
my $database = GPForum::Test::PgDatabase->fresh( seed => 1 );
my $dbh      = $database->dbh;
my $schema   = $database->schema;
my $user     = seed_id( user => 2 );
my $store    = GPForum::Service::Community::LikeStore->new( schema => $schema );
my $workflow = GPForum::Service::Community::Workflow->new(
    bookmark_store => GPForum::Service::Community::BookmarkStore->new(
        schema => $schema
    ),
    command_idempotency =>
      GPForum::Service::Operations::CommandIdempotency->new(
        schema => $schema
      ),
    like_store   => $store,
    logger       => GPForum::Test::LogLines->new,
    report_store =>
      GPForum::Service::Moderation::ReportStore->new( schema => $schema ),
    subscription_store =>
      GPForum::Service::Notification::SubscriptionStore->new(
        schema => $schema
      ),
);

my $others = $dbh->selectall_arrayref( $OTHERS_SQL, { Slice => {} }, $user );
my ($own) = $dbh->selectrow_array( $OWN_SQL, undef, $user );
is( scalar @{$others}, 2, 'the seed has posts by other members' );
ok( $own, 'and one by the member' );
my ( $post, $hidden ) = map { $_->{post_id} } @{$others};
my $thread = $others->[0]{thread_id};

my $liked = $workflow->like_post(
    { command_id => 'like-1', post_id => $post, user_id => $user } );
is( $liked->{status}, 'ok', 'a member likes a post' );
is_deeply(
    $liked->{stored},
    {
        like_count => 1,
        liked      => 1,
        ok         => 1,
        post_id    => $post,
        thread_id  => $thread,
        user_id    => $user,
    },
    'and is answered with the count'
);
is( _count( $LIKES_SQL,  $post,        $user ), 1, 'the like is one row' );
is( _count( $EVENTS_SQL, 'post.liked', $post ), 1, 'with its event' );
is( _count( $OUTBOX_SQL, 'post.liked', $post ), 1, 'and its outbox message' );
is_deeply(
    $store->summary_for_posts( [ $post, $hidden ], $user ),
    { $post => { like_count => 1, liked => 1 } },
    'the page read counts it, as the viewer\'s own'
);
is_deeply(
    $store->summary_for_posts( [$post] ),
    { $post => { like_count => 1, liked => 0 } },
    'and for a reader who is not signed in, as nobody\'s'
);

is_deeply(
    $workflow->like_post(
        { command_id => 'like-1', post_id => $post, user_id => $user }
    ),
    $liked,
    'the same command again is answered the same'
);
my $again = $workflow->like_post(
    { command_id => 'like-2', post_id => $post, user_id => $user } );
is( $again->{stored}{like_count}, 1, 'a like given twice is one' );
is( _count( $EVENTS_SQL, 'post.liked', $post ), 1, 'with one event' );

my $self_like = $workflow->like_post(
    { command_id => 'like-3', post_id => $own, user_id => $user } );
is( $self_like->{status}, 'invalid',      'the member\'s own post refuses it' );
is( _count( $LIKES_SQL, $own, $user ), 0, 'and takes no row' );

$dbh->do( $HIDE_SQL, undef, $hidden );
is(
    $workflow->like_post(
        { command_id => 'like-4', post_id => $hidden, user_id => $user }
    )->{status},
    'not_found',
    'a hidden post takes no like'
);

my $unliked = $workflow->unlike_post(
    { command_id => 'unlike-1', post_id => $post, user_id => $user } );
is( $unliked->{status},                 'ok',        'the like is taken back' );
is( $unliked->{stored}{liked},          0,           'as the answer says' );
is( $unliked->{stored}{like_count},     0,           'with the count' );
is( _count( $LIKES_SQL, $post, $user ), 0,           'the row is gone' );
is( _count( $EVENTS_SQL, 'post.unliked', $post ), 1, 'with its event' );
is(
    $workflow->unlike_post(
        { command_id => 'unlike-2', post_id => $post, user_id => $user }
    )->{stored}{like_count},
    0,
    'taking back a like not given changes nothing'
);
is( _count( $EVENTS_SQL, 'post.unliked', $post ), 1, 'and records no event' );

$workflow->like_post(
    { command_id => 'like-5', post_id => $post, user_id => $user } );
my ($document) = $dbh->selectrow_array( $EXPORT_SQL, undef, $user );
is_deeply( [ map { $_->{post_id} } @{ $json->decode($document)->{likes} } ],
    [$post], 'the member\'s export lists the post they liked' );
is( scalar $dbh->selectrow_array( $REVOKE_SQL, undef, $user, $now ),
    1, 'erasing the member deletes their likes' );
is( _count( $LIKES_SQL, $post, $user ), 0, 'and the row is gone' );

done_testing();

sub _count ( $sql, @values ) {
    return scalar $dbh->selectrow_array( $sql, undef, @values );
}

1;
