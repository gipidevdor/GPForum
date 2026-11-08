# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Community::MessageStore;

use Const::Fast;
use MIME::Base64 qw(encode_base64url);
use Mojo::Base 'GPForum::Base', -async_await;
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
has recorder    => \&GPForum::Infrastructure::EventRecorder::for_service;
__PACKAGE__->requires(qw(schema));

# ADR 0133: the watched words and the link rule, as a reply is screened
# (Service::Forum::PostingAutomod).
has automod => undef;    # optional: without it nothing is screened

# A schema without the function layer -- the in-memory doubles -- holds no
# messages: its reads are empty and its writes unavailable.
has functions => \&GPForum::Infrastructure::SqlFunction::for_service;

sub maximum_body ($self) { return $MAXIMUM_BODY; }

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
    my ( $refused, @send ) = $self->_start_call($input);
    return $refused // $self->_send(@send);
}

# The send on the worker's pooled asynchronous connections.
async sub start_p ( $self, $input, $context = undef ) {
    my ( $refused, @send ) = $self->_start_call($input);
    return $refused // await $self->_send_p( @send, $context );
}

sub _start_call ( $self, $input ) {
    my $username = $input->{username} // q{};
    return _refused( 'invalid', 'username' )
      if !length $username || length $username > $MAXIMUM_USERNAME;

    return (
        undef,
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
    my ( $refused, @send ) = _reply_call($input);
    return $refused // $self->_send(@send);
}

async sub reply_p ( $self, $input, $context = undef ) {
    my ( $refused, @send ) = _reply_call($input);
    return $refused // await $self->_send_p( @send, $context );
}

sub _reply_call ($input) {
    return _refused('not_found')
      if !GPForum::Infrastructure::Id->is_uuid_spelling(
        $input->{conversation_id} );

    return ( undef, 'community_message_reply', $input,
        { conversation_id => $input->{conversation_id} } );
}

# The checks, the screening and the write. A send answers ok (status ok or
# replayed) with the conversation and the message, or a refusal: invalid
# (with the field), forbidden, not_found, self, blocked, gone, limit,
# conflict, or the automod's refusal (status invalid, with automod).
sub _send ( $self, $name, $input, $extra ) {
    my $plan = $self->_send_plan( $input, $extra );
    return $plan->{refused} if $plan->{refused};
    my $functions = $self->_functions;
    my $write     = sub ($screened) {
        return _answer( $functions->row( $name, $plan->{call}->($screened) )
              || { status => 'failed' } );
    };
    return $write->( $plan->{screening} ) if !$self->automod;

    my $screen = $self->automod->screen( $SEND, $plan->{screening} );
    return $screen->{refusal}           if $screen->{refusal};
    return $write->( $screen->{input} ) if !$screen->{settle};

    return $self->automod->settle( $SEND, $screen, $write );
}

# The same send on the worker's pooled asynchronous connections: the screen,
# and a settled write with its decisions in one transaction, there too.
async sub _send_p ( $self, $name, $input, $extra, $context ) {
    return $self->_send( $name, $input, $extra ) if !$self->functions;
    my $plan = $self->_send_plan( $input, $extra );
    return $plan->{refused} if $plan->{refused};
    my $write_p = async sub ( $screened, $functions = undef ) {
        $functions //= $self->functions;
        return _answer(
            (
                await $functions->row_p(
                    $name, $plan->{call}->($screened), $context
                )
            )
              || { status => 'failed' }
        );
    };
    return await $write_p->( $plan->{screening} ) if !$self->automod;

    my $screen =
      await $self->automod->screen_p( $SEND, $plan->{screening}, $context );
    return $screen->{refusal}                   if $screen->{refusal};
    return await $write_p->( $screen->{input} ) if !$screen->{settle};

    return await $self->automod->settle_p( $SEND, $screen, $write_p, $context );
}

# The checks before a send, then what is screened and the call's values for
# the screened text.
sub _send_plan ( $self, $input, $extra ) {
    my $body = $self->normalize_body( $input->{body} );
    return { refused => _refused( 'invalid', 'body' ) }
      if !length $body || length $body > $MAXIMUM_BODY;
    return { refused => _refused('invalid') }
      if !GPForum::Infrastructure::Id->is_uuid_spelling(
        $input->{sender_user_id} );
    $self->_functions;

    my $message_id =
      GPForum::Infrastructure::Id->is_uuid_spelling( $input->{command_id} )
      ? $input->{command_id}
      : $self->id_service->uuid;
    return {
        call => sub ($screened) {
            return {
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
            };
        },
        screening => {
            author_user_id => $input->{sender_user_id},
            viewer         => $input->{viewer},
            body           => $body,
        },
    };
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
    my $plan = $self->_inbox_plan($after);
    return _empty_page() if !$self->functions || !defined $user_id;

    return _inbox_page(
        $plan,
        $self->functions->rows(
            'community_message_inbox', _inbox_values( $user_id, $plan )
        )
    );
}

# The reads a member's GET pages make, as the web worker runs them: on its
# pooled asynchronous connections. Through call_p's fallback each one forked
# a child that opened a connection of its own, one child at a time.
async sub inbox_p ( $self, $user_id, $after = undef, $context = undef ) {
    my $plan = $self->_inbox_plan($after);
    return _empty_page() if !$self->functions || !defined $user_id;

    return _inbox_page(
        $plan,
        await $self->functions->rows_p(
            'community_message_inbox', _inbox_values( $user_id, $plan ),
            $context
        )
    );
}

sub _inbox_plan ( $self, $after ) {
    return $self->page_window->plan(
        { after => $after, limit => $INBOX_PAGE, sort => 'timestamp' } );
}

sub _inbox_values ( $user_id, $plan ) {
    return {
        user_id   => $user_id,
        after_at  => $plan->{after} ? $plan->{after}{sort_value} : undef,
        after_id  => $plan->{after} ? $plan->{after}{id}         : undef,
        row_limit => $plan->{fetch_rows},
    };
}

sub _inbox_page ( $plan, $rows ) {
    return _page( $rows, $plan->{limit}, 'last_message_at', 'conversation_id' );
}

# The conversation as the member reads it, or undef when it is not theirs.
sub conversation ( $self, $conversation_id, $user_id ) {
    return undef if !$self->_reads_conversation( $conversation_id, $user_id );

    return $self->functions->row( 'community_message_conversation',
        { conversation_id => $conversation_id, user_id => $user_id } );
}

async sub conversation_p ( $self, $conversation_id, $user_id, $context = undef )
{
    return undef if !$self->_reads_conversation( $conversation_id, $user_id );

    return (
        await $self->functions->row_p(
            'community_message_conversation',
            { conversation_id => $conversation_id, user_id => $user_id },
            $context
        )
    );
}

# A page of the conversation's messages, the last stored first, older ones
# before the cursor (a position: the clock reads whole seconds, and two
# messages of one second keep the order they were sent in):
# { items, has_next, next_cursor }.
sub messages ( $self, $conversation_id, $user_id, $before = undef ) {
    my $plan = $self->_messages_plan($before);
    return _empty_page()
      if !$self->_reads_conversation( $conversation_id, $user_id );

    return _messages_page(
        $plan,
        $self->functions->rows(
            'community_message_list',
            _messages_values( $conversation_id, $user_id, $plan )
        )
    );
}

async sub messages_p (
    $self, $conversation_id, $user_id,
    $before = undef,
    $context = undef
  )
{
    my $plan = $self->_messages_plan($before);
    return _empty_page()
      if !$self->_reads_conversation( $conversation_id, $user_id );

    return _messages_page(
        $plan,
        await $self->functions->rows_p(
            'community_message_list',
            _messages_values( $conversation_id, $user_id, $plan ), $context
        )
    );
}

sub _reads_conversation ( $self, $conversation_id, $user_id ) {
    return
         $self->functions
      && defined $user_id
      && GPForum::Infrastructure::Id->is_uuid_spelling($conversation_id);
}

sub _messages_plan ( $self, $before ) {
    return $self->page_window->plan(
        { after => $before, limit => $CONVERSATION_PAGE, sort => 'position' } );
}

sub _messages_values ( $conversation_id, $user_id, $plan ) {
    return {
        conversation_id => $conversation_id,
        user_id         => $user_id,
        before_position => $plan->{after} ? $plan->{after}{sort_value} : undef,
        row_limit       => $plan->{fetch_rows},
    };
}

sub _messages_page ( $plan, $rows ) {
    return _page( $rows, $plan->{limit}, 'message_position', 'message_id' );
}

# The member has read the conversation, and the notifications of it.
sub mark_read ( $self, $conversation_id, $user_id ) {
    return _marked(
        $self->_functions->row(
            'community_message_mark_read',
            $self->_mark_values( $conversation_id, $user_id )
        )
    );
}

async sub mark_read_p ( $self, $conversation_id, $user_id, $context = undef ) {
    return _marked(
        await $self->_functions->row_p(
            'community_message_mark_read',
            $self->_mark_values( $conversation_id, $user_id ),
            $context
        )
    );
}

sub _mark_values ( $self, $conversation_id, $user_id ) {
    return {
        conversation_id => $conversation_id,
        user_id         => $user_id,
        now             => $self->clock->now_iso8601,
    };
}

sub _marked ($row) {
    $row ||= { status => 'not_found' };
    return {
        status             => $row->{status},
        notifications_read => 0 + ( $row->{notifications_read} // 0 ),
    };
}

# Whom the member would write to by that name, with the conversation the
# two already hold: undef for nobody to write to.
sub recipient ( $self, $user_id, $username ) {
    return undef if !$self->_names_recipient( $user_id, $username );

    return $self->functions->row(
        'community_message_conversation_with',
        { user_id => $user_id, username => $username }
    );
}

# The compose page's lookup on the worker's pooled asynchronous connections.
async sub recipient_p ( $self, $user_id, $username, $context = undef ) {
    return undef if !$self->_names_recipient( $user_id, $username );

    return await $self->functions->row_p( 'community_message_conversation_with',
        { user_id => $user_id, username => $username }, $context );
}

sub _names_recipient ( $self, $user_id, $username ) {
    return
         $self->functions
      && defined $user_id
      && defined $username
      && length $username
      && length $username <= $MAXIMUM_USERNAME ? 1 : 0;
}

# The message the member may report -- another member's, in a conversation
# of theirs -- or undef.
sub reportable ( $self, $message_id, $user_id ) {
    return undef if !$self->_names_message( $message_id, $user_id );

    return $self->functions->row( 'community_message_for_report',
        { message_id => $message_id, user_id => $user_id } );
}

async sub reportable_p ( $self, $message_id, $user_id, $context = undef ) {
    return undef if !$self->_names_message( $message_id, $user_id );

    return await $self->functions->row_p( 'community_message_for_report',
        { message_id => $message_id, user_id => $user_id }, $context );
}

sub _names_message ( $self, $message_id, $user_id ) {
    return
         $self->functions
      && defined $user_id
      && GPForum::Infrastructure::Id->is_uuid_spelling($message_id) ? 1 : 0;
}

# ADR 0139: the one way staff read a member's message. The reading is
# audited in the same call (direct_message.report_read: the staff member,
# the message, the report; never the text), and only a report about a
# message reads one: { status => ok, message } or { status => not_found |
# gone | invalid }.
sub read_reported ( $self, $report_id, $actor_user_id ) {
    my ( $refusal, @call ) =
      $self->_reported_values( $report_id, $actor_user_id );
    return $refusal // _reported_answer( $self->_functions->row(@call) );
}

# The same audited read on the worker's pooled asynchronous connections,
# not a forked child with a connection of its own.
async sub read_reported_p ( $self, $report_id, $actor_user_id,
    $context = undef )
{
    return $self->read_reported( $report_id, $actor_user_id )
      if !$self->functions;
    my ( $refusal, @call ) =
      $self->_reported_values( $report_id, $actor_user_id );
    return $refusal
      // _reported_answer( await $self->functions->row_p( @call, $context ) );
}

# A refusal, or undef and the audited read's function and values.
sub _reported_values ( $self, $report_id, $actor_user_id ) {
    return { status => 'not_found' }
      if !GPForum::Infrastructure::Id->is_uuid_spelling($report_id);

    my $audit = $self->recorder->audit_call(
        action      => $REPORT_READ,
        actor_id    => $actor_user_id,
        metadata    => { report_id => $report_id },
        target_id   => $report_id,
        target_type => 'message',
    )->{audit};
    return ( undef, 'moderation_reported_message',
        { report_id => $report_id, audit => $audit } );
}

sub _reported_answer ($row) {
    $row ||= { status => 'not_found' };
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

=head2 start_p

L</start> as a promise, with an optional query context last: the screen and
the send run on the worker's pooled asynchronous connections, a settled
send and its automod decisions in one transaction.

=head2 reply

As L</start>, in the conversation C<conversation_id>; refuses C<not_found>
for a conversation that is not the sender's and C<gone> when the other
member's account was erased.

=head2 reply_p

L</reply> as a promise, with an optional query context last, sent as
L</start_p> sends.

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

=head2 inbox_p

L</inbox> as a promise, with an optional query context last, read on the
worker's pooled asynchronous connections.

=head2 conversation_p

L</conversation> as a promise, read the same way.

=head2 messages_p

L</messages> as a promise, read the same way.

=head2 mark_read

Marks the conversation read for the member, and the inbox's notifications
of its messages; answers C<status> (C<ok>, C<unchanged>, C<not_found>) and
C<notifications_read>.

=head2 mark_read_p

L</mark_read> as a promise, with an optional query context last, run on the
worker's pooled asynchronous connections.

=head2 recipient

Whom the member would write to by that name, with the conversation the two
already hold, or undef.

=head2 recipient_p

L</recipient> as a promise, with an optional query context last, read on
the worker's pooled asynchronous connections.

=head2 reportable

The message the member may report, or undef.

=head2 reportable_p

L</reportable> as a promise, with an optional query context last, read on
the worker's pooled asynchronous connections.

=head2 read_reported

Reads the message a report names for the staff member given, and audits
the reading in the same call.

=head2 read_reported_p

L</read_reported> as a promise, with an optional query context last, read
and audited on the worker's pooled asynchronous connections.

=head2 maximum_body

5000.

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

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
