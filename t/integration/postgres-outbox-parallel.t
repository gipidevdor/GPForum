# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package main;
use v5.40;
use Test::More;
use Const::Fast;
use Carp          qw(croak);
use File::Temp    qw(tempdir);
use JSON::MaybeXS qw(decode_json);
use Digest::SHA   qw(sha256);
use English       qw(-no_match_vars);
use lib 'lib', 't/lib';
use GPForum::Infrastructure::Id;
use GPForum::Infrastructure::EventRecorder;
use GPForum::Service::Outbox::Dispatcher;
use GPForum::Test::PgDatabase;
use GPForum::Test::Promise qw(await_result);
use GPForum::Test::FileOutboxTransport;
our $VERSION = '0.001';
const my $BATCH_SIZE    => 100;
const my $PER_AGGREGATE => 4;
const my $MESSAGES      => 8;

const my $DIGEST_BYTES => 4;

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'temporary PostgreSQL required';
}
my $database = GPForum::Test::PgDatabase->fresh;
my $ids      = GPForum::Infrastructure::Id->new;
my $recorder =
  GPForum::Infrastructure::EventRecorder->new( schema => $database->schema );
my %aggregate;

while ( keys %aggregate < 2 ) {
    my $id     = $ids->uuid;
    my $digest = sha256("thread:$id");
    my $prefix = substr $digest, 0, $DIGEST_BYTES;
    my $bucket = unpack 'N', $prefix;
    my $lane   = $bucket % 2;
    $aggregate{$lane} //= $id;
}
for my $sequence ( 1 .. $PER_AGGREGATE ) {
    for my $aggregate ( values %aggregate ) {
        $recorder->record_event(
            event_type        => 'thread.updated',
            aggregate_type    => 'thread',
            aggregate_id      => $aggregate,
            aggregate_version => $sequence,
            correlation_id    => $ids->uuid,
            idempotency_key   => "parallel:$aggregate:$sequence",
            payload           => { sequence => $sequence }
        );
    }
}

# Database defaults have subsecond precision; the worker's clock has seconds.
# Make the fixture due explicitly rather than waiting for the next second.
$database->dbh->do(
    (
        join q{ },
        q{UPDATE public.outbox_messages},
        q{SET available_at = '2026-05-23T12:00:00Z',},
        q{next_attempt_at = '2026-05-23T12:00:00Z'}
    )
);
my $directory  = tempdir( CLEANUP => 1 );
my $path       = "$directory/deliveries.jsonl";
my $dispatcher = GPForum::Service::Outbox::Dispatcher->new(
    schema    => $database->schema,
    transport => GPForum::Test::FileOutboxTransport->new( path => $path ),
    worker_id => 'parallel-integration',

);
my $summary = await_result( $dispatcher->dispatch_pending_p( $BATCH_SIZE, 2 ) );
is( $summary->{selected},   $MESSAGES, 'one batch claims all messages' );
is( $summary->{dispatched}, $MESSAGES, 'all messages dispatched' );
is( $summary->{acknowledged},
    $MESSAGES, 'all claims acknowledged individually' );
is( $summary->{failed}, 0, 'no delivery failed' );
open my $file, '<', $path or croak $OS_ERROR;
my @delivered = map { decode_json($_) } <$file>;
close $file or croak $OS_ERROR;
is( scalar @delivered, $MESSAGES, 'every delivery is recorded once' );
my %pids = map { $_->{pid} => 1 } @delivered;
is( scalar keys %pids, 2, 'two actual subprocesses handle independent lanes' );
ok( !exists $pids{$PROCESS_ID},
    'blocking dispatch runs outside the parent event loop' );

for my $aggregate ( values %aggregate ) {
    is_deeply(
        [
            map  { $_->{sequence} }
            grep { $_->{aggregate} eq $aggregate } @delivered
        ],
        [ 1 .. $PER_AGGREGATE ],
        'each aggregate retains event order'
    );
}
my $again = await_result( $dispatcher->dispatch_pending_p( $BATCH_SIZE, 2 ) );
is( $again->{selected}, 0, 'acknowledged messages are not dispatched again' );
done_testing;
1;
