# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Command::Migrate;
use GPForum::Infrastructure::EventRecorder;
use GPForum::Infrastructure::Id;
use GPForum::Service::Admin::CategoryStore;
use GPForum::Test::PostgresHarness;
use GPForum::Test::ScriptedId;

our $VERSION = '0.001';

const my $ACTOR => '018f1000-0000-7000-8000-00000000e001';

if ( !$ENV{GPFORUM_DATABASE_DSN} ) {
    plan skip_all => 'set GPFORUM_DATABASE_DSN to run the event recorder test';
}

# Recording an event whose event_id is already stored -- a retried write after
# a crash between the event and its outbox row -- must reuse the stored event
# and leave exactly one event and one outbox row. The path read the stored row
# as a hash, which only the test doubles return: against PostgreSQL it saw no
# columns and tried to insert an outbox row with no event.
my $database =
  GPForum::Test::PostgresHarness::create_database( $ENV{GPFORUM_DATABASE_DSN} );
local $ENV{GPFORUM_DATABASE_DSN} = $database->{dsn};
GPForum::Test::PostgresHarness::quietly(
    sub { return GPForum::Command::Migrate->new->run('--apply') } );

my $schema   = GPForum::Test::PostgresHarness::connect_schema();
my $dbh      = $schema->storage->dbh;
my $id       = GPForum::Infrastructure::Id->new;
my $recorder = GPForum::Infrastructure::EventRecorder->new(
    id_service => $id,
    schema     => $schema,
);
my $event_id  = $id->uuid;
my $aggregate = $id->uuid;
my %event     = (
    actor_id          => $ACTOR,
    aggregate_id      => $aggregate,
    aggregate_type    => 'category',
    aggregate_version => 1,
    event_id          => $event_id,
    event_type        => 'category.updated',
    idempotency_key   => "category.updated:$aggregate",
    payload           => { category_id => $aggregate },
);

my $first = $recorder->record_event(%event);
is( $first->{event_id}, $event_id, 'the event is recorded' );

my $again = $recorder->record_event(%event);
ok( $again->{skipped}, 'recording it again reuses the stored event' );
is( $again->{event_id}, $event_id, 'and returns it' );

$dbh->do( 'DELETE FROM outbox_messages WHERE event_id = ?', undef, $event_id );
my $recovered = $recorder->record_event(%event);
ok( $recovered->{skipped}, 'an event whose outbox row is missing is reused' );
is(
    scalar $dbh->selectrow_array(
        'SELECT count(*) FROM outbox_messages WHERE event_id = ?', undef,
        $event_id
    ),
    1,
    'and gets its outbox row back'
);
is(
    scalar $dbh->selectrow_array(
        'SELECT count(*) FROM event_log WHERE event_id = ?', undef,
        $event_id
    ),
    1,
    'with still one event'
);

# ADR 0110's append_once: a write whose row was stored but whose event was
# lost records the event when the command is replayed -- once, and only
# then. Six stores share EventRecorder::event_recorded for that lookup.
ok(
    $recorder->event_recorded("category.updated:$aggregate"),
    'event_recorded finds an event by its idempotency key'
);
ok( !$recorder->event_recorded("category.updated:$event_id"),
    'and not one that was never recorded' );

$dbh->do(
    q{INSERT INTO users (id, username, display_name, email_normalized,}
      . q{ password_hash, status) VALUES (?, 'recorder-admin', 'Recorder',}
      . q{ 'recorder@example.test', 'x', 'active') ON CONFLICT DO NOTHING},
    undef, $ACTOR
);
my $store = GPForum::Service::Admin::CategoryStore->new( schema => $schema );
my %input = ( actor_user_id => $ACTOR, title => 'Event recorder board' );
my $key =
  'category.created:' . $store->create_category( {%input} )->{category_id};
$dbh->do(
    'DELETE FROM outbox_messages WHERE event_id IN'
      . ' (SELECT event_id FROM event_log WHERE idempotency_key = ?)',
    undef, $key
);
$dbh->do( 'DELETE FROM event_log WHERE idempotency_key = ?', undef, $key );
ok( !$recorder->event_recorded($key),
    'a category whose event is lost, as in a crash' );
ok(
    $store->create_category( {%input} )->{idempotent},
    'repeating the command reuses the stored category'
);
is( _events($key), 1, 'and records the lost event' );
$store->create_category( {%input} );
is( _events($key), 1, 'only once' );

# The conflicts api.ops_record_event and api.ops_record_audit resolve
# themselves, raised on purpose: the recorder is handed an id already
# stored (ADR 0116, ADR 0156).
my $ids      = GPForum::Test::ScriptedId->new;
my $scripted = GPForum::Infrastructure::EventRecorder->new(
    id_service => $ids,
    schema     => $schema,
);

# An outbox id another event's row holds is drawn again.
my ($held) =
  $dbh->selectrow_array(
    'SELECT outbox_id FROM outbox_messages' . ' WHERE event_id = ?',
    undef, $event_id );
my $reminted_id = $id->uuid;
$ids->next_ids( [$held] );
my $reminted = $scripted->record_event(
    %event,
    correlation_id  => $id->uuid,
    event_id        => $reminted_id,
    idempotency_key => "category.updated:$reminted_id",
);
ok( !$reminted->{skipped}, 'an event whose outbox id is taken is recorded' );
my ($drawn) =
  $dbh->selectrow_array(
    'SELECT outbox_id FROM outbox_messages' . ' WHERE event_id = ?',
    undef, $reminted_id );
ok( $drawn && $drawn ne $held, 'with an outbox id drawn again' );
is( _outbox_rows( 'outbox_id = ?', $held ),
    1, 'beside the row that holds the taken one' );

# An outbox row left under the event's key -- the event itself lost -- is
# the event's handoff: the event is written again, its message is not.
my $handed = $id->uuid;
my %handed = (
    %event,
    event_id        => $handed,
    idempotency_key => "category.updated:$handed",
);
$recorder->record_event(%handed);
$dbh->do( 'DELETE FROM event_log WHERE event_id = ?', undef, $handed );
my $rewritten = $recorder->record_event(%handed);
ok( !$rewritten->{skipped},
    'an event whose outbox row outlived it is written again' );
is( _outbox_rows( 'event_id = ?', $handed ),
    1, 'and keeps the one outbox row its key names' );

# An audit id the recorder draws itself, already stored at the same time,
# meets the primary key: the record is written under an id drawn again.
my $audit_id = $id->uuid;
my %audit    = (
    action         => 'test.recorder_conflict',
    actor_id       => $ACTOR,
    correlation_id => $id->uuid,
    created_at     => '2026-11-02T10:00:00Z',
    metadata       => { case => 'audit id drawn twice' },
    target_id      => $aggregate,
    target_type    => 'category',
);
$recorder->record_audit( %audit, audit_id => $audit_id );
$ids->next_ids( [$audit_id] );
my $redrawn = $scripted->record_audit(%audit);
isnt( $redrawn->{audit_id}, $audit_id,
    'an audit id drawn by the recorder and already stored is drawn again' );
is(
    scalar $dbh->selectrow_array(
        'SELECT count(*) FROM audit_log WHERE audit_id = ?', undef,
        $audit_id
    ),
    1,
    'and stored once'
);
ok(
    $scripted->verify_audit_record($redrawn),
    'and the record under the new id verifies'
);
is_deeply( $recorder->verify_audit_chain( 'category', $aggregate ),
    [], 'and its chain is whole' );

$dbh->disconnect;
GPForum::Test::PostgresHarness::drop_database($database);

done_testing();

sub _outbox_rows {
    my ( $where, @binds ) = @_;

    return
      scalar $dbh->selectrow_array(
        "SELECT count(*) FROM outbox_messages WHERE $where",
        undef, @binds );
}

sub _events {
    my ($idempotency_key) = @_;

    return
      scalar $dbh->selectrow_array(
        'SELECT count(*) FROM event_log WHERE idempotency_key = ?',
        undef, $idempotency_key );
}

1;
