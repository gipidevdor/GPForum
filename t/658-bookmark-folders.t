# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use Test::Fatal;
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Infrastructure::SqlFunction;
use GPForum::Service::Community::BookmarkFolders;
use GPForum::Test::SqlFunctionHandle;

our $VERSION = '0.001';

# Filing a bookmark in a folder (ADR 0136), on a handle that records the
# call and answers what the test gives: what a text names, the filing,
# taking a bookmark out of its folder, and the member's folders.

const my $BOOKMARK => '018f1007-0001-7000-8000-000000000001';
const my $MEMBER   => '018f1002-0002-7000-8000-000000000002';
const my $OVER_MAX => 41;
const my $COUNT    => 3;

sub fixture ( $rows = [] ) {
    my $handle  = GPForum::Test::SqlFunctionHandle->new( rows => $rows );
    my $folders = GPForum::Service::Community::BookmarkFolders->new(
        functions =>
          GPForum::Infrastructure::SqlFunction->new( schema => $handle ),
        schema => $handle,
    );
    return ( $handle, $folders );
}

subtest 'a text names a folder: trimmed, folded, forty characters at most' =>
  sub {
    my ( undef, $folders ) = fixture();
    is( $folders->normalise('  Read   later '),
        'Read later', 'trimmed and folded' );
    is( $folders->normalise(undef),  q{}, 'nothing names no folder' );
    is( $folders->normalise(q{   }), q{}, 'nor do spaces' );
    is( $folders->normalise( 'x' x $OVER_MAX ),
        undef, 'over forty characters is not a folder' );
  };

subtest 'a bookmark is filed in its folder' => sub {
    my ( $handle, $folders ) =
      fixture( [ { bookmark_id => $BOOKMARK, folder => 'Read later' } ] );
    is_deeply(
        $folders->file_bookmark( $BOOKMARK, $MEMBER, ' Read  later ' ),
        { bookmark_id => $BOOKMARK, folder => 'Read later' },
        'the bookmark is in the folder named'
    );
    like(
        $handle->prepared->[0],
        qr/api[.]community_set_bookmark_folder_v2/msx,
        'through the filing function'
    );
    is_deeply(
        [ @{ $handle->executed->[0] } ],
        [ $BOOKMARK, $MEMBER, 'Read later' ],
        'with the bookmark, the member and the folder as named'
    );
};

subtest 'an empty folder takes the bookmark out of its folder' => sub {
    my ( $handle, $folders ) =
      fixture( [ { bookmark_id => $BOOKMARK, folder => undef } ] );
    is_deeply(
        $folders->file_bookmark( $BOOKMARK, $MEMBER, q{} ),
        { bookmark_id => $BOOKMARK, folder => undef },
        'the bookmark has no folder'
    );
    is( $handle->executed->[0][2], q{}, 'the function hears the empty folder' );
};

subtest 'what cannot be filed is refused before any call' => sub {
    my ( $handle, $folders ) = fixture( [ { bookmark_id => $BOOKMARK } ] );
    is( $folders->file_bookmark( 'bookmark-1', $MEMBER, 'x' ),
        undef, 'a bookmark id that is not one' );
    is( $folders->file_bookmark( $BOOKMARK, 'user-1', 'x' ),
        undef, 'a member id that is not one' );
    is( $folders->file_bookmark( $BOOKMARK, $MEMBER, 'x' x $OVER_MAX ),
        undef, 'a folder too long' );
    is( scalar @{ $handle->executed }, 0, 'and the database heard nothing' );
};

subtest 'a bookmark not the member\'s is not filed' => sub {
    my ( undef, $folders ) = fixture( [] );
    is( $folders->file_bookmark( $BOOKMARK, $MEMBER, 'Mine' ),
        undef, 'the function answers nothing, so nothing is filed' );
};

subtest 'the member\'s folders come with their counts' => sub {
    my ( $handle, $folders ) = fixture(
        [
            { bookmark_count => $COUNT, folder => 'Later' },
            { bookmark_count => 1,      folder => 'Perl' },
        ]
    );
    is_deeply(
        $folders->list_folders($MEMBER),
        [
            { bookmark_count => $COUNT, folder => 'Later' },
            { bookmark_count => 1,      folder => 'Perl' },
        ],
        'each with its count'
    );
    like(
        $handle->prepared->[0],
        qr/api[.]community_list_bookmark_folders_v2/msx,
        'through the folder list function'
    );
    is_deeply( $folders->list_folders('user-1'),
        [], 'a member id that is not one has none' );
};

subtest 'folders exist only as functions' => sub {
    my $folders = GPForum::Service::Community::BookmarkFolders->new(
        functions => undef,
        schema    => GPForum::Test::SqlFunctionHandle->new,
    );
    like(
        exception { $folders->list_folders($MEMBER) },
        qr/SQL [ ] function [ ] layer/msx,
        'without the call layer the service refuses to guess'
    );
};

done_testing();

1;
