# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Moderation::ReviewWorkflow;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -signatures;
use v5.40;

use GPForum::Infrastructure::Id;
use GPForum::Infrastructure::Row;
use GPForum::X::Conflict;

our $VERSION = '0.001';

# ADR 0134: the command each kind of held post is published by.
const my %COMMAND  => ( thread => 'thread.create', reply => 'reply.create' );
const my $APPROVED => 'approved';
const my $REJECTED => 'rejected';

__PACKAGE__->requires(qw(store posting viewer_resolver));
has notifications => undef;    # optional: without it nobody is notified
has reply_links   => undef;    # optional: without it a reply is not linked
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
                return _settled( $held->{status}, $APPROVED, $held )
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
        $self->_notify( 'review_approved', $answer );
    }

    return $answer;
}

# Rejects a pending post, with an optional reason the author reads.
sub reject ( $self, $input ) {
    my $reason = _trim( $input->{reason} );
    return { ok => 0, status => 'invalid', field => 'reason' }
      if length $reason > $self->store->maximum_reason;

    my $answer = $self->_decide(
        {
            review_id     => $input->{review_id},
            status        => $REJECTED,
            actor_user_id => $input->{actor_user_id},
            reason        => $reason,
        }
    );
    if ( $answer->{ok} && $answer->{status} eq 'ok' ) {
        $answer->{reason} = $reason;
        $self->_notify( 'review_rejected', $answer );
    }

    return $answer;
}

# The author takes back a post still pending.
sub withdraw ( $self, $input ) {
    return $self->_decide(
        {
            review_id     => $input->{review_id},
            status        => 'withdrawn',
            actor_user_id => $input->{author_user_id},
        }
    );
}

sub _publish ( $self, $held ) {
    my $kind   = $held->{kind} // q{};
    my $viewer = $self->viewer_resolver->resolve( $held->{author_user_id} );

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

    return $self->posting->publish_reviewed(
        exists $COMMAND{$kind} ? $COMMAND{$kind} : q{},
        { %common, %where } );
}

sub _approved ( $self, $input, $held, $published ) {
    my $stored = $published->{stored} // {};
    my $post_id =
      GPForum::Infrastructure::Row->column( $stored->{post}, 'post_id' );
    my $thread_id =
      GPForum::Infrastructure::Row->column( $stored->{thread}, 'thread_id' )
      // GPForum::Infrastructure::Row->column( $stored->{post}, 'thread_id' )
      // $held->{thread_id};
    my $decided = $self->store->decide(
        {
            review_id     => $held->{review_id},
            status        => $APPROVED,
            actor_user_id => $input->{actor_user_id},
            post_id       => $post_id,
        }
    );
    my $status = $decided->{status} // q{};
    if ( $status ne 'ok' ) {
        GPForum::X::Conflict->throw(
            message => "the approval was not recorded: $status" );
    }

    return {
        ok               => 1,
        status           => 'ok',
        review_status    => $APPROVED,
        review_id        => $held->{review_id},
        author_user_id   => $held->{author_user_id},
        kind             => $held->{kind},
        thread_id        => $thread_id,
        post_id          => $post_id,
        reply_to_post_id => $held->{reply_to_post_id},
        stored           => $stored,
    };
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
    my $status = $row->{status} // 'not_found';
    return _not_found() if $status eq 'not_found';
    return { ok => 0, status => 'invalid', field => 'status' }
      if $status eq 'invalid';
    return _settled( $row->{review_status}, $input->{status}, $row )
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
# one a conflict.
sub _settled ( $current, $wanted, $row ) {
    return {
        ok            => 1,
        status        => 'unchanged',
        review_status => $current,
        review_id     => $row->{review_id},
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

# The author hears of the decision on what they can read: the post or
# thread published, or the thread a rejected reply was for. A rejected
# thread has no such place; its author finds the decision on their list
# of posts held for review.
sub _notify ( $self, $type, $answer ) {
    return if !$self->notifications;
    my ( $source_type, $source_id ) =
      $type eq 'review_approved' && $answer->{kind} eq 'reply'
      ? ( post => $answer->{post_id} )
      : ( thread => $answer->{thread_id} );
    return if !$source_id;

    try {
        $self->notifications->create_notification(
            {
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
            }
        );
    }
    catch ($error) {
        $self->_log( warn => "review notification failed: $error" );
    };

    return;
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

sub _trim ($value) {
    my $text = $value // q{};
    $text =~ s/\A\s+|\s+\z//gmsx;

    return $text;
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
C<refused> (it can no longer be published), C<not_found> or C<failed>.

=head2 reject

Records a rejection with an optional reason of at most 500 characters.

=head2 withdraw

The author takes back a pending post.

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

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause
license.

=cut
