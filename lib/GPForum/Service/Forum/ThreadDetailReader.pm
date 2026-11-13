# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Forum::ThreadDetailReader;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -async_await;
use v5.40;

use GPForum::Infrastructure::ResultRow::Thread;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Service::Forum::Viewer;
use GPForum::Service::Forum::Visibility;

use GPForum::Service::Forum::PostReader;
use GPForum::Service::Forum::ThreadPageSnapshot;
use GPForum::Service::Forum::PageWindow;
use GPForum::Infrastructure::Id;
use GPForum::X::Unavailable;

our $VERSION = '0.001';

const my $DEFAULT_POST_LIMIT => 25;

__PACKAGE__->requires('schema');

has post_reader => sub {
    my ($self) = @_;

    return GPForum::Service::Forum::PostReader->new( schema => $self->schema );
};

# ADR 0126: the row is api.forum_thread_page_head's.
has functions => \&GPForum::Infrastructure::SqlFunction::for_service;

# Each read is written once, as its promise method (ADR 0177); the post
# reader it awaits blocks with it.
GPForum::Infrastructure::SqlFunction->blocking_twins(
    qw(find_thread find_thread_row thread_page));
GPForum::Infrastructure::SqlFunction->blocking_parts('post_reader');

# The thread, if the viewer can read it (ADR 0102): its space, its category
# and the thread itself, an author reading their own non-public or deleted
# thread. $viewer is a Viewer; none reads as anonymous.
async sub find_thread_p ( $self, $thread_id, $viewer = undef, $context = undef )
{
    return $self->visible_thread_row(
        await $self->find_thread_row_p( $thread_id, $context ), $viewer );
}

# The thread's row, whatever the viewer may read.
async sub find_thread_row_p ( $self, $thread_id, $context = undef ) {
    return undef if !defined $thread_id || !length $thread_id;

    return GPForum::Infrastructure::ResultRow::Thread->from(
        await $self->_functions->row_p(
            @{ $self->thread_row_call($thread_id) }, $context
        )
    );
}

# Apply the reader's visibility rules to an already loaded head. A combined
# post preflight can use its head without querying the database a second time.
sub visible_thread_row ( $self, $row, $viewer = undef ) {
    return undef
      if !_thread_is_visible( $row,
        GPForum::Service::Forum::Viewer->from($viewer) );

    return $row;
}

# The call find_thread_row_p makes: the function's catalogue name and its
# parameters. Public so the query-plan evidence explains what runs.
sub thread_row_call ( $self, $thread_id ) {
    return [ 'forum_thread_page_head', { thread_id => $thread_id } ];
}

# A page of the thread: its head and a page of its posts, from the first,
# from a cursor, from a position (at) or around one post. Without a post
# asked for, the page is one snapshot statement (ThreadPageSnapshot).
async sub thread_page_p ( $self, $request, $context = undef ) {
    $request =
      { %{$request}, query_context => $request->{query_context} // $context };
    if ( !defined $request->{post} || !length $request->{post} ) {
        return await GPForum::Service::Forum::ThreadPageSnapshot->new(
            detail_reader => $self )->read_p($request);
    }
    return { ok => 0, error => 'not_found' }
      if !GPForum::Infrastructure::Id->is_uuid( $request->{post} );

    my $viewer = $request->{viewer}
      || GPForum::Service::Forum::Viewer->anonymous;
    my $thread = await $self->find_thread_p( $request->{thread_id}, $viewer,
        $request->{query_context} );
    return { ok => 0, error => 'not_found' } if !$thread;
    my $scope = $self->post_scope( $viewer, $thread );
    my $post  = await $self->post_reader->find_listed_post_p(
        {
            post_id        => $request->{post},
            thread_id      => $request->{thread_id},
            viewer_user_id => $viewer->user_id,
            viewer_scope   => $scope,
            query_context  => $request->{query_context}
        }
    );
    return { ok => 0, error => 'not_found' } if !$post;
    my $posts = await $self->post_reader->list_thread_posts_p(
        {
            thread_id => $request->{thread_id},
            limit     => $request->{limit} || $DEFAULT_POST_LIMIT,
            after => GPForum::Service::Forum::PageWindow->cursor_at_position(
                $post->get_column('position')
            ),
            viewer_user_id => $viewer->user_id,
            viewer_scope   => $scope,
            query_context  => $request->{query_context}
        }
    );
    return { ok => 1, thread => $thread, posts => $posts };
}

# The viewer for the thread's posts: grants decided for its category, and the
# owner of a private thread reads every reply in it (Visibility::_authors).
sub post_scope ( $, $viewer, $thread ) {
    my $scope = $viewer->within( $thread->get_column('category_id'),
        $thread->get_column('space_id') );
    my $owner = $thread->get_column('author_user_id') // q{};
    return $scope
      if ( $thread->get_column('visibility') // q{} ) ne 'private'
      || !$viewer->member
      || ( $viewer->user_id // q{} ) ne $owner;

    return GPForum::Service::Forum::Viewer->new(
        global_read => 1,
        member      => 1,
        user_id     => $viewer->user_id,
    );
}

sub _functions ($self) {
    return $self->functions // GPForum::X::Unavailable->throw(
        message => 'threads need the PostgreSQL function layer' );
}

sub _thread_is_visible ( $row, $viewer ) {
    return 0 if !$row;
    return 0 if !_visible_state( $row->get_column('moderation_state') );
    return 0
      if !GPForum::Service::Forum::Visibility->readable(
        $viewer,
        {
            category_id         => $row->get_column('category_id'),
            category_visibility => $row->get_column('category_visibility'),
            space_id            => $row->get_column('space_id'),
            space_visibility    => $row->get_column('space_visibility'),
            thread_author       => $row->get_column('author_user_id'),
            thread_visibility   => $row->get_column('visibility'),
        }
      );
    return 1 if !_deleted_row($row);

    return _author_viewer( $row, $viewer->user_id );
}

sub _deleted_row ($row) {
    return defined $row->get_column('deleted_at') ? 1 : 0;
}

sub _author_viewer ( $row, $viewer ) {
    return 0 if !defined $viewer || !length $viewer;

    my $author = $row->get_column('author_user_id') || q{};

    return $author eq $viewer ? 1 : 0;
}

sub _visible_state ($state) {
    return $state && ( $state eq 'visible' || $state eq 'locked' ) ? 1 : 0;
}

1;

__END__

=head1 NAME

GPForum::Service::Forum::ThreadDetailReader - Load a thread the viewer may read, with a page of its posts.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $reader = GPForum::Service::Forum::ThreadDetailReader->new(
        schema => $schema,
    );
    my $page = $reader->thread_page(
        {
            thread_id => $thread_id,
            viewer    => $viewer,
            limit     => 25,
            after     => $cursor,
        }
    );
    # { ok => 1, thread => $row, posts => { items, has_next, next_cursor } }
    # or { ok => 0, error => 'not_found' }

    my $thread = $reader->find_thread( $thread_id, $viewer );

=head1 DESCRIPTION

Reads the thread page. The thread row comes in one statement with its
author's names, its category's title and visibility and its space's
visibility, joined on primary keys, because the category and the space
decide who may read the thread (ADR 0102). A thread is readable when its
moderation state is C<visible> or C<locked> and
L<GPForum::Service::Forum::Visibility> lets the viewer read it; a deleted
thread is readable only by its author.

The posts come from L<GPForum::Service::Forum::PostReader>, scoped to the
viewer's grants for the thread's category and space. The author of a
private thread, when the viewer is a member, reads every reply in it.

A thread the viewer may not read and a thread that does not exist give the
same answer, so a page does not reveal that a hidden thread is there.

The thread row is read through C<api.forum_thread_page_head> (ADR 0126):
one call, a plain row. A page without a post asked for is one snapshot
statement (L<GPForum::Service::Forum::ThreadPageSnapshot>). Each read is
written once, as its promise method; the blocking methods are its twins,
run with the post reader on the blocking layer too (ADR 0177).

=head1 SUBROUTINES/METHODS

=head2 new

Constructor (L<GPForum::Base>). C<schema>, the DBIx::Class schema, is
required: without it C<new> throws L<GPForum::X::Argument>;
C<post_reader> defaults to a L<GPForum::Service::Forum::PostReader> on it.
C<functions> defaults to the schema's
L<GPForum::Infrastructure::SqlFunction>.

=head2 find_thread_p

Takes a thread id and an optional viewer (a
L<GPForum::Service::Forum::Viewer>, a user id, or nothing for an anonymous
reader). Answers the thread row from L</find_thread_row_p> when the viewer
may read it, otherwise C<undef>.

=head2 find_thread_row_p

Takes a thread id. Answers the thread row with its own columns
(C<thread_id>, C<category_id>, C<author_user_id>, C<title>, C<slug>,
C<pinned>, C<visibility>, C<moderation_state>, C<locked_at>,
C<last_activity_at>, C<deleted_at>) plus C<author_username>,
C<author_display_name>, C<category_title>, C<category_visibility>,
C<space_id> and C<space_visibility>, without any visibility check, as a
L<GPForum::Infrastructure::ResultRow::Thread>. Answers C<undef> for an
undefined or empty id or a missing thread.

=head2 visible_thread_row

Takes an already loaded thread head and an optional viewer. Applies the same
visibility and deletion checks as L</find_thread_p>, returning the row or
undef without loading it again.

=head2 thread_row_call

The call L</find_thread_row_p> makes, for the query-plan evidence:
C<[ 'forum_thread_page_head', { thread_id => $thread_id } ]>.

=head2 post_scope

Takes a viewer and a thread row. Returns the viewer whose grants the
thread's posts are judged by: the viewer within the thread's category and
space, or, for the owner of a private thread, one who reads every reply.

=head2 thread_page_p

Takes a hash reference with C<thread_id>, an optional C<viewer> (anonymous
when absent), an optional C<limit> (25 when absent or zero), and an
optional C<after> cursor, C<at> position or C<post> id. Answers
C<< { ok => 0, error => 'not_found' } >> when the viewer may not read the
thread or the post, otherwise
C<< { ok => 1, thread => $row, posts => $page } >>, where C<$page> is the
post reader's page (C<items>, C<has_next>, C<next_cursor>); a snapshot page
also carries C<read_snapshot>, the page's other reads answered ahead.

=head2 find_thread, find_thread_row, thread_page

The blocking twins: each is its C<_p> method run on the blocking call layer
(ADR 0177), answering the value instead of a promise. Each C<_p> method
takes an optional query context last.

=head1 DIAGNOSTICS

A thread that is missing or not readable is returned as C<not_found>, not
thrown. Database errors propagate.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Service::Forum::PostReader>, L<GPForum::Service::Forum::Viewer>,
L<GPForum::Service::Forum::Visibility>, L<GPForum::Base>,
L<GPForum::Infrastructure::ResultRow::Thread>,
L<GPForum::Infrastructure::SqlFunction>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

None known.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
