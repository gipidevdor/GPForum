# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Service::Forum::CategoryReader;
use GPForum::Service::Forum::Viewer;
use GPForum::Service::Forum::HomePageReader;
use GPForum::Service::Forum::PostReader;
use GPForum::Service::Forum::ThreadDetailReader;
use GPForum::Service::Forum::ThreadReader;
use GPForum::Service::Operations::LocalCache;
use GPForum::Test::AnsweringFunctions;
use GPForum::Test::ForumWebServices;

our $VERSION = '0.001';

# What the forum readers make of the rows their functions answer: which
# categories and threads a viewer may find, how pages are cut and cached,
# and what the home page shows. What the functions select, and in what
# order, is the integration tier's (postgres-sql-function-forum-reads.t and
# postgres-effective-visibility.t).

const my $CATEGORY_LIMIT => 10;
const my $DEFAULT_LIMIT  => 100;
const my $HOME_FETCH     => 2;

my %category = (
    general => {
        category_id      => 'category-1',
        title            => 'General',
        slug             => 'general',
        deleted_at       => undef,
        space_id         => 'space-1',
        space_visibility => 'public',
        visibility       => 'public',
    },
    staff => {
        category_id      => 'category-staff',
        title            => 'Staff',
        slug             => 'staff',
        deleted_at       => undef,
        space_id         => 'space-1',
        space_visibility => 'public',
        visibility       => 'private',
    },
    deleted => {
        category_id      => 'category-deleted',
        deleted_at       => '2026-05-23T12:00:00Z',
        space_id         => 'space-1',
        space_visibility => 'public',
        visibility       => 'public',
    },
);
my %thread = (
    'thread-1'      => _thread( 'thread-1', 'Welcome', '2026-05-23T12:00:00Z' ),
    'thread-2'      => _thread( 'thread-2', 'Second',  '2026-05-23T11:00:00Z' ),
    'thread-hidden' => _thread(
        'thread-hidden', 'Hidden',
        '2026-05-22',    moderation_state => 'hidden'
    ),
    'thread-locked' => _thread(
        'thread-locked', 'Locked',
        '2026-05-22',    moderation_state => 'locked'
    ),
    'thread-deleted' => _thread(
        'thread-deleted', 'Gone',
        '2026-05-22',     deleted_at => '2026-05-23T12:00:00Z'
    ),
);
my @posts = ( _post( 'post-1', 1 ), _post( 'post-2', 2 ) );
my $private_post =
  _post( 'post-private', scalar @posts + 1, visibility => 'members' );

my $functions = GPForum::Test::AnsweringFunctions->new(
    answers => {
        forum_list_categories => [ $category{general} ],
        forum_find_category   => sub ($values) {
            return [ grep { $_->{category_id} eq $values->{category_id} }
                  values %category ];
        },
        forum_list_public_threads   => [ @thread{qw(thread-1 thread-2)} ],
        forum_list_category_threads => [ @thread{qw(thread-1 thread-2)} ],
        forum_thread_page_head      => sub ($values) {
            return [ $thread{ $values->{thread_id} } // () ];
        },
        forum_thread_page_snapshot => sub ($values) {
            my $head = $thread{ $values->{thread_id} } or return [];
            return [
                {
                    thread_head => $head,
                    posts       => [ @posts[ 0 .. $values->{page_limit} ] ],
                    page_reads  => [],
                }
            ];
        },
        forum_find_visible_post => sub ($values) {
            return [
                grep { $_->{post_id} eq $values->{post_id} } @posts,
                $private_post
            ];
        },
    }
);
my %readers = (
    category => GPForum::Service::Forum::CategoryReader->new(
        functions => $functions,
        schema    => {}
    ),
    thread => GPForum::Service::Forum::ThreadReader->new(
        functions => $functions,
        schema    => {}
    ),
    post => GPForum::Service::Forum::PostReader->new(
        functions => $functions,
        schema    => {}
    ),
);
$readers{detail} = GPForum::Service::Forum::ThreadDetailReader->new(
    functions   => $functions,
    post_reader => $readers{post},
    schema      => {},
);
my $granted = GPForum::Service::Forum::Viewer->new(
    category_ids => ['category-staff'],
    member       => 1,
    user_id      => 'user-staff',
);

subtest 'categories' => sub {
    my $categories =
      $readers{category}->list_categories( { limit => $CATEGORY_LIMIT } );
    is( scalar @{$categories}, 1, 'the list is the rows the function answers' );
    is( $functions->asked('forum_list_categories')->[-1]{row_limit},
        $CATEGORY_LIMIT, 'asked for the limit given' );
    $readers{category}->list_categories( { limit => 'wide-open' } );
    is( $functions->asked('forum_list_categories')->[-1]{row_limit},
        $DEFAULT_LIMIT, 'an invalid limit asks for the default' );

    # ADR 0102: a private category is not found for a reader who cannot read
    # it, and is for one whose grant covers it.
    is( $readers{category}->find_category('category-staff'),
        undef, 'an anonymous reader does not find a private category' );
    ok( $readers{category}->find_category( 'category-staff', $granted ),
        'a reader granted category.read on it does' );
    is( $readers{category}->find_category('category-1')->get_column('title'),
        'General', 'a public category is found' );
    is( $readers{category}->find_category('missing'),
        undef, 'a missing category is undef' );
    is( $readers{category}->find_category('category-deleted'),
        undef, 'a deleted category is not found' );
};

subtest 'a cached category list asks once' => sub {
    my $reader = GPForum::Service::Forum::CategoryReader->new(
        cache     => GPForum::Service::Operations::LocalCache->new,
        functions => $functions,
        schema    => {},
    );
    my $before = scalar @{ $functions->asked('forum_list_categories') };
    my $first  = $reader->list_categories( { limit => $CATEGORY_LIMIT } );
    my $cached = $reader->list_categories( { limit => $CATEGORY_LIMIT } );
    is(
        scalar @{ $functions->asked('forum_list_categories') },
        $before + 1,
        'the second list comes from the cache'
    );
    is_deeply( $cached, $first, 'and is the first' );
    is( ref $first->[0], 'HASH', 'as plain column hashes' );
};

subtest 'the home page' => sub {
    my $home = GPForum::Service::Forum::HomePageReader->new(
        category_reader => $readers{category},
        thread_reader   => $readers{thread},
    )->home_page( { category_limit => $CATEGORY_LIMIT, thread_limit => 1 } );

    is( scalar @{ $home->{categories} },
        1, 'home page reader returns category view models' );
    is( $home->{categories}[0]{title},
        'General', 'home page reader maps category title' );
    is( $functions->asked('forum_list_public_threads')->[-1]{row_limit},
        $HOME_FETCH, 'it asks for one thread more than it shows' );
    is( scalar @{ $home->{latest_threads}{items} },
        1, 'home page reader applies thread limit' );
    is( $home->{latest_threads}{items}[0]{thread_id},
        'thread-1', 'home page reader maps latest public thread' );
    ok(
        $home->{latest_threads}{next_cursor},
        'home page reader exposes keyset cursor'
    );
    is( $home->{latest_threads}{items}[0]{excerpt},
        q{}, 'a thread row without an excerpt shows none' );

    my $listed  = GPForum::Test::ForumWebServices->new;
    my $excerpt = GPForum::Service::Forum::HomePageReader->new(
        category_reader => $listed,
        thread_reader   => $listed,
    )->home_page( {} )->{latest_threads}{items}[0]{excerpt};
    is(
        $excerpt,
"First public post \N{EM DASH} caf\N{LATIN SMALL LETTER E WITH ACUTE} for all",
        q{the latest threads show their opening posts' excerpts, as text}
    );
};

subtest 'a category listing reads as its viewer' => sub {
    $readers{thread}->list_category_threads(
        { category_id => 'category-1', viewer_user_id => 'user-1' } );
    is(
        $functions->asked('forum_list_category_threads')->[-1]{viewer_user_id},
        'user-1', 'a signed-in reader is asked for, for their own deleted'
    );
    $readers{thread}->list_category_threads( { category_id => 'category-1' } );
    is(
        $functions->asked('forum_list_category_threads')->[-1]{viewer_user_id},
        undef, 'an anonymous reader is not'
    );
};

subtest 'a post is found only when its viewer may read it' => sub {
    is( $readers{post}->find_visible_post('post-1')->get_column('post_id'),
        'post-1', 'a public post is found' );
    is( $readers{post}->find_visible_post('post-private'),
        undef, 'a members-only post is not, for a visitor' );
    is(
        $readers{post}->find_visible_post(
            'post-private',
            GPForum::Service::Forum::Viewer->new(
                member  => 1,
                user_id => 'user-1'
            )
        )->get_column('post_id'),
        'post-private',
        'and is, for a member'
    );
};

subtest 'thread pages' => sub {
    is( $readers{detail}->find_thread('thread-1')->get_column('title'),
        'Welcome', 'a visible thread is found' );
    my $page =
      $readers{detail}->thread_page( { thread_id => 'thread-1', limit => 1 } );
    ok( $page->{ok}, 'its page is ok' );
    is( $page->{thread}->get_column('thread_id'),
        'thread-1', 'with the thread' );
    is( scalar @{ $page->{posts}{items} }, 1, 'and the post limit applied' );
    ok( $page->{posts}{next_cursor}, 'and a cursor to the next posts' );

    $readers{detail}->thread_page(
        {
            thread_id => 'thread-1',
            viewer    => GPForum::Service::Forum::Viewer->new(
                member  => 1,
                user_id => 'user-1'
            ),
        }
    );
    is(
        $functions->asked('forum_thread_page_snapshot')->[-1]{viewer_user_id},
        'user-1',
        'a signed-in page reads as its viewer, for their own deleted posts'
    );

    my $missing = $readers{detail}->thread_page( { thread_id => 'missing' } );
    is_deeply(
        $missing,
        { ok => 0, error => 'not_found' },
        'a missing thread page is not found'
    );
    is( $readers{detail}->find_thread('thread-hidden'),
        undef, 'a hidden thread is not visible' );
    is(
        $readers{detail}->find_thread('thread-locked')->get_column('thread_id'),
        'thread-locked', 'a locked thread remains readable'
    );
    is( $readers{detail}->find_thread('thread-deleted'),
        undef, 'a deleted thread is hidden from anonymous viewers' );
    is(
        $readers{detail}->find_thread( 'thread-deleted', 'user-1' )
          ->get_column('thread_id'),
        'thread-deleted',
        'and its author still sees it'
    );
};

done_testing();

sub _thread ( $thread_id, $title, $activity, %override ) {
    return {
        thread_id           => $thread_id,
        title               => $title,
        slug                => lc $title,
        category_id         => 'category-1',
        category_visibility => 'public',
        space_id            => 'space-1',
        space_visibility    => 'public',
        author_user_id      => 'user-1',
        visibility          => 'public',
        moderation_state    => 'visible',
        pinned              => 0,
        deleted_at          => undef,
        last_activity_at    => $activity,
        %override,
    };
}

sub _post ( $post_id, $position, %override ) {
    return {
        post_id             => $post_id,
        thread_id           => 'thread-1',
        author_user_id      => 'user-2',
        position            => $position,
        deleted_at          => undef,
        moderation_state    => 'visible',
        visibility          => 'public',
        thread_visibility   => 'public',
        thread_author       => 'user-1',
        category_id         => 'category-1',
        category_visibility => 'public',
        space_id            => 'space-1',
        space_visibility    => 'public',
        %override,
    };
}

1;
