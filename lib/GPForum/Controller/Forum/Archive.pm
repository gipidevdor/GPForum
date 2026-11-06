# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Controller::Forum::Archive;

use Mojo::Base 'GPForum::Controller::Forum::Base', -async_await;
use v5.40;
use Const::Fast;
use GPForum::Infrastructure::Id;
use Mojo::JSON qw(to_json);
use GPForum::Infrastructure::FileAsset;
use GPForum::Web::MediaResponse;

our $VERSION = '0.001';

const my $HTTP_NOT_FOUND => 404;

async sub thread ($self) {
    return (
        await $self->await_p(
            $self->_download( 'thread', $self->param('thread_id') )
        )
    );
}

async sub category ($self) {
    return (
        await $self->await_p(
            $self->_download( 'category', $self->param('category_id') )
        )
    );
}

async sub _download ( $self, $kind, $id ) {
    return $self->render( text => 'Not found', status => $HTTP_NOT_FOUND )
      if !GPForum::Infrastructure::Id->is_uuid($id);
    return $self->_rate_limited
      if !( await $self->await_p( $self->read_allowed('archive') ) );
    my $file = (
        await $self->call_p(
            $self->gp_archive, 'spool', $kind, $id, $self->gp_forum_viewer
        )
    );
    return $self->render( text => 'Not found', status => $HTTP_NOT_FOUND )
      if !$file;
    $self->res->headers->content_type('application/mbox');
    $self->res->headers->content_disposition(
        qq{attachment; filename="gpforum-$kind-$id.mbox"});
    $self->res->headers->cache_control('private, no-store');
    my $asset = GPForum::Infrastructure::FileAsset->from_descriptor( $file, 1 );
    return GPForum::Web::MediaResponse->new->render( $self, $asset,
        "$file->{inode}-$file->{size}-$file->{mtime}" );
}

async sub signature ($self) {
    my $payload = ( await $self->await_p( $self->_signature_payload ) )
      or return;
    return $self->render( json => $payload );
}

async sub signature_page ($self) {
    my $payload = ( await $self->await_p( $self->_signature_payload ) )
      or return;
    return $self->render(
        template      => 'forum/verification',
        post_id       => $payload->{post_id},
        envelope      => $payload->{envelope},
        envelope_json => to_json($payload)
    );
}

async sub _signature_payload ($self) {
    my $id = $self->param('post_id');
    if ( !GPForum::Infrastructure::Id->is_uuid($id) ) {
        $self->render( text => 'Not found', status => $HTTP_NOT_FOUND );
        return undef;
    }
    if ( !( await $self->await_p( $self->read_allowed('signature') ) ) ) {
        $self->_rate_limited;
        return undef;
    }
    my $row = (
        await $self->call_p(
            $self->gp_archive, 'post', $id, $self->gp_forum_viewer
        )
    );
    if ( !$row ) {
        $self->render( text => 'Not found', status => $HTTP_NOT_FOUND );
        return undef;
    }
    my %post = $row->get_columns;
    $self->res->headers->cache_control('private, no-store');
    return {
        post_id  => $id,
        envelope =>
          ( await $self->call_p( $self->gp_archive, 'signature', \%post ) )
    };
}

async sub signing_keys ($self) {
    return $self->render(
        json => ( await $self->call_p( $self->gp_archive, 'key_set' ) ) );
}

1;
