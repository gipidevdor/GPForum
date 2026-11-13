# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Notification::RecipientPolicy;

use Mojo::Base 'GPForum::Service::Forum::Readability', -async_await;
use v5.40;

use GPForum::Infrastructure::Id;
use GPForum::Infrastructure::SqlFunction;

our $VERSION = '0.001';

# Each read is written once, as its promise method (ADR 0177); the viewer
# resolver it awaits (Readability's part) blocks with it.
GPForum::Infrastructure::SqlFunction->blocking_twins(
    qw(can_notify notifiable_readers_list));

# ADR 0102: a notification about a post or thread reaches only a recipient
# who can read it; else a reply in a private thread, or a mention in a
# members-only category, would notify everyone subscribed or mentioned and
# hand them the thread, the post and the actor. A public source costs one
# query; any other, the recipient's viewer as well. Read on the policy's
# call layer: a transaction's, when it was joined to one, so a mention
# reads the post its own write has not committed yet.
#
# ADR 0139: a direct message reaches only a member of its conversation.
async sub can_notify_p (
    $self, $recipient, $source_type, $source_id,
    $payload = undef,
    $context = undef
  )
{
    return await $self->_message_participant_p( $recipient, $source_id,
        $context )
      if ( $source_type // q{} ) eq 'message';

    return await $self->readable_by_p( $recipient, $source_type, $source_id,
        $context );
}

# The readers, of those given -- viewers or user ids -- who may be notified
# about the source: for a message, the members of its conversation, one
# lookup each; for a post or thread, Readability's readers_list -- one
# statement for where the source sits, and none for a reader given as a
# viewer. The fan-out screens every recipient this way at once.
async sub notifiable_readers_list_p ( $self, $source_type, $source_id,
    @readers )
{
    return await $self->readers_list_p( $source_type, $source_id, @readers )
      if ( $source_type // q{} ) ne 'message';

    my @notifiable;
    for my $reader (@readers) {
        if (
            await $self->_message_participant_p( _user_id_of($reader),
                $source_id ) )
        {
            push @notifiable, $reader;
        }
    }
    return \@notifiable;
}

# The same readers as a list.
sub notifiable_readers ( $self, @arguments ) {
    return @{ $self->notifiable_readers_list(@arguments) };
}

sub _user_id_of ($reader) {
    return blessed $reader && $reader->can('user_id')
      ? $reader->user_id
      : $reader;
}

async sub _message_participant_p ( $self, $recipient, $message_id,
    $context = undef )
{
    return 0
      if !GPForum::Infrastructure::Id->is_uuid_spelling($message_id)
      || !GPForum::Infrastructure::Id->is_uuid_spelling($recipient);

    my $row = await $self->_functions->row_p( 'community_message_participant',
        { message_id => $message_id, user_id => $recipient }, $context );

    return $row && $row->{participant} ? 1 : 0;
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

=head2 can_notify_p

True when the recipient may be notified about the source; takes the
recipient, the source type and id, the payload and an optional query
context. It reads on the policy's call layer, a transaction's when the
policy was built with that layer as its C<functions>.

=head2 notifiable_readers_list_p

Takes a source type, a source id and readers, each a
L<GPForum::Service::Forum::Viewer> or a user id. Answers those who may be
notified about the source: a conversation's members for a message, each
looked up; for a post or thread the readers of
L<GPForum::Service::Forum::Readability/readers_list_p>, one statement for
where the source sits and none for a reader given as a viewer.

=head2 notifiable_readers

The readers C<notifiable_readers_list> answers, as a list.

=head2 can_notify, notifiable_readers_list

The blocking twins: each is its C<_p> method run on the blocking call layer
(ADR 0177), the viewer resolver with it, answering the value instead of a
promise.

=head1 DIAGNOSTICS

Dies when the database does; the dispatcher then fails the notification.
Without the PostgreSQL function layer a read raises
L<GPForum::X::Unavailable>.

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
