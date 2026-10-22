# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Infrastructure::ResultRow;

use Mojo::Base -base, -signatures;
use v5.40;

our $VERSION = '0.001';

# A row a PostgreSQL function returned (ADR 0126), read the way the
# DBIx::Class rows it replaces were read. Readers hand their rows to
# controllers, views and tests that ask a row for get_column; until every
# area has moved, a function's row answers them the same way. It is the hash
# DBI fetched, blessed: no inflation, no accessors, no resultset.
sub from ( $class, $row ) {
    return undef if ref $row ne 'HASH';

    return bless $row, $class;
}

sub get_column ( $self, $name ) {
    return $self->{$name};
}

sub get_columns ($self) {
    return %{$self};
}

sub has_column_loaded ( $self, $name ) {
    return exists $self->{$name} ? 1 : 0;
}

1;

__END__

=head1 NAME

GPForum::Infrastructure::ResultRow - A function's row, read the way a DBIx::Class row was.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $row = GPForum::Infrastructure::ResultRow->from(
        $functions->row( 'forum_thread_page_head', { thread_id => $id } ) );
    my $title = $row->get_column('title');

=head1 DESCRIPTION

The rows L<GPForum::Infrastructure::SqlFunction> returns are hashes keyed by
the function's columns. A reader that used to return DBIx::Class rows blesses
them into this class, so every caller that asks a row for C<get_column>,
C<get_columns> or C<has_column_loaded> keeps working while ADR 0126 moves
the areas one by one. Nothing is inflated: a column is the value DBI
fetched.

=head1 SUBROUTINES/METHODS

=head2 from

The hash, blessed, or undef when there is none.

=head2 get_column

The column's value, or undef when the row has no such column.

=head2 get_columns

Every column and its value, as a list.

=head2 has_column_loaded

1 when the row has the column, else 0.

=head1 DIAGNOSTICS

None.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<Mojo::Base>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

The hash is blessed in place: the caller hands it over.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause
license.

=cut
