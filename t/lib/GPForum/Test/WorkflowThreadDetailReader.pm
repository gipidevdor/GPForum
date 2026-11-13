# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::WorkflowThreadDetailReader;

use Mojo::Base -base, -signatures;
use v5.40;

our $VERSION = '0.001';

# The posting workflow's readers over one thread and one post: the thread
# as the author reads it, and the rows the post's context is read from
# (GPForum::Test::PostingFunctions).
has 'post';      # optional: no post found
has 'thread';    # optional: no thread found

sub find_thread ( $self, @ ) {
    return $self->thread;
}

sub find_thread_row ( $self, @ ) {
    return $self->thread;
}

sub find_post ( $self, @ ) {
    return $self->post;
}

# A thread head already read, as the author reads it: this reader's thread.
sub visible_thread_row ( $self, $row, @ ) {
    return $row ? $self->thread : undef;
}

1;
