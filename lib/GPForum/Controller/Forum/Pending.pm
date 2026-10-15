# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Controller::Forum::Pending;

use Const::Fast;
use Mojo::Base 'GPForum::Controller::Forum::Base', -signatures;
use v5.40;

our $VERSION = '0.001';

const my $HTTP_OK => 200;

# ADR 0134: the signed-in member's posts held for review -- pending, and
# those decided in the last 30 days -- only ever their own.
sub list ($self) {
    $self->res->headers->cache_control('private, no-store');
    my $user_id = $self->_current_user_id;
    return $self->_unauthorized if !$user_id;
    return                      if !$self->read_allowed('review.read');

    my $rows;
    try {
        $rows = $self->gp_review_store->mine($user_id);
    }
    catch ($error) {
        $self->app->log->error("held posts failed: $error");
        return $self->_service_unavailable;
    };
    my @held = map { $self->_held_row($_) } @{$rows};
    return $self->render(
        json   => { held_posts => \@held },
        status => $HTTP_OK
    ) if $self->_wants_json;

    return $self->render(
        template   => 'forum/pending',
        held_posts => \@held,
        status     => $HTTP_OK,
    );
}

# The author takes back a post still pending.
sub withdraw ($self) {
    $self->res->headers->cache_control('private, no-store');
    my $user_id = $self->write_user_id('review.withdraw');
    return if !$user_id;

    my $answer = $self->gp_review_workflow->withdraw(
        {
            review_id      => $self->param('review_id'),
            author_user_id => $user_id,
        }
    );
    my $status = $answer->{status} // 'failed';
    return $self->_service_unavailable              if $status eq 'failed';
    return $self->_not_found('held post not found') if $status eq 'not_found';
    return $self->_conflict('held post already decided')
      if $status eq 'conflict';
    return $self->render( json => $answer, status => $HTTP_OK )
      if $self->_wants_json;

    $self->flash( success => $self->i18n('forum.review_withdrawn') );
    return $self->redirect_to('pending_posts');
}

sub _held_row ( $self, $row ) {
    my %held = %{$row};
    $held{ui} = { heading_id => "held-$row->{review_id}-heading" };
    if ( $row->{post_id} && $row->{thread_id} ) {
        $held{published_url} =
          $self->url_for( 'thread', thread_id => $row->{thread_id} )
          ->fragment("post-$row->{post_id}")
          ->to_string;
    }
    if ( $row->{thread_id} ) {
        $held{thread_url} =
          $self->url_for( 'thread', thread_id => $row->{thread_id} )->to_string;
    }
    if ( ( $row->{status} // q{} ) eq 'pending' ) {
        $held{withdraw_url} =
          $self->url_for( 'pending_post_withdraw',
            review_id => $row->{review_id} )->to_string;
    }

    return \%held;
}

1;

__END__

=head1 NAME

GPForum::Controller::Forum::Pending - A member's posts held for review.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    $routes->get('/pending')->to('Forum::Pending#list');
    $routes->post('/pending/:review_id/withdraw')
      ->to('Forum::Pending#withdraw');

=head1 DESCRIPTION

The author's side of ADR 0134. A new member's post held for review is
on this page, as the author wrote it, until staff decide it: pending,
then approved (with a link to it) or rejected (with the reason staff
gave). Nobody else sees it here. A pending post can be withdrawn.

=head1 SUBROUTINES/METHODS

=head2 list

The signed-in member's held posts, as a page or JSON.

=head2 withdraw

Withdraws one of the member's pending posts (CSRF, rate limited).

=head1 DIAGNOSTICS

Answers 401 without a member, 404 for a post that is not the member's
or not pending any more, 409 when it was already decided, and 503 when
the queue cannot be read or written.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Service::Moderation::ReviewStore>,
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
