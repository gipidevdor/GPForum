# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Service::Forum::ReadState;
use GPForum::Service::Forum::ReadWorkflow;
use GPForum::Infrastructure::ResultRow;
use GPForum::Test::AnsweringFunctions;
use GPForum::Test::CommandIdempotency;
use GPForum::Test::FixedClock;

our $VERSION = '0.001';

# What the read state makes of a member's marker: where a page's unread
# posts begin, and what a mark is refused with. The marker itself moves
# only forward in api.forum_read_marker_command
# (postgres-sql-function-thread-actions.t); the command's call is
# t/652-thread-action-commands.t's.

const my $LAST_VISIBLE_INDEX => 4;
const my $FIRST_POSITION     => 1;
const my $SECOND_POSITION    => 2;
const my $NO_POSITION        => 0;
const my $UNREAD_POSTS       => 2;
const my $ONE_UNREAD_POST    => 1;

my $posts = [
    { post_id => 'post-1', position => $FIRST_POSITION },
    { post_id => 'post-2', position => $SECOND_POSITION },
];

subtest 'a reader without a marker' => sub {
    my $read_state = _read_state(undef);
    my $anonymous  = $read_state->summary_for_page( undef, 'thread-1', $posts );
    is( $anonymous->{authenticated},
        0, 'anonymous reading summary is explicit' );
    is( $anonymous->{last_visible_position},
        $SECOND_POSITION, 'anonymous summary tracks last visible position' );

    my $initial = $read_state->state_for_thread( 'user-1', 'thread-1' );
    is( $initial->{last_read_position},
        $NO_POSITION, 'missing read state starts at zero' );

    my $summary = $read_state->summary_for_page( 'user-1', 'thread-1', $posts );
    is( $summary->{authenticated},  1, 'user reading summary is explicit' );
    is( $summary->{unread_in_page}, $UNREAD_POSTS,  'all posts are unread' );
    is( $summary->{first_unread_post_id}, 'post-1', 'first unread is named' );
    is( $summary->{first_unread_anchor},
        'post-post-1', 'first unread anchor is stable' );
    is( $summary->{last_visible_position},
        $SECOND_POSITION, 'summary exposes last visible position' );
};

subtest 'a reader with a marker' => sub {
    my $read_state = _read_state($FIRST_POSITION);
    my $summary = $read_state->summary_for_page( 'user-1', 'thread-1', $posts );
    is( $summary->{unread_in_page},
        $ONE_UNREAD_POST, 'summary reflects stored read position' );
    is( $summary->{first_unread_post_id},
        'post-2', 'summary jumps to next unread post' );
    is( $summary->{last_read_at}, 'recorded', 'with the marker\'s time' );
};

subtest 'no state is asked for without both ids' => sub {
    my $functions  = GPForum::Test::AnsweringFunctions->new;
    my $read_state = GPForum::Service::Forum::ReadState->new(
        functions => $functions,
        schema    => {}
    );
    $read_state->state_for_thread( undef,    'thread-1' );
    $read_state->state_for_thread( 'user-1', q{} );
    is( scalar @{ $functions->calls }, 0, 'the database is not asked' );
};

subtest
  'page summaries preserve ordering, empty values and row representations' =>
  sub {
    my @fields = qw(authenticated first_unread_anchor first_unread_position
      first_unread_post_id last_visible_position unread_in_page);
    my @cases = (
        {
            name     => 'empty page',
            marker   => 1,
            posts    => [],
            expected => [ 1, undef, 0, undef, 0, 0 ],
        },
        {
            name     => 'all read',
            marker   => 2,
            posts    => [ reverse @{$posts} ],
            expected => [ 1, undef, 0, undef, 2, 0 ],
        },
        {
            name     => 'mixed',
            marker   => 1,
            posts    => [ reverse @{$posts} ],
            expected => [ 1, 'post-post-2', 2, 'post-2', 2, 1 ],
        },
        {
            name     => 'first in page order',
            marker   => 0,
            posts    => [ reverse @{$posts} ],
            expected => [ 1, 'post-post-2', 2, 'post-2', 2, 2 ],
        },
        {
            name     => 'an unread row without an id',
            marker   => 0,
            posts    => [ { position => 2 }, $posts->[0] ],
            expected => [ 1, undef, 2, undef, 2, 2 ],
        },
        {
            name     => 'an absent row',
            marker   => 0,
            posts    => [ undef, $posts->[0] ],
            expected => [ 1,     'post-post-1', 1, 'post-1', 1, 1 ],
        },
    );
    for my $case (@cases) {
        my $reader = _read_state( $case->{marker} );
        for my $objects ( 0, 1 ) {
            my $page = [
                map {
                    !defined $_ ? undef
                      : $objects
                      ? GPForum::Infrastructure::ResultRow->from( { %{$_} } )
                      : { %{$_} }
                } @{ $case->{posts} }
            ];
            my $result = $reader->summary_for_page( 'reader', 'thread', $page );
            is_deeply( [ @{$result}{@fields} ],
                $case->{expected}, "$case->{name}, objects=$objects" );
            my $guest = $reader->summary_for_page( undef, 'thread', $page );
            is_deeply(
                [ @{$guest}{@fields} ],
                [
                    0, undef, undef, undef,
                    $case->{expected}[$LAST_VISIBLE_INDEX], 0
                ],
                "anonymous $case->{name}, objects=$objects"
            );
        }
    }
  };

subtest 'what a mark is refused with, and the row it marks with' => sub {
    my $read_state = _read_state(undef);
    my $invalid    = $read_state->invalid_mark(
        {
            user_id            => 'user-1',
            thread_id          => q{},
            last_read_position => 'bad',
        }
    );
    is( $invalid->{status}, 'invalid', 'a bad request is refused' );
    is_deeply(
        [ sort keys %{ $invalid->{errors} } ],
        [qw(last_read_position thread_id)],
        'naming each field'
    );
    is(
        $read_state->invalid_mark(
            {
                user_id            => 'user-1',
                thread_id          => 'thread-1',
                last_read_position => $NO_POSITION,
            }
        ),
        undef,
        'a sound one is not'
    );
    is( $read_state->mark_row( { thread_id => 'thread-1' } )->{last_read_at},
        '2026-05-23T12:00:00Z', 'the row carries the clock\'s time' );
};

subtest 'a mark without a command id is refused before the call' => sub {
    my $functions = GPForum::Test::AnsweringFunctions->new;
    my $workflow  = GPForum::Service::Forum::ReadWorkflow->new(
        command_idempotency => GPForum::Test::CommandIdempotency->new,
        read_state          => GPForum::Service::Forum::ReadState->new(
            functions => $functions,
            schema    => {}
        ),
    );
    my $missing = $workflow->mark_thread_read(
        {
            last_read_position => $FIRST_POSITION,
            thread_id          => 'thread-1',
            user_id            => 'user-1',
        }
    );
    is( $missing->{status}, 'invalid', 'a missing command_id is refused' );
    is( $missing->{errors}{command_id}, 'command_id is required', 'and named' );
    is( scalar @{ $functions->calls },  0, 'without a call' );
};

done_testing();

# A read state whose marker, if any, is at $position.
sub _read_state ($position) {
    return GPForum::Service::Forum::ReadState->new(
        clock     => GPForum::Test::FixedClock->new,
        functions => GPForum::Test::AnsweringFunctions->new(
            answers => {
                forum_read_state => sub ($values) {
                    return [] if !defined $position;
                    return [
                        +{
                            %{$values},
                            last_read_position => $position,
                            last_read_at       => 'recorded',
                        }
                    ];
                },
            }
        ),
        schema => {},
    );
}

1;
