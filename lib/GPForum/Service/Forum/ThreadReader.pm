# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Forum::ThreadReader;

use Const::Fast;
use MIME::Base64 qw(encode_base64url);
use Mojo::Base 'GPForum::Base', -async_await;
use v5.40;

use GPForum::Infrastructure::Keyset;
use GPForum::Infrastructure::ResultRow::Thread;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Service::Forum::Viewer;
use GPForum::Service::Forum::Visibility;
use GPForum::X::Unavailable;

use GPForum::Service::Forum::PageWindow;

our $VERSION = '0.001';

const my $PINNED_CURSOR_PARTS => 3;
const my %UNPINNED_TOKEN      => ( q{} => 1, '0' => 1, 'f' => 1, 'false' => 1 );

# How many replies a listed thread has: its counter row's reply_count, which
# every reply, delete and restore writes (ADR 0119). One lookup by primary
# key for each row of the page, inside the page's own statement.
#
# It counts the replies that are not deleted, whoever may read them: one a
# moderator hid, or one more private than its thread, is counted and not
# shown.
const my $REPLY_COUNT => <<'SQL';
COALESCE((SELECT counter.reply_count
            FROM thread_counters counter
           WHERE counter.thread_id = me.thread_id), 0)
SQL

__PACKAGE__->requires('schema');

has page_window => sub { return GPForum::Service::Forum::PageWindow->new; };
has functions   => \&GPForum::Infrastructure::SqlFunction::for_service;

# Each list is written once, as its promise method (ADR 0177).
GPForum::Infrastructure::SqlFunction->blocking_twins(
    qw(list_category_threads list_public_threads));

# A category's threads, pinned first, as the viewer may read them.
async sub list_category_threads_p ( $self, $request, $context = undef ) {
    my $plan = $self->_category_plan($request);
    my $rows = await $self->_functions->rows_p(
        @{ $self->category_threads_call( $request, $plan ) }, $context );
    return _pinned_page( _threads($rows), $plan->{limit} );
}

# The latest public threads the viewer may read.
async sub list_public_threads_p ( $self, $request, $context = undef ) {
    my $plan = $self->_latest_plan($request);
    my $rows = await $self->_functions->rows_p(
        @{ $self->latest_threads_call( $request, $plan ) }, $context );
    return $self->page_window->page( _threads($rows), $plan->{limit},
        [ 'last_activity_at', 'thread_id' ] );
}

sub _threads ($rows) {
    return [ map { GPForum::Infrastructure::ResultRow::Thread->from($_) }
          @{$rows} ];
}

# The calls the readers execute, also used by the nested query-plan gate.
sub category_threads_call ( $self, $request, $plan = undef ) {
    $plan ||= $self->_category_plan($request);
    my $scope = $request->{viewer_scope}
      || GPForum::Service::Forum::Viewer->anonymous;
    my $after = _decode_pinned_cursor( $request->{after} ) || {};
    return [
        'forum_list_category_threads',
        {
            after_activity  => $after->{sort_value},
            after_pinned    => $after->{pinned},
            after_thread_id => $after->{id},
            category_id     => $request->{category_id},
            global_read     => $scope->global_read,
            member          => $scope->member,
            row_limit       => $plan->{fetch_rows},
            scope_user_id   => _user_id( $scope->user_id ),
            viewer_user_id  => _user_id( $request->{viewer_user_id} ),
        }
    ];
}

# The list as a resultset, kept only for the query-plan evidence
# (Benchmark::QueryPlanEndpoints), which compares it with the function.
sub category_threads_resultset ( $self, $request, $plan = undef ) {
    $plan ||= $self->_category_plan($request);

    # Scalar first: with no cursor the decoder returns an empty list, which as
    # an argument would remove the parameter rather than pass undef.
    my $after   = _decode_pinned_cursor( $request->{after} );
    my $visible = _visible_category_query( $request, $after );

    return $self->schema->resultset('Thread')->search_rs(
        $self->_viewer_condition(
            $visible, $request->{viewer_user_id},
            $plan->{fetch_rows}
        ),
        {
            columns => [
                qw(
                  thread_id category_id author_user_id title slug pinned
                  visibility moderation_state locked_at last_activity_at
                  created_at deleted_at
                )
            ],
            join      => 'author',
            '+select' =>
              [ 'author.username', 'author.display_name', \$REPLY_COUNT ],
            '+as'    => [qw(author_username author_display_name reply_count)],
            order_by => _category_order(),
            rows     => $plan->{fetch_rows},
        }
    );
}

sub latest_threads_call ( $self, $request, $plan = undef ) {
    $plan ||= $self->_latest_plan($request);
    my $viewer = $request->{viewer}
      || GPForum::Service::Forum::Viewer->anonymous;
    my $after = $plan->{after} || {};
    return [
        'forum_list_public_threads',
        {
            after_activity  => $after->{sort_value},
            after_thread_id => $after->{id},
            category_ids    => $viewer->category_ids,
            global_read     => $viewer->global_read,
            member          => $viewer->member,
            row_limit       => $plan->{fetch_rows},
            space_ids       => $viewer->space_ids,
        }
    ];
}

# The latest list as a resultset, kept only for the query-plan evidence.
# Public threads only, from categories and spaces the viewer can read (ADR
# 0102): the home page's latest list and, with an anonymous viewer, the
# sitemap and the Atom feed.
sub latest_threads_resultset ( $self, $request, $plan = undef ) {
    $plan ||= $self->_latest_plan($request);
    my $query = {
        'me.deleted_at'       => undef,
        'me.moderation_state' => { -in => [ 'visible', 'locked' ] },
        'me.visibility'       => 'public',
        %{ GPForum::Service::Forum::Visibility->readable_condition(
                $request->{viewer}
                  || GPForum::Service::Forum::Viewer->anonymous,
                {
                    category    => 'category.visibility',
                    category_id => 'me.category_id',
                    space       => 'space.visibility',
                    space_id    => 'category.space_id',
                }
            )
        },
    };
    if ( $plan->{after} ) {
        GPForum::Infrastructure::Keyset->after(
            $query,
            {
                direction => 'desc',
                id   => [ 'me.thread_id',        $plan->{after}{id} ],
                sort => [ 'me.last_activity_at', $plan->{after}{sort_value} ],
            }
        );
    }

    return $self->schema->resultset('Thread')->search_rs(
        $query,
        {
            columns => [
                qw(
                  thread_id category_id author_user_id title slug pinned
                  visibility moderation_state last_activity_at created_at
                  deleted_at
                )
            ],
            join      => [ 'author', { category => 'space' } ],
            '+select' =>
              [ 'author.username', 'author.display_name', \$REPLY_COUNT ],
            '+as'    => [qw(author_username author_display_name reply_count)],
            order_by => [
                { -desc => 'me.last_activity_at' },
                { -desc => 'me.thread_id' },
            ],
            rows => $plan->{fetch_rows},
        }
    );
}

# A category has its own three-part cursor. PageWindow only needs its size:
# decoding that cursor as a two-part cursor first did the same work twice.
sub _category_plan ( $self, $request ) {
    return $self->page_window->plan( { limit => $request->{limit} } );
}

# The latest list sorts by last_activity_at, so only a timestamp cursor is one.
sub _latest_plan ( $self, $request ) {
    return $self->page_window->plan( { %{$request}, sort => 'timestamp' } );
}

# The category was authorized by the caller; its threads are judged on their
# own level, with the viewer's grants decided for the category
# ($request->{viewer_scope}, from Viewer->within). Without one, public only.
sub _visible_category_query ( $request, $after ) {
    my $query = {
        'me.category_id'      => $request->{category_id},
        'me.deleted_at'       => undef,
        'me.moderation_state' => { -in => [ 'visible', 'locked' ] },
        %{ GPForum::Service::Forum::Visibility->readable_condition(
                $request->{viewer_scope}
                  || GPForum::Service::Forum::Viewer->anonymous,
                {
                    thread        => 'me.visibility',
                    thread_author => 'me.author_user_id',
                }
            )
        },
    };
    if ($after) {
        $query->{-or} = _pinned_cursor_clause($after);

        # The bounds the OR implies, which the category index can answer
        # (Infrastructure::Keyset says why). Past the pinned block -- every
        # deep page -- the activity bound holds too.
        $query->{'me.pinned'} = { q{<=} => $after->{pinned} };
        if ( !$after->{pinned} ) {
            $query->{'me.last_activity_at'} = { q{<=} => $after->{sort_value} };
        }
    }

    return $query;
}

# An anonymous reader sees the visible threads. A signed-in reader also sees
# their own deleted ones, and "deleted_at IS NULL OR author_user_id = ?" as one
# predicate can use no index on threads: every category index is partial on
# deleted_at IS NULL, which that OR does not imply, so PostgreSQL read the whole
# table for every signed-in category page. Each half is instead read in page
# order from its own partial index and cut at the page size, and the page is
# taken from the union of the two by key -- still one statement, and still
# ordered by PostgreSQL rather than merged here.
sub _viewer_condition ( $self, $visible, $viewer, $rows ) {
    return $visible if !defined $viewer || !length $viewer;

    my $own_deleted = {
        %{$visible},
        'me.author_user_id' => $viewer,
        'me.deleted_at'     => { q{!=} => undef },
    };

    return {
        'me.thread_id' => {
            -in => _union_all(
                map { $self->_page_keys( $_, $rows )->as_query } $visible,
                $own_deleted
            )
        }
    };
}

sub _page_keys ( $self, $query, $rows ) {
    return $self->schema->resultset('Thread')->search_rs(
        $query,
        {
            columns  => ['thread_id'],
            order_by => _category_order(),
            rows     => $rows,
        }
    );
}

# as_query gives \[ $sql, @bind ] with the SQL already parenthesised, so the
# arms join with UNION ALL as they are and their binds concatenate in order.
sub _union_all (@subqueries) {
    my @arms = map { ${$_} } @subqueries;
    my ( @sql, @bind );
    for my $arm (@arms) {
        my ( $sql, @arm_bind ) = @{$arm};
        push @sql,  $sql;
        push @bind, @arm_bind;
    }

    return \[ join( ' UNION ALL ', @sql ), @bind ];
}

sub _category_order {
    return [
        { -desc => 'me.pinned' },
        { -desc => 'me.last_activity_at' },
        { -desc => 'me.thread_id' },
    ];
}

# The category listing orders by pinned DESC, last_activity_at DESC,
# thread_id DESC, so the keyset predicate has to lead with pinned. A cursor
# that only carried the last two columns let pinned rows repeat or vanish
# across pages.
sub _pinned_cursor_clause ($after) {
    return [
        { 'me.pinned' => { '<' => $after->{pinned} } },
        {
            'me.pinned'           => $after->{pinned},
            'me.last_activity_at' => { '<' => $after->{sort_value} },
        },
        {
            'me.pinned'           => $after->{pinned},
            'me.last_activity_at' => $after->{sort_value},
            'me.thread_id'        => { '<' => $after->{id} },
        },
    ];
}

sub _pinned_page ( $rows, $limit ) {
    my @items    = @{$rows};
    my $has_next = @items > $limit ? 1 : 0;

    if ($has_next) {
        pop @items;
    }

    return {
        items       => \@items,
        has_next    => $has_next,
        next_cursor => $has_next ? _encode_pinned_cursor( $items[-1] ) : undef,
    };
}

sub _encode_pinned_cursor ($row) {
    return if !$row;

    return encode_base64url(
        join q{|},
        _pinned_flag( $row->get_column('pinned') ),
        _cursor_text( $row->get_column('last_activity_at') ),
        _cursor_text( $row->get_column('thread_id') ),
    );
}

sub _decode_pinned_cursor ($cursor) {
    return if !defined $cursor || !length $cursor;

    my $decoded =
      GPForum::Service::Forum::PageWindow->decode_cursor_text($cursor);
    return if !defined $decoded;

    my @parts        = split /[|]/msx, $decoded, $PINNED_CURSOR_PARTS;
    my $cursor_parts = _pinned_cursor_from_parts( \@parts );
    return if !$cursor_parts;
    return
      if !GPForum::Service::Forum::PageWindow->acceptable_cursor(
        @{$cursor_parts}{qw(sort_value id)}, 'timestamp' );

    return $cursor_parts;
}

# A category cursor carries three parts: pinned, last activity and id.
sub _pinned_cursor_from_parts ($parts) {
    if ( @{$parts} != $PINNED_CURSOR_PARTS ) {
        return;
    }

    return {
        pinned     => _pinned_flag( $parts->[0] ),
        sort_value => $parts->[1],
        id         => $parts->[2],
    };
}

sub _pinned_flag ($value) {
    return 0 if !defined $value;

    return exists $UNPINNED_TOKEN{ lc $value } ? 0 : 1;
}

sub _cursor_text ($value) {
    return defined $value ? $value : q{};
}

sub _functions ($self) {
    return $self->functions // GPForum::X::Unavailable->throw(
        message => 'thread lists need the PostgreSQL function layer' );
}

sub _user_id ($id) {
    return defined $id && length $id ? $id : undef;
}

1;

__END__

=head1 NAME

GPForum::Service::Forum::ThreadReader - Keyset pages of a category's threads and of the latest public threads.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $reader = GPForum::Service::Forum::ThreadReader->new( schema => $schema );

    my $threads = $reader->list_category_threads(
        {
            category_id    => $category_id,
            limit          => 25,
            after          => $cursor,
            viewer_user_id => $user_id,
            viewer_scope   => $viewer->within( $category_id, $space_id ),
        }
    );

    my $latest = $reader->list_public_threads(
        { limit => 20, after => $cursor, viewer => $viewer } );

=head1 DESCRIPTION

Two thread listings, each a keyset page of one row more than the limit,
planned by L<GPForum::Service::Forum::PageWindow>.

The lists call C<api.forum_list_category_threads> and
C<api.forum_list_public_threads>. Each keyset shape keeps its own
statement, and category pages keep the two limited scans for a viewer's
live and deleted rows. Returned rows have the column accessors of a
C<Thread> row. Each list is written once, as its promise method; the
blocking methods are its twins (ADR 0177).

A category's threads are ordered by C<pinned>, then C<last_activity_at>,
then C<thread_id>, all descending, so its cursor leads with C<pinned>: a
cursor that carried only the last two columns let pinned threads repeat or
vanish across pages; a cursor of any other shape is no cursor, and the first
page is shown. The category
itself is authorized by the caller; its threads are judged on their own
level with the viewer's grants for that category (C<viewer_scope>, from
C<< Viewer->within >>), or as public only when there is none. Threads that
are deleted or not C<visible> or C<locked> are left out, except that a
signed-in reader also sees their own deleted threads. That is read as the
union of two page-sized key queries, one per partial index, because a
single C<deleted_at IS NULL OR author_user_id = ?> predicate could use no
index and read the whole table for every signed-in category page.

The latest list holds public threads only, not deleted and C<visible> or
C<locked>, from categories and spaces the viewer can read (ADR 0102),
ordered by C<last_activity_at> and then C<thread_id>, descending. It feeds
the home page's latest threads and, with an anonymous viewer, the sitemap
and the Atom feed.

Rows carry the author's C<username> and C<display_name> as
C<author_username> and C<author_display_name>, and C<reply_count>: the
C<reply_count> of the thread's C<thread_counters> row, 0 without one. It
counts the replies that are not deleted, the opening post not being one,
whoever may read them, so a reply a moderator hid, or one more private
than its thread, is counted and not shown.

=head1 SUBROUTINES/METHODS

=head2 category_threads_call

Takes a category listing request and optional precomputed page plan. Returns
the catalogue name and parameters the PostgreSQL category list executes.

=head2 latest_threads_call

Take the listing request and an optional precomputed page plan. Return the
catalogue name and parameters the corresponding PostgreSQL list executes,
also used by the nested query-plan evidence.

=head2 new

Constructor (L<GPForum::Base>). C<schema>, the L<DBIx::Class> schema, is
required: without it C<new> throws L<GPForum::X::Argument>. C<page_window>
defaults to a L<GPForum::Service::Forum::PageWindow>.

=head2 list_category_threads_p

Takes a hash reference with C<category_id>, C<limit>, C<after> (the cursor
string from the URL), C<viewer_user_id> (undef or empty for an anonymous
reader) and C<viewer_scope>. Answers C<< { items, has_next, next_cursor } >>:
the thread rows, whether there is a next page, and that page's cursor
(base64url of C<pinned|last_activity_at|thread_id>) or undef.

=head2 category_threads_resultset

Takes the same request and, optionally, a plan from
L<GPForum::Service::Forum::PageWindow/plan> (made from the request when
omitted). Returns the list as an unexecuted C<Thread> resultset, kept only
for the query-plan evidence, which compares it with the function.

=head2 list_public_threads_p

Takes a hash reference with C<limit>, C<after> (the cursor string) and
C<viewer> (anonymous when omitted). Answers the page hash reference from
L<GPForum::Service::Forum::PageWindow/page>, with a cursor over
C<last_activity_at> and C<thread_id>. Each row also carries C<excerpt>:
the first 1,000 characters of its opening post's safe HTML, undef when that
post is not public, visible and in place (migration 1056).

=head2 latest_threads_resultset

Takes the same request and an optional plan. Returns the latest list as an
unexecuted C<Thread> resultset, kept only for the query-plan evidence.

=head2 list_category_threads, list_public_threads

The blocking twins: each is its C<_p> method run on the blocking call layer
(ADR 0177), answering the value instead of a promise. Each C<_p> method
takes an optional query context last.

=head1 DIAGNOSTICS

Nothing of its own: a cursor that does not decode, has the wrong number of
parts or carries an unacceptable value shows the first page. Database
errors propagate. Without the PostgreSQL function layer each list raises
L<GPForum::X::Unavailable>.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Infrastructure::Keyset>, L<GPForum::Service::Forum::PageWindow>,
L<GPForum::Service::Forum::Viewer>, L<GPForum::Service::Forum::Visibility>,
L<GPForum::Base>.

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
