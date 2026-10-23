# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Controller::Forum::Archive;

use Mojo::Base 'GPForum::Controller::Forum::Base', -signatures;
use v5.40;
use Const::Fast;
use GPForum::Infrastructure::Id;

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
    my $id = $self->param('post_id');
    return $self->render( text => 'Not found', status => $HTTP_NOT_FOUND )
      if !GPForum::Infrastructure::Id->is_uuid($id);
    return $self->_rate_limited if !$self->read_allowed('signature');
    my $row = $self->gp_archive->post( $id, $self->gp_forum_viewer );
    return $self->render( text => 'Not found', status => $HTTP_NOT_FOUND )
      if !$row;
    my %post = $row->get_columns;
    $self->res->headers->cache_control('private, no-store');
    return $self->render(
        json => {
            post_id  => $id,
            envelope => $self->gp_archive->signature( \%post )
        }
    );
}

sub signing_keys ($self) {
    return $self->render( json => $self->gp_archive->key_set );
}

1;
