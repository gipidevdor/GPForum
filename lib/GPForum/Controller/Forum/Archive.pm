# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Controller::Forum::Archive;

use Mojo::Base 'GPForum::Controller::Forum::Base', -signatures;
use v5.40;
use Const::Fast;
use GPForum::Infrastructure::Id;
use Mojo::JSON qw(to_json);

our $VERSION = '0.001';

const my $HTTP_NOT_FOUND => 404;

sub thread ($self) {
    return $self->_download( 'thread', $self->param('thread_id') );
}

sub category ($self) {
    return $self->_download( 'category', $self->param('category_id') );
}

sub _download ( $self, $kind, $id ) {
    return $self->render( text => 'Not found', status => $HTTP_NOT_FOUND )
      if !GPForum::Infrastructure::Id->is_uuid($id);
    return $self->_rate_limited if !$self->read_allowed('archive');
    my $file = $self->gp_archive->spool( $kind, $id, $self->gp_forum_viewer );
    return $self->render( text => 'Not found', status => $HTTP_NOT_FOUND )
      if !$file;
    $self->res->headers->content_type('application/mbox');
    $self->res->headers->content_disposition(
        qq{attachment; filename="gpforum-$kind-$id.mbox"});
    $self->res->headers->cache_control('private, no-store');
    $self->on( finish => sub { undef $file; } );
    return $self->reply->file( $file->filename );
}

sub signature ($self) {
    my $payload = $self->_signature_payload or return;
    return $self->render( json => $payload );
}

sub signature_page ($self) {
    my $payload = $self->_signature_payload or return;
    return $self->render(
        template      => 'forum/verification',
        post_id       => $payload->{post_id},
        envelope      => $payload->{envelope},
        envelope_json => to_json($payload)
    );
}

sub _signature_payload ($self) {
    my $id = $self->param('post_id');
    if ( !GPForum::Infrastructure::Id->is_uuid($id) ) {
        $self->render( text => 'Not found', status => $HTTP_NOT_FOUND );
        return undef;
    }
    if ( !$self->read_allowed('signature') ) {
        $self->_rate_limited;
        return undef;
    }
    my $row = $self->gp_archive->post( $id, $self->gp_forum_viewer );
    if ( !$row ) {
        $self->render( text => 'Not found', status => $HTTP_NOT_FOUND );
        return undef;
    }
    my %post = $row->get_columns;
    $self->res->headers->cache_control('private, no-store');
    return {
        post_id  => $id,
        envelope => $self->gp_archive->signature( \%post )
    };
}

sub signing_keys ($self) {
    return $self->render( json => $self->gp_archive->key_set );
}

1;
