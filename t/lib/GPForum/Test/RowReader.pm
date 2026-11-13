# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::RowReader;

use v5.40;

our $VERSION = '0.001';

# The workflow's readers over one post and one thread row, and the rows a
# post's context is read from (GPForum::Test::PostingFunctions). find_thread
# answers as ThreadDetailReader does for the writer, written out here rather
# than asked of GPForum::Domain::Thread: only visible and locked threads, and
# a deleted one to its author only.
sub new ( $class, %row ) {
    return bless {%row}, $class;
}

sub find_post ( $self, $post_id ) {
    return $self->{post} ? { %{ $self->{post} } } : undef;
}

sub find_thread ( $self, $thread_id, $viewer ) {
    my $thread = $self->{thread};
    return undef if !$thread;

    my $state = $thread->{moderation_state} // q{};
    return undef if $state ne 'visible' && $state ne 'locked';
    return undef
      if defined $thread->{deleted_at}
      && ( $thread->{author_user_id} // q{} ) ne $self->{writer};

    return { %{$thread} };
}

# The thread's row as stored, whoever reads it: the post context's thread.
sub find_thread_row ( $self, $thread_id ) {
    return $self->{thread} ? { %{ $self->{thread} } } : undef;
}

# A thread head already read, as the writer may read it: find_thread's
# answer.
sub visible_thread_row ( $self, $row, $viewer = undef ) {
    return $row ? $self->find_thread( undef, $viewer ) : undef;
}

1;
