# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Web::ForumAccess;

use Const::Fast;
use Mojo::Base -base, -signatures;
use v5.40;

our $VERSION = '0.001';

const my $TRUST_READ_MULTIPLIER => 4;

const my $READ_RATE_LIMIT           => 60;
const my $READ_RATE_WINDOW          => 60;
const my $WRITE_RATE_LIMIT          => 20;
const my $COMPOSER_RATE_LIMIT       => 60;
const my $REPORT_RATE_LIMIT         => 5;
const my $CHURN_RATE_LIMIT          => 10;
const my $WRITE_RATE_WINDOW         => 60;
const my $REPORT_DETAILS_MAX        => 2_000;
const my $REPORT_REASON_MAX         => 80;
const my $CACHE_PREFIX              => 'forum-ssr';
const my $CACHE_TAG                 => 'forum:public-html';
const my $SEARCH_LIMIT              => 20;
const my $SEARCH_MAX_LIMIT          => 50;
const my $AUTOCOMPLETE_LIMIT        => 10;
const my $AUTOCOMPLETE_MIN          => 2;
const my $LIST_PAGE_LIMIT           => 25;
const my $LIST_PAGE_MAX             => 100;
const my $CATEGORY_LIST_LIMIT       => 100;
const my $CATEGORY_LIST_MAX         => 200;
const my $TARGET_POST               => 'post';
const my $TARGET_THREAD             => 'thread';
const my $TARGET_USER               => 'user';
const my $STATUS_BOOKMARKED         => 'bookmarked';
const my $STATUS_BOOKMARK_REMOVED   => 'bookmark_removed';
const my $STATUS_BOOKMARK_FILED     => 'bookmark_filed';
const my $STATUS_SUBSCRIBED         => 'subscribed';
const my $STATUS_SUBSCRIPTION_MUTED => 'subscription_muted';
const my $STATUS_UNSUBSCRIBED       => 'unsubscribed';
const my $STATUS_THREAD_CREATED     => 'thread_created';
const my $STATUS_THREAD_UPDATED     => 'thread_updated';
const my $STATUS_THREAD_MOVED       => 'thread_moved';
const my $STATUS_THREAD_DELETED     => 'thread_deleted';
const my $STATUS_THREAD_RESTORED    => 'thread_restored';
const my $STATUS_POST_CREATED       => 'post_created';
const my $STATUS_POST_UPDATED       => 'post_updated';
const my $STATUS_POST_DELETED       => 'post_deleted';
const my $STATUS_POST_RESTORED      => 'post_restored';
const my $STATUS_POST_LIKED         => 'post_liked';
const my $STATUS_POST_UNLIKED       => 'post_unliked';
const my $STATUS_POST_REACTED       => 'post_reacted';
const my $STATUS_POST_UNREACTED     => 'post_unreacted';

# What a member may do and undo at will, and so may churn: capped at 10 a
# minute (ADR 0129 adds the like).
const my $THREAD_CHURN =>
  qr/\A thread[.](?:bookmark|subscribe|subscription|unsubscribe)/msx;
const my $POST_CHURN         => qr/\A post[.](?:like|unlike|react|unreact)/msx;
const my $STATUS_READ_MARKED => 'read_marked';
const my $STATUS_REPORTED    => 'reported';
const my %WRITE_FLASH => (
    $STATUS_BOOKMARKED         => 'forum.bookmarked',
    $STATUS_BOOKMARK_FILED     => 'forum.bookmark_filed',
    $STATUS_BOOKMARK_REMOVED   => 'forum.bookmark_removed',
    $STATUS_POST_CREATED       => 'forum.reply_posted',
    $STATUS_POST_DELETED       => 'forum.post_deleted',
    $STATUS_POST_LIKED         => 'forum.post_liked',
    $STATUS_POST_RESTORED      => 'forum.post_restored',
    $STATUS_POST_UNLIKED       => 'forum.post_unliked',
    $STATUS_POST_REACTED       => 'forum.post_reacted',
    $STATUS_POST_UNREACTED     => 'forum.post_unreacted',
    $STATUS_POST_UPDATED       => 'forum.post_updated',
    $STATUS_READ_MARKED        => 'forum.posts_marked_read',
    $STATUS_REPORTED           => 'forum.reported',
    $STATUS_SUBSCRIBED         => 'forum.subscribed',
    $STATUS_SUBSCRIPTION_MUTED => 'forum.subscription_muted',
    $STATUS_THREAD_CREATED     => 'forum.thread_created',
    $STATUS_THREAD_DELETED     => 'forum.thread_deleted',
    $STATUS_THREAD_MOVED       => 'forum.thread_moved',
    $STATUS_THREAD_RESTORED    => 'forum.thread_restored',
    $STATUS_THREAD_UPDATED     => 'forum.thread_updated',
    $STATUS_UNSUBSCRIBED       => 'forum.unsubscribed',
);

# ADR 0144: a profile picture uploaded or removed, at most 10 a minute too:
# each upload runs the image tool.
const my $AVATAR_CHURN => qr/\A avatar[.](?:upload|remove)/msx;

const my %PARTICIPATION_ACTIONS => (
    'avatar.upload'  => 1,
    'draft.save'     => 1,
    'draft.preview'  => 1,
    'message.send'   => 1,
    'post.delete'    => 1,
    'post.edit'      => 1,
    'post.like'      => 1,
    'post.react'     => 1,
    'post.restore'   => 1,
    'post.unlike'    => 1,
    'post.unreact'   => 1,
    'reply.create'   => 1,
    'report.create'  => 1,
    'thread.create'  => 1,
    'thread.delete'  => 1,
    'thread.edit'    => 1,
    'thread.move'    => 1,
    'thread.restore' => 1,
);

# The forum_retrieval limit per window: GPFORUM_FORUM_READ_RATE_LIMIT,
# through the configuration, so it is validated, listed on the settings page
# and in the environment file template like every other setting. A capacity
# run from one address raises it for its window; without a configuration the
# product default applies.
has config          => undef;          # optional: GPForum::Config
has read_rate_limit => sub ($self) {
    return $self->config
      ? $self->config->forum_read_rate_limit
      : $READ_RATE_LIMIT;
};

sub read_rate_input ( $self, $input ) {
    return {
        action   => $input->{action},
        actor_id => $input->{actor_id},
        limit    => $self->read_rate_limit *
          ( $TRUST_READ_MULTIPLIER**_trust($input) ),
        scope          => 'forum_retrieval',
        window_seconds => $READ_RATE_WINDOW,
    };
}

sub write_rate_input ( $self, $input ) {
    return {
        action   => $input->{action},
        actor_id => $input->{actor_id},
        limit    => $self->write_limit_for( $input->{action} ) *
          ( $input->{action} eq 'report.create' ? 1 : 2**_trust($input) ),
        scope          => 'forum_http',
        window_seconds => $WRITE_RATE_WINDOW,
    };
}

sub write_limit_for ( $, $action ) {
    return $COMPOSER_RATE_LIMIT
      if $action eq 'draft.save' || $action eq 'draft.preview';
    if ( $action eq 'report.create' ) {
        return $REPORT_RATE_LIMIT;
    }
    if ( _churn_action($action) ) {
        return $CHURN_RATE_LIMIT;
    }

    return $WRITE_RATE_LIMIT;
}

sub _trust ($input) {
    my $level = $input->{trust_level} // 0;
    return $level =~ /\A [0-4] \z/msx ? $level : 0;
}

sub requires_participation ( $, $action ) {
    if ( !defined $action ) {
        return 0;
    }
    if ( exists $PARTICIPATION_ACTIONS{$action} ) {
        return 1;
    }

    return 0;
}

sub report_field_errors ( $self, $reason, $details ) {
    my %errors;
    my $reason_error = $self->report_reason_error($reason);
    if ($reason_error) {
        $errors{reason} = $reason_error;
    }
    if ( length( $details || q{} ) > $REPORT_DETAILS_MAX ) {
        $errors{details} = 'details are too long';
    }

    return \%errors;
}

sub report_reason_error ( $, $reason ) {
    if ( !defined $reason || !length $reason ) {
        return 'reason is required';
    }
    if ( length $reason > $REPORT_REASON_MAX ) {
        return 'reason is too long';
    }

    return undef;
}

sub is_unavailable ( $, $result ) {
    my $payload = $result || {};
    if ( $payload->{system_error} ) {
        return 1;
    }
    if ( ( $payload->{status} || q{} ) eq 'failed' ) {
        return 1;
    }

    return 0;
}

sub is_non_negative_integer ( $, $value ) {
    if ( !defined $value ) {
        return 0;
    }

    return $value =~ /\A [[:digit:]]+ \z/msx ? 1 : 0;
}

sub bounded_limit ( $self, $input ) {
    if ( $self->_invalid_limit( $input->{value} ) ) {
        return $input->{default};
    }
    if ( $input->{value} > $input->{maximum} ) {
        return $input->{maximum};
    }

    return $input->{value};
}

sub search_filter_fields {
    return qw(category_id author_user_id from to scope);
}

# The page size a list is read with, bounded as Forum::PageWindow bounds it,
# so the public cache's key names the size the page shows. Passed through,
# ?limit=abc, ?limit=007 and ?limit=100000 would each key an entry of their
# own for the same page of 25 or 100.
sub list_page_limit ( $self, $requested ) {
    return int $self->bounded_limit(
        {
            default => $LIST_PAGE_LIMIT,
            maximum => $LIST_PAGE_MAX,
            value   => $requested,
        }
    );
}

# The category index's size, bounded as Forum::CategoryReader bounds it (100
# unless asked for fewer, at most 200), for the same reason.
sub category_list_limit ( $self, $requested ) {
    return int $self->bounded_limit(
        {
            default => $CATEGORY_LIST_LIMIT,
            maximum => $CATEGORY_LIST_MAX,
            value   => $requested,
        }
    );
}

sub post_target {
    return $TARGET_POST;
}

sub thread_target {
    return $TARGET_THREAD;
}

sub user_target {
    return $TARGET_USER;
}

sub bookmarked_status {
    return $STATUS_BOOKMARKED;
}

sub bookmark_removed_status {
    return $STATUS_BOOKMARK_REMOVED;
}

sub bookmark_filed_status {
    return $STATUS_BOOKMARK_FILED;
}

sub post_liked_status {
    return $STATUS_POST_LIKED;
}

sub post_unliked_status {
    return $STATUS_POST_UNLIKED;
}

sub post_reacted_status {
    return $STATUS_POST_REACTED;
}

sub post_unreacted_status {
    return $STATUS_POST_UNREACTED;
}

sub subscribed_status {
    return $STATUS_SUBSCRIBED;
}

sub subscription_muted_status {
    return $STATUS_SUBSCRIPTION_MUTED;
}

sub unsubscribed_status {
    return $STATUS_UNSUBSCRIBED;
}

sub thread_created_status {
    return $STATUS_THREAD_CREATED;
}

sub thread_updated_status {
    return $STATUS_THREAD_UPDATED;
}

sub thread_moved_status {
    return $STATUS_THREAD_MOVED;
}

sub thread_deleted_status {
    return $STATUS_THREAD_DELETED;
}

sub thread_restored_status {
    return $STATUS_THREAD_RESTORED;
}

sub post_created_status {
    return $STATUS_POST_CREATED;
}

sub post_updated_status {
    return $STATUS_POST_UPDATED;
}

sub post_deleted_status {
    return $STATUS_POST_DELETED;
}

sub post_restored_status {
    return $STATUS_POST_RESTORED;
}

sub read_marked_status {
    return $STATUS_READ_MARKED;
}

sub reported_status {
    return $STATUS_REPORTED;
}

sub write_flash_key ( $, $status ) {
    if ( !defined $status ) {
        return undef;
    }
    if ( exists $WRITE_FLASH{$status} ) {
        return $WRITE_FLASH{$status};
    }

    return undef;
}

sub search_page_limit ( $self, $requested ) {
    return $self->_window_limit( $requested, $SEARCH_LIMIT );
}

sub autocomplete_limit ( $self, $requested ) {
    return $self->_window_limit( $requested, $AUTOCOMPLETE_LIMIT );
}

sub autocomplete_too_short ( $, $query ) {
    return length( $query || q{} ) < $AUTOCOMPLETE_MIN ? 1 : 0;
}

sub search_fetch_limit ( $, $limit ) {
    if ( $limit < $SEARCH_MAX_LIMIT ) {
        return $limit + 1;
    }

    return $limit;
}

sub search_more_limit ( $self, $has_more, $limit ) {
    my $next_limit;
    if ($has_more) {
        $next_limit = $self->search_page_limit( $limit * 2 );
    }

    return $next_limit;
}

# The key names everything that changes the page and nothing else: the
# visitor's language and theme -- else an English visitor is served the
# Italian page a previous visitor cached -- the path, and the effective page
# size. Keyed by the raw query string, every junk parameter would mint an
# entry and evict real ones (8.2).
sub public_cache_options ( $, $input ) {
    return {
        key => join( q{:},
            $CACHE_PREFIX,    $input->{name},
            $input->{locale}, $input->{theme},
            $input->{path},   'limit=' . ( $input->{limit} // q{} ) ),
        tags => [ $CACHE_TAG, @{ $input->{tags} } ],
    };
}

sub read_position_errors {
    return { last_read_position =>
          'last_read_position must be a non-negative integer', };
}

sub _window_limit ( $self, $requested, $default ) {
    return $self->bounded_limit(
        {
            default => $default,
            maximum => $SEARCH_MAX_LIMIT,
            value   => $requested,
        }
    );
}

sub _churn_action ($action) {
    return
         $action =~ $THREAD_CHURN
      || $action =~ $POST_CHURN
      || $action =~ $AVATAR_CHURN ? 1 : 0;
}

sub _invalid_limit ( $self, $value ) {
    if ( !defined $value ) {
        return 1;
    }
    if ( !$self->is_non_negative_integer($value) ) {
        return 1;
    }

    return $value < 1 ? 1 : 0;
}

1;

__END__

=head1 NAME

GPForum::Web::ForumAccess - Forum rate limits and input policy.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $limit = $access->write_limit_for('thread.create');

=head1 DESCRIPTION

Owns forum read/write rate-limit hashes, participation actions, report field
errors, search page and autocomplete limits, list page defaults, community
target types, community write-success statuses, search filter names, public SSR
cache keys, non-negative integer limits, and store-failure classification
for HTTP 503. It does not render HTTP responses or call rate-limiter
services.
L<GPForum::Controller::Forum::Base> still checks CSRF, sessions, suspensions,
and Guard errors.

=head1 SUBROUTINES/METHODS

=head2 read_rate_input

Returns the C<forum_retrieval> rate-limit arguments: L</read_rate_limit>
requests per 60 seconds.

=head2 config

The L<GPForum::Config> the read limit comes from; optional.

=head2 read_rate_limit

The forum pages one visitor may read per 60 seconds: the configuration's
C<forum_read_rate_limit> (C<GPFORUM_FORUM_READ_RATE_LIMIT>), or 60 without a
configuration.

=head2 write_rate_input

Returns the C<forum_http> rate-limit arguments for an action.

=head2 write_limit_for

Returns 5 for reports, 10 for bookmark/subscription churn, otherwise 20.

=head2 requires_participation

True for the writes a suspended member may not make: C<draft.save>,
C<draft.preview>, C<message.send>, C<thread.create>, C<reply.create>,
C<post.edit>, C<post.delete>, C<post.restore>, C<post.like>, C<post.unlike>,
C<post.react>, C<post.unreact>, C<avatar.upload>, C<report.create>,
C<thread.edit>, C<thread.delete>, C<thread.move>, and
C<thread.restore>. Bookmarks, subscriptions and read markers stay open: they
are the member's own and nobody else sees them.

=head2 report_field_errors

Returns reason/details validation errors.

=head2 report_reason_error

Returns a reason error or undef.

=head2 is_unavailable

True when a write result is a store failure (C<failed>) or a report
C<system_error>. Controllers map that to HTTP 503 without the exception text.

=head2 is_non_negative_integer

True when the value is a digit string, including zero.

=head2 bounded_limit

Takes C<< { value, default, maximum } >>. Returns C<default> when C<value>
is undefined, not made only of digits, or zero; C<maximum> when it is
larger; otherwise C<value> as given.

=head2 search_filter_fields

Returns the allowed search filter parameter names.

=head2 list_page_limit

Takes the requested page size of a category, thread, feed or bookmark list,
as it came in the URL. Returns 25 when it is undefined, not made only of
digits, or zero; 100 when it is larger; otherwise its integer value (C<007>
is 7). These are L<GPForum::Service::Forum::PageWindow>'s bounds, so the
size returned is the size the list is read with, and the public cache key
built from it names the page shown.

=head2 category_list_limit

Takes the requested size of the category index. Returns 100 when it is
undefined, not made only of digits, or zero; 200 when it is larger;
otherwise its integer value: L<GPForum::Service::Forum::CategoryReader>'s
bounds.

=head2 post_target

Returns C<post>.

=head2 thread_target

Returns C<thread>.

=head2 user_target

Returns C<user>.

=head2 bookmarked_status

Returns C<bookmarked>.

=head2 bookmark_removed_status

Returns C<bookmark_removed>.

=head2 bookmark_filed_status

Returns C<bookmark_filed>, the status of a bookmark moved to a folder (ADR
0136).

=head2 post_liked_status

Returns C<post_liked>.

=head2 post_unliked_status

Returns C<post_unliked>.

=head2 post_reacted_status

Returns C<post_reacted> (ADR 0145).

=head2 post_unreacted_status

Returns C<post_unreacted>.

=head2 subscribed_status

Returns C<subscribed>.

=head2 subscription_muted_status

Returns C<subscription_muted>.

=head2 unsubscribed_status

Returns C<unsubscribed>.

=head2 thread_created_status

Returns C<thread_created>.

=head2 thread_updated_status

Returns C<thread_updated>.

=head2 thread_moved_status

Returns C<thread_moved>.

=head2 thread_deleted_status

Returns C<thread_deleted>.

=head2 thread_restored_status

Returns C<thread_restored>.

=head2 post_created_status

Returns C<post_created>.

=head2 post_updated_status

Returns C<post_updated>.

=head2 post_deleted_status

Returns C<post_deleted>.

=head2 post_restored_status

Returns C<post_restored>.

=head2 read_marked_status

Returns C<read_marked>.

=head2 reported_status

Returns C<reported>.

=head2 write_flash_key

Returns the i18n catalog key for a successful HTML write, or undef when the
status has no flash copy.

=head2 search_page_limit

Returns a search page size between 1 and 50, defaulting to 20.

=head2 autocomplete_limit

Returns an autocomplete size between 1 and 50, defaulting to 10.

=head2 autocomplete_too_short

True when the query prefix is shorter than two characters.

=head2 search_fetch_limit

Returns one extra row for has-more detection unless the page is already at
the maximum.

=head2 search_more_limit

Returns the doubled next-page size when more results exist, or undef so
hash constructors keep the following keys.

=head2 public_cache_options

Takes C<< { name, locale, theme, path, limit, tags } >>. Returns
C<< { key, tags } >>: the key is C<forum-ssr:NAME:LOCALE:THEME:PATH:limit=N>
and the tags are C<forum:public-html> followed by C<tags>. The caller passes
the effective page size as C<limit> (L</list_page_limit>,
L</category_list_limit>) and the page's path without the parts that do not
change it, so a URL that differs only in those shares the entry.

=head2 read_position_errors

Returns the last-read position validation hash.

=head1 DIAGNOSTICS

None. HTTP rendering stays on the forum controllers.

=head1 CONFIGURATION AND ENVIRONMENT

Reads C<forum_read_rate_limit> from L<GPForum::Config>
(C<GPFORUM_FORUM_READ_RATE_LIMIT>, a positive whole number, 60 by default),
which a capacity run from one address raises; the configuration refuses any
other value at the start. The process environment is never read here.

=head1 DEPENDENCIES

Uses L<Const::Fast> and L<Mojo::Base>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Rate-limiter checks and Guard rendering remain on
L<GPForum::Controller::Forum::Base>.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause
license.

=cut
