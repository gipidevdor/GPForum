# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Infrastructure::EventRecorder;

use Const::Fast;
use JSON::MaybeXS;
use Mojo::Base 'GPForum::Base', -signatures, -async_await;
use v5.40;

use GPForum::Domain::EventEnvelope;
use GPForum::Infrastructure::AuditRecord;
use GPForum::Infrastructure::OutboxMessageBuilder;
use GPForum::Infrastructure::Text qw(has_text);
use GPForum::X::Unavailable;

use GPForum::Infrastructure::SqlFunction;

our $VERSION = '0.001';

has functions => \&GPForum::Infrastructure::SqlFunction::for_service;

const my $DEFAULT_SCHEMA_VERSION => 1;

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

# Shared lazy attribute factory; each owner keeps its own recorder and ids.
sub for_service ($service) {
    return __PACKAGE__->new(
        id_service => $service->id_service,
        schema     => $service->schema,
    );
}

# record_event_p settled on the blocking layer (ADR 0177): the caller's
# transaction, when one is open, is the one the event joins.
sub record_event ( $self, %input ) {
    return GPForum::Infrastructure::SqlFunction->settle( $self,
        'record_event_p', \%input );
}

# One api.ops_record_event call: the event, its outbox row and, for an id
# the caller named, the lock on that id (ADR 0116). The recorder needs the
# function layer: without it nothing is recorded, and the write fails.
async sub record_event_p ( $self, $input, $context = undef ) {
    my $row = await $self->_functions->row_p( 'ops_record_event',
        $self->event_call( %{$input} ), $context );
    return $row->{event};
}

# Whether the log holds an event with this idempotency key. A command that
# stored its row and failed before its event was recorded finishes, on
# replay, by recording the event -- once, and only if this says it is
# missing. ADR 0091's append_once: six stores each had their own copy.
sub event_recorded ( $self, $idempotency_key ) {
    return $self->_functions->row( 'ops_event_recorded',
        { key => $idempotency_key } )->{recorded} ? 1 : 0;
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
        explicit      => has_text( $input{event_id} ),
    };
}

# What record_audit sends to api.ops_record_audit, prepared and not sent.
sub audit_call ( $self, %input ) {
    return {
        audit    => $self->audit_record->build( \%input ),
        explicit => has_text( $input{audit_id} ),
    };
}

# record_audit_p settled on the blocking layer, as record_event.
sub record_audit ( $self, %input ) {
    return GPForum::Infrastructure::SqlFunction->settle( $self,
        'record_audit_p', \%input );
}

# One api.ops_record_audit call: the chain's lock, its tip and the row
# linked to it (ADR 0156), as record_event_p records an event.
async sub record_audit_p ( $self, $input, $context = undef ) {
    my $row = await $self->_functions->row_p( 'ops_record_audit',
        $self->audit_call( %{$input} ), $context );
    return $row->{audit};
}

sub _functions ($self) {
    return $self->functions // GPForum::X::Unavailable->throw(
        message => 'the event recorder needs the PostgreSQL function layer' );
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

Each write is one call of a PostgreSQL function (ADR 0126):
C<api.ops_record_event> and C<api.ops_record_audit>, on the caller's call
layer. The blocking L</record_event> and L</record_audit> are the promise
methods settled on the blocking layer (ADR 0177). Without the function
layer the recorder writes nothing and throws L<GPForum::X::Unavailable>.

An event is shaped by L<GPForum::Domain::EventEnvelope>; its outbox row is
keyed by the event so a retry does not queue it twice. An event already
stored under its C<event_id> is not written again: it is returned with
C<skipped> set, and its outbox row is added if it is missing. A unique
conflict on an insert is resolved in the function by reading the row that
won, or by drawing a new id.

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
the read of its tip and the insert share the caller's transaction, all in
the one call of C<api.ops_record_audit>; writers of other aggregates do not
wait. An C<audit_id> the caller passes is locked on its own (class
2026100311) and looked up; one already stored, at any time, is a
collision: the record is written under a newly minted id, as it is after a
conflict on the key.

=head1 SUBROUTINES/METHODS

=head2 for_service

Lazy attribute factory: C<has recorder =E<gt> \&GPForum::Infrastructure::EventRecorder::for_service>.
Builds a fresh recorder using the owning service's schema and id service.
An explicitly injected recorder is retained; no recorder is shared implicitly.

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

=head2 record_event_p

Records an event as L</record_event> does, on the call layer; takes the
same input as a hash reference and an optional request context, and
answers a promise.

=head2 event_recorded

Takes an idempotency key. True when C<event_log> holds an event with it: a
command that stored its rows and died before its event replays by
recording the event once, if this says it is missing.

=head2 record_audit

Takes the audit record's fields as a list of pairs: C<action>, C<actor_id>,
C<target_type>, C<target_id>, C<metadata>, and optionally C<audit_id>,
C<correlation_id> (both minted when absent), C<schema_version> and
C<created_at> (default now). Chains it to the newest record of its target's
chain, writes it, and
returns it as a hash reference with its C<previous_hash> and
C<record_hash>. Its C<audit_id> is a new one when the caller's was already
taken.

=head2 record_audit_p

Records an audit row as L</record_audit> does, on the call layer; takes the
same input as a hash reference and an optional request context, and
answers a promise.

=head2 verify_audit_record

Takes an audit record, a hash reference or a row. True when its
C<record_hash> matches its fields.

=head1 DIAGNOSTICS

C<new> throws L<GPForum::X::Argument> when no C<schema> is given.
L</record_event>, L</record_audit>, their promise methods and
L</event_recorded> throw L<GPForum::X::Unavailable> without the function
layer.

Database errors are raised as the call layer raises them; the functions
raise a unique conflict on any key but the row's own id, and one on an
outbox row's idempotency key whose row cannot be found again.

=head1 CONFIGURATION AND ENVIRONMENT

No environment variables are read.

=head1 DEPENDENCIES

Uses L<GPForum::Domain::EventEnvelope>,
L<GPForum::Infrastructure::AuditRecord>,
L<GPForum::Infrastructure::OutboxMessageBuilder>,
L<GPForum::Infrastructure::SqlFunction>, L<GPForum::X::Unavailable>,
L<GPForum::Base>, L<JSON::MaybeXS>, and loads
L<GPForum::Infrastructure::Id> only when no C<id_service> is injected.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

The lookup by id reads each partition's primary key index, so its cost
grows with the number of monthly partitions until their retention is
decided (ADR 0113).

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
