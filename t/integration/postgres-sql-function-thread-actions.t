# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use JSON::MaybeXS;
use POSIX qw(strftime);
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Benchmark::SeedDataset qw(seed_id);
use GPForum::Service::Community::BookmarkStore;
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

# ADR 0126, section 10: the three thread actions as one call each
# (migration 104) against the Perl path that kept the command log around
# the store's function. On two databases seeded alike, with the ids and the
# clock scripted, each command's answer and every row it writes -- the read
# state and its delta, the bookmark, the subscription, the command log row
# with its response and hash -- are the same on both paths: the first run,
# its replay, a conflict under the same command id, a mark that does not
# advance, and a request the store refuses.

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all =>
      'set GPFORUM_TEST_DSN for thread-action differential tests';
}

my $now  = strftime( '%Y-%m-%dT%H:%M:%SZ', gmtime );
my $json = JSON::MaybeXS->new( canonical => 1 );
my %pair =
  map { $_ => GPForum::Test::PgDatabase->fresh( seed => 1 ) } qw(function perl);
my $user   = seed_id( user   => 2 );
my $thread = seed_id( thread => 1 );
my $serial = 0;

my %mark = ( thread_id => $thread, user_id => $user );
same_mark( { %mark, command_id => 'actions-read', last_read_position => 3 } );
same_mark( { %mark, command_id => 'actions-read', last_read_position => 3 },
    'ok', 'replayed' );
same_mark( { %mark, command_id => 'actions-read', last_read_position => 5 },
    'conflict', 'another request under the same command id' );
same_mark(
    { %mark, command_id => 'actions-read-behind', last_read_position => 2 },
    'ok', 'a mark behind the stored one' );
same_mark(
    {
        %mark,
        command_id         => 'actions-read-malformed',
        last_read_position => 'three'
    },
    'invalid',
    'a position that is not a number'
);

my %target =
  ( target_id => $thread, target_type => 'thread', user_id => $user );
same_community( 'save_bookmark',
    { %target, command_id => 'actions-bookmark', note => 'kept' } );
same_community( 'save_bookmark',
    { %target, command_id => 'actions-bookmark', note => 'kept' },
    'ok', 'replayed' );
same_community( 'save_bookmark',
    { %target, command_id => 'actions-bookmark-again', note => 'kept again' },
    'ok', 'the bookmark restored with another note' );
same_community( 'save_subscription',
    { %target, command_id => 'actions-subscribe', preference => 'all' } );
same_community( 'save_subscription',
    { %target, command_id => 'actions-subscribe', preference => 'all' },
    'ok', 'replayed' );
same_community(
    'save_subscription',
    { %target, command_id => 'actions-subscribe', preference => 'mentions' },
    'conflict',
    'another preference under the same command id'
);
same_community(
    'save_subscription',
    {
        %target,
        command_id => 'actions-subscribe-again',
        preference => 'mentions'
    },
    'ok',
    'the subscription kept with another preference'
);

done_testing();

sub same_mark ( $input, $expected = 'ok', $label = 'first run' ) {
    ++$serial;
    my %result;
    for my $path (qw(function perl)) {
        my $workflow = read_workflow($path);
        $result{$path} = $workflow->mark_thread_read( { %{$input} } );
        if ( ( $result{$path}{status} // q{} ) eq 'failed' ) {
            diag explain $workflow->logger->lines;
        }
    }
    _same( 'read marker', $label, $expected, \%result,
        [qw(thread_read_state user_read_marker_deltas command_log)] );
    return;
}

sub same_community ( $method, $input, $expected = 'ok', $label = 'first run' ) {
    ++$serial;
    my %result;
    for my $path (qw(function perl)) {
        my $workflow = community_workflow($path);
        $result{$path} = $workflow->$method( { %{$input} } );
        if ( ( $result{$path}{status} // q{} ) eq 'failed' ) {
            diag explain $workflow->logger->lines;
        }
    }
    _same( $method, $label, $expected, \%result,
        [qw(bookmarks subscriptions command_log)] );
    return;
}

sub _same ( $what, $label, $expected, $result, $tables ) {
    is_deeply( $result->{function}, $result->{perl},
        "$serial $what, $label: the answer is the Perl path's" );
    is( $result->{function}{status},
        $expected, "$serial $what, $label: $expected" );
    for my $table ( @{$tables} ) {
        is_deeply(
            snapshot( $pair{function}->dbh, $table ),
            snapshot( $pair{perl}->dbh,     $table ),
            "$serial $what, $label: same $table"
        );
    }
    return;
}

sub read_workflow ($path) {
    my ( $schema, $old, $ids, $clock ) = scripted($path);
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

sub community_workflow ($path) {
    my ( $schema, $old, $ids, $clock ) = scripted($path);
    my %store = ( clock => $clock, id_service => $ids, schema => $schema );
    return GPForum::Service::Community::Workflow->new(
        bookmark_store =>
          GPForum::Service::Community::BookmarkStore->new( %store, %{$old} ),
        command_idempotency => command_log( $schema, $old, $ids, $clock ),
        logger              => GPForum::Test::LogLines->new,
        report_store        =>
          GPForum::Service::Moderation::ReportStore->new( %store, %{$old} ),
        subscription_store =>
          GPForum::Service::Notification::SubscriptionStore->new(
            %store, %{$old}
          ),
    );
}

# The same ids and the same time on both paths, so the rows can be compared.
sub scripted ($path) {
    my $old = $path eq 'perl' ? { functions => undef } : {};
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

sub snapshot ( $dbh, $table ) {
    my $rows =
      $dbh->selectall_arrayref( "SELECT * FROM $table", { Slice => {} } );
    for my $row ( @{$rows} ) {
        for my $column (qw(payload)) {
            if ( defined $row->{$column} ) {
                $row->{$column} = $json->decode( $row->{$column} );
            }
        }
    }
    return [ sort { $json->encode($a) cmp $json->encode($b) } @{$rows} ];
}

1;
