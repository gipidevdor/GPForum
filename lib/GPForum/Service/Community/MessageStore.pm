# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Community::MessageStore;

use Const::Fast;
use MIME::Base64 qw(encode_base64url);
use Mojo::Base 'GPForum::Base', -signatures;
use v5.40;

use GPForum::Infrastructure::EventRecorder;
use GPForum::Infrastructure::Id;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Service::Clock;
use GPForum::Service::Forum::PageWindow;
use GPForum::X::Unavailable;

our $VERSION = '0.001';

# ADR 0139: a message is 1 to 5000 characters of plain text; a member below
# trust level 1 starts at most 3 conversations in a day, any other 20.
const my $MAXIMUM_BODY           => 5_000;
const my $DAILY_LIMIT            => 20;
const my $NEW_MEMBER_DAILY_LIMIT => 3;
const my $NEW_MEMBER_TRUST_BELOW => 1;
const my $MAXIMUM_USERNAME       => 200;
const my $INBOX_PAGE             => 25;
const my $CONVERSATION_PAGE      => 30;
const my $SEND                   => 'message.send';
const my $REPORT_READ            => 'direct_message.report_read';

# What a send answers besides ok: the refusals of the functions and the
# store's own.
const my %SENT => ( ok => 1, replayed => 1 );

has clock       => sub { return GPForum::Service::Clock->new; };
has id_service  => sub { return GPForum::Infrastructure::Id->new; };
has page_window => sub { return GPForum::Service::Forum::PageWindow->new; };
has recorder    => sub ($self) {
    return GPForum::Infrastructure::EventRecorder->new(
        id_service => $self->id_service,
        schema     => $self->schema,
    );
};
__PACKAGE__->requires(qw(schema));

# ADR 0133: the watched words and the link rule, as a reply is screened
# (Service::Forum::PostingAutomod).
has automod => undef;    # optional: without it nothing is screened

# A schema without the function layer -- the in-memory doubles -- holds no
# messages: its reads are empty and its writes unavailable.
has functions => sub ($self) {
    return GPForum::Infrastructure::SqlFunction->for_schema( $self->schema );
};

sub maximum_body ($self) { return $MAXIMUM_BODY; }

sub daily_limits ($self) {
    return {
        member     => $DAILY_LIMIT,
        new_member => $NEW_MEMBER_DAILY_LIMIT,
        trust      => $NEW_MEMBER_TRUST_BELOW,
    };
}

# The text as it is stored: line endings made one, the outer blank space
# trimmed, the lines inside kept.
sub normalize_body ( $self, $body ) {
    return q{} if !defined $body;
    $body =~ s/\r\n?/\n/gmsx;
    $body =~ s/\A\s+//msx;
    $body =~ s/\s+\z//msx;

    return $body;
}

# Sends a message to the member called $input->{username}, in the one
# conversation the two hold, starting it when there is none.
sub start ( $self, $input ) {
    my $username = $input->{username} // q{};
    return _refused( 'invalid', 'username' )
      if !length $username || length $username > $MAXIMUM_USERNAME;

    return $self->_send(
        'community_message_start',
        $input,
        {
            username               => $username,
            new_conversation_id    => $self->id_service->uuid,
            daily_limit            => $DAILY_LIMIT,
            new_member_daily_limit => $NEW_MEMBER_DAILY_LIMIT,
            new_member_trust_below => $NEW_MEMBER_TRUST_BELOW,
        }
    );
}

# Sends a message in a conversation the sender is a member of.
sub reply ( $self, $input ) {
    return _refused('not_found')
      if !GPForum::Infrastructure::Id->is_uuid_spelling(
        $input->{conversation_id} );

    return $self->_send( 'community_message_reply', $input,
        { conversation_id => $input->{conversation_id} } );
}

# The checks, the screening and the write. A send answers ok (status ok or
# replayed) with the conversation and the message, or a refusal: invalid
# (with the field), forbidden, not_found, self, blocked, gone, limit,
# conflict, or the automod's refusal (status invalid, with automod).
sub _send ( $self, $name, $input, $extra ) {
    my $body = $self->normalize_body( $input->{body} );
    return _refused( 'invalid', 'body' )
      if !length $body || length $body > $MAXIMUM_BODY;
    return _refused('invalid')
      if !GPForum::Infrastructure::Id->is_uuid_spelling(
        $input->{sender_user_id} );
    my $functions = $self->_functions;

    my $message_id =
      GPForum::Infrastructure::Id->is_uuid_spelling( $input->{command_id} )
      ? $input->{command_id}
      : $self->id_service->uuid;
    my $write = sub ($screened) {
        my $row = $functions->row(
            $name,
            {
                row => {
                    %{$extra},
                    message_id     => $message_id,
                    sender_user_id => $input->{sender_user_id},
                    body           => $screened->{body},
                    created_at     => $self->clock->now_iso8601,
                    event_id       => $self->id_service->uuid,
                    correlation_id => $self->id_service->uuid,
                    outbox_id      => $self->id_service->uuid,
                }
            }
        ) || { status => 'failed' };

        return _answer($row);
    };

    my $screening = {
        author_user_id => $input->{sender_user_id},
        viewer         => $input->{viewer},
        body           => $body,
    };
    return $write->($screening) if !$self->automod;

    my $screen = $self->automod->screen( $SEND, $screening );
    return $screen->{refusal}           if $screen->{refusal};
    return $write->( $screen->{input} ) if !$screen->{settle};

    return $self->automod->settle( $SEND, $screen, $write );
}

sub _answer ($row) {
    my $status = $row->{status} // 'failed';
    return {
        ok                => 0,
        status            => $status,
        conversation_id   => $row->{conversation_id},
        recipient_user_id => $row->{recipient_user_id},
      }
      if !exists $SENT{$status};

    return {
        ok                => 1,
        status            => $status,
        idempotent        => $status eq 'replayed' ? 1 : 0,
        conversation_id   => $row->{conversation_id},
        message_id        => $row->{message_id},
        recipient_user_id => $row->{recipient_user_id},
        started           => $row->{started}      ? 1 : 0,
        first_unread      => $row->{first_unread} ? 1 : 0,
        stored => { message => { message_id => $row->{message_id} } },
    };
}

# A page of the member's conversations, the one moved last first:
# { items, has_next, next_cursor }.
sub inbox ( $self, $user_id, $after = undef ) {
    my $plan = $self->page_window->plan(
        { after => $after, limit => $INBOX_PAGE, sort => 'timestamp' } );
    return _empty_page() if !$self->functions || !defined $user_id;

    my $rows = $self->functions->rows(
        'community_message_inbox',
        {
            user_id   => $user_id,
            after_at  => $plan->{after} ? $plan->{after}{sort_value} : undef,
            after_id  => $plan->{after} ? $plan->{after}{id}         : undef,
            row_limit => $plan->{fetch_rows},
        }
    );

    return _page( $rows, $plan->{limit}, 'last_message_at', 'conversation_id' );
}

# The conversation as the member reads it, or undef when it is not theirs.
sub conversation ( $self, $conversation_id, $user_id ) {
    return undef
      if !$self->functions
      || !defined $user_id
      || !GPForum::Infrastructure::Id->is_uuid_spelling($conversation_id);

    return $self->functions->row( 'community_message_conversation',
        { conversation_id => $conversation_id, user_id => $user_id } );
}

# A page of the conversation's messages, the last stored first, older ones
# before the cursor (a position: the clock reads whole seconds, and two
# messages of one second keep the order they were sent in):
# { items, has_next, next_cursor }.
sub messages ( $self, $conversation_id, $user_id, $before = undef ) {
    my $plan = $self->page_window->plan(
        { after => $before, limit => $CONVERSATION_PAGE, sort => 'position' } );
    return _empty_page()
      if !$self->functions
      || !defined $user_id
      || !GPForum::Infrastructure::Id->is_uuid_spelling($conversation_id);

    my $rows = $self->functions->rows(
        'community_message_list',
        {
            conversation_id => $conversation_id,
            user_id         => $user_id,
            before_position => $plan->{after}
            ? $plan->{after}{sort_value}
            : undef,
            row_limit => $plan->{fetch_rows},
        }
    );

    return _page( $rows, $plan->{limit}, 'message_position', 'message_id' );
}

# The member has read the conversation, and the notifications of it.
sub mark_read ( $self, $conversation_id, $user_id ) {
    my $row = $self->_functions->row(
        'community_message_mark_read',
        {
            conversation_id => $conversation_id,
            user_id         => $user_id,
            now             => $self->clock->now_iso8601,
        }
    ) || { status => 'not_found' };

    return {
        status             => $row->{status},
        notifications_read => 0 + ( $row->{notifications_read} // 0 ),
    };
}

# Whom the member would write to by that name, with the conversation the
# two already hold: undef for nobody to write to.
sub recipient ( $self, $user_id, $username ) {
    return undef
      if !$self->functions
      || !defined $user_id
      || !defined $username
      || !length $username
      || length $username > $MAXIMUM_USERNAME;

    return $self->functions->row(
        'community_message_conversation_with',
        { user_id => $user_id, username => $username }
    );
}

# The message the member may report -- another member's, in a conversation
# of theirs -- or undef.
sub reportable ( $self, $message_id, $user_id ) {
    return undef
      if !$self->functions
      || !defined $user_id
      || !GPForum::Infrastructure::Id->is_uuid_spelling($message_id);

    return $self->functions->row( 'community_message_for_report',
        { message_id => $message_id, user_id => $user_id } );
}

# ADR 0139: the one way staff read a member's message. The reading is
# audited in the same call (direct_message.report_read: the staff member,
# the message, the report; never the text), and only a report about a
# message reads one: { status => ok, message } or { status => not_found |
# gone | invalid }.
sub read_reported ( $self, $report_id, $actor_user_id ) {
    return { status => 'not_found' }
      if !GPForum::Infrastructure::Id->is_uuid_spelling($report_id);

    my $audit = $self->recorder->audit_call(
        action      => $REPORT_READ,
        actor_id    => $actor_user_id,
        metadata    => { report_id => $report_id },
        target_id   => $report_id,
        target_type => 'message',
    )->{audit};
    my $row =
      $self->_functions->row( 'moderation_reported_message',
        { report_id => $report_id, audit => $audit } )
      || { status => 'not_found' };
    return { status => $row->{status} } if $row->{status} ne 'ok';

    return {
        status  => 'ok',
        message => {
            map { $_ => $row->{$_} }
              qw(report_id message_id author_user_id author_username body
              created_at)
        },
    };
}

sub _page ( $rows, $limit, $sort_column, $id_column ) {
    my @items    = @{ $rows || [] };
    my $has_next = @items > $limit ? 1 : 0;
    if ($has_next) {
        pop @items;
    }

    return {
        items       => \@items,
        has_next    => $has_next,
        next_cursor => $has_next
        ? encode_base64url(
            join q{|},
            $items[-1]{$sort_column},
            $items[-1]{$id_column}
          )
        : undef,
    };
}

sub _empty_page {
    return { items => [], has_next => 0, next_cursor => undef };
}

sub _functions ($self) {
    return $self->functions // GPForum::X::Unavailable->throw(
        message => 'direct messages need the PostgreSQL function layer' );
}

sub _refused ( $status, $field = undef ) {
    return {
        ok     => 0,
        status => $status,
        ( defined $field ? ( field => $field ) : () ),
    };
}

1;

__END__

=head1 NAME

GPForum::Service::Community::MessageStore - Direct messages between two members.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $messages = GPForum::Service::Community::MessageStore->new(
        schema => $schema, automod => $posting_automod );
    my $sent = $messages->start(
        {
            sender_user_id => $id,
            username       => 'ada',
            body           => 'Hello',
            command_id     => $command_id,
        }
    );
    my $page = $messages->inbox( $id, $cursor );

=head1 DESCRIPTION

ADR 0139. Two members hold one private conversation; each message is plain
text of 1 to 5000 characters. Every read and write is a function of schema
C<api> (ADR 0126); refusals are result values (ADR 0118). A send is
screened by the watched words and the link rule as a reply is (ADR 0133),
when the store has an C<automod>. The function refuses a send when either
member blocks the other (ADR 0130), and a new conversation beyond the
sender's daily bound: 3 in a day below trust level 1, 20 otherwise.

=head1 SUBROUTINES/METHODS

=head2 start

Sends a message to the member named by C<username>, starting the
conversation when the two hold none. Takes C<sender_user_id>, C<username>,
C<body>, C<command_id> (the message's id, so a form sent twice sends one
message) and C<viewer> (for the screening). Answers C<ok> with C<status>
(C<ok> or C<replayed>), C<conversation_id>, C<message_id>,
C<recipient_user_id>, C<started> and C<first_unread>; or C<ok> 0 with
C<status> C<invalid> (with C<field>, or C<automod>), C<forbidden>,
C<not_found>, C<self>, C<blocked>, C<limit>, C<conflict> or C<failed>.

=head2 reply

As L</start>, in the conversation C<conversation_id>; refuses C<not_found>
for a conversation that is not the sender's and C<gone> when the other
member's account was erased.

=head2 normalize_body

The text as stored: line endings made one, the outer blank space trimmed.

=head2 inbox

A page of the member's conversations, the one moved last first, each with
the other member, the unread count and the start of the latest message.

=head2 conversation

The conversation as its member reads it, or undef for anyone else.

=head2 messages

A page of the conversation's messages, the last sent first (by the order
they were stored in), for its members only.

=head2 mark_read

Marks the conversation read for the member, and the inbox's notifications
of its messages; answers C<status> (C<ok>, C<unchanged>, C<not_found>) and
C<notifications_read>.

=head2 recipient

Whom the member would write to by that name, with the conversation the two
already hold, or undef.

=head2 reportable

The message the member may report, or undef.

=head2 read_reported

Reads the message a report names for the staff member given, and audits
the reading in the same call.

=head2 maximum_body

5000.

=head2 daily_limits

The bounds on new conversations a day: C<member>, C<new_member> and the
C<trust> level below which a member is new.

=head1 DIAGNOSTICS

A write on a schema without the function layer throws
L<GPForum::X::Unavailable>; database errors propagate.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Infrastructure::SqlFunction>,
L<GPForum::Service::Forum::PostingAutomod> (optional).

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

A message cannot be edited or deleted by its author; conversations hold
two members.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause
license.

=cut
