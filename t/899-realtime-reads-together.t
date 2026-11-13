# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;
use Const::Fast;
use Test::More;
use lib 'lib';
use lib 't/lib';

use GPForum::Service::Realtime::ConnectionRegistry;
use GPForum::Service::Realtime::Hub;
use GPForum::Service::Realtime::SubscriptionPolicy;
use GPForum::Test::RealtimeConnection;
use GPForum::Test::SlowRealtimeReads;

our $VERSION = '0.001';

const my $MODERATORS   => 7;
const my $TABS         => 2;
const my $AT_ONCE      => 5;
const my @RESOURCE_SET => qw(thread post);

# The hub and the subscription policy ask their independent reads together:
# a reply's thread and post readers, the moderators of a queue a few at a
# time, a subscriber's suspension and thread. The double answers each read
# a moment later and counts how many are in flight at once.

sub settled ($promise) {
    my ( $value, $error );
    $promise->then(
        sub ($answer) { $value  = $answer },
        sub ($failure) { $error = $failure }
    )->wait;
    return ( $value, $error );
}

subtest 'a reply hint asks its thread and post readers together' => sub {
    my $reads = GPForum::Test::SlowRealtimeReads->new(
        readers => { thread => [qw(ann bob)], post => [qw(bob cid)] } );
    my $hub = GPForum::Service::Realtime::Hub->new(
        registry    => GPForum::Service::Realtime::ConnectionRegistry->new,
        readability => $reads,
    );
    my %socket;
    for my $user (qw(ann bob cid)) {
        $socket{$user} = GPForum::Test::RealtimeConnection->new;
        $hub->register_connection( "c-$user", { user_id => $user },
            $socket{$user} );
        $hub->registry->subscribe( "c-$user", 'thread:t1' );
    }
    my ($result) = settled(
        $hub->broadcast_p(
            'thread:t1',
            { type => 'thread.update', payload => { post_id => 'p1' } }
        )
    );

    is( $result->{delivered}, 1, 'one subscriber reads both' );
    is( scalar @{ $socket{bob}->sent },
        1, 'the one who reads the thread and the post' );
    is( scalar @{ $socket{ann}->sent } + scalar @{ $socket{cid}->sent },
        0, 'not who reads only one of them' );
    is(
        scalar @{ $reads->calls },
        scalar @RESOURCE_SET,
        'each resource asked once'
    );
    is( $reads->most, scalar @RESOURCE_SET, 'all in flight together' );
};

subtest 'a queue broadcast asks its moderators a few at a time' => sub {
    my $reads = GPForum::Test::SlowRealtimeReads->new( denied => { m3 => 1 } );
    my $hub   = GPForum::Service::Realtime::Hub->new(
        registry   => GPForum::Service::Realtime::ConnectionRegistry->new,
        authorizer => $reads,
    );
    my @moderators = map { "m$_" } 1 .. $MODERATORS;
    for my $user (@moderators) {
        for my $tab ( 1 .. $TABS ) {
            $hub->register_connection(
                "c-$user-$tab",
                { user_id => $user },
                GPForum::Test::RealtimeConnection->new
            );
            $hub->registry->subscribe( "c-$user-$tab", 'moderation:queue' );
        }
    }
    my ($result) = settled(
        $hub->broadcast_p(
            'moderation:queue', { type => 'moderation.queue.invalidate' }
        )
    );

    is(
        $result->{delivered},
        ( $MODERATORS - 1 ) * $TABS,
        'every tab of each moderator still admitted'
    );
    is_deeply( [ sort @{ $reads->calls } ],
        \@moderators, 'each moderator asked once' );
    is( $reads->most, $AT_ONCE, 'at most five asked at once' );
};

subtest 'a subscription reads the suspension and the thread together' => sub {
    my $reads  = GPForum::Test::SlowRealtimeReads->new;
    my $policy = GPForum::Service::Realtime::SubscriptionPolicy->new(
        readability      => $reads,
        suspension_store => $reads,
    );
    my @question = (
        { user_id => 'ann' },
        'realtime.subscribe', { type => 'thread', id => 't1' }, {},
    );

    my ($answer) = settled( $policy->permits_p(@question) );
    is_deeply(
        $answer,
        { ok => 1, reason => 'thread_readable' },
        'a readable thread is allowed'
    );
    is( $reads->most, 2, 'the suspension and the thread in flight together' );

    $reads->fail(1);
    my ( undef, $error ) = settled( $policy->permits_p(@question) );
    like(
        $error,
        qr/readability [ ] is [ ] down/msx,
        'a thread read that failed fails an account that passed'
    );

    $reads->suspended(1);
    my ( $denied, $thrown ) = settled( $policy->permits_p(@question) );
    is_deeply(
        $denied,
        { ok => 0, reason => 'forbidden' },
        'a suspended member is denied first'
    );
    ok( !defined $thrown, 'without the thread read failing the answer' );
};

done_testing();

1;
