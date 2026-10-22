# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::RecordingFunctions;

use Mojo::Base -base, -signatures;
use v5.40;

our $VERSION = '0.001';

has calls => sub { return []; };

sub row ( $self, $name, $values ) {
    push @{ $self->calls }, [ $name, $values ];

    return undef;
}

sub rows ( $self, $name, $values ) {
    push @{ $self->calls }, [ $name, $values ];

    return [];
}

1;

__END__

=head1 NAME

GPForum::Test::RecordingFunctions - A function layer that records each call
and answers nothing.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $functions = GPForum::Test::RecordingFunctions->new;
    my $store = GPForum::Service::Forum::DraftStore->new(
        functions => $functions, schema => {} );
    is( scalar @{ $functions->calls }, 0, 'refused before the database' );

=head1 DESCRIPTION

Stands in for L<GPForum::Infrastructure::SqlFunction> when a test checks
that a store refuses input before it asks the database anything.

=head1 SUBROUTINES/METHODS

=head2 calls

Each call made, as C<[ $name, $values ]>.

=head2 row

Records the call and returns undef.

=head2 rows

Records the call and returns an empty list.

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
