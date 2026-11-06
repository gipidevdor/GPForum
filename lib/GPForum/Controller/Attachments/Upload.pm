# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Controller::Attachments::Upload;

use Mojo::Base 'GPForum::Controller::Attachments::Base', -signatures;
use v5.40;
use Const::Fast;
use GPForum::Infrastructure::Id;

our $VERSION = '0.001';
const my $HTTP_OK          => 200;
const my $HTTP_BAD_REQUEST => 400;
const my $PAGE_SIZE        => 50;
const my $EXCERPT_LENGTH   => 240;
const my %FAILURE_CODE => (
    invalid   => 400,
    conflict  => 409,
    not_found => 404,
    forbidden => 403,
    failed    => 503,
);

sub show ($self) {
    return $self->_form( undef, $HTTP_OK );
}

sub _form ( $self, $error, $status ) {
    my $actor = $self->current_user_id;
    if ( !$actor ) {
        my $path = $self->req->url->path;
        return $self->redirect_to(
            $self->url_for('login')->query( return_to => $path->to_string ) );
    }
    $self->res->headers->cache_control('private, no-store');
    my $id   = $self->param('post_id');
    my $post = $self->_owned_post( $id, $actor )  or return;
    my $page = $self->_upload_page( $id, $actor ) or return;
    return $self->render(
        template     => 'attachments/upload',
        post_id      => $id,
        post_excerpt => substr(
            $self->column( $post, 'body_source' ) // q{}, 0,
            $EXCERPT_LENGTH
        ),
        post_url => $self->url_for( 'thread',
            thread_id => $self->column( $post, 'thread_id' ) )
          ->query( post => $id )
          ->fragment( 'post-' . $id ),
        media_max_mib => $self->gp_config->media_max_mib,
        command_id    => $self->gp_id->uuid,
        error         => $error,
        status        => $status,
        %{$page},
    );
}

sub _owned_post ( $self, $id, $actor ) {
    if ( !GPForum::Infrastructure::Id->is_uuid($id) ) {
        $self->not_found('post not found');
        return undef;
    }
    my $post =
      $self->gp_post_reader->find_visible_post( $id, $self->gp_forum_viewer );
    if ( !$post || $self->column( $post, 'deleted_at' ) ) {
        $self->not_found('post not found');
        return undef;
    }
    if ( ( $self->column( $post, 'author_user_id' ) // q{} ) ne $actor ) {
        $self->_forbidden('post author required');
        return undef;
    }
    if ( !$self->gp_suspension_store->can_participate($actor)->{ok} ) {
        $self->_forbidden('user is suspended');
        return undef;
    }
    return $post;
}

sub _upload_page ( $self, $id, $actor ) {
    my $after = $self->param('after');
    if ( defined $after && !GPForum::Infrastructure::Id->is_uuid($after) ) {
        $self->render( text => 'Invalid cursor', status => $HTTP_BAD_REQUEST );
        return undef;
    }
    my $files =
      $self->gp_attachment_store->owned_uploads_for_post( $id, $actor, $after );
    my $more = @{$files} > $PAGE_SIZE ? pop @{$files} : undef;
    my $tail = @{$files}              ? $files->[-1]  : undef;
    my $next =
        $more && $tail
      ? $self->url_for( 'post_attachment_form', post_id => $id )
      ->query( after => $tail->{link_id} )
      : undef;
    for my $file ( @{$files} ) {
        $file->{delete_command_id} = $self->gp_id->uuid;
    }
    return { uploads => $files, next_page => $next };
}

sub upload_post ($self) {
    my $user_id = $self->write_user_id;
    if ( !$user_id ) {
        return;
    }

    my $result = $self->gp_attachment_workflow->upload_for_post(
        {
            actor_user_id    => $user_id,
            command_id       => $self->command_id_param,
            post_id          => $self->param('post_id'),
            upload           => $self->req->upload('attachment'),
            viewer           => $self->gp_forum_viewer,
            source_kind      => $self->param('source_kind'),
            source_url       => $self->param('source_url'),
            rights_confirmed => $self->param('rights_confirmed'),
        }
    );
    if (   !$result->{ok}
        && !$self->wants_json
        && ( $self->param('upload_form') // q{} ) eq '1' )
    {
        return $self->_form( $self->i18n('media.upload_refused'),
            $FAILURE_CODE{ $result->{status} // q{} }
              // $FAILURE_CODE{failed} );
    }
    return $self->upload_write_response($result);
}

sub delete_post ($self) {
    my $user_id = $self->write_user_id;
    if ( !$user_id ) {
        return;
    }

    my $result = $self->gp_attachment_workflow->delete_for_post(
        {
            actor_user_id => $user_id,
            attachment_id => $self->param('attachment_id'),
            command_id    => $self->command_id_param,
            post_id       => $self->param('post_id'),
            viewer        => $self->gp_forum_viewer,
        }
    );
    if ( !$self->wants_json && ( $self->param('upload_form') // q{} ) eq '1' ) {
        return $self->_form( $self->i18n('media.upload_refused'),
            $FAILURE_CODE{ $result->{status} // q{} } // $FAILURE_CODE{failed} )
          if !$result->{ok};
        $self->set_success_flash('forum.attachment_deleted');
        return $self->redirect_to( 'post_attachment_form',
            post_id => $self->param('post_id') );
    }
    return $self->delete_write_response($result);
}

1;

__END__

=head1 NAME

GPForum::Controller::Attachments::Upload - Post attachment writes.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    $routes->post('/p/:post_id/attachments')
      ->to('Attachments::Upload#upload_post');

=head1 DESCRIPTION

Accepts authenticated post attachment uploads and deletes through the
attachment workflow.

=head1 SUBROUTINES/METHODS

=head2 upload_post

Uploads and links an attachment to a visible post owned by the actor.
Requires C<command_id>.

=head2 show

Displays the private upload form for the signed-in author of a visible post.
It includes the configured size limit, supported formats and provenance fields.

=head2 delete_post

Soft-deletes an attachment linked to a visible post owned by the actor.
Requires C<command_id>.

=head1 DIAGNOSTICS

CSRF, auth, rate-limit, and validation failures use the shared attachment
helpers.

=head1 CONFIGURATION AND ENVIRONMENT

Uses the attachment workflow helper configured during application startup.

=head1 DEPENDENCIES

Uses L<GPForum::Controller::Attachments::Base>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Attachment downloads remain on the parent attachments controller.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
