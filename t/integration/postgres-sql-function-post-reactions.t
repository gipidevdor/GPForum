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
use GPForum::Service::Community::ReactionStore;
use GPForum::Service::Community::Workflow;
use GPForum::Service::Moderation::ReportStore;
use GPForum::Service::Notification::SubscriptionStore;
use GPForum::Service::Operations::CommandIdempotency;
use GPForum::Test::LogLines;
use GPForum::Test::PgDatabase;

our $VERSION = '0.001';

# ADR 0145 against the migrated schema: a reaction is one row, counted when
# read, beside the like; given twice it is one; a fifth reaction, the
# member's own post and a hidden post refuse it; taken back it is gone, with
# its event; erasure deletes a member's reactions and the export lists them.

const my $OTHERS_SQL => join q{ },
  'SELECT p.post_id, p.thread_id FROM posts p',
  q{WHERE p.deleted_at IS NULL AND p.moderation_state = 'visible'},
  q{AND p.visibility = 'public' AND p.author_user_id <> ?},
  'ORDER BY p.post_id LIMIT 2';
const my $OWN_SQL => join q{ },
  'SELECT p.post_id FROM posts p',
  q{WHERE p.deleted_at IS NULL AND p.moderation_state = 'visible'},
  'AND p.author_user_id = ? ORDER BY p.post_id LIMIT 1';
const my $ROWS_SQL => join q{ },
  'SELECT count(*) FROM post_reactions',
  'WHERE post_id = ? AND user_id = ? AND reaction = ?';
const my $EVENTS_SQL =>
  'SELECT count(*) FROM event_log WHERE event_type = ? AND aggregate_id = ?';
const my $HIDE_SQL =>
  q{UPDATE posts SET moderation_state = 'hidden' WHERE post_id = ?};

# The erasure and the export the release calls, as the catalogue names them.
my $catalogue = GPForum::Infrastructure::SqlFunctionCatalogue->new;
const my $REVOKE_SQL => q{SELECT revoked FROM }
  . $catalogue->function('privacy_revoke_user')->{function}
  . q{('PostReaction', ?, ?)};
const my $EXPORT_SQL => q{SELECT document FROM }
  . $catalogue->function('portability_export_parts')->{function} . q{(?)};

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'set GPFORUM_TEST_DSN for the post reactions test';
}

my $json     = JSON::MaybeXS->new( canonical => 1 );
my $now      = strftime( '%Y-%m-%dT%H:%M:%SZ', gmtime );
my $database = GPForum::Test::PgDatabase->fresh( seed => 1 );
my $dbh      = $database->dbh;
my $schema   = $database->schema;
my $user     = seed_id( user => 2 );
my $store =
  GPForum::Service::Community::ReactionStore->new( schema => $schema );
my $workflow = GPForum::Service::Community::Workflow->new(
    bookmark_store => GPForum::Service::Community::BookmarkStore->new(
        schema => $schema
    ),
    command_idempotency =>
      GPForum::Service::Operations::CommandIdempotency->new(
        schema => $schema
      ),
    like_store =>
      GPForum::Service::Community::LikeStore->new( schema => $schema ),
    logger         => GPForum::Test::LogLines->new,
    reaction_store => $store,
    report_store   =>
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

sub react ( $id, $post_id, $reaction ) {
    return $workflow->react_post(
        {
            command_id => $id,
            post_id    => $post_id,
            reaction   => $reaction,
            user_id    => $user
        }
    );
}

my $reacted = react( 'react-1', $post, 'heart' );
is( $reacted->{status}, 'ok', 'a member gives a post a heart' );
is_deeply(
    $reacted->{stored},
    {
        ok             => 1,
        post_id        => $post,
        reacted        => 1,
        reaction       => 'heart',
        reaction_count => 1,
        thread_id      => $thread,
        user_id        => $user,
    },
    'and is answered with the count of hearts'
);
is( _count( $ROWS_SQL, $post, $user, 'heart' ), 1, 'the heart is one row' );
is( _count( $EVENTS_SQL, 'post.reacted', $post ), 1, 'with its event' );
is( react( 'react-2', $post, 'laugh' )->{stored}{reaction_count},
    1, 'a second reaction on the post is its own' );
is_deeply(
    $store->reactions_for_posts( [ $post, $hidden ], $user ),
    {
        $post => {
            heart => { count => 1, reacted => 1 },
            laugh => { count => 1, reacted => 1 },
        }
    },
    'the page read counts each, as the viewer\'s own'
);
is( $store->reactions_for_posts( [$post] )->{$post}{heart}{reacted},
    0, 'and for a reader who is not signed in, as nobody\'s' );

is_deeply( react( 'react-1', $post, 'heart' ),
    $reacted, 'the same command again is answered the same' );
is( react( 'react-3', $post, 'heart' )->{stored}{reaction_count},
    1, 'a heart given twice is one' );
is( _count( $EVENTS_SQL, 'post.reacted', $post ),
    2, 'with one event per reaction given' );

is( react( 'react-4', $post, 'frown' )->{status},
    'invalid', 'a fifth reaction is refused' );
is( react( 'react-5', $own, 'heart' )->{status},
    'invalid', 'the member\'s own post refuses it' );
is( _count( $ROWS_SQL, $own, $user, 'heart' ), 0, 'and takes no row' );
$dbh->do( $HIDE_SQL, undef, $hidden );
is( react( 'react-6', $hidden, 'heart' )->{status},
    'not_found', 'a hidden post takes no reaction' );

my $unreacted = $workflow->unreact_post(
    {
        command_id => 'unreact-1',
        post_id    => $post,
        reaction   => 'heart',
        user_id    => $user
    }
);
is( $unreacted->{status},                 'ok', 'the heart is taken back' );
is( $unreacted->{stored}{reacted},        0,    'as the answer says' );
is( $unreacted->{stored}{reaction_count}, 0,    'with the count' );
is( _count( $ROWS_SQL, $post, $user, 'heart' ),     0, 'the row is gone' );
is( _count( $EVENTS_SQL, 'post.unreacted', $post ), 1, 'with its event' );
is( _count( $ROWS_SQL, $post, $user, 'laugh' ),     1, 'the laugh stays' );

my ($document) = $dbh->selectrow_array( $EXPORT_SQL, undef, $user );
is_deeply(
    [
        map { [ $_->{post_id}, $_->{reaction} ] }
          @{ $json->decode($document)->{reactions} }
    ],
    [ [ $post, 'laugh' ] ],
    'the member\'s export lists their reactions'
);
is( scalar $dbh->selectrow_array( $REVOKE_SQL, undef, $user, $now ),
    1, 'erasing the member deletes their reactions' );
is( _count( $ROWS_SQL, $post, $user, 'laugh' ), 0, 'and the row is gone' );

done_testing();

sub _count ( $sql, @values ) {
    return scalar $dbh->selectrow_array( $sql, undef, @values );
}

1;
