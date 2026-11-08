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
has recorder => sub {
    my ($self) = @_;

    return GPForum::Infrastructure::EventRecorder->new(
        id_service => $self->id_service,
        schema     => $self->schema,
        functions  => $self->functions,
    );
};
__PACKAGE__->requires(qw(schema));
has record => sub { return GPForum::Service::Privacy::Record->new; };
has events => sub {
    my ($self) = @_;

    return GPForum::Service::Privacy::Event->new( record => $self->record );
};

# The resource's active hold is reused -- committed by an earlier attempt, or
# by a concurrent request that won the active key -- completing its event if
# that attempt left none. A minted id already stored with no such hold is
# minted once more.
sub create_hold ( $self, $input ) {
    return $self->schema->txn_do(
        sub {
            my $existing = $self->_active_hold_hash($input);
            if ($existing) {
                return $self->_finish_leftover_hold( $existing, $input );
            }

            my $insert = sub { return $self->_insert_hold($input); };
            my ( $created, $error ) =
              GPForum::Infrastructure::UniqueConflict->attempt( $self->schema,
                $insert );
            if ($created) {
                return $created;
            }

            my ( $id_taken, $reread ) = _insert_conflict($error);
            if ($reread) {
                $existing = $self->_active_hold_hash($input);
                if ($existing) {
                    return $self->_finish_leftover_hold( $existing, $input );
                }
            }
            if ( !$id_taken ) {
                GPForum::Infrastructure::UniqueConflict->rethrow($error);
            }

            ( $created, $error ) =
              GPForum::Infrastructure::UniqueConflict->attempt( $self->schema,
                $insert );
            if ($created) {
                return $created;
            }
            GPForum::Infrastructure::UniqueConflict->rethrow($error);
        }
    );
}

# create_hold in one transaction on the worker's pooled asynchronous
# connections, or in a savepoint of the transaction $functions belongs to.
async sub create_hold_p ( $self, $input, $context = undef, $functions = undef )
{
    $functions //= $self->functions;
    return $self->create_hold($input) if !$functions;

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

sub _active_hold_hash ( $self, $input ) {
    return $self->_hold_hash(
        $self->active_holds_for(
            $input->{resource_type},
            $input->{resource_id}, 1
        )
    );
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

sub active_holds_for ( $self, $resource_type, $resource_id, $limit ) {
    if ( $self->functions ) {
        return _result_rows(
            $self->functions->rows(
                'privacy_review',
                _active_query( $resource_type, $resource_id, $limit )
            )
        );
    }

    my $search = $self->schema->resultset('RetentionHold')->search_rs(
        {
            ends_at       => undef,
            resource_id   => $resource_id,
            resource_type => $resource_type,
        },
        {
            order_by => [ { -desc => 'created_at' } ],
            rows     => $limit,
        }
    );

    return [ $self->record->rows($search) ];
}

sub _insert_hold ( $self, $input ) {
    my $hold = $self->_new_hold($input);
    if ( $self->functions ) {
        $self->functions->row( 'privacy_insert',
            { source => 'RetentionHold', row => $hold } );
    }
    else {
        $self->schema->resultset('RetentionHold')->create($hold);
    }
    $self->_record_event_and_audit( $hold, $input->{created_by} );

    return $hold;
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
sub _finish_leftover_hold ( $self, $existing, $input ) {
    if ( !$self->recorder->event_recorded( _created_key($existing) ) ) {
        $self->_record_event_and_audit( $existing, $input->{created_by} );
    }

    return $existing;
}

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

sub _record_event_and_audit ( $self, $hold, $actor_id ) {
    my $recorded = $self->_recorded( $hold, $actor_id );
    $self->recorder->record_event(
        %{ $self->events->hold_envelope($recorded) } );
    $self->recorder->record_audit( %{ $self->events->hold_audit($recorded) } );

    return;
}

# The event and the audit entry on the transaction's own call layer.
async sub _record_event_and_audit_p ( $self, $db, $hold, $actor_id, $context ) {
    my $recorded = $self->_recorded( $hold, $actor_id );
    my $recorder = GPForum::Infrastructure::EventRecorder->new(
        id_service => $self->id_service,
        schema     => $self->schema,
        functions  => $db,
    );
    await $recorder->record_event_p( $self->events->hold_envelope($recorded),
        $context );
    await $recorder->record_audit_p( $self->events->hold_audit($recorded),
        $context );

    return;
}

sub _recorded ( $self, $hold, $actor_id ) {
    return {
        actor_id       => $actor_id,
        correlation_id => $self->id_service->uuid,
        hold           => $hold,
    };
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

=head2 create_hold

Inserts a hold inside a transaction and records the created event.

=head2 create_hold_p

L</create_hold> as a promise, with an optional query context and an
optional transaction call layer last: one transaction on the worker's
pooled asynchronous connections, or a savepoint of the given one.

=head2 active_holds_for

Returns open holds for a resource type and id, newest first.

=head1 DIAGNOSTICS

None. Persistence errors stay in the schema transaction.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

Uses L<GPForum::Infrastructure::EventRecorder>,
L<GPForum::Infrastructure::UniqueConflict>, L<GPForum::X::Conflict>,
L<GPForum::Service::Clock>, L<GPForum::Service::Privacy::Event>,
L<GPForum::Service::Privacy::Record>, and L<GPForum::Base>.
C<GPForum::Infrastructure::Id> is required lazily unless an C<id_service> is
injected.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Public C<active_holds_for> still takes four arguments including the invocant.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
