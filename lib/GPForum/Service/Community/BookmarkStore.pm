# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Community::BookmarkStore;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -async_await;
use v5.40;

use GPForum::Infrastructure::Id;
use GPForum::Infrastructure::Keyset;
use GPForum::Infrastructure::ResultRow;
use GPForum::Infrastructure::Row qw(column_of);
use GPForum::Infrastructure::SourceFunction;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Service::Clock;
use GPForum::Service::Forum::PageWindow;
use GPForum::Service::Forum::SourceThread;
use GPForum::X::Unavailable;

our $VERSION = '0.001';

const my $DEFAULT_LIMIT  => 50;
const my @CURSOR_COLUMNS => qw(created_at bookmark_id);

has clock       => sub { return GPForum::Service::Clock->new; };
has id_service  => sub { return GPForum::Infrastructure::Id->new; };
has page_window => sub { return GPForum::Service::Forum::PageWindow->new; };
__PACKAGE__->requires(qw(schema));
has functions => \&GPForum::Infrastructure::SqlFunction::for_service;

# ADR 0102: only rows whose post or thread the reader can still read, judged
# in the query before LIMIT. A bookmark kept pointing at a thread after its
# category turned private, showing its title to someone who lost access.
has readability => undef;    # optional: every source counts as readable

# Each read is written once, as its promise method (ADR 0177). A bookmark
# is written by api.community_bookmark_command and
# api.community_target_command (Community::Workflow), with the row
# new_bookmark_row draws.
GPForum::Infrastructure::SqlFunction->blocking_twins(
    qw(find_for_user_target status_for_user_target));

# The member's bookmark on the target, removed or not.
async sub find_for_user_target_p ( $self, $user_id, $target_type, $target_id,
    $context = undef )
{
    return GPForum::Infrastructure::ResultRow->from(
        await $self->_functions->row_p(
            @{ $self->find_call( $user_id, $target_type, $target_id ) },
            $context
        )
    );
}

# The call find_for_user_target makes on PostgreSQL: a page that reads the
# bookmark with its other reads in one statement
# (Service::Forum::ThreadPageReads) answers it.
sub find_call ( $, $user_id, $target_type, $target_id ) {
    return [
        'community_find_bookmark',
        {
            user_id     => $user_id,
            target_type => $target_type,
            target_id   => $target_id,
        }
    ];
}

# Whether the member's bookmark on the target is there, and its note.
async sub status_for_user_target_p ( $self, $user_id, $target_type,
    $target_id, $context = undef )
{
    return { bookmarked => 0 } if !$user_id;
    my $bookmark =
      await $self->find_for_user_target_p( $user_id, $target_type,
        $target_id, $context );
    return { bookmarked => 0 } if !$bookmark;

    return {
        bookmarked  => defined column_of( $bookmark, 'deleted_at' ) ? 0 : 1,
        bookmark_id => column_of( $bookmark, 'bookmark_id' ),
        note        => column_of( $bookmark, 'note' ),
    };
}

sub list_for_user ( $self, $user_id, $options ) {
    return GPForum::Infrastructure::SourceFunction->list(
        $self->_functions,
        $self->source_list_call( $user_id, $options || {} ),
        $self->readability ? 1 : 0
    );
}

# The page as the web worker reads it, on its pooled connections; without
# SQL functions the blocking read answers.
async sub list_page_for_user_p ( $self, $user_id, $options, $context = undef ) {
    return (
        await GPForum::Infrastructure::SourceFunction->page_p(
            $self,            $user_id,              $options,
            \@CURSOR_COLUMNS, 'bookmarks_resultset', $context
        )
    );
}

sub list_page_for_user ( $self, $user_id, $options ) {
    return GPForum::Infrastructure::SourceFunction->page( $self, $user_id,
        $options, \@CURSOR_COLUMNS, 'bookmarks_resultset' );
}

sub source_list_call ( $self, $user_id, $options ) {
    my $values =
      GPForum::Infrastructure::SourceFunction->page_values( $self->readability,
        $user_id, $options, $DEFAULT_LIMIT );
    $values->{folder}      = $options->{folder}      || undef;
    $values->{target_type} = $options->{target_type} || undef;
    return [ 'community_list_bookmarks', $values ];
}

sub bookmarks_resultset ( $self, $user_id, $options ) {
    my $query = {
        user_id    => $user_id,
        deleted_at => undef,
        %{ GPForum::Infrastructure::SourceFunction->readable_condition(
                $self->readability, $user_id,
                $options->{viewer}, 'me.target_type',
                'me.target_id'
            )
        },
    };
    if ( $options->{target_type} ) {
        $query->{target_type} = $options->{target_type};
    }
    if ( $options->{after} ) {
        GPForum::Infrastructure::Keyset->after(
            $query,
            {
                direction => 'desc',
                id        => [ 'bookmark_id', $options->{after}{id} ],
                sort      => [ 'created_at',  $options->{after}{sort_value} ],
            }
        );
    }

    return $self->schema->resultset('Bookmark')->search_rs(
        $query,
        {
            GPForum::Service::Forum::SourceThread->attributes(
                $self->readability, 'me.target_type', 'me.target_id'
            ),
            order_by =>
              [ { -desc => 'created_at' }, { -desc => 'bookmark_id' } ],
            rows => $options->{limit} || $DEFAULT_LIMIT,
        }
    );
}

# The row api.community_bookmark_command saves: a new id, the request and
# the time.
sub new_bookmark_row ( $self, $input ) {
    return {
        bookmark_id => $self->id_service->uuid,
        user_id     => $input->{user_id},
        target_type => $input->{target_type},
        target_id   => $input->{target_id},
        note        => $input->{note} || q{},
        created_at  => $self->clock->now_iso8601,
        deleted_at  => undef
    };
}

sub _functions ($self) {
    return $self->functions // GPForum::X::Unavailable->throw(
        message => 'bookmarks need the PostgreSQL function layer' );
}

1;

__END__

=head1 NAME

GPForum::Service::Community::BookmarkStore - Saves, removes and lists a member's bookmarks.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $store = GPForum::Service::Community::BookmarkStore->new(
        readability => GPForum::Service::Forum::Readability->new(
            schema => $schema,
        ),
        schema => $schema,
    );
    my $status = $store->status_for_user_target( $user_id, 'thread', $thread_id );
    my $page   = $store->list_page_for_user(
        $user_id,
        { target_type => 'thread', limit => 25, after => $cursor, viewer => $viewer },
    );

=head1 DESCRIPTION

A member has at most one C<bookmarks> row per target. Removing a bookmark
soft-deletes it; saving it again restores the same row, with the new note.
Both are one call each with the command log
(C<api.community_bookmark_command>, C<api.community_target_command>), made by
L<GPForum::Service::Community::Workflow> with the row L</new_bookmark_row>
draws; this store reads.

Lists show active bookmarks only, newest first. When C<readability> is set,
they keep only bookmarks whose post or thread the reader can still read,
judged in the query before C<LIMIT> (ADR 0102), so a page stays full. A
bookmark used to keep pointing at a thread after its category turned
private, showing its title to someone who had lost access. Each read is
written once, as its promise method; the blocking methods are its twins
(ADR 0177).

=head1 SUBROUTINES/METHODS

=head2 new_bookmark_row

Takes C<user_id>, C<target_type>, C<target_id> and C<note>. Returns the row
C<api.community_bookmark_command> saves: a new id, the request, the time,
and no deletion.

=head2 find_for_user_target_p

Takes a user id, a target type and a target id, and an optional query
context. Answers that member's bookmark row for the target, active or
soft-deleted, or undef.

=head2 find_call

Takes what L</find_for_user_target_p> takes; answers the call it makes,
the function's catalogue name and its values. The class answers it too.

=head2 status_for_user_target_p

Takes a user id, a target type and a target id, and an optional query
context. Answers C<< { bookmarked => 0 } >> when there is no user id or no
row; otherwise C<bookmarked> (1 when active, 0 when soft-deleted),
C<bookmark_id> and C<note>.

=head2 find_for_user_target, status_for_user_target

The blocking twins: each is its C<_p> method run on the blocking call layer
(ADR 0177), answering the value instead of a promise.

=head2 list_for_user

Takes a user id and an optional hash reference of the options
C<bookmarks_resultset> takes. Returns an array reference of the rows, at
most C<limit> (default 50) of them.

=head2 list_page_for_user

Takes a user id and a hash reference with C<limit>, C<after> (the cursor
string from the URL), C<target_type> and C<viewer>. Returns the page hash
reference from L<GPForum::Service::Forum::PageWindow/page>: C<items>,
C<has_next> and C<next_cursor>, the cursor over C<created_at> and
C<bookmark_id>.

=head2 list_page_for_user_p

L</list_page_for_user> as a promise, with an optional query context last,
read on the worker's pooled asynchronous connections
(L<GPForum::Infrastructure::SourceFunction/page_p>).

=head2 bookmarks_resultset

Takes a user id and a hash reference with optional C<target_type>,
C<after> (an already decoded C<< { sort_value, id } >>), C<limit> (default
50) and C<viewer> (the reader to judge readability for; defaults to the
user id). Returns the unexecuted C<Bookmark> resultset of the member's
active bookmarks, ordered by C<created_at> and then C<bookmark_id>,
descending. Public so tests and the query-plan evidence see the SQL that
runs. When C<readability> is set, each row also carries the thread it is
about, C<source_thread_id> and C<source_thread_title>
(L<GPForum::Service::Forum::SourceThread>); without it neither is selected,
since the list is then not cut to what the reader may read.

=head2 source_list_call

Takes the member id and listing options with an already decoded cursor.
Returns the function catalogue name and the exact bound parameters the list
executes, also used by its nested query-plan evidence.

=head1 DIAGNOSTICS

Database errors propagate. Without the PostgreSQL function layer every
read raises L<GPForum::X::Unavailable>.

=head1 CONFIGURATION AND ENVIRONMENT

None. C<clock> and C<id_service> default to L<GPForum::Service::Clock> and
L<GPForum::Infrastructure::Id>; tests pass fixed ones.

=head1 DEPENDENCIES

L<GPForum::Infrastructure::Id>, L<GPForum::Infrastructure::Keyset>,
L<GPForum::Infrastructure::Row>, L<GPForum::Infrastructure::SqlFunction>,
L<GPForum::Infrastructure::SourceFunction>, L<GPForum::Service::Clock>,
L<GPForum::Service::Forum::PageWindow>,
L<GPForum::Service::Forum::Readability> (passed in as C<readability>).

Extends L<GPForum::Base>: built without C<schema> it throws
L<GPForum::X::Argument>.

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
