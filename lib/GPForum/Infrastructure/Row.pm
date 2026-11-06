# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Infrastructure::Row;

use Mojo::Base -base, -signatures;
use v5.40;

our $VERSION = '0.001';

# One reader for "a row that may be a hashref or a DBIx::Class row".
#
# There were forty-one hand-copied versions of this in lib/, in thirteen
# distinct spellings, and they did not agree on what to return when the row
# answers neither shape. Six ended in a bare `return;`, which yields the empty
# LIST in list context -- and every one of those was called from inside a hash
# literal:
#
#     calculated_at => _column( $row, 'calculated_at' ),
#     score         => _column( $row, 'score' ),
#
# With a row that was not found, the pairs collapse and every subsequent key
# shifts by one: calculated_at takes the value 'score', trust_level takes
# 'user_id', and the user id becomes a key. Perl reports only "Odd number of
# elements in hash assignment".
#
# This returns undef, in scalar and list context alike, so a missing row
# produces a missing value rather than a corrupted hash.
sub column ( $, $row, $name ) {
    return undef         if !defined $row;
    return $row->{$name} if ref $row eq 'HASH';

    # UNIVERSAL::can by name: a row double is free to define its own can(),
    # and asking the object would then answer a different question.
    ## no critic (BuiltinFunctions::ProhibitUniversalCan)
    return $row->get_column($name)
      if UNIVERSAL::can( $row, 'get_column' );
    ## use critic

    return undef;
}

# Loaded values in one snapshot where the row supports it. A plain hash is
# borrowed for reading; a column-only row is read under the requested names.
sub columns ( $, $row, @names ) {
    return {}   if !defined $row;
    return $row if ref $row eq 'HASH';

    ## no critic (BuiltinFunctions::ProhibitUniversalCan) -- row classes may override can
    return { $row->get_columns } if UNIVERSAL::can( $row, 'get_columns' );
    return { map { $_ => $row->get_column($_) } @names }
      if UNIVERSAL::can( $row, 'get_column' );
    ## use critic

    return {};
}

# Optional join columns may be absent from an otherwise valid row. Never
# request an unloaded DBIx::Class column, which would throw rather than miss.
sub loaded_column ( $class, $row, $name ) {
    return undef         if !defined $row;
    return $row->{$name} if ref $row eq 'HASH';

    ## no critic (BuiltinFunctions::ProhibitUniversalCan) -- row classes may override can
    if ( UNIVERSAL::can( $row, 'has_column_loaded' ) ) {
        return undef if !$row->has_column_loaded($name);
    }
    elsif ( UNIVERSAL::can( $row, 'result_source' ) ) {
        my $source = $row->result_source;
        return undef
          if $source
          && $source->can('has_column')
          && !$source->has_column($name);
    }
    ## use critic

    return $class->column( $row, $name );
}

# A search's rows as a list: a DBIx::Class resultset's, a double's that
# answers rows, an array reference's own, nothing for anything else. There
# were twenty-two copies of this, four of them different.
sub rows_of ( $, $search ) {
    return ()         if !$search;
    return @{$search} if ref $search eq 'ARRAY';
    ## no critic (BuiltinFunctions::ProhibitUniversalCan) -- collection adapters may override can, and unsupported references have no methods
    return $search->all       if UNIVERSAL::can( $search, 'all' );
    return @{ $search->rows } if UNIVERSAL::can( $search, 'rows' );
    ## use critic

    return ();
}

# Whether a row is there and its column holds this value, undef reading as
# the empty string.
sub belongs ( $class, $row, $column, $value ) {
    return 0 if !$row;

    return ( $class->column( $row, $column ) // q{} ) eq ( $value // q{} )
      ? 1
      : 0;
}

# A row with these changes made: a hash's in place, a DBIx::Class row's
# written through update. Returns the row.
sub updated ( $, $row, $changes ) {
    if ( ref $row eq 'HASH' ) {
        @{$row}{ keys %{$changes} } = values %{$changes};

        return $row;
    }
    $row->update($changes);

    return $row;
}

1;

__END__

=head1 NAME

GPForum::Infrastructure::Row - Single reader for hashref or resultset rows.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $score = GPForum::Infrastructure::Row->column( $row, 'score' );

=head1 DESCRIPTION

Reads one column from a row that may be a plain hashref or a DBIx::Class row,
and returns undef when it is neither or when the row is missing. Never returns
the empty list, so the result is safe inside a hash literal.

=head1 SUBROUTINES/METHODS

=head2 column

Returns the named column, or undef.

=head2 columns

Takes a row and optional column names. Returns its loaded values as a hash
reference: a plain hash is borrowed for reading, an object with C<get_columns>
supplies a snapshot, and an object with only C<get_column> is read under the
requested names. Missing or unsupported rows return an empty hash reference.
Callers must not modify a borrowed hash.

=head2 loaded_column

An optional column, or undef in both scalar and list context. Uses
C<has_column_loaded> where available to avoid requesting an unloaded join
column. Older row adapters with only C<result_source> are checked against
their source's columns; column-only adapters retain ordinary C<column>
behavior. This method never fetches a relationship or runs a query.

=head2 rows_of

Takes a resultset, a double that answers C<all> or C<rows>, or an array
reference, and returns its rows as a list; the empty list for anything
else, undef included.

=head2 belongs

Takes a row, a column and a value; returns 1 when the row is there and the
column holds the value (undef as the empty string), 0 otherwise.

=head2 updated

Takes a row and a hash reference of changes and makes them: on a hash
reference in place, on a DBIx::Class row through C<update>. Returns the
row.

=head1 DIAGNOSTICS

This module does not throw its own exceptions.

=head1 CONFIGURATION AND ENVIRONMENT

No environment variables are read.

=head1 DEPENDENCIES

Uses L<Mojo::Base>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Callers that need a column accessor rather than C<get_column>, or that want a
missing row to be fatal, keep their own reader.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
