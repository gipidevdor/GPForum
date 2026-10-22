# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::ViewModel::Community::Presenter;

use Mojo::Base 'GPForum::ViewModel::Base', -signatures;
use v5.40;

use GPForum::ViewModel::Notifications::Presenter;

our $VERSION = '0.001';

has notifications_presenter =>
  sub { return GPForum::ViewModel::Notifications::Presenter->new; };

sub bookmarks_page ( $self, %input ) {
    my $page = $input{page} || {};

    return {
        bookmarks => [ map { $self->bookmark($_) } @{ $page->{items} || [] } ],
        folder    => $input{folder} // q{},
        folders   => [
            map { $self->_folder($_) }
              @{ ref $input{folders} eq 'ARRAY' ? $input{folders} : [] }
        ],
        next_cursor => $page->{next_cursor},
    };
}

# A folder of the member's with how many bookmarks it holds (ADR 0136).
sub _folder ( $, $row ) {
    my $hash = ref $row eq 'HASH' ? $row : {};

    return {
        bookmark_count => $hash->{bookmark_count} // 0,
        folder         => $hash->{folder}         // q{},
    };
}

sub feed_page ( $self, %input ) {
    my $page = $input{page} || {};

    return {
        feed_items =>
          [ map { $self->feed_item($_) } @{ $page->{items} || [] } ],
        next_cursor => $page->{next_cursor},
    };
}

sub bookmark_response ( $self, $status, $bookmark ) {
    return {
        bookmark => $bookmark,
        status   => $status,
    };
}

sub like_response ( $self, $status, $like ) {
    return {
        like   => $like,
        status => $status,
    };
}

sub reaction_response ( $self, $status, $reaction ) {
    return {
        reaction => $reaction,
        status   => $status,
    };
}

sub subscription_response ( $self, $status, $subscription ) {
    return {
        status       => $status,
        subscription => $subscription,
    };
}

sub notifications_page ( $self, %input ) {
    return $self->notifications_presenter->notifications_page(%input);
}

sub mentions_page ( $self, %input ) {
    return $self->notifications_presenter->mentions_page(%input);
}

sub bookmark ( $self, $row ) {
    return {
        bookmark_id  => $self->column( $row, 'bookmark_id' ),
        created_at   => $self->column( $row, 'created_at' ),
        folder       => $self->loaded_column( $row, 'folder' ),
        note         => $self->column( $row, 'note' ),
        target_id    => $self->column( $row, 'target_id' ),
        thread_id    => $self->loaded_column( $row, 'source_thread_id' ),
        thread_title => $self->loaded_column( $row, 'source_thread_title' ),
        target_type  => $self->column( $row, 'target_type' ),
    };
}

sub feed_item ( $self, $row ) {
    return {
        created_at   => $self->column( $row, 'created_at' ),
        item_id      => $self->column( $row, 'item_id' ),
        thread_id    => $self->loaded_column( $row, 'source_thread_id' ),
        thread_title => $self->loaded_column( $row, 'source_thread_title' ),
        item_type          => $self->column( $row, 'item_type' ),
        permission_version => $self->column( $row, 'permission_version' ),
        rank_score         => $self->column( $row, 'rank_score' ),
        user_id            => $self->column( $row, 'user_id' ),
        visibility_version => $self->column( $row, 'visibility_version' ),
    };
}

sub notification ( $self, $row, %input ) {
    return $self->notifications_presenter->notification( $row, %input );
}

sub mention ( $self, $row, %input ) {
    return $self->notifications_presenter->mention( $row, %input );
}

1;
