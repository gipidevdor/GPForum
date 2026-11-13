# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::OutboxFunctions;

use Carp qw(croak);
use Mojo::Base 'GPForum::Test::SettledCalls', -signatures;
use v5.40;

our $VERSION = '0.001';

# The outbox's functions as the dispatcher calls them, through the SQL
# function layer, on rows a test gives: api.outbox_claim_ready answers the
# claimed rows, api.outbox_owned_write lands while the message is still this
# worker's, api.outbox_dead_letter keeps the letter. A transaction that
# fails takes back every call made in it, as PostgreSQL's would.

has claimed_rows => sub { return []; };

# The ids a write still finds this worker's. undef means every one, the
# common case; setting it models a message whose lease ran out and that
# another worker claimed.
has owned_ids => undef;

has calls   => sub { return []; };    # [ name, arguments ], in order
has letters => sub { return []; };    # the dead letters recorded

# The error a dead letter's write fails with, if any.
has letter_error => undef;

# The ids whose first acknowledgement fails, as a worker that crashed after
# the dispatch and before the acknowledgement would leave them.
has crash_ids => sub { return {}; };

has transactions => 0;    # how many transactions were opened

sub transaction_p ( $self, $work, $context = undef, $readonly = 0 ) {
    $self->transactions( $self->transactions + 1 );
    my @kept = ( scalar @{ $self->calls }, scalar @{ $self->letters } );
    my $value;
    try { $value = $work->($self); }
    catch ($error) {
        splice @{ $self->calls },   $kept[0];
        splice @{ $self->letters }, $kept[1];
        croak $error;
    };

    return $value;
}

sub rows ( $self, $name, $arguments ) {
    push @{ $self->calls }, [ $name, $arguments ];
    croak "no rows of $name" if $name ne 'outbox_claim_ready';

    return [ map { +{ %{$_} } } @{ $self->claimed_rows } ];
}

sub row ( $self, $name, $arguments ) {
    if ( ( $arguments->{changes}{status} // q{} ) eq 'done'
        && delete $self->crash_ids->{ $arguments->{outbox_id} // q{} } )
    {
        croak 'crash after dispatch';
    }
    push @{ $self->calls }, [ $name, $arguments ];
    if ( $name eq 'outbox_dead_letter' ) {
        croak $self->letter_error if defined $self->letter_error;
        push @{ $self->letters }, $arguments->{letter};
        return { letter => $arguments->{letter} };
    }
    croak "no row of $name" if $name ne 'outbox_owned_write';

    return { landed => $self->_owned( $arguments->{outbox_id} ) ? 1 : 0 };
}

# The claim's arguments, or undef before it.
sub claim ($self) {
    my ($claim) = grep { $_->[0] eq 'outbox_claim_ready' } @{ $self->calls };

    return $claim ? $claim->[1] : undef;
}

# The writes after the claim, in order, as kind:id: renew for a renewal,
# which writes locked_until alone, otherwise the status written. A write
# made for another worker reads other-kind:id.
sub writes ( $self, $worker ) {
    return [
        map  { _write( $_->[1], $worker ) }
        grep { $_->[0] eq 'outbox_owned_write' } @{ $self->calls }
    ];
}

sub _owned ( $self, $id ) {
    return 1 if !defined $self->owned_ids;

    return scalar grep { $_ eq $id } @{ $self->owned_ids };
}

sub _write ( $arguments, $worker ) {
    my $changes = $arguments->{changes};
    my $kind =
      join( q{ }, sort keys %{$changes} ) eq 'locked_until'
      ? 'renew'
      : $changes->{status} // 'other';

    return ( $arguments->{worker_id} eq $worker ? q{} : 'other-' )
      . "$kind:$arguments->{outbox_id}";
}

1;

__END__

=head1 NAME

GPForum::Test::OutboxFunctions - The outbox's SQL functions, on given rows.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $functions = GPForum::Test::OutboxFunctions->new(
        claimed_rows => [ { outbox_id => 'm1', status => 'running' } ],
        owned_ids    => ['m1'],
    );
    GPForum::Service::Outbox::Dispatcher->new(
        functions => $functions,
        ...
    )->dispatch_pending(1);
    is_deeply( $functions->writes('worker'), [qw(renew:m1 done:m1)] );

=head1 DESCRIPTION

Stands in for L<GPForum::Infrastructure::SqlFunction> where the dispatcher
and its dead-letter recorder use it: C<outbox_claim_ready>,
C<outbox_owned_write> and C<outbox_dead_letter>. The PostgreSQL functions
themselves are tested in F<t/integration/postgres-outbox-lease-race.t> and
F<t/integration/postgres-outbox-reclaim.t>.

=head1 SUBROUTINES/METHODS

=head2 claimed_rows

The rows the claim answers.

=head2 owned_ids

The ids a write still lands on; undef for every one.

=head2 calls

Every call, C<[ name, arguments ]>, in order.

=head2 letters

The dead letters recorded.

=head2 letter_error

The error the dead letter's write croaks with; undef for none.

=head2 crash_ids

A hash of ids whose first acknowledgement croaks C<crash after dispatch>,
written and recorded nowhere.

=head2 transactions

How many transactions L</transaction_p> opened.

=head2 transaction_p

Runs the work on this double; when it dies, takes back the calls and
letters it made and dies again.

=head2 rows

C<outbox_claim_ready>: copies of the claimed rows.

=head2 row

C<outbox_owned_write>: C<< { landed } >>; C<outbox_dead_letter>: the letter.

=head2 claim

The claim's arguments, or undef before it.

=head2 writes

Takes a worker id and returns the writes after the claim as C<kind:id>.

=head1 DIAGNOSTICS

Croaks on a function it does not stand in for.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Test::SettledCalls>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

For tests only.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
