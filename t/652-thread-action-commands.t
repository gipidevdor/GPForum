# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use JSON::MaybeXS;
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Infrastructure::SqlFunction;
use GPForum::Service::Community::BookmarkStore;
use GPForum::Service::Community::Workflow;
use GPForum::Service::Forum::ReadState;
use GPForum::Service::Forum::ReadWorkflow;
use GPForum::Service::Notification::SubscriptionStore;
use GPForum::Service::Operations::CommandIdempotency;
use GPForum::Test::FixedClock;
use GPForum::Test::LogLines;
use GPForum::Test::SequenceId;
use GPForum::Test::SqlFunctionHandle;

our $VERSION = '0.001';

# A thread action with a call layer and a command log is one call: what the
# call sends (the command log's row, the store's row, a refusal decided
# before the call) and what its outcome answers, on a handle that records
# the call and answers what the test gives.

const my $THREAD       => '018f1004-0001-7000-8000-000000000001';
const my $USER         => '018f1002-0002-7000-8000-000000000002';
const my $NOW          => '2026-10-14T10:00:00Z';
const my $PREFIX       => '018f0009-0000-7000-8000';
const my $POSITION     => 7;
const my $IDS_WITH_ROW => 3;    # the command id, its correlation id, the row id

my $json = JSON::MaybeXS->new( canonical => 1 );

sub fixture ( $rows = [] ) {
    my $handle = GPForum::Test::SqlFunctionHandle->new( rows => $rows );
    my $functions =
      GPForum::Infrastructure::SqlFunction->new( schema => $handle );
    my $ids   = GPForum::Test::SequenceId->new( prefix  => $PREFIX );
    my $clock = GPForum::Test::FixedClock->new( iso8601 => $NOW );
    my $log   = GPForum::Service::Operations::CommandIdempotency->new(
        clock      => $clock,
        functions  => $functions,
        id_service => $ids,
        schema     => $handle,
    );
    return ( $handle, $functions, $ids, $clock, $log );
}

sub expected_ids ($count) {
    my $ids = GPForum::Test::SequenceId->new( prefix => $PREFIX );
    return map { $ids->uuid } 1 .. $count;
}

sub sent ($handle) {
    my ( $log, $answer, $row ) = @{ $handle->executed->[-1] };
    return (
        $json->decode($log),
        defined $answer ? $json->decode($answer) : undef,
        defined $row    ? $json->decode($row)    : undef,
    );
}

subtest 'a read marker is one call' => sub {
    my $response = {
        advanced   => 1,
        ok         => 1,
        read_state => {
            last_read_at       => $NOW,
            last_read_position => $POSITION,
            thread_id          => $THREAD,
            user_id            => $USER,
        },
        status => 'ok',
    };
    my ( $handle, $functions, $ids, $clock, $log ) = fixture(
        [ { outcome => 'recorded', response => $json->encode($response) } ] );
    my $workflow = GPForum::Service::Forum::ReadWorkflow->new(
        command_idempotency => $log,
        logger              => GPForum::Test::LogLines->new,
        read_state          => GPForum::Service::Forum::ReadState->new(
            clock     => $clock,
            functions => $functions,
            schema    => $handle,
        ),
    );
    my $result = $workflow->mark_thread_read(
        {
            command_id         => ' read-1 ',
            last_read_position => $POSITION,
            thread_id          => $THREAD,
            user_id            => $USER,
        }
    );
    is_deeply( $result, $response, 'the answer is the one recorded' );
    is( scalar @{ $handle->executed }, 1, 'in one call' );
    like(
        $handle->prepared->[0],
        qr/api[.]forum_read_marker_command_v2/msx,
        'to the read marker command'
    );
    my ( $sent_log, $answer, $row ) = sent($handle);
    my ( $command_id, $correlation_id ) = expected_ids(2);
    is_deeply(
        $sent_log,
        {
            actor_id               => $USER,
            command_at             => $NOW,
            command_correlation_id => $correlation_id,
            command_id             => $command_id,
            command_type           => 'forum.read_marker',
            idempotency_key        => 'read-1',
            request_hash           =>
              GPForum::Service::Operations::CommandIdempotency->request_hash(
                {
                    last_read_position => $POSITION,
                    thread_id          => $THREAD,
                    user_id            => $USER,
                }
              ),
        },
        'the command log row as CommandIdempotency writes it'
    );
    is( $answer, undef, 'no refusal decided before the call' );
    is_deeply(
        $row,
        {
            last_read_at       => $NOW,
            last_read_position => $POSITION,
            thread_id          => $THREAD,
            user_id            => $USER,
        },
        'the store row the mark function takes'
    );
};

subtest 'a refused mark is recorded without the mark' => sub {
    my $refusal = {
        errors => {
            last_read_position =>
              'last_read_position must be a non-negative integer'
        },
        ok     => 0,
        status => 'invalid',
    };
    my ( $handle, $functions, $ids, $clock, $log ) = fixture(
        [ { outcome => 'recorded', response => $json->encode($refusal) } ] );
    my $workflow = GPForum::Service::Forum::ReadWorkflow->new(
        command_idempotency => $log,
        read_state          => GPForum::Service::Forum::ReadState->new(
            clock     => $clock,
            functions => $functions,
            schema    => $handle,
        ),
    );
    my $result = $workflow->mark_thread_read(
        {
            command_id         => 'read-bad',
            last_read_position => 'seven',
            thread_id          => $THREAD,
            user_id            => $USER,
        }
    );
    is_deeply( $result, $refusal, 'the answer is the refusal' );
    my ( $sent_log, $answer, $row ) = sent($handle);
    is_deeply( $answer, $refusal, 'sent as the answer to record' );
    is( $row, undef, 'with no row to mark' );
};

subtest 'a replay answers the stored response, a conflict its words' => sub {
    my $stored = { advanced => 0, ok => 1, read_state => {}, status => 'ok' };
    for my $case (
        [ replayed => $stored, $stored ],
        [
            conflict => undef,
            'idempotency key was already used for another request'
        ],
        [ in_progress => undef, 'idempotency key is already in progress' ],
      )
    {
        my ( $outcome, $response, $expected ) = @{$case};
        my ( $handle, $functions, $ids, $clock, $log ) = fixture(
            [
                {
                    outcome  => $outcome,
                    response => $response ? $json->encode($response) : undef
                }
            ]
        );
        my $workflow = GPForum::Service::Forum::ReadWorkflow->new(
            command_idempotency => $log,
            read_state          => GPForum::Service::Forum::ReadState->new(
                clock     => $clock,
                functions => $functions,
                schema    => $handle,
            ),
        );
        my $result = $workflow->mark_thread_read(
            {
                command_id         => 'read-again',
                last_read_position => 1,
                thread_id          => $THREAD,
                user_id            => $USER,
            }
        );
        if ( ref $expected ) {
            is_deeply( $result, $expected, "$outcome: the stored response" );
        }
        else {
            is( $result->{status}, 'conflict', "$outcome: a conflict" );
            is( $result->{error},  $expected,  "$outcome: in the log's words" );
            is( $result->{ok},     0,          "$outcome: not ok" );
        }
    }
};

subtest 'a bookmark and a subscription are one call each' => sub {
    for my $case (
        [
            save_bookmark => 'community_bookmark_command',
            'community.bookmark',
            { note => 'kept' },
            { note => 'kept' },
            {
                bookmark_id => undef,
                created_at  => $NOW,
                deleted_at  => undef,
                note        => 'kept',
                target_id   => $THREAD,
                target_type => 'thread',
                user_id     => $USER,
            },
            'bookmark_id',
        ],
        [
            save_subscription => 'community_subscribe_command',
            'community.subscribe',
            {},
            { preference => 'all' },
            {
                created_at      => $NOW,
                muted_at        => undef,
                preference      => 'all',
                revoked_at      => undef,
                subscription_id => undef,
                target_id       => $THREAD,
                target_type     => 'thread',
                user_id         => $USER,
            },
            'subscription_id',
        ],
      )
    {
        my ( $method, $function, $type, $extra, $request_extra, $row_expected,
            $id_column )
          = @{$case};
        my $response = {
            error  => undef,
            errors => undef,
            ok     => 1,
            status => 'ok',
            stored => {}
        };
        my ( $handle, $functions, $ids, $clock, $log ) = fixture(
            [ { outcome => 'recorded', response => $json->encode($response) } ]
        );
        my %store = (
            clock      => $clock,
            functions  => $functions,
            id_service => $ids,
            schema     => $handle,
        );
        my $workflow = GPForum::Service::Community::Workflow->new(
            bookmark_store =>
              GPForum::Service::Community::BookmarkStore->new(%store),
            command_idempotency => $log,
            like_store          => $handle,
            logger              => GPForum::Test::LogLines->new,
            report_store        => $handle,
            subscription_store  =>
              GPForum::Service::Notification::SubscriptionStore->new(%store),
        );
        my $result = $workflow->$method(
            {
                command_id  => "$method-1",
                target_id   => $THREAD,
                target_type => 'thread',
                user_id     => $USER,
                %{$extra},
            }
        );
        is_deeply( $result, $response, "$method: the answer recorded" );
        is( scalar @{ $handle->executed }, 1, "$method: one call" );
        like( $handle->prepared->[0],
            qr/api[.]${function}_v2/msx, "$method: to its command" );
        my ( $sent_log, $answer, $row ) = sent($handle);
        my ( $command_id, $correlation_id, $row_id ) =
          expected_ids($IDS_WITH_ROW);
        is_deeply(
            $sent_log,
            {
                actor_id               => $USER,
                command_at             => $NOW,
                command_correlation_id => $correlation_id,
                command_id             => $command_id,
                command_type           => $type,
                idempotency_key        => "$method-1",
                request_hash           =>
                  GPForum::Service::Operations::CommandIdempotency
                  ->request_hash(
                    {
                        target_id   => $THREAD,
                        target_type => 'thread',
                        user_id     => $USER,
                        %{$request_extra},
                    }
                  ),
            },
            "$method: the command log row"
        );
        is( $answer, undef, "$method: no refusal before the call" );
        $row_expected->{$id_column} = $row_id;
        is_deeply( $row, $row_expected,
            "$method: the store row, its id drawn after the log's" );
    }
};

done_testing();

1;
