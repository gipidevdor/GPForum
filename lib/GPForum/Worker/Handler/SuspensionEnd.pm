# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Worker::Handler::SuspensionEnd;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -signatures;
use v5.40;

use GPForum::Jobs::EventPayload;

our $VERSION = '0.001';

const my $END_DUE => 'user.suspension_end_due';

__PACKAGE__->requires(qw(store));
has payload => sub { return GPForum::Jobs::EventPayload->new; };

# v5.0.0-2.3.2: a timed suspension ends at its valid_to, not at the next
# revocation. Its end waits in the outbox (migration 1055) and comes here a
# second after valid_to; the suspension store sets the member active again
# when nothing holds them any more.
sub supports ( $self, $event ) {
    return
         ( $event->{event_type} // q{} ) eq $END_DUE
      && defined $self->_user_id($event)
      && defined $self->_suspension_id($event) ? 1 : 0;
}

sub handle ( $self, $event ) {
    my $ended = $self->store->end_suspension( $self->_user_id($event),
        $self->_suspension_id($event) );

    return { action => 'suspension.end', %{$ended} };
}

sub _user_id ( $self, $event ) {
    return $self->payload->value( $event, 'user_id' );
}

sub _suspension_id ( $self, $event ) {
    return $self->payload->value( $event, 'suspension_id' );
}

1;

__END__

=head1 NAME

GPForum::Worker::Handler::SuspensionEnd - End a timed suspension when its time is up.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    GPForum::Worker::Handler::SuspensionEnd->new( store => $suspension_store )
      ->handle($suspension_end_due);

=head1 DESCRIPTION

Takes the C<user.suspension_end_due> message a timed suspension queues in
the outbox, due a second after its C<valid_to>, and hands it to
L<GPForum::Service::Moderation::SuspensionStore/end_suspension>.

=head1 SUBROUTINES/METHODS

=head2 store

The suspension store; required.

=head2 payload

The event payload reader, L<GPForum::Jobs::EventPayload>.

=head2 supports

True for C<user.suspension_end_due> messages that name their member and
their suspension.

=head2 handle

Ends the suspension and returns the store's answer with
C<< action => 'suspension.end' >>.

=head1 DIAGNOSTICS

C<new> throws L<GPForum::X::Argument> when no C<store> is given. C<handle>
lets the store's L<GPForum::X::Unavailable> through when the suspension is
still in force, and dies when the database does; the outbox delivers the
message again either way.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Base>, L<GPForum::Jobs::EventPayload>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

The suspension ends when the outbox delivers its message: within the
dispatcher's poll of the second after C<valid_to> while the worker runs.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
