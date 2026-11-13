# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use lib 'lib';
use lib 't/lib';

use Const::Fast;
use Mojo::File qw(path);
use GPForum::Service::Outbox::ClaimedMessage;
use GPForum::Service::Outbox::FailureType;
use GPForum::Service::Outbox::Retry;
use GPForum::Test::OutboxFailure;
use GPForum::Test::OutboxRow;
use GPForum::X::Argument;
use GPForum::X::Unavailable;
use Test::More;

our $VERSION = '0.001';

const my $LOCK_SECONDS    => 60;
const my $DEFAULT_MAX     => 5;
const my $CUSTOM_MAX      => 2;
const my $FIRST_ATTEMPT   => 1;
const my $RETRY_ATTEMPT   => 3;
const my $NEXT_ATTEMPT    => 4;
const my $BACKOFF_SECONDS => 180;

my $types = GPForum::Service::Outbox::FailureType->new;
is( $types->classify('boom'),
    'transient', 'unmatched exceptions classify as transient' );
is( $types->classify( GPForum::Test::OutboxFailure->new('serial timeout') ),
    'serialization', 'serial error text classifies as serialization' );
is( $types->classify( GPForum::Test::OutboxFailure->new('forbidden') ),
    'authorization', 'forbidden error text classifies as authorization' );
is( $types->classify( GPForum::Test::OutboxFailure->new('unauthorised') ),
    'authorization', 'unauthorised error text classifies as authorization' );
is( $types->classify( GPForum::Test::OutboxFailure->new('transport closed') ),
    'transport', 'transport error text classifies as transport' );
is( $types->classify( GPForum::Test::OutboxFailure->new('notify failed') ),
    'transport', 'notify error text classifies as transport' );
is( $types->classify( GPForum::Test::OutboxFailure->new('permanent reject') ),
    'permanent', 'permanent error text classifies as permanent' );
is( $types->classify( bless {}, 'GPForum::Test::SerialCase' ),
    'serialization', 'Serial class names classify as serialization' );
is( $types->classify( bless {}, 'GPForum::Test::AuthorizationDenied' ),
    'authorization', 'Authorization class names classify as authorization' );
is( $types->classify( bless {}, 'GPForum::Test::AuthorisationDenied' ),
    'authorization', 'Authorisation class names classify as authorization' );
is( $types->classify( bless {}, 'GPForum::Test::TransportBroke' ),
    'transport', 'Transport class names classify as transport' );
is( $types->classify( bless {}, 'GPForum::Test::PermanentFail' ),
    'permanent', 'Permanent class names classify as permanent' );
is(
    $types->classify(
        GPForum::Test::OutboxFailure->new( 'serial timeout', 'permanent' )
    ),
    'permanent',
    'declared failure_type wins over regex rules'
);
is(
    $types->classify(
        GPForum::X::Unavailable->new( message => 'clamd did not answer' )
    ),
    'transport',
    'an X::Unavailable is classified by the type it declares'
);
is(
    $types->classify(
        GPForum::X::Argument->new( message => 'Pg serial transport' )
    ),
    'permanent',
    'an X class is not reclassified by the regexes its message matches'
);
is( $types->classify( { message => 'serial timeout' } ),
    'transient', 'an unblessed reference is matched, not asked for a type' );

my $retry = GPForum::Service::Outbox::Retry->new;
is(
    $retry->next_attempt(
        GPForum::Test::OutboxRow->new( data => { attempt_count => 0 } )
    ),
    1,
    'retry starts attempt counts from zero'
);
is(
    $retry->next_attempt(
        GPForum::Test::OutboxRow->new(
            data => { attempt_count => $RETRY_ATTEMPT }
        )
    ),
    $NEXT_ATTEMPT,
    'retry increments the stored attempt count'
);
is( $retry->status($RETRY_ATTEMPT),
    'failed', 'retry keeps status failed before the attempt ceiling' );
is( $retry->status( $FIRST_ATTEMPT, 'permanent' ),
    'cancelled',
    'retry cancels a permanent failure before the attempt ceiling' );
is( $retry->status( $FIRST_ATTEMPT, 'transient' ),
    'failed', 'retry keeps a transient failure retryable before the ceiling' );
is( $retry->status($DEFAULT_MAX),
    'cancelled', 'retry cancels when attempts reach the default ceiling' );
is(
    GPForum::Service::Outbox::Retry->new( max_attempts => $CUSTOM_MAX )
      ->status($CUSTOM_MAX),
    'cancelled',
    'retry cancels when attempts reach a custom ceiling'
);
is( $retry->backoff_seconds($RETRY_ATTEMPT),
    $BACKOFF_SECONDS, 'retry backoff is attempt count times the lock quantum' );
is( $retry->lock_seconds,
    $LOCK_SECONDS, 'retry lock duration matches the claim lock quantum' );
ok( $retry->is_cancelled('cancelled'),
    'retry treats cancelled as a terminal status' );
ok( !$retry->is_cancelled('failed'),
    'retry does not treat failed as a terminal status' );

# The claim is api.outbox_claim_ready (the operations baseline): each half of the
# ready rows read from its own index, locked FOR UPDATE SKIP LOCKED so
# several workers claim without a global lock, in a stable order.
my $migration = path('migrations/2015_api_operations.sql')->slurp;
my $start     = index $migration, 'CREATE FUNCTION api.outbox_claim_ready_v5(';
my $claim     = substr $migration, $start,
  index( $migration, "\n\$\$;", $start ) - $start;
ok(
    index( $claim, 'FOR UPDATE OF me SKIP LOCKED' ) >= 0,
    'the claim locks with FOR UPDATE SKIP LOCKED'
);
ok(
    index( $claim,
        'ORDER BY ready.next_attempt_at, ready.created_at, ready.outbox_id' )
      >= 0,
    'and answers in a stable ready-queue order'
);

my $object_message = GPForum::Service::Outbox::ClaimedMessage->new(
    row => { payload => '{"event_id":"event-1"}' }, );
is_deeply(
    $object_message->get_column('payload'),
    { event_id => 'event-1' },
    'claimed message decodes JSON object payloads'
);

my $scalar_message = GPForum::Service::Outbox::ClaimedMessage->new(
    row => { payload => '"not-an-object"' }, );
is_deeply( $scalar_message->get_column('payload'), {},
    'claimed message rejects non-object JSON after allow_nonref default change'
);

my $array_message = GPForum::Service::Outbox::ClaimedMessage->new(
    row => { payload => '["event-1"]' }, );
is_deeply( $array_message->get_column('payload'),
    {}, 'claimed message rejects JSON arrays as outbox payloads' );

done_testing();

1;
