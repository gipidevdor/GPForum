# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Service::Forum::ReplyLinks;
use GPForum::Test::PgDatabase;

our $VERSION = '0.001';

# ADR 0132 against the migrated schema: a link holds between two posts of
# one thread when the post answered is there to be read; not across
# threads, not to a hidden post, not to itself; written twice it is one;
# and the page reads the targets of its posts with the position and the
# author. A reply answers only a post every reader of the reply may read.

const my $POSTS_SQL => join q{ },
  'SELECT p.post_id, p.thread_id, p.position FROM posts p',
  q{WHERE p.deleted_at IS NULL AND p.moderation_state = 'visible'},
  'ORDER BY p.thread_id, p.position LIMIT 4';
const my $OTHER_THREAD_SQL => join q{ },
  'SELECT p.post_id FROM posts p WHERE p.thread_id <> ?',
  q{AND p.deleted_at IS NULL AND p.moderation_state = 'visible'},
  'ORDER BY p.post_id LIMIT 1';
const my $HIDE_SQL =>
  q{UPDATE posts SET moderation_state = 'hidden' WHERE post_id = ?};
const my $AUTHOR_SQL => join q{ },
  'SELECT u.username FROM posts p JOIN users u ON u.id = p.author_user_id',
  'WHERE p.post_id = ?';
const my $VISIBILITY_SQL =>
  q{UPDATE posts SET visibility = ? WHERE post_id = ?};
const my $UNLINK_SQL => q{DELETE FROM post_replies WHERE post_id = ?};
const my $SAME_AUTHOR_SQL => join q{ },
  'UPDATE posts SET author_user_id =',
  '(SELECT t.author_user_id FROM posts t WHERE t.post_id = ?)',
  'WHERE post_id = ?';
const my $THREE => 3;

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'set GPFORUM_TEST_DSN for the reply links test';
}

my $database = GPForum::Test::PgDatabase->fresh( seed => 1 );
my $dbh      = $database->dbh;
my $links =
  GPForum::Service::Forum::ReplyLinks->new( schema => $database->schema );

my $posts = $dbh->selectall_arrayref( $POSTS_SQL, { Slice => {} } );
my @same  = grep { $_->{thread_id} eq $posts->[0]{thread_id} } @{$posts};
ok( @same >= $THREE, 'the seed has a thread with three posts' );
my ( $opening, $answer, $later ) = map { $_->{post_id} } @same;
my ($elsewhere) =
  $dbh->selectrow_array( $OTHER_THREAD_SQL, undef, $posts->[0]{thread_id} );

is( $links->link_reply( $answer, $opening ),
    1, 'a reply is linked to the post it answers' );
is( $links->link_reply( $answer, $opening ),
    1, 'and linking it again is the same link' );
is( $links->link_reply( $later, $elsewhere ),
    0, 'a post in another thread is not answered' );
is( $links->link_reply( $later, $later ), 0, 'nor the reply itself' );
$dbh->do( $HIDE_SQL, undef, $opening );
is( $links->link_reply( $later, $opening ), 0, 'nor a post that is hidden' );
my ($author) = $dbh->selectrow_array( $AUTHOR_SQL, undef, $opening );
is_deeply(
    $links->targets_for_posts( [ $opening, $answer, $later ] ),
    {
        $answer => {
            author_username => $author,
            position        => $same[0]{position},
            post_id         => $opening,
        }
    },
    'the page reads which post each answers, with its position and author'
);

# ADR 0102: a reply names the post it answers to every reader of the reply,
# so it answers only a post each of them may read. The seed's thread, its
# category and its space are public.
$dbh->do( $VISIBILITY_SQL, undef, 'members', $answer );
is( $links->link_reply( $later, $answer ),
    0, 'a public reply does not answer a members-only post' );
$dbh->do( $VISIBILITY_SQL, undef, 'members', $later );
is( $links->link_reply( $later, $answer ), 1, 'a members-only reply does' );
$dbh->do( $UNLINK_SQL, undef, $later );
$dbh->do( $VISIBILITY_SQL, undef, 'private', $answer );
is( $links->link_reply( $later, $answer ),
    0, 'no reply but a private one answers a private post' );
$dbh->do( $VISIBILITY_SQL,  undef, 'private', $later );
$dbh->do( $SAME_AUTHOR_SQL, undef, $opening,  $answer );
is( $links->link_reply( $later, $answer ),
    0, 'nor a private reply by another member' );
$dbh->do( $SAME_AUTHOR_SQL, undef, $opening, $later );
is( $links->link_reply( $later, $answer ),
    1, 'but one by the private post\'s own author does' );

done_testing();

1;
