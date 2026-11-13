# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Admin::PermissionGate;

use Mojo::Base 'GPForum::Base', -async_await;
use v5.40;

use GPForum::Infrastructure::SqlFunction;
use GPForum::X::Unavailable;

our $VERSION = '0.001';

__PACKAGE__->requires(qw(schema));
has functions => \&GPForum::Infrastructure::SqlFunction::for_service;

# Each check is written once, as its promise method (ADR 0177).
GPForum::Infrastructure::SqlFunction->blocking_twins(
    qw(allowed navigation_context));

async sub allowed_p ( $self, $actor, $permission, $context = undef ) {
    my $user_id = _user_id($actor);
    return 0 if !defined $user_id || !length $user_id;
    my $row = await $self->_functions->row_p(
        'admin_permission_allowed',
        {
            user_id       => $user_id,
            resource_type => $permission->{resource_type},
            action        => $permission->{action},
            resource_id   => _scope_value( $permission->{resource_id} ),
            space_id      => _scope_value( $permission->{space_id} ),
        },
        $context
    );
    return $row && $row->{allowed} ? 1 : 0;
}

# This advisory lookup belongs only to the menu page. Destinations still
# authorize their own requests; no permission snapshot is kept in a session.
async sub navigation_context_p ( $self, $actor, $context = undef ) {
    my $user_id = _user_id($actor);
    return { available => 1, permissions => {} }
      if !defined $user_id || !length $user_id;
    my $row = await $self->_functions->row_p( 'admin_navigation_context',
        { user_id => $user_id }, $context );
    return {
        available => 1,
        %{ $row // {} }, permissions => $row ? $row->{permissions} : {}
    };
}

# An empty scope is no scope: only a global binding answers it.
sub _scope_value ($value) {
    return defined $value && length $value ? $value : undef;
}

sub _user_id ($actor) {
    return                   if !defined $actor;
    return $actor->{user_id} if ref $actor eq 'HASH';

    return $actor;
}

sub _functions ($self) {
    return $self->functions // GPForum::X::Unavailable->throw(
        message => 'the permission gate needs the PostgreSQL function layer' );
}

1;

__END__

=head1 NAME

GPForum::Service::Admin::PermissionGate - Scope-aware role binding check.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $gate = GPForum::Service::Admin::PermissionGate->new( schema => $schema );

    my $global = $gate->allowed(
        { user_id       => $user_id },
        { resource_type => 'report', action => 'view_queue' },
    );

    my $scoped = $gate->allowed(
        { user_id => $user_id },
        {
            resource_type => 'thread',
            action        => 'moderate',
            resource_id   => $thread_id,
            space_id      => $space_id,
        },
    );

=head1 DESCRIPTION

Answers whether an actor holds a permission through an active role binding.
C<role_bindings> rows carry an optional C<resource_id> and C<space_id>; a row
with both columns NULL is a global grant, any other row is scoped to that
resource or space.

The check is deliberately fail-closed. A caller that supplies no scope is
only satisfied by global bindings, so a binding scoped to one category or
space can never authorize an unscoped action. A caller that supplies a scope
is satisfied by global bindings and by bindings whose C<resource_id> and
C<space_id> both equal the requested scope; a partial match does not count.

=head1 SUBROUTINES/METHODS

=head2 allowed_p

Takes an actor (a user id, or a hash with C<user_id>), a permission hash
with C<resource_type> and C<action>, plus optional C<resource_id> and
C<space_id> naming the scope the caller is acting on, and an optional query
context. Resolves with 1 when an unrevoked role binding grants the
permission at global scope or at exactly the requested scope
(C<api.admin_permission_allowed>), and 0 otherwise. An empty string scope
is treated as no scope; an actor without a user id is refused before any
statement. C<allowed> is its blocking twin.

=head2 navigation_context_p

Takes an actor and an optional query context. Resolves with the active
account's username and the finite set of global permissions the menu uses,
read in one statement (C<api.admin_navigation_context>). Scoped, revoked
and suspended grants do not expose staff links. This does not authorize
destination controllers, and the answer belongs to this request: it is
never kept in the session. C<navigation_context> is its blocking twin.

=head1 DIAGNOSTICS

The gate answers 0 rather than throwing for unknown actors. Throws
L<GPForum::X::Unavailable> without the function layer.

=head1 CONFIGURATION AND ENVIRONMENT

Requires a L<GPForum::Schema>, whose function layer answers both checks.
C<gpforum admin> creates the first binding with both scope columns NULL, so
bootstrap grants stay global.

=head1 DEPENDENCIES

Uses L<GPForum::Base> and L<GPForum::Infrastructure::SqlFunction>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Does not resolve a scoped resource to its parent category or space, so a
category-scoped binding does not authorize an action addressed by thread or
post id. Callers pass the scope they are acting on.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
