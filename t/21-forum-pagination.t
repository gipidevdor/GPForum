# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use MIME::Base64 qw(encode_base64url);
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Service::Forum::PageWindow;
use GPForum::Service::Forum::PostReader;
use GPForum::Service::Forum::ThreadReader;
use GPForum::Test::AnsweringFunctions;
use GPForum::Test::ForumReadRow;

our $VERSION = '0.001';

const my $EXPECTED_TESTS => 37;
const my $DEFAULT_LIMIT  => 25;
const my $MAX_LIMIT      => 100;
const my $REQUEST_LIMIT  => 2;
const my $MAX_PAGE_WALK  => 20;
const my $FULLWIDTH_ONE  => chr 0xFF11;

plan tests => $EXPECTED_TESTS;

my $page_window  = GPForum::Service::Forum::PageWindow->new;
my $default_plan = $page_window->plan( {} );

is( $default_plan->{limit}, $DEFAULT_LIMIT, 'page window defaults limit' );
is(
    $default_plan->{fetch_rows},
    $DEFAULT_LIMIT + 1,
    'page window fetches one extra row'
);

my $bounded_plan = $page_window->plan( { limit => $MAX_LIMIT + 1 } );
is( $bounded_plan->{limit}, $MAX_LIMIT, 'page window clamps max limit' );

my $low_plan = $page_window->plan( { limit => 0 } );
is( $low_plan->{limit}, 1, 'page window clamps minimum limit' );

my $invalid_limit_plan = $page_window->plan( { limit => 'many' } );
is( $invalid_limit_plan->{limit},
    $DEFAULT_LIMIT, 'page window defaults invalid limit' );

my $invalid_cursor_plan = $page_window->plan( { after => 'not-a-cursor' } );
is( $invalid_cursor_plan->{after},
    undef, 'page window ignores malformed cursor' );

# A list binds its cursor as the type it sorts by: a timestamp given to a
# list of positions reached PostgreSQL as a bigint and failed the request.
my $position_cursor =
  encode_base64url( join q{|}, '12', '018f1000-0000-7000-8000-000000000105' );
my $timestamp_cursor = encode_base64url( join q{|}, '2026-05-23T12:02:00Z',
    '018f1000-0000-7000-8000-000000000105' );
is(
    $page_window->plan( { after => $timestamp_cursor, sort => 'position' } )
      ->{after},
    undef,
    'a list of positions takes no timestamp cursor'
);
is(
    $page_window->plan( { after => $position_cursor, sort => 'timestamp' } )
      ->{after},
    undef,
    'a list of timestamps takes no position cursor'
);
is(
    $page_window->plan( { after => $position_cursor, sort => 'position' } )
      ->{after}{sort_value},
    '12',
    'a list of positions takes a position cursor'
);
is(
    $page_window->plan( { after => $timestamp_cursor, sort => 'timestamp' } )
      ->{after}{sort_value},
    '2026-05-23T12:02:00Z',
    'a list of timestamps takes a timestamp cursor'
);
is(
    $page_window->plan(
        { after => "${FULLWIDTH_ONE}|018f1000-0000-7000-8000-000000000105" }
    )->{after},
    undef,
    'a fullwidth digit is no position'
);

my $thread_rows = [
    _row(
        {
            thread_id        => '018f1000-0000-7000-8000-000000000105',
            last_activity_at => '2026-05-23T12:03:00Z',
        }
    ),
    _row(
        {
            thread_id        => '018f1000-0000-7000-8000-000000000104',
            last_activity_at => '2026-05-23T12:02:00Z',
        }
    ),
    _row(
        {
            thread_id        => '018f1000-0000-7000-8000-000000000103',
            last_activity_at => '2026-05-23T12:01:00Z',
        }
    ),
];
my $thread_page =
  $page_window->page( $thread_rows, $REQUEST_LIMIT,
    [ 'last_activity_at', 'thread_id' ] );

is( scalar @{ $thread_page->{items} }, $REQUEST_LIMIT, 'page trims extra row' );
ok( $thread_page->{has_next},    'page marks next page' );
ok( $thread_page->{next_cursor}, 'page emits next cursor' );

my $decoded_plan =
  $page_window->plan( { after => $thread_page->{next_cursor} } );
is( $decoded_plan->{after}{sort_value},
    '2026-05-23T12:02:00Z', 'cursor stores sort value' );
is(
    $decoded_plan->{after}{id},
    '018f1000-0000-7000-8000-000000000104',
    'cursor stores id'
);

my $post_rows = [
    _row(
        { post_id => '018f1000-0000-7000-8000-000000000100', position => 1 }
    ),
    _row(
        { post_id => '018f1000-0000-7000-8000-000000000101', position => 2 }
    ),
    _row(
        { post_id => '018f1000-0000-7000-8000-000000000102', position => 3 }
    ),
];
my $post_page =
  $page_window->page( $post_rows, $REQUEST_LIMIT, [ 'position', 'post_id' ] );
is( scalar @{ $post_page->{items} },
    $REQUEST_LIMIT, 'post page trims extra row' );
ok( $post_page->{next_cursor}, 'post page emits cursor' );

# The readers ask their functions for a page of one row more than the
# limit, and carry the cursor of the last row they keep. What the functions
# do with the values is the integration tier's (postgres-sql-function-forum-
# reads.t); here, what the readers ask and what they make of the rows.
my $functions = GPForum::Test::AnsweringFunctions->new(
    answers => {
        forum_list_category_threads => [ map { _columns($_) } @{$thread_rows} ],
        forum_thread_page_posts     => [ map { _columns($_) } @{$post_rows} ],
    }
);
my $thread_reader = GPForum::Service::Forum::ThreadReader->new(
    functions => $functions,
    schema    => {},
);
my $category_page = $thread_reader->list_category_threads(
    {
        category_id => 'category-1',
        limit       => $REQUEST_LIMIT,
    }
);
my $category_asked = $functions->asked('forum_list_category_threads')->[-1];

is( scalar @{ $category_page->{items} },
    $REQUEST_LIMIT, 'thread reader returns page items' );
is( $category_asked->{category_id},
    'category-1', 'thread reader asks for the category' );
is(
    $category_asked->{row_limit},
    $REQUEST_LIMIT + 1,
    'thread reader fetches limit plus one'
);
is( $category_asked->{after_thread_id}, undef, 'the first page has no cursor' );

$thread_reader->list_category_threads(
    {
        category_id => 'category-1',
        limit       => $REQUEST_LIMIT,
        after       => $category_page->{next_cursor},
    }
);
$category_asked = $functions->asked('forum_list_category_threads')->[-1];
is( $category_asked->{after_pinned},
    0, 'thread cursor leads the keyset with pinned' );
is( $category_asked->{after_activity},
    '2026-05-23T12:02:00Z', 'thread cursor pages by activity within pinned' );
is(
    $category_asked->{after_thread_id},
    '018f1000-0000-7000-8000-000000000104',
    'thread cursor breaks an activity tie by thread id'
);

my $post_reader = GPForum::Service::Forum::PostReader->new(
    functions => $functions,
    schema    => {},
);
my $thread_post_page = $post_reader->list_thread_posts(
    {
        thread_id => '018f1000-0000-7000-8000-000000000103',
        limit     => $REQUEST_LIMIT,
    }
);
my $posts_asked = $functions->asked('forum_thread_page_posts')->[-1];

is( scalar @{ $thread_post_page->{items} },
    $REQUEST_LIMIT, 'post reader returns page items' );
is(
    $posts_asked->{thread_id},
    '018f1000-0000-7000-8000-000000000103',
    'post reader asks for the thread'
);
is(
    $posts_asked->{row_limit},
    $REQUEST_LIMIT + 1,
    'post reader fetches limit plus one'
);
is( $posts_asked->{standing},
    'anonymous', 'an anonymous page reads as anonymous' );

$post_reader->list_thread_posts(
    {
        thread_id => '018f1000-0000-7000-8000-000000000103',
        limit     => $REQUEST_LIMIT,
        after     => $thread_post_page->{next_cursor},
    }
);
$posts_asked = $functions->asked('forum_thread_page_posts')->[-1];
is( $posts_asked->{after_position}, 2, 'post cursor pages by position' );
is(
    $posts_asked->{after_post_id},
    '018f1000-0000-7000-8000-000000000101',
    'post cursor breaks a position tie by post id'
);

# A pinned thread sorts ahead of every unpinned one no matter how stale it is,
# so a cursor that ignored pinned made page two repeat or skip whole threads.
# The double orders and bounds as the function does, so the walk shows the
# cursor the reader writes is the one it reads back.
my @keyset_rows = (
    _keyset_row(
        '018f1000-0000-7000-8000-000000000111',
        1, '2026-05-20T09:00:00Z'
    ),
    _keyset_row(
        '018f1000-0000-7000-8000-000000000112',
        1, '2026-05-19T09:00:00Z'
    ),
    _keyset_row(
        '018f1000-0000-7000-8000-000000000106',
        0, '2026-05-24T09:00:00Z'
    ),
    _keyset_row(
        '018f1000-0000-7000-8000-000000000107',
        0, '2026-05-23T09:00:00Z'
    ),
    _keyset_row(
        '018f1000-0000-7000-8000-000000000108',
        0, '2026-05-22T09:00:00Z'
    ),
    _keyset_row(
        '018f1000-0000-7000-8000-000000000109',
        0, '2026-05-18T09:00:00Z'
    ),
    _keyset_row(
        '018f1000-0000-7000-8000-000000000110',
        0, '2026-05-17T09:00:00Z'
    ),
);
my $keyset_functions = GPForum::Test::AnsweringFunctions->new(
    answers => {
        forum_list_category_threads =>
          sub ($values) { return _keyset_page( \@keyset_rows, $values ); },
    }
);
my $keyset_reader = GPForum::Service::Forum::ThreadReader->new(
    functions => $keyset_functions,
    schema    => {},
);
my $walk = _walk_category_pages( $keyset_reader, $REQUEST_LIMIT );

ok( $walk->{pages} > 1, 'pinned keyset paging spans more than one page' );
is(
    scalar @{ $walk->{ids} },
    scalar @keyset_rows,
    'pinned keyset paging returns every thread exactly once'
);
is_deeply(
    [ sort @{ $walk->{ids} } ],
    [ sort map { $_->{thread_id} } @keyset_rows ],
    'pinned keyset paging neither drops nor duplicates a thread'
);
is_deeply(
    $walk->{ids},
    [
        '018f1000-0000-7000-8000-000000000111',
        '018f1000-0000-7000-8000-000000000112',
        '018f1000-0000-7000-8000-000000000106',
        '018f1000-0000-7000-8000-000000000107',
        '018f1000-0000-7000-8000-000000000108',
        '018f1000-0000-7000-8000-000000000109',
        '018f1000-0000-7000-8000-000000000110',
    ],
    'pinned keyset paging keeps pinned threads ahead of fresher ones'
);

my $legacy_cursor =
  encode_base64url('2026-05-23T09:00:00Z|018f1000-0000-7000-8000-000000000107');
my $legacy_page = $keyset_reader->list_category_threads(
    {
        category_id => 'category-1',
        limit       => $REQUEST_LIMIT,
        after       => $legacy_cursor,
    }
);

ok( $legacy_page, 'a two-part cursor still answers a page' );
is(
    $keyset_functions->asked('forum_list_category_threads')
      ->[-1]{after_thread_id},
    undef, 'the first one: a cursor without its pinned part is no cursor'
);

sub _walk_category_pages {
    my ( $reader, $limit ) = @_;

    my @ids;
    my $pages = 0;
    my $after;
    while ( $pages < $MAX_PAGE_WALK ) {
        my $page = $reader->list_category_threads(
            {
                after       => $after,
                category_id => 'category-1',
                limit       => $limit,
            }
        );
        push @ids, map { $_->get_column('thread_id') } @{ $page->{items} };
        $pages += 1;
        last if !$page->{has_next};
        $after = $page->{next_cursor};
    }

    return { ids => \@ids, pages => $pages };
}

# The rows after the cursor, in the category order -- pinned, then activity,
# then id, all descending -- up to the row limit.
sub _keyset_page ( $rows, $values ) {
    my @ordered = sort {
             $b->{pinned}           <=> $a->{pinned}
          || $b->{last_activity_at} cmp $a->{last_activity_at}
          || $b->{thread_id}        cmp $a->{thread_id}
    } @{$rows};
    if ( defined $values->{after_thread_id} ) {
        my $after =
          [ @{$values}{qw(after_pinned after_activity after_thread_id)} ];
        @ordered = grep {
            _before( [ @{$_}{qw(pinned last_activity_at thread_id)} ], $after )
        } @ordered;
    }

    return [ grep { defined } @ordered[ 0 .. $values->{row_limit} - 1 ] ];
}

# Whether a key sorts after the cursor's in the descending order.
sub _before ( $key, $after ) {
    return $key->[0] < $after->[0]           if $key->[0] != $after->[0];
    return ( $key->[1] cmp $after->[1] ) < 0 if $key->[1] ne $after->[1];

    return ( $key->[2] cmp $after->[2] ) < 0;
}

sub _keyset_row {
    my ( $thread_id, $pinned, $last_activity_at ) = @_;

    return {
        category_id      => 'category-1',
        last_activity_at => $last_activity_at,
        moderation_state => 'visible',
        pinned           => $pinned,
        thread_id        => $thread_id,
        visibility       => 'public',
    };
}

sub _columns ($row) {
    return { $row->get_columns };
}

sub _row {
    my ($data) = @_;

    return GPForum::Test::ForumReadRow->new( data => $data );
}

1;
