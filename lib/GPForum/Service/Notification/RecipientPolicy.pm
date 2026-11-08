# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Notification::RecipientPolicy;

use Mojo::Base 'GPForum::Service::Forum::Readability', -async_await;
use v5.40;

use GPForum::Infrastructure::Id;

our $VERSION = '0.001';

# ADR 0102: a notification about a post or thread reaches only a recipient
# who can read it; else a reply in a private thread, or a mention in a
# members-only category, would notify everyone subscribed or mentioned and
# hand them the thread, the post and the actor. A public source costs one
# query; any other, the recipient's viewer as well.
#
# ADR 0139: a direct message reaches only a member of its conversation.
sub can_notify ( $self, $recipient, $source_type, $source_id, @ ) {
    return $self->_message_participant( $recipient, $source_id )
      if ( $source_type // q{} ) eq 'message';

    return $self->readable_by( $recipient, $source_type, $source_id );
}

# can_notify on the worker's pooled asynchronous connections, or on the
# call layer of the transaction the policy was joined to: a mention reads
# the post its own write has not committed yet.
async sub can_notify_p (
    $self, $recipient, $source_type, $source_id,
    $payload = undef,
    $context = undef
  )
{
    return $self->can_notify( $recipient, $source_type, $source_id )
      if !$self->functions;
    return await $self->_message_participant_p( $recipient, $source_id,
        $context )
      if ( $source_type // q{} ) eq 'message';

    return await $self->readable_by_p( $recipient, $source_type, $source_id,
        $context );
}

# The readers, of those given -- viewers or user ids -- who may be notified
# about the source: for a message, the members of its conversation, one
# lookup each; for a post or thread, Readability's readers_of -- one
# statement for where the source sits, and none for a reader given as a
# viewer. The fan-out screens every recipient this way at once.
sub notifiable_readers ( $self, $source_type, $source_id, @readers ) {
    return
      grep { $self->_message_participant( _user_id_of($_), $source_id ) }
      @readers
      if ( $source_type // q{} ) eq 'message';

    return $self->readers_of( $source_type, $source_id, @readers );
}

sub _user_id_of ($reader) {
    return blessed $reader && $reader->can('user_id')
      ? $reader->user_id
      : $reader;
}

sub _message_participant ( $self, $recipient, $message_id ) {
    return 0 if !_participant_call( $self, $recipient, $message_id );

    my $row = $self->functions->row( 'community_message_participant',
        { message_id => $message_id, user_id => $recipient } );

    return $row && $row->{participant} ? 1 : 0;
}

async sub _message_participant_p ( $self, $recipient, $message_id, $context ) {
    return 0 if !_participant_call( $self, $recipient, $message_id );

    my $row = await $self->functions->row_p( 'community_message_participant',
        { message_id => $message_id, user_id => $recipient }, $context );

    return $row && $row->{participant} ? 1 : 0;
}

sub _participant_call ( $self, $recipient, $message_id ) {
    return
         $self->functions
      && GPForum::Infrastructure::Id->is_uuid_spelling($message_id)
      && GPForum::Infrastructure::Id->is_uuid_spelling($recipient) ? 1 : 0;
}

1;

__END__

=head1 NAME

GPForum::Service::Notification::RecipientPolicy - Who may be notified about a source.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $dispatcher = GPForum::Service::Notification::Dispatcher->new(
        permission_engine =>
          GPForum::Service::Notification::RecipientPolicy->new(
            schema => $schema ),
        ...
    );

=head1 DESCRIPTION

The notification dispatcher's permission hook (ADR 0102): a recipient is
notified about a post or thread only if they can read it, as
L<GPForum::Service::Forum::Readability> judges; about a direct message only
if they are a member of its conversation (ADR 0139).

=head1 SUBROUTINES/METHODS

=head2 can_notify

True when the recipient may be notified about the source.

=head2 can_notify_p

L</can_notify> as a promise; takes the recipient, the source type and id,
the payload and an optional query context. It reads on the worker's pooled
asynchronous connections, or on a transaction's call layer when the policy
was built with that layer as its C<functions>.

=head2 notifiable_readers

Takes a source type, a source id and readers, each a
L<GPForum::Service::Forum::Viewer> or a user id. Returns those who may be
notified about the source: a conversation's members for a message, each
looked up; for a post or thread the readers of
L<GPForum::Service::Forum::Readability/readers_of>, one statement for where
the source sits and none for a reader given as a viewer.

=head1 DIAGNOSTICS

Dies when the database does; the dispatcher then fails the notification.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Service::Forum::Readability>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

None known. Notifications already in an inbox are re-checked when the inbox
is read (the dispatcher's C<readability>).

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
