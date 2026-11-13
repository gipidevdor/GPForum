# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use JSON::MaybeXS qw(encode_json);
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Infrastructure::Id;
use GPForum::Service::Outbox::ClaimedMessage;
use GPForum::Service::Outbox::DeadLetterRecorder;
use GPForum::Service::Outbox::Dispatcher;
use GPForum::Test::OutboxClock;
use GPForum::Test::OutboxTransport;
use GPForum::Test::PgDatabase;
use GPForum::Test::ScriptedId;

our $VERSION = '0.001';

const my @WORKER_COUNTS => ( 2, 4, 8 );
const my $BATCH_SIZE    => 3;
const my $MESSAGE_COUNT => 24;
const my $READY         => '2026-05-23T11:59:00Z';
const my $INSERT_SQL => join q{ },
  'INSERT INTO outbox_messages (outbox_id, event_id, queue, job_type,',
  'idempotency_key, payload, available_at, created_at, status,',
  'next_attempt_at, attempt_count)',
  q{VALUES (?, ?, 'domain', 'test.dispatch', ?, ?::jsonb, ?::timestamptz,},
  q{?::timestamptz, 'pending', ?::timestamptz, ?)};
const my $ROW_SQL =>
  'SELECT status, attempt_count FROM outbox_messages WHERE outbox_id = ?';
const my $LETTER_SQL => join q{ },
  'SELECT dead_letter_id, source_table, retry_count, failure_type,',
  'payload::text AS payload FROM dead_letters WHERE source_id = ?';
const my $LETTERS_SQL => 'SELECT count(*) FROM dead_letters';

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'set GPFORUM_TEST_DSN to run against PostgreSQL';
}

# What the dispatcher's unit tests (t/13-outbox-dispatcher.t,
# t/84-outbox-concurrent-dispatcher.t) leave to api.outbox_claim_ready and
# api.outbox_dead_letter, stated on PostgreSQL: which rows a claim takes,
# and a dead letter written once.

my $database = GPForum::Test::PgDatabase->fresh;
my $schema   = $database->schema;
my $ids      = GPForum::Infrastructure::Id->new;

for my $worker_count (@WORKER_COUNTS) {
    _pool_delivers_once($worker_count);
    _claim_wave_is_unique($worker_count);
}
_claim_takes_the_oldest_first();
_exhausted_message_is_dead_lettered_once();
_recorded_message_is_skipped();
_taken_letter_id_is_minted_again();

done_testing();

sub _pool_delivers_once {
    my ($worker_count) = @_;

    _clear();
    my %name =
      map { _insert("pool-$worker_count-$_") => $_ } 1 .. $MESSAGE_COUNT;
    my $transport = GPForum::Test::OutboxTransport->new;
    my @workers =
      map { _dispatcher( $transport, "worker-$_" ) } 1 .. $worker_count;

    while (1) {
        my $selected = 0;
        for my $worker (@workers) {
            $selected += $worker->dispatch_pending($BATCH_SIZE)->{selected};
        }
        last if !$selected;
    }

    is( scalar @{ $transport->delivered },
        $MESSAGE_COUNT, "$worker_count workers deliver every ready message" );
    is( _duplicates( $transport->delivered ),
        0, "$worker_count workers produce zero duplicate deliveries" );
    is( scalar( grep { $name{$_} } @{ $transport->delivered } ),
        $MESSAGE_COUNT, 'and deliver only the messages of the queue' );

    return;
}

sub _claim_wave_is_unique {
    my ($worker_count) = @_;

    _clear();
    for my $position ( 1 .. $MESSAGE_COUNT ) {
        _insert("claim-$worker_count-$position");
    }
    my $transport = GPForum::Test::OutboxTransport->new;
    my @claimed   = map { $_->claim_ready_batch($BATCH_SIZE) }
      map { _dispatcher( $transport, "worker-$_" ) } 1 .. $worker_count;

    is(
        scalar @claimed,
        $worker_count * $BATCH_SIZE,
        "$worker_count workers claim disjoint batches"
    );
    is( _duplicates( [ map { $_->get_column('outbox_id') } @claimed ] ),
        0, "$worker_count workers never claim the same outbox id" );

    return;
}

# The ready message due first is claimed first, whatever order it was
# written in.
sub _claim_takes_the_oldest_first {
    _clear();
    _insert( 'later', 0, '2026-05-23T11:59:30Z' );
    my $oldest = _insert( 'oldest', 0, '2026-05-23T11:58:00Z' );
    _insert( 'between', 0, '2026-05-23T11:59:00Z' );

    my @claimed =
      _dispatcher( GPForum::Test::OutboxTransport->new, 'worker-order' )
      ->claim_ready_batch(1);
    is_deeply( [ map { $_->get_column('outbox_id') } @claimed ],
        [$oldest], 'the claim takes the oldest ready message first' );
    is( _row($oldest)->{status}, 'running', 'and holds it' );

    return;
}

sub _exhausted_message_is_dead_lettered_once {
    _clear();
    my $failing = _insert( 'exhausted', 1 );
    my $transport =
      GPForum::Test::OutboxTransport->new( fail_ids => { $failing => 1 } );
    my $dispatcher = _dispatcher( $transport, 'worker-1', max_attempts => 2 );

    my $summary = $dispatcher->dispatch_pending(2);
    is( $summary->{dead_lettered}, 1,
        'the exhausted message is dead-lettered' );
    is_deeply(
        _row($failing),
        { status => 'cancelled', attempt_count => 2 },
        'its outbox row is cancelled with the attempt counted'
    );
    my $letter = _letter($failing);
    is( $letter->{source_table},
        'outbox_messages', 'the dead letter names its source table' );
    is( $letter->{retry_count},  2,           'and the retry count' );
    is( $letter->{failure_type}, 'transient', 'and the failure type' );
    like( $letter->{payload}, qr/"name":\s*"exhausted"/msx,
        'and keeps the payload' );

    my $again = $dispatcher->dispatch_pending(2);
    is( $again->{selected}, 0,
        'cancelled dead-lettered row is not claimed again' );
    is( $again->{dead_lettered}, 0,
        'cancelled row is not dead-lettered twice' );
    is( _value($LETTERS_SQL), 1, 'dead letter remains a single review row' );

    return;
}

# A message another worker recorded first: nothing is written, and the
# answer says so.
sub _recorded_message_is_skipped {
    _clear();
    my $message = _message( _insert('recorded') );
    my $first   = _recorder()->create_dead_letter( $message, _failure() );
    ok( !$first->{skipped}, 'the first dead letter is written' );

    my $again = _recorder()->create_dead_letter( $message, _failure() );
    is_deeply(
        $again,
        { skipped => 1 },
        'already-recorded dead letter is skipped'
    );
    is( _value($LETTERS_SQL), 1,
        'already-recorded dead letter does not insert another row' );

    return;
}

# The id drawn for a letter is already another letter's: the function mints
# it again and records this message.
sub _taken_letter_id_is_minted_again {
    _clear();
    my $taken = $ids->uuid;
    _recorder($taken)
      ->create_dead_letter( _message( _insert('other-source') ), _failure() );

    my $source = _insert('this-source');
    my $letter =
      _recorder($taken)->create_dead_letter( _message($source), _failure() );
    ok( !$letter->{skipped},
        'unique dead-letter id collision remints and records' );
    isnt( $letter->{dead_letter_id},
        $taken, 'unique dead-letter id collision remints the id' );
    is( $letter->{source_id}, $source,
        'unique dead-letter id collision keeps this source' );
    is(
        _letter($source)->{dead_letter_id},
        $letter->{dead_letter_id},
        'under the id it answers'
    );
    is( _value($LETTERS_SQL), 2,
        'unique dead-letter id collision inserts this review row' );

    return;
}

sub _dispatcher ( $transport, $worker_id, %options ) {
    return GPForum::Service::Outbox::Dispatcher->new(
        clock     => GPForum::Test::OutboxClock->new,
        schema    => $schema,
        transport => $transport,
        worker_id => $worker_id,
        %options,
    );
}

sub _recorder (@next_ids) {
    return GPForum::Service::Outbox::DeadLetterRecorder->new(
        clock      => GPForum::Test::OutboxClock->new,
        id_service => GPForum::Test::ScriptedId->new( next_ids => \@next_ids ),
        schema     => $schema,
    );
}

sub _message ($outbox_id) {
    return GPForum::Service::Outbox::ClaimedMessage->new(
        row => { outbox_id => $outbox_id, payload => { event_id => 'e' } } );
}

sub _failure {
    return {
        attempt_count => 2,
        error_class   => 'transport',
        error_message => 'failed',
        failure_type  => 'transient',
    };
}

# A ready message named $name; answers its id.
sub _insert ( $name, $attempts = 0, $due = $READY ) {
    my $outbox_id = $ids->uuid;
    $schema->storage->dbh->do( $INSERT_SQL, undef, $outbox_id, $ids->uuid,
        "key-$name", encode_json( { name => $name } ),
        $due, $due, $due, $attempts );

    return $outbox_id;
}

sub _clear {
    $schema->storage->dbh->do('DELETE FROM dead_letters');
    $schema->storage->dbh->do('DELETE FROM outbox_messages');

    return;
}

sub _row ($outbox_id) {
    return $schema->storage->dbh->selectrow_hashref( $ROW_SQL, undef,
        $outbox_id );
}

sub _letter ($source_id) {
    return $schema->storage->dbh->selectrow_hashref( $LETTER_SQL, undef,
        $source_id );
}

sub _value ( $sql, @bind ) {
    my ($value) = $schema->storage->dbh->selectrow_array( $sql, undef, @bind );

    return $value;
}

sub _duplicates ($values) {
    my %seen;

    return scalar grep { $seen{$_}++ } @{$values};
}

1;
