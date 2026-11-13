# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::CopyingRow;

use Mojo::Base 'GPForum::Test::Row';
use v5.40;

our $VERSION = '0.001';

# A row whose resultset keeps the hash it created the row from: an update
# builds a new hash rather than writing through to that one.
sub write_columns {
    my ( $self, $changes ) = @_;

    $self->data( { %{ $self->data }, %{$changes} } );

    return;
}

1;

__END__

=head1 NAME

GPForum::Test::CopyingRow - A row double that copies on write.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    package GPForum::Test::AttachmentRow;
    use Mojo::Base 'GPForum::Test::CopyingRow';

=head1 DESCRIPTION

The parent of the attachment, community, moderation and read-state row
doubles, whose resultsets keep the hash each row was created from.

=head1 SUBROUTINES/METHODS

=head2 write_columns

Takes a hash reference of changes and gives the row a new hash with them,
leaving the one its resultset holds as it was.

=head1 DIAGNOSTICS

None.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Test::Row>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

For tests only.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
