# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Forum::ThreadPageReads;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -signatures;
use v5.40;

use GPForum::Infrastructure::Id;
use GPForum::Infrastructure::Row;
use GPForum::Infrastructure::SqlFunction;

our $VERSION = '0.001';

# The engagement a thread page reads is the member's on the thread: what
# GPForum::ViewModel::Forum::Page asks the bookmark and subscription stores.
const my $THREAD_TARGET => 'thread';

# Each part api.forum_thread_page_reads_v2 answers (migration 124): the
# store method that says the call it answers, the function and version that
# call names -- the version whose implementation the migration calls -- and
# the call's own columns, which the part's rows carry under those names.
const my %PART => (
    like => {
        function => 'community_post_likes',
        version  => 2,
        columns  => [qw(post_id like_count liked)],
    },
    reply_target => {
        function => 'forum_reply_targets',
        version  => 2,
        columns  => [
            qw(post_id reply_to_post_id reply_to_position
              reply_to_author_username)
        ],
    },
    tag => {
        function => 'forum_thread_tags',
        version  => 2,
        columns  => [qw(thread_id slug name tag_position)],
    },
    attachment_link => {
        function => 'attachment_links',
        version  => 2,
        columns  => [
            qw(attachment_link_id attachment_id target_type target_id
              created_at)
        ],
    },
    bookmark => {
        function => 'community_find_bookmark',
        version  => 2,
        columns  => [
            qw(bookmark_id user_id target_type target_id note created_at
              deleted_at)
        ],
    },
    subscription => {
        function => 'notification_find_subscription',
        version  => 2,
        columns  => [
            qw(subscription_id user_id target_type target_id preference
              created_at muted_at revoked_at)
        ],
    },
    read_state => {
        function => 'forum_read_state',
        version  => 2,
        columns  => [qw(user_id thread_id last_read_position last_read_at)],
    },
);

# Each store, and the method that says its call.
const my %CALLER => (
    like            => [ like_store         => 'summary_call' ],
    reply_target    => [ reply_links        => 'targets_call' ],
    tag             => [ thread_tags        => 'tags_call' ],
    attachment_link => [ attachment_store   => 'post_links_call' ],
    bookmark        => [ bookmark_store     => 'find_call' ],
    subscription    => [ subscription_store => 'find_call' ],
    read_state      => [ read_state         => 'state_call' ],
);

__PACKAGE__->requires(
    qw(schema like_store reply_links thread_tags attachment_store
      bookmark_store subscription_store read_state)
);
has logger    => undef;       # optional: without it a failed read is not logged
has functions => sub ($self) {
    return GPForum::Infrastructure::SqlFunction->for_schema( $self->schema );
};

# Runs the code that builds a thread page's payload with its reads answered.
sub reading ( $self, $input, $code ) {
    return GPForum::Infrastructure::SqlFunction->answering(
        $self->answers($input), $code );
}

# The answers for the reads a thread page makes once it has its posts (see
# GPForum::Infrastructure::SqlFunction/answering): each read's rows under
# its call's key, all read in one statement. None when a store cannot say
# its call (a test double), the schema has no function layer, a value is
# not one PostgreSQL reads, or the statement fails: each read then makes its
# own call, as it did.
#
# Takes the page as the detail reader gave it, the thread id as the request
# names it (the read state is keyed by that one), and the viewer's user id.
sub answers ( $self, $input ) {
    my $page = $input->{page};
    my %read = (
        posts     => [ _post_ids($page) ],
        thread    => _column( $page->{thread}, 'thread_id' ),
        thread_id => $input->{thread_id},
        viewer    => _has_text( $input->{viewer_user_id} )
        ? $input->{viewer_user_id}
        : undef,
    );
    my $calls     = $self->_calls( \%read )   or return {};
    my $values    = _values( \%read, $calls ) or return {};
    my $functions = $self->functions          or return {};

    my $rows;
    try {
        $rows = $functions->rows( 'forum_thread_page_reads', $values );
    }
    catch ($error) {
        my ($reason) = split /\n/msx, "$error";
        if ( $self->logger ) {
            $self->logger->warn("thread page reads degraded: $reason");
        }
        return {};
    };

    return _answers( $functions, $calls, $rows );
}

# The call each read makes, by part: none for a read the page does not make
# (no posts, no member, no tag-able thread). Undef when a store cannot say.
sub _calls ( $self, $read ) {
    for my $part ( keys %CALLER ) {
        my ( $store, $method ) = @{ $CALLER{$part} };
        return undef if !$self->$store->can($method);
    }
    my ( $posts, $thread, $viewer ) = @{$read}{qw(posts thread viewer)};
    my %call;
    if ( @{$posts} ) {
        $call{like} = $self->like_store->summary_call( $posts, $viewer );
        $call{reply_target} = $self->reply_links->targets_call($posts);
        $call{attachment_link} =
          $self->attachment_store->post_links_call($posts);
    }
    $call{tag} = $self->thread_tags->tags_call( [$thread] );
    if ( defined $viewer ) {
        $call{bookmark} =
          $self->bookmark_store->find_call( $viewer, $THREAD_TARGET, $thread );
        $call{subscription} =
          $self->subscription_store->find_call( $viewer, $THREAD_TARGET,
            $thread );
    }
    if ( defined $viewer && _has_text( $read->{thread_id} ) ) {
        $call{read_state} =
          $self->read_state->state_call( $viewer, $read->{thread_id} );
    }

    return { map { defined $call{$_} ? ( $_ => $call{$_} ) : () } keys %call };
}

# The one call's values, from the calls it answers. Undef when the thread
# or the viewer is not an id PostgreSQL reads as a uuid: the call would
# answer no part at all, where some of the reads would have rows. The
# posts' ids are the database's own.
sub _values ( $read, $calls ) {
    for my $id ( grep { defined } @{$read}{qw(thread viewer)} ) {
        return undef if !GPForum::Infrastructure::Id->is_uuid_spelling($id);
    }
    return undef if !defined $read->{thread};

    my $links = $calls->{attachment_link} ? $calls->{attachment_link}[1] : {};
    return {
        thread_id              => $read->{thread},
        post_ids               => $read->{posts},
        viewer_user_id         => $read->{viewer},
        engagement_target_type => $THREAD_TARGET,
        link_target_type       => $links->{target_type},
        link_post_ids          => $links->{post_ids}  // [],
        link_row_limit         => $links->{row_limit} // 0,
    };
}

# Each part's rows under the key of the call it answers, as that call's own
# columns. A call that names another function, or another version of it,
# than the one the statement read for its part is not answered.
sub _answers ( $functions, $calls, $rows ) {
    my %by_part;
    for my $row ( @{$rows} ) {
        my $part = $PART{ $row->{part} } or next;
        push @{ $by_part{ $row->{part} } },
          { map { $_ => $row->{$_} } @{ $part->{columns} } };
    }
    my %answers;
    for my $part ( keys %{$calls} ) {
        my ( $name, $values ) = @{ $calls->{$part} };
        next if $name ne $PART{$part}{function};
        next
          if $functions->catalogue->function($name)->{version} !=
          $PART{$part}{version};

        $answers{ $functions->answer_key( $name, $values ) } = $by_part{$part}
          // [];
    }

    return \%answers;
}

sub _post_ids ($page) {
    return grep { _has_text($_) }
      map { _column( $_, 'post_id' ) } @{ $page->{posts}{items} || [] };
}

sub _column ( $row, $name ) {
    return GPForum::Infrastructure::Row->column( $row, $name );
}

sub _has_text ($value) {
    return defined $value && length $value ? 1 : 0;
}

1;

__END__

=head1 NAME

GPForum::Service::Forum::ThreadPageReads - The reads a thread page makes
after its posts, in one statement.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $reads = GPForum::Service::Forum::ThreadPageReads->new(
        schema             => $schema,
        like_store         => $likes,
        reply_links        => $reply_links,
        thread_tags        => $tags,
        attachment_store   => $attachments,
        bookmark_store     => $bookmarks,
        subscription_store => $subscriptions,
        read_state         => $read_state,
        logger             => $log,
    );
    my $payload = $reads->reading(
        {
            page           => $page,
            thread_id      => $thread_id,
            viewer_user_id => $viewer_user_id,
        },
        sub { return build_the_payload() },
    );

=head1 DESCRIPTION

Once a thread page has its thread and its posts, it reads the posts'
likes, the posts they answer, the thread's tags and the posts' attachment
links, and for a member their bookmark, their subscription and their read
state: seven calls, each a round trip. C<api.forum_thread_page_reads_v2>
(migration 124) runs the seven calls' queries and answers their rows in
one statement; this service makes that statement and hands each read's
rows to the call that would have read them, through
L<GPForum::Infrastructure::SqlFunction/answering>. The stores, their
shapes and their failure handling are unchanged: each still asks for its
rows, and gets them without a round trip.

Each store says the call it makes (C<summary_call>, C<targets_call>,
C<tags_call>, C<post_links_call>, C<find_call>, C<state_call>), so the keys
are the stores' own. A store that cannot say -- a test double -- leaves the
page to its own calls; so does a part whose call names a function or
version other than the one the statement read.

=head1 SUBROUTINES/METHODS

=head2 new

Constructor (L<GPForum::Base>). C<schema> and the seven stores are
required; C<logger> is optional.

=head2 reading

Takes what L</answers> takes and a code reference; runs the code under
L<GPForum::Infrastructure::SqlFunction/answering> with those answers and
returns what it returns.

=head2 answers

Takes a hash reference: C<page>, the page the detail reader returned,
C<thread_id>, the thread id the request names, and C<viewer_user_id>
(undef for a guest). Returns the answers for
L<GPForum::Infrastructure::SqlFunction/answering>: a hash reference, empty
when the reads cannot be made in one statement, in which case the page
reads them one by one as before.

=head1 DIAGNOSTICS

A failed statement is logged at warn as C<thread page reads degraded:
REASON> and answers nothing.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Infrastructure::SqlFunction>, L<GPForum::Infrastructure::Row>,
L<GPForum::Infrastructure::Id>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

The statement answers what the stores' calls answer as of migration 124. A
store that moves its call to another function, or a later version, is no
longer answered here, and its read goes back to a round trip of its own
until the statement follows it.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause
license.

=cut
