# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause
package main;
use v5.40;
use Const::Fast;
use Test::More;
use lib 'lib';
use lib 't/lib';
use GPForum::Test::RegistryHashMeter;
use GPForum::Service::Realtime::ConnectionRegistry;
our $VERSION = '0.001';
const my $CONNECTIONS => 2000;
const my $CHURN       => 100;
my $registry = GPForum::Service::Realtime::ConnectionRegistry->new(
    max_connections_per_user         => 2,
    max_subscriptions_per_connection => 2
);
ok( $registry->register( 'a', { user_id => 'alice' }, undef ), 'first socket' );
ok( $registry->register( 'b', { user_id => 'alice' }, undef ),
    'second socket' );
ok( !$registry->register( 'c', { user_id => 'alice' }, undef ),
    'quota remains enforced' );
$registry->subscribe( 'a', 'notifications:alice' );
$registry->subscribe( 'b', 'notifications:alice' );
$registry->subscribe( 'b', 'thread:one' );
ok( $registry->subscribe( 'b', 'notifications:alice' )->{ok},
    'resubscribing at quota stays idempotent' );
ok(
    !$registry->subscribe( 'b', 'thread:two' )->{ok},
    'new subscription at quota is refused'
);
is( scalar( $registry->subscribers('notifications:alice') ),
    2, 'two recipients, no duplicate' );
$registry->unregister('a');
is( scalar( $registry->subscribers('notifications:alice') ),
    1, 'disconnect removes recipient' );
ok( $registry->register( 'c', { user_id => 'alice' }, undef ),
    'disconnect releases quota' );
$registry->subscribe( 'c', 'notifications:alice' );
ok( $registry->register( 'c', { user_id => 'bob' }, undef ),
    'replacing an id reassigns its owner' );
is( scalar( $registry->subscribers('notifications:alice') ),
    1, 'replacement drops old subscriptions' );
is( $registry->user_connection_counts->{alice},
    1, 'replacement releases previous owner count' );
is( $registry->user_connection_counts->{bob},
    1, 'replacement counts new owner once' );
ok( !$registry->unregister('missing'), 'missing disconnect is harmless' );
$registry->unregister('b');
$registry->unregister('c');
is_deeply( $registry->channel_connections,    {}, 'empty channels are pruned' );
is_deeply( $registry->user_connection_counts, {}, 'empty owners are pruned' );

for my $index ( 1 .. $CHURN ) {
    $registry->register( "c-$index", { user_id => "user-$index" }, undef );
    $registry->subscribe( "c-$index", "notifications:user-$index" );
    $registry->unregister("c-$index");
}
is( $registry->count, 0, 'churn retains no sockets' );
is_deeply( $registry->channel_connections, {}, 'churn retains no channel ids' );
is_deeply( $registry->user_connection_counts,
    {}, 'churn retains no user counters' );
my %seeded = map {
    (
        "c-$_" => {
            connection_id => "c-$_",
            actor         => { user_id                 => "user-$_" },
            subscriptions => { "notifications:user-$_" => 1 }
        }
    )
} 1 .. $CONNECTIONS;

# Meter traversal rather than wall-clock timing. Production never ties data.
tie my %measured, 'GPForum::Test::RegistryHashMeter', \%seeded;    ## no critic (Miscellanea::ProhibitTies)
my $meter   = tied %measured;
my $indexed = GPForum::Service::Realtime::ConnectionRegistry->new(
    connections => \%measured );
my @warm = $indexed->subscribers('notifications:user-1');
$indexed->can_register( { user_id => 'user-1' } );
$meter->{fetches}    = 0;
$meter->{iterations} = 0;
my @subscribers = $indexed->subscribers('notifications:user-1');
is( scalar @subscribers, 1, 'seeded registry finds its recipient' );
is( $meter->{fetches}, 1,
    'recipient lookup reads only its own row among thousands' );
is( $meter->{iterations}, 0,
    'recipient lookup never enumerates unrelated sockets' );
$meter->{fetches} = 0;
ok( $indexed->can_register( { user_id => 'user-1' } ),
    'seeded owner quota is available' );
is( $meter->{fetches},    0, 'quota check reads no socket rows' );
is( $meter->{iterations}, 0, 'quota check enumerates no sockets' );
my @absent = $indexed->subscribers('notifications:absent');
is( scalar @absent, 0, 'missing channel is empty' );
ok(
    !exists $indexed->channel_connections->{'notifications:absent'},
    'missing lookups do not allocate persistent channels'
);
my $seeded_registry = GPForum::Service::Realtime::ConnectionRegistry->new(
    connections => {
        one => {
            connection_id => 'one',
            actor         => { user_id      => 'same' },
            subscriptions => { 'thread:one' => 1 }
        },
        two => {
            connection_id => 'two',
            actor         => { user_id      => 'same' },
            subscriptions => { 'thread:one' => 1 }
        },
    }
);
$seeded_registry->unregister('one');
is( $seeded_registry->user_connection_counts->{same},
    1, 'first operation may disconnect a seeded socket' );
is( scalar( $seeded_registry->subscribers('thread:one') ),
    1, 'seeded channel remains consistent after disconnect' );
done_testing;
1;
