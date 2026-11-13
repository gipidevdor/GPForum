# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::TransactionFunctions;

use Mojo::Base 'GPForum::Test::AnsweringFunctions', -signatures;
use v5.40;

our $VERSION = '0.001';

# A call layer double that answers each function as AnsweringFunctions
# does, and records each transaction it runs: its mode and the functions
# called inside it, in order.
has transactions => sub { return []; };
has depth        => 0;

sub transaction_p ( $self, $work, $context = undef, $readonly = 0 ) {
    my $transaction = { readonly => $readonly ? 1 : 0, calls => [] };
    push @{ $self->transactions }, $transaction;
    my $first = @{ $self->calls };
    $self->depth( $self->depth + 1 );
    my $promise = $work->($self);
    $self->depth( $self->depth - 1 );
    $transaction->{calls} =
      [ map { $_->[0] } @{ $self->calls }[ $first .. $#{ $self->calls } ] ];

    return $promise;
}

sub in_transaction ($self) { return $self->depth ? 1 : 0; }

1;

__END__

=head1 NAME

GPForum::Test::TransactionFunctions - A call layer double recording the
transactions it runs.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $functions = GPForum::Test::TransactionFunctions->new(
        answers => { search_ranked => [] } );
    $searcher->ranked_search( undef, 'forum', {} );
    my $calls = $functions->transactions->[0]{calls};

=head1 DESCRIPTION

Answers each function as L<GPForum::Test::AnsweringFunctions> does. Each
C<transaction_p> runs its work on the double itself and is recorded, with
whether it was read-only and the functions called inside it.

=head1 SUBROUTINES/METHODS

=head2 transactions

Each transaction run, as a hash reference with C<readonly> (1 or 0) and
C<calls> (the names of the functions called inside it, in order).

=head2 depth

How many transactions are open.

=head2 transaction_p

Runs the work on the double, recording the transaction.

=head2 in_transaction

1 while a transaction is open, else 0.

=head1 DIAGNOSTICS

None.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<Mojo::Base>, L<GPForum::Test::AnsweringFunctions>.

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
