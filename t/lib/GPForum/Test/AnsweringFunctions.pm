# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::AnsweringFunctions;

use Mojo::Base 'GPForum::Test::SettledCalls', -signatures;
use v5.40;

our $VERSION = '0.001';

# A call layer that answers each function by name with the rows a test
# gives -- a list, or a code reference given the call's values -- and
# records every call. A function it was given nothing for answers no rows.
has answers => sub { return {}; };
has calls   => sub { return []; };

sub rows ( $self, $name, $values ) {
    push @{ $self->calls }, [ $name, $values ];
    my $answer = $self->answers->{$name} // [];
    my $rows   = ref $answer eq 'CODE' ? $answer->($values) : $answer;

    return [ map { +{ %{$_} } } @{$rows} ];
}

sub row ( $self, $name, $values ) {
    return $self->rows( $name, $values )->[0];
}

# A key that names a call, as the function layer's names a call answered
# ahead: here the function's name and its values, sorted.
sub answer_key ( $self, $name, $values ) {
    return join "\0", $name,
      map { $_ => $values->{$_} // q{} } sort keys %{$values};
}

# The calls made to one function, as their values.
sub asked ( $self, $name ) {
    return [ map { $_->[1] } grep { $_->[0] eq $name } @{ $self->calls } ];
}

1;

__END__

=head1 NAME

GPForum::Test::AnsweringFunctions - A call layer double answering each
function with the rows a test gives.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $functions = GPForum::Test::AnsweringFunctions->new(
        answers => { forum_list_categories => [ { title => 'General' } ] } );
    my $reader = GPForum::Service::Forum::CategoryReader->new(
        functions => $functions, schema => {} );
    my $limit = $functions->asked('forum_list_categories')->[0]{row_limit};

=head1 DESCRIPTION

Stands in for L<GPForum::Infrastructure::SqlFunction> where a test checks
what a store does with the rows a function answers, and what it asks. Its
promises are settled (L<GPForum::Test::SettledCalls>), so a store's promise
methods and their blocking twins both run on it.

=head1 SUBROUTINES/METHODS

=head2 answers

Function name to its rows: an array reference of hashes, or a code
reference given the call's values that returns one. Each answer is a copy.

=head2 calls

Each call made, as C<[ $name, $values ]>.

=head2 rows

Records the call and answers the function's rows; none for a function the
test gave nothing for.

=head2 row

The first of L</rows>, or undef.

=head2 answer_key

Takes a function's name and values; a key that names the call.

=head2 asked

Takes a function name; the values of each call made to it, in order.

=head1 DIAGNOSTICS

None.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Test::SettledCalls>.

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
