# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;
use Const::Fast;
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Infrastructure::Id;
use GPForum::Service::Community::BookmarkStore;
use GPForum::Service::Community::FeedReader;
use GPForum::Service::Community::MentionReader;
use GPForum::Service::Community::ReputationLedger;
use GPForum::Service::Forum::ReadState;
use GPForum::Test::PostgresHarness;
use GPForum::Service::Forum::Readability;
use GPForum::Service::Forum::Viewer;
use GPForum::Test::PgDatabase;

our $VERSION = '0.001';

const my $FIXTURE_ROWS      => 12;
const my $PAGE_SIZE         => 3;
const my $PAGE_GUARD        => 20;
const my $CREATED_AT        => '2026-10-01T12:00:00Z';
const my @CREDIT_DELTAS     => ( 7, 11 );
const my $CREDIT_WAVES      => 2;
const my $CREDIT_SUM        => 18;
const my @READ_POSITIONS    => ( 5, 9 );
const my $MAX_READ_POSITION => 9;

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all =>
      'set GPFORUM_TEST_DSN to compare community source functions';
}

my $database = GPForum::Test::PgDatabase->fresh( seed => 1 );
my $schema   = $database->schema;
my $dbh      = $database->dbh;
my $ids      = GPForum::Infrastructure::Id->new;
my ( $user, $actor ) =
  @{ $dbh->selectcol_arrayref('SELECT id FROM users ORDER BY id LIMIT 2') };
my $sources = $dbh->selectall_arrayref(
'SELECT p.post_id, p.thread_id, t.category_id, c.space_id FROM posts p JOIN threads t USING (thread_id) JOIN categories c USING (category_id) ORDER BY p.post_id LIMIT ?',
    { Slice => {} },
    $FIXTURE_ROWS
);
my $category = $sources->[0]{category_id};
my $space    = $sources->[0]{space_id};

for my $source ( @{$sources} ) {
    $dbh->do(
q{INSERT INTO bookmarks (bookmark_id, user_id, target_type, target_id, note, created_at) VALUES (?, ?, 'post', ?, 'read later', ?)},
        undef, $ids->uuid, $user, $source->{post_id}, $CREATED_AT
    );
    $dbh->do(
q{INSERT INTO mentions (mention_id, source_type, source_id, actor_id, mentioned_user_id, mentioned_username, created_at) VALUES (?, 'post', ?, ?, ?, 'member', ?)},
        undef, $ids->uuid, $source->{post_id}, $actor, $user, $CREATED_AT
    );
    $dbh->do(
q{INSERT INTO user_feed_items (user_id, item_type, item_id, created_at, visibility_version, permission_version) VALUES (?, 'post', ?, ?, 1, 1)},
        undef, $user, $source->{post_id}, $CREATED_AT
    );
}

my $readability =
  GPForum::Service::Forum::Readability->new( schema => $schema );
my %viewer = (
    anonymous => GPForum::Service::Forum::Viewer->anonymous,
    member    =>
      GPForum::Service::Forum::Viewer->new( member => 1, user_id => $user ),
    suspended => GPForum::Service::Forum::Viewer->new( user_id => $user ),
    grant     => GPForum::Service::Forum::Viewer->new(
        member       => 1,
        user_id      => $user,
        category_ids => [$category]
    ),
    grant_without_member =>
      GPForum::Service::Forum::Viewer->new( category_ids => [$category] ),
    global => GPForum::Service::Forum::Viewer->new(
        member      => 1,
        global_read => 1,
        user_id     => $user
    ),
    global_without_member =>
      GPForum::Service::Forum::Viewer->new( global_read => 1 ),
    space_grant => GPForum::Service::Forum::Viewer->new(
        member    => 1,
        user_id   => $user,
        space_ids => [$space]
    ),
);
my %classes = (
    bookmarks =>
      [ 'GPForum::Service::Community::BookmarkStore', 'list_page_for_user' ],
    feed => [ 'GPForum::Service::Community::FeedReader', 'list_page_for_user' ],
    mentions => [
        'GPForum::Service::Community::MentionReader',
        'list_page_for_recipient'
    ],
);

for my $kind ( sort keys %classes ) {
    my ( $class, $method ) = @{ $classes{$kind} };
    my $new = $class->new( schema => $schema, readability => $readability );
    my $old = $class->new(
        schema      => $schema,
        readability => $readability,
        functions   => undef
    );
    for my $level (qw(public members private)) {
        $dbh->do( 'UPDATE categories SET visibility = ? WHERE category_id = ?',
            undef, $level, $category );
        for my $name ( sort keys %viewer ) {
            _pages( $new, $old, $method,
                { limit => $PAGE_SIZE, viewer => $viewer{$name} },
                "$kind/$level/$name" );
        }
    }
    my $plain        = $class->new( schema => $schema );
    my $legacy_plain = $class->new( schema => $schema, functions => undef );
    _pages( $plain, $legacy_plain, $method, { limit => $PAGE_SIZE },
        "$kind/unfiltered" );
    _pages(
        $plain, $legacy_plain, $method,
        { limit => $PAGE_SIZE, viewer => $user },
        "$kind/unfiltered ignores reader id"
    );
}

$dbh->do( q{UPDATE posts SET moderation_state = 'hidden' WHERE post_id = ?},
    undef, $sources->[0]{post_id} );
for my $kind ( sort keys %classes ) {
    my ( $class, $method ) = @{ $classes{$kind} };
    _pages(
        $class->new( schema => $schema, readability => $readability ),
        $class->new(
            schema      => $schema,
            readability => $readability,
            functions   => undef
        ),
        $method,
        { limit => $PAGE_SIZE, viewer => $viewer{global} },
        "$kind/hidden source"
    );
}

_reputation_credit_races();
_read_marker_race();

done_testing();

# Both first-snapshot insertion and later row updates see simultaneous
# writers with distinct event sources. The final score must include both.
sub _reputation_credit_races {
    $dbh->do( 'DELETE FROM reputation_events WHERE user_id = ?', undef, $user );
    $dbh->do( 'DELETE FROM trust_score_snapshots WHERE user_id = ?',
        undef, $user );
    local $ENV{GPFORUM_DATABASE_DSN} = $database->dsn;
    for my $wave ( 1 .. $CREDIT_WAVES ) {
        my @source_ids = map { $ids->uuid } @CREDIT_DELTAS;
        my @outcomes   = GPForum::Test::PostgresHarness::race(
            sub ($slot) {
                return GPForum::Service::Community::ReputationLedger->new(
                    schema => GPForum::Test::PostgresHarness::connect_schema() )
                  ->record_event(
                    {
                        actor_id    => $actor,
                        user_id     => $user,
                        source_type => 'post',
                        source_id   => $source_ids[$slot],
                        delta       => $CREDIT_DELTAS[$slot],
                        reason      => 'concurrent credit',
                    }
                  );
            }
        );
        for my $index ( 0 .. $#outcomes ) {
            ok(
                $outcomes[$index]{ok} && $outcomes[$index]{result}{ok},
                "credit wave $wave worker $index succeeded"
            ) or diag $outcomes[$index]{error};
        }
        my ($score) = $dbh->selectrow_array(
            'SELECT score FROM trust_score_snapshots WHERE user_id = ?',
            undef, $user );
        is( $score, $wave * $CREDIT_SUM,
            "credit wave $wave keeps both deltas" );
        my ($events) = $dbh->selectrow_array(
            'SELECT count(*) FROM reputation_events WHERE user_id = ?',
            undef, $user );
        is(
            $events,
            $wave * GPForum::Test::PostgresHarness::worker_count(),
            'every credited source has exactly one event'
        );
    }
    return;
}

sub _read_marker_race {
    my $thread = $sources->[0]{thread_id};
    $dbh->do(
        'DELETE FROM thread_read_state WHERE user_id = ? AND thread_id = ?',
        undef, $user, $thread );
    $dbh->do(
'DELETE FROM user_read_marker_deltas WHERE user_id = ? AND thread_id = ?',
        undef, $user, $thread
    );
    local $ENV{GPFORUM_DATABASE_DSN} = $database->dsn;
    my @outcomes = GPForum::Test::PostgresHarness::race(
        sub ($slot) {
            return GPForum::Service::Forum::ReadState->new(
                schema => GPForum::Test::PostgresHarness::connect_schema() )
              ->mark_thread_read(
                {
                    user_id            => $user,
                    thread_id          => $thread,
                    last_read_position => $READ_POSITIONS[$slot],
                }
              );
        }
    );
    for my $index ( 0 .. $#outcomes ) {
        ok( $outcomes[$index]{ok} && $outcomes[$index]{result}{ok},
            "read-marker worker $index succeeded" )
          or diag $outcomes[$index]{error};
    }
    my ($state) = $dbh->selectrow_array(
'SELECT last_read_position FROM thread_read_state WHERE user_id = ? AND thread_id = ?',
        undef, $user, $thread
    );
    my ($delta) = $dbh->selectrow_array(
'SELECT last_read_position FROM user_read_marker_deltas WHERE user_id = ? AND thread_id = ?',
        undef, $user, $thread
    );
    is( $state, $MAX_READ_POSITION,
        'parallel read markers keep the highest position' );
    is( $delta, $state,
        'the synchronization delta commits with the highest marker' );
    return;
}

sub _pages ( $new, $old, $method, $options, $label ) {
    for my $page_number ( 1 .. $PAGE_GUARD ) {
        my $expected = $old->$method( $user, $options );
        my $actual   = $new->$method( $user, $options );
        is_deeply( _page($actual), _page($expected),
            "$label page $page_number columns and cursor" );
        return if !$expected->{has_next};
        $options = { %{$options}, after => $expected->{next_cursor} };
    }
    fail("$label exceeded the page guard");
    return;
}

sub _page ($page) {
    return {
        %{$page}, items => [ map { +{ $_->get_columns } } @{ $page->{items} } ]
    };
}

1;
