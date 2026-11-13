# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::RecorderFunctions;

use Carp qw(croak);
use JSON::MaybeXS;
use List::Util qw(any);
use Mojo::Base 'GPForum::Test::SettledCalls', -signatures;
use v5.40;

use GPForum::Infrastructure::AuditRecord;
use GPForum::Infrastructure::OutboxMessageBuilder;

our $VERSION = '0.001';

my $JSON = JSON::MaybeXS->new( canonical => 1, utf8 => 1 );

# EventRecorder's functions over rows kept in memory, each written as the
# function writes it: api.ops_record_event keeps an event once under its id
# and gives it one outbox row, keyed by the event; api.ops_record_audit
# links the record to the tip of its target's chain (ADR 0156) and draws a
# new id for a caller's id already stored; api.ops_event_recorded reads
# the events back. What each call was sent is kept in calls. A failure,
# when given, is raised by every call, as a database gone away raises it.
has audits  => sub { return []; };
has calls   => sub { return []; };
has events  => sub { return []; };
has failure => undef;
has outbox  => sub { return []; };
has records => sub { return GPForum::Infrastructure::AuditRecord->new; };
has minted  => 0;

sub rows ( $self, $name, $values ) {
    push @{ $self->calls }, [ $name, _copy($values) ];
    croak $self->failure if defined $self->failure;

    return [ { event => $self->_record_event($values) } ]
      if $name eq 'ops_record_event';
    return [ { audit => $self->_record_audit($values) } ]
      if $name eq 'ops_record_audit';
    if ( $name eq 'ops_event_recorded' ) {
        my $key = $values->{key} // q{};
        my $recorded =
          any { ( $_->{idempotency_key} // q{} ) eq $key } @{ $self->events };
        return [ { recorded => $recorded ? 1 : 0 } ];
    }

    die "$name is not answered here\n";
}

sub row ( $self, $name, $values ) {
    return $self->rows( $name, $values )->[0];
}

# The calls made to one function, each with what it was sent.
sub sent ( $self, $name ) {
    return [ map { $_->[1] } grep { $_->[0] eq $name } @{ $self->calls } ];
}

# The audit rows of one chain, by position.
sub chain ( $self, $key ) {
    return [
        sort { $a->{chain_position} <=> $b->{chain_position} }
        grep { $_->{chain_key} eq $key } @{ $self->audits }
    ];
}

# An event already kept under its id is not written again: it comes back
# skipped, and gets its outbox row if it has none.
sub _record_event ( $self, $values ) {
    my $event = _copy( $values->{event} );
    my ($stored) =
      grep { $_->{event_id} eq $event->{event_id} } @{ $self->events };
    if ($stored) {
        $event = { %{ _copy($stored) }, skipped => 1 };
    }
    else {
        push @{ $self->events }, _copy($event);
    }
    $self->_ensure_outbox( $event, $values );

    return $event;
}

sub _ensure_outbox ( $self, $event, $values ) {
    my $key =
      GPForum::Infrastructure::OutboxMessageBuilder::idempotency_key_for(
        $event);
    return if any { $_->{idempotency_key} eq $key } @{ $self->outbox };

    my %stored = %{$event};
    delete $stored{skipped};
    my $row =
      GPForum::Infrastructure::OutboxMessageBuilder->new( id_service => $self )
      ->for_event( \%stored, $values->{outbox_extras} );
    $row->{outbox_id} = $values->{outbox_id} // $row->{outbox_id};
    push @{ $self->outbox }, _copy($row);

    return;
}

sub _record_audit ( $self, $values ) {
    my $audit = _copy( $values->{audit} );
    if ( $values->{explicit}
        && any { $_->{audit_id} eq $audit->{audit_id} } @{ $self->audits } )
    {
        $audit->{audit_id} = $self->uuid;
    }
    my $key =
      $self->records->chain_key( @{$audit}{qw(target_type target_id)} );
    my $tip     = $self->chain($key)->[-1];
    my $chained = $self->records->build(
        { %{$audit}, previous_hash => undef },
        $tip ? $tip->{record_hash} : undef
    );
    $chained->{chain_key}      = $key;
    $chained->{chain_position} = $tip ? $tip->{chain_position} + 1 : 1;
    push @{ $self->audits }, _copy($chained);

    return $chained;
}

# The ids the functions draw for themselves: an outbox id or an audit id
# taken.
sub uuid ($self) {
    $self->minted( $self->minted + 1 );

    return 'minted-' . $self->minted;
}

sub _copy ($document) {
    return $JSON->decode( $JSON->encode($document) );
}

1;

__END__

=head1 NAME

GPForum::Test::RecorderFunctions - EventRecorder's functions over rows kept in memory.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $log      = GPForum::Test::RecorderFunctions->new;
    my $recorder = GPForum::Infrastructure::EventRecorder->new(
        functions => $log,
        schema    => GPForum::Test::Schema->new,
    );
    $recorder->record_audit(%audit);
    is( scalar @{ $log->audits }, 1 );

=head1 DESCRIPTION

Stands in for L<GPForum::Infrastructure::SqlFunction> where a unit test runs
the real L<GPForum::Infrastructure::EventRecorder>: C<api.ops_record_event>,
C<api.ops_record_audit> and C<api.ops_event_recorded>, over rows in memory. Its promises are
settled (L<GPForum::Test::SettledCalls>). The real functions, their locks
and their conflicts are the integration tier's
(C<t/integration/postgres-partition-conflicts.t>,
C<t/integration/postgres-audit-chain.t>,
C<t/integration/postgres-event-recorder.t>).

=head1 SUBROUTINES/METHODS

=head2 audits

The audit rows kept, in the order written, with C<chain_key> and
C<chain_position>.

=head2 calls

Each call made, as C<[ $name, $values ]>.

=head2 chain

Takes a chain key. The audit rows of that chain, by position.

=head2 events

The events kept, in the order written.

=head2 failure

When set, every call dies with it.

=head2 minted

How many ids the double has drawn itself.

=head2 outbox

The outbox rows kept, one per event.

=head2 records

The L<GPForum::Infrastructure::AuditRecord> the chain is hashed with.

=head2 row

The first of L</rows>.

=head2 rows

The function's rows; dies for a function it does not answer.

=head2 sent

Takes a function's name. What each call to it was sent, in order.

=head2 uuid

An id the double draws: C<minted-1>, C<minted-2>, ...

=head1 DIAGNOSTICS

Dies with L</failure> when it is set, and for a function it does not answer.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Test::SettledCalls>, L<GPForum::Infrastructure::AuditRecord>,
L<GPForum::Infrastructure::OutboxMessageBuilder>, L<JSON::MaybeXS>.

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
