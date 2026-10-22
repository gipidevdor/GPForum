# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
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
# author.

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

done_testing();

1;
