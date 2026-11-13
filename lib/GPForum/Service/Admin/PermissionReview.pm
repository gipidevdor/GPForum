# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Admin::PermissionReview;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -signatures, -async_await;
use v5.40;

use GPForum::Infrastructure::SqlFunction;
use GPForum::Infrastructure::ResultRow;
use GPForum::X::Unavailable;

our $VERSION = '0.001';

const my $DEFAULT_LIMIT => 50;

__PACKAGE__->requires(qw(schema));

has functions => \&GPForum::Infrastructure::SqlFunction::for_service;

# The read is written once, as its promise method (ADR 0177).
GPForum::Infrastructure::SqlFunction->blocking_twins('roles_for_user');

async sub roles_for_user_p ( $self, $user_id, $options, $context = undef ) {
    my $rows = await $self->_functions->rows_p(
        'admin_roles_for_user',
        {
            user_id   => $user_id,
            row_limit => ( $options || {} )->{limit} || $DEFAULT_LIMIT
        },
        $context
    );
    return [ map { GPForum::Infrastructure::ResultRow->from($_) } @{$rows} ];
}

sub _functions ($self) {
    return $self->functions // GPForum::X::Unavailable->throw(
        message => 'the role review needs the PostgreSQL function layer' );
}

1;

__END__

=head1 NAME

GPForum::Service::Admin::PermissionReview - Lists a member's role bindings for the console.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $review = GPForum::Service::Admin::PermissionReview->new(
        schema => $schema,
    );
    my $bindings    = $review->roles_for_user( $user_id, { limit => 25 } );

=head1 DESCRIPTION

The read side of the console's role pages. It reads the C<role_bindings>
table and changes nothing; granting and revoking
roles happen elsewhere. A list is capped at C<limit> rows, 50 when the
option is missing or zero.

The console's user roles page (L<GPForum::Controller::Admin>) calls
L</roles_for_user_p>.

=head1 SUBROUTINES/METHODS

=head2 roles_for_user_p

Takes a user id, a hash reference of options, of which only C<limit> is
read, and an optional query context. Resolves with an array reference of
the member's role bindings that have not been revoked (C<revoked_at> is
null), ordered by C<resource_type> and then C<role_id>, at most C<limit> of
them (C<api.admin_roles_for_user>). C<roles_for_user> is its blocking twin.

=head1 DIAGNOSTICS

Throws L<GPForum::X::Unavailable> without the function layer. Database
errors propagate; the console logs them and answers with a system failure.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<Const::Fast>, L<GPForum::Base>; the C<schema> attribute is a
L<GPForum::Schema>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

There is no cursor: a member with more bindings than C<limit> shows only
the first page.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
