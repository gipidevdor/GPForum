# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::RecordingRecorder;

use Mojo::Base -base, -signatures;
use v5.40;

our $VERSION = '0.001';

# An EventRecorder that keeps what it was asked to prepare, for a store's
# unit test to read back: events and audit rows, in order. A store sends
# them to api.ops_record_event and api.ops_record_audit on its own call
# layer; the calls answered here are what it sends.
has audits => sub { return []; };
has events => sub { return []; };

sub event_call ( $self, %event ) {
    push @{ $self->events }, \%event;
    return {
        event         => {%event},
        explicit      => 0,
        outbox_extras => undef,
        outbox_id     => undef,
    };
}

sub audit_call ( $self, %audit ) {
    push @{ $self->audits }, \%audit;
    return { audit => {%audit}, explicit => 0 };
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
C<event_call> and C<audit_call> keep their arguments in C<events> and
C<audits>, and answer the call a store sends to C<api.ops_record_event> and
C<api.ops_record_audit>.

=head1 SUBROUTINES/METHODS

=head2 event_call

Keeps the event and answers the call that records it.

=head2 audit_call

Keeps the audit row and answers the call that records it.

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

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
