# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Identity::ProfileReader;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -async_await;
use v5.40;

use GPForum::Infrastructure::SqlFunction;
use GPForum::Infrastructure::ResultRow;

use GPForum::Infrastructure::Keyset;
use GPForum::Infrastructure::Row qw(column_of rows_in);
use GPForum::Service::Forum::PageWindow;

our $VERSION = '0.001';

const my $DEFAULT_THREAD_LIMIT  => 10;
const my @THREAD_CURSOR_COLUMNS => qw(last_activity_at thread_id);
const my @REPLY_CURSOR_COLUMNS  => qw(created_at post_id);
const my $TRUST_NEW             => 0;
const my $TRUST_PARTICIPANT     => 1;
const my $TRUST_TRUSTED         => 2;
const my $COUNTS_TTL_SECONDS    => 60;

# The tags a member's cached counts carry: every public page's, which the
# invalidation worker purges when moderation or a category changes what is
# public, and the member's own, which it purges when they post, delete or
# restore (GPForum::Worker::Handler::CacheInvalidation).
const my $PUBLIC_HTML_TAG => 'forum:public-html';

has page_window => sub { return GPForum::Service::Forum::PageWindow->new; };
__PACKAGE__->requires(qw(schema));

has functions   => \&GPForum::Infrastructure::SqlFunction::for_service;
has cache       => undef;  # optional: without it the counts are read every time
has cache_epoch => undef;  # optional: missing required epoch bypasses cache
has cache_epoch_required => 0;
has cache_ttl_seconds    => sub { return $COUNTS_TTL_SECONDS; };

# The tag of a member's cached counts.
sub counts_tag ( $, $user_id ) {
    return "profile:$user_id";
}

sub public_profile ( $self, $username, $options ) {
    my $user = $self->_find_public_user($username);
    return _not_found() if !$user;

    # The two lists page apart, each with its own cursor: the threads by
    # their last activity (after), the replies by when they were written
    # (replies_after). One cursor for both paged the replies by a thread's
    # activity, repeating or skipping them.
    my ( $thread_page, $reply_page ) = $self->_page_plans($options);

    return _found(
        $user,
        {
            counts    => $self->_contribution_counts($user),
            threads   => $self->_recent_public_threads( $user, $thread_page ),
            replies   => $self->_recent_public_replies( $user, $reply_page ),
            avatar_id => $self->_avatar_id($user),
            trust     => $self->_trust_hash($user),
        }
    );
}

# The profile page as the web worker reads it, on its pooled asynchronous
# connections: through call_p's fallback each profile forked a child that
# opened a PostgreSQL connection of its own, one child at a time per
# worker. The same reads and the same shaping as public_profile.
async sub public_profile_p ( $self, $username, $options, $context = undef ) {
    return $self->public_profile( $username, $options )
      if !$self->functions || !$self->functions->can('row_p');

    my $functions = $self->functions;
    my $user      = _public_user(
        await $functions->row_p(
            'identity_user_by_identifier', _identifier_values($username),
            $context
        )
    );
    return _not_found() if !$user;

    my ( $thread_page, $reply_page ) = $self->_page_plans($options);
    my $user_only = { user_id => column_of( $user, 'id' ) };
    my $counts    = await $self->_contribution_counts_p( $user, $context );
    my $threads   = await $functions->rows_p( 'identity_profile_threads',
        _page_parameters( $user, $thread_page ), $context );
    my $replies = await $functions->rows_p( 'identity_profile_replies',
        _page_parameters( $user, $reply_page ), $context );
    my $avatar =
      await $functions->row_p( 'community_avatar_status', $user_only,
        $context );
    my $trust =
      await $functions->row_p( 'identity_profile_trust', $user_only, $context );

    return _found(
        $user,
        {
            counts  => $counts,
            threads =>
              $self->_thread_list( _result_rows($threads), $thread_page ),
            replies =>
              $self->_reply_list( _result_rows($replies), $reply_page ),
            avatar_id => _attachment_id($avatar),
            trust     => _trust_from( $user, $trust ),
        }
    );
}

sub _not_found {
    return { ok => 0, error => 'not_found' };
}

sub _found ( $user, $parts ) {
    return {
        ok      => 1,
        profile => {
            user    => _user_hash( $user, $parts->{avatar_id} ),
            trust   => $parts->{trust},
            counts  => $parts->{counts},
            threads => $parts->{threads},
            replies => $parts->{replies},
        },
    };
}

# The threads' and the replies' page plans, each with its own cursor.
sub _page_plans ( $self, $options ) {
    my $safe_options = $options || {};
    return map {
        $self->page_window->plan(
            {
                limit => $safe_options->{limit},
                after => $safe_options->{$_},
                sort  => 'timestamp',
            }
        )
    } qw(after replies_after);
}

sub _find_public_user ( $self, $username ) {
    return _public_user(
        $self->functions
        ? $self->functions->row( 'identity_user_by_identifier',
            _identifier_values($username) )
        : $self->schema->resultset('User')
          ->find( { username => _normalize_username($username) } )
    );
}

sub _identifier_values ($username) {
    return { identifier => _normalize_username($username), by_email => 0 };
}

# Deleted and suspended members have no public profile.
sub _public_user ($user) {
    return undef if !$user;
    return undef if defined column_of( $user, 'deleted_at' );
    return undef if ( column_of( $user, 'status' ) || q{} ) eq 'suspended';

    return $user;
}

# ADR 0144: the picture the member shows, or undef. Only the PostgreSQL
# function layer holds pictures.
sub _avatar_id ( $self, $user ) {
    return undef if !$self->functions;

    return _attachment_id(
        $self->functions->row(
            'community_avatar_status', { user_id => column_of( $user, 'id' ) }
        )
    );
}

sub _attachment_id ($status) {
    return $status ? $status->{attachment_id} : undef;
}

sub _trust_hash ( $self, $user ) {
    return _trust_from(
        $user,
        $self->functions
        ? $self->functions->row( 'identity_profile_trust',
            { user_id => column_of( $user, 'id' ) } )
        : $self->schema->resultset('TrustScoreSnapshot')
          ->find( column_of( $user, 'id' ) )
    );
}

sub _trust_from ( $user, $snapshot ) {
    return {
        score       => column_of( $snapshot, 'score' ) || 0,
        trust_level => column_of( $snapshot, 'trust_level' )
          || column_of( $user, 'trust_level' )
          || 0,
        calculated_at => column_of( $snapshot, 'calculated_at' ),
        version       => column_of( $snapshot, 'version' ) || 1,
        badge         => _trust_badge(
                 column_of( $snapshot, 'trust_level' )
              || column_of( $user, 'trust_level' )
              || 0
        ),
    };
}

sub _recent_public_threads ( $self, $user, $page ) {
    return $self->_thread_list(
        $self->functions
        ? _result_rows(
            $self->functions->rows(
                'identity_profile_threads', _page_parameters( $user, $page )
            )
          )
        : [
            rows_in(
                $self->public_threads_resultset(
                    column_of( $user, 'id' ), $page
                )
            )
        ],
        $page
    );
}

sub _result_rows ($rows) {
    return [ map { GPForum::Infrastructure::ResultRow->from($_) } @{$rows} ];
}

sub _thread_list ( $self, $rows, $page ) {
    my $window =
      $self->page_window->page( $rows, $page->{limit},
        \@THREAD_CURSOR_COLUMNS );

    return {
        items       => [ map { _thread_hash($_) } @{ $window->{items} } ],
        next_cursor => $window->{next_cursor},
    };
}

sub _reply_list ( $self, $rows, $page ) {
    my $window =
      $self->page_window->page( $rows, $page->{limit}, \@REPLY_CURSOR_COLUMNS );

    return {
        items       => [ map { _reply_hash($_) } @{ $window->{items} } ],
        next_cursor => $window->{next_cursor},
    };
}

# The resultset the profile's thread list executes. Public so the plan tests
# EXPLAIN what actually runs.
sub public_threads_resultset ( $self, $user_id, $page ) {
    return $self->schema->resultset('Thread')->search_rs(
        _thread_query( $user_id, $page->{after} ),
        {
            columns => [
                qw(
                  thread_id category_id author_user_id title slug visibility
                  moderation_state last_activity_at created_at
                )
            ],
            join     => { category => 'space' },
            order_by => [
                { -desc => 'me.last_activity_at' },
                { -desc => 'me.thread_id' }
            ],
            rows => $page->{fetch_rows} || $DEFAULT_THREAD_LIMIT,
        }
    );
}

sub _recent_public_replies ( $self, $user, $page ) {
    return $self->_reply_list(
        _result_rows(
            $self->functions->rows(
                'identity_profile_replies', _page_parameters( $user, $page )
            )
        ),
        $page
    ) if $self->functions;
    my $query  = _reply_query( column_of( $user, 'id' ), $page->{after} );
    my $search = $self->schema->resultset('Post')->search_rs(
        $query,
        {
            columns => [
                qw(
                  post_id thread_id author_user_id position visibility
                  moderation_state created_at
                )
            ],
            join => [ { thread => { category => 'space' } }, 'current_body' ],
            '+select' => [
                'thread.title', 'thread.slug',
                'current_body.body_rendered_safe'
            ],
            '+as'    => [qw(thread_title thread_slug body)],
            order_by =>
              [ { -desc => 'me.created_at' }, { -desc => 'me.post_id' } ],
            rows => $page->{fetch_rows} || $DEFAULT_THREAD_LIMIT,
        }
    );

    return $self->_reply_list( [ rows_in($search) ], $page );
}

# The member's public threads and replies. Counting them walks every one
# with its thread, category and space, on a page anyone may ask for again
# and again, so the counts are cached, for at most cache_ttl_seconds.
sub _contribution_counts ( $self, $user ) {
    my $user_id = column_of( $user, 'id' );
    my ( $key, $entry ) = $self->_counts_entry($user_id);
    return $self->_count_contributions($user_id) if !defined $key;

    return $self->cache->get_or_set( $key,
        sub { return $self->_count_contributions($user_id); }, $entry );
}

# The same counts and the same cache entry, read on a pooled asynchronous
# connection. The ticket is taken before the read, as get_or_set takes it,
# so an invalidation during the read keeps the stale counts out.
async sub _contribution_counts_p ( $self, $user, $context ) {
    my $values = { user_id => column_of( $user, 'id' ) };
    my ( $key, $entry ) = $self->_counts_entry( $values->{user_id} );
    my $cache = $self->cache;
    if ( defined $key ) {
        my $cached = $cache->get($key);
        return $cached if defined $cached;
        if ( $cache->can('ticket') ) {
            $entry->{ticket} = $cache->ticket( $entry->{tags}, { mint => 1 } );
        }
    }
    my $counts =
      await $self->functions->row_p( 'identity_profile_counts', $values,
        $context );
    if ( defined $key ) { $cache->put( $key, $counts, $entry ); }

    return $counts;
}

# The cache key and entry options of a member's counts, or nothing when
# the counts are not cached.
sub _counts_entry ( $self, $user_id ) {
    return
      if !$self->cache
      || ( $self->cache_epoch_required && !defined $self->cache_epoch );

    my $key = $self->counts_tag($user_id) . ':counts';
    if ( defined $self->cache_epoch ) {
        $key .= q{:privacy:} . $self->cache_epoch;
    }

    return (
        $key,
        {
            tags        => [ $PUBLIC_HTML_TAG, $self->counts_tag($user_id) ],
            ttl_seconds => $self->cache_ttl_seconds,
        }
    );
}

sub _count_contributions ( $self, $user_id ) {
    if ( $self->functions ) {
        return $self->functions->row( 'identity_profile_counts',
            { user_id => $user_id } );
    }
    my $threads = _count_search(
        $self->schema->resultset('Thread')->search_rs(
            _thread_query($user_id), { join => { category => 'space' } }
        )
    );
    my $replies = _count_search(
        $self->schema->resultset('Post')->search_rs(
            _reply_query($user_id),
            { join => { thread => { category => 'space' } } }
        )
    );

    return {
        public_threads => $threads,
        public_replies => $replies,
        total_public   => $threads + $replies,
    };
}

# The category and space a profile row sits in must be public and live: a
# public thread in a private category is not public activity (ADR 0102).
sub _page_parameters ( $user, $page ) {
    my $after = $page->{after} || {};
    return {
        user_id   => column_of( $user, 'id' ),
        after_at  => $after->{sort_value},
        after_id  => $after->{id},
        row_limit => $page->{fetch_rows} || $DEFAULT_THREAD_LIMIT
    };
}

sub _public_placement ($category) {
    return {
        "$category.deleted_at" => undef,
        "$category.visibility" => 'public',
        'space.visibility'     => 'public',
    };
}

# A profile is public for every reader (ADR 0102): only public threads in
# public, live categories of public spaces, whoever is looking.
sub _thread_query ( $user_id, $after = undef ) {
    my $query = {
        'me.author_user_id'   => $user_id,
        'me.deleted_at'       => undef,
        'me.moderation_state' => { -in => [ 'visible', 'locked' ] },
        'me.visibility'       => 'public',
        %{ _public_placement('category') },
    };
    if ($after) {
        GPForum::Infrastructure::Keyset->after(
            $query,
            {
                direction => 'desc',
                id        => [ 'me.thread_id',        $after->{id} ],
                sort      => [ 'me.last_activity_at', $after->{sort_value} ],
            }
        );
    }

    return $query;
}

sub _reply_query ( $user_id, $after = undef ) {
    my $query = {
        'me.author_user_id'       => $user_id,
        'me.deleted_at'           => undef,
        'me.moderation_state'     => 'visible',
        'me.visibility'           => 'public',
        'me.position'             => { q{>} => 1 },
        'thread.deleted_at'       => undef,
        'thread.moderation_state' => { -in => [ 'visible', 'locked' ] },
        'thread.visibility'       => 'public',
        %{ _public_placement('category') },
    };
    if ($after) {
        GPForum::Infrastructure::Keyset->after(
            $query,
            {
                direction => 'desc',
                id        => [ 'me.post_id',    $after->{id} ],
                sort      => [ 'me.created_at', $after->{sort_value} ],
            }
        );
    }

    return $query;
}

sub _user_hash ( $user, $avatar_id = undef ) {
    return {
        avatar_id     => $avatar_id,
        user_id       => column_of( $user, 'id' ),
        username      => column_of( $user, 'username' ),
        display_name  => column_of( $user, 'display_name' ),
        bio           => column_of( $user, 'bio' ) // q{},
        status        => column_of( $user, 'status' ),
        trust_level   => column_of( $user, 'trust_level' ) || 0,
        created_at    => column_of( $user, 'created_at' ),
        updated_at    => column_of( $user, 'updated_at' ),
        profile_label => q{@} . ( column_of( $user, 'username' ) || q{} ),
    };
}

sub _thread_hash ($thread) {
    return {
        thread_id        => column_of( $thread, 'thread_id' ),
        category_id      => column_of( $thread, 'category_id' ),
        author_user_id   => column_of( $thread, 'author_user_id' ),
        title            => column_of( $thread, 'title' ),
        slug             => column_of( $thread, 'slug' ),
        visibility       => column_of( $thread, 'visibility' ),
        moderation_state => column_of( $thread, 'moderation_state' ),
        last_activity_at => column_of( $thread, 'last_activity_at' ),
        created_at       => column_of( $thread, 'created_at' ),
    };
}

sub _reply_hash ($post) {
    return {
        post_id          => column_of( $post, 'post_id' ),
        thread_id        => column_of( $post, 'thread_id' ),
        author_user_id   => column_of( $post, 'author_user_id' ),
        position         => column_of( $post, 'position' ),
        visibility       => column_of( $post, 'visibility' ),
        moderation_state => column_of( $post, 'moderation_state' ),
        thread_title     => column_of( $post, 'thread_title' ),
        thread_slug      => column_of( $post, 'thread_slug' ),
        body             => column_of( $post, 'body' ),
        created_at       => column_of( $post, 'created_at' ),
    };
}

sub _trust_badge ($level) {
    return 'Trusted contributor' if $level >= $TRUST_TRUSTED;
    return 'Participant'         if $level >= $TRUST_PARTICIPANT;
    return 'New contributor'     if $level >= $TRUST_NEW;

    return 'New contributor';
}

sub _normalize_username ($username) {
    my $normalized = defined $username ? lc $username : q{};
    $normalized =~ s/\A \s+//msx;
    $normalized =~ s/\s+ \z//msx;

    return $normalized;
}

sub _count_search ($search) {
    return $search->count if $search && $search->can('count');

    my @rows = rows_in($search);
    return scalar @rows;
}

1;

__END__

=head1 NAME

GPForum::Service::Identity::ProfileReader - A member's public profile: identity, trust, counts and recent public activity.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $reader =
      GPForum::Service::Identity::ProfileReader->new( schema => $schema );

    my $result = $reader->public_profile( 'Alice', { limit => 10 } );
    if ( $result->{ok} ) {
        my $profile = $result->{profile};
        # user, trust, counts, threads, replies
    }

=head1 DESCRIPTION

Builds the data of the public profile page. A profile is the same for every
reader (ADR 0102): it counts and lists only public threads, not deleted and
visible or locked, in public, live categories of public spaces, and the
replies in them that are public, visible and not deleted, leaving out each
thread's opening post. Deleted and suspended members have no public
profile. The thread and reply lists are keyset paged through
L<GPForum::Service::Forum::PageWindow>, most recent first.

The counts walk every public post and thread of the member, so with a
C<cache> (the application's tiered cache) they are kept for at most
C<cache_ttl_seconds> (60 by default), under the tags C<forum:public-html>,
which moderation and category changes purge, and L</counts_tag>, which
the member's own posts, deletions and restores purge
(L<GPForum::Worker::Handler::CacheInvalidation>).

The trust block reads the member's C<trust_score_snapshots> row and falls
back to the trust level on the user row; the badge is
C<New contributor> below level 1, C<Participant> at level 1 and
C<Trusted contributor> from level 2.

=head1 SUBROUTINES/METHODS

=head2 public_profile

Takes a username, matched trimmed and lower-cased, and an optional hash
reference with C<limit> and C<after>. Returns
C<< { ok => 0, error => 'not_found' } >> when there is no such member or
the member is deleted or suspended. Otherwise returns
C<< { ok => 1, profile => { user, trust, counts, threads, replies } } >>:
C<user> has the id, username, display name, status, trust level, timestamps
and an C<@username> C<profile_label>, and C<avatar_id>, the picture the
member shows or undef (ADR 0144); C<trust> has C<score>,
C<trust_level>, C<calculated_at>, C<version> and C<badge>; C<counts> has
C<public_threads>, C<public_replies> and C<total_public>; C<threads> and
C<replies> are C<< { items, next_cursor } >> of plain hashes. The same limit
and cursor apply to both lists.

=head2 public_profile_p

L</public_profile> as a promise, with the request's optional query
context last: the member, counts, lists, picture and trust are read on the
worker's pooled asynchronous connections, the counts through the same
cache entry. Without the function layer, or with one that has no promise
reads, it answers what L</public_profile> answers.

=head2 counts_tag

Takes a member id. Returns the cache tag of that member's counts,
C<profile:ID>. Needs no instance.

=head2 public_threads_resultset

Takes a user id and a page plan (C<after> and C<fetch_rows>, as
L<GPForum::Service::Forum::PageWindow/plan> returns). Returns the
unexecuted resultset the profile's thread list runs, public so the plan
tests can EXPLAIN it. Without C<fetch_rows> it reads 10 rows.

=head1 DIAGNOSTICS

A missing profile is returned as C<not_found>, not thrown. Database errors
propagate.

=head1 CONFIGURATION AND ENVIRONMENT

C<cache_epoch> namespaces cached source data by the request's committed
public-content revocation epoch. C<cache_epoch_required> bypasses caching
when that epoch is unavailable; production enables this guard.

None. The optional C<cache> and C<cache_ttl_seconds> attributes are
the counts' cache and how long an entry lives.

=head1 DEPENDENCIES

L<GPForum::Infrastructure::Keyset>, L<GPForum::Infrastructure::Row>,
L<GPForum::Service::Forum::PageWindow>.

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
