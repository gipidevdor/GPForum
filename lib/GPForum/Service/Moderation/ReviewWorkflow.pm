# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Moderation::ReviewWorkflow;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -signatures, -async_await;
use v5.40;

use GPForum::Infrastructure::Id;
use GPForum::Infrastructure::Row  qw(column_of);
use GPForum::Infrastructure::Text qw(trimmed);
use GPForum::X::Conflict;

our $VERSION = '0.001';

# ADR 0134: the command each kind of held post is published by.
const my %COMMAND  => ( thread => 'thread.create', reply => 'reply.create' );
const my $APPROVED => 'approved';
const my $REJECTED => 'rejected';

__PACKAGE__->requires(qw(store posting viewer_resolver));
has notifications => undef;    # optional: without it nobody is notified
has reply_links   => undef;    # optional: without it a reply is not linked
has thread_tags   => undef;    # optional: without it a held thread gets no tags
has logger        => undef;    # optional: without it nothing is logged

# Approves a pending post: publishes it as its author's command, then
# records the decision, under the entry's lock and in one transaction. A
# post that can no longer be published (its thread locked or gone, its
# author suspended) is refused, and nothing is recorded: staff reject it
# instead. The author is told once it is published.
sub approve ( $self, $input ) {
    my $review_id = $input->{review_id} // q{};
    return _not_found()
      if !GPForum::Infrastructure::Id->is_uuid_spelling($review_id);

    my ( $answer, $refusal );
    try {
        $answer = $self->store->in_transaction(
            sub {
                my $held = $self->store->take($review_id);
                return _not_found() if !$held;
                return _settled( $held->{status}, $APPROVED, $held->{review_id},
                    $held )
                  if $held->{status} ne 'pending';

                my $published = $self->_publish($held);
                if ( !$published->{ok} ) {
                    $refusal = $published;
                    GPForum::X::Conflict->throw(
                        message => 'the held post was not published' );
                }
                return $self->_approved( $input, $held, $published );
            }
        );
    }
    catch ($error) {
        return _refused($refusal) if $refusal;
        $self->_log( error => "review approval failed: $error" );
        return _failed();
    };
    if ( $answer->{ok} && $answer->{status} eq 'ok' ) {
        $self->_link_reply($answer);
        $self->_set_tags($answer);
        $self->_notify( 'review_approved', $answer );
    }

    return $answer;
}

# The approval on the worker's pooled asynchronous connections: the take,
# the publication and the decision commit in one transaction, as approve's
# do, and the link, the tags and the notification follow once it has.
async sub approve_p ( $self, $input, $context = undef ) {
    my $store = $self->store;
    return $self->approve($input)
      if !$store->can('in_transaction_p') || !$store->functions;
    my $review_id = $input->{review_id} // q{};
    return _not_found()
      if !GPForum::Infrastructure::Id->is_uuid_spelling($review_id);

    my ( $answer, $refusal );
    try {
        $answer = await $store->in_transaction_p(
            async sub ( $joined, $scope ) {
                my $held = await $joined->take_p( $review_id, $context );
                return _not_found() if !$held;
                return _settled( $held->{status}, $APPROVED, $held->{review_id},
                    $held )
                  if $held->{status} ne 'pending';

                my $published =
                  await $self->_publish_p( $held, $context, $scope );
                if ( !$published->{ok} ) {
                    $refusal = $published;
                    GPForum::X::Conflict->throw(
                        message => 'the held post was not published' );
                }
                my $decision = _approval( $input, $held, $published );
                return _approved_answer( $decision,
                    await $joined->decide_p( $decision->{decide}, $context ) );
            },
            $context
        );
    }
    catch ($error) {
        return _refused($refusal) if $refusal;
        $self->_log( error => "review approval failed: $error" );
        return _failed();
    };
    if ( $answer->{ok} && $answer->{status} eq 'ok' ) {
        await $self->_link_reply_p( $answer, $context );
        await $self->_set_tags_p( $answer, $context );
        await $self->_notify_p( 'review_approved', $answer, $context );
    }

    return $answer;
}

# Rejects a pending post, with an optional reason the author reads.
sub reject ( $self, $input ) {
    my ( $refusal, $decision ) = $self->_rejection($input);
    return $refusal if $refusal;

    my $answer = $self->_decide($decision);
    if ( _decided_ok($answer) ) {
        $answer->{reason} = $decision->{reason};
        $self->_notify( 'review_rejected', $answer );
    }

    return $answer;
}

# The rejection on the worker's pooled asynchronous connections.
async sub reject_p ( $self, $input, $context = undef ) {
    my ( $refusal, $decision ) = $self->_rejection($input);
    return $refusal if $refusal;

    my $answer = await $self->_decide_p( $decision, $context );
    if ( _decided_ok($answer) ) {
        $answer->{reason} = $decision->{reason};
        await $self->_notify_p( 'review_rejected', $answer, $context );
    }

    return $answer;
}

# A refusal of the reason, or undef and the decision a rejection records.
sub _rejection ( $self, $input ) {
    my $reason = trimmed( $input->{reason} );
    return { ok => 0, status => 'invalid', field => 'reason' }
      if length $reason > $self->store->maximum_reason;
    return (
        undef,
        {
            review_id     => $input->{review_id},
            status        => $REJECTED,
            actor_user_id => $input->{actor_user_id},
            reason        => $reason,
        }
    );
}

sub _decided_ok ($answer) {
    return $answer->{ok} && $answer->{status} eq 'ok' ? 1 : 0;
}

# The author takes back a post still pending.
sub withdraw ( $self, $input ) {
    return $self->_decide( _withdrawal($input) );
}

# The withdrawal on the worker's pooled asynchronous connections.
async sub withdraw_p ( $self, $input, $context = undef ) {
    return await $self->_decide_p( _withdrawal($input), $context );
}

sub _withdrawal ($input) {
    return {
        review_id     => $input->{review_id},
        status        => 'withdrawn',
        actor_user_id => $input->{author_user_id},
    };
}

sub _publish ( $self, $held ) {
    my ( $refusal, $type, $input ) = _publication( $held,
        $self->viewer_resolver->resolve( $held->{author_user_id} ) );
    return $refusal // $self->posting->publish_reviewed( $type, $input );
}

# _publish on the worker's pooled asynchronous connections, the post written
# on the review's transaction ($scope).
async sub _publish_p ( $self, $held, $context, $scope ) {
    my $resolver = $self->viewer_resolver;
    my $viewer =
      $resolver->can('resolve_p')
      ? await $resolver->resolve_p( $held->{author_user_id}, $context )
      : $resolver->resolve( $held->{author_user_id} );
    my ( $refusal, $type, $input ) = _publication( $held, $viewer );
    return $refusal if $refusal;
    my $posting = $self->posting;

    return $posting->can('publish_reviewed_p')
      ? await $posting->publish_reviewed_p( $type, $input, $context, $scope )
      : $posting->publish_reviewed( $type, $input );
}

# The refusal of an author who cannot post now, or undef, the command and
# its input the held post is published by.
sub _publication ( $held, $viewer ) {
    my $kind = $held->{kind} // q{};

    # The resolver reads a suspended, closed or unreadable account as no
    # member, and a non-member writes nothing: the posting workflow trusts
    # the controller's participation check, which an approval never passes.
    return {
        ok     => 0,
        status => 'forbidden',
        error  => 'the author cannot post now'
      }
      if !$viewer->member;

    my %common = (
        viewer         => $viewer,
        author_user_id => $held->{author_user_id},
        body_source    => $held->{body_source},
        command_id     => $held->{command_id},
        visibility     => $held->{visibility},
    );
    my %where =
      $kind eq 'thread'
      ? ( category_id => $held->{category_id}, title => $held->{title} )
      : ( thread_id => $held->{thread_id} );

    return (
        undef,
        exists $COMMAND{$kind} ? $COMMAND{$kind} : q{},
        { %common, %where }
    );
}

sub _approved ( $self, $input, $held, $published ) {
    my $decision = _approval( $input, $held, $published );

    return _approved_answer( $decision,
        $self->store->decide( $decision->{decide} ) );
}

# The decision an approval records, and the answer it gives once recorded.
sub _approval ( $input, $held, $published ) {
    my $stored    = $published->{stored} // {};
    my $post_id   = column_of( $stored->{post},   'post_id' );
    my $thread_id = column_of( $stored->{thread}, 'thread_id' )
      // column_of( $stored->{post}, 'thread_id' ) // $held->{thread_id};
    return {
        decide => {
            review_id     => $held->{review_id},
            status        => $APPROVED,
            actor_user_id => $input->{actor_user_id},
            post_id       => $post_id,
        },
        answer => {
            ok               => 1,
            status           => 'ok',
            review_status    => $APPROVED,
            review_id        => $held->{review_id},
            author_user_id   => $held->{author_user_id},
            kind             => $held->{kind},
            thread_id        => $thread_id,
            post_id          => $post_id,
            reply_to_post_id => $held->{reply_to_post_id},
            tags             => $held->{tags} // q{},
            stored           => $stored,
        },
    };
}

sub _approved_answer ( $decision, $decided ) {
    my $status = $decided->{status} // q{};
    if ( $status ne 'ok' ) {
        GPForum::X::Conflict->throw(
            message => "the approval was not recorded: $status" );
    }

    return $decision->{answer};
}

sub _decide ( $self, $input ) {
    my $row;
    try {
        $row = $self->store->decide($input);
    }
    catch ($error) {
        $self->_log( error => "review decision failed: $error" );
        return _failed();
    };
    return _decided( $input, $row );
}

async sub _decide_p ( $self, $input, $context ) {
    my $store = $self->store;
    my $row;
    try {
        $row =
          $store->can('decide_p')
          ? await $store->decide_p( $input, $context )
          : $store->decide($input);
    }
    catch ($error) {
        $self->_log( error => "review decision failed: $error" );
        return _failed();
    };
    return _decided( $input, $row );
}

sub _decided ( $input, $row ) {
    my $status = $row->{status} // 'not_found';
    return _not_found() if $status eq 'not_found';
    return { ok => 0, status => 'invalid', field => 'status' }
      if $status eq 'invalid';
    return _settled( $row->{review_status}, $input->{status},
        $input->{review_id}, $row )
      if $status ne 'ok';

    return {
        ok             => 1,
        status         => 'ok',
        review_status  => $input->{status},
        review_id      => $input->{review_id},
        author_user_id => $row->{author_user_id},
        kind           => $row->{kind},
        thread_id      => $row->{thread_id},
        post_id        => $row->{post_id},
    };
}

# A post already decided: the same decision again is no change, another
# one a conflict. The review is the one asked about: the decision's row
# names none, so the repeat answered a null review_id where the first
# answer named it.
sub _settled ( $current, $wanted, $review_id, $row ) {
    return {
        ok            => 1,
        status        => 'unchanged',
        review_status => $current,
        review_id     => $review_id,
        post_id       => $row->{post_id},
        thread_id     => $row->{thread_id},
      }
      if ( $current // q{} ) eq $wanted;

    return {
        ok            => 0,
        status        => 'conflict',
        error         => 'held post already decided',
        review_status => $current,
    };
}

# ADR 0132: a reply that answered a post is linked to it once published.
sub _link_reply ( $self, $answer ) {
    my $target = $answer->{reply_to_post_id};
    return if !$self->reply_links || !$target || !$answer->{post_id};
    try {
        $self->reply_links->link_reply( $answer->{post_id}, $target );
    }
    catch ($error) {
        $self->_log( warn => "reply link failed: $error" );
    };

    return;
}

async sub _link_reply_p ( $self, $answer, $context ) {
    my ( $links, $target ) =
      ( $self->reply_links, $answer->{reply_to_post_id} );
    return if !$links || !$target || !$answer->{post_id};
    return $self->_link_reply($answer) if !$links->can('link_reply_p');
    try {
        await $links->link_reply_p( $answer->{post_id}, $target, $context );
    }
    catch ($error) {
        $self->_log( warn => "reply link failed: $error" );
    };

    return;
}

# ADR 0135: a held thread is published with the tags its author gave it. A
# write that fails leaves the thread as it is, as at creation: the thread is
# the content, the tags a hint.
sub _set_tags ( $self, $answer ) {
    my $tags = $answer->{tags} // q{};
    return
         if !$self->thread_tags
      || ( $answer->{kind} // q{} ) ne 'thread'
      || !length $tags
      || !$answer->{thread_id};
    try {
        $self->thread_tags->set_thread_tags( $answer->{thread_id}, $tags );
    }
    catch ($error) {
        $self->_log( warn => "thread tags failed: $error" );
    };

    return;
}

async sub _set_tags_p ( $self, $answer, $context ) {
    my $tags = $self->thread_tags;
    return $self->_set_tags($answer)
      if !$tags || !$tags->can('set_thread_tags_p');
    my $text = $answer->{tags} // q{};
    return
         if ( $answer->{kind} // q{} ) ne 'thread'
      || !length $text
      || !$answer->{thread_id};
    try {
        await $tags->set_thread_tags_p( $answer->{thread_id}, $text, $context );
    }
    catch ($error) {
        $self->_log( warn => "thread tags failed: $error" );
    };

    return;
}

# The author hears of the decision on what they can read: the post or
# thread published, or the thread a rejected reply was for. A rejected
# thread has no such place; its author finds the decision on their list
# of posts held for review.
sub _notify ( $self, $type, $answer ) {
    my $notification = $self->_notification( $type, $answer ) or return;
    try {
        $self->notifications->create_notification($notification);
    }
    catch ($error) {
        $self->_log( warn => "review notification failed: $error" );
    };

    return;
}

# _notify through the dispatcher's asynchronous twin when it has one.
async sub _notify_p ( $self, $type, $answer, $context ) {
    my $notification  = $self->_notification( $type, $answer ) or return;
    my $notifications = $self->notifications;
    try {
        if ( $notifications->can('create_notification_p') ) {
            await $notifications->create_notification_p( $notification,
                $context );
        }
        else { $notifications->create_notification($notification); }
    }
    catch ($error) {
        $self->_log( warn => "review notification failed: $error" );
    };

    return;
}

sub _notification ( $self, $type, $answer ) {
    return undef if !$self->notifications;
    my ( $source_type, $source_id ) =
      $type eq 'review_approved' && $answer->{kind} eq 'reply'
      ? ( post => $answer->{post_id} )
      : ( thread => $answer->{thread_id} );
    return undef if !$source_id;

    return {
        idempotency_key   => "review:$answer->{review_id}:$type",
        notification_type => $type,
        recipient_user_id => $answer->{author_user_id},
        source_type       => $source_type,
        source_id         => $source_id,
        payload           => {
            review_id => $answer->{review_id},
            kind      => $answer->{kind},
            thread_id => $answer->{thread_id},
            post_id   => $answer->{post_id},
            reason    => $answer->{reason} // q{},
        },
    };
}

sub _refused ($published) {
    return {
        ok     => 0,
        status => 'refused',
        error  => $published->{error} // $published->{status} // 'refused',
    };
}

sub _not_found {
    return { ok => 0, status => 'not_found', error => 'held post not found' };
}

sub _failed {
    return { ok => 0, status => 'failed', error => 'review decision failed' };
}

sub _log ( $self, $level, $message ) {
    return if !$self->logger;
    $self->logger->$level($message);

    return;
}

1;

__END__

=head1 NAME

GPForum::Service::Moderation::ReviewWorkflow - Staff approve or reject posts held for review.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $workflow = GPForum::Service::Moderation::ReviewWorkflow->new(
        store           => $review_store,
        posting         => $posting_workflow,
        viewer_resolver => $viewer_resolver,
        notifications   => $dispatcher,
    );
    my $answer = $workflow->approve(
        { review_id => $id, actor_user_id => $staff } );

=head1 DESCRIPTION

The decisions of ADR 0134. An approval publishes the held post as its
author's command, with the command id the author submitted, through the
posting workflow (which checks again that the author may still post
there), and records the decision under the entry's lock in the same
transaction: two staff approving at once publish it once, and a post that
can no longer be published is refused with nothing recorded. A rejection
records the staff's reason. The author may withdraw a post still pending.
The author is notified of an approval, and of a rejected reply.

=head1 SUBROUTINES/METHODS

=head2 approve

Publishes a pending post and records the approval. Answers C<ok>,
C<unchanged> (already approved), C<conflict> (decided otherwise),
C<refused> (it can no longer be published), C<not_found> or C<failed>. A
published reply is linked to the post it answers, a published thread given
the tags its author typed (ADR 0135).

=head2 approve_p

L</approve> as a promise, with an optional query context last: the held
post is taken under its lock, published through the posting workflow's
C<publish_reviewed_p> and the decision recorded, in one transaction on the
worker's pooled asynchronous connections; the reply link, the tags and the
author's notification follow it there.

=head2 reject

Records a rejection with an optional reason of at most 500 characters.

=head2 reject_p

L</reject> as a promise, with an optional query context last: the decision
is written on the worker's pooled asynchronous connections.

=head2 withdraw

The author takes back a pending post.

=head2 withdraw_p

L</withdraw> as a promise, with an optional query context last: the decision
is written on the worker's pooled asynchronous connections.

=head1 DIAGNOSTICS

A failure answers C<failed> and is logged; an approval that failed
publishes nothing.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Service::Moderation::ReviewStore>,
L<GPForum::Service::Forum::PostingWorkflow>,
L<GPForum::Service::Forum::ViewerResolver>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

A rejected thread has no readable place to notify its author about; the
decision is on the author's list of held posts.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
