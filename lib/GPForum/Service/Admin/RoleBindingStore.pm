# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Admin::RoleBindingStore;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -signatures, -async_await;
use v5.40;

use GPForum::Infrastructure::SqlFunction;
use GPForum::Infrastructure::ResultRow;

use GPForum::Infrastructure::Row qw(column_of);
use GPForum::Infrastructure::EventRecorder;
use GPForum::Infrastructure::UniqueConflict;
use GPForum::Service::Admin::Event;
use GPForum::Service::Clock;
use GPForum::X::Conflict;

our $VERSION = '0.001';

const my $ROW_LIMIT_ONE     => 1;
const my $ID_CONSTRAINT     => 'role_bindings_pkey';
const my $ACTIVE_CONSTRAINT => 'idx_role_bindings_active_unique';

has clock      => sub { return GPForum::Service::Clock->new; };
has id_service => sub {
    require GPForum::Infrastructure::Id;
    return GPForum::Infrastructure::Id->new;
};
has recorder => \&GPForum::Infrastructure::EventRecorder::for_service;
__PACKAGE__->requires(qw(schema));
has events => sub { return GPForum::Service::Admin::Event->new; };

has functions => \&GPForum::Infrastructure::SqlFunction::for_service;

sub bind_role ( $self, $input ) {
    return $self->_txn( sub { return $self->_bind_role_once($input); } );
}

sub _txn ( $self, $code ) {
    return $self->schema->can('txn_do')
      ? $self->schema->txn_do($code)
      : $code->();
}

# An active binding of the same role on the same resource is reused --
# committed by an earlier attempt or by a concurrent request that won the
# active key -- completing its audit entry if that attempt left none. A
# minted id already stored with no such binding is minted once more.
sub _bind_role_once ( $self, $input ) {
    my $existing = $self->_active_binding($input);
    if ($existing) {
        return $self->_finish_leftover_binding( $existing, $input );
    }

    my $create = sub { return $self->_create_binding($input); };
    my ( $created, $error ) =
      GPForum::Infrastructure::UniqueConflict->attempt( $self->schema,
        $create );
    if ( !$error ) {
        return $created;
    }

    my $conflict = GPForum::X::Conflict->caught($error);
    my $id_taken = $conflict && $conflict->on($ID_CONSTRAINT);
    if ( $id_taken || ( $conflict && $conflict->on($ACTIVE_CONSTRAINT) ) ) {
        $existing = $self->_active_binding($input);
        if ($existing) {
            return $self->_finish_leftover_binding( $existing, $input );
        }
        if ($id_taken) {
            my ( $retried, $retry_error ) =
              GPForum::Infrastructure::UniqueConflict->attempt( $self->schema,
                $create );
            if ($retry_error) {
                GPForum::Infrastructure::UniqueConflict->rethrow($retry_error);
            }
            return $retried;
        }
    }

    GPForum::Infrastructure::UniqueConflict->rethrow($error);
}

sub _create_binding ( $self, $input ) {
    my $binding = $self->_new_binding($input);
    if ( $self->functions ) {
        $self->functions->row( 'admin_insert_binding', { values => $binding } );
    }
    else { $self->schema->resultset('RoleBinding')->create($binding); }
    $self->_record_audit( _created_audit( $input, $binding ) );

    return { ok => 1, binding => $binding };
}

sub _new_binding ( $self, $input ) {
    return {
        binding_id         => $self->id_service->uuid,
        user_id            => $input->{user_id},
        role_id            => $input->{role_id},
        resource_type      => $input->{resource_type},
        resource_id        => $input->{resource_id},
        space_id           => $input->{space_id},
        created_by_user_id => $input->{actor_user_id},
        created_at         => $self->clock->now_iso8601,
        revoked_at         => undef,
    };
}

sub _created_audit ( $input, $binding ) {
    return {
        action        => 'role_binding.created',
        actor_user_id => $input->{actor_user_id},
        binding       => $binding,
        created_at    => $binding->{created_at},
    };
}

sub revoke_binding ( $self, $binding_id, $actor_user_id ) {
    return $self->_txn(
        sub {
            return $self->_revoke_binding_once( $binding_id, $actor_user_id );
        }
    );
}

# SELECT ... FOR UPDATE: a second revocation of the same binding waits here
# until the first commits, then reads the revoked_at it wrote. Read without
# the lock, both saw the binding active; the later one overwrote revoked_at
# and recorded a second audit row.
sub _revoke_binding_once ( $self, $binding_id, $actor_user_id ) {
    my $binding =
      $self->functions
      ? GPForum::Infrastructure::ResultRow->from(
        $self->functions->row(
            'admin_lock_binding', { binding_id => $binding_id }
        )
      )
      : $self->schema->resultset('RoleBinding')
      ->find( $binding_id, { for => 'update' } );
    return undef if !$binding;

    # Checked under the row lock, so a revocation that committed while this
    # one waited is reported here rather than stamped and audited again.
    return {
        binding_id => $binding_id,
        idempotent => 1,
        revoked_at => $binding->get_column('revoked_at'),
      }
      if defined $binding->get_column('revoked_at');

    my $revoked_at = $self->clock->now_iso8601;
    if ( $self->functions ) {
        $self->functions->row( 'admin_revoke_binding',
            { binding_id => $binding_id, revoked_at => $revoked_at } );
    }
    else { $binding->update( { revoked_at => $revoked_at } ); }
    $self->_record_audit(
        _revoked_audit( $binding, $binding_id, $actor_user_id, $revoked_at ) );

    return {
        binding_id => $binding_id,
        revoked_at => $revoked_at,
    };
}

sub _revoked_audit ( $binding, $binding_id, $actor_user_id, $revoked_at ) {
    return {
        action        => 'role_binding.revoked',
        actor_user_id => $actor_user_id,
        binding       => {
            binding_id    => $binding_id,
            resource_id   => $binding->get_column('resource_id'),
            resource_type => $binding->get_column('resource_type'),
            role_id       => $binding->get_column('role_id'),
            space_id      => $binding->get_column('space_id'),
            user_id       => $binding->get_column('user_id'),
        },
        created_at => $revoked_at,
    };
}

# The two binding writes on a pooled asynchronous connection, inside the
# caller's transaction ($scope, the call layer transaction_p hands its work)
# or in one of their own, with the blocking writes' steps.
async sub bind_role_p ( $self, $input, $context = undef, $scope = undef ) {
    return $self->bind_role($input) if !$self->functions;
    my $work = sub ($functions) {
        return $self->_bind_role_once_p( $functions, $input, $context );
    };
    return await(
          $scope
        ? $work->($scope)
        : $self->functions->transaction_p( $work, $context )
    );
}

async sub revoke_binding_p (
    $self, $binding_id, $actor_user_id,
    $context = undef,
    $scope = undef
  )
{
    return $self->revoke_binding( $binding_id, $actor_user_id )
      if !$self->functions;
    my $work = async sub ($functions) {
        my $binding = GPForum::Infrastructure::ResultRow->from(
            await $functions->row_p(
                'admin_lock_binding', { binding_id => $binding_id },
                $context
            )
        );
        return undef if !$binding;
        return {
            binding_id => $binding_id,
            idempotent => 1,
            revoked_at => $binding->get_column('revoked_at'),
          }
          if defined $binding->get_column('revoked_at');

        my $revoked_at = $self->clock->now_iso8601;
        await $functions->row_p( 'admin_revoke_binding',
            { binding_id => $binding_id, revoked_at => $revoked_at },
            $context );
        await $self->_record_audit_p(
            $functions,
            _revoked_audit(
                $binding, $binding_id, $actor_user_id, $revoked_at
            ),
            $context
        );
        return {
            binding_id => $binding_id,
            revoked_at => $revoked_at,
        };
    };
    return await(
          $scope
        ? $work->($scope)
        : $self->functions->transaction_p( $work, $context )
    );
}

async sub _bind_role_once_p ( $self, $functions, $input, $context ) {
    my $existing =
      await $self->_active_binding_p( $functions, $input, $context );
    return await $self->_finish_leftover_binding_p( $functions, $existing,
        $input, $context )
      if $existing;

    my $create = async sub ($savepoint) {
        my $binding = $self->_new_binding($input);
        await $savepoint->row_p( 'admin_insert_binding',
            { values => $binding }, $context );
        await $self->_record_audit_p( $savepoint,
            _created_audit( $input, $binding ), $context );
        return { ok => 1, binding => $binding };
    };
    for my $retry ( 0, 1 ) {
        my ( $created, $error ) =
          await GPForum::Infrastructure::UniqueConflict->attempt_p( $functions,
            $create );
        return $created if !$error;

        my $conflict = GPForum::X::Conflict->caught($error);
        my $id_taken = !$retry && $conflict && $conflict->on($ID_CONSTRAINT);
        if ( $id_taken
            || ( !$retry && $conflict && $conflict->on($ACTIVE_CONSTRAINT) ) )
        {
            $existing =
              await $self->_active_binding_p( $functions, $input, $context );
            return await $self->_finish_leftover_binding_p( $functions,
                $existing, $input, $context )
              if $existing;
            next if $id_taken;
        }
        GPForum::Infrastructure::UniqueConflict->rethrow($error);
    }
    return;
}

async sub _active_binding_p ( $self, $functions, $input, $context ) {
    return GPForum::Infrastructure::ResultRow->from(
        await $functions->row_p( _active_binding_call($input), $context ) );
}

async sub _finish_leftover_binding_p ( $self, $functions, $existing, $input,
    $context )
{
    my $audited =
      await $functions->row_p( _created_audit_call($existing), $context );
    if ( !$audited ) {
        await $self->_record_audit_p( $functions,
            $self->_leftover_audit( $existing, $input ), $context );
    }
    return _leftover_answer($existing);
}

sub _record_audit_p ( $self, $functions, $input, $context ) {
    return $functions->row_p(
        'ops_record_audit',
        $self->recorder->audit_call(
            %{ $self->events->binding_audit($input) }
        ),
        $context
    );
}

sub _active_binding ( $self, $input ) {
    if ( $self->functions ) {
        return GPForum::Infrastructure::ResultRow->from(
            $self->functions->row( _active_binding_call($input) ) );
    }
    my $search = $self->schema->resultset('RoleBinding')->search_rs(
        {
            user_id       => $input->{user_id},
            role_id       => $input->{role_id},
            resource_type => $input->{resource_type},
            resource_id   => $input->{resource_id},
            space_id      => $input->{space_id},
            revoked_at    => undef,
        },
        { rows => $ROW_LIMIT_ONE }
    );

    return $search->single if $search->can('single');

    if ( $search->can('all') ) {
        my @rows = $search->all;
        return $rows[0];
    }

    return $search->rows->[0] if $search->can('rows');

    return undef;
}

sub _active_binding_call ($input) {
    return (
        'admin_lookup_binding',
        {
            query => {
                map { $_ => $input->{$_} }
                  qw(user_id role_id resource_type resource_id space_id)
            }
        }
    );
}

sub _created_audit_call ($existing) {
    return (
        'admin_lookup_audit',
        {
            query => {
                action    => 'role_binding.created',
                target_id => column_of( $existing, 'binding_id' )
            }
        }
    );
}

sub _binding_hash ($binding) {
    return undef if !$binding;

    return {
        binding_id         => column_of( $binding, 'binding_id' ),
        created_at         => column_of( $binding, 'created_at' ),
        created_by_user_id => column_of( $binding, 'created_by_user_id' ),
        resource_id        => column_of( $binding, 'resource_id' ),
        resource_type      => column_of( $binding, 'resource_type' ),
        revoked_at         => column_of( $binding, 'revoked_at' ),
        role_id            => column_of( $binding, 'role_id' ),
        space_id           => column_of( $binding, 'space_id' ),
        user_id            => column_of( $binding, 'user_id' ),
    };
}

# An earlier attempt may have committed the binding without its audit entry.
sub _finish_leftover_binding ( $self, $existing, $input ) {
    my $audited;
    if ( $self->functions ) {
        $audited = $self->functions->row( _created_audit_call($existing) );
    }
    else {
        my $search = $self->schema->resultset('AuditLog')->search_rs(
            {
                action    => 'role_binding.created',
                target_id => column_of( $existing, 'binding_id' ),
            },
            { rows => $ROW_LIMIT_ONE },
        );
        $audited = $search->can('single') ? $search->single : undef;
    }
    if ( !$audited ) {
        $self->_record_audit( $self->_leftover_audit( $existing, $input ) );
    }

    return _leftover_answer($existing);
}

sub _leftover_audit ( $self, $existing, $input ) {
    return {
        action        => 'role_binding.created',
        actor_user_id => $input->{actor_user_id},
        binding       => $existing,
        created_at    => column_of( $existing, 'created_at' )
          || $self->clock->now_iso8601,
    };
}

sub _leftover_answer ($existing) {
    return {
        ok         => 1,
        idempotent => 1,
        binding    => _binding_hash($existing),
    };
}

sub _record_audit ( $self, $input ) {
    $self->recorder->record_audit( %{ $self->events->binding_audit($input) } );

    return;
}

1;

__END__

=head1 NAME

GPForum::Service::Admin::RoleBindingStore - Grants and revokes role bindings, with their audit rows.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $store =
      GPForum::Service::Admin::RoleBindingStore->new( schema => $schema );
    my $bound = $store->bind_role(
        {
            actor_user_id => $admin_id,
            user_id       => $user_id,
            role_id       => $role_id,
            resource_type => 'global',
            resource_id   => undef,
            space_id      => undef,
        }
    );
    $store->revoke_binding( $bound->{binding}{binding_id}, $admin_id );

=head1 DESCRIPTION

A role binding gives a user a role over a scope: a resource type, optionally
one resource, optionally one space. This store writes those rows for the
console (through L<GPForum::Service::Admin::Workflow>) and for the first
administrator (through L<GPForum::Service::Admin::Bootstrapper>), and records
a C<role_binding.created> or C<role_binding.revoked> audit row with each.

Granting is idempotent: the same user, role and scope that already hold an
active binding get that binding back. The database's unique index on active
bindings decides a race between two grants, and the loser returns the
winner's row rather than an error. A binding found without its audit row --
one written before a crash, or by older code -- has the row written when it
is next granted. Revoking stamps C<revoked_at> under the binding's row lock;
the row is kept.

=head1 SUBROUTINES/METHODS

=head2 bind_role

Takes a hash reference with C<user_id>, C<role_id>, C<resource_type>,
C<resource_id>, C<space_id> and C<actor_user_id>; the scope columns are
matched as given, so C<undef> means "none". Runs inside
C<< $schema->txn_do >> when the schema has one.

Returns C<< { ok => 1, binding => \%binding } >> for a new binding, or
C<< { ok => 1, idempotent => 1, binding => \%binding } >> when an active one
already existed or a concurrent grant made it first. C<%binding> holds
C<binding_id>, C<user_id>, C<role_id>, C<resource_type>, C<resource_id>,
C<space_id>, C<created_by_user_id>, C<created_at> and C<revoked_at>.

The insert runs under a savepoint. When it collides on the primary key the
store looks again for an active binding and otherwise retries once with a new
id; a second failure is rethrown.

=head2 bind_role_p

Binds a role as L</bind_role> does on a pooled
asynchronous connection: inside the transaction of the call layer given
as its last argument, or in one of its own.

=head2 revoke_binding

Takes a binding id and the acting user's id. Returns C<undef> when there is
no such binding, C<< { binding_id, idempotent => 1, revoked_at } >> with the
earlier time when it was already revoked, and
C<< { binding_id, revoked_at } >> when this call revoked it and wrote the
audit row.

Runs inside C<< $schema->txn_do >> when the schema has one, and reads the
binding with C<SELECT ... FOR UPDATE>. Two revocations of one binding are
therefore serialised: the second waits for the first to commit, then finds
C<revoked_at> set and returns the idempotent answer, so the binding keeps
the first revocation's time and has one C<role_binding.revoked> audit row.

=head2 revoke_binding_p

Revokes a binding as L</revoke_binding> does, its row locked, on a pooled
asynchronous connection: inside the transaction of the call layer given
as its last argument, or in one of its own.

=head1 DIAGNOSTICS

Rethrows any insert error that is not a unique conflict on
C<role_bindings_pkey> or C<idx_role_bindings_active_unique>, and a conflict
on the active index when no active binding can then be found. Other
database errors propagate.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Infrastructure::EventRecorder>,
L<GPForum::Infrastructure::UniqueConflict>, L<GPForum::X::Conflict>,
L<GPForum::Infrastructure::Row>,
L<GPForum::Infrastructure::Id>,
L<GPForum::Service::Admin::Event>,
L<GPForum::Service::Clock>.

Extends L<GPForum::Base>: built without C<schema> it throws
L<GPForum::X::Argument>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

No input is validated here; L<GPForum::Service::Admin::Workflow> checks the
required fields first.

The row lock that serialises revocations lasts as long as the transaction
around it. L<GPForum::Schema> always has C<txn_do>; through a schema
without one, as some in-memory test doubles are, each statement would
commit on its own and the lock would be released as soon as it was taken.

Completing a lost C<role_binding.created> row is not serialised: the active
binding is read without a lock and its audit row looked for before one is
written, so two grants that find the same binding without its row at the
same moment can both write it.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
