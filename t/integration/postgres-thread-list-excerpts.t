# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Service::Forum::HomePageReader;
use GPForum::Service::Forum::ThreadReader;
use GPForum::Test::PgDatabase;

our $VERSION = '0.001';

const my $EXCERPT_HTML => 1_000;
const my $EXCERPT_TEXT => 200;
const my $ELLIPSIS     => "\N{HORIZONTAL ELLIPSIS}";
const my $OPENING_SQL => join q{ },
  'SELECT p.post_id, b.body_id, b.body_rendered_safe FROM posts p',
  'JOIN post_bodies b ON b.body_id = p.current_body_id',
  'WHERE p.thread_id = ? AND p.position = 1';
const my $LISTED_SQL => join q{ },
  'SELECT excerpt FROM api.forum_list_public_threads_v6(',
  'false, false, ARRAY[]::uuid[], ARRAY[]::uuid[], NULL, NULL, 1)',
  'WHERE thread_id = ?';
const my %UNSHOWN => (
    'an opening post marked hidden'  => 'hidden_at = now()',
    'a deleted opening post'         => 'deleted_at = now()',
    'an opening post moderation hid' => q{moderation_state = 'hidden'},
    'an opening post for members'    => q{visibility = 'members'},
);

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'set GPFORUM_TEST_DSN to read the thread list excerpts';
}

# The latest threads carry the start of their opening posts (migration
# 1056): the home page read an excerpt no thread list had and showed none,
# and the feed read its excerpts in a statement of its own. Only an opening
# post that is public, visible and in place gives one.
my $database = GPForum::Test::PgDatabase->fresh( seed => 1 );
my $dbh      = $database->dbh;
my $threads =
  GPForum::Service::Forum::ThreadReader->new( schema => $database->schema );
my $home =
  GPForum::Service::Forum::HomePageReader->new( schema => $database->schema );

my $latest    = $threads->list_public_threads( { limit => 1 } );
my $thread_id = $latest->{items}[0]->get_column('thread_id');
my $opening   = $dbh->selectrow_hashref( $OPENING_SQL, undef, $thread_id );
is(
    $latest->{items}[0]->get_column('excerpt'),
    substr( $opening->{body_rendered_safe}, 0, $EXCERPT_HTML ),
    'the latest thread carries the start of its opening post\'s safe HTML'
);

my $older = $threads->list_public_threads(
    { limit => 1, after => $latest->{next_cursor} } );
my $next = $older->{items}[0]->get_column('thread_id');
is(
    $older->{items}[0]->get_column('excerpt'),
    substr(
        $dbh->selectrow_hashref( $OPENING_SQL, undef, $next )
          ->{body_rendered_safe},
        0,
        $EXCERPT_HTML
    ),
    'and so does the next page\'s, through the keyset'
);

$dbh->do(
    'UPDATE post_bodies SET body_rendered_safe = ? WHERE body_id = ?',
    undef,
    '<p>Tom &amp; Jerry &lt;3</p>' . ( '<p>again</p>' x $EXCERPT_TEXT ),
    $opening->{body_id}
);
my $shown =
  $home->home_page( { thread_limit => 1 } )
  ->{latest_threads}{items}[0]{excerpt};
like(
    $shown,
    qr/\A Tom [ ] & [ ] Jerry [ ] <3 [ ] again [ ]/msx,
    'the home page shows it as text, its entities read once'
);
ok( length $shown <= $EXCERPT_TEXT, 'in at most 200 characters' );
like( $shown, qr/again$ELLIPSIS \z/msx, 'ending on a whole word' );

for my $case ( sort keys %UNSHOWN ) {
    $dbh->begin_work;
    $dbh->do( "UPDATE posts SET $UNSHOWN{$case} WHERE post_id = ?",
        undef, $opening->{post_id} );
    is( scalar $dbh->selectrow_array( $LISTED_SQL, undef, $thread_id ),
        undef, "$case gives no excerpt" );
    $dbh->rollback;
}
isnt( scalar $dbh->selectrow_array( $LISTED_SQL, undef, $thread_id ),
    undef, 'and the post in place gives one again' );

done_testing();

1;
