# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::LogLines;

use Mojo::Base -base, -signatures;
use v5.40;

our $VERSION = '0.001';

# A logger that keeps each line, its level in front, for a test to read.
has lines => sub { return []; };

sub error ( $self, $message ) {
    push @{ $self->lines }, "error $message";

    return;
}

## no critic (Subroutines::ProhibitBuiltinHomonyms)
# The name is the logger's: Mojo::Log's warning level is warn.
sub warn ( $self, $message ) {
    push @{ $self->lines }, "warn $message";

    return;
}
## use critic

1;

__END__

=head1 NAME

GPForum::Test::LogLines - A logger that keeps its lines.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $log = GPForum::Test::LogLines->new;
    $log->error('reply create failed: ...');
    # $log->lines: [ 'error reply create failed: ...' ]

=head1 DESCRIPTION

Answers the C<error> and C<warn> a service logs through, and keeps each
line with its level in front.

=head1 SUBROUTINES/METHODS

=head2 error

=head2 warn

Keep the message, after C<error> or C<warn>.

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
