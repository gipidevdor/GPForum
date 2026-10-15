# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Infrastructure::SqlFunction::Retained;

use Mojo::Base 'GPForum::Infrastructure::SqlFunction', -signatures;
use v5.40;

our $VERSION = '0.001';

# The call layer for a retained version: a reader sends the values of
# today's call, and a version shipped before one of them took the
# arguments of its day. The value no parameter of the entry names is
# dropped before the call; an entry's own parameters are still all
# required, as the real layer requires them. The search optimisation test
# and the paired benchmark call the retained search versions through it.
sub rows ( $self, $name, $values ) {
    return $self->SUPER::rows( $name, $self->_theirs( $name, $values ) );
}

sub statement ( $self, $name, $values ) {
    return $self->SUPER::statement( $name, $self->_theirs( $name, $values ) );
}

sub _theirs ( $self, $name, $values ) {
    my %known = map { $_ => 1 } @{ $self->catalogue->function($name)->{names} };
    return {
        map  { $_ => $values->{$_} }
        grep { exists $known{$_} } keys %{$values}
    };
}

1;

__END__

=head1 NAME

GPForum::Infrastructure::SqlFunction::Retained - Call a retained function version with the arguments of its day.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $functions = GPForum::Infrastructure::SqlFunction::Retained->new(
        catalogue => $catalogue_at_that_version,
        schema    => $schema,
    );

=head1 DESCRIPTION

A L<GPForum::Infrastructure::SqlFunction> whose C<rows> and C<statement>
drop every value the catalogue entry names no parameter for, so a Searcher
of today can call a search version shipped before one of its arguments.

=head1 SUBROUTINES/METHODS

=head2 rows

As the parent's, with the unknown values dropped.

=head2 statement

As the parent's, with the unknown values dropped.

=head1 DIAGNOSTICS

None of its own.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Infrastructure::SqlFunction>.

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
