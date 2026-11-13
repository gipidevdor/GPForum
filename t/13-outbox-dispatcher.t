# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use Test::Exception;
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Service::Outbox::Dispatcher;
use GPForum::Test::Id;
use GPForum::Test::OutboxClock;
use GPForum::Test::OutboxFunctions;
use GPForum::Test::OutboxTransport;

our $VERSION = '0.001';

const my $DEFAULT_MAX => 5;
const my $NOW         => '2026-05-23T12:00:00Z';
const my $LEASE_END   => '2026-05-23T12:01:00Z';

# The dispatcher claims through api.outbox_claim_ready and writes every
# outcome through api.outbox_owned_write, which lands only while the message
# is still this worker's; a dead letter is api.outbox_dead_letter's. The
# functions themselves -- which rows a claim takes, a dead letter written
# once -- are t/integration/postgres-outbox-dispatcher.t's,
# postgres-outbox-lease-race.t's and postgres-outbox-reclaim.t's.
my $functions = GPForum::Test::OutboxFunctions->new(
    claimed_rows => [
        _row( 'outbox-1', 0 ),
        _row( 'outbox-2', 1, { event_id => 'event-2' } ),
    ]
);
my $transport =
  GPForum::Test::OutboxTransport->new( fail_ids => { 'outbox-2' => 1 }, );
my $summary = _dispatcher(
    $functions, $transport,
    worker_id    => 'worker-1',
    max_attempts => 2,
)->dispatch_pending(2);

is( $summary->{selected},      2, 'dispatcher selects ready messages' );
is( $summary->{dispatched},    1, 'dispatcher counts delivered messages' );
is( $summary->{failed},        0, 'dispatcher counts retryable failures' );
is( $summary->{dead_lettered}, 1, 'dispatcher counts exhausted failures' );
is_deeply(
    $functions->claim,
    {
        now          => $NOW,
        locked_until => $LEASE_END,
        row_limit    => 2,
        worker_id    => 'worker-1',
    },
    'the claim names now, the lease end, the caller limit and this worker'
);
is_deeply(
    $functions->writes('worker-1'),
    [qw(renew:outbox-1 done:outbox-1 renew:outbox-2 cancelled:outbox-2)],
    'each message is renewed, then its outcome written'
);
is( _changes( $functions, 'outbox-1', 'renew' )->{locked_until},
    $LEASE_END, 'the renewal records the lock timeout' );

my $done = _changes( $functions, 'outbox-1', 'done' );
ok( exists $done->{locked_by} && !defined $done->{locked_by},
    'successful message releases worker lock' );
is_deeply( $transport->delivered, ['outbox-1'],
    'transport receives only successful message' );

my $cancelled = _changes( $functions, 'outbox-2', 'cancelled' );
is( $cancelled->{attempt_count}, 2,
    'failing message increments attempt count' );
ok( !exists $cancelled->{attempts},
    'and writes the count once, as attempt_count' );
is( $cancelled->{last_error}, 'boom', 'failing message records error text' );
is(
    $cancelled->{last_error_class},
    'GPForum::Test::OutboxFailure',
    'failing message records error class'
);
is( $cancelled->{failure_type},
    'transient', 'failing message records classified failure type' );
is( $cancelled->{next_attempt_at},
    $LEASE_END, 'failing message schedules retry' );
ok( exists $cancelled->{locked_by} && !defined $cancelled->{locked_by},
    'failing message releases worker lock' );

my $letters = $functions->letters;
is( scalar @{$letters}, 1, 'dead letter row is created' );
is( $letters->[0]{source_table},
    'outbox_messages', 'dead letter stores source table' );
is( $letters->[0]{source_id},   'outbox-2', 'dead letter stores source id' );
is( $letters->[0]{retry_count}, 2,          'dead letter stores retry count' );
is( $letters->[0]{failure_type},
    'transient', 'dead letter stores classified failure type' );
is_deeply(
    $letters->[0]{payload},
    { event_id => 'event-2' },
    'dead letter stores failed payload'
);
is( $functions->transactions, 1,
    'the cancellation and its dead letter are written in one transaction' );

my $permanent_functions = GPForum::Test::OutboxFunctions->new( claimed_rows =>
      [ _row( 'outbox-permanent', 0, { event_id => 'event-permanent' } ) ] );
my $permanent_summary = _dispatcher(
    $permanent_functions,
    GPForum::Test::OutboxTransport->new(
        fail_ids   => { 'outbox-permanent' => 1 },
        fail_types => { 'outbox-permanent' => 'permanent' },
    ),
    max_attempts => $DEFAULT_MAX,
    worker_id    => 'worker-permanent',
)->dispatch_pending(1);
is( $permanent_summary->{dead_lettered},
    1, 'permanent failure is dead-lettered on the first attempt' );
is( $permanent_summary->{failed},
    0, 'permanent failure is not scheduled for retry' );
is_deeply(
    $permanent_functions->writes('worker-permanent'),
    [qw(renew:outbox-permanent cancelled:outbox-permanent)],
    'permanent failure cancels the outbox row'
);
is( $permanent_functions->letters->[0]{failure_type},
    'permanent', 'permanent dead letter stores the classified failure type' );

my $pg_functions =
  GPForum::Test::OutboxFunctions->new( claimed_rows => [ _row('pg-1') ] );
my @pg_claimed =
  _dispatcher( $pg_functions, GPForum::Test::OutboxTransport->new )
  ->claim_ready_batch(1);

is( scalar @pg_claimed,
    1, 'PostgreSQL claim returns rows already locked by current worker' );
is(
    ref $pg_claimed[0],
    'GPForum::Service::Outbox::ClaimedMessage',
    'PostgreSQL claim returns lightweight DBI-backed messages'
);
is_deeply( [ map { $_->[0] } @{ $pg_functions->calls } ],
    ['outbox_claim_ready'],
    'the claim is one call, and nothing reloads the claimed rows' );
is_deeply(
    [ @{ $pg_functions->claim }{qw(row_limit worker_id)} ],
    [ 1, 'pg-worker' ],
    'PostgreSQL claim names the caller limit and the current worker'
);

my $pg_done_functions = GPForum::Test::OutboxFunctions->new(
    claimed_rows => [ map { _row($_) } qw(pg-done-1 pg-done-2) ] );
my $pg_done_transport = GPForum::Test::OutboxTransport->new;
my $pg_done_summary =
  _dispatcher( $pg_done_functions, $pg_done_transport )->dispatch_pending(2);

is( $pg_done_summary->{dispatched},
    2, 'PostgreSQL direct dispatcher dispatches claimed messages' );
is( $pg_done_summary->{acknowledged},
    2, 'PostgreSQL direct dispatcher acknowledges each done message' );
is_deeply(
    $pg_done_transport->delivered,
    [ 'pg-done-1', 'pg-done-2' ],
    'PostgreSQL direct dispatcher preserves delivery order'
);

# Per message: the claim renewed, then the acknowledgement, before the next
# message is touched -- not one acknowledgement for the batch at its end,
# which a slow batch's expired lease let a second worker race. Each write
# names this worker, whose message it must still be.
is_deeply(
    $pg_done_functions->writes('pg-worker'),
    [qw(renew:pg-done-1 done:pg-done-1 renew:pg-done-2 done:pg-done-2)],
    'PostgreSQL direct dispatcher renews then acknowledges each message'
);

# A write lands only while the message is still this worker's: one whose
# lease expired and was re-claimed elsewhere is not. The second message is:
# its renewal finds it gone, and it is not dispatched at all.
my $pg_stolen_transport = GPForum::Test::OutboxTransport->new;
my $pg_stolen_summary   = _dispatcher(
    GPForum::Test::OutboxFunctions->new(
        claimed_rows => [ map { _row($_) } qw(pg-steal-1 pg-steal-2) ],
        owned_ids    => ['pg-steal-1'],
    ),
    $pg_stolen_transport
)->dispatch_pending(2);

is_deeply( $pg_stolen_transport->delivered,
    ['pg-steal-1'], 'the message another worker took is not dispatched' );
is( $pg_stolen_summary->{dispatched},
    1, 'only the owned message is counted as dispatched' );
is( $pg_stolen_summary->{acknowledged}, 1, 'and as acknowledged' );
is( $pg_stolen_summary->{lost},         1, 'the other is counted as lost' );

# The status update and the dead-letter row describe one failure. Written
# separately, a crash between them left a message marked cancelled -- terminal,
# never retried -- with nothing recording why. Making the dead-letter insert
# throw must therefore take the status update down with it.
my $atomic_functions = GPForum::Test::OutboxFunctions->new(
    claimed_rows =>
      [ _row( 'outbox-atomic', 1, { event_id => 'event-atomic' } ) ],
    letter_error => 'dead letter store is down',
);
my $atomic_dispatcher = _dispatcher(
    $atomic_functions,
    GPForum::Test::OutboxTransport->new(
        fail_ids => { 'outbox-atomic' => 1 }
    ),
    worker_id    => 'worker-atomic',
    max_attempts => 2,
);

my $atomic_transactions = $atomic_functions->transactions;
dies_ok(
    sub { $atomic_dispatcher->dispatch_pending(1); },
    'a dead-letter write failure is not swallowed'
);
cmp_ok( $atomic_functions->transactions,
    q{>}, $atomic_transactions,
    'the failure bookkeeping runs inside a transaction' );
is_deeply( $atomic_functions->writes('worker-atomic'),
    ['renew:outbox-atomic'],
    'the message is not left cancelled when its dead letter was not written' );
is( scalar @{ $atomic_functions->letters },
    0, 'no dead letter survives the rolled back transaction' );

done_testing();

# A row the claim function answers, running and this worker's.
sub _row ( $id, $attempts = 0, $payload = { event_id => "event-$id" } ) {
    return {
        attempt_count   => $attempts,
        created_at      => $NOW,
        locked_by       => 'pg-worker',
        next_attempt_at => $NOW,
        outbox_id       => $id,
        payload         => $payload,
        status          => 'running',
    };
}

sub _dispatcher ( $functions, $transport, %options ) {
    return GPForum::Service::Outbox::Dispatcher->new(
        clock      => GPForum::Test::OutboxClock->new,
        functions  => $functions,
        id_service => GPForum::Test::Id->new,
        schema     => {},
        transport  => $transport,
        worker_id  => 'pg-worker',
        %options,
    );
}

# The changes of the write of a kind (renew, or the status written) made to
# a message.
sub _changes ( $functions, $id, $kind ) {
    my ($write) = grep {
             $_->[0] eq 'outbox_owned_write'
          && $_->[1]{outbox_id} eq $id
          && (
            $kind eq 'renew'
            ? !exists $_->[1]{changes}{status}
            : ( $_->[1]{changes}{status} // q{} ) eq $kind
          )
    } @{ $functions->calls };

    return $write ? $write->[1]{changes} : {};
}

1;
