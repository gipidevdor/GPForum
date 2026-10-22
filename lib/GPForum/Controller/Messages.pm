# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Controller::Messages;

use Const::Fast;
use Mojo::Base 'GPForum::Controller::Forum::Base', -signatures;
use v5.40;

use GPForum::ViewModel::Community::Messages;

our $VERSION = '0.001';

const my $HTTP_OK          => 200;
const my $HTTP_CREATED     => 201;
const my $HTTP_BAD_REQUEST => 400;
const my $HTTP_FORBIDDEN   => 403;
const my $HTTP_NOT_FOUND   => 404;
const my $HTTP_CONFLICT    => 409;
const my $HTTP_GONE        => 410;
const my $HTTP_TOO_MANY    => 429;
const my $HTTP_UNAVAILABLE => 503;
const my $SEND             => 'message.send';
const my $REPORT           => 'report.create';
const my $NO_STORE         => 'private, no-store';

# ADR 0139: what each refusal of a send answers, and the words the form
# shows with it.
const my %REFUSAL => (
    blocked   => [ $HTTP_FORBIDDEN,   'messages.refused_blocked' ],
    conflict  => [ $HTTP_CONFLICT,    'messages.refused_conflict' ],
    failed    => [ $HTTP_UNAVAILABLE, 'messages.refused_failed' ],
    forbidden => [ $HTTP_FORBIDDEN,   'messages.refused_forbidden' ],
    gone      => [ $HTTP_GONE,        'messages.refused_gone' ],
    invalid   => [ $HTTP_BAD_REQUEST, 'messages.refused_invalid' ],
    limit     => [ $HTTP_TOO_MANY,    'messages.refused_limit' ],
    not_found => [ $HTTP_NOT_FOUND,   'messages.refused_not_found' ],
    self      => [ $HTTP_BAD_REQUEST, 'messages.refused_self' ],
);
const my %AUTOMOD_ERROR => (
    link_limit   => 'messages.refused_links',
    watched_word => 'messages.refused_watched_word',
);

# The member's conversations.
sub inbox ($self) {
    my $user_id = $self->_reader or return;
    my $page =
      $self->gp_message_store->inbox( $user_id, $self->param('after') );

    return $self->_render( $HTTP_OK, 'messages/inbox',
        $self->_view->inbox_page( page => $page, user_id => $user_id ),
    );
}

# The form that writes to a member, or the conversation the two hold.
sub compose ($self) {
    my $user_id = $self->_reader or return;
    my $recipient =
      $self->gp_message_store->recipient( $user_id, $self->param('username') );
    return $self->_not_found('member not found')
      if !$recipient || $recipient->{other_user_id} eq $user_id;
    return $self->redirect_to( 'message_conversation',
        conversation_id => $recipient->{conversation_id} )
      if $recipient->{conversation_id};

    return $self->_compose( $HTTP_OK, $recipient );
}

# The first message to a member, from the compose form.
sub start ($self) {
    my $user_id = $self->write_user_id($SEND) or return;
    my $result  = $self->gp_message_store->start(
        {
            sender_user_id => $user_id,
            username       => $self->param('username'),
            body           => $self->param('body'),
            command_id     => $self->param('command_id'),
            viewer         => $self->gp_forum_viewer,
        }
    );
    return $self->_sent($result) if $result->{ok};

    my $recipient =
      $self->gp_message_store->recipient( $user_id, $self->param('username') );
    return $self->_refused(
        $result,
        sub ( $status, $error ) {
            return $self->_compose( $status, $recipient, $error );
        }
    ) if $recipient && !$self->_wants_json;

    return $self->_refused($result);
}

# A conversation, its newest messages and the form that answers. Reading
# it marks it read.
sub conversation ($self) {
    my $user_id = $self->_reader or return;
    my $head =
      $self->gp_message_store->conversation( $self->param('conversation_id'),
        $user_id );
    return $self->_not_found('conversation not found') if !$head;

    if ( ( $head->{unread_count} // 0 ) > 0 && !$self->param('before') ) {
        $self->gp_message_store->mark_read( $head->{conversation_id},
            $user_id );
    }

    return $self->_conversation( $HTTP_OK, $head, $user_id );
}

# An answer in the conversation.
sub reply ($self) {
    my $user_id = $self->write_user_id($SEND) or return;
    my $result  = $self->gp_message_store->reply(
        {
            sender_user_id  => $user_id,
            conversation_id => $self->param('conversation_id'),
            body            => $self->param('body'),
            command_id      => $self->param('command_id'),
            viewer          => $self->gp_forum_viewer,
        }
    );
    return $self->_sent($result) if $result->{ok};

    my $head =
      $self->gp_message_store->conversation( $self->param('conversation_id'),
        $user_id );
    return $self->_refused(
        $result,
        sub ( $status, $error ) {
            return $self->_conversation( $status, $head, $user_id, $error );
        }
    ) if $head && !$self->_wants_json;

    return $self->_refused($result);
}

# A member reports another member's message in a conversation of theirs
# to the staff queue, as a post is reported.
sub report ($self) {
    my $user_id = $self->write_user_id($REPORT) or return;
    my $message =
      $self->gp_message_store->reportable( $self->param('message_id'),
        $user_id );
    return $self->_not_found('message not found')
      if !$message
      || $message->{conversation_id} ne $self->param('conversation_id');

    my $result = $self->create_report(
        {
            reporter_user_id => $user_id,
            target_type      => 'message',
            target_id        => $message->{message_id},
        }
    );
    return $self->_report_error_response($result) if !$result->{ok};
    return $self->_report_json_response($result)  if $self->_wants_json;

    my $url = $self->url_for( 'message_conversation',
        conversation_id => $message->{conversation_id} );

    return $self->_html_success( $self->forum_access->reported_status, $url );
}

# The member reading, or undef once the request is answered.
sub _reader ($self) {
    my $user_id = $self->_current_user_id;
    $self->res->headers->cache_control($NO_STORE);
    if ( !$user_id ) {
        $self->_unauthorized;
        return undef;
    }

    return $user_id;
}

sub _sent ( $self, $result ) {
    $self->res->headers->cache_control($NO_STORE);
    my $replayed = $result->{status} eq 'replayed';
    return $self->render(
        json => {
            ok              => 1,
            status          => $replayed ? 'replayed' : 'sent',
            conversation_id => $result->{conversation_id},
            message_id      => $result->{message_id},
        },
        status => $replayed ? $HTTP_OK : $HTTP_CREATED,
    ) if $self->_wants_json;

    $self->set_success_flash('messages.sent');
    my $url = $self->url_for( 'message_conversation',
        conversation_id => $result->{conversation_id} );
    $url->fragment( 'message-' . $result->{message_id} );

    return $self->redirect_to($url);
}

# A refused send: JSON names the status; a page shows the form again with
# what was written and why it was not sent, when $page can render it.
sub _refused ( $self, $result, $page = undef ) {
    my $status = $result->{status} // 'failed';
    my ( $code, $key ) = @{ $REFUSAL{$status} // $REFUSAL{failed} };
    if ( $status eq 'invalid' && $result->{automod} ) {
        $key = $AUTOMOD_ERROR{ $result->{automod}{reason} // q{} } // $key;
    }
    elsif ( $status eq 'invalid' && ( $result->{field} // q{} ) eq 'body' ) {
        $key = 'messages.refused_body';
    }
    $self->res->headers->cache_control($NO_STORE);

    return $self->render(
        json => {
            ok     => 0,
            status => $status,
            ( $result->{field} ? ( field => $result->{field} ) : () ),
            (
                $result->{automod}
                ? ( automod => $result->{automod}{reason} )
                : ()
            ),
        },
        status => $code,
    ) if $self->_wants_json || !$page;

    return $page->(
        $code,
        $self->t(
            $key,
            {
                limit   => $self->gp_message_store->maximum_body,
                phrases => join q{, },
                @{ ( $result->{automod} // {} )->{phrases} // [] },
            }
        )
    );
}

sub _compose ( $self, $status, $recipient, $error = undef ) {
    return $self->_render(
        $status,
        'messages/compose',
        $self->_view->compose_page(
            recipient    => $recipient,
            command_id   => $self->_new_command_id,
            draft        => $error ? $self->param('body') : undef,
            error        => $error,
            maximum_body => $self->gp_message_store->maximum_body,
        )
    );
}

sub _conversation ( $self, $status, $head, $user_id, $error = undef ) {
    my $page = $self->gp_message_store->messages( $head->{conversation_id},
        $user_id, $self->param('before') );

    return $self->_render(
        $status,
        'messages/conversation',
        $self->_view->conversation_page(
            conversation     => $head,
            page             => $page,
            user_id          => $user_id,
            command_ids      => sub { return $self->_new_command_id; },
            reply_command_id => $self->_new_command_id,
            draft            => $error ? $self->param('body') : undef,
            error            => $error,
            maximum_body     => $self->gp_message_store->maximum_body,
        )
    );
}

sub _render ( $self, $status, $template, $payload ) {
    $self->res->headers->cache_control($NO_STORE);

    return $self->render_payload(
        {
            controller => $self,
            payload    => $payload,
            status     => $status,
            template   => $template,
        }
    );
}

sub _view ($self) {
    return GPForum::ViewModel::Community::Messages->new;
}

1;

__END__

=head1 NAME

GPForum::Controller::Messages - Direct messages: the inbox, a conversation, sending and reporting.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    $routes->get('/messages')->to('Messages#inbox');
    $routes->post('/messages/:conversation_id')->to('Messages#reply');

=head1 DESCRIPTION

ADR 0139. A signed-in member reads their conversations and writes to
another member from that member's profile. Every page is the member's own
and is never cached (C<private, no-store>); a conversation is found only
by its members, anyone else is answered 404. A send checks the CSRF token,
the member, the C<message.send> write rate limit and that the member is
not suspended (C<Forum::Base::write_user_id>); the store screens it and the
function refuses a block either way and a new conversation beyond the day's
bound. A refused send shows the form again with what was written and why;
JSON answers name the status. A report goes to the staff queue through the
community workflow, as a post's does.

=head1 SUBROUTINES/METHODS

=head2 inbox

C<GET /messages>: the member's conversations, the one moved last first.

=head2 compose

C<GET /messages/new/:username>: the form that writes to the member, or a
redirect to the conversation the two already hold.

=head2 start

C<POST /messages/new/:username>: the first message.

=head2 conversation

C<GET /messages/:conversation_id>: the newest messages (older ones with
C<before>), marking the conversation read.

=head2 reply

C<POST /messages/:conversation_id>: an answer.

=head2 report

C<POST /messages/:conversation_id/:message_id/report>: reports the other
member's message to the staff.

=head1 DIAGNOSTICS

401 or the sign-in redirect without a member, 403 for a bad CSRF token, a
suspended sender or a block, 404 for a conversation or member that is not
there for the reader, 410 when the other member's account was erased, 429
over the rate limit or the day's bound on new conversations.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Service::Community::MessageStore>, through the
C<gp_message_store> helper.

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
