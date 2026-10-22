# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Service::Community::BookmarkFolders;
use GPForum::Service::Community::BookmarkStore;
use GPForum::Service::Forum::Readability;
use GPForum::Service::Forum::Viewer;
use GPForum::Test::PgDatabase;

our $VERSION = '0.001';

# ADR 0136 against the migrated schema: a member files their own bookmark
# in a folder, moves it, takes it out; another member cannot; the bookmark
# list carries the folder and lists one folder or all; the folders come
# with their counts; a removed bookmark leaves its folder's count.

const my $MEMBERS_SQL =>
  q{SELECT id FROM users WHERE status = 'active' ORDER BY id LIMIT 2};
const my $THREADS_SQL => join q{ },
  'SELECT t.thread_id FROM threads t',
  'JOIN categories c ON c.category_id = t.category_id',
  q{WHERE t.deleted_at IS NULL AND t.moderation_state = 'visible'},
  q{AND t.visibility = 'public' AND c.visibility = 'public'},
  'ORDER BY t.thread_id LIMIT 2';
const my $TWO => 2;

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'set GPFORUM_TEST_DSN for the bookmark folders test';
}

my $database = GPForum::Test::PgDatabase->fresh( seed => 1 );
my $dbh      = $database->dbh;
my $schema   = $database->schema;
my $store    = GPForum::Service::Community::BookmarkStore->new(
    readability =>
      GPForum::Service::Forum::Readability->new( schema => $schema ),
    schema => $schema,
);
my $folders =
  GPForum::Service::Community::BookmarkFolders->new( schema => $schema );

my ( $member, $other ) =
  map { $_->[0] } @{ $dbh->selectall_arrayref($MEMBERS_SQL) };
my ( $thread_a, $thread_b ) =
  map { $_->[0] } @{ $dbh->selectall_arrayref($THREADS_SQL) };
ok(
    $member && $other && $thread_a && $thread_b,
    'the seed has two members and two threads'
);
my $viewer =
  GPForum::Service::Forum::Viewer->new( member => 1, user_id => $member );

my $saved = $store->save_bookmark(
    {
        user_id     => $member,
        target_type => 'thread',
        target_id   => $thread_a,
        note        => 'one'
    }
);
my $also = $store->save_bookmark(
    {
        user_id     => $member,
        target_type => 'thread',
        target_id   => $thread_b,
        note        => 'two'
    }
);

is_deeply(
    $folders->file_bookmark( $saved->{bookmark_id}, $member, 'Read later' ),
    { bookmark_id => $saved->{bookmark_id}, folder => 'Read later' },
    'a member files their bookmark in a folder'
);
is( $folders->file_bookmark( $saved->{bookmark_id}, $other, 'Theirs' ),
    undef, 'another member cannot file it' );
is_deeply(
    $folders->file_bookmark( $also->{bookmark_id}, $member, 'Read later' ),
    { bookmark_id => $also->{bookmark_id}, folder => 'Read later' },
    'a second bookmark joins the folder'
);
is_deeply(
    $folders->list_folders($member),
    [ { bookmark_count => $TWO, folder => 'Read later' } ],
    'the folder is listed with its count'
);

my $listed = $store->list_page_for_user( $member,
    { folder => 'Read later', target_type => 'thread', viewer => $viewer } );
is( scalar @{ $listed->{items} }, $TWO, 'the list of the folder has both' );
is( $listed->{items}[0]->get_column('folder'),
    'Read later', 'each row carries its folder' );
is_deeply(
    $folders->file_bookmark( $also->{bookmark_id}, $member, 'Perl' ),
    { bookmark_id => $also->{bookmark_id}, folder => 'Perl' },
    'a bookmark is moved to another folder'
);
is(
    scalar @{
        $store->list_page_for_user(
            $member,
            {
                folder      => 'Read later',
                target_type => 'thread',
                viewer      => $viewer
            }
        )->{items}
    },
    1,
    'and the first folder lists one'
);
is(
    scalar @{
        $store->list_page_for_user( $member,
            { target_type => 'thread', viewer => $viewer } )->{items}
    },
    $TWO,
    'the whole list is unchanged'
);
is_deeply(
    $folders->file_bookmark( $also->{bookmark_id}, $member, q{} ),
    { bookmark_id => $also->{bookmark_id}, folder => undef },
    'an empty folder takes a bookmark out of its folder'
);
is_deeply(
    $folders->list_folders($member),
    [ { bookmark_count => 1, folder => 'Read later' } ],
    'and the folder it left is gone from the list'
);
$store->remove_for_user_target(
    { user_id => $member, target_type => 'thread', target_id => $thread_a } );
is_deeply( $folders->list_folders($member),
    [], 'a bookmark removed is not counted in its folder' );
is( $folders->file_bookmark( $saved->{bookmark_id}, $member, 'Back' ),
    undef, 'nor can it be filed while removed' );

done_testing();

1;
