# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::RecordingRecorder;

use Mojo::Base -base, -signatures;
use v5.40;

our $VERSION = '0.001';

# An EventRecorder that keeps what it was asked to record, for a store's
# unit test to read back: events and audit rows, in order.
has audits => sub { return []; };
has events => sub { return []; };

sub record_event ( $self, %event ) {
    push @{ $self->events }, \%event;
    return \%event;
}

sub record_audit ( $self, %audit ) {
    push @{ $self->audits }, \%audit;
    return \%audit;
}

sub event_recorded ( $self, $key ) {
    return ( grep { $_->{idempotency_key} eq $key } @{ $self->events } )
      ? 1
      : 0;
}

1;

__END__

=head1 NAME

GPForum::Test::RecordingRecorder - An event recorder that remembers.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $recorder = GPForum::Test::RecordingRecorder->new;
    $store->recorder($recorder);
    is( $recorder->events->[0]{event_type}, 'announcement.published' );

=head1 DESCRIPTION

Stands in for L<GPForum::Infrastructure::EventRecorder> in a unit test:
C<record_event> and C<record_audit> keep their arguments in C<events> and
C<audits>; C<event_recorded> answers from the events kept.

=head1 SUBROUTINES/METHODS

=head2 record_event

Keeps the event.

=head2 record_audit

Keeps the audit row.

=head2 event_recorded

True when an event with that idempotency key was kept.

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
