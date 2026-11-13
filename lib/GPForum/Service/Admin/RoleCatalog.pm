# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Admin::RoleCatalog;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -async_await;
use v5.40;

use GPForum::Infrastructure::SqlFunction;
use GPForum::Infrastructure::ResultRow;
use List::Util qw(any);

use GPForum::Infrastructure::Row qw(column_of);
use GPForum::Infrastructure::EventRecorder;
use GPForum::Infrastructure::UniqueConflict;
use GPForum::Service::Admin::Event;
use GPForum::Service::Clock;
use GPForum::X::Conflict;
use GPForum::X::Unavailable;

our $VERSION = '0.001';

const my $ROLE_ID_CONSTRAINT           => 'roles_pkey';
const my $ROLE_NAME_CONSTRAINT         => 'roles_name_key';
const my $PERMISSION_ID_CONSTRAINT     => 'permissions_pkey';
const my $PERMISSION_NAME_CONSTRAINT   => 'permissions_name_key';
const my $PERMISSION_ACTION_CONSTRAINT => 'permissions_resource_action_key';
const my $ROLE_PERMISSION_CONSTRAINT   => 'role_permissions_pkey';
const my $ATTACHED_ACTION              => 'role_permission.attached';
const my $UUID_DIGITS                  => 32;
const my %LOOKUP => (
    Role           => 'admin_lookup_role',
    Permission     => 'admin_lookup_permission',
    RolePermission => 'admin_lookup_role_permission',
    AuditLog       => 'admin_lookup_audit',
);

has clock      => sub { return GPForum::Service::Clock->new; };
has id_service => sub {
    require GPForum::Infrastructure::Id;
    return GPForum::Infrastructure::Id->new;
};
has recorder => \&GPForum::Infrastructure::EventRecorder::for_service;
__PACKAGE__->requires(qw(schema));
has events => sub { return GPForum::Service::Admin::Event->new; };

has functions => \&GPForum::Infrastructure::SqlFunction::for_service;

# Each write and read is written once, as its promise method (ADR 0177).
GPForum::Infrastructure::SqlFunction->blocking_twins(
    qw(create_role create_permission attach_permission list_roles
      list_permissions)
);

# The three catalog writes run inside the caller's transaction ($scope, the
# call layer transaction_p hands its work) or in one of their own. Each
# reuses the row already stored -- committed by an earlier attempt, or by a
# concurrent request that won a unique key -- completing its audit entry if
# that attempt left none; else it creates the row in a savepoint with its
# audit entry. A minted id that collided with no such row is minted once
# more.
async sub create_role_p ( $self, $input, $context = undef, $scope = undef ) {
    return await $self->_catalog_write_p(
        {
            source   => 'Role',
            query    => { name => $input->{name} },
            id_key   => $ROLE_ID_CONSTRAINT,
            keys     => [$ROLE_NAME_CONSTRAINT],
            insert   => 'admin_insert_role',
            row      => sub { return $self->_new_role($input); },
            audit    => sub ($row) { return _role_audit( $input, $row ); },
            leftover => sub ($row) {
                return _leftover_role_audit( $row, $input );
            },
            columns => [ _role_columns() ],
        },
        $context,
        $scope
    );
}

# A permission is one per resource type and action, whatever its name: a
# conflict on either key is answered by the permission stored for the pair.
async sub create_permission_p ( $self, $input, $context = undef,
    $scope = undef )
{
    return await $self->_catalog_write_p(
        {
            source => 'Permission',
            query  => {
                action        => $input->{action},
                resource_type => $input->{resource_type},
            },
            id_key => $PERMISSION_ID_CONSTRAINT,
            keys   =>
              [ $PERMISSION_NAME_CONSTRAINT, $PERMISSION_ACTION_CONSTRAINT ],
            insert => 'admin_insert_permission',
            row    => sub { return $self->_new_permission($input); },
            audit  => sub ($row) { return _permission_audit( $input, $row ); },
            leftover => sub ($row) {
                return _leftover_permission_audit( $row, $input );
            },
            columns => [ _permission_columns() ],
        },
        $context,
        $scope
    );
}

async sub attach_permission_p ( $self, $input, $context = undef,
    $scope = undef )
{
    return await $self->_catalog_write_p(
        {
            source => 'RolePermission',
            query  => {
                role_id       => $input->{role_id},
                permission_id => $input->{permission_id},
            },
            keys   => [$ROLE_PERMISSION_CONSTRAINT],
            insert => 'admin_insert_role_permission',
            row    => sub { return $self->_new_attachment($input); },
            audit  => sub ($row) { return _attachment_audit( $input, $row ); },
            leftover => sub ($row) {
                return _leftover_attachment_audit( $row, $input );
            },
            columns => [ _role_permission_columns() ],
        },
        $context,
        $scope
    );
}

async sub _catalog_write_p ( $self, $job, $context, $scope ) {
    my $work = sub ($functions) {
        return $self->_reuse_or_create_p( $functions, $job, $context );
    };
    return await(
          $scope
        ? $work->($scope)
        : $self->_functions->transaction_p( $work, $context )
    );
}

async sub _reuse_or_create_p ( $self, $functions, $job, $context ) {
    my $find = sub {
        return $self->_single_row_p( $functions, $job->{source}, $job->{query},
            $context );
    };
    my $existing = await $find->();
    return await $self->_finish_leftover_p( $functions, $job, $existing,
        $context )
      if $existing;

    my $create = async sub ($savepoint) {
        my $row = $job->{row}->();
        await $savepoint->row_p( $job->{insert}, { values => $row }, $context );
        await $self->_record_admin_audit_p( $savepoint, $job->{audit}->($row),
            $context );
        return $row;
    };
    for my $retry ( 0, 1 ) {
        my ( $created, $error ) =
          await GPForum::Infrastructure::UniqueConflict->attempt_p( $functions,
            $create );
        return $created if $created;

        my $on =
          $retry
          ? q{}
          : _conflict_on( $error, $job->{id_key}, @{ $job->{keys} } );
        if ( !$on ) {
            GPForum::Infrastructure::UniqueConflict->rethrow($error);
        }
        $existing = await $find->();
        return await $self->_finish_leftover_p( $functions, $job, $existing,
            $context )
          if $existing;
        if ( $on ne 'id' ) {
            GPForum::Infrastructure::UniqueConflict->rethrow($error);
        }
    }
    return;
}

# Which key a unique conflict is on: the minted id's (id), another of the
# row's keys (key), or none of them (an empty string).
sub _conflict_on ( $error, $id_key, @keys ) {
    my $conflict = GPForum::X::Conflict->caught($error);
    return q{}  if !$conflict;
    return 'id' if $id_key && $conflict->on($id_key);
    return ( any { $conflict->on($_) } @keys ) ? 'key' : q{};
}

# An attachment's entry targets the role, as the entry of every other
# permission attached to that role does; only its metadata names the
# permission. Matched on the role alone, an attachment whose entry was lost
# passed for audited as soon as any other permission of the role had been.
# So the role's attachment entries are read -- one per permission attached
# to it, and only on this leftover path -- and the pair is matched here.
async sub _finish_leftover_p ( $self, $functions, $job, $existing, $context ) {
    my $audit = $job->{leftover}->($existing);
    my $recorded =
      $audit->{action} eq $ATTACHED_ACTION
      ? _attachment_audited(
        await $functions->rows_p(
            'admin_attachment_audits',
            { map { $_ => $audit->{$_} } qw(action target_id target_type) },
            $context
        ),
        $audit
      )
      : await $self->_single_row_p( $functions, q{AuditLog},
        { action => $audit->{action}, target_id => $audit->{target_id} },
        $context );
    if ( !$recorded ) {
        await $self->_record_admin_audit_p( $functions,
            $self->_missing_audit($audit), $context );
    }

    return {
        ( map { $_ => column_of( $existing, $_ ) } @{ $job->{columns} } ),
        idempotent => 1
    };
}

async sub _single_row_p ( $self, $functions, $resultset_name, $query, $context )
{
    return GPForum::Infrastructure::ResultRow->from(
        await $functions->row_p(
            $LOOKUP{$resultset_name},
            { query => $query }, $context
        )
    );
}

sub _record_admin_audit_p ( $self, $functions, $input, $context ) {
    return $functions->row_p(
        'ops_record_audit',
        $self->recorder->audit_call(
            %{ $self->events->catalog_audit($input) }
        ),
        $context
    );
}

# Whether one of the role's attachment entries names this permission.
sub _attachment_audited ( $rows, $job ) {
    my $wanted = $job->{metadata};
    for my $audit ( @{$rows} ) {
        return 1
          if _same_id( $audit->{metadata}{role_id}, $wanted->{role_id} )
          && _same_id( $audit->{metadata}{permission_id},
            $wanted->{permission_id} );
    }
    return 0;
}

# Roles ordered by name; every role without a limit.
async sub list_roles_p ( $self, $options, $context = undef ) {
    return _result_rows(
        await $self->_functions->rows_p(
            'admin_list_roles', { row_limit => ( $options || {} )->{limit} },
            $context
        )
    );
}

# Permissions ordered by resource type, action and name; every permission
# without a limit.
async sub list_permissions_p ( $self, $options, $context = undef ) {
    return _result_rows(
        await $self->_functions->rows_p(
            'admin_list_permissions',
            { row_limit => ( $options || {} )->{limit} },
            $context
        )
    );
}

sub _result_rows ($rows) {
    return [ map { GPForum::Infrastructure::ResultRow->from($_) } @{$rows} ];
}

sub _new_role ( $self, $input ) {
    return {
        role_id     => $self->id_service->uuid,
        name        => $input->{name},
        description => $input->{description} || q{},
        created_at  => $self->clock->now_iso8601,
    };
}

sub _role_audit ( $input, $role ) {
    return {
        action        => 'role.created',
        actor_user_id => $input->{actor_user_id},
        target_type   => 'role',
        target_id     => $role->{role_id},
        metadata      => {
            description => $role->{description},
            name        => $role->{name},
        },
        created_at => $role->{created_at},
    };
}

sub _leftover_role_audit ( $existing, $input ) {
    return {
        action        => 'role.created',
        actor_user_id => $input->{actor_user_id},
        created_at    => column_of( $existing, 'created_at' ),
        metadata      => {
            description => column_of( $existing, 'description' ),
            name        => column_of( $existing, 'name' ),
        },
        target_id   => column_of( $existing, 'role_id' ),
        target_type => 'role',
    };
}

sub _new_permission ( $self, $input ) {
    return {
        permission_id => $self->id_service->uuid,
        name          => $input->{name},
        resource_type => $input->{resource_type},
        action        => $input->{action},
        created_at    => $self->clock->now_iso8601,
    };
}

sub _permission_audit ( $input, $permission ) {
    return {
        action        => 'permission.created',
        actor_user_id => $input->{actor_user_id},
        target_type   => 'permission',
        target_id     => $permission->{permission_id},
        metadata      => {
            action        => $permission->{action},
            name          => $permission->{name},
            resource_type => $permission->{resource_type},
        },
        created_at => $permission->{created_at},
    };
}

sub _leftover_permission_audit ( $existing, $input ) {
    return {
        action        => 'permission.created',
        actor_user_id => $input->{actor_user_id},
        created_at    => column_of( $existing, 'created_at' ),
        metadata      => {
            action        => column_of( $existing, 'action' ),
            name          => column_of( $existing, 'name' ),
            resource_type => column_of( $existing, 'resource_type' ),
        },
        target_id   => column_of( $existing, 'permission_id' ),
        target_type => 'permission',
    };
}

sub _new_attachment ( $self, $input ) {
    return {
        role_id       => $input->{role_id},
        permission_id => $input->{permission_id},
        created_at    => $self->clock->now_iso8601,
    };
}

sub _attachment_audit ( $input, $role_permission ) {
    return {
        action        => $ATTACHED_ACTION,
        actor_user_id => $input->{actor_user_id},
        target_type   => 'role',
        target_id     => $role_permission->{role_id},
        metadata      => {
            permission_id => $role_permission->{permission_id},
            role_id       => $role_permission->{role_id},
        },
        created_at => $role_permission->{created_at},
    };
}

sub _leftover_attachment_audit ( $existing, $input ) {
    return {
        action        => $ATTACHED_ACTION,
        actor_user_id => $input->{actor_user_id},
        created_at    => column_of( $existing, 'created_at' ),
        metadata      => {
            permission_id => column_of( $existing, 'permission_id' ),
            role_id       => column_of( $existing, 'role_id' ),
        },
        target_id   => column_of( $existing, 'role_id' ),
        target_type => 'role',
    };
}

sub _missing_audit ( $self, $job ) {
    return {
        action        => $job->{action},
        actor_user_id => $job->{actor_user_id},
        created_at    => $job->{created_at} || $self->clock->now_iso8601,
        metadata      => $job->{metadata},
        target_id     => $job->{target_id},
        target_type   => $job->{target_type},
    };
}

# Ids are UUIDs, and the metadata keeps one as the command spelled it.
# PostgreSQL also reads a uuid in upper case, in braces or with its hyphens
# moved or left out, and hands back the canonical form; lower-casing alone
# missed the other spellings and wrote a second entry on every repeat.
sub _same_id ( $recorded, $wanted ) {
    return 0 if !defined $recorded || !defined $wanted;

    return _id_key($recorded) eq _id_key($wanted) ? 1 : 0;
}

# The bare lower-case digits of a uuid. Anything else -- the test doubles'
# ids -- is compared lower-cased as it is.
sub _id_key ($id) {
    my $digits = ( lc $id ) =~ tr/{}-//dr;

    return
      length $digits == $UUID_DIGITS && $digits !~ m/[^[:xdigit:]]/msx
      ? $digits
      : lc $id;
}

sub _role_columns {
    return qw(role_id name description created_at);
}

sub _permission_columns {
    return qw(permission_id name resource_type action created_at);
}

sub _role_permission_columns {
    return qw(role_id permission_id created_at);
}

sub _functions ($self) {
    return $self->functions // GPForum::X::Unavailable->throw(
        message => 'the role catalog needs the PostgreSQL function layer' );
}

1;

__END__

=head1 NAME

GPForum::Service::Admin::RoleCatalog - Creates roles and permissions and attaches one to the other.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $catalog = GPForum::Service::Admin::RoleCatalog->new( schema => $schema );
    my $role = $catalog->create_role(
        {
            actor_user_id => $admin_id,
            name          => 'moderator',
            description   => 'Moderates the public categories',
        }
    );
    my $permission = $catalog->create_permission(
        {
            actor_user_id => $admin_id,
            name          => 'thread.hide',
            resource_type => 'thread',
            action        => 'hide',
        }
    );
    $catalog->attach_permission(
        {
            actor_user_id => $admin_id,
            role_id       => $role->{role_id},
            permission_id => $permission->{permission_id},
        }
    );
    my $roles = $catalog->list_roles( { limit => 50 } );

=head1 DESCRIPTION

The persistence behind the console's role catalog: C<roles>,
C<permissions> and C<role_permissions>, each write with its audit entry
(C<role.created>, C<permission.created>, C<role_permission.attached>).
L<GPForum::Service::Admin::Workflow> calls it for the console's commands,
and L<GPForum::Service::Admin::Bootstrapper> for the owner's role. A row
and its audit entry commit together, in the caller's transaction or in one
the write opens.

Every write is idempotent. A role is found by name, a permission by
resource type and action, an attachment by role and permission; when the
row is already there it is returned as it is, marked C<idempotent>, and
the audit entry is written only if none exists yet, so a command that
stopped between its row and its audit is completed rather than repeated.

A new row is inserted inside a savepoint
(L<GPForum::Infrastructure::UniqueConflict/attempt_p>). When the insert
loses a race on the natural key, the row the other request inserted is
returned instead. When it collides on the generated id, the natural key is
looked up again and, if there is still no row, the insert is retried once
with a fresh id.

=head1 SUBROUTINES/METHODS

Each write and read is written once, as its promise method; the blocking
methods are those bodies settled on the blocking layer (ADR 0177). Each
write takes an optional query context and the call layer of the caller's
transaction, when the write joins it; without one it runs in a transaction
of its own.

=head2 create_role_p

Takes a hash reference with C<name>, an optional C<description> (empty
when omitted) and the C<actor_user_id> to audit. Resolves with a hash
reference with C<role_id>, C<name>, C<description> and C<created_at>; for a
role that already had that name, the existing row's values with
C<< idempotent => 1 >>. C<create_role> is its blocking twin.

=head2 create_permission_p

Takes a hash reference with C<name>, C<resource_type>, C<action> and the
C<actor_user_id> to audit. Resolves with a hash reference with
C<permission_id>, C<name>, C<resource_type>, C<action> and C<created_at>;
for a resource type and action that already had a permission, the
existing row's values with C<< idempotent => 1 >>. C<create_permission> is
its blocking twin.

=head2 attach_permission_p

Takes a hash reference with C<role_id>, C<permission_id> and the
C<actor_user_id> to audit. Resolves with a hash reference with C<role_id>,
C<permission_id> and C<created_at>; for a pair already attached, the
existing row's values with C<< idempotent => 1 >>.
C<attach_permission> is its blocking twin.

An attachment's audit entry targets the role and names the permission in
its metadata, so the check for a missing entry reads the role's
C<role_permission.attached> entries and matches the role and permission
pair; an entry for another permission of the same role does not count.
The metadata keeps each id as the command spelled it, so ids are compared
as PostgreSQL reads a uuid: whatever the case, braces or hyphens.

=head2 list_roles_p

Takes a hash reference (or undef) with an optional C<limit>, without which
every role is read, and an optional query context. Resolves with an array
reference of role rows ordered by name. C<list_roles> is its blocking twin.

=head2 list_permissions_p

Takes a hash reference (or undef) with an optional C<limit>, without which
every permission is read, and an optional query context. Resolves with an
array reference of permission rows ordered by resource type, action and
name. C<list_permissions> is its blocking twin.

=head1 DIAGNOSTICS

A database error, and any unique violation that cannot be resolved to an
existing row, is rethrown with L<Carp/croak>: a second id collision, or a
permission name already used for a different resource type and action.
Throws L<GPForum::X::Unavailable> without the function layer.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<Const::Fast>, L<GPForum::Base>, L<List::Util>,
L<GPForum::Infrastructure::SqlFunction>,
L<GPForum::Infrastructure::EventRecorder>,
L<GPForum::Infrastructure::Id>, L<GPForum::Infrastructure::Row>,
L<GPForum::Infrastructure::UniqueConflict>, L<GPForum::X::Conflict>,
L<GPForum::Service::Admin::Event>, L<GPForum::Service::Clock>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Repeating C<create_role_p> with a different description returns the
existing role unchanged; nothing is updated.

The check for a lost attachment entry reads every
C<role_permission.attached> entry of the role, one per permission attached
to it, because only the metadata names the permission. It runs only when
the pair is already attached, never on a first attachment.

Completing a lost entry is not serialised. The existing role, permission or
attachment is read without a row lock and its entry looked for before
anything is written, so two commands that find the same row without its
entry at the same moment can both write one.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
