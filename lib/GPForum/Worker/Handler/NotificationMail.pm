# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Worker::Handler::NotificationMail;

use Const::Fast;
use Mojo::Base -base, -signatures;
use v5.40;

use GPForum::Infrastructure::Id;

our $VERSION = '0.001';

const my $EMAIL_REQUESTED => 'notification.email.requested';

has mailer           => undef;    # optional: task is only captured
has preference_store => undef;    # optional: task is only captured
has renderer         => undef;    # optional: task is only captured
has sink             => undef;    # optional: tests capture tasks
has tokens           => undef;    # optional: task is only captured

sub supports ( $, $event ) {
    return ( $event->{event_type} || q{} ) eq $EMAIL_REQUESTED;
}

sub handle ( $self, $event ) {
    my $mail = $event->{domain_payload} || $event->{payload} || {};
    my $task = {
        action            => 'notification.mail',
        event_id          => $event->{event_id},
        notification_type => $mail->{notification_type},
        recipient_user_id => $mail->{recipient_user_id},
    };
    if ( $self->sink ) {
        $self->sink->capture($task);
    }
    if (
           !$self->mailer
        || !$self->preference_store
        || !$self->renderer
        || !$self->tokens
        || !GPForum::Infrastructure::Id->is_uuid_spelling(
            $mail->{recipient_user_id}
        )
      )
    {
        $task->{skipped} = 1;
        return $task;
    }

    # Asked again as it is sent: an unsubscribe, a lost verification or a
    # closed account since the notification was queued stops the mail.
    my $plan =
      $self->preference_store->delivery_plan( $mail->{recipient_user_id},
        $mail->{notification_type} );
    if (   !$plan->{email}
        || !length( $plan->{email_address} // q{} )
        || !length( $plan->{event_type}    // q{} ) )
    {
        $task->{skipped} = 1;
        return $task;
    }

    $task->{delivered} =
      $self->mailer->send_notification_mail( $self->_message( $mail, $plan ) );

    return $task;
}

# The subject and body as the member's locale says them, the link to what
# it is about (the thread, or the inbox), and the footer with the settings
# page and the link that stops this kind of mail.
sub _message ( $self, $mail, $plan ) {
    my $locale   = $plan->{locale} || 'en';
    my $rendered = $self->renderer->render_email(
        $locale,
        {
            notification_type => $mail->{notification_type},
            source_type       => $mail->{source_type},
            source_id         => $mail->{source_id},
            payload           => {
                thread_id => $mail->{thread_id},
                post_id   => $mail->{post_id},
                reason    => $mail->{reason},
            },
        }
    );
    my $base = $self->mailer->public_base_url;
    $base =~ s{ / \z}{}msx;
    my $target = _target($mail);
    my $unsubscribe =
        $base
      . '/unsubscribe/'
      . $self->tokens->issue( $mail->{recipient_user_id}, $plan->{event_type} );
    my $footer = $self->renderer->i18n->translate(
        $locale,
        'notifications.email_footer',
        {
            settings_url    => "$base/settings",
            unsubscribe_url => $unsubscribe,
        }
    );

    return {
        to      => $plan->{email_address},
        subject => $rendered->{subject},
        body    => join( "\n\n",
            $rendered->{text_body},
            $base . $target,
            q{--}, $footer ),
        unsubscribe_url => $unsubscribe,
    };
}

# The page the mail links to: the thread, the conversation of a direct
# message (ADR 0139), or the inbox.
sub _target ($mail) {
    return "/t/$mail->{thread_id}"
      if GPForum::Infrastructure::Id->is_uuid_spelling( $mail->{thread_id} );
    return "/messages/$mail->{conversation_id}"
      if GPForum::Infrastructure::Id->is_uuid_spelling(
        $mail->{conversation_id} );

    return '/notifications';
}

1;

__END__

=head1 NAME

GPForum::Worker::Handler::NotificationMail - Sends the notifications a member takes by email.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $handler = GPForum::Worker::Handler::NotificationMail->new(
        mailer           => $mailer,
        preference_store => $preferences,
        renderer         => $renderer,
        tokens           => $unsubscribe_tokens,
    );
    $handler->handle($event);

=head1 DESCRIPTION

ADR 0078. The dispatcher queues C<notification.email.requested> for a
notification whose type the member takes by email. This handler asks the
member's preferences again, through
L<GPForum::Service::Notification::PreferenceStore/delivery_plan>, and sends
the mail only while they still say email: the address and locale are read
then, never carried in the event. The mail is plain text in the member's
language: the notification's subject and body as
L<GPForum::Service::Notification::Renderer/render_email> says them, a link
to the thread (or the conversation of a direct message, or the inbox), and a footer naming the settings page and the
signed link that turns this kind of email off, which is also the mail's
RFC 8058 C<List-Unsubscribe> header. No post text goes into it.

The handler runs under the outbox's idempotent job runner
(C<worker.notification_mail>), so a retried event sends once.

=head1 SUBROUTINES/METHODS

=head2 supports

True for C<notification.email.requested>.

=head2 handle

Sends the mail and returns the task: C<action>, C<event_id>,
C<notification_type>, C<recipient_user_id>, and C<delivered> or
C<skipped>.

=head1 DIAGNOSTICS

A transport failure propagates, and the outbox retries the event.

=head1 CONFIGURATION AND ENVIRONMENT

The mailer's C<public_base_url> is the links' origin.

=head1 DEPENDENCIES

L<GPForum::Infrastructure::Id>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Each notification is its own mail; the daily or weekly digest is
L<GPForum::Worker::Handler::NotificationDigest>'s.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause
license.

=cut
