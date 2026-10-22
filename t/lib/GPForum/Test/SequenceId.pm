# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::SequenceId;

use Mojo::Base 'GPForum::Infrastructure::Id', -signatures;
use v5.40;

our $VERSION = '0.001';

# Real uuids, the same sequence every time: two runs of the same writes on
# two databases, given one of these each, draw the same ids in the same
# order. A test lines up ids it wants drawn first (an id already stored, to
# make PostgreSQL raise the conflict a store recovers from).
has prefix   => '018f9000-0000-7000-8000';
has next_ids => sub { return []; };
has drawn    => 0;

sub uuid ($self) {
    my $scripted = shift @{ $self->next_ids };
    return $scripted if defined $scripted;

    $self->drawn( $self->drawn + 1 );

    return sprintf '%s-%012x', $self->prefix, $self->drawn;
}

1;

__END__

=head1 NAME

GPForum::Test::SequenceId - The same real uuids in the same order, after any a test lines up.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $ids = GPForum::Test::SequenceId->new( next_ids => [$taken] );
    $ids->uuid;    # $taken
    $ids->uuid;    # 018f9000-0000-7000-8000-000000000001

=head1 DESCRIPTION

An id service for tests that compare two runs of the same writes: the ids
are uuids PostgreSQL stores, drawn from C<prefix> and a counter, after the
ones C<next_ids> lines up.

=head1 SUBROUTINES/METHODS

=head2 uuid

The next lined-up id, else the next of the sequence.

=head1 DIAGNOSTICS

None.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Infrastructure::Id>.

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
