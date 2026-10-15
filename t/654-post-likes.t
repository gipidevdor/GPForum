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
use GPForum::Service::Community::LikeStore;
use GPForum::Service::Community::Workflow;
use GPForum::Service::Operations::CommandIdempotency;
use GPForum::Test::FixedClock;
use GPForum::Test::LogLines;
use GPForum::Test::SequenceId;
use GPForum::Test::SqlFunctionHandle;

our $VERSION = '0.001';

# A like, and taking it back, are one call each (ADR 0129, on the shape of
# ADR 0126 section 5): what the call sends -- the command log's row and the
# like's row with the ids the store drew -- and what its outcome answers, on
# a handle that records the call and answers what the test gives. The page
# read maps the counts by post.

const my $POST         => '018f1005-0001-7000-8000-000000000001';
const my $THREAD       => '018f1004-0001-7000-8000-000000000001';
const my $USER         => '018f1002-0002-7000-8000-000000000002';
const my $NOW          => '2026-10-15T10:00:00Z';
const my $PREFIX       => '018f0009-0000-7000-8000';
const my $IDS_PER_LIKE => 5;    # the command's two, then the row's three
const my $LIKES        => 2;

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
    my $store = GPForum::Service::Community::LikeStore->new(
        clock      => $clock,
        functions  => $functions,
        id_service => $ids,
        schema     => $handle,
    );
    my $workflow = GPForum::Service::Community::Workflow->new(
        bookmark_store      => $handle,
        command_idempotency => $log,
        functions           => $functions,
        like_store          => $store,
        logger              => GPForum::Test::LogLines->new,
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

sub stored ( $liked, $count ) {
    return {
        like_count => $count,
        liked      => $liked,
        ok         => 1,
        post_id    => $POST,
        thread_id  => $THREAD,
        user_id    => $USER,
    };
}

for my $case (
    [ like_post   => 'community.like',   'community_like_command_v2',   1 ],
    [ unlike_post => 'community.unlike', 'community_unlike_command_v2', 0 ],
  )
{
    my ( $method, $command_type, $function, $liked ) = @{$case};
    subtest "$method is one call" => sub {
        my $response = {
            error  => undef,
            errors => undef,
            ok     => 1,
            status => 'ok',
            stored => stored( $liked, $liked ? 1 : 0 ),
        };
        my ( $handle, $store, $workflow, $log ) = fixture(
            [ { outcome => 'recorded', response => $json->encode($response) } ]
        );
        my $result = $workflow->$method(
            { command_id => " $method-1 ", post_id => $POST, user_id => $USER }
        );
        is_deeply( $result, $response, 'the answer is the one recorded' );
        is( scalar @{ $handle->executed }, 1, 'in one call' );
        like( $handle->prepared->[0], qr/api[.]$function/msx, "to $function" );
        my ( $sent_log, $answer, $row ) = sent($handle);
        my ( $command_id, $correlation_id, $row_correlation, $event_id,
            $outbox_id )
          = expected_ids($IDS_PER_LIKE);
        is_deeply(
            $sent_log,
            {
                actor_id               => $USER,
                command_at             => $NOW,
                command_correlation_id => $correlation_id,
                command_id             => $command_id,
                command_type           => $command_type,
                idempotency_key        => "$method-1",
                request_hash           =>
                  $log->request_hash( { post_id => $POST, user_id => $USER } ),
            },
            'the command log row is sent as the Perl path writes it'
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
                user_id        => $USER,
            },
            'and the row with the event ids the store drew'
        );
    };
}

subtest 'a refused command is a conflict' => sub {
    my ( $handle, $store, $workflow ) =
      fixture( [ { outcome => 'conflict', response => undef } ] );
    my $result = $workflow->like_post(
        { command_id => 'like-2', post_id => $POST, user_id => $USER } );
    is( $result->{status}, 'conflict', 'the outcome names the refusal' );
    ok( $result->{error}, 'with its reason' );
};

subtest 'the page read maps the likes by post' => sub {
    my ( $handle, $store ) =
      fixture( [ { like_count => $LIKES, liked => 1, post_id => $POST } ] );
    is_deeply(
        $store->summary_for_posts( [ $POST, $THREAD ], $USER ),
        { $POST => { like_count => $LIKES, liked => 1 } },
        'a post with likes is counted, with the viewer\'s own'
    );
    like(
        $handle->prepared->[0],
        qr/api[.]community_post_likes_v2/msx,
        'through the page read'
    );
    is_deeply( $store->summary_for_posts( [], $USER ),
        {}, 'and no posts ask nothing' );
    is( scalar @{ $handle->executed }, 1, 'of the database' );
};

subtest 'likes exist only as functions' => sub {
    my $store = GPForum::Service::Community::LikeStore->new(
        functions => undef,
        schema    => GPForum::Test::SqlFunctionHandle->new,
    );
    like(
        exception { $store->like( { post_id => $POST, user_id => $USER } ) },
        qr/SQL [ ] function [ ] layer/msx,
        'without the call layer the store refuses to guess'
    );
};

done_testing();

1;
