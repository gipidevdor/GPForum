# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Forum::PostReader;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -async_await;
use v5.40;

use GPForum::Infrastructure::Keyset;
use GPForum::Infrastructure::ResultRow::Post;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Service::Forum::Viewer;
use GPForum::Service::Forum::Visibility;
use GPForum::X::Argument;
use GPForum::X::Unavailable;

use GPForum::Service::Forum::PageWindow;

our $VERSION = '0.001';

__PACKAGE__->requires('schema');

has page_window => sub { return GPForum::Service::Forum::PageWindow->new; };

# The columns a post row carries, in the order the resultset selects them.
const my @POST_COLUMNS => qw(
  post_id thread_id author_user_id current_body_id position
  visibility moderation_state created_at deleted_at
);
const my @POST_EXTRA =>
  qw(body body_source author_username author_display_name);

# ADR 0126: a page of a shape is api.forum_thread_page_posts's, each shape's
# statement a branch of the function.
has functions => \&GPForum::Infrastructure::SqlFunction::for_service;

# Each read is written once, as its promise method (ADR 0177).
GPForum::Infrastructure::SqlFunction->blocking_twins(
    qw(list_thread_posts find_listed_post find_visible_post find_post));

# A page of a thread's posts as the viewer may read them: the shape -- the
# viewer's standing, whether their own deleted posts are listed, and whether
# a cursor bounds the page -- picks the function's branch.
async sub list_thread_posts_p ( $self, $request, $context = undef ) {
    $request =
      { %{$request}, query_context => $request->{query_context} // $context };
    my $plan = $self->_plan($request);
    my $rows = await $self->_functions->rows_p(
        @{ $self->thread_posts_call( $request, $plan ) },
        $request->{query_context} );
    my $posts =
      [ map { GPForum::Infrastructure::ResultRow::Post->from($_) } @{$rows} ];
    return $self->page_window->page( $posts, $plan->{limit},
        [ 'position', 'post_id' ] );
}

# One post of a thread as the list would list it: the same columns, the
# same rules (ADR 0102). For the page that asks for the post a reply just
# created, with the viewer's scope for the thread.
async sub find_listed_post_p ( $self, $request, $context = undef ) {
    my $scope = $request->{viewer_scope}
      || GPForum::Service::Forum::Viewer->anonymous;
    return GPForum::Infrastructure::ResultRow::Post->from(
        await $self->_functions->row_p(
            'forum_find_listed_post',
            {
                global_read    => $scope->global_read,
                member         => $scope->member,
                post_id        => $request->{post_id},
                scope_user_id  => _user_id( $scope->user_id ),
                thread_id      => $request->{thread_id},
                viewer_user_id => _user_id( $request->{viewer_user_id} ),
            },
            $request->{query_context} // $context
        )
    );
}

# The call list_thread_posts_p makes: the function's catalogue name and its
# parameters, the branch chosen by the viewer's standing, their own posts
# and the cursor. Public so the query-plan evidence explains what runs.
sub thread_posts_call ( $self, $request, $plan = undef ) {
    $plan ||= $self->_plan($request);
    my $after  = $plan->{after} || {};
    my $viewer = $request->{viewer_user_id};
    if ( !length( $viewer // q{} ) ) {
        $viewer = undef;
    }

    my $values = {
        after_position => $after->{sort_value},
        after_post_id  => $after->{id},
        row_limit      => $plan->{fetch_rows},
        standing       => _standing($request),
        thread_id      => $request->{thread_id},
        viewer_user_id => $viewer,
    };

    # The function binds one viewer for the posts they may read and their own
    # deleted ones; every caller reads a page as the viewer it serves.
    if ( !_one_viewer($request) ) {
        GPForum::X::Argument->throw(
            message => 'a thread page reads as one viewer' );
    }

    return [ 'forum_thread_page_posts', $values ];
}

# The page's plan: a thread's posts sort by position, so only a position
# cursor is one.
sub _plan ( $self, $request ) {
    return $self->page_window->plan( { %{$request}, sort => 'position' } );
}

# The function binds one viewer id for both the posts the viewer may read
# and the deleted posts of their own: the scope must name the viewer the
# page is read as.
sub _one_viewer ($request) {
    my $viewer = $request->{viewer_scope}
      || GPForum::Service::Forum::Viewer->anonymous;

    return ( $viewer->user_id // q{} ) eq ( $request->{viewer_user_id} // q{} );
}

# The viewer's standing for the thread's posts: what decides which levels
# of visibility a shape reads.
sub _standing ($request) {
    my $viewer = $request->{viewer_scope}
      || GPForum::Service::Forum::Viewer->anonymous;

    return
        $viewer->global_read ? 'global'
      : $viewer->member      ? 'member'
      :                        'anonymous';
}

# The page as a resultset, kept only for the query-plan evidence
# (Benchmark::QueryPlanEndpoints), which compares it with the function.
sub thread_posts_resultset ( $self, $request, $plan = undef ) {
    $plan ||= $self->_plan($request);
    my $query = {
        'me.thread_id'        => $request->{thread_id},
        'me.moderation_state' => 'visible',
        %{ _post_visibility($request) },
    };
    _apply_deleted_filter( $query, $request );
    if ( $plan->{after} ) {
        _apply_cursor( $query, $plan->{after} );
    }

    return $self->schema->resultset('Post')->search_rs(
        $query,
        {
            %{ _list_attrs() },
            order_by =>
              [ { -asc => 'me.position' }, { -asc => 'me.post_id' }, ],
            rows => $plan->{fetch_rows},
        }
    );
}

# What a listed post carries: its columns, its current body and its author.
sub _list_attrs {
    return {
        columns   => [@POST_COLUMNS],
        join      => [ 'current_body', 'author' ],
        '+select' => [
            'current_body.body_rendered_safe', 'current_body.body_source',
            'author.username',                 'author.display_name',
        ],
        '+as' => [@POST_EXTRA],
    };
}

# ADR 0102. The thread was authorized by the caller; its posts are judged on
# their own level, with the viewer's grants decided for the thread's category
# ($request->{viewer_scope}, from Viewer->within). Without one, public only.
sub _post_visibility ($request) {
    my $viewer = $request->{viewer_scope}
      || GPForum::Service::Forum::Viewer->anonymous;

    return GPForum::Service::Forum::Visibility->readable_condition(
        $viewer,
        {
            post        => 'me.visibility',
            post_author => 'me.author_user_id',
        }
    );
}

# A post, if it and its thread are visible and the viewer can read them: its
# space, category, thread and the post itself (ADR 0102).
async sub find_visible_post_p ( $self, $post_id, $viewer = undef,
    $context = undef )
{
    return undef if !defined $post_id || !length $post_id;
    my $row = await $self->_functions->row_p( 'forum_find_visible_post',
        { post_id => $post_id }, $context );
    return _visible_to( GPForum::Infrastructure::ResultRow::Post->from($row),
        $viewer );
}

sub _visible_to ( $row, $viewer ) {
    return undef if !$row;

    return GPForum::Service::Forum::Visibility->readable(
        GPForum::Service::Forum::Viewer->from($viewer),
        {
            (
                map { $_ => $row->get_column($_) }
                  qw(category_id category_visibility space_id
                  space_visibility thread_author thread_visibility)
            ),
            post_author     => $row->get_column('author_user_id'),
            post_visibility => $row->get_column('visibility'),
        }
    ) ? $row : undef;
}

sub _apply_deleted_filter ( $query, $request ) {
    my $viewer = $request->{viewer_user_id};
    if ( defined $viewer && length $viewer ) {
        $query->{-or} = _viewer_deleted_clause($viewer);
        return;
    }

    $query->{'me.deleted_at'} = undef;

    return;
}

sub _viewer_deleted_clause ($viewer) {
    return [ { 'me.deleted_at' => undef },
        { 'me.author_user_id' => $viewer }, ];
}

# Adds the cursor to the query's -and, never replacing it: the -and already
# holds the post-visibility condition (ADR 0102), and replacing it -- as this
# did -- listed every private post from the second page on.
sub _apply_cursor ( $query, $after ) {
    my @and = @{ delete $query->{-and} // [] };
    if ( exists $query->{-or} ) {
        push @and, { -or => delete $query->{-or} };
    }
    push @and,
      GPForum::Infrastructure::Keyset->after(
        {},
        {
            id   => [ 'me.post_id',  $after->{id} ],
            sort => [ 'me.position', $after->{sort_value} ],
        }
      );
    $query->{-and} = \@and;

    return;
}

# A post by its id, whatever its state.
async sub find_post_p ( $self, $post_id, $context = undef ) {
    return undef if !defined $post_id || !length $post_id;
    return GPForum::Infrastructure::ResultRow::Post->from(
        await $self->_functions->row_p(
            'forum_find_post', { post_id => $post_id }, $context
        )
    );
}

sub _functions ($self) {
    return $self->functions // GPForum::X::Unavailable->throw(
        message => 'forum posts need the PostgreSQL function layer' );
}

sub _user_id ($id) {
    return defined $id && length $id ? $id : undef;
}

1;

__END__

=head1 NAME

GPForum::Service::Forum::PostReader - The posts of a thread a viewer may read, page by page, and single-post lookups.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $reader = GPForum::Service::Forum::PostReader->new( schema => $schema );

    my $page = $reader->list_thread_posts(
        {
            limit          => 25,
            thread_id      => $thread_id,
            viewer_scope   => $viewer->within( $category_id, $space_id ),
            viewer_user_id => $viewer->user_id,
        }
    );
    # { items => [...], has_next => 1, next_cursor => '...' }

    my $post = $reader->find_visible_post( $post_id, $viewer );

=head1 DESCRIPTION

Reads posts for the thread page and for actions on a single post. The
caller has already authorized the thread; each post is judged on its own
visibility, with the viewer's grants decided for the thread's category
(C<viewer_scope>, from L<GPForum::Service::Forum::Viewer/within>), and as
public-only without one (ADR 0102). Only visible posts are listed, and
deleted ones are left out except that a signed-in viewer still sees their
own. Posts come in position order, keyset paged on C<position> and
C<post_id> through L<GPForum::Service::Forum::PageWindow>; the cursor is
added beside the visibility condition, never in place of it, which once
listed every private post from the second page on.

Each listed row carries the post's columns plus C<body> (the rendered safe
HTML), C<body_source>, C<author_username> and C<author_display_name>.

A page is read through C<api.forum_thread_page_posts> (ADR 0126), whose
branches are the twelve shapes of a page: the viewer's standing (global
read, member, anonymous), whether a viewer id lists its own deleted posts,
and whether a cursor bounds the page. One call, plain rows. A request whose
scope names another viewer than its C<viewer_user_id> is refused
(GPForum::X::Argument): every caller reads a page as the viewer it serves.
Each read is written once, as its promise method; the blocking methods are
its twins (ADR 0177).

=head1 SUBROUTINES/METHODS

=head2 new

Constructor (L<GPForum::Base>). C<schema> is required. C<functions>
defaults to the schema's L<GPForum::Infrastructure::SqlFunction>.

=head2 list_thread_posts_p

Takes a hash reference with C<thread_id>, C<viewer_scope>,
C<viewer_user_id>, C<limit> and C<after>. Answers
C<< { items, has_next, next_cursor } >> with the post rows, each a
L<GPForum::Infrastructure::ResultRow::Post>, which answers C<get_column>
and the column accessors as the C<Post> row does.

=head2 thread_posts_call

Takes the same request and an optional page plan. Returns the call
L</list_thread_posts_p> makes, the function's catalogue name and its
parameters, public so the query-plan evidence explains what runs.

=head2 thread_posts_resultset

Takes the same request and an optional page plan. Returns the page as an
unexecuted resultset, kept only for the query-plan evidence, which compares
it with the function.

=head2 find_listed_post_p

Takes a hash reference with C<post_id>, C<thread_id>, C<viewer_scope> and
C<viewer_user_id>, as L</list_thread_posts_p> does. Answers the post as the
list would list it, with the same columns and under the same rules, or
undef.

=head2 find_visible_post_p

Takes a post id and an optional viewer (a
L<GPForum::Service::Forum::Viewer>, a bare user id, or nothing for an
anonymous one). Answers the post row when the post is visible and not
deleted, its thread is visible or locked and not deleted, and the viewer may
read its space, category, thread and the post itself; undef otherwise, and
for an empty id.

=head2 find_post_p

Takes a post id. Answers the post row whatever its state, or undef for an
empty id or no row.

=head2 list_thread_posts, find_listed_post, find_visible_post, find_post

The blocking twins: each is its C<_p> method run on the blocking call layer
(ADR 0177), answering the value instead of a promise. Every C<_p> method
takes an optional query context last.

=head1 DIAGNOSTICS

C<new> throws L<GPForum::X::Argument> without a C<schema>. Otherwise none of
its own; what is missing or unreadable is answered as undef. Database errors
propagate. Without the PostgreSQL function layer every read raises
L<GPForum::X::Unavailable>.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Base>, L<GPForum::Infrastructure::Keyset>,
L<GPForum::Infrastructure::ResultRow::Post>,
L<GPForum::Infrastructure::SqlFunction>,
L<GPForum::Service::Forum::Viewer>, L<GPForum::Service::Forum::Visibility>,
L<GPForum::Service::Forum::PageWindow>.

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
