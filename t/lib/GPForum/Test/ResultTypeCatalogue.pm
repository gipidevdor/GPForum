# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::ResultTypeCatalogue;

use Mojo::Base -base, -signatures;
use v5.40;

our $VERSION = '0.001';

# The two probes of t/integration/postgres-sql-function-result-type.t, each
# a function of one integer that returns a table's row.
sub function ( $self, $name ) {
    my $function =
      $name eq 'once'
      ? 'api.ops_result_type_once_v1'
      : 'api.ops_result_type_probe_v1';

    return {
        function => $function,
        json     => {},
        names    => ['a'],
        sql      => "SELECT * FROM $function(?::integer)",
        types    => ['integer'],
    };
}

1;

__END__

=head1 NAME

GPForum::Test::ResultTypeCatalogue - A catalogue of two functions that return a table's row.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    GPForum::Infrastructure::SqlFunction->new(
        catalogue => GPForum::Test::ResultTypeCatalogue->new,
        schema    => $schema,
    )->rows( 'probe', { a => 1 } );

=head1 DESCRIPTION

Stands in for L<GPForum::Infrastructure::SqlFunctionCatalogue> where a test
calls functions it creates itself: C<once> names
C<api.ops_result_type_once_v1>, any other name
C<api.ops_result_type_probe_v1>.

=head1 SUBROUTINES/METHODS

=head2 function

The entry for a name, as the catalogue gives one.

=head1 DIAGNOSTICS

None.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<Mojo::Base>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

None known.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause
license.

=cut
