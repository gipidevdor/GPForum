# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::SettledTwins;

use v5.40;

use Mojo::Promise;
use Mojo::Util qw(monkey_patch);

our $VERSION = '0.001';

# Gives a double the promise half of the contract a service speaks (ADR
# 0177): each named method's METHOD_p answers the double's own blocking
# answer, in scalar context, as a promise already settled -- resolved with
# it, or rejected with what it died with -- so the one body that awaits it
# runs to its end on either layer. Trailing arguments a promise method
# takes and the double does not (a query context) are dropped.
#
#     GPForum::Test::SettledTwins->install( __PACKAGE__, start => 0 );
#
# names each method with the number of arguments it takes, or undef for all.
sub install ( $class, $package, %arity ) {
    for my $method ( sort keys %arity ) {
        my $count = $arity{$method};
        monkey_patch $package, "${method}_p" => sub ( $self, @arguments ) {
            if ( defined $count && @arguments > $count ) {
                splice @arguments, $count;
            }
            return settled( sub { return scalar $self->$method(@arguments); } );
        };
    }

    return $package;
}

# The answer as a resolved promise, or its failure as a rejected one, as an
# async sub answers.
sub settled ($answer) {
    my $promise;
    try { $promise = Mojo::Promise->resolve( $answer->() ); }
    catch ($error) { $promise = Mojo::Promise->reject($error); };

    return $promise;
}

1;

__END__

=head1 NAME

GPForum::Test::SettledTwins - Settled promise methods for a test double's blocking answers.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    GPForum::Test::SettledTwins->install( __PACKAGE__,
        start => 0, poll_once => 0 );

=head1 DESCRIPTION

A double answers its blocking methods; this gives it each method's
C<METHOD_p>, settled when it is made, so a service's one promise body (ADR
0177) runs on it and on the blocking layer alike.

=head1 SUBROUTINES/METHODS

=head2 install

Takes the double's package and pairs of method name and argument count
(undef keeps every argument), and installs each C<METHOD_p>.

=head2 settled

Takes code and answers its scalar result as a resolved promise, or its
failure as a rejected one.

=head1 DIAGNOSTICS

None.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<Mojo::Promise>, L<Mojo::Util>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

None known.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
