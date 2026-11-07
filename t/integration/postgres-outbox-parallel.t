# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package main;
use v5.40;
use Test::More;
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
plan skip_all => 'temporary PostgreSQL required'
  if !GPForum::Test::PgDatabase->admin_dsn;
my $database = GPForum::Test::PgDatabase->fresh;
my $ids      = GPForum::Infrastructure::Id->new;
my $recorder =
  GPForum::Infrastructure::EventRecorder->new( schema => $database->schema );
my %aggregate;

while ( keys %aggregate < 2 ) {
    my $id   = $ids->uuid;
    my $lane = unpack( 'N', substr( sha256("thread:$id"), 0, 4 ) ) % 2;
    $aggregate{$lane} //= $id;
}
for my $sequence ( 1 .. 4 ) {
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
    q{
    UPDATE public.outbox_messages
    SET available_at = '2026-05-23T12:00:00Z',
        next_attempt_at = '2026-05-23T12:00:00Z'
}
);
my $directory  = tempdir( CLEANUP => 1 );
my $path       = "$directory/deliveries.jsonl";
my $dispatcher = GPForum::Service::Outbox::Dispatcher->new(
    schema    => $database->schema,
    transport => GPForum::Test::FileOutboxTransport->new( path => $path ),
    worker_id => 'parallel-integration'
);
my $summary = await_result( $dispatcher->dispatch_pending_p( 100, 2 ) );
is( $summary->{selected},     8, 'one batch claims all messages' );
is( $summary->{dispatched},   8, 'all messages dispatched' );
is( $summary->{acknowledged}, 8, 'all claims acknowledged individually' );
is( $summary->{failed},       0, 'no delivery failed' );
open my $file, '<', $path or die $OS_ERROR;
my @delivered = map { decode_json($_) } <$file>;
close $file or die $OS_ERROR;
is( scalar @delivered, 8, 'every delivery is recorded once' );
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
        [ 1, 2, 3, 4 ],
        'each aggregate retains event order'
    );
}
my $again = await_result( $dispatcher->dispatch_pending_p( 100, 2 ) );
is( $again->{selected}, 0, 'acknowledged messages are not dispatched again' );
done_testing;
1;
