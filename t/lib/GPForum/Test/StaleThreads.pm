# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::StaleThreads;

use Mojo::Base -base, -signatures;
use v5.40;

use GPForum::Infrastructure::ResultRow;

our $VERSION = '0.001';

# The thread detail reader as the workflow's check before the lock saw it:
# the rows a test gives, by thread id, whatever the database holds now. A
# moderator's lock or an author's delete that commits after the check is
# what the store's check under the lock must still refuse.
has rows => sub { return {}; };

sub find_thread ( $self, $thread_id, $viewer = undef ) {
    my $row = $self->rows->{ lc( $thread_id // q{} ) };
    return undef if !$row;

    return GPForum::Infrastructure::ResultRow->from( { %{$row} } );
}

1;

__END__

=head1 NAME

GPForum::Test::StaleThreads - A thread reader that answers the rows it was given, as a check made earlier read them.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $reader = GPForum::Test::StaleThreads->new(
        rows => { $thread_id => { %columns, locked_at => undef } } );

=head1 DESCRIPTION

Stands for L<GPForum::Service::Forum::ThreadDetailReader> in a workflow
whose check before the lock must see a thread as it was before another
writer changed it.

=head1 SUBROUTINES/METHODS

=head2 find_thread

The row given for the thread id (any case), as a
L<GPForum::Infrastructure::ResultRow>, or undef.

=head1 DIAGNOSTICS

None.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<Mojo::Base>, L<GPForum::Infrastructure::ResultRow>.

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
