# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use utf8;
use v5.40;

use Const::Fast;
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Service::Forum::ThreadTags;
use GPForum::Service::Forum::Viewer;
use GPForum::Test::PgDatabase;

our $VERSION = '0.001';

# ADR 0135 against the migrated schema: a thread's tags are set in order,
# replaced as a set, shared by slug across threads; the page reads them in
# one call; the tag page lists the threads a reader may read under a tag,
# in every category or one, and not a hidden thread nor a members-only
# thread for an anonymous reader; the index counts them.

const my $THREADS_SQL => join q{ },
  'SELECT t.thread_id, t.category_id FROM threads t',
  'JOIN categories c ON c.category_id = t.category_id',
  q{WHERE t.deleted_at IS NULL AND t.moderation_state = 'visible'},
  q{AND t.visibility = 'public' AND c.visibility = 'public'},
  'ORDER BY t.thread_id LIMIT 3';
const my $HIDE_SQL =>
  q{UPDATE threads SET moderation_state = 'hidden' WHERE thread_id = ?};
const my $MEMBERS_SQL =>
  q{UPDATE threads SET visibility = 'members' WHERE thread_id = ?};
const my $MEMBER_SQL =>
  q{SELECT id FROM users WHERE status = 'active' ORDER BY id LIMIT 1};
const my $UNKNOWN => '018f1006-0009-7000-8000-000000000009';
const my $THREE   => 3;

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'set GPFORUM_TEST_DSN for the thread tags test';
}

my $database = GPForum::Test::PgDatabase->fresh( seed => 1 );
my $dbh      = $database->dbh;
my $tags =
  GPForum::Service::Forum::ThreadTags->new( schema => $database->schema );

my $threads = $dbh->selectall_arrayref( $THREADS_SQL, { Slice => {} } );
ok( @{$threads} >= $THREE, 'the seed has three public threads' );
my ( $tagged, $shared, $untagged ) = @{$threads};
my ($member_id) = $dbh->selectrow_array($MEMBER_SQL);
my $anonymous = GPForum::Service::Forum::Viewer->anonymous;
my $member =
  GPForum::Service::Forum::Viewer->new( member => 1, user_id => $member_id );

is_deeply(
    $tags->set_thread_tags(
        $tagged->{thread_id}, 'Perl, PostgreSQL, perl, Café, a, b, c'
    ),
    [
        { name => 'Perl',       slug => 'perl' },
        { name => 'PostgreSQL', slug => 'postgresql' },
        { name => 'Café',       slug => 'cafe' },
        { name => 'a',          slug => 'a' },
        { name => 'b',          slug => 'b' },
    ],
    'a thread takes the first five tags its author names, once each'
);
is_deeply(
    $tags->set_thread_tags( $tagged->{thread_id}, 'postgresql, Web dev' ),
    [
        { name => 'PostgreSQL', slug => 'postgresql' },
        { name => 'Web dev',    slug => 'web-dev' },
    ],
    'set again, the tags are replaced and a known slug keeps its first name'
);
is_deeply(
    $tags->set_thread_tags( $shared->{thread_id}, 'PostgreSQL' ),
    [ { name => 'PostgreSQL', slug => 'postgresql' } ],
    'another thread shares the tag by its slug'
);
is_deeply( $tags->set_thread_tags( $UNKNOWN, 'perl' ),
    [], 'a thread that does not exist takes none' );
is_deeply(
    $tags->tags_for_threads(
        [ $tagged->{thread_id}, $shared->{thread_id}, $untagged->{thread_id} ]
    ),
    {
        $tagged->{thread_id} => [
            { name => 'PostgreSQL', slug => 'postgresql' },
            { name => 'Web dev',    slug => 'web-dev' },
        ],
        $shared->{thread_id} =>
          [ { name => 'PostgreSQL', slug => 'postgresql' } ],
    },
'the page reads the tags of its threads, in order, none for a thread without'
);

my @listed = map { $_->get_column('thread_id') } @{
    $tags->list_tagged_threads(
        { slug => 'postgresql', viewer => $anonymous }
    )
};
is_deeply(
    [ sort @listed ],
    [ sort $tagged->{thread_id}, $shared->{thread_id} ],
    'the tag page lists both threads under the tag'
);
is(
    $tags->list_tagged_threads(
        { slug => 'postgresql', viewer => $anonymous }
    )->[0]->get_column('category_title'),
    scalar $dbh->selectrow_array(
        'SELECT title FROM categories WHERE category_id = ?',
        undef,
        $listed[0] eq $tagged->{thread_id}
        ? $tagged->{category_id}
        : $shared->{category_id}
    ),
    'each with its category'
);
my @in_category = map { $_->get_column('thread_id') } @{
    $tags->list_tagged_threads(
        {
            category_id => $shared->{category_id},
            slug        => 'postgresql',
            viewer      => $anonymous
        }
    )
};
my %listed_in_category = map { $_ => 1 } @in_category;
ok( $listed_in_category{ $shared->{thread_id} },
    'filtered by category, the thread of that category is listed' );
ok(
    $tagged->{category_id} eq $shared->{category_id}
      || !$listed_in_category{ $tagged->{thread_id} },
    'and not one of another category'
);
is_deeply(
    $tags->list_tagged_threads( { slug => 'nothing', viewer => $member } ),
    [], 'a tag nothing carries lists nothing' );

my ($count) = map { $_->{thread_count} }
  grep { $_->{slug} eq 'postgresql' }
  @{ $tags->list_tags( { viewer => $anonymous } ) };
is( $count, 2, 'the index counts the threads under the tag' );

$dbh->do( $MEMBERS_SQL, undef, $shared->{thread_id} );
is_deeply(
    [
        map { $_->get_column('thread_id') } @{
            $tags->list_tagged_threads(
                { slug => 'postgresql', viewer => $anonymous }
            )
        }
    ],
    [ $tagged->{thread_id} ],
    'a members-only thread is not listed for an anonymous reader'
);
is(
    scalar @{
        $tags->list_tagged_threads(
            { slug => 'postgresql', viewer => $member }
        )
    },
    2,
    'but is for a member'
);
$dbh->do( $HIDE_SQL, undef, $tagged->{thread_id} );
is_deeply(
    [
        map { $_->get_column('thread_id') } @{
            $tags->list_tagged_threads(
                { slug => 'postgresql', viewer => $member }
            )
        }
    ],
    [ $shared->{thread_id} ],
    'nor a hidden thread for anyone'
);
is(
    scalar(
        grep { $_->{slug} eq 'web-dev' }
          @{ $tags->list_tags( { viewer => $member } ) }
    ),
    0,
    'and a tag only a hidden thread carries is absent from the index'
);

done_testing();

1;
