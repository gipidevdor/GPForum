# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Forum::ThreadPageSnapshot;

use Mojo::Base 'GPForum::Base', -async_await;
use v5.40;
use GPForum::Infrastructure::ResultRow::Post;
use GPForum::Infrastructure::ResultRow::Thread;
use GPForum::Service::Attachment::Lifecycle;
use GPForum::Service::Forum::PageWindow;
use GPForum::Service::Forum::Viewer;

our $VERSION = '0.001';

__PACKAGE__->requires('detail_reader');
has lifecycle => sub { return GPForum::Service::Attachment::Lifecycle->new; };
has window    => sub { return GPForum::Service::Forum::PageWindow->new; };

async sub read_p ( $self, $request ) {
    my $viewer = $request->{viewer}
      || GPForum::Service::Forum::Viewer->anonymous;
    my $call      = $self->snapshot_call($request);
    my $functions = $self->detail_reader->functions;
    my $row    = await $functions->row_p( @{$call}, $request->{query_context} );
    my $thread = $self->detail_reader->visible_thread_row(
        GPForum::Infrastructure::ResultRow::Thread->from(
            $row ? $row->{thread_head} : undef
        ),
        $viewer
    );
    return { ok => 0, error => 'not_found' } if !$thread;
    my $posts = $self->window->page(
        [
            map { GPForum::Infrastructure::ResultRow::Post->from($_) }
              @{ $row->{posts} }
        ],
        $call->[1]{page_limit},
        [ 'position', 'post_id' ]
    );
    return {
        ok            => 1,
        thread        => $thread,
        posts         => $posts,
        read_snapshot => {
            key => $functions->answer_key(
                'forum_thread_page_reads',
                $self->_read_values( $thread, $posts, $viewer )
            ),
            rows => $row->{page_reads},
        },
    };
}

# Shared by the live reader and its nested-plan regression gate.
sub snapshot_call ( $self, $request ) {
    my $viewer = $request->{viewer}
      || GPForum::Service::Forum::Viewer->anonymous;
    my $plan = $self->window->plan(
        {
            limit => $request->{limit} || undef,
            after => GPForum::Service::Forum::PageWindow->cursor_at_position(
                $request->{at}
            ) // $request->{after},
            sort => 'position',
        }
    );
    return [
        'forum_thread_page_snapshot', $self->_values( $request, $viewer, $plan )
    ];
}

sub _values ( $self, $request, $viewer, $plan ) {
    my $position = $plan->{after} || {};
    return {
        thread_id        => $request->{thread_id},
        viewer_user_id   => $viewer->user_id,
        member           => $viewer->member,
        global_read      => $viewer->global_read,
        category_ids     => $viewer->category_ids,
        space_ids        => $viewer->space_ids,
        after_position   => $position->{sort_value},
        after_post_id    => $position->{id},
        page_limit       => $plan->{limit},
        link_target_type => $self->lifecycle->post_link_target,
        links_per_post   => $self->lifecycle->post_link_rows( [undef] ),
    };
}

sub _read_values ( $self, $thread, $posts, $viewer ) {
    my @ids   = map { $_->get_column('post_id') } @{ $posts->{items} };
    my @links = sort @ids;
    return {
        thread_id              => $thread->get_column('thread_id'),
        post_ids               => \@ids,
        viewer_user_id         => $viewer->user_id,
        engagement_target_type => 'thread',
        link_target_type => @ids ? $self->lifecycle->post_link_target : undef,
        link_post_ids    => \@links,
        link_row_limit   => $self->lifecycle->post_link_rows( \@links ),
    };
}

1;

__END__

=head1 NAME

GPForum::Service::Forum::ThreadPageSnapshot - One asynchronous thread-page read.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $snapshot = GPForum::Service::Forum::ThreadPageSnapshot->new(
        detail_reader => $reader,
    );
    my $page = await $snapshot->read_p($request);

=head1 DESCRIPTION

Reads the authorized thread, its keyset page and ancillary rows in one native
PostgreSQL operation and one MVCC snapshot. No data is retained across requests.
The detail reader repeats its usual visibility check on the returned head.
The lookahead post is omitted from ancillary reads. A function-answer key binds
those rows to the exact viewer, thread, post ids and attachment query limits;
another caller or a changed page cannot reuse them under a different call.

=head1 SUBROUTINES/METHODS

=head2 snapshot_call

Returns the exact stored-function name and bound values used by the reader,
including its bounded page and attachment limits, for query-plan evidence.

=head2 read_p

Takes the detail reader's request and returns its ordinary page result, with
request-local ancillary rows for C<ThreadPageReads>. Post-anchor requests keep
the existing detail-reader path; ordinary cursors and C<at> use this operation.

=head1 CONFIGURATION AND ENVIRONMENT

C<detail_reader> is required. C<lifecycle> supplies attachment
target and per-post bounds; C<window> bounds pagination and handles cursors.

=head1 DIAGNOSTICS

Missing and unreadable threads return C<not_found>. Database errors propagate.

=head1 DEPENDENCIES

L<GPForum::Service::Forum::ThreadDetailReader>,
L<GPForum::Service::Attachment::Lifecycle>, L<GPForum::Service::Forum::PageWindow>.

=head1 INCOMPATIBILITIES

None.

=head1 BUGS AND LIMITATIONS

Post anchors retain the existing native asynchronous read path.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause.

=cut
