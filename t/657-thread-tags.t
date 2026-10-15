# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use utf8;
use v5.40;

use Const::Fast;
use Test::Fatal;
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Infrastructure::SqlFunction;
use GPForum::Service::Forum::ThreadTags;
use GPForum::Service::Forum::Viewer;
use GPForum::Test::SqlFunctionHandle;

our $VERSION = '0.001';

# The tags a thread carries (ADR 0135), on a handle that records the call
# and answers what the test gives: what a text names, the write after the
# thread command, the page's read, the tag page's list and the index.

const my $THREAD      => '018f1006-0001-7000-8000-000000000001';
const my $OTHER       => '018f1006-0002-7000-8000-000000000002';
const my $MEMBER      => '018f1002-0002-7000-8000-000000000002';
const my $CATEGORY    => '018f1001-0001-7000-8000-000000000001';
const my $MAX_TAGS    => 5;
const my $LIMIT       => 20;
const my $OVER_MAX    => 31;
const my $VIEWER_ARGS => 4;

sub fixture ( $rows = [] ) {
    my $handle = GPForum::Test::SqlFunctionHandle->new( rows => $rows );
    my $tags   = GPForum::Service::Forum::ThreadTags->new(
        functions =>
          GPForum::Infrastructure::SqlFunction->new( schema => $handle ),
        schema => $handle,
    );
    return ( $handle, $tags );
}

subtest 'a text names tags: trimmed, folded, one per slug, five at most' =>
  sub {
    my ( undef, $tags ) = fixture();
    is_deeply(
        $tags->normalise('  Perl ,PostgreSQL, perl,  Web   dev ,Café'),
        [
            { name => 'Perl',       slug => 'perl' },
            { name => 'PostgreSQL', slug => 'postgresql' },
            { name => 'Web dev',    slug => 'web-dev' },
            { name => 'Café',       slug => 'cafe' },
        ],
        'each trimmed and folded, a repeated slug once, marks dropped'
    );
    is_deeply( $tags->normalise(undef),   [], 'nothing names nothing' );
    is_deeply( $tags->normalise(' , ,,'), [], 'nor do empty parts' );
    is_deeply(
        $tags->normalise('a,b,c,d,e,f,g'),
        [ map { { name => $_, slug => $_ } } qw(a b c d e) ],
        'the first five are kept'
    );
    is( scalar @{ $tags->normalise( join q{,}, ('x') x ( $MAX_TAGS + 2 ) ) },
        1, 'one slug is one tag however often it is named' );
    is_deeply(
        $tags->normalise( ( 'x' x $OVER_MAX ) . ',ok,***' ),
        [ { name => 'ok', slug => 'ok' } ],
        'a name over thirty characters or without a letter or digit is left out'
    );
  };

subtest 'the tags are set after the thread, slugs and names in order' => sub {
    my ( $handle, $tags ) = fixture(
        [
            { name => 'Perl',       slug => 'perl',       tag_position => 1 },
            { name => 'PostgreSQL', slug => 'postgresql', tag_position => 2 },
        ]
    );
    is_deeply(
        $tags->set_thread_tags( $THREAD, 'Perl, PostgreSQL' ),
        [
            { name => 'Perl',       slug => 'perl' },
            { name => 'PostgreSQL', slug => 'postgresql' },
        ],
        'the thread has the tags the function answers'
    );
    like(
        $handle->prepared->[0],
        qr/api[.]forum_set_thread_tags_v2/msx,
        'through the write function'
    );
    my $bound = $handle->executed->[0];
    is( $bound->[0], $THREAD, 'for the thread' );
    is_deeply( $bound->[1], [qw(perl postgresql)], 'with the slugs in order' );
    is_deeply( $bound->[2], [qw(Perl PostgreSQL)], 'and the names' );
};

subtest 'a thread id that is not a uuid sets nothing' => sub {
    my ( $handle, $tags ) = fixture( [ { name => 'x', slug => 'x' } ] );
    is_deeply( $tags->set_thread_tags( 'thread-1', 'x' ), [], 'nothing' );
    is( scalar @{ $handle->executed }, 0, 'and the database heard nothing' );
};

subtest 'the page reads the tags of its threads in one call' => sub {
    my ( $handle, $tags ) = fixture(
        [
            {
                name         => 'Perl',
                slug         => 'perl',
                tag_position => 1,
                thread_id    => $THREAD
            },
            {
                name         => 'Web dev',
                slug         => 'web-dev',
                tag_position => 2,
                thread_id    => $THREAD
            },
            {
                name         => 'Café',
                slug         => 'cafe',
                tag_position => 1,
                thread_id    => $OTHER
            },
        ]
    );
    is_deeply(
        $tags->tags_for_threads( [ $THREAD, $OTHER, 'thread-1' ] ),
        {
            $THREAD => [
                { name => 'Perl',    slug => 'perl' },
                { name => 'Web dev', slug => 'web-dev' },
            ],
            $OTHER => [ { name => 'Café', slug => 'cafe' } ],
        },
        'by thread id, each list in order'
    );
    like(
        $handle->prepared->[0],
        qr/api[.]forum_thread_tags_v2/msx,
        'through the read function'
    );
    is( scalar @{ $handle->executed }, 1, 'in one statement' );
    is_deeply( $tags->tags_for_threads( ['thread-1'] ),
        {}, 'ids that are not uuids are not asked about' );
};

subtest 'the tag page lists the threads the viewer may read' => sub {
    my ( $handle, $tags ) = fixture(
        [
            {
                author_username  => 'giacomo',
                category_id      => $CATEGORY,
                category_title   => 'General',
                last_activity_at => '2026-10-15T10:00:00Z',
                pinned           => 0,
                reply_count      => 2,
                thread_id        => $THREAD,
                title            => 'Perl in 2026',
            }
        ]
    );
    my $viewer = GPForum::Service::Forum::Viewer->new(
        member  => 1,
        user_id => $MEMBER
    );
    my $threads = $tags->list_tagged_threads(
        {
            category_id => $CATEGORY,
            limit       => $LIMIT,
            slug        => 'perl',
            viewer      => $viewer
        }
    );
    is( scalar @{$threads},                     1,       'one thread' );
    is( $threads->[0]->get_column('thread_id'), $THREAD, 'as a row' );
    is( $threads->[0]->get_column('category_title'),
        'General', 'with its category' );
    like(
        $handle->prepared->[0],
        qr/api[.]forum_list_tagged_threads_v2/msx,
        'through the list function'
    );
    my $bound = $handle->executed->[0];
    is_deeply(
        [ @{$bound}[ 0 .. $VIEWER_ARGS ] ],
        [ 'perl', $CATEGORY, 1, 0, $MEMBER ],
        'with the slug, the category and the viewer'
    );
    is( $bound->[-1], $LIMIT, 'and the limit' );

    $tags->list_tagged_threads( { slug => 'perl', category_id => 'nope' } );
    is( $handle->executed->[-1][1],
        undef, 'a category that is not an id is no filter' );
    is( $handle->executed->[-1][2], 0, 'and no viewer is anonymous' );
};

subtest 'the index counts the threads under each tag' => sub {
    my ( $handle, $tags ) =
      fixture( [ { name => 'Perl', slug => 'perl', thread_count => 3 } ] );
    is_deeply(
        $tags->list_tags(
            { viewer => GPForum::Service::Forum::Viewer->anonymous }
        ),
        [ { name => 'Perl', slug => 'perl', thread_count => 3 } ],
        'each with its count'
    );
    like(
        $handle->prepared->[0],
        qr/api[.]forum_list_tags_v2/msx,
        'through the index function'
    );
};

subtest 'a slug has one form' => sub {
    my ( undef, $tags ) = fixture();
    ok( $tags->is_slug('web-dev'),  'letters, digits and single dashes' );
    ok( !$tags->is_slug('Web-Dev'), 'not upper case' );
    ok( !$tags->is_slug('-web'),    'not a leading dash' );
    ok( !$tags->is_slug('a--b'),    'not two dashes' );
    ok( !$tags->is_slug(undef),     'not nothing' );
    ok( !$tags->is_slug( 'x' x $OVER_MAX ), 'not over thirty characters' );
};

subtest 'tags exist only as functions' => sub {
    my $tags = GPForum::Service::Forum::ThreadTags->new(
        functions => undef,
        schema    => GPForum::Test::SqlFunctionHandle->new,
    );
    like(
        exception { $tags->tags_for_threads( [$THREAD] ) },
        qr/SQL [ ] function [ ] layer/msx,
        'without the call layer the service refuses to guess'
    );
};

done_testing();

1;
