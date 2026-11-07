# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Admin::PermissionReview;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -signatures;
use v5.40;

use GPForum::Infrastructure::Row;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Infrastructure::ResultRow;

our $VERSION = '0.001';

const my $DEFAULT_LIMIT => 50;

__PACKAGE__->requires(qw(schema));

has functions => \&GPForum::Infrastructure::SqlFunction::for_service;

sub roles_for_user ( $self, $user_id, $options ) {
    if ( $self->functions ) {
        return [
            map { GPForum::Infrastructure::ResultRow->from($_) } @{
                $self->functions->rows(
                    'admin_roles_for_user',
                    {
                        user_id   => $user_id,
                        row_limit => $options->{limit} || $DEFAULT_LIMIT
                    }
                )
            }
        ];
    }
    my $search = $self->schema->resultset('RoleBinding')->search_rs(
        {
            user_id    => $user_id,
            revoked_at => undef,
        },
        {
            order_by => [ { -asc => 'resource_type' }, { -asc => 'role_id' } ],
            rows     => $options->{limit} || $DEFAULT_LIMIT,
        }
    );

    return [ GPForum::Infrastructure::Row->rows_of($search) ];
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
L</roles_for_user>.

=head1 SUBROUTINES/METHODS

=head2 roles_for_user

Takes a user id and a hash reference of options, of which only C<limit> is
read. Returns an array reference of the member's C<RoleBinding> rows that
have not been revoked (C<revoked_at> is null), ordered by C<resource_type>
and then C<role_id>, at most C<limit> of them.

=head1 DIAGNOSTICS

None of its own. Database errors propagate; for L</roles_for_user> the
console logs them and answers with a system failure.

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
