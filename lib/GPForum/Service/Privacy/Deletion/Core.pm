# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Privacy::Deletion::Core;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -async_await;
use v5.40;

use GPForum::Infrastructure::UniqueConflict;
use GPForum::X::Conflict;
use GPForum::X::Unavailable;

our $VERSION = '0.001';

const my $STATUS_COMPLETED     => 'completed';
const my $ACTION_ID_CONSTRAINT => 'deletion_actions_pkey';

# Whether an insert lost its minted id, and whether a reread may find the
# row that won the other constraint or the id.
sub lost_race ( $, $error, $id_constraint, $other_constraint = undef ) {
    my $conflict = GPForum::X::Conflict->caught($error);
    my $id_taken = $conflict && $conflict->on($id_constraint) ? 1 : 0;
    my $other =
         $conflict
      && defined $other_constraint
      && $conflict->on($other_constraint) ? 1 : 0;

    return ( $id_taken, $id_taken || $other );
}

sub _new_action ( $self, $request_id, $input ) {
    return {
        action_type         => $input->{action_type},
        actor_id            => $input->{actor_id},
        created_at          => $input->{created_at},
        deletion_action_id  => $self->id_service->uuid,
        deletion_request_id => $request_id,
        metadata            => $input->{metadata} || {},
    };
}

# A minted action id already stored is minted once more.
async sub record_action_p ( $self, $db, $request_id, $input, $context ) {
    my $create = async sub ($savepoint) {
        my $action = $self->_new_action( $request_id, $input );
        await $self->insert_privacy_row_p( $savepoint, 'DeletionAction',
            $action, $context );

        return $action;
    };
    my ( $created, $error ) =
      await GPForum::Infrastructure::UniqueConflict->attempt_p( $db, $create );
    return $created if $created;

    my ($id_taken) = $self->lost_race( $error, $ACTION_ID_CONSTRAINT );
    return await GPForum::Infrastructure::UniqueConflict->once_more_p( $db,
        $create )
      if $id_taken;

    GPForum::Infrastructure::UniqueConflict->rethrow($error);
}

sub request_id_of ( $self, $input ) {
    return $self->record->column( $input->{request}, 'deletion_request_id' );
}

sub same_request_status ( $self, $request, $status ) {
    my $held = $self->record->column( $request, 'status' ) || q{};
    if ( $held eq $status ) {
        return 1;
    }

    return 0;
}

async sub set_request_status_p ( $self, $db, $request, $status, $context ) {
    return if $self->same_request_status( $request, $status );

    await $self->update_privacy_row_p( $db, 'DeletionRequest', $request,
        { status => $status }, $context );
    return;
}

async sub complete_request_row_p ( $self, $db, $request, $timestamp, $context )
{
    return if $self->same_request_status( $request, $STATUS_COMPLETED );

    await $self->update_privacy_row_p(
        $db,
        'DeletionRequest',
        $request,
        {
            completed_at => $timestamp,
            status       => $STATUS_COMPLETED,
        },
        $context
    );
    return;
}

sub job_query ( $, $request_id ) {
    return ( 'ErasureJob', { deletion_request_id => $request_id },
        'scheduled_at' );
}

sub active_hold_query ( $self, $request ) {
    return (
        'RetentionHold',
        {
            ends_at       => undef,
            resource_id   => $self->record->column( $request, 'resource_id' ),
            resource_type => $self->record->column( $request, 'resource_type' ),
        },
        'created_at',
    );
}

# The newest row of a source that matches the query (api.privacy_latest).
async sub latest_row_p ( $, $db, $context, $source, $query, $ ) {
    my $row = await $db->row_p( 'privacy_latest',
        { source => $source, query => $query }, $context );
    return $row ? $row->{document} : undef;
}

async sub find_privacy_row_p ( $, $db, $source, $id, $lock, $context ) {
    my $row = await $db->row_p( 'privacy_find',
        { source => $source, id => $id, lock_row => $lock }, $context );
    return $row ? $row->{document} : undef;
}

async sub insert_privacy_row_p ( $, $db, $source, $row, $context ) {
    return (
        await $db->row_p(
            'privacy_insert', { source => $source, row => $row }, $context
        )
    )->{document};
}

async sub update_privacy_row_p ( $, $db, $source, $row, $changes, $context ) {
    await $db->row_p( 'privacy_update',
        _update_values( $source, $row, $changes ), $context );
    @{$row}{ keys %{$changes} } = values %{$changes};
    return $row;
}

sub _update_values ( $source, $row, $changes ) {
    my $id_column =
        $source eq 'User'       ? 'id'
      : $source eq 'ErasureJob' ? 'erasure_job_id'
      :                           'deletion_request_id';
    return {
        source  => $source,
        id      => $row->{$id_column},
        changes => $changes
    };
}

# The event and the audit entry on the transaction's own call layer, as the
# recorder prepares them.
async sub record_privacy_event_and_audit_p ( $self, $db, $input, $context ) {
    my $correlation_id = $self->id_service->uuid;
    my $recorder       = $self->recorder;
    await $db->row_p(
        'ops_record_event',
        $recorder->event_call(
            %{ $self->events->envelope( $input, $correlation_id ) }
        ),
        $context
    );
    await $db->row_p(
        'ops_record_audit',
        $recorder->audit_call(
            %{ $self->events->audit( $input, $correlation_id ) }
        ),
        $context
    );

    return;
}

# Whether the event under this idempotency key is recorded: a step an
# earlier attempt committed without its event finishes by recording it.
async sub event_recorded_p ( $, $db, $key, $context ) {
    my $recorded =
      await $db->row_p( 'ops_event_recorded', { key => $key }, $context );
    return $recorded->{recorded} ? 1 : 0;
}

# The call layer every step runs on: the deletion steps need the function
# layer, and a store without it is a wiring fault.
sub call_layer ($self) {
    return $self->functions // GPForum::X::Unavailable->throw(
        message => 'privacy requests need the PostgreSQL database' );
}

1;

__END__

=head1 NAME

GPForum::Service::Privacy::Deletion::Core - The privacy rows and records the deletion steps share.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    # Part of GPForum::Service::Privacy::DeletionWorkflow; callers use that class.

=head1 DESCRIPTION

Finding, inserting and updating the privacy rows, the latest-row and job and
hold lookups, the request status changes, the action record and the privacy
event with its audit entry. Each step is a promise method that takes the
transaction's call layer (C<$db>) first; the deletion steps run them in
their transaction, on the pooled connections or, for a blocking caller, on
the blocking layer (ADR 0177).

GPForum::Service::Privacy::DeletionWorkflow inherits it, so the object a caller builds has every method; this
file holds one part of that class so each part can be read by itself.

=head1 SUBROUTINES/METHODS

=head2 lost_race

Takes a caught error, the id constraint and an optional other constraint.
Returns whether the insert lost its minted id, and whether a reread may find
the row that won.

=head2 record_action_p

Takes the call layer, a request id, the action (C<action_type>,
C<actor_id>, C<created_at>, C<metadata>) and a query context. Inserts the
deletion action in a savepoint, minting its id once more when the minted one
is taken, and answers the action.

=head2 request_id_of

Takes a step's input and answers the id of its C<request>.

=head2 same_request_status

Takes a request and a status. Returns 1 when the request already has it.

=head2 set_request_status_p

Takes the call layer, a request, a status and a query context. Writes the
status unless the request already has it.

=head2 complete_request_row_p

Takes the call layer, a request, a timestamp and a query context. Marks the
request C<completed> at that time unless it already is.

=head2 job_query

Takes a request id. Returns the source, the query and the order field of
the request's erasure job, for L</latest_row_p>.

=head2 active_hold_query

Takes a request. Returns the source, the query and the order field of the
active hold on its resource, for L</latest_row_p>.

=head2 latest_row_p

Takes the call layer, a query context, a source, a query and an order
field. Answers the newest matching row as a hash, or undef.

=head2 find_privacy_row_p

Takes the call layer, a source, an id, whether to lock the row and a query
context. Answers the row as a hash, or undef.

=head2 insert_privacy_row_p

Takes the call layer, a source, the row and a query context. Inserts the
row and answers it as stored.

=head2 update_privacy_row_p

Takes the call layer, a source, the row, the changes and a query context.
Writes the changes, applies them to the row hash and answers it.

=head2 record_privacy_event_and_audit_p

Takes the call layer, the event input built by
L<GPForum::Service::Privacy::Event> and a query context. Records the event
(with its outbox message) and the audit entry under one correlation id, in
the transaction.

=head2 event_recorded_p

Takes the call layer, an event idempotency key and a query context. Answers
1 when the event is recorded, 0 otherwise.

=head2 call_layer

Answers the call layer the steps run on (C<functions>), or throws
L<GPForum::X::Unavailable> without the SQL function layer.

=head1 DIAGNOSTICS

Without the function layer the deletion steps throw
L<GPForum::X::Unavailable>.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

As GPForum::Service::Privacy::DeletionWorkflow.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

None known.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
