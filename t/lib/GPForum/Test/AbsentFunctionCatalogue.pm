# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::AbsentFunctionCatalogue;

use Mojo::Base -base, -signatures;
use v5.40;

our $VERSION = '0.001';

# A function catalogue naming one boundary no migration made: what api-role
# reads when it is run before gpforum migrate on an upgrade.

sub names ($self) {
    return ['absent'];
}

sub function ( $self, $name ) {
    return { function => 'api.absent_boundary_v1', types => ['uuid'] };
}

1;

__END__

=head1 NAME

GPForum::Test::AbsentFunctionCatalogue - A catalogue naming a function that
is not there.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    GPForum::Service::Operations::ApiRole->new(
        catalogue => GPForum::Test::AbsentFunctionCatalogue->new,
        dbh       => $dbh,
    );

=head1 DESCRIPTION

Stands in for L<GPForum::Infrastructure::SqlFunctionCatalogue> with one
entry, C<api.absent_boundary_v1(uuid)>, that no migration creates.

=head1 SUBROUTINES/METHODS

=head2 names

The one operation's name.

=head2 function

Its entry: the function's name and argument types.

=head1 DIAGNOSTICS

None.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<Mojo::Base>.

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
