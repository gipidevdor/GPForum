# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Controller::Forum::Community;

use Const::Fast;
use Mojo::Base 'GPForum::Controller::Forum::Base', -signatures;
use v5.40;

our $VERSION = '0.001';

const my $HTTP_OK => 200;

sub feed ($self) {
    my $user_id = $self->_current_user_id;
    if ( !$user_id ) {
        return $self->_unauthorized;
    }

    my $page = $self->gp_feed_reader->list_page_for_user(
        $user_id,
        {
            limit  => $self->list_page_limit,
            after  => $self->param('after'),
            viewer => $self->gp_forum_viewer,
        }
    );

    my $payload = $self->gp_community_view_model->feed_page( page => $page );

    return $self->render_payload(
        {
            controller => $self,
            payload    => $payload,
            status     => $HTTP_OK,
            template   => 'forum/feed',
        }
    );
}

sub bookmarks ($self) {
    my $user_id = $self->_current_user_id;
    if ( !$user_id ) {
        return $self->_unauthorized;
    }

    my $folder =
      $self->gp_bookmark_folders->normalise( $self->param('folder') );
    my $page = $self->gp_bookmark_store->list_page_for_user(
        $user_id,
        {
            folder      => length( $folder // q{} ) ? $folder : undef,
            target_type => $self->forum_access->thread_target,
            limit       => $self->list_page_limit,
            after       => $self->param('after'),
            viewer      => $self->gp_forum_viewer,
        }
    );

    my $payload = $self->gp_community_view_model->bookmarks_page(
        folder  => $folder,
        folders => $self->gp_bookmark_folders->list_folders($user_id),
        page    => $page,
    );

    return $self->render_payload(
        {
            controller => $self,
            payload    => $payload,
            status     => $HTTP_OK,
            template   => 'forum/bookmarks',
        }
    );
}

sub create_thread_bookmark ($self) {
    my $user_id = $self->write_user_id('thread.bookmark');
    if ( !$user_id ) {
        return;
    }
    if ( !$self->visible_thread ) {
        return;
    }

    my $result = $self->gp_community_workflow->save_bookmark(
        {
            command_id  => $self->command_id_param,
            note        => $self->param('note'),
            target_id   => $self->param('thread_id'),
            target_type => $self->forum_access->thread_target,
            user_id     => $user_id,
        }
    );
    $self->_file_saved_bookmark( $result, $user_id );

    return $self->_community_write_response( 'bookmark',
        $self->forum_access->bookmarked_status, $result );
}

# The folder named with a save (ADR 0136) is set once the bookmark is
# stored; a field left out or empty leaves the bookmark where it is. A
# write that fails leaves the bookmark as it is: the folder is a hint.
sub _file_saved_bookmark ( $self, $result, $user_id ) {
    my $folder = $self->param('folder');
    return if !defined $folder || !length $folder;
    return if ( $result->{status} // 'ok' ) ne 'ok';
    my $bookmark_id = $self->_column( $result->{stored}, 'bookmark_id' );
    return if !$bookmark_id;
    try {
        $self->gp_bookmark_folders->file_bookmark( $bookmark_id, $user_id,
            $folder );
    }
    catch ($error) {
        $self->app->log->warn("bookmark folder failed: $error");
    };
    return;
}

# Moves one of the member's bookmarks to a folder, or out of its folder,
# from the bookmarks page; the page then shows that folder.
sub file_bookmark ($self) {
    my $user_id = $self->write_user_id('thread.bookmark.file');
    if ( !$user_id ) {
        return;
    }

    my $filed =
      $self->gp_bookmark_folders->file_bookmark( $self->param('bookmark_id'),
        $user_id, $self->param('folder') );
    if ( !$filed ) {
        return $self->_not_found('bookmark not found');
    }
    my $status = $self->forum_access->bookmark_filed_status;
    if ( $self->_wants_json ) {
        return $self->render(
            json => $self->gp_community_view_model->bookmark_response(
                $status, $filed
            ),
            status => $HTTP_OK,
        );
    }
    $self->set_success_flash( $self->forum_access->write_flash_key($status) );
    my $folder = $filed->{folder} // q{};

    return $self->redirect_to( $self->url_for('bookmarks')
          ->query( length $folder ? ( folder => $folder ) : () ) );
}

sub remove_thread_bookmark ($self) {
    my $user_id = $self->write_user_id('thread.bookmark.remove');
    if ( !$user_id ) {
        return;
    }
    if ( !$self->visible_thread ) {
        return;
    }

    return $self->_community_write_response(
        'bookmark',
        $self->forum_access->bookmark_removed_status,
        $self->gp_community_workflow->remove_bookmark(
            {
                command_id  => $self->command_id_param,
                target_id   => $self->param('thread_id'),
                target_type => $self->forum_access->thread_target,
                user_id     => $user_id,
            }
        ),
    );
}

sub subscribe_thread ($self) {
    my $user_id = $self->write_user_id('thread.subscribe');
    if ( !$user_id ) {
        return;
    }
    if ( !$self->visible_thread ) {
        return;
    }

    return $self->_community_write_response(
        'subscription',
        $self->forum_access->subscribed_status,
        $self->gp_community_workflow->save_subscription(
            {
                command_id  => $self->command_id_param,
                preference  => $self->param('preference') || 'all',
                target_id   => $self->param('thread_id'),
                target_type => $self->forum_access->thread_target,
                user_id     => $user_id,
            }
        ),
    );
}

sub mute_thread_subscription ($self) {
    my $user_id = $self->write_user_id('thread.subscription.mute');
    if ( !$user_id ) {
        return;
    }
    if ( !$self->visible_thread ) {
        return;
    }

    return $self->_community_write_response(
        'subscription',
        $self->forum_access->subscription_muted_status,
        $self->gp_community_workflow->mute_subscription(
            {
                command_id  => $self->command_id_param,
                target_id   => $self->param('thread_id'),
                target_type => $self->forum_access->thread_target,
                user_id     => $user_id,
            }
        ),
    );
}

sub unsubscribe_thread ($self) {
    my $user_id = $self->write_user_id('thread.unsubscribe');
    if ( !$user_id ) {
        return;
    }
    if ( !$self->visible_thread ) {
        return;
    }

    return $self->_community_write_response(
        'subscription',
        $self->forum_access->unsubscribed_status,
        $self->gp_community_workflow->revoke_subscription(
            {
                command_id  => $self->command_id_param,
                target_id   => $self->param('thread_id'),
                target_type => $self->forum_access->thread_target,
                user_id     => $user_id,
            }
        ),
    );
}

# A refusal the workflow names answers with its error page; any other status
# (none, or ok) is the bookmark or subscription response.
sub like_post ($self) {
    return $self->_like_write( 'post.like', 'like_post',
        $self->forum_access->post_liked_status );
}

sub unlike_post ($self) {
    return $self->_like_write( 'post.unlike', 'unlike_post',
        $self->forum_access->post_unliked_status );
}

# A like goes to a post the member may read, and not to their own; the
# function refuses both again under its lock (ADR 0129).
sub _like_write ( $self, $action, $method, $status ) {
    my $user_id = $self->write_user_id($action);
    if ( !$user_id ) {
        return;
    }
    my $post = $self->_visible_post;
    if ( !$post ) {
        return;
    }
    if ( $method eq 'like_post'
        && ( $self->_column( $post, 'author_user_id' ) // q{} ) eq $user_id )
    {
        return $self->_bad_request(
            { post_id => 'a post is not liked by its author' } );
    }

    return $self->_community_write_response(
        'like', $status,
        $self->gp_community_workflow->$method(
            {
                command_id => $self->command_id_param,
                post_id    => $self->param('post_id'),
                user_id    => $user_id,
            }
        ),
    );
}

# The post of the request when the viewer may read it and its thread, else
# a 404 answered and nothing.
sub _visible_post ($self) {
    my $post =
      $self->gp_post_reader->find_visible_post( $self->param('post_id'),
        $self->gp_forum_viewer );
    if (
        !$post
        || !$self->gp_thread_detail_reader->find_thread(
            $self->_column( $post, 'thread_id' ),
            $self->gp_forum_viewer
        )
      )
    {
        $self->_not_found('post not found');
        return undef;
    }

    return $post;
}

sub _community_write_response ( $self, $kind, $status, $result ) {
    my $mapped = $result->{status} // 'ok';
    if ( $mapped eq 'failed' ) {
        return $self->_service_unavailable;
    }
    if ( $mapped eq 'not_found' ) {
        return $self->_not_found( $result->{error} );
    }
    if ( $mapped eq 'invalid' ) {
        return $self->_bad_request( $result->{errors} );
    }
    if ( $mapped eq 'conflict' ) {
        return $self->_conflict( $result->{error} );
    }
    if ( $kind eq 'bookmark' ) {
        return $self->bookmark_action_response( $status, $result->{stored} );
    }
    if ( $kind eq 'like' ) {
        return $self->like_action_response( $status, $result->{stored} );
    }

    return $self->subscription_action_response( $status, $result->{stored} );
}

sub report_thread ($self) {
    my $user_id = $self->write_user_id('report.create');
    if ( !$user_id ) {
        return;
    }

    my $thread = $self->visible_thread;
    if ( !$thread ) {
        return;
    }

    my $thread_id = $self->_column( $thread, 'thread_id' );
    return $self->report_response(
        $self->create_report(
            {
                reporter_user_id => $user_id,
                target_type      => $self->forum_access->thread_target,
                target_id        => $thread_id,
            }
        ),
        $thread_id,
        undef,
    );
}

sub report_post ($self) {
    my $user_id = $self->write_user_id('report.create');
    if ( !$user_id ) {
        return;
    }

    my $post =
      $self->gp_post_reader->find_visible_post( $self->param('post_id'),
        $self->gp_forum_viewer );
    if ( !$post ) {
        return $self->_not_found('post not found');
    }

    my $thread_id = $self->_column( $post, 'thread_id' );
    if (
        !$self->gp_thread_detail_reader->find_thread(
            $thread_id, $self->gp_forum_viewer
        )
      )
    {
        return $self->_not_found('post not found');
    }

    return $self->report_response(
        $self->create_report(
            {
                reporter_user_id => $user_id,
                target_type      => $self->forum_access->post_target,
                target_id        => $self->_column( $post, 'post_id' ),
            }
        ),
        $thread_id,
        $self->_column( $post, 'post_id' ),
    );
}

sub report_profile ($self) {
    my $user_id = $self->write_user_id('report.create');
    if ( !$user_id ) {
        return;
    }

    my $username = $self->param('username');
    my $profile  = $self->gp_profile_reader->public_profile(
        $username,
        {
            limit => 1,
        }
    );
    if ( !$profile->{ok} ) {
        return $self->_not_found('profile not found');
    }

    return $self->profilereport_response(
        $self->create_report(
            {
                reporter_user_id => $user_id,
                target_type      => $self->forum_access->user_target,
                target_id        => $profile->{profile}{user}{user_id},
            }
        ),
        $profile->{profile}{user}{username} || $username,
    );
}

1;

__END__

=head1 NAME

GPForum::Controller::Forum::Community - Feed, bookmarks, subscriptions, reports.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    $routes->get('/feed')->to('Forum::Community#feed');

=head1 DESCRIPTION

Handles authenticated community surfaces around visible threads and profiles.
Bookmark and subscription writes go through
L<GPForum::Service::Community::Workflow> and require HTTP C<command_id>.
Bookmark and report target types and write-success statuses live on
L<GPForum::Web::ForumAccess>.

=head1 SUBROUTINES/METHODS

=head2 feed

Renders the signed-in member feed.

=head2 bookmarks

Renders the signed-in bookmark list.

=head2 create_thread_bookmark

Saves a thread bookmark.

=head2 remove_thread_bookmark

Removes a thread bookmark.

=head2 file_bookmark

Moves one of the member's bookmarks to the folder given, or out of its
folder when the field is empty (ADR 0136); 404 when the bookmark is not
the member's or the folder is too long.

=head2 subscribe_thread

Subscribes the viewer to a visible thread.

=head2 mute_thread_subscription

Mutes an existing thread subscription.

=head2 unsubscribe_thread

Revokes an existing thread subscription.

=head2 like_post

Likes the post for the signed-in member (C<POST /p/:post_id/like>).

=head2 unlike_post

Takes the member's like back (C<POST /p/:post_id/like/remove>).

=head2 report_thread

Creates a thread report.

=head2 report_post

Creates a post report.

=head2 report_profile

Creates a profile report.

=head1 DIAGNOSTICS

Missing threads, bookmarks, and subscriptions render as not found.

=head1 CONFIGURATION AND ENVIRONMENT

Uses the community workflow and stores configured during application startup.

=head1 DEPENDENCIES

Uses L<GPForum::Controller::Forum::Base>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Reports require a reason and are rate-limited separately from other writes.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause
license.

=cut
