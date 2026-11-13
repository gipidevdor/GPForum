# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::FailingUnreadCount;

use Mojo::Base 'GPForum::Infrastructure::SqlFunction', -async_await;
use v5.40;

our $VERSION = '0.001';

# The blocking call layer, whose unread count fails in PostgreSQL: the
# statement divides by zero with the member's id bound, so the error aborts
# the transaction it runs in and DBI appends the statement and that id to
# its line, as a real failed count does. Every other call runs as it is.
async sub rows_p ( $self, $name, $values, $context = undef ) {
    if ( $name eq 'notification_unread_count' ) {
        my $storage = $self->schema->storage;
        $storage->database->query(
            'SELECT 1 / 0 WHERE CAST(? AS uuid) IS NOT NULL',
            $values->{recipient_user_id} );
    }

    return await $self->SUPER::rows_p( $name, $values, $context );
}

1;

__END__

=head1 NAME

GPForum::Test::FailingUnreadCount - A blocking call layer whose unread count fails in PostgreSQL.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $functions = GPForum::Test::FailingUnreadCount->new(
        schema => $schema, blocking => 1 );

=head1 DESCRIPTION

A L<GPForum::Infrastructure::SqlFunction> on which
C<notification_unread_count> raises PostgreSQL's division by zero, inside
the caller's transaction.

=head1 SUBROUTINES/METHODS

=head2 rows_p

The layer's own, after the failing statement for the unread count.

=head1 DIAGNOSTICS

The count dies with DBI's error.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Infrastructure::SqlFunction>.

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
