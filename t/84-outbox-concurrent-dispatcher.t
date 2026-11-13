# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Carp qw(croak);
use Const::Fast;
use JSON::MaybeXS qw(decode_json);
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Service::Outbox::Dispatcher;
use GPForum::Test::Id;
use GPForum::Test::OutboxClock;
use GPForum::Test::OutboxFunctions;
use GPForum::Test::OutboxTransport;

our $VERSION = '0.001';

const my $READY_AT       => '2026-05-23T12:00:00Z';
const my $FUTURE_LOCK    => '2026-05-23T12:01:00Z';
const my $BENCH_MESSAGES => 12;
const my $BENCH_BATCHES  => 4;

# Which rows a claim takes -- every ready message delivered once by a pool
# of workers, disjoint claims, a stale lock taken over and a fresh one left,
# a crash between the claim and the dispatch -- is api.outbox_claim_ready's,
# stated on PostgreSQL in t/integration/postgres-outbox-dispatcher.t and
# t/integration/postgres-outbox-reclaim.t. Here: what the dispatcher writes
# for a retryable failure, and the benchmark over the shared queue.

_assert_retry_backoff();
_assert_benchmark_json_smoke();

done_testing();

sub _assert_retry_backoff {
    my $functions = GPForum::Test::OutboxFunctions->new(
        claimed_rows => [
            {
                attempt_count   => 0,
                created_at      => $READY_AT,
                locked_by       => 'retry-worker',
                next_attempt_at => $READY_AT,
                outbox_id       => 'retry-1',
                payload         => {},
                status          => 'running',
            }
        ]
    );
    my $transport =
      GPForum::Test::OutboxTransport->new( fail_ids => { 'retry-1' => 1 } );
    my $summary = GPForum::Service::Outbox::Dispatcher->new(
        clock      => GPForum::Test::OutboxClock->new,
        functions  => $functions,
        id_service => GPForum::Test::Id->new,
        schema     => {},
        transport  => $transport,
        worker_id  => 'retry-worker',
    )->dispatch_pending(1);
    my ($failed) =
      map  { $_->[1]{changes} }
      grep { ( $_->[1]{changes}{status} // q{} ) eq 'failed' }
      @{ $functions->calls };

    is( $summary->{failed}, 1, 'retryable failure is counted' );
    is( $summary->{dead_lettered}, 0,
        'retryable failure is not dead-lettered' );
    is_deeply(
        $functions->writes('retry-worker'),
        [qw(renew:retry-1 failed:retry-1)],
        'retryable row remains failed'
    );
    is( $failed->{attempt_count}, 1, 'retryable row increments attempt count' );
    is( $failed->{next_attempt_at},
        $FUTURE_LOCK, 'retryable row schedules backoff' );
    is( scalar @{ $functions->letters },
        0, 'retryable row does not create a dead letter' );

    return;
}

sub _assert_benchmark_json_smoke {
    my $output = _capture_command( 'script/bench-outbox-dispatcher',
        '--messages', '12', '--workers', '1,2', '--batch-size', '3',
        '--json', );
    my $report = decode_json($output);

    is( $report->{status}, 'ok', 'outbox benchmark reports ok status' );
    is( scalar @{ $report->{results} },
        2, 'outbox benchmark covers requested worker matrix' );
    is( $report->{results}[0]{duplicates},
        0, 'outbox benchmark reports zero duplicates' );
    is( $report->{results}[0]{lost},
        0, 'outbox benchmark reports zero lost messages' );
    ok(
        exists $report->{results}[0]{p95_claim_ms},
        'outbox benchmark reports claim latency'
    );

    # Twelve messages in batches of three: four batches claimed, and twelve
    # acknowledgements -- one a message, not one a batch, which is what the
    # field called ack_batches stopped counting.
    is( $report->{results}[0]{claimed_batches},
        $BENCH_BATCHES, 'outbox benchmark reports the batches claimed' );
    is( $report->{results}[0]{acknowledged},
        $BENCH_MESSAGES, 'and every message acknowledged' );
    ok(
        !exists $report->{results}[0]{ack_batches},
        'under names that say what they count'
    );
    like(
        _capture_command(
            'script/bench-outbox-dispatcher',
            '--messages', '12', '--workers', '1', '--batch-size', '3'
        ),
        qr/[ ] acknowledged=12 [ ] claimed_batches=4 [ ]/msx,
        'and so does the line'
    );

    return;
}

sub _capture_command {
    my (@command) = @_;

    open my $handle, q{-|}, @command
      or croak 'failed to run outbox benchmark';

    my $captured = q{};
    while ( my $line = <$handle> ) {
        $captured .= $line;
    }

    close $handle
      or croak 'outbox benchmark failed';

    return $captured;
}

1;
