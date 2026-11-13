# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Carp qw(croak);
use Const::Fast;
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Benchmark::SeedDataset qw(seed_id);
use GPForum::Infrastructure::Row    qw(rows_in);
use GPForum::Service::Forum::CategoryReader;
use GPForum::Service::Forum::HomePageReader;
use GPForum::Service::Forum::PostReader;
use GPForum::Service::Forum::Readability;
use GPForum::Service::Forum::ThreadReader;
use GPForum::Service::Forum::Viewer;
use GPForum::Test::PgDatabase;

our $VERSION = '0.001';

const my $OTHER_USER        => 3;
const my $CATEGORIES        => 3;
const my @CATEGORY_LIMITS   => ( 1, 3, 100 );
const my @THREAD_LIMITS     => ( 1, 7, 100 );
const my $PAGE_GUARD        => 100;
const my $HOME_THREAD_LIMIT => 3;

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'set GPFORUM_TEST_DSN to compare forum read functions';
}

# Compare the functions to the resultsets the query-plan evidence keeps
# beside them, on the same data: all visibility levels, grants without
# membership, independent scope and deleted-row viewer ids, tied activity
# times, pinned-block transitions, hidden/deleted rows and every page,
# rather than only the first page. A lookup has no resultset: it is checked
# against the list it would appear in, and against the source's placement.
my $database   = GPForum::Test::PgDatabase->fresh( seed => 1 );
my $schema     = $database->schema;
my $dbh        = $database->dbh;
my $user       = seed_id( user  => 2 );
my $other      = seed_id( user  => 3 );
my $space      = seed_id( space => 1 );
my @categories = map { seed_id( category => $_ ) } 1 .. $CATEGORIES;

_fixture();

my %viewer = (
    anonymous => GPForum::Service::Forum::Viewer->anonymous,
    member    => GPForum::Service::Forum::Viewer->new(
        member  => 1,
        user_id => $user
    ),
    suspended      => GPForum::Service::Forum::Viewer->new( user_id => $user ),
    category_grant => GPForum::Service::Forum::Viewer->new(
        category_ids => [ $categories[2] ],
        member       => 1,
        user_id      => $other
    ),
    space_grant => GPForum::Service::Forum::Viewer->new(
        space_ids => [$space],
        member    => 1,
        user_id   => $other
    ),
    grant_without_membership => GPForum::Service::Forum::Viewer->new(
        category_ids => [ $categories[2] ],
        user_id      => $other
    ),
    global => GPForum::Service::Forum::Viewer->new(
        global_read => 1,
        member      => 1,
        user_id     => $other
    ),
    global_without_membership => GPForum::Service::Forum::Viewer->new(
        global_read => 1
    ),
    accountless_member => GPForum::Service::Forum::Viewer->new( member => 1 ),
);

my %path = ( function => _readers() );

subtest 'category, latest and home visibility agrees' => \&_compare_categories;
subtest 'category pages retain visibility, deleted rows and pinned cursors' =>
  \&_compare_category_pages;
subtest 'post lookups agree with the pages and the placement' =>
  \&_compare_posts;
subtest 'post pages agree for every viewer, their own deleted posts included' =>
  \&_compare_post_pages;
subtest 'deleted category and malformed lookup ids still fail closed' =>
  \&_refusals;

done_testing();

sub _compare_categories {
    my $reader = $path{function}{categories};
    for my $visibility (qw(public members private)) {
        $dbh->do( 'UPDATE spaces SET visibility = ? WHERE space_id = ?',
            undef, $visibility, $space );
        for my $name ( sort keys %viewer ) {
            my $scope = $viewer{$name};
            for my $limit (@CATEGORY_LIMITS) {
                is_deeply(
                    _columns(
                        $reader->list_categories(
                            { limit => $limit, viewer => $scope }
                        )
                    ),
                    _columns(
                        [
                            rows_in(
                                $reader->categories_resultset( $limit, $scope )
                            )
                        ]
                    ),
                    "$visibility/$name: category list $limit"
                );
            }
            my %listed = map { $_->get_column('category_id') => 1 }
              rows_in( $reader->categories_resultset( 100, $scope ) );
            for my $category (@categories) {

                # A known disagreement: the list reads global_read as every
                # level, the lookup (Visibility->readable) still asks a
                # members-only level for membership. Only a viewer with the
                # grant and no membership -- a suspended administrator --
                # sees the difference.
                local $TODO =
                  $name eq 'global_without_membership'
                  ? 'the list and the lookup disagree on global_read without membership'
                  : undef;
                is(
                    defined $reader->find_category( $category, $scope ) ? 1 : 0,
                    $listed{$category}                                  ? 1 : 0,
                    "$visibility/$name: category lookup $category"
                );
            }
            my $request = { limit => $HOME_THREAD_LIMIT, viewer => $scope };
            _pages( 'list_public_threads', $request,
                "$visibility/$name: latest" );
        }
    }
    $dbh->do( 'UPDATE spaces SET visibility = ? WHERE space_id = ?',
        undef, 'public', $space );
    return;
}

sub _compare_category_pages {
    for my $name ( sort keys %viewer ) {
        my $scope = $viewer{$name}->within( $categories[0], $space );
        for my $deleted_viewer ( undef, $user, $other ) {
            for my $limit (@THREAD_LIMITS) {
                _pages(
                    'list_category_threads',
                    {
                        category_id    => $categories[0],
                        limit          => $limit,
                        viewer_scope   => $scope,
                        viewer_user_id => $deleted_viewer,
                    },
                    "$name/deleted="
                      . ( $deleted_viewer // 'none' )
                      . "/limit=$limit"
                );
            }
        }
    }
    return;
}

sub _compare_posts {
    my $posts = $dbh->selectall_arrayref(
        'SELECT post_id, thread_id FROM posts ORDER BY post_id LIMIT 40',
        { Slice => {} } );
    my $reader = $path{function}{posts};
    for my $post ( @{$posts} ) {
        is( $reader->find_post( $post->{post_id} )->get_column('post_id'),
            $post->{post_id}, "unfiltered post $post->{post_id}" );
        for my $name ( sort keys %viewer ) {
            my $scope = $viewer{$name};
            is(
                defined $reader->find_visible_post( $post->{post_id}, $scope )
                ? 1
                : 0,
                $path{function}{readability}
                  ->readable_by( $scope, 'post', $post->{post_id} ),
                "$name: visible post $post->{post_id} as its placement says"
            );
            for my $deleted_viewer ( undef, $user ) {
                my $request = {
                    %{$post},
                    viewer_scope   => $scope,
                    viewer_user_id => $deleted_viewer,
                };
                my %listed = map { $_->get_column('post_id') => 1 } rows_in(
                    $reader->thread_posts_resultset(
                        { %{$request}, limit => 100 }
                    )
                );
                is(
                    defined $reader->find_listed_post($request) ? 1 : 0,
                    $listed{ $post->{post_id} }                 ? 1 : 0,
                    "$name: listed post $post->{post_id}/"
                      . ( $deleted_viewer // 'none' )
                );
            }
        }
    }
    return;
}

sub _refusals {
    $dbh->do( 'UPDATE categories SET deleted_at = now() WHERE category_id = ?',
        undef, $categories[0] );
    for my $name ( sort keys %viewer ) {
        ok(
            !$path{function}{categories}
              ->find_category( $categories[0], $viewer{$name} ),
            "$name: deleted category unavailable"
        );
    }
    for my $id ( undef, q{}, 'not-a-uuid',
        '018f1005-ffff-7000-8000-00000000ffff' )
    {
        ok( !$path{function}{posts}->find_post($id), 'unavailable post id' );
        ok( !$path{function}{posts}->find_visible_post($id),
            'unavailable visible post id' );
        ok( !$path{function}{categories}->find_category($id),
            'unavailable category id' );
    }
    return;
}

sub _compare_post_pages {
    for my $number ( 1 .. $CATEGORIES ) {
        my $thread = seed_id( thread => $number );
        for my $name ( sort keys %viewer ) {
            my $scope =
              $viewer{$name}->within( $categories[ $number - 1 ], $space );

            # A page is read as one viewer: the posts they may read and the
            # deleted posts of their own.
            for my $deleted_viewer ( $scope->user_id ) {
                my $after;
                my %seen;
                for my $page ( 1 .. $PAGE_GUARD ) {
                    my $request = {
                        after          => $after,
                        limit          => 1,
                        thread_id      => $thread,
                        viewer_scope   => $scope,
                        viewer_user_id => $deleted_viewer,
                    };
                    my $reader = $path{function}{posts};
                    my $got    = $reader->list_thread_posts($request);
                    is_deeply(
                        _page_of($got),
                        _resultset_page(
                            $reader->thread_posts_resultset($request), 1
                        ),
                        "$thread/$name/deleted="
                          . ( $deleted_viewer // 'none' )
                          . "/page=$page"
                    );
                    for my $row ( @{ $got->{items} } ) {
                        ok( !$seen{ $row->get_column('post_id') }++,
                            'no repeated post' );
                    }
                    last if !$got->{has_next};
                    $after = $got->{next_cursor};
                    if ( $page == $PAGE_GUARD ) {
                        croak 'post pagination did not terminate';
                    }
                }
            }
        }
    }
    return;
}

sub _readers {
    my %reader;
    for my $item (
        [ categories  => 'CategoryReader' ],
        [ posts       => 'PostReader' ],
        [ threads     => 'ThreadReader' ],
        [ readability => 'Readability' ]
      )
    {
        my ( $name, $class ) = @{$item};
        $class = "GPForum::Service::Forum::$class";
        $reader{$name} = $class->new( schema => $schema );
    }
    $reader{home} = GPForum::Service::Forum::HomePageReader->new(
        category_reader => $reader{categories},
        thread_reader   => $reader{threads}
    );
    return \%reader;
}

# A thread page's posts also name the author's picture on the function
# path (ADR 0144), and the latest threads their opening post's excerpt
# (migration 1056), which the resultsets do not read: the rest must match
# column for column.
sub _columns ($rows) {
    return undef                             if !$rows;
    return [ map { _columns($_) } @{$rows} ] if ref $rows eq 'ARRAY';

    my %columns = $rows->get_columns;
    delete @columns{qw(author_avatar_id excerpt)};

    return \%columns;
}

# A page as its items' columns and whether another follows.
sub _page_of ($page) {
    return {
        has_next => $page->{has_next},
        items    => _columns( $page->{items} )
    };
}

# The same from a resultset that reads one row more than the limit.
sub _resultset_page ( $resultset, $limit ) {
    my @rows     = rows_in($resultset);
    my $has_next = @rows > $limit ? 1 : 0;
    return {
        has_next => $has_next,
        items    =>
          _columns( [ @rows[ 0 .. ( $has_next ? $limit : @rows ) - 1 ] ] )
    };
}

sub _pages ( $method, $request, $label ) {
    my %resultset = (
        list_public_threads   => 'latest_threads_resultset',
        list_category_threads => 'category_threads_resultset',
    );
    my $reader = $path{function}{threads};
    my $after;
    my %seen;
    for my $page ( 1 .. $PAGE_GUARD ) {
        my $input = { %{$request}, after => $after };
        my $got   = $reader->$method($input);
        my $from  = $resultset{$method};
        is_deeply(
            _page_of($got),
            _resultset_page( $reader->$from($input), $request->{limit} ),
            "$label: page $page"
        );
        for my $row ( @{ $got->{items} } ) {
            ok( !$seen{ $row->get_column('thread_id') }++,
                "$label: no repeated thread" );
        }
        last if !$got->{has_next};
        $after = $got->{next_cursor};
        if ( $page == $PAGE_GUARD ) {
            croak 'pagination did not terminate';
        }
    }
    return;
}

sub _fixture {
    for my $number ( 1 .. $CATEGORIES ) {
        $dbh->do(
            'UPDATE categories SET visibility = ? WHERE category_id = ?',
            undef,
            (qw(public members private))[ $number - 1 ],
            $categories[ $number - 1 ]
        );
    }
    $dbh->do(
q{INSERT INTO threads (thread_id, category_id, author_user_id, title, slug,}
          . q{ pinned, visibility, moderation_state, deleted_at, deleted_by, last_activity_at)}
          . q{ SELECT gen_random_uuid(), ?, (ARRAY[?, ?]::uuid[])[1 + n % 2],}
          . q{ 'Read fixture ' || n, 'read-fixture-' || n, n % 5 = 0,}
          . q{ (ARRAY['public', 'members', 'private'])[1 + n % 3],}
          . q{ CASE WHEN n % 11 = 0 THEN 'hidden' ELSE 'visible' END,}
          . q{ CASE WHEN n % 7 = 0 THEN now() END,}
          . q{ CASE WHEN n % 7 = 0 THEN (ARRAY[?, ?]::uuid[])[1 + n % 2] END,}
          . q{ timestamptz '2026-01-01' + (n / 4) * interval '1 minute'}
          . q{ FROM generate_series(1, 40) AS n},
        undef, $categories[0], $user, $other, $user, $other
    );
    $dbh->do(
q{UPDATE posts SET visibility = (ARRAY['public', 'members', 'private'])[1 + position % 3],}
          . q{ moderation_state = CASE WHEN position % 5 = 0 THEN 'hidden' ELSE 'visible' END,}
          . q{ deleted_at = CASE WHEN position % 7 = 0 THEN now() END,}
          . q{ deleted_by = CASE WHEN position % 7 = 0 THEN author_user_id END}
    );
    $dbh->do('ANALYZE');
    return;
}

1;
