# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use JSON::MaybeXS;
use Test::Fatal;
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Infrastructure::SqlFunction;
use GPForum::Service::Community::ReactionStore;
use GPForum::Service::Community::Workflow;
use GPForum::Service::Operations::CommandIdempotency;
use GPForum::Test::FixedClock;
use GPForum::Test::LogLines;
use GPForum::Test::SequenceId;
use GPForum::Test::SqlFunctionHandle;

our $VERSION = '0.001';

# A reaction, and taking it back, are one call each (ADR 0145, on the shape
# of the like, ADR 0129): what the call sends -- the command log's row and
# the reaction's row with the ids the store drew -- and what its outcome
# answers, on a handle that records the call. The page read maps the counts
# by post and reaction.

const my $POST             => '018f1005-0001-7000-8000-000000000001';
const my $OTHER            => '018f1005-0002-7000-8000-000000000002';
const my $THREAD           => '018f1004-0001-7000-8000-000000000001';
const my $USER             => '018f1002-0002-7000-8000-000000000002';
const my $NOW              => '2026-10-22T10:00:00Z';
const my $PREFIX           => '018f0009-0000-7000-8000';
const my $IDS_PER_REACTION => 5;    # the command's two, then the row's three
const my $HEARTS           => 3;

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
    my $store = GPForum::Service::Community::ReactionStore->new(
        clock      => $clock,
        functions  => $functions,
        id_service => $ids,
        schema     => $handle,
    );
    my $workflow = GPForum::Service::Community::Workflow->new(
        bookmark_store      => $handle,
        command_idempotency => $log,
        functions           => $functions,
        like_store          => $handle,
        logger              => GPForum::Test::LogLines->new,
        reaction_store      => $store,
        report_store        => $handle,
        subscription_store  => $handle,
    );
    return ( $handle, $store, $workflow, $log );
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

sub stored ( $reacted, $count ) {
    return {
        ok             => 1,
        post_id        => $POST,
        reacted        => $reacted,
        reaction       => 'heart',
        reaction_count => $count,
        thread_id      => $THREAD,
        user_id        => $USER,
    };
}

subtest 'the four reactions, and nothing else' => sub {
    my ( undef, $store ) = fixture();
    is_deeply(
        $store->reactions,
        [qw(heart laugh celebrate think)],
        'in the order a page shows them'
    );
    ok( $store->is_reaction('laugh'), 'one of them is one' );
    ok( !$store->is_reaction('like'), 'the like is not a reaction' );
    ok( !$store->is_reaction(undef),  'nor is nothing' );
};

for my $case (
    [ react_post   => 'community.react',   'community_react_command_v2',   1 ],
    [ unreact_post => 'community.unreact', 'community_unreact_command_v2', 0 ],
  )
{
    my ( $method, $command_type, $function, $reacted ) = @{$case};
    subtest "$method is one call" => sub {
        my $response = {
            error  => undef,
            errors => undef,
            ok     => 1,
            status => 'ok',
            stored => stored( $reacted, $reacted ? 1 : 0 ),
        };
        my ( $handle, $store, $workflow, $log ) = fixture(
            [ { outcome => 'recorded', response => $json->encode($response) } ]
        );
        my $result = $workflow->$method(
            {
                command_id => " $method-1 ",
                post_id    => $POST,
                reaction   => 'heart',
                user_id    => $USER
            }
        );
        is_deeply( $result, $response, 'the answer is the one recorded' );
        is( scalar @{ $handle->executed }, 1, 'in one call' );
        like( $handle->prepared->[0], qr/api[.]$function/msx, "to $function" );
        my ( $sent_log, $answer, $row ) = sent($handle);
        my ( $command_id, $correlation_id, $row_correlation, $event_id,
            $outbox_id )
          = expected_ids($IDS_PER_REACTION);
        is_deeply(
            $sent_log,
            {
                actor_id               => $USER,
                command_at             => $NOW,
                command_correlation_id => $correlation_id,
                command_id             => $command_id,
                command_type           => $command_type,
                idempotency_key        => "$method-1",
                request_hash           => $log->request_hash(
                    { post_id => $POST, reaction => 'heart', user_id => $USER }
                ),
            },
            'the command log row names the reaction with the post'
        );
        is( $answer, undef, 'with no answer decided before the call' );
        is_deeply(
            $row,
            {
                correlation_id => $row_correlation,
                created_at     => $NOW,
                event_id       => $event_id,
                outbox_id      => $outbox_id,
                post_id        => $POST,
                reaction       => 'heart',
                user_id        => $USER,
            },
            'and the row with the reaction and the event ids the store drew'
        );
    };
}

subtest 'the page reads the reactions of its posts in one call' => sub {
    my ( $handle, $store ) = fixture(
        [
            {
                post_id        => $POST,
                reacted        => 1,
                reaction       => 'heart',
                reaction_count => $HEARTS
            },
            {
                post_id        => $POST,
                reacted        => 0,
                reaction       => 'think',
                reaction_count => 1
            },
            {
                post_id        => $OTHER,
                reacted        => 0,
                reaction       => 'laugh',
                reaction_count => 1
            },
        ]
    );
    is_deeply(
        $store->reactions_for_posts( [ $POST, $OTHER ], $USER ),
        {
            $POST => {
                heart => { count => $HEARTS, reacted => 1 },
                think => { count => 1,       reacted => 0 },
            },
            $OTHER => { laugh => { count => 1, reacted => 0 } },
        },
        'by post, then by reaction: how many, and whether the viewer gave it'
    );
    like(
        $handle->prepared->[0],
        qr/api[.]community_post_reactions_v2/msx,
        'through the read function'
    );
    is_deeply(
        [ @{ $handle->executed->[0] } ],
        [ [ $POST, $OTHER ], $USER ],
        'with the posts and the viewer'
    );
    is_deeply( $store->reactions_for_posts( [] ),
        {}, 'a page without posts asks nothing' );
    is_deeply(
        $store->reactions_call( [$POST] ),
        [
            'community_post_reactions',
            { post_ids => [$POST], viewer_user_id => undef }
        ],
        'the call a guest makes names no viewer'
    );
};

subtest 'without a reaction store the workflow refuses' => sub {
    my ( $handle, undef, undef, $log ) = fixture();
    my $workflow = GPForum::Service::Community::Workflow->new(
        bookmark_store      => $handle,
        command_idempotency => $log,
        like_store          => $handle,
        report_store        => $handle,
        subscription_store  => $handle,
    );
    like(
        exception {
            $workflow->react_post(
                { post_id => $POST, reaction => 'heart', user_id => $USER } );
        },
        qr/reaction [ ] store/msx,
        'a reaction needs its store'
    );
};

subtest 'reactions exist only as functions' => sub {
    my $store = GPForum::Service::Community::ReactionStore->new(
        functions => undef,
        schema    => GPForum::Test::SqlFunctionHandle->new,
    );
    like(
        exception { $store->reactions_for_posts( [$POST] ) },
        qr/SQL [ ] function [ ] layer/msx,
        'without the call layer the store refuses to guess'
    );
};

done_testing();

1;
