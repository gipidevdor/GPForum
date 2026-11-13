# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::WorkflowStore;

use Mojo::Base -base, -signatures;
use v5.40;

our $VERSION = '0.001';

# The store steps of the posting functions (the sink of
# GPForum::Test::PostingFunctions): each write counted, and answered with
# its row, refused with `refuse`, or dying with `fail`; `commands` keeps
# the command each write was handed, in order.
has calls    => 0;
has commands => sub { return []; };
has 'fail';
has 'refuse';

sub create_post ( $self, $command ) {
    return $self->_post( $command, $command->{post}{author_user_id} );
}

sub edit_post ( $self, $command ) {
    return $self->_post( $command, $command->{post}{editor_user_id} );
}

sub delete_post ( $self, $command ) {
    return $self->_post( $command, $command->{post}{deleted_by} );
}

sub restore_post ( $self, $command ) {
    return $self->_post( $command, $command->{post}{restored_by} );
}

sub create_thread ( $self, $command ) {
    return $self->_written(
        'thread', $command,
        {
            post   => { author_user_id => 'user-1', post_id => 'post-1' },
            thread => { thread_id      => 'thread-1' },
        }
    );
}

sub edit_thread ( $self, $command ) {
    return $self->_written(
        'thread', $command,
        {
            thread => {
                slug      => $command->{thread}{slug},
                thread_id => $command->{thread}{thread_id},
                title     => $command->{thread}{title},
            },
        }
    );
}

sub delete_thread ( $self, $command ) {
    return $self->_placed($command);
}

sub restore_thread ( $self, $command ) {
    return $self->_placed($command);
}

sub move_thread ( $self, $command ) {
    return $self->_placed($command);
}

sub _post ( $self, $command, $author_user_id ) {
    return $self->_written(
        'post', $command,
        {
            post => {
                author_user_id => $author_user_id,
                post_id        => $command->{post}{post_id},
                thread_id      => $command->{post}{thread_id},
            },
        }
    );
}

sub _placed ( $self, $command ) {
    return $self->_written(
        'thread', $command,
        {
            thread => {
                category_id => $command->{thread}{category_id},
                thread_id   => $command->{thread}{thread_id},
            },
        }
    );
}

sub _written ( $self, $noun, $command, $rows ) {
    $self->calls( $self->calls + 1 );
    push @{ $self->commands }, $command;
    if ( $self->fail ) {
        die "$noun store failed\n";
    }
    return { ok => 0, error => $self->refuse } if $self->refuse;

    return { ok => 1, %{$rows} };
}

1;
