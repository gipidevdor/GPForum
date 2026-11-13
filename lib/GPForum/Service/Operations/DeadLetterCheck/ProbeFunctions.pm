# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Operations::DeadLetterCheck::ProbeFunctions;

use Carp qw(croak);
use Const::Fast;
use Mojo::Base -base, -signatures;
use v5.40;

use Mojo::Promise;

our $VERSION = '0.001';

const my $RUNNING => 'running';

has outbox  => undef;    # optional: a claim finds nothing without it
has letters => undef;    # optional: a dead letter is refused without it

# The probe's calls are answered at once, in the process: it is its own
# blocking layer (ADR 0177), and its transaction runs the work as it is.
sub blocking ($self) { return 1; }

sub blocking_layer ($self) { return $self; }

sub in_transaction ($self) { return 0; }

sub transaction_p ( $self, $work, $context = undef, $readonly = 0 ) {
    return $work->($self);
}

sub rows_p ( $self, $name, $values, $context = undef ) {
    return _settled( sub { return $self->rows( $name, $values ); } );
}

sub row_p ( $self, $name, $values, $context = undef ) {
    return _settled( sub { return $self->row( $name, $values ); } );
}

# api.outbox_claim_ready: the due pending and failed rows and the running
# ones whose lease ran out, up to the limit, each then held by the worker.
sub rows ( $self, $name, $values ) {
    croak "the dead-letter probe has no rows of $name"
      if $name ne 'outbox_claim_ready';
    return [] if !$self->outbox;

    my @claimed = $self->outbox->search_rs(
        [
            {
                status          => { -in  => [qw(pending failed)] },
                next_attempt_at => { '<=' => $values->{now} },
            },
            { status => $RUNNING, locked_until => { '<=' => $values->{now} } },
        ],
        { rows => $values->{row_limit} }
    )->all;
    for my $row (@claimed) {
        $row->update(
            {
                locked_at    => $values->{now},
                locked_by    => $values->{worker_id},
                locked_until => $values->{locked_until},
                status       => $RUNNING,
            }
        );
    }

    return [ map { +{ %{ $_->data } } } @claimed ];
}

sub row ( $self, $name, $values ) {
    return $self->_owned_write($values) if $name eq 'outbox_owned_write';
    return $self->_dead_letter( $values->{letter} )
      if $name eq 'outbox_dead_letter';

    croak "the dead-letter probe has no row of $name";
}

# api.outbox_owned_write: lands only on a running row this worker holds.
sub _owned_write ( $self, $values ) {
    my ($row) =
      grep { ( $_->get_column('outbox_id') // q{} ) eq $values->{outbox_id} }
      $self->outbox ? @{ $self->outbox->rows } : ();
    return { landed => 0 }
      if !$row
      || ( $row->get_column('status')    // q{} ) ne $RUNNING
      || ( $row->get_column('locked_by') // q{} ) ne $values->{worker_id};

    $row->update( $values->{changes} );
    return { landed => 1 };
}

# api.outbox_dead_letter: once per source.
sub _dead_letter ( $self, $letter ) {
    croak 'the dead-letter probe keeps no letters' if !$self->letters;
    return { letter => { skipped => 1 } } if $self->letters->find($letter);

    $self->letters->create($letter);
    return { letter => $letter };
}

sub _settled ($answer) {
    my $promise;
    try { $promise = Mojo::Promise->resolve( $answer->() ); }
    catch ($error) { $promise = Mojo::Promise->reject($error); };

    return $promise;
}

1;

__END__

=head1 NAME

GPForum::Service::Operations::DeadLetterCheck::ProbeFunctions - The dead-letter check's outbox functions, answered in memory.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    # Built by GPForum::Service::Operations::DeadLetterCheck for its
    # simulate mode; nothing else uses it.
    my $functions =
      GPForum::Service::Operations::DeadLetterCheck::ProbeFunctions->new(
        outbox  => $probe_outbox,
        letters => $probe_letters,
      );

=head1 DESCRIPTION

The call layer the real L<GPForum::Service::Outbox::Dispatcher> runs on in
the dead-letter check's C<simulate> mode: the three outbox functions it
calls -- C<outbox_claim_ready>, C<outbox_owned_write> and
C<outbox_dead_letter> -- over the probe's in-memory outbox and letters. Its
promises are settled when they are made, so it is its own blocking layer.

=head1 SUBROUTINES/METHODS

=head2 outbox

The L<GPForum::Service::Operations::DeadLetterCheck::ProbeOutbox> claimed
from.

=head2 letters

The L<GPForum::Service::Operations::DeadLetterCheck::ProbeLetters> dead
letters are kept in.

=head2 blocking

True.

=head2 blocking_layer

Itself.

=head2 in_transaction

False: no caller's transaction is open around the probe.

=head2 transaction_p

Runs the work on this layer and answers what it answers.

=head2 rows

C<outbox_claim_ready>: the due C<pending> and C<failed> rows and the
C<running> rows whose C<locked_until> has passed, up to C<row_limit>, each
then marked running and held by C<worker_id>; answered as hashes.

=head2 row

C<outbox_owned_write>: C<< { landed } >>, true when the row is running and
held by C<worker_id>, its changes then applied. C<outbox_dead_letter>: the
letter, or C<< { skipped => 1 } >> when its source already has one.

=head2 rows_p

L</rows> as a settled promise.

=head2 row_p

L</row> as a settled promise.

=head1 DIAGNOSTICS

Croaks on a function it does not answer.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<Mojo::Base>, L<Mojo::Promise>, L<Const::Fast>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

It stands in for PostgreSQL only as far as the dead-letter check needs.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
