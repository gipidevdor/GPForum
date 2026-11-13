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
use GPForum::X::Unavailable;

our $VERSION = '0.001';

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

# Each write is written once, as its promise method (ADR 0177).
GPForum::Infrastructure::SqlFunction->blocking_twins(
    qw(bind_role revoke_binding));

# An active binding of the same role on the same resource is reused --
# committed by an earlier attempt or by a concurrent request that won the
# active key -- completing its audit entry if that attempt left none. A
# minted id already stored with no such binding is minted once more. The
# write runs inside the caller's transaction ($scope, the call layer
# transaction_p hands its work) or in one of its own.
async sub bind_role_p ( $self, $input, $context = undef, $scope = undef ) {
    my $work = sub ($functions) {
        return $self->_bind_role_once_p( $functions, $input, $context );
    };
    return await(
          $scope
        ? $work->($scope)
        : $self->_functions->transaction_p( $work, $context )
    );
}

# api.admin_lock_binding reads the binding FOR UPDATE: a second revocation
# of the same binding waits there until the first commits, then reads the
# revoked_at it wrote and is answered idempotently, rather than stamped and
# audited again.
async sub revoke_binding_p (
    $self, $binding_id, $actor_user_id,
    $context = undef,
    $scope = undef
  )
{
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
        : $self->_functions->transaction_p( $work, $context )
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

async sub _active_binding_p ( $self, $functions, $input, $context ) {
    return GPForum::Infrastructure::ResultRow->from(
        await $functions->row_p(
            'admin_lookup_binding',
            {
                query => {
                    map { $_ => $input->{$_} }
                      qw(user_id role_id resource_type resource_id space_id)
                }
            },
            $context
        )
    );
}

# An earlier attempt may have committed the binding without its audit entry.
async sub _finish_leftover_binding_p ( $self, $functions, $existing, $input,
    $context )
{
    my $audited = await $functions->row_p(
        'admin_lookup_audit',
        {
            query => {
                action    => 'role_binding.created',
                target_id => column_of( $existing, 'binding_id' )
            }
        },
        $context
    );
    if ( !$audited ) {
        await $self->_record_audit_p( $functions,
            $self->_leftover_audit( $existing, $input ), $context );
    }
    return {
        ok         => 1,
        idempotent => 1,
        binding    => _binding_hash($existing),
    };
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

sub _binding_hash ($binding) {
    return {
        map { $_ => column_of( $binding, $_ ) }
          qw(binding_id created_at created_by_user_id resource_id
          resource_type revoked_at role_id space_id user_id)
    };
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

sub _functions ($self) {
    return $self->functions // GPForum::X::Unavailable->throw(
        message => 'role bindings need the PostgreSQL function layer' );
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

Each write is written once, as its promise method; the blocking methods
are those bodies settled on the blocking layer (ADR 0177).

=head2 bind_role_p

Takes a hash reference with C<user_id>, C<role_id>, C<resource_type>,
C<resource_id>, C<space_id> and C<actor_user_id>, an optional query
context, and the call layer of the caller's transaction, when the write
joins it; without one the write runs in a transaction of its own. The scope
columns are matched as given, so C<undef> means "none".

Resolves with C<< { ok => 1, binding => \%binding } >> for a new binding, or
C<< { ok => 1, idempotent => 1, binding => \%binding } >> when an active one
already existed or a concurrent grant made it first. C<%binding> holds
C<binding_id>, C<user_id>, C<role_id>, C<resource_type>, C<resource_id>,
C<space_id>, C<created_by_user_id>, C<created_at> and C<revoked_at>.

The insert runs under a savepoint. When it collides on the primary key the
store looks again for an active binding and otherwise retries once with a new
id; a second failure is rethrown. C<bind_role> is its blocking twin.

=head2 revoke_binding_p

Takes a binding id, the acting user's id, an optional query context and the
caller's call layer, as L</bind_role_p> does. Resolves with C<undef> when
there is no such binding, C<< { binding_id, idempotent => 1, revoked_at } >>
with the earlier time when it was already revoked, and
C<< { binding_id, revoked_at } >> when this call revoked it and wrote the
audit row.

The binding is read with C<SELECT ... FOR UPDATE> (C<api.admin_lock_binding>).
Two revocations of one binding are therefore serialised: the second waits
for the first to commit, then finds C<revoked_at> set and resolves with the
idempotent answer, so the binding keeps the first revocation's time and has
one C<role_binding.revoked> audit row. C<revoke_binding> is its blocking
twin.

=head1 DIAGNOSTICS

Rethrows any insert error that is not a unique conflict on
C<role_bindings_pkey> or C<idx_role_bindings_active_unique>, and a conflict
on the active index when no active binding can then be found. Other
database errors propagate. Throws L<GPForum::X::Unavailable> without the
function layer.

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
around it: the caller's, or the one the write opens.

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
