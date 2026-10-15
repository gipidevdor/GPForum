# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Controller::Moderation::Review;

use Const::Fast;
use Mojo::Base 'GPForum::Controller::Moderation::Base', -signatures;
use v5.40;

use GPForum::Web::Guard;

our $VERSION = '0.001';

const my $HTTP_OK       => 200;
const my $HTTP_CONFLICT => 409;
const my $QUEUE         => 'moderation_review';

# ADR 0134: deciding a held post needs the global thread.moderate binding,
# the one that publishes and hides content everywhere; reading the queue
# needs report.view_queue, as the report queue does.
const my $DECIDE_RESOURCE => 'thread';
const my $DECIDE_ACTION   => 'moderate';
const my %FLASH => (
    approved  => 'moderation.review_approved',
    rejected  => 'moderation.review_rejected',
    unchanged => 'moderation.review_unchanged',
);

sub queue ($self) {
    my $user_id =
      $self->authorized_user_id( $self->moderation_access->view_queue_action );
    return if !$user_id;

    my $rows;
    try {
        $rows = $self->gp_review_store->queue( $self->queue_limit );
    }
    catch ($error) {
        $self->app->log->error("moderation review queue failed: $error");
        return $self->system_failure;
    };
    $self->res->headers->cache_control('private, no-store');
    my @held  = map { $self->_held_row($_) } @{$rows};
    my $total = @{$rows} ? $rows->[0]{pending_total} : 0;
    return $self->render(
        json   => { held_posts => \@held, pending_total => 0 + $total },
        status => $HTTP_OK,
    ) if $self->_wants_json;

    return $self->render(
        template      => 'moderation/review',
        held_posts    => \@held,
        pending_total => $total,
        status        => $HTTP_OK,
    );
}

sub approve ($self) {
    my $user_id =
      $self->authorized_write_user_id( $DECIDE_RESOURCE, $DECIDE_ACTION );
    return if !$user_id;

    return $self->_decided(
        'approved',
        $self->gp_review_workflow->approve(
            {
                review_id     => $self->param('review_id'),
                actor_user_id => $user_id,
            }
        )
    );
}

sub reject ($self) {
    my $user_id =
      $self->authorized_write_user_id( $DECIDE_RESOURCE, $DECIDE_ACTION );
    return if !$user_id;

    return $self->_decided(
        'rejected',
        $self->gp_review_workflow->reject(
            {
                review_id     => $self->param('review_id'),
                actor_user_id => $user_id,
                reason        => $self->param('reason'),
            }
        )
    );
}

sub _decided ( $self, $decision, $answer ) {
    my $status = $answer->{status} // 'failed';
    my $guard  = GPForum::Web::Guard->new;
    return $self->system_failure                 if $status eq 'failed';
    return $self->_not_found( $answer->{error} ) if $status eq 'not_found';
    return $guard->bad_request(
        $self,
        $self->moderation_access->invalid_request(
            { $answer->{field} // 'reason' => 'reason is too long' }
        )
    ) if $status eq 'invalid';
    if ( $status eq 'conflict' || $status eq 'refused' ) {
        return $self->render(
            json => {
                ok     => 0,
                status => $status,
                error  => $answer->{error},
            },
            status => $HTTP_CONFLICT,
        ) if $self->_wants_json;
        $self->flash(
            error => $self->i18n(
                $status eq 'refused'
                ? 'moderation.review_refused'
                : 'moderation.review_conflict'
            )
        );
        return $self->redirect_to($QUEUE);
    }

    return $self->render(
        json => {
            ok            => 1,
            status        => $status,
            review_id     => $answer->{review_id},
            review_status => $answer->{review_status},
            post_id       => $answer->{post_id},
            thread_id     => $answer->{thread_id},
        },
        status => $HTTP_OK,
    ) if $self->_wants_json;

    $self->flash( success =>
          $self->i18n( $FLASH{ $status eq 'ok' ? $decision : $status } ) );
    return $self->redirect_to($QUEUE);
}

sub _held_row ( $self, $row ) {
    my %held = %{$row};
    my $id   = $row->{review_id};
    $held{ui} = {
        heading_id => "review-$id-heading",
        reason_id  => "review-$id-reason",
    };
    if ( $row->{thread_id} ) {
        $held{thread_url} =
          $self->url_for( 'thread', thread_id => $row->{thread_id} )->to_string;
    }
    $held{approve_url} =
      $self->url_for( 'moderation_review_approve', review_id => $id )
      ->to_string;
    $held{reject_url} =
      $self->url_for( 'moderation_review_reject', review_id => $id )->to_string;

    return \%held;
}

1;

__END__

=head1 NAME

GPForum::Controller::Moderation::Review - The first-post review queue.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    $routes->get('/moderation/review')->to('Moderation::Review#queue');
    $routes->post('/moderation/review/:review_id/approve')
      ->to('Moderation::Review#approve');

=head1 DESCRIPTION

The staff side of ADR 0134: the posts held for review, oldest first, as
their authors wrote them, with why each is held, and a form to approve
(publish) or reject (with an optional reason) each one. The queue needs
C<report.view_queue>; a decision needs the global C<thread.moderate>
binding, a CSRF token and the moderation write rate limit. The forms
work without JavaScript and answer with a redirect and a notice, or JSON
when asked.

=head1 SUBROUTINES/METHODS

=head2 queue

The pending posts, as a page or JSON.

=head2 approve

Publishes a held post as its author's, and records the approval.

=head2 reject

Rejects a held post, with an optional reason the author reads.

=head1 DIAGNOSTICS

A post decided otherwise, or one that can no longer be published (its
thread locked or gone, its author suspended), answers 409, or a notice on
the queue; a missing one 404; a failure 503.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Service::Moderation::ReviewWorkflow>.

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
