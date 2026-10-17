# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Worker::Handler::NotificationDispatch;

use Const::Fast;
use Mojo::Base -base, -signatures;
use v5.40;

use GPForum::X::Unavailable;

our $VERSION = '0.001';

const my $POST_CREATED   => 'post.created';
const my $MESSAGE_SENT   => 'direct_message.sent';
const my $DIRECT_MESSAGE => 'direct_message';

has sink       => undef;    # optional: tests capture tasks
has dispatcher => undef;    # optional: task is only captured

sub supports ( $self, $event ) {
    my $type = $event->{event_type} // q{};

    return $type eq $POST_CREATED || $type eq $MESSAGE_SENT;
}

sub handle ( $self, $event ) {
    return $self->_handle_message($event)
      if ( $event->{event_type} // q{} ) eq $MESSAGE_SENT;

    my $task = {
        action    => 'notification.dispatch',
        thread_id => _event_value( $event, 'thread_id' ),
        post_id   => $event->{aggregate_id},
        event_id  => $event->{event_id},
    };

    if ( $self->sink ) {
        $self->sink->capture($task);
    }

    if ( $self->dispatcher && defined $task->{thread_id} ) {
        $task->{fanout} = $self->_dispatch_notifications( $event, $task );
        _fail_on_dropped_recipients( $task->{fanout} );
    }

    return $task;
}

# The dispatcher keeps going past a recipient it could not notify and reports
# them as failed. Returning normally marked the event done and dropped them
# for good: nothing retried, dead-lettered or logged them. Failing hands the
# event back to the outbox, whose retry is safe -- recipients already served
# come back as duplicates, by the inbox's primary key. The failure is
# X::Unavailable: a recipient the inbox did not take, which a retry can mend.
sub _fail_on_dropped_recipients ($fanout) {
    my $failed = ref $fanout eq 'HASH' ? $fanout->{failed} || [] : [];
    return if !@{$failed};

    my $message = sprintf
      'notification fanout failed for %d recipient%s; retrying',
      scalar @{$failed}, @{$failed} == 1 ? q{} : 's';
    GPForum::X::Unavailable->throw( message => $message );
}

sub _dispatch_notifications ( $self, $event, $task ) {
    return $self->dispatcher->fanout_to_subscribers(
        {
            target_type                => 'thread',
            target_id                  => $task->{thread_id},
            source_type                => 'post',
            source_id                  => $task->{post_id},
            notification_type          => 'reply',
            excluded_recipient_user_id => $event->{actor_id},
            idempotency_key            =>
              join( q{:}, 'notification.reply', $event->{event_id} ),
            payload => {
                thread_id => $task->{thread_id},
                post_id   => $task->{post_id},
                event_id  => $event->{event_id},
                actor_id  => $event->{actor_id},
            },
        }
    );
}

# ADR 0139: the recipient of a direct message is notified of the first
# message of an unread run, as their preferences for the kind message say;
# the next ones wait in the same conversation. The event names ids only,
# and so does the notification. A delivery that failed hands the event back
# to the outbox, whose retry is safe by the notification's idempotency key.
sub _handle_message ( $self, $event ) {
    my $task = {
        action            => 'notification.direct_message',
        conversation_id   => _event_value( $event, 'conversation_id' ),
        message_id        => _event_value( $event, 'message_id' ),
        recipient_user_id => _event_value( $event, 'recipient_user_id' ),
        event_id          => $event->{event_id},
    };
    if ( $self->sink ) {
        $self->sink->capture($task);
    }
    return $task
      if !$self->dispatcher
      || !_event_value( $event, 'first_unread' )
      || !defined $task->{recipient_user_id}
      || !defined $task->{message_id};

    my $delivered = $self->dispatcher->create_notification(
        {
            idempotency_key =>
              join( q{:}, 'notification.direct_message', $event->{event_id} ),
            notification_type => $DIRECT_MESSAGE,
            recipient_user_id => $task->{recipient_user_id},
            source_type       => 'message',
            source_id         => $task->{message_id},
            payload           => {
                conversation_id => $task->{conversation_id},
                message_id      => $task->{message_id},
                event_id        => $event->{event_id},
                actor_id        => $event->{actor_id},
            },
        }
    );
    $task->{delivery} = $delivered;
    if ( ref $delivered eq 'HASH'
        && ( $delivered->{status} // q{} ) eq 'failed' )
    {
        GPForum::X::Unavailable->throw(
            message => 'direct message notification failed; retrying' );
    }

    return $task;
}

sub _event_value ( $event, $name ) {
    return $event->{$name} if defined $event->{$name};

    my $payload = $event->{domain_payload} || {};

    return $payload->{$name};
}

1;
