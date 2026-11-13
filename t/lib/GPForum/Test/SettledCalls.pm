# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::SettledCalls;

use Mojo::Base -base, -signatures;
use v5.40;

use Mojo::Promise;

our $VERSION = '0.001';

# A call layer double speaks the whole contract of ADR 0177: its promises
# are settled when they are made, as the blocking layer's are, so a store's
# promise methods and their blocking twins both run on it. A subclass
# answers row and rows.
sub blocking ($self) { return 1; }

sub blocking_layer ($self) { return $self; }

sub row_p ( $self, $name, $values, $context = undef ) {
    return _settled( sub { return $self->row( $name, $values ); } );
}

sub rows_p ( $self, $name, $values, $context = undef ) {
    return _settled( sub { return $self->rows( $name, $values ); } );
}

# A savepoint or a transaction of nothing: the work runs on this layer.
sub transaction_p ( $self, $work, $context = undef, $readonly = 0 ) {
    return $work->($self);
}

# No caller's transaction is open around the double.
sub in_transaction ($self) { return 0; }

# The answer as a resolved promise, or its failure as a rejected one, as an
# async sub answers.
sub _settled ($answer) {
    my $promise;
    try { $promise = Mojo::Promise->resolve( $answer->() ); }
    catch ($error) { $promise = Mojo::Promise->reject($error); };

    return $promise;
}

1;

__END__

=head1 NAME

GPForum::Test::SettledCalls - The promise half of a call layer double.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    package GPForum::Test::RecordingFunctions;
    use Mojo::Base 'GPForum::Test::SettledCalls', -signatures;

    sub row  ( $self, $name, $values ) { ... }
    sub rows ( $self, $name, $values ) { ... }

=head1 DESCRIPTION

The base of the doubles that stand in for
L<GPForum::Infrastructure::SqlFunction>. A subclass answers C<row> and
C<rows>; this class answers C<row_p> and C<rows_p> with those answers as
settled promises, and is its own blocking layer (ADR 0177).

=head1 SUBROUTINES/METHODS

=head2 blocking

True: the double's promises are settled when they are made.

=head2 blocking_layer

The double itself.

=head2 row_p

C<row>'s answer as a settled promise; a failure of C<row> is a settled
rejection, as the blocking layer's is.

=head2 transaction_p

Runs the work on the double itself, as a transaction of it would: the work
answers the promise.

=head2 in_transaction

0: no caller's transaction is open around the double.

=head2 rows_p

C<rows>'s answer as a settled promise.

=head1 DIAGNOSTICS

None.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<Mojo::Base>, L<Mojo::Promise>.

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
