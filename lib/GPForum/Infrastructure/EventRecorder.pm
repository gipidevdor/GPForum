# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Infrastructure::EventRecorder;

use Const::Fast;
use JSON::MaybeXS;
use Mojo::Base 'GPForum::Base', -signatures;
use v5.40;

use GPForum::Domain::EventEnvelope;
use GPForum::Infrastructure::AuditRecord;
use GPForum::Infrastructure::OutboxMessageBuilder;
use GPForum::Infrastructure::Storage;
use GPForum::Infrastructure::UniqueConflict;
use GPForum::X::Conflict;

use GPForum::Infrastructure::SqlFunction;

our $VERSION = '0.001';

has functions => sub ($self) {
    return GPForum::Infrastructure::SqlFunction->for_schema( $self->schema );
};

const my $DEFAULT_SCHEMA_VERSION => 1;
const my $EVENT_ID_LOCK_CLASS    => 2_026_100_310;
const my $AUDIT_ID_LOCK_CLASS    => 2_026_100_311;
const my $AUDIT_CHAIN_LOCK_CLASS => 2_026_102_401;
const my $ROW_LIMIT_ONE          => 1;
const my $OUTBOX_ID_CONSTRAINT   => 'outbox_messages_pkey';
const my $OUTBOX_KEY_CONSTRAINT  => 'outbox_messages_idempotency_key_key';
const my $AUDIT_ID_CONSTRAINT    => 'audit_log_pkey';
const my $EVENT_ID_CONSTRAINT    => 'event_log_pkey';

# Two int4 keys: the class names the lock, hashtext the id or the chain key.
# Two values that hash alike only wait for each other.
const my $HASHED_LOCK_SQL =>
  'SELECT pg_advisory_xact_lock(?, hashtext(?::text))';

has envelope   => sub { return GPForum::Domain::EventEnvelope->new; };
has id_service => sub {
    require GPForum::Infrastructure::Id;
    return GPForum::Infrastructure::Id->new;
};
has outbox_builder => sub {
    my ($self) = @_;

    return GPForum::Infrastructure::OutboxMessageBuilder->new(
        id_service => $self->id_service, );
};
__PACKAGE__->requires(qw(schema));
has json => sub { return JSON::MaybeXS->new( canonical => 1, utf8 => 1 ); };
has audit_record => sub {
    my ($self) = @_;

    return GPForum::Infrastructure::AuditRecord->new(
        id_service => $self->id_service,
        json       => $self->json,
    );
};

sub record_event ( $self, %input ) {
    if ( $self->functions ) {
        return $self->functions->row( 'ops_record_event',
            $self->event_call(%input) )->{event};
    }
    my $outbox_payload = delete $input{outbox_payload};
    my $event          = $self->_recorded_event( \%input );
    if ( !$self->audit_record->has_text( $input{event_id} ) ) {
        return $self->_reuse_or_insert_event( $event, $outbox_payload );
    }

    return $self->_in_transaction(
        sub {
            $self->_lock_event_id( $event->{event_id} );

            return $self->_reuse_or_insert_event( $event, $outbox_payload );
        }
    );
}

# ADR 0116. event_log_pkey is (event_id, created_at), so an event stored
# under this id at another time is no conflict for the insert: only the
# lookup by id, which reads every partition, finds it. A caller's own id can
# be written by another worker at the same moment, each at its own clock;
# both lookups would miss the other's uncommitted row and both inserts
# would succeed. The lock, held to the end of the transaction, puts the
# second lookup after the first commit; at READ COMMITTED, which every
# transaction here runs at, that lookup is a statement of its own and sees
# the commit. An id minted here is known to no one else and needs neither.
sub _lock_event_id ( $self, $event_id ) {
    my $dbh = GPForum::Infrastructure::Storage->dbh_of( $self->schema );
    if ( !$dbh ) {
        return;
    }

    $dbh->selectrow_array( $HASHED_LOCK_SQL, undef, $EVENT_ID_LOCK_CLASS,
        $event_id );

    return;
}

# Whether the log holds an event with this idempotency key. A command that
# stored its row and failed before its event was recorded finishes, on
# replay, by recording the event -- once, and only if this says it is
# missing. ADR 0091's append_once: six stores each had their own copy.
sub event_recorded ( $self, $idempotency_key ) {
    if ( $self->functions ) {
        return $self->functions->row( 'ops_event_recorded',
            { key => $idempotency_key } )->{recorded} ? 1 : 0;
    }
    my $search = $self->schema->resultset('EventLog')->search_rs(
        { idempotency_key => $idempotency_key },
        { rows            => $ROW_LIMIT_ONE },
    );

    return _first_row($search) ? 1 : 0;
}

sub _recorded_event ( $self, $input ) {
    return $self->envelope->record(
        %{$input},
        correlation_id => $input->{correlation_id} || $self->id_service->uuid,
        event_id       => $input->{event_id}       || $self->id_service->uuid,
        schema_version => $input->{schema_version} || $DEFAULT_SCHEMA_VERSION,
        timestamp => $input->{timestamp} || $self->audit_record->now_iso8601,
    );
}

sub _reuse_or_insert_event ( $self, $event, $outbox_payload ) {
    my $existing = $self->_existing_event($event);
    if ($existing) {
        $self->_ensure_outbox( $existing, $outbox_payload );

        return _skipped_event($existing);
    }

    my $stored = $self->_insert_or_retry_event($event);
    $self->_ensure_outbox( $stored, $outbox_payload );

    return $stored;
}

# event_log and audit_log are partitioned by created_at, and PostgreSQL names
# the partition's index in the conflict (event_log_default_pkey,
# audit_log_2026_10_pkey), never the table's constraint: the conflict's `on`
# reads the partitions' indexes from the catalog. Matched on the table's
# constraint alone, every collision on PostgreSQL was rethrown -- a raced
# event was not reused and a colliding audit id was not minted again.
sub _insert_or_retry_event ( $self, $event ) {
    my ( $created, $error ) =
      GPForum::Infrastructure::UniqueConflict->attempt( $self->schema,
        sub { return $self->_insert_event($event); },
      );
    if ($created) {
        return $created;
    }

    my $conflict = GPForum::X::Conflict->caught($error);
    if ( !$conflict || !$conflict->on($EVENT_ID_CONSTRAINT) ) {
        GPForum::Infrastructure::UniqueConflict->rethrow($error);
    }

    my $stored = $self->_existing_event($event);
    if ( _same_open_event( $stored, $event ) ) {
        return _skipped_event($stored);
    }

    my $retry = $self->_event_with_new_id($event);

    return $self->_once_more( sub { return $self->_insert_event($retry); } );
}

sub _insert_event ( $self, $event ) {
    $self->schema->resultset('EventLog')->create($event);

    return $event;
}

# The insert tried once more, after a collision on an id minted here: a
# second collision on a fresh id is no race to recover from, and is raised.
sub _once_more ( $self, $code ) {
    my ( $created, $error ) =
      GPForum::Infrastructure::UniqueConflict->attempt( $self->schema, $code );
    if ($created) {
        return $created;
    }

    GPForum::Infrastructure::UniqueConflict->rethrow($error);
}

# The stored event is the same open event when both carry the same
# idempotency key.
sub _same_open_event ( $stored, $event ) {
    my $stored_key = _event_hash($stored)->{idempotency_key};
    my $key        = $event->{idempotency_key};
    if ( !defined $stored_key || !defined $key ) {
        return 0;
    }

    return $stored_key eq $key ? 1 : 0;
}

sub _event_with_new_id ( $self, $event ) {
    my $event_id = $self->id_service->uuid;
    my $metadata = ref $event->{metadata} eq 'HASH' ? $event->{metadata} : {};

    return {
        %{$event},
        event_id => $event_id,
        metadata => { %{$metadata}, event_id => $event_id },
    };
}

# A collision on the outbox id is a raced write of the same message or an
# id minted twice; one on the idempotency key is the same message written by
# someone else first. Both take the stored row when there is one.
sub _ensure_outbox ( $self, $event, $outbox_payload ) {
    my $existing = $self->_existing_outbox($event);
    if ($existing) {
        return $existing;
    }

    my ( $created, $error ) =
      GPForum::Infrastructure::UniqueConflict->attempt( $self->schema,
        sub { return $self->_insert_outbox( $event, $outbox_payload ); },
      );
    if ($created) {
        return $created;
    }

    my $conflict = GPForum::X::Conflict->caught($error);
    if ( !$conflict ) {
        GPForum::Infrastructure::UniqueConflict->rethrow($error);
    }

    my $on_id = $conflict->on($OUTBOX_ID_CONSTRAINT);
    if ( !$on_id && !$conflict->on($OUTBOX_KEY_CONSTRAINT) ) {
        GPForum::Infrastructure::UniqueConflict->rethrow($error);
    }

    $existing = $self->_existing_outbox($event);
    if ($existing) {
        return $existing;
    }

    # A key taken by a row that is gone again by the time it is looked up:
    # nothing to reuse, and a fresh outbox id would collide on the key too.
    # The server's own conflict is raised, with the key's value in its text.
    if ( !$on_id ) {
        GPForum::Infrastructure::UniqueConflict->rethrow($error);
    }

    return $self->_once_more(
        sub { return $self->_insert_outbox( $event, $outbox_payload ); } );
}

sub _insert_outbox ( $self, $event, $outbox_payload ) {
    my $row = $self->outbox_builder->for_event( $event, $outbox_payload );
    $self->schema->resultset('OutboxMessage')->create($row);

    return $row;
}

# The stored event as the same hash a new one is: the reuse and outbox paths
# read its fields by key. They were handed the DBIx::Class row, whose fields
# are not hash keys -- only the test doubles returned hashes -- so against
# PostgreSQL a retried event looked empty and its outbox row was built with
# no event_id.
sub _existing_event ( $self, $event ) {
    my $row = $self->schema->resultset('EventLog')
      ->find( { event_id => $event->{event_id} } );
    return undef if !$row;
    return $row  if ref $row eq 'HASH';

    return { $row->get_inflated_columns };
}

sub _existing_outbox ( $self, $event ) {
    my $search = $self->schema->resultset('OutboxMessage')->search_rs(
        {
            idempotency_key =>
              GPForum::Infrastructure::OutboxMessageBuilder::idempotency_key_for(
                $event)
        },
        { rows => $ROW_LIMIT_ONE },
    );

    return _first_row($search);
}

sub _first_row ($search) {
    if ( $search && $search->can('single') ) {
        return $search->single;
    }

    return undef;
}

sub _skipped_event ($existing) {
    return { %{ _event_hash($existing) }, skipped => 1 };
}

sub _event_hash ($event) {
    if ( ref $event eq 'HASH' ) {
        return $event;
    }

    return {};
}

# What record_event sends to api.ops_record_event, prepared and not sent:
# the event as the envelope records it (its ids and time drawn here, in
# record_event's order), the outbox row's id, the outbox payload and whether
# the caller named the event's id. Public so a command that records the
# event in one call (api.identity_register_command) sends the same.
sub event_call ( $self, %input ) {
    my $outbox_payload = delete $input{outbox_payload};
    my $event          = $self->_recorded_event( \%input );
    return {
        event         => $event,
        outbox_id     => $self->outbox_builder->id_service->uuid,
        outbox_extras => $outbox_payload,
        explicit      => $self->audit_record->has_text( $input{event_id} ),
    };
}

# What record_audit sends to api.ops_record_audit, prepared and not sent.
sub audit_call ( $self, %input ) {
    return {
        audit    => $self->audit_record->build( \%input ),
        explicit => $self->audit_record->has_text( $input{audit_id} ),
    };
}

sub record_audit ( $self, %input ) {
    if ( $self->functions ) {
        return $self->functions->row( 'ops_record_audit',
            $self->audit_call(%input) )->{audit};
    }
    my $work = sub {
        $self->_lock_audit_chain(
            $self->audit_record->chain_key( @input{qw(target_type target_id)} )
        );

        return $self->_insert_or_retry_audit(
            $self->_audit_with_free_id( \%input ) );
    };

    return $self->_in_transaction($work);
}

# pg_advisory_xact_lock is released at the end of the holding transaction, so
# the lock, the reads it guards, and the insert have to share one. Callers
# already inside txn_do keep that transaction; autocommit callers get one here.
sub _in_transaction ( $self, $work ) {
    if ( $self->_needs_transaction ) {
        return $self->schema->txn_do($work);
    }

    return $work->();
}

# A schema without a transaction depth to read -- a test double -- gets none.
sub _needs_transaction ($self) {
    if ( !$self->schema->can('txn_do') ) {
        return 0;
    }

    my $storage = GPForum::Infrastructure::Storage->storage_of( $self->schema );
    if ( !blessed $storage || !$storage->can('txn_depth') ) {
        return 0;
    }

    my $depth;
    try {
        $depth = $storage->txn_depth;
    }
    catch ($error) {
        $depth = undef;
    };
    if ( !defined $depth ) {
        return 0;
    }

    return $depth ? 0 : 1;
}

# ADR 0116, as ADR 0156 amends it. audit_log_pkey is (audit_id, created_at):
# a caller's audit id already stored at another time is no conflict for the
# insert, and was written a second time. It is looked up by id in every
# partition, under a lock on that id, and taken as the conflict on the key
# is: as a collision, written under a new id. An id the record mints itself
# is known to no one else and is neither locked nor looked up.
sub _audit_with_free_id ( $self, $input ) {
    my $audit_id = $input->{audit_id};
    if ( !$self->audit_record->has_text($audit_id) ) {
        return $input;
    }
    $self->_lock_hashed( $AUDIT_ID_LOCK_CLASS, $audit_id );

    my $resultset = $self->schema->resultset('AuditLog');
    if ( !$resultset->can('search_rs') ) {
        return $input;
    }
    my $taken = _first_row(
        $resultset->search_rs(
            { audit_id => $audit_id },
            { columns  => ['audit_id'], rows => $ROW_LIMIT_ONE }
        )
    );

    return $taken ? { %{$input}, audit_id => $self->id_service->uuid } : $input;
}

sub _insert_or_retry_audit ( $self, $input ) {
    my ( $created, $error ) =
      GPForum::Infrastructure::UniqueConflict->attempt( $self->schema,
        sub { return $self->_insert_audit($input); },
      );
    if ($created) {
        return $created;
    }

    my $conflict = GPForum::X::Conflict->caught($error);
    if ( !$conflict || !$conflict->on($AUDIT_ID_CONSTRAINT) ) {
        GPForum::Infrastructure::UniqueConflict->rethrow($error);
    }

    my %retry = ( %{$input}, audit_id => $self->id_service->uuid );

    return $self->_once_more( sub { return $self->_insert_audit( \%retry ); } );
}

# ADR 0156: the row takes the next position in its target's chain and links
# to the row at the position before; what api.core_shared_append_audit_v1
# does on PostgreSQL, so the two paths write the same rows.
sub _insert_audit ( $self, $input ) {
    my $key =
      $self->audit_record->chain_key( @{$input}{qw(target_type target_id)} );
    my $tip   = $self->_audit_chain_tip($key);
    my $audit = $self->audit_record->build( $input, $tip->{record_hash} );
    $audit->{chain_key}      = $key;
    $audit->{chain_position} = ( $tip->{chain_position} // 0 ) + 1;
    $self->schema->resultset('AuditLog')->create($audit);

    return $audit;
}

sub verify_audit_record ( $self, $audit ) {
    return $self->audit_record->verify($audit);
}

# The flaws of one chain (ADR 0156), none for a sound one: each as
# api.ops_audit_chain_verify answers it, with the position and the audit id
# it is at. A schema without the function layer -- a test double -- has no
# chain to walk and answers none.
sub verify_audit_chain ( $self, $target_type, $target_id ) {
    return [] if !$self->functions;

    return $self->functions->rows(
        'ops_audit_chain_verify',
        {
            chain_key =>
              $self->audit_record->chain_key( $target_type, $target_id )
        }
    );
}

# The chain's lock, held to the end of the transaction, as the function
# takes it: writers of one aggregate wait for each other, no one else.
sub _lock_audit_chain ( $self, $key ) {
    $self->_lock_hashed( $AUDIT_CHAIN_LOCK_CLASS, $key );

    return;
}

sub _lock_hashed ( $self, $class, $value ) {
    my $dbh = GPForum::Infrastructure::Storage->dbh_of( $self->schema );
    if ( !$dbh ) {
        return;
    }

    $dbh->selectrow_array( $HASHED_LOCK_SQL, undef, $class, $value );

    return;
}

# The last row of one chain, { record_hash, chain_position }, or an empty
# hash for a chain with no row yet: among the rows this schema created (a
# test double's) first, then the stored ones.
sub _audit_chain_tip ( $self, $key ) {
    my $created = $self->_created_chain_tip($key);
    return $created if $created;

    my $resultset = $self->schema->resultset('AuditLog');
    if ( !$resultset->can('search') ) {
        return {};
    }
    my $latest = $resultset->search_rs( { chain_key => $key },
        { order_by => [ { -desc => 'chain_position' } ], rows => 1 } )->single;

    return $latest ? $self->_chain_tip_of($latest) : {};
}

sub _created_chain_tip ( $self, $key ) {
    if ( !$self->schema->can('created_for') ) {
        return undef;
    }
    my @tips = sort { $a->{chain_position} <=> $b->{chain_position} }
      map  { $self->_chain_tip_of($_) }
      grep { ( $self->audit_record->column( $_, 'chain_key' ) // q{} ) eq $key }
      @{ $self->schema->created_for('AuditLog') };

    return @tips ? $tips[-1] : undef;
}

sub _chain_tip_of ( $self, $row ) {
    return {
        chain_position => $self->audit_record->column( $row, 'chain_position' )
          // 0,
        record_hash => $self->audit_record->column( $row, 'record_hash' ),
    };
}

1;

__END__

=head1 NAME

GPForum::Infrastructure::EventRecorder - Appends events with their outbox rows, and hash-chained audit records.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $recorder = GPForum::Infrastructure::EventRecorder->new(
        schema => $schema );
    $schema->txn_do(
        sub {
            # ... the command's own rows ...
            return if $recorder->event_recorded($idempotency_key);
            $recorder->record_event(
                event_type        => 'thread.created',
                aggregate_type    => 'thread',
                aggregate_id      => $thread_id,
                aggregate_version => 1,
                actor_id          => $user_id,
                idempotency_key   => $idempotency_key,
                payload           => { thread_id => $thread_id },
                timestamp         => $created_at,
            );
            $recorder->record_audit(
                action      => 'thread.created',
                actor_id    => $user_id,
                target_type => 'thread',
                target_id   => $thread_id,
                created_at  => $created_at,
            );
        }
    );

=head1 DESCRIPTION

The one writer of C<event_log>, of the C<outbox_messages> row each event
gets, and of C<audit_log>. The stores call it inside their command's
transaction, so the event, its outbox row and the audit record commit or
roll back with the command's own rows.

An event is shaped by L<GPForum::Domain::EventEnvelope>; its outbox row by
L<GPForum::Infrastructure::OutboxMessageBuilder>, keyed by the event so a
retry does not queue it twice. An event already stored under its
C<event_id> is not written again: it is returned with C<skipped> set, and
its outbox row is added if it is missing. A unique conflict on the insert
is taken back in a savepoint (L<GPForum::Infrastructure::UniqueConflict>)
and resolved by reading the row that won.

C<event_log>, C<audit_log> and C<notifications> are partitioned by
C<created_at>, and their primary keys are the id and that time, so the key
does not catch an id stored at another time; the lookup by id, which reads
every partition, does (ADR 0116). An C<event_id> the caller passes is
looked up under a transaction advisory lock on that id, so two workers
writing it at once at different times cannot both miss the other. An id
minted here is known to no one else and is neither locked nor raced.

An audit record is built by L<GPForum::Infrastructure::AuditRecord> and
belongs to the chain of its target (ADR 0156): C<chain_key> is
C<target_type:target_id>, C<chain_position> the next position in that
chain, and C<previous_hash> the C<record_hash> at the position before. The
chain's lock, C<pg_advisory_xact_lock(2026102401, hashtext(chain_key))>,
the read of its tip and the insert share one transaction, the caller's or
one opened here; writers of other aggregates do not wait. On PostgreSQL
C<api.ops_record_audit> does all of it in one call. An C<audit_id> the
caller passes is locked on its own (class 2026100311) and looked up; one
already stored, at any time, is a collision: the record is written under a
newly minted id, as it is after a conflict on the key.

=head1 SUBROUTINES/METHODS

=head2 event_call

Takes what L</record_event> takes and returns what it would send to
C<api.ops_record_event>, prepared and not sent: C<event>, the envelope's
record with its ids and time drawn here in C<record_event>'s order;
C<outbox_id>, the outbox row's id; C<outbox_extras>, the outbox payload;
and C<explicit>, whether the caller named the event's id. For a command
that records the event in one call with its other writes
(C<api.identity_register_command>).

=head2 verify_audit_chain

Takes a target type and a target id, the pair that names an aggregate's
chain (ADR 0156; C<undef> for both names the chain of the rows with no
target). Returns an array reference of the chain's flaws as
C<api.ops_audit_chain_verify> reports them, each with C<chain_position>,
C<audit_id> and C<problem>; empty for a sound chain. Without the function
layer (a test double) it is empty.

=head2 audit_call

Takes what L</record_audit> takes and returns what it would send to
C<api.ops_record_audit>, prepared and not sent: C<audit>, the record built,
and C<explicit>.

=head2 record_event

Takes the event's fields as a list of pairs: C<event_type>,
C<aggregate_type>, C<aggregate_id>, C<aggregate_version>, C<actor_id>,
C<idempotency_key>, C<payload>, and optionally C<event_id>,
C<correlation_id> (both minted when absent), C<causation_id>,
C<schema_version> (default 1), C<timestamp> (the row's C<created_at>,
default now) and C<outbox_payload> (fields merged into the outbox row's
payload, and kept out of the event's). Returns the stored event as a hash
reference; one already stored under its C<event_id> comes back with
C<< skipped => 1 >>. An insert that conflicts on the id with an event of
another idempotency key is written again under a new C<event_id>, which
the returned event carries. Dies on any other database error, a unique
conflict on any other key included.

=head2 event_recorded

Takes an idempotency key. True when C<event_log> holds an event with it: a
command that stored its rows and died before its event replays by
recording the event once, if this says it is missing.

=head2 record_audit

Takes the audit record's fields as a list of pairs: C<action>, C<actor_id>,
C<target_type>, C<target_id>, C<metadata>, and optionally C<audit_id>,
C<correlation_id> (both minted when absent), C<schema_version> and
C<created_at> (default now). Chains it to the newest record, writes it, and
returns it as a hash reference with its C<previous_hash> and
C<record_hash>. Its C<audit_id> is a new one when the caller's was already
taken.

=head2 verify_audit_record

Takes an audit record, a hash reference or a row. True when its
C<record_hash> matches its fields.

=head1 DIAGNOSTICS

C<new> throws L<GPForum::X::Argument> when no C<schema> is given.

Database errors are rethrown as DBI raised them; a unique conflict on any
key but the row's own id is rethrown too. Conflicts are told apart by
asking the L<GPForum::X::Conflict> that
L<GPForum::Infrastructure::UniqueConflict> returns which constraint it is
on, a partition's index included. A conflict on an outbox row's
idempotency key whose row cannot be found again is rethrown as the server
raised it.

=head1 CONFIGURATION AND ENVIRONMENT

No environment variables are read. The advisory locks are taken only
through a schema whose storage has a database handle; a test double without
one is written to without them.

=head1 DEPENDENCIES

Uses L<GPForum::Domain::EventEnvelope>,
L<GPForum::Infrastructure::AuditRecord>,
L<GPForum::Infrastructure::OutboxMessageBuilder>,
L<GPForum::Infrastructure::Storage>,
L<GPForum::Infrastructure::UniqueConflict>, L<GPForum::X::Conflict>,
L<GPForum::Base>, L<JSON::MaybeXS>, and loads
L<GPForum::Infrastructure::Id> only when no C<id_service> is injected.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

The lookup by id reads each partition's primary key index, so its cost
grows with the number of monthly partitions until their retention is
decided (ADR 0113).

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause
license.

=cut
