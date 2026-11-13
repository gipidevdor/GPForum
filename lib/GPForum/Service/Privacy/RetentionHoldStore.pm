# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Privacy::RetentionHoldStore;

use Const::Fast;
use GPForum::Infrastructure::EventRecorder;
use GPForum::Infrastructure::UniqueConflict;
use GPForum::Service::Clock;
use GPForum::Service::Privacy::Event;
use GPForum::Service::Privacy::Record;
use GPForum::X::Conflict;
use GPForum::X::Unavailable;
use Mojo::Base 'GPForum::Base', -signatures, -async_await;
use v5.40;

use GPForum::Infrastructure::SqlFunction;
use GPForum::Infrastructure::ResultRow;

has functions => \&GPForum::Infrastructure::SqlFunction::for_service;

our $VERSION = '0.001';

const my $ACTIVE_CONSTRAINT => 'idx_retention_holds_active_resource_unique';
const my $ID_CONSTRAINT     => 'retention_holds_pkey';

has clock      => sub { return GPForum::Service::Clock->new; };
has id_service => sub {
    require GPForum::Infrastructure::Id;
    return GPForum::Infrastructure::Id->new;
};

# Prepares the event and audit calls a hold sends on its transaction.
has recorder => \&GPForum::Infrastructure::EventRecorder::for_service;
__PACKAGE__->requires(qw(schema));
has record => sub { return GPForum::Service::Privacy::Record->new; };
has events => sub {
    my ($self) = @_;

    return GPForum::Service::Privacy::Event->new( record => $self->record );
};

# Each operation is written once, as its promise method (ADR 0177).
GPForum::Infrastructure::SqlFunction->blocking_twins(
    qw(create_hold active_holds_for));

# The resource's active hold is reused -- committed by an earlier attempt, or
# by a concurrent request that won the active key -- completing its event if
# that attempt left none. A minted id already stored with no such hold is
# minted once more. One transaction, or a savepoint of the transaction
# $functions belongs to.
async sub create_hold_p ( $self, $input, $context = undef, $functions = undef )
{
    $functions //= $self->_functions;

    return await $functions->transaction_p(
        async sub ($scope) {
            my $existing =
              await $self->_active_hold_hash_p( $scope, $input, $context );
            return await $self->_finish_leftover_hold_p( $scope, $existing,
                $input, $context )
              if $existing;

            my $insert = async sub ($savepoint) {
                return await $self->_insert_hold_p( $savepoint, $input,
                    $context );
            };
            my ( $created, $error ) =
              await GPForum::Infrastructure::UniqueConflict->attempt_p( $scope,
                $insert );
            return $created if $created;

            my ( $id_taken, $reread ) = _insert_conflict($error);
            if ($reread) {
                $existing =
                  await $self->_active_hold_hash_p( $scope, $input, $context );
                return await $self->_finish_leftover_hold_p( $scope,
                    $existing, $input, $context )
                  if $existing;
            }
            if ( !$id_taken ) {
                GPForum::Infrastructure::UniqueConflict->rethrow($error);
            }

            ( $created, $error ) =
              await GPForum::Infrastructure::UniqueConflict->attempt_p( $scope,
                $insert );
            return $created if $created;
            GPForum::Infrastructure::UniqueConflict->rethrow($error);
        },
        $context
    );
}

# The resource's holds in force, newest first.
async sub active_holds_for_p ( $self, $resource_type, $resource_id, $limit,
    $context = undef )
{
    return _result_rows(
        await $self->_functions->rows_p(
            'privacy_review',
            _active_query( $resource_type, $resource_id, $limit ), $context
        )
    );
}

# Whether an insert lost its minted id, and whether it lost to a hold that
# a reread may now find.
sub _insert_conflict ($error) {
    my $conflict = GPForum::X::Conflict->caught($error);
    my $id_taken = $conflict && $conflict->on($ID_CONSTRAINT) ? 1 : 0;

    return ( $id_taken,
        $id_taken || ( $conflict && $conflict->on($ACTIVE_CONSTRAINT) )
        ? 1
        : 0 );
}

async sub _active_hold_hash_p ( $self, $db, $input, $context ) {
    my $rows =
      await $db->rows_p( 'privacy_review',
        _active_query( $input->{resource_type}, $input->{resource_id}, 1 ),
        $context );
    return $self->_hold_hash( _result_rows($rows) );
}

sub _hold_hash ( $self, $holds ) {
    if ( !@{$holds} ) {
        return undef;
    }

    my $hold = $holds->[0];
    return {
        map { $_ => scalar $self->record->column( $hold, $_ ) }
          qw(created_at created_by ends_at reason resource_id resource_type
          retention_hold_id starts_at)
    };
}

# api.privacy_review reads only the holds in force (no ends_at).
sub _active_query ( $resource_type, $resource_id, $limit ) {
    return {
        source => 'RetentionHold',
        query  => {
            resource_type => $resource_type,
            resource_id   => $resource_id
        },
        row_limit => $limit,
        oldest    => 0
    };
}

sub _result_rows ($rows) {
    return [ map { GPForum::Infrastructure::ResultRow->from( $_->{document} ) }
          @{$rows} ];
}

async sub _insert_hold_p ( $self, $db, $input, $context ) {
    my $hold = $self->_new_hold($input);
    await $db->row_p( 'privacy_insert',
        { source => 'RetentionHold', row => $hold }, $context );
    await $self->_record_event_and_audit_p( $db, $hold, $input->{created_by},
        $context );

    return $hold;
}

sub _new_hold ( $self, $input ) {
    my $timestamp = $self->clock->now_iso8601;
    return {
        created_at        => $timestamp,
        created_by        => $input->{created_by},
        ends_at           => $input->{ends_at},
        reason            => $input->{reason},
        resource_id       => $input->{resource_id},
        resource_type     => $input->{resource_type},
        retention_hold_id => $self->id_service->uuid,
        starts_at         => $input->{starts_at} || $timestamp,
    };
}

# An earlier attempt may have committed the hold without its event.
async sub _finish_leftover_hold_p ( $self, $db, $existing, $input, $context ) {
    my $recorded = await $db->row_p( 'ops_event_recorded',
        { key => _created_key($existing) }, $context );
    if ( !$recorded->{recorded} ) {
        await $self->_record_event_and_audit_p( $db, $existing,
            $input->{created_by}, $context );
    }

    return $existing;
}

sub _created_key ($hold) {
    return join q{:}, 'privacy.retention_hold_created',
      $hold->{retention_hold_id};
}

# The event and the audit entry on the transaction's own call layer, as the
# recorder prepares them.
async sub _record_event_and_audit_p ( $self, $db, $hold, $actor_id, $context ) {
    my $recorded = $self->_recorded( $hold, $actor_id );
    await $db->row_p(
        'ops_record_event',
        $self->recorder->event_call(
            %{ $self->events->hold_envelope($recorded) }
        ),
        $context
    );
    await $db->row_p(
        'ops_record_audit',
        $self->recorder->audit_call(
            %{ $self->events->hold_audit($recorded) }
        ),
        $context
    );

    return;
}

sub _recorded ( $self, $hold, $actor_id ) {
    return {
        actor_id       => $actor_id,
        correlation_id => $self->id_service->uuid,
        hold           => $hold,
    };
}

sub _functions ($self) {
    return $self->functions // GPForum::X::Unavailable->throw(
        message => 'retention holds need the PostgreSQL database' );
}

1;

__END__

=head1 NAME

GPForum::Service::Privacy::RetentionHoldStore - Retention hold persistence.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $hold = $store->create_hold($input);

=head1 DESCRIPTION

Creates retention holds and lists active holds for a resource. Event and
audit hashes live in L<GPForum::Service::Privacy::Event>. This store still
writes RetentionHold rows, EventLog, OutboxMessage, and AuditLog. A unique
partial index keeps one active hold per resource; a unique race on that
index reloads the winning row. A unique race on C<retention_hold_id> remints
the id once and does not return another hold.

=head1 SUBROUTINES/METHODS

=head2 create_hold_p

Takes the hold (C<resource_type>, C<resource_id>, C<reason>, C<created_by>
and the optional C<starts_at> and C<ends_at>), an optional query context and
an optional transaction call layer. Inserts the hold and records the created
event and audit entry, in one transaction, or in a savepoint of the given
one. Answers the hold as a hash reference.

=head2 active_holds_for_p

Takes a resource type, a resource id, a limit and an optional query
context. Answers the holds in force on the resource, newest first.

=head2 create_hold, active_holds_for

The blocking twins of the promise methods above (ADR 0177): each runs its
promise method on the blocking layer, the process's own connection and the
transaction it holds, and returns its answer.

=head1 DIAGNOSTICS

Without the SQL function layer it throws L<GPForum::X::Unavailable>.
Persistence errors roll the transaction back and propagate.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

Uses L<GPForum::Infrastructure::EventRecorder>,
L<GPForum::Infrastructure::UniqueConflict>, L<GPForum::X::Conflict>,
L<GPForum::X::Unavailable>, L<GPForum::Infrastructure::SqlFunction>,
L<GPForum::Service::Clock>, L<GPForum::Service::Privacy::Event>,
L<GPForum::Service::Privacy::Record>, and L<GPForum::Base>.
C<GPForum::Infrastructure::Id> is required lazily unless an C<id_service> is
injected.

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
