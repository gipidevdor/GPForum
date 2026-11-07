# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::OutboxBenchmarkFunctions;

use Carp       qw(croak);
use List::Util qw(min);
use Mojo::Base -base, -signatures;
use v5.40;

our $VERSION = '0.001';

# The outbox's functions over a queue in memory that several dispatchers
# share, as workers share the table: each claim takes the next rows in
# order, and every write lands -- the ordinary case, a message still its
# worker's. What it measures is the dispatcher's own cost.

has cursor => 0;
has queue  => sub { return []; };

sub rows ( $self, $name, $arguments ) {
    croak "no rows of $name" if $name ne 'outbox_claim_ready';

    my $end =
      min( $self->cursor + $arguments->{row_limit}, scalar @{ $self->queue } );
    my @claimed = @{ $self->queue }[ $self->cursor .. $end - 1 ];
    $self->cursor($end);

    return [ map { +{ %{$_} } } @claimed ];
}

sub row ( $self, $name, $arguments ) {
    croak "no row of $name" if $name ne 'outbox_owned_write';
    return { landed => 1 };
}

1;

__END__

=head1 NAME

GPForum::Test::OutboxBenchmarkFunctions - The outbox's functions over a
shared queue in memory.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $functions =
      GPForum::Test::OutboxBenchmarkFunctions->new( queue => \@rows );
    my @workers = map {
        GPForum::Service::Outbox::Dispatcher->new(
            functions => $functions,
            worker_id => "bench-worker-$_",
            ...
        )
    } 1 .. 4;

=head1 DESCRIPTION

Stands in for L<GPForum::Infrastructure::SqlFunction> where the dispatcher
claims and writes, for F<script/bench-outbox-dispatcher>: C<outbox_claim_ready>
hands out the queue's next rows, C<outbox_owned_write> always lands.

=head1 SUBROUTINES/METHODS

=head2 queue

The rows to claim, in order.

=head2 cursor

How many have been claimed.

=head2 rows

C<outbox_claim_ready>: up to C<row_limit> of the next rows.

=head2 row

C<outbox_owned_write>: C<< { landed => 1 } >>.

=head1 DIAGNOSTICS

Croaks on a function it does not stand in for.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<Mojo::Base>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

For benchmarks and tests only.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
