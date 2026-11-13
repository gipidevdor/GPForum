# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use MIME::Base64 qw(encode_base64url);
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Benchmark::SeedDataset qw(seed_id);
use GPForum::Infrastructure::Row    qw(rows_in);
use GPForum::Infrastructure::SqlFunction;
use GPForum::Service::Forum::PostReader;
use GPForum::Service::Forum::ThreadDetailReader;
use GPForum::Service::Forum::Viewer;
use GPForum::Service::Operations::DbQueryStats;
use GPForum::Test::PgDatabase;
use GPForum::Test::Promise      qw(await_result);
use GPForum::Test::ReplacedSubs qw(with_replaced_subs);

our $VERSION = '0.001';

const my $SEEK_POSITION    => 25;
const my $ADDED_POSTS      => 60;
const my @LIMITS           => ( 1, 7, 25, 100 );
const my $DELETE_EVERY     => 7;
const my $HIDE_EVERY       => 11;
const my $NO_BODY_EVERY    => 5;
const my $FIRST_ADDED      => 9;
const my $AUTHORS          => 3;
const my $PRIVATE_CATEGORY => 3;
const my @SHAPES => map { _shapes_of($_) } qw(global member anonymous);

const my $POSTS_SQL => join q{ },
  q{INSERT INTO posts (post_id, thread_id, author_user_id, position,},
  q{visibility, moderation_state, deleted_at, deleted_by)},
  q{SELECT gen_random_uuid(), ?, (ARRAY[?, ?, ?]::uuid[])[1 + n % 3], n,},
  q{(ARRAY['public', 'members', 'private'])[1 + (n / 3) % 3],},
  q{CASE WHEN n % ? = 0 THEN 'hidden' ELSE 'visible' END,},
  q{CASE WHEN n % ? = 0 THEN now() END,},
  q{CASE WHEN n % ? = 0 THEN (ARRAY[?, ?, ?]::uuid[])[1 + n % 3] END},
  q{FROM generate_series(?::bigint, ?::bigint) AS n};
const my $BODIES_SQL => join q{ },
  q{WITH b AS (INSERT INTO post_bodies (body_id, post_id, body_format,},
  q{body_source, body_rendered_safe, source_hash)},
  q{SELECT gen_random_uuid(), p.post_id, 'markdown',},
  q{'Reply ' || p.position, '<p>Reply ' || p.position || '</p>',},
  q{md5(p.post_id::text) FROM posts p WHERE p.thread_id = ?},
  q{AND p.current_body_id IS NULL AND p.position % ? <> 0},
  q{RETURNING body_id, post_id)},
  q{UPDATE posts p SET current_body_id = b.body_id FROM b},
  q{WHERE b.post_id = p.post_id};

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'set GPFORUM_TEST_DSN to compare the thread page paths';
}

# ADR 0126, section 10: the thread page as one snapshot statement
# (api.forum_thread_page_snapshot) against the same page read in parts --
# the head (api.forum_thread_page_head) and the posts
# (api.forum_thread_page_posts) -- and the posts against the resultset the
# query-plan evidence keeps, on the same rows: every thread state, every
# viewer the page can have, every shape of the posts statement, every page
# of a thread at several page sizes, the ids a URL can bring. Same rows,
# same columns, same values, same cursors.
my $database = GPForum::Test::PgDatabase->fresh( seed => 1 );
my $dbh      = $database->dbh;
my $schema   = $database->schema;
my $stats    = GPForum::Service::Operations::DbQueryStats->new;
$stats->attach_to_schema($schema);

my @authors = map { seed_id( user => $_ ) } 1 .. $AUTHORS;
my %user    = (
    author => $authors[0],
    member => $authors[1],
    reader => $authors[-1],
);

# The seed puts thread n in category (n - 1) % 3 + 1; category 3 is made
# private, readable through a grant only.
my %thread = (
    deleted    => seed_id( thread => 4 ),
    hidden     => seed_id( thread => 7 ),
    locked     => seed_id( thread => 5 ),
    long       => seed_id( thread => 1 ),
    members    => seed_id( thread => 8 ),
    missing    => '018f1004-ffff-7000-8000-00000000ffff',
    private    => seed_id( thread => 2 ),
    restricted => seed_id( thread => 9 ),
);
_fixture();

my %viewer = (
    anonymous => GPForum::Service::Forum::Viewer->anonymous,
    author    => GPForum::Service::Forum::Viewer->new(
        member  => 1,
        user_id => $user{author},
    ),
    member => GPForum::Service::Forum::Viewer->new(
        member  => 1,
        user_id => $user{member},
    ),
    granted => GPForum::Service::Forum::Viewer->new(
        category_ids => [ seed_id( category => $PRIVATE_CATEGORY ) ],
        member       => 1,
        user_id      => $user{reader},
    ),
    moderator => GPForum::Service::Forum::Viewer->new(
        global_read => 1,
        member      => 1,
        user_id     => $user{reader},
    ),
    suspended =>
      GPForum::Service::Forum::Viewer->new( user_id => $user{member} ),
    accountless => GPForum::Service::Forum::Viewer->new( member => 1 ),
    unaccounted_moderator =>
      GPForum::Service::Forum::Viewer->new( global_read => 1, member => 1 ),
);

my %reader = %{ _readers() };

# Every shape the posts statement has is compared: the branches the
# function was called for are recorded as it runs.
my %shapes;
my $rows = GPForum::Infrastructure::SqlFunction->can('rows');
with_replaced_subs(
    'GPForum::Infrastructure::SqlFunction',
    {
        rows => sub ( $layer, $name, $values ) {
            if ( $name eq 'forum_thread_page_posts' ) {
                $shapes{ _shape($values) } = 1;
            }
            return $rows->( $layer, $name, $values );
        },
    },
    sub {
        for my $thread_name ( sort keys %thread ) {
            for my $viewer_name ( sort keys %viewer ) {
                _same_thread( $thread_name, $viewer_name );
                for my $limit (@LIMITS) {
                    _same_pages( $thread_name, $viewer_name, $limit );
                }
            }
        }
    }
);
is_deeply(
    [ sort keys %shapes ],
    [ sort @SHAPES ],
    'every shape of the posts statement was compared'
);

# The ids a URL can bring: another spelling of a thread's id, braces and
# capitals, finds the thread; one that is not an id finds nothing, and no
# statement is sent for it.
my $found = _columns( $reader{threads}->find_thread_row( $thread{long} ) );
for my $spelling ( uc $thread{long}, "{$thread{long}}" ) {
    is_deeply( _columns( $reader{threads}->find_thread_row($spelling) ),
        $found, "the thread as '$spelling'" );
}
for my $spelling ( 'not-a-uuid', q{} ) {
    is( $reader{threads}->find_thread_row($spelling),
        undef, "nothing as '$spelling'" );
}
my $before = $stats->{total_queries};
$reader{threads}->find_thread_row('not-a-uuid');
$reader{posts}->list_thread_posts( { limit => 1, thread_id => 'not-a-uuid' } );
is( $stats->{total_queries} - $before, 0, 'a malformed id sends no statement' );

# A cursor whose position is a timestamp is no cursor for a list of
# positions: the page is the first one. PageWindow used to let it through
# for every list, and PostgreSQL refused the bigint, which failed the
# request.
my $timestamp = encode_base64url("2026-01-01 00:00:00|$thread{long}");
my %first     = map {
    ( $_ // q{} ) => [
        map { _columns($_) } @{
            $reader{posts}->list_thread_posts(
                { after => $_, limit => 1, thread_id => $thread{long} }
            )->{items}
        }
    ]
} ( $timestamp, undef );
is_deeply( $first{$timestamp}, $first{q{}},
    'a timestamp cursor on the posts shows the first page' );

# The page is one statement.
my $start = $stats->{total_queries};
$reader{threads}
  ->thread_page( { thread_id => $thread{long}, viewer => $viewer{member} } );
is( $stats->{total_queries} - $start, 1, 'the thread page is one statement' );

_seek_pages();

done_testing();

# find_thread: the head the page shows, column for column, or none.
sub _same_thread ( $thread_name, $viewer_name ) {
    my $found = _columns( $reader{threads}
          ->find_thread( $thread{$thread_name}, $viewer{$viewer_name} ) );
    my $page = $reader{threads}->thread_page(
        {
            thread_id => $thread{$thread_name},
            viewer    => $viewer{$viewer_name}
        }
    );
    is_deeply(
        $found,
        $page->{ok} ? _columns( $page->{thread} ) : undef,
        "$thread_name as $viewer_name: the same thread"
    );

    return;
}

# Every page of the thread, following its cursor: the snapshot's page is
# the page read in parts, and its posts are the resultset's.
sub _same_pages ( $thread_name, $viewer_name, $limit ) {
    my $after;
    my $pages = 0;
    while (1) {
        my $label = "$thread_name as $viewer_name, $limit a page, page $pages";
        my $page  = _page( $thread_name, $viewer_name, $limit, $after );
        is_deeply(
            $page,
            _in_parts( $thread_name, $viewer_name, $limit, $after ),
            "$label: the snapshot is the page read in parts"
        ) or last;
        if ( $page->{ok} // 1 ) {
            is_deeply(
                $page->{posts},
                _resultset_posts( $thread_name, $viewer_name, $limit, $after ),
                "$label: the posts are the resultset's"
            );
        }
        last if !$page->{next_cursor};
        $after = $page->{next_cursor};
        $pages++;
    }

    return;
}

sub _seek_pages {

    # Ordinal and post-id navigation reuse the same permission-scoped keyset.
    my $name = 'snapshot';
    {
        for my $standing (qw(anonymous member moderator)) {
            my $reader = $reader{threads};
            my $all    = $reader->thread_page(
                {
                    thread_id => $thread{long},
                    viewer    => $viewer{$standing},
                    limit     => 100
                }
            );
            my @expected =
              grep { $_->get_column('position') >= $SEEK_POSITION }
              @{ $all->{posts}{items} };
            my $jump = $reader->thread_page(
                {
                    thread_id => $thread{long},
                    viewer    => $viewer{$standing},
                    at        => $SEEK_POSITION,
                    limit     => 100
                }
            );
            is_deeply(
                [
                    map { $_->get_column('post_id') } @{ $jump->{posts}{items} }
                ],
                [ map { $_->get_column('post_id') } @expected ],
                "$name/$standing seeks without exposing skipped private posts"
            );
            if (@expected) {
                my $target = $expected[0]->get_column('post_id');
                my $linked = $reader->thread_page(
                    {
                        thread_id => $thread{long},
                        viewer    => $viewer{$standing},
                        post      => $target
                    }
                );
                is( $linked->{posts}{items}[0]->get_column('post_id'),
                    $target, "$name/$standing opens a deep post link" );
            }
        }
        my $hidden_id = $dbh->selectrow_array(
q{SELECT post_id FROM posts WHERE thread_id = ? AND moderation_state = 'hidden' LIMIT 1},
            undef, $thread{long}
        );
        is(
            $reader{threads}->thread_page(
                {
                    thread_id => $thread{long},
                    viewer    => $viewer{anonymous},
                    post      => $hidden_id
                }
            )->{ok},
            0,
            "$name: a hidden post link is not found"
        );
        is(
            $reader{threads}->thread_page(
                {
                    thread_id => $thread{private},
                    viewer    => $viewer{anonymous},
                    at        => $SEEK_POSITION
                }
            )->{ok},
            0,
            "$name: ordinal navigation does not open a private thread"
        );
    }

    return;
}

sub _readers {
    my $posts = GPForum::Service::Forum::PostReader->new( schema => $schema );

    return {
        posts   => $posts,
        threads => GPForum::Service::Forum::ThreadDetailReader->new(
            post_reader => $posts,
            schema      => $schema,
        ),
    };
}

# The page as the snapshot reads it.
sub _page ( $thread_name, $viewer_name, $limit, $after ) {
    my $viewer = $viewer{$viewer_name};
    my $page   = await_result(
        $reader{threads}->thread_page_p(
            {
                after     => $after,
                limit     => $limit,
                thread_id => $thread{$thread_name},
                viewer    => $viewer,
            }
        )
    );
    return { ok => 0, error => $page->{error} } if !$page->{ok};

    return {
        has_next    => $page->{posts}{has_next},
        next_cursor => $page->{posts}{next_cursor},
        posts       => [ map { _columns($_) } @{ $page->{posts}{items} } ],
        thread      => _columns( $page->{thread} ),
    };
}

# The same page read in parts: the head, then the posts as its scope reads
# them.
sub _in_parts ( $thread_name, $viewer_name, $limit, $after ) {
    my $viewer = $viewer{$viewer_name};
    my $head =
      $reader{threads}->find_thread( $thread{$thread_name}, $viewer );
    return { ok => 0, error => 'not_found' } if !$head;
    my $posts =
      $reader{posts}
      ->list_thread_posts( _posts_request( $head, $viewer, $limit, $after ) );

    return {
        has_next    => $posts->{has_next},
        next_cursor => $posts->{next_cursor},
        posts       => [ map { _columns($_) } @{ $posts->{items} } ],
        thread      => _columns($head),
    };
}

# The page's posts from the resultset, which reads one row more.
sub _resultset_posts ( $thread_name, $viewer_name, $limit, $after ) {
    my $viewer = $viewer{$viewer_name};
    my $head =
      $reader{threads}->find_thread( $thread{$thread_name}, $viewer );
    my @rows = rows_in(
        $reader{posts}->thread_posts_resultset(
            _posts_request( $head, $viewer, $limit, $after )
        )
    );
    splice @rows, $limit;

    return [ map { _columns($_) } @rows ];
}

sub _posts_request ( $head, $viewer, $limit, $after ) {
    return {
        after          => $after,
        limit          => $limit,
        thread_id      => $head->get_column('thread_id'),
        viewer_scope   => $reader{threads}->post_scope( $viewer, $head ),
        viewer_user_id => $viewer->user_id,
    };
}

sub _shapes_of ($standing) {
    return map { ( "$standing:$_:first", "$standing:$_:after" ) } qw(any own);
}

sub _shape ($values) {
    return join q{:}, $values->{standing},
      ( defined $values->{viewer_user_id} ? 'own'   : 'any' ),
      ( defined $values->{after_post_id}  ? 'after' : 'first' );
}

# The function's rows also name the author's picture (ADR 0144), which the
# resultset does not read: the rest must match column for column.
sub _columns ($row) {
    return undef if !$row;

    my %columns = $row->get_columns;
    delete $columns{author_avatar_id};

    return \%columns;
}

# The long thread gets sixty more posts by three authors, at every
# visibility, some hidden, some deleted, some without a body; the other
# threads take every state a thread page tells apart.
sub _fixture {
    $dbh->do(
        $POSTS_SQL,    undef,
        $thread{long}, @authors,
        $HIDE_EVERY,   $DELETE_EVERY,
        $DELETE_EVERY, @authors,
        $FIRST_ADDED,  $FIRST_ADDED + $ADDED_POSTS - 1
    );
    $dbh->do( $BODIES_SQL, undef, $thread{long}, $NO_BODY_EVERY );
    $dbh->do(
        q{UPDATE posts SET visibility = 'private', author_user_id = ?}
          . q{ WHERE thread_id = ? AND position > 1},
        undef, $user{member}, $thread{private}
    );
    my %state = (
        deleted    => q{deleted_at = now(), deleted_by = author_user_id},
        hidden     => q{moderation_state = 'hidden'},
        locked     => q{moderation_state = 'locked', locked_at = now()},
        long       => q{visibility = 'public'},
        members    => q{visibility = 'members'},
        private    => q{visibility = 'private'},
        restricted => q{visibility = 'public'},
    );
    for my $name ( sort keys %state ) {
        my $author = $name eq 'private' ? $user{member} : $user{author};
        $dbh->do(
            "UPDATE threads SET $state{$name}, author_user_id = ?"
              . ' WHERE thread_id = ?',
            undef, $author, $thread{$name}
        );
    }
    $dbh->do(
        q{UPDATE categories SET visibility = 'private' WHERE category_id = ?},
        undef, seed_id( category => $PRIVATE_CATEGORY ) );
    $dbh->do('ANALYZE');

    return;
}

1;
