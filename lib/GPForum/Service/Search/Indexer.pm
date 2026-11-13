# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Search::Indexer;

use Const::Fast;
use List::Util  qw(none uniq);
use Digest::SHA qw(sha1_hex);
use Mojo::Base 'GPForum::Base', -signatures, -async_await;
use v5.40;

use GPForum::X::Argument;
use GPForum::X::Unavailable;
use GPForum::Service::Clock;
use GPForum::Infrastructure::Id;
use GPForum::Service::Search::DocumentBuilder;
use GPForum::Infrastructure::SqlFunction;

our $VERSION = '0.001';

const my $REBUILD_BATCH  => 500;
const my @REBUILD_COUNTS => qw(indexed pruned unchanged);
const my @REBUILD_TYPES  => qw(thread post);

# A UUID's 8-4-4-4-12 hex groups, read from the front of a SHA-1 digest.
const my $UUID_GROUPS => 'A8 A4 A4 A4 A12';

has clock      => sub { return GPForum::Service::Clock->new; };
has id_service => sub { return GPForum::Infrastructure::Id->new; };

# Ids a rebuild step indexes, and posts a batch of one thread indexes or
# removes: enough to be worth an outbox message, few enough that a step never
# holds the dispatcher for long, nor a removal's transaction more than this
# many document locks.
has rebuild_batch_size => $REBUILD_BATCH;
has semantic           => undef;          # optional: local embedding projection
__PACKAGE__->requires(qw(schema));
has functions => \&GPForum::Infrastructure::SqlFunction::for_service;

# Written once, as its promise method (ADR 0177); the embedding projection
# it awaits blocks with it.
GPForum::Infrastructure::SqlFunction->blocking_twins(
    qw(observe_lag index_thread index_thread_posts index_thread_posts_batch
      index_post remove_post remove_thread rebuild rebuild_batch)
);
GPForum::Infrastructure::SqlFunction->blocking_parts('semantic');

# How far search can be behind the forum: the outbox says, which every search
# update passes through (api.search_observe_lag_v3).
async sub observe_lag_p ( $self, $context = undef ) {
    my $row =
      await $self->_functions->row_p( 'search_observe_lag', {}, $context );

    return {
        lag_seconds       => 0 + ( $row->{lag_seconds} // 0 ),
        oldest_pending_at => $row->{oldest_pending_at},
        pending           => 0 + ( $row->{pending} // 0 ),
        projection_name   => 'search_documents',
        status            => $row->{pending} ? 'behind' : 'current',
    };
}

# The thread's document, then its embedding: slow inference never holds the
# document lock.
async sub index_thread_p ( $self, $thread_id, $context = undef ) {
    my $result = await $self->_index_entity_p( 'thread', $thread_id, $context );
    await $self->_embed_p( 'thread', $thread_id, $context );

    return $result;
}

# Batch drivers hold no transaction of their own on purpose: each entity
# below is already one statement, and a corpus-wide transaction would pin
# the snapshot for the whole rebuild.
async sub index_thread_posts_p ( $self, $thread_id, $context = undef ) {
    my %summary = map { $_ => 0 } @REBUILD_COUNTS;
    my $after;
    while (1) {
        my $batch =
          await $self->index_thread_posts_batch_p( $thread_id, $after,
            $context );
        for my $count (@REBUILD_COUNTS) {
            $summary{$count} += $batch->{$count};
        }
        $after = $batch->{next_after};
        last if !defined $after;
    }

    return \%summary;
}

# One batch of a thread's posts indexed again, each post on its own: every
# post of the thread, whatever its state, so a post that died since keeps
# no document. $after is the position of the last post done; next_after,
# set when the batch was full, is where the next batch starts. The search
# handler runs one batch per outbox message, so renaming or moving a large
# thread never holds the dispatcher for long.
async sub index_thread_posts_batch_p (
    $self, $thread_id,
    $after = undef,
    $context = undef
  )
{
    my $posts =
      await $self->_thread_post_batch_p( $thread_id, $after, $context );
    my %counts = map { $_ => 0 } @REBUILD_COUNTS;
    for my $post ( @{$posts} ) {
        my $result = await $self->index_post_p( $post->{post_id}, $context );
        $counts{ _rebuild_outcome($result) }++;
    }

    return {
        %counts,
        next_after => _next_position( $posts, $self->rebuild_batch_size ),
        thread_id  => $thread_id,
    };
}

async sub index_post_p ( $self, $post_id, $context = undef ) {
    my $result = await $self->_index_entity_p( 'post', $post_id, $context );
    await $self->_embed_p( 'post', $post_id, $context );

    return $result;
}

# A hidden or deleted post leaves the index by being indexed again under its
# lock: indexing removes the document of a post that is no longer live. A
# blind delete let a hide retried after the restore that followed it remove
# the restored post's document, as remove_thread below explains for threads.
async sub remove_post_p ( $self, $post_id, $context = undef ) {
    return await $self->_index_entity_p( 'post', $post_id, $context );
}

# A hidden or deleted thread leaves the index with every post in it, or
# deleted content stays searchable. The thread's document goes first, in its
# own statement: autocomplete serves thread documents only, so the title
# leaves the suggestions at once. The posts follow a batch at a time, each
# batch one statement holding at most rebuild_batch_size advisory locks --
# PostgreSQL's shared lock table holds a few thousand, and a whole large
# thread in one transaction failed to leave. A failure part way leaves
# removed whatever went; the retry removes the rest.
#
# Each step reads the thread again under its locks and removes only while it
# is still dead: the thread's document is indexed again, which removes it
# from a dead thread, and a batch of posts stops at a live one. Two
# dispatchers can deliver a hide and the restore after it in either order,
# and a removal that came second deleted what the restore had just indexed.
async sub remove_thread_p ( $self, $thread_id, $context = undef ) {
    my $result = await $self->index_thread_p( $thread_id, $context );
    $result->{posts_removed} =
      await $self->_remove_posts_for_thread_p( $thread_id, $context );

    return $result;
}

# Rebuilds the projection from the canonical rows (ADR 0062), after a
# search configuration change, a handler bug or dead-lettered events: every
# live thread and post is indexed again, a batch of ids at a time so memory
# stays flat however large the forum, and documents whose source is gone,
# deleted or hidden are removed.
async sub rebuild_p ( $self, $scope, $context = undef ) {
    my $entity_type = $scope->{entity_type} || 'all';
    my %summary     = (
        entity_type => $entity_type,
        indexed     => 0,
        ok          => 1,
        pruned      => 0,
        unchanged   => 0,
    );
    my $cursor = { entity_type => $entity_type };
    while ($cursor) {
        my $step = await $self->rebuild_batch_p( $cursor, $context );
        for my $count (@REBUILD_COUNTS) {
            $summary{$count} += $step->{$count};
        }
        $cursor = $step->{next};
    }

    return \%summary;
}

# One step of a rebuild: up to 500 ids of one entity type, or, last, the
# removal of orphaned documents. $cursor holds entity_type (thread, post or
# all), stage (the type being indexed, or prune) and after (the last id
# done). Answers this step's counts and the next cursor, or none when the
# rebuild is done. The console's rebuild runs one step per outbox message,
# so a large forum never holds the dispatcher for long.
async sub rebuild_batch_p ( $self, $cursor, $context = undef ) {
    my @types  = _rebuild_types( $cursor->{entity_type} );
    my $stage  = $cursor->{stage} || $types[0];
    my %counts = map { $_ => 0 } @REBUILD_COUNTS;

    if ( $stage eq 'prune' ) {

        # A dead thread's posts go with it, whichever type was rebuilt: the
        # post prune removes only posts that are dead or in a dead thread.
        for my $type ( uniq( @types, 'post' ) ) {
            $counts{pruned} += await $self->_prune_p( $type, $context );
        }
        return { %counts, next => undef };
    }
    if ( none { $_ eq $stage } @types ) {
        GPForum::X::Argument->throw(
            message => "unknown rebuild stage: $stage" );
    }

    my @ids = await $self->_live_ids_p( $stage, $cursor->{after}, $context );
    for my $id (@ids) {
        my $result = await $self->_index_p( $stage, $id, $context );
        $counts{ _rebuild_outcome($result) }++;
    }

    my %next = ( entity_type => $cursor->{entity_type} || 'all' );
    if ( @ids == $self->rebuild_batch_size ) {
        @next{qw(stage after)} = ( $stage, $ids[-1] );
    }
    else {
        $next{stage} = _stage_after( $stage, @types );
    }

    return { %counts, next => \%next };
}

# Reading the source row and rewriting search_documents are one statement,
# under the document's advisory lock (api.search_index_entity): a document
# half written from a row that moved on indexes stale content, and a
# rebuild and the live handler cannot interleave. An unchanged document is
# skipped; a source gone, deleted or hidden has its document removed.
async sub _index_entity_p ( $self, $type, $id, $context ) {
    my $row = await $self->_functions->row_p(
        'search_index_entity',
        {
            entity_type => $type,
            entity_id   => $id,
            document_id =>
              _document_id_for( { entity_type => $type, entity_id => $id } ),
            indexed_at => $self->clock->now_iso8601,
            config => GPForum::Service::Search::DocumentBuilder->search_config,
        },
        $context
    );

    return $row->{result};
}

# Called after the lexical document committed.
async sub _embed_p ( $self, $type, $id, $context ) {
    my $semantic = $self->semantic;
    return if !$semantic;

    await $semantic->index_entity_p( $type, $id, $context );
    return;
}

sub _index_p ( $self, $type, $id, $context ) {
    return $type eq 'thread'
      ? $self->index_thread_p( $id, $context )
      : $self->index_post_p( $id, $context );
}

sub _rebuild_types ($entity_type) {
    my $type = $entity_type || 'all';
    return @REBUILD_TYPES if $type eq 'all';
    return ($type)        if !none { $_ eq $type } @REBUILD_TYPES;

    GPForum::X::Argument->throw(
        message => "unknown rebuild entity type: $type" );
}

sub _stage_after ( $stage, @types ) {
    my ($position) = grep { $types[$_] eq $stage } 0 .. $#types;

    return $position < $#types ? $types[ $position + 1 ] : 'prune';
}

sub _rebuild_outcome ($result) {
    return 'unchanged'                                 if $result->{skipped};
    return $result->{deleted} ? 'pruned' : 'unchanged' if $result->{removed};

    return 'indexed';
}

# The ids the document builder will index: a post counts only in a live
# thread, or every rebuild would visit, and remove again, the posts of a
# hidden thread.
async sub _live_ids_p ( $self, $type, $after, $context ) {
    my $rows = await $self->_functions->rows_p(
        'search_live_ids',
        {
            entity_type => $type,
            after_id    => $after,
            row_limit   => $self->rebuild_batch_size
        },
        $context
    );

    return map { $_->{entity_id} } @{$rows};
}

# Two phases. The candidates are read from one snapshot, then each is
# indexed again under its document lock: a source restored since the
# snapshot is indexed rather than lost, and only what is still dead goes.
async sub _prune_p ( $self, $type, $context ) {
    my $candidates =
      await $self->_functions->rows_p( 'search_prune_candidates',
        { entity_type => $type }, $context );
    my $pruned = 0;
    for my $row ( @{$candidates} ) {
        my $result =
          await $self->_index_p( $type, $row->{entity_id}, $context );
        $pruned += _rebuild_outcome($result) eq 'pruned' ? 1 : 0;
    }

    return $pruned;
}

async sub _remove_posts_for_thread_p ( $self, $thread_id, $context ) {
    my $removed = 0;
    my $after;
    while (1) {
        my $posts =
          await $self->_thread_post_batch_p( $thread_id, $after, $context );
        last if !@{$posts};

        my $deleted = await $self->_remove_post_batch_p( $thread_id,
            [ map { $_->{post_id} } @{$posts} ], $context );
        last if !defined $deleted;

        $removed += $deleted;
        $after = _next_position( $posts, $self->rebuild_batch_size );
        last if !defined $after;
    }

    return $removed;
}

# One statement per batch (api.search_remove_post_batch): the batch's
# document locks, then the thread read again, then one delete. A thread
# live again by then was restored -- its restore committed before these
# locks were taken, or its reindex waits for them -- so nothing is deleted
# and undef stops the removal.
async sub _remove_post_batch_p ( $self, $thread_id, $post_ids, $context ) {
    my $row = await $self->_functions->row_p( 'search_remove_post_batch',
        { thread_id => $thread_id, post_ids => $post_ids }, $context );

    return $row->{removed};
}

# Up to rebuild_batch_size posts of a thread, by position after $after:
# every post, whatever its state, since a hidden or deleted post may still
# have a document. Position, not post id: the thread's unique position index
# serves the range and the order.
sub _thread_post_batch_p ( $self, $thread_id, $after, $context ) {
    return $self->_functions->rows_p(
        'search_thread_post_batch',
        {
            thread_id      => $thread_id,
            after_position => $after,
            row_limit      => $self->rebuild_batch_size
        },
        $context
    );
}

# Where the next batch starts, or nothing when this one was the last: a
# batch shorter than the batch size has run out of posts.
sub _next_position ( $posts, $batch_size ) {
    return undef if @{$posts} < $batch_size;

    return $posts->[-1]{position};
}

sub _functions ($self) {
    return $self->functions // GPForum::X::Unavailable->throw(
        message => 'search indexing needs the PostgreSQL database' );
}

sub _document_id_for ($document) {
    my $hex = sha1_hex(
        join q{:}, 'search_document',
        $document->{entity_type},
        $document->{entity_id}
    );

    return join q{-}, unpack $UUID_GROUPS, $hex;
}

1;

__END__

=head1 NAME

GPForum::Service::Search::Indexer - Keeps the search_documents projection in step with threads and posts, and rebuilds it.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $indexer = GPForum::Service::Search::Indexer->new( schema => $schema );

    $indexer->index_thread($thread_id);
    $indexer->index_post($post_id);
    $indexer->remove_thread($thread_id);

    my $batch = $indexer->index_thread_posts_batch( $thread_id, $after );
    # next batch from $batch->{next_after}, until it is undef

    my $summary = $indexer->rebuild( { entity_type => 'all' } );
    my $step    = $indexer->rebuild_batch( { entity_type => 'post' } );
    my $lag     = $indexer->observe_lag;

=head1 DESCRIPTION

C<search_documents> is a projection of the canonical rows (ADR 0062): one
document per live thread (visible or locked) and per visible post in such
a thread, with a
weighted C<tsvector> of title (A) and body (B) in the document's language.
The document id is derived from the entity type and id, so it is stable.

Each thread or post is indexed by one call of C<api.search_index_entity>:
the source row is read and the document written or removed under a
transaction-scoped advisory lock on the document's name, so a rebuild and
the live search handler cannot interleave and leave a stale document. A
document whose fields are unchanged is not rewritten. A source that is
gone, deleted or hidden has its document removed. With a C<semantic>
projection, the entity's embedding follows the lexical document.

Each operation is written once, as its promise method on the PostgreSQL
function layer; the blocking method of the same name settles it on the
blocking layer (ADR 0177).

Work that can be large runs in batches of C<rebuild_batch_size> (500) and
never in one transaction: a thread's posts by position, a rebuild by id.
The search handler and the console's rebuild run one batch per outbox
message, so neither holds the dispatcher for long. Removing a thread
removes its own document first, then its posts' documents a batch at a
time, each batch rechecking under its locks that the thread is still dead,
so a removal delivered after a restore deletes nothing the restore indexed.

=head1 SUBROUTINES/METHODS

=head2 observe_lag_p

Takes an optional request context, as every promise method below does,
last. Answers how far search may be behind the forum, from the
outbox, which every search update passes through:
C<< { projection_name => 'search_documents', pending, oldest_pending_at,
lag_seconds, status } >>, C<pending> the outbox messages still pending,
running or failed, C<lag_seconds> the age of the oldest, and C<status>
C<behind> or C<current>.

=head2 index_thread_p

Takes a thread id and indexes it. Returns what the function answers: the
written document; C<< { skipped => 1, entity_type,
entity_id, indexed_at, source_version } >> when the stored document is
already current; or, when the thread is missing or not live,
C<< { ok => 1, removed => 1, deleted, entity_type, entity_id } >>,
C<deleted> being the number of documents removed. It does not touch the
thread's posts.

=head2 index_thread_posts_p

Takes a thread id and reindexes every post of the thread, whatever its
state, batch after batch, each post on its own. Returns
C<< { indexed, pruned, unchanged } >>: posts written, documents removed,
and posts skipped as current or with no document to remove.

=head2 index_thread_posts_batch_p

Takes a thread id and an optional position (the last post done). Reindexes
up to C<rebuild_batch_size> posts after it, as C<index_thread_posts> does.
Returns C<< { indexed, pruned, unchanged, thread_id, next_after } >>,
C<next_after> the position to pass next, or undef when this batch was the
last.

=head2 index_post_p

Takes a post id and indexes it. Returns as
C<index_thread> does; a post is removed when it is missing, not visible,
or in a thread that is not live.

=head2 remove_post_p

Takes a post id and removes its document when the post
is no longer live: missing, not visible, or in a thread that is not live.
A post restored before the removal ran keeps its document. Returns as
L</index_post_p>.

=head2 remove_thread_p

Takes a thread id. Indexes the thread again, which removes its document
when the thread is dead, then removes the documents of its posts a batch
at a time, stopping as soon as the thread is found live again. Returns
C<index_thread>'s result with C<posts_removed>, the number of post
documents deleted. A failure part way leaves removed what went; a retry
removes the rest.

=head2 rebuild_p

Takes a hash reference with C<entity_type>: C<thread>, C<post> or C<all>
(the default). Runs C<rebuild_batch> until it is done: every live thread
and post of that type is indexed again, then documents whose source is
gone, deleted or hidden are pruned. Returns
C<< { ok => 1, entity_type, indexed, pruned, unchanged } >>.

=head2 rebuild_batch_p

Takes a cursor hash reference with C<entity_type>, and optionally C<stage>
(the type being indexed, or C<prune>) and C<after> (the last id done).
Indexes up to C<rebuild_batch_size> live ids of the stage's type, or, at
the C<prune> stage, removes orphaned documents: those of the rebuilt type
and always those of posts, so a dead thread's posts go with it. Each prune
candidate is indexed again under its lock, so one restored since is kept.
Returns C<< { indexed, pruned, unchanged, next } >>, C<next> the cursor
for the following step or undef when the rebuild is done.

=head2 observe_lag, index_thread, index_thread_posts, index_thread_posts_batch, index_post, remove_post, remove_thread, rebuild, rebuild_batch

The blocking twins of the promise methods above: each takes the same
arguments and returns what its promise answers, settled on the blocking
layer (ADR 0177).

=head1 DIAGNOSTICS

C<rebuild> and C<rebuild_batch> throw L<GPForum::X::Argument> C<unknown
rebuild entity type:> or C<unknown rebuild stage:> for a cursor they cannot
follow. Without the function layer every method throws
L<GPForum::X::Unavailable>. Database errors propagate.

=head1 CONFIGURATION AND ENVIRONMENT

None. C<clock> and C<id_service> default to L<GPForum::Service::Clock>
and L<GPForum::Infrastructure::Id>; C<rebuild_batch_size> defaults to 500.

=head1 DEPENDENCIES

L<Const::Fast>, L<Digest::SHA>, L<List::Util>, L<Mojo::Base>,
L<GPForum::Infrastructure::Id>, L<GPForum::Infrastructure::SqlFunction>,
L<GPForum::Service::Clock>, L<GPForum::Service::Search::DocumentBuilder>
(its search configuration), L<GPForum::X::Argument>,
L<GPForum::X::Unavailable>; PostgreSQL's C<api.search_*> functions.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

C<observe_lag> counts every outbox message not yet delivered, not only
those for search, so it is an upper bound.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
