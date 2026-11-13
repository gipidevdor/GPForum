# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Community::MentionStore;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -signatures, -async_await;
use v5.40;

use GPForum::Infrastructure::Id;
use GPForum::Infrastructure::Row qw(column_of);
use GPForum::Infrastructure::EventRecorder;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Service::Clock;
use GPForum::Service::Community::MentionExtractor;
use GPForum::X::Conflict;
use GPForum::X::Unavailable;

our $VERSION = '0.001';

const my $DEFAULT_MAX_MENTIONS => 10;
const my $SCHEMA_VERSION       => 1;

has clock => sub { return GPForum::Service::Clock->new; };
has extractor =>
  sub { return GPForum::Service::Community::MentionExtractor->new; };
has id_service              => sub { return GPForum::Infrastructure::Id->new; };
has notification_dispatcher => undef;    # optional: no notifications

# ADR 0102: who may read the source. A mention of someone who cannot is not
# recorded, so it neither notifies them nor lists the thread on their
# mentions page.
has readability => undef;    # optional: every source counts as readable

# ADR 0130: a member who blocks the author is not mentioned at all -- no
# mention row, no notification. Service::Community::RelationStore.
has relations => undef;    # optional: nobody blocks anyone
has recorder  => \&GPForum::Infrastructure::EventRecorder::for_service;
__PACKAGE__->requires(qw(schema));
has functions => \&GPForum::Infrastructure::SqlFunction::for_service;

# Written once, as its promise method (ADR 0177); the services it awaits
# block with it.
GPForum::Infrastructure::SqlFunction->blocking_twins('record_for_source');
GPForum::Infrastructure::SqlFunction->blocking_parts(
    qw(readability relations recorder notification_dispatcher));

# The mentions in a source's body, recorded and notified. With $scope --
# the call layer of the post's own transaction -- every read and write
# joins it: the post the readability check reads is not committed yet, and
# a notification's badge goes out when it commits. Without one the inserts
# and notifications commit in a transaction of their own.
async sub record_for_source_p ( $self, $input, $context = undef,
    $scope = undef )
{
    my $mentions = $self->extractor->extract( $input->{body_source} );
    return _empty_result() if !@{$mentions};

    my $limited = $self->_limited_mentions( $input, $mentions );
    if ( $limited->{audit} ) {
        await $self->_record_fanout_audit_p( $limited->{audit}, $context,
            $scope );
    }
    my $work = async sub ($layer) {
        my $joined = $self->_joined($layer);
        my $resolved =
          await $joined->_resolve_users_p( $limited->{mentions}, $context );
        my $result =
          await $joined->_insert_mentions_p( $input, $limited->{mentions},
            $resolved, $context, $layer );
        push @{ $result->{skipped} }, @{ $limited->{skipped} };
        return $result;
    };
    return await $work->($scope) if $scope;

    return await $self->_functions->transaction_p( $work, $context );
}

# The store and the services it reads and writes through on a
# transaction's call layer.
sub _joined ( $self, $layer ) {
    return GPForum::Infrastructure::SqlFunction->joined( $self, $layer );
}

# The mentions within the cap, those past it skipped, and the audit of the
# cut when there was one.
sub _limited_mentions ( $self, $input, $mentions ) {
    my $max_mentions = $input->{max_mentions} || $DEFAULT_MAX_MENTIONS;
    return { mentions => $mentions, skipped => [] }
      if @{$mentions} <= $max_mentions;

    my @allowed = @{$mentions}[ 0 .. $max_mentions - 1 ];
    my @blocked = @{$mentions}[ $max_mentions .. $#{$mentions} ];
    my @skipped = map { _skip( $_, 'fanout_limited' ) } @blocked;

    return {
        mentions => \@allowed,
        skipped  => \@skipped,
        audit => $self->_fanout_audit( $input, scalar @blocked, $max_mentions ),
    };
}

sub _fanout_audit ( $self, $input, $blocked_count, $max_mentions ) {
    return {
        action     => 'mention.fanout_limited',
        actor_id   => _uuid_or_undef( $input->{actor_id} ),
        created_at => $self->clock->now_iso8601,
        metadata   => {
            blocked_count => $blocked_count,
            max_mentions  => $max_mentions,
            source_id     => $input->{source_id},
            source_type   => $input->{source_type},
        },
        previous_hash  => undef,
        record_hash    => q{},
        schema_version => $SCHEMA_VERSION,
        target_id      => _uuid_or_undef( $input->{source_id} ),
        target_type    => 'mention',
    };
}

# The audit of the cut, in a savepoint of the caller's transaction when
# there is one: a failure to write it is ignored, and must not abort the
# post's transaction.
async sub _record_fanout_audit_p ( $self, $audit, $context, $scope ) {
    my $created;
    try {
        $created = $scope
          ? await $scope->transaction_p(
            async sub ($savepoint) {
                return await $self->_joined($savepoint)
                  ->recorder->record_audit_p( $audit, $context );
            },
            $context
          )
          : await $self->recorder->record_audit_p( $audit, $context );
    }
    catch ($error) {
        return undef;
    };

    return $created;
}

# Each member is mentioned once per source. An unknown member, the author,
# and a member who cannot read the source are skipped. A mention already
# stored is notified again as it is met -- the dispatcher answers a
# duplicate, which is not counted -- and new ones once all are stored. The
# store is joined to the transaction's call layer, and the dispatcher is
# handed it.
async sub _insert_mentions_p ( $self, $input, $mentions, $resolved, $context,
    $layer )
{
    my ( @created, @notifications, @skipped );
    for my $mention ( @{$mentions} ) {
        my ( $skip, $user_id ) = _unmentioned( $input, $mention, $resolved );
        $skip //=
          await $self->_unreadable_or_blocked_p( $input, $user_id, $context );
        if ($skip) {
            push @skipped, _skip( $mention, $skip );
            next;
        }

        my $row     = $self->_mention_row( $input, $mention, $user_id );
        my $created = await $self->_create_by_function_p( $row, $context );
        if ($created) {
            push @created, $created;
            next;
        }
        push @notifications,
          await $self->_accepted_notification_p( $input, $row, $context,
            $layer );
    }
    for my $created (@created) {
        push @notifications,
          await $self->_accepted_notification_p( $input, $created, $context,
            $layer );
    }

    return _inserted( \@created, \@notifications, \@skipped );
}

# Why a mention is not recorded before anything is read -- an unknown
# member, or the author -- and the member's id otherwise.
sub _unmentioned ( $input, $mention, $resolved ) {
    my $user = $resolved->{ $mention->{username} };
    return 'unknown_user' if !$user;
    my $user_id = column_of( $user, 'id' );
    return 'self_mention' if $user_id eq $input->{actor_id};

    return ( undef, $user_id );
}

async sub _unreadable_or_blocked_p ( $self, $input, $user_id, $context ) {
    my ( $readability, $relations ) = ( $self->readability, $self->relations );
    if ($readability) {
        my @source = ( $user_id, $input->{source_type}, $input->{source_id} );
        return 'source_not_readable'
          if !await $readability->readable_by_p( @source, $context );
    }
    if ($relations) {
        my @pair = ( $user_id, $input->{actor_id} );
        return 'blocked' if await $relations->blocks_p( @pair, $context );
    }

    return undef;
}

sub _mention_row ( $self, $input, $mention, $user_id ) {
    return {
        actor_id           => $input->{actor_id},
        created_at         => $self->clock->now_iso8601,
        mention_id         => $self->id_service->uuid,
        mentioned_user_id  => $user_id,
        mentioned_username => $mention->{username},
        source_id          => $input->{source_id},
        source_type        => $input->{source_type},
    };
}

sub _inserted ( $created, $notifications, $skipped ) {
    return {
        ok            => 1,
        created       => $created,
        notifications => [ grep { defined } @{$notifications} ],
        skipped       => $skipped,
    };
}

# A mention of this member from this source already stored -- before, or by
# a concurrent request -- answers undef. A minted id already stored is
# minted once more.
async sub _create_by_function_p ( $self, $row, $context ) {
    my $create = async sub {
        return (
            await $self->functions->row_p(
                'community_create_mention', { row => $row }, $context
            )
        )->{result};
    };
    my $result = await $create->();
    if ( $result && $result->{retry_id} ) {
        $row->{mention_id} = $self->id_service->uuid;
        $result = await $create->();
        if ( $result && $result->{retry_id} ) {
            GPForum::X::Conflict->throw(
                message => 'the replacement mention id is already stored' );
        }
    }
    return $result;
}

# The member is notified through the dispatcher, when there is one, on the
# caller's transaction. A notification it refused, or already held,
# answers undef.
async sub _accepted_notification_p ( $self, $input, $mention, $context, $layer )
{
    my $dispatcher = $self->notification_dispatcher;
    return undef if !$dispatcher;

    return _accepted(
        await $dispatcher->create_notification_p(
            _notification( $input, $mention ),
            $context, $layer
        )
    );
}

sub _notification ( $input, $mention ) {
    my $post_id =
      $input->{source_type} eq q{post} ? $input->{source_id} : undef;
    return {
        notification_type => 'mention',
        payload           => {
            actor_id           => $input->{actor_id},
            mentioned_username => $mention->{mentioned_username},
            post_id            => $post_id,
            source_id          => $input->{source_id},
            source_type        => $input->{source_type},
            thread_id          => $input->{thread_id},
        },
        recipient_user_id => $mention->{mentioned_user_id},
        source_id         => $input->{source_id},
        source_type       => $input->{source_type},
    };
}

sub _accepted ($result) {
    return undef if !$result || !$result->{ok} || $result->{duplicate};

    return $result;
}

async sub _resolve_users_p ( $self, $mentions, $context ) {
    my @usernames = map { $_->{username} } @{$mentions};
    my $rows =
      await $self->_functions->rows_p( 'community_resolve_mention_users',
        { usernames => \@usernames }, $context );

    return { map { lc( $_->{username} ) => $_ } @{$rows} };
}

sub _functions ($self) {
    return $self->functions // GPForum::X::Unavailable->throw(
        message => 'mentions need the PostgreSQL function layer' );
}

sub _empty_result {
    return {
        ok            => 1,
        created       => [],
        notifications => [],
        skipped       => [],
    };
}

sub _skip ( $mention, $reason ) {
    return {
        username => $mention->{username},
        reason   => $reason,
    };
}

sub _uuid_or_undef ($value) {
    return GPForum::Infrastructure::Id->is_uuid($value) ? $value : undef;
}

1;

__END__

=head1 NAME

GPForum::Service::Community::MentionStore - Record the mentions in a post and notify the people mentioned.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $mentions = GPForum::Service::Community::MentionStore->new(
        notification_dispatcher => $notification_dispatcher,
        readability => GPForum::Service::Forum::Readability->new(
            schema => $schema,
        ),
        schema => $schema,
    );
    my $result = $mentions->record_for_source(
        {
            actor_id     => $author_id,
            body_source  => $body_source,
            max_mentions => 10,
            source_id    => $post_id,
            source_type  => 'post',
            thread_id    => $thread_id,
        }
    );
    # { ok => 1, created => [...], notifications => [...], skipped => [...] }

=head1 DESCRIPTION

Turns the C<@username> mentions found by
L<GPForum::Service::Community::MentionExtractor> into C<mentions> rows and
C<mention> notifications. A mention is not recorded when the username
matches no user (deleted users are not looked up), when it names the
author, or when the
mentioned user cannot read the source (ADR 0102): a mention of someone who
cannot read the post would otherwise notify them and list the thread on
their mentions page.

The number of mentions one body can fan out to is capped (10 by default);
the ones past the cap are skipped and the cut is audited as
C<mention.fanout_limited>, so a post cannot be used to notify a crowd.

Recording is idempotent per source and mentioned user, which a unique
index enforces: C<api.community_create_mention> answers nothing for a
mention already recorded, whose notification is requested again, and a
result the dispatcher marks as a duplicate is left out. It is written once,
as its promise method; the blocking method is its twin, with the services
it awaits (ADR 0177).

=head1 SUBROUTINES/METHODS

=head2 new

Mojo::Base constructor. C<schema> is required. C<notification_dispatcher>
(an object with C<create_notification_p>, such as
L<GPForum::Service::Notification::Dispatcher>) and C<readability> (an
object with C<readable_by_p>, such as L<GPForum::Service::Forum::Readability>)
are optional: without the first no notification is sent, without the
second every resolved user is taken to be able to read the source.
C<clock>, C<extractor>, C<id_service> and C<recorder> have defaults.

=head2 record_for_source_p

Takes a hash reference with C<body_source> (the text to scan),
C<source_type>, C<source_id>, C<actor_id> (the author), C<thread_id> (put
into the notification payload) and an optional C<max_mentions> (10 when
absent or zero), an optional query context and an optional transaction call
layer (the scope a L<GPForum::Infrastructure::SqlFunction/transaction_p>
work receives). With that layer the readability and block checks, the
inserts and the dispatcher's C<create_notification_p> all join the caller's
transaction, so a post still being written is read as its author's
transaction sees it; without it they commit in a transaction of their own.
The fan-out audit is written in a savepoint, its failure ignored.

Answers a hash reference with C<< ok => 1 >>, C<created> (the hashes of the
mention rows inserted), C<notifications> (the dispatcher's results for the
notifications it accepted and did not report as duplicates) and C<skipped>
(C<< { username, reason } >> entries with reason C<unknown_user>,
C<self_mention>, C<source_not_readable>, C<blocked> (the member blocks the
author, ADR 0130) or C<fanout_limited>). A body without mentions answers
empty lists and touches nothing.

=head2 record_for_source

The blocking twin: L</record_for_source_p> run on the blocking call layer
(ADR 0177), its readability, relations, recorder and dispatcher with it.

=head1 DIAGNOSTICS

Database errors propagate, and the transaction rolls back; a mention id
that collides twice throws L<GPForum::X::Conflict>. Without the PostgreSQL
function layer recording raises L<GPForum::X::Unavailable>. A failure to write the fan-out audit is ignored.
L<GPForum::Service::Forum::PostingWorkflow> calls this inside a C<try> so
that a failed mention does not fail the post.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Service::Community::MentionExtractor>,
L<GPForum::Infrastructure::EventRecorder>,
L<GPForum::Infrastructure::UniqueConflict>, L<GPForum::X::Conflict>,
L<GPForum::Infrastructure::Row>, L<GPForum::Infrastructure::Id>,
L<GPForum::Service::Clock>.

Extends L<GPForum::Base>: built without C<schema> it throws
L<GPForum::X::Argument>.

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
