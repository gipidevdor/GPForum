# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Worker::Handler::NotificationDigest;

use Carp qw(croak);
use Const::Fast;
use Mojo::Base -base, -signatures;
use v5.40;

use GPForum::Infrastructure::Id;
use GPForum::Service::Notification::DigestMessage;

our $VERSION = '0.001';

const my $DIGEST_REQUESTED => 'notification.digest.requested';

has mailer           => undef;    # optional: task is only captured
has preference_store => undef;    # optional: task is only captured
has renderer         => undef;    # optional: task is only captured
has sink             => undef;    # optional: tests capture tasks
has tokens           => undef;    # optional: task is only captured

sub supports ( $, $event ) {
    return ( $event->{event_type} || q{} ) eq $DIGEST_REQUESTED;
}

sub handle ( $self, $event ) {
    my $digest = $event->{domain_payload} || $event->{payload} || {};
    my $task   = {
        action            => 'notification.digest',
        event_id          => $event->{event_id},
        frequency         => $digest->{frequency},
        recipient_user_id => $digest->{recipient_user_id},
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
            $digest->{recipient_user_id}
        )
      )
    {
        $task->{skipped} = 1;
        return $task;
    }

    # Asked again as it is sent: a digest switched off, an unsubscribe, a
    # lost verification or a closed account since it was queued stops it.
    my $plan =
      $self->preference_store->digest_plan( $digest->{recipient_user_id} );
    if ( !$plan->{digest} || !length( $plan->{email_address} // q{} ) ) {
        $task->{skipped} = 1;
        return $task;
    }

    # At most once (ADR 0078, 2026-10-17): the record is claimed before the
    # transport takes the mail, so a delivery of the event after the mail
    # went out -- the job not marked done -- sends nothing; a transport
    # that refuses it gives the claim back for the retry.
    my $digest_key = {
        user_id      => $digest->{recipient_user_id},
        frequency    => $digest->{frequency},
        period_start => $digest->{period_start},
        event_id     => $event->{event_id},
    };
    my $claim = $self->preference_store->claim_digest_send($digest_key);
    if ( ( $claim->{status} // q{} ) ne 'claimed' ) {
        $task->{skipped} = 1;
        $task->{reason}  = $claim->{status} // 'missing';
        return $task;
    }
    try {
        $task->{delivered} = $self->_send( $digest, $plan, $event->{event_id} );
    }
    catch ($error) {
        $self->preference_store->release_digest_send($digest_key);
        croak $error;
    };

    return $task;
}

sub _send ( $self, $digest, $plan, $event_id ) {
    my $base = $self->mailer->public_base_url;
    my $unsubscribe =
        ( $base =~ s{ / \z}{}msxr )
      . '/unsubscribe/'
      . $self->tokens->issue( $digest->{recipient_user_id}, 'digest' );
    my $message = GPForum::Service::Notification::DigestMessage->new(
        i18n => $self->renderer->i18n )->compose(
        {
            locale          => $plan->{locale} || 'en',
            frequency       => $digest->{frequency},
            items           => $digest->{items},
            thread_total    => $digest->{thread_total},
            base_url        => $base,
            unsubscribe_url => $unsubscribe,
        }
        );

    return $self->mailer->send_digest_mail(
        {
            to              => $plan->{email_address},
            subject         => $message->{subject},
            text            => $message->{text},
            html            => $message->{html},
            unsubscribe_url => $unsubscribe,
            message_key     => $event_id,
        }
    );
}

1;

__END__

=head1 NAME

GPForum::Worker::Handler::NotificationDigest - Sends the daily or weekly email digest.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $handler = GPForum::Worker::Handler::NotificationDigest->new(
        mailer           => $mailer,
        preference_store => $preferences,
        renderer         => $renderer,
        tokens           => $unsubscribe_tokens,
    );
    $handler->handle($event);

=head1 DESCRIPTION

ADR 0078. The scheduled job (L<GPForum::Service::Notification::DigestQueue>)
queues C<notification.digest.requested> with the threads a member's digest
names. This handler asks the member's preferences again, through
L<GPForum::Service::Notification::PreferenceStore/digest_plan>, and sends
only while the digest is still on: the address and locale are read then,
never carried in the event. The mail, in the member's language, has a
plain-text and an HTML part (L<GPForum::Service::Notification::DigestMessage>)
and the signed link that stops the digest, which is also its RFC 8058
C<List-Unsubscribe> header.

The handler runs under the outbox's idempotent job runner
(C<worker.notification_digest>), and sends at most once: it claims the
digest's record (L<GPForum::Service::Notification::PreferenceStore/claim_digest_send>)
before the transport takes the mail, so an event delivered again after
the mail went out -- the job not yet marked done -- sends nothing, and a
transport that refuses the mail gives the claim back for the retry. The
mail's C<Message-ID> is named by the event, the same each time.

=head1 SUBROUTINES/METHODS

=head2 supports

True for C<notification.digest.requested>.

=head2 handle

Sends the digest and returns the task: C<action>, C<event_id>,
C<frequency>, C<recipient_user_id>, and C<delivered> or C<skipped> (with
C<reason> C<sent> or C<missing> when the claim was refused).

=head1 DIAGNOSTICS

A transport failure gives the claim back and propagates, and the outbox
retries the event. A worker that dies between the claim and the
transport loses that digest: it is never sent twice.

=head1 CONFIGURATION AND ENVIRONMENT

The mailer's C<public_base_url> is the links' origin.

=head1 DEPENDENCIES

L<Carp>, L<GPForum::Infrastructure::Id> and
L<GPForum::Service::Notification::DigestMessage>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

The digest names the threads as they were titled when it was queued.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause
license.

=cut
