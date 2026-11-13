# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;

use POSIX qw(strftime);
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Benchmark::SeedDataset qw(seed_id);
use GPForum::Service::Community::BookmarkStore;
use GPForum::Service::Community::LikeStore;
use GPForum::Service::Moderation::ReportStore;
use GPForum::Service::Community::Workflow;
use GPForum::Service::Forum::ReadState;
use GPForum::Service::Forum::ReadWorkflow;
use GPForum::Service::Notification::SubscriptionStore;
use GPForum::Service::Operations::CommandIdempotency;
use GPForum::Test::FixedClock;
use GPForum::Test::LogLines;
use GPForum::Test::PgDatabase;
use GPForum::Test::SequenceId;

our $VERSION = '0.001';

# How far past the seed's marker the marks are taken, and the commands the
# read marks log: the first, the one behind it and the refused one.
const my $MARKS_AHEAD     => 3;
const my $COMMANDS_LOGGED => 3;

# ADR 0126, section 10: the three thread actions as one call each, each
# with one path (ADR 0177) and its answers and rows stated. The read
# marker: the first mark, its replay, a conflict under the same command id,
# a mark behind the stored one, which never regresses it, and a request the
# store refuses. The bookmark and the subscription: the first run, its
# replay, a conflict, and a second command that restores the one row.

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all =>
      'set GPFORUM_TEST_DSN for thread-action differential tests';
}

my $now = strftime( '%Y-%m-%dT%H:%M:%SZ', gmtime );
my %pair =
  map { $_ => GPForum::Test::PgDatabase->fresh( seed => 1 ) } qw(function);
my $user   = seed_id( user   => 2 );
my $thread = seed_id( thread => 1 );
my $serial = 0;

# The seed may have marked the thread already: the marks are taken past it.
my %mark  = ( thread_id => $thread, user_id => $user );
my $ahead = ( stored()->[0] // 0 ) + $MARKS_AHEAD;
my $first =
  mark( { %mark, command_id => 'actions-read', last_read_position => $ahead } );
is( $first->{status},                         'ok', 'a first mark is ok' );
is( $first->{advanced},                       1,    'and advances the marker' );
is( $first->{read_state}{last_read_position}, $ahead, 'to its position' );
is_deeply( stored(), [ $ahead, $ahead ], 'the marker and its delta hold it' );
is( commands(), 1, 'with its command logged' );

is_deeply(
    mark(
        { %mark, command_id => 'actions-read', last_read_position => $ahead }
    ),
    $first,
    'the same command again answers what it answered'
);
is( commands(), 1, 'and logs nothing more' );

my $conflict =
  mark(
    { %mark, command_id => 'actions-read', last_read_position => $ahead + 2 } );
is( $conflict->{status}, 'conflict',
    'another request under the same command id is a conflict' );
is_deeply( stored(), [ $ahead, $ahead ], 'which marks nothing' );

my $behind = mark(
    {
        %mark,
        command_id         => 'actions-read-behind',
        last_read_position => $ahead - 1
    }
);
is( $behind->{status},   'ok', 'a mark behind the stored one is ok' );
is( $behind->{advanced}, 0,    'and does not advance' );
is_deeply( stored(), [ $ahead, $ahead ], 'the marker never regresses' );

my $malformed = mark(
    {
        %mark,
        command_id         => 'actions-read-malformed',
        last_read_position => 'three'
    }
);
is( $malformed->{status}, 'invalid', 'a position that is not a number' );
ok( $malformed->{errors}{last_read_position}, 'is refused on its field' );
is( commands(), $COMMANDS_LOGGED,
    'each command is logged once, the refused one too' );

my %target =
  ( target_id => $thread, target_type => 'thread', user_id => $user );
my $bookmarked = community( 'save_bookmark',
    { %target, command_id => 'actions-bookmark', note => 'kept' } );
is_deeply(
    community(
        'save_bookmark',
        { %target, command_id => 'actions-bookmark', note => 'kept' }
    ),
    $bookmarked,
    'the same bookmark command again answers what it answered'
);
community( 'save_bookmark',
    { %target, command_id => 'actions-bookmark-again', note => 'kept again' } );
is_deeply(
    rows( 'bookmarks', qw(note deleted_at) ),
    [ { note => 'kept again', deleted_at => undef } ],
    'the bookmark is restored with another note, one row'
);

my $subscribed = community( 'save_subscription',
    { %target, command_id => 'actions-subscribe', preference => 'all' } );
is_deeply(
    community(
        'save_subscription',
        { %target, command_id => 'actions-subscribe', preference => 'all' }
    ),
    $subscribed,
    'the same subscription command again answers what it answered'
);
community( 'save_subscription',
    { %target, command_id => 'actions-subscribe', preference => 'mentions' },
    'conflict' );
community(
    'save_subscription',
    {
        %target,
        command_id => 'actions-subscribe-again',
        preference => 'mentions'
    }
);
is_deeply(
    rows( 'subscriptions', qw(preference revoked_at) ),
    [ { preference => 'mentions', revoked_at => undef } ],
    'the subscription is kept with another preference, one row'
);

done_testing();

sub mark ($input) {
    ++$serial;
    my $workflow = read_workflow();
    my $result   = $workflow->mark_thread_read( { %{$input} } );
    if ( ( $result->{status} // q{} ) eq 'failed' ) {
        diag explain $workflow->logger->lines;
    }
    return $result;
}

# The stored marker's position and its delta's.
sub stored {
    my $dbh = $pair{function}->dbh;
    return [
        map {
            scalar $dbh->selectrow_array(
"SELECT last_read_position FROM $_ WHERE user_id = ? AND thread_id = ?",
                undef, $user, $thread
            )
        } qw(thread_read_state user_read_marker_deltas)
    ];
}

sub commands {
    return
      scalar $pair{function}->dbh->selectrow_array(
        q{SELECT count(*) FROM command_log WHERE command_type = ?},
        undef, 'forum.read_marker' );
}

sub community ( $method, $input, $expected = 'ok' ) {
    ++$serial;
    my $workflow = community_workflow();
    my $result   = $workflow->$method( { %{$input} } );
    if ( ( $result->{status} // q{} ) eq 'failed' ) {
        diag explain $workflow->logger->lines;
    }
    is( $result->{status}, $expected, "$serial $method: $expected" );
    return $result;
}

# The member's rows of a table on the thread, with the columns named.
sub rows ( $table, @columns ) {
    my $list = join q{, }, @columns;
    return $pair{function}->dbh->selectall_arrayref(
"SELECT $list FROM $table WHERE user_id = ? AND target_type = 'thread' AND target_id = ?",
        { Slice => {} }, $user, $thread
    );
}

sub read_workflow {
    my ( $schema, $old, $ids, $clock ) = scripted('function');
    return GPForum::Service::Forum::ReadWorkflow->new(
        command_idempotency => command_log( $schema, $old, $ids, $clock ),
        logger              => GPForum::Test::LogLines->new,
        read_state          => GPForum::Service::Forum::ReadState->new(
            clock  => $clock,
            schema => $schema,
            %{$old}
        ),
    );
}

sub community_workflow {
    my ( $schema, $old, $ids, $clock ) = scripted('function');
    my %store = ( clock => $clock, id_service => $ids, schema => $schema );
    return GPForum::Service::Community::Workflow->new(
        bookmark_store =>
          GPForum::Service::Community::BookmarkStore->new( %store, %{$old} ),
        command_idempotency => command_log( $schema, $old, $ids, $clock ),
        like_store          =>
          GPForum::Service::Community::LikeStore->new( %store, %{$old} ),
        logger       => GPForum::Test::LogLines->new,
        report_store =>
          GPForum::Service::Moderation::ReportStore->new( %store, %{$old} ),
        subscription_store =>
          GPForum::Service::Notification::SubscriptionStore->new(
            %store, %{$old}
          ),
    );
}

# The same ids and the same time on both paths, so the rows can be compared.
sub scripted ($path) {
    my $old = {};
    my $ids = GPForum::Test::SequenceId->new(
        prefix => ( sprintf '018f%04x-0000-7000-8000', $serial ) );
    my $clock = GPForum::Test::FixedClock->new( iso8601 => $now );
    return ( $pair{$path}->schema, $old, $ids, $clock );
}

sub command_log ( $schema, $old, $ids, $clock ) {
    return GPForum::Service::Operations::CommandIdempotency->new(
        clock      => $clock,
        id_service => $ids,
        schema     => $schema,
        %{$old}
    );
}

1;
