# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use List::Util qw(all none);
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Infrastructure::Id;
use GPForum::Service::Search::DocumentBuilder;
use GPForum::Service::Search::Indexer;
use GPForum::Service::Forum::Viewer;
use GPForum::Service::Search::PermissionEngine;
use GPForum::Service::Search::Searcher;
use GPForum::Test::AnsweringFunctions;
use GPForum::Test::FixedClock;
use GPForum::Test::SearchEventRecorder;
use GPForum::Test::SearchIndexer;
use GPForum::Test::SearchIndexFunctions;
use GPForum::Test::SearchPermissionEngine;
use GPForum::Test::SearchResultSet;
use GPForum::Test::SearchRow;
use GPForum::Test::SearchSchema;
use GPForum::Worker::Handler::SearchIndexing;
use GPForum::X::Argument;

our $VERSION = '0.001';

const my $SEARCH_LIMIT        => 5;
const my $SEARCH_DEFAULT      => 20;
const my $SEARCH_MAX          => 50;
const my $UNDELETE_CALL_INDEX => 3;
const my $REVERSAL_CALL_INDEX => 4;
const my $LONG_THREAD_POSTS   => 5;
const my $SMALL_BATCH         => 2;
const my $TWO_BATCHES         => 2 * $SMALL_BATCH;

# Search binds an id filter only when it is a UUID, as the columns are.
const my $FILTER_CATEGORY => '0b9c1b52-6a43-4c3e-9d47-0f1c2a3b4c5d';
const my $FILTER_AUTHOR   => '7e2f9a10-3c5d-4e6f-8a9b-1c2d3e4f5a6b';
const my $OTHER_AUTHOR    => '5a6b7c8d-9e0f-4a1b-8c2d-3e4f5a6b7c8d';

# More fraction digits than PostgreSQL reads in a timestamp.
const my $LONG_FRACTION => q{9} x 400;

# The indexer's own logic: what it asks the search functions, a batch at a
# time, and what it counts. What a document holds, and when a source is
# live, is the functions' (t/integration/postgres-search-*.t).
my $forum = GPForum::Test::SearchIndexFunctions->new(
    threads => { 'thread-1' => 'visible', 'thread-locked' => 'locked' },
    posts   => {
        'post-1' =>
          { thread_id => 'thread-1', position => 1, state => 'visible' },
    },
);
my $indexer = GPForum::Service::Search::Indexer->new(
    functions => $forum,
    schema    => {},
    clock     => GPForum::Test::FixedClock->new,
);
ok( !$indexer->index_thread('thread-1')->{skipped}, 'a thread is indexed' );
ok(
    $indexer->index_thread('thread-1')->{skipped},
    'and skipped once its document is current'
);
my $asked = $forum->asked('search_index_entity')->[0];
is_deeply(
    [ @{$asked}{qw(entity_type entity_id config)} ],
    [
        'thread', 'thread-1',
        GPForum::Service::Search::DocumentBuilder->search_config
    ],
    'with the search configuration the searcher reads with'
);
like(
    $asked->{document_id},
    GPForum::Infrastructure::Id->uuid_pattern,
    'and a document id derived from the entity'
);

$forum->posts->{'post-1'}{state} = 'hidden';
ok( $indexer->remove_post('post-1')->{removed},
    'a hidden post leaves the index when it is indexed again' );
$forum->posts->{'post-1'}{state} = 'visible';

my $rebuilt = $indexer->rebuild( { entity_type => 'all' } );
is_deeply(
    [ @{$rebuilt}{qw(entity_type indexed pruned unchanged)} ],
    [ 'all', 2, 0, 1 ],
    'a rebuild indexes the live sources and counts the current ones'
);
is_deeply(
    $forum->documents_of('thread'),
    [qw(thread-1 thread-locked)],
    'locked threads included, as the builder has them'
);
$forum->threads->{'thread-locked'} = 'hidden';
is( $indexer->rebuild( { entity_type => 'thread' } )->{pruned},
    1, 'and prunes the document of a source that died' );
my $refused;
try { $indexer->rebuild_batch( { entity_type => 'forum' } ); }
catch ($error) { $refused = GPForum::X::Argument->caught($error); };
ok( $refused, 'an unknown entity type is refused' );

my $search_documents = GPForum::Test::SearchResultSet->new(
    rows => [
        GPForum::Test::SearchRow->new(
            data => {
                entity_type      => 'thread',
                entity_id        => 'thread-1',
                category_id      => $FILTER_CATEGORY,
                author_user_id   => $FILTER_AUTHOR,
                title            => 'Welcome to GPForum',
                title_normalized => 'welcome to gpforum',
                body       => 'A durable <script>x</script> Perl forum post',
                visibility => 'public',
                permission_scope  => 'public',
                rank_score        => 0.8,
                source_created_at => '2026-05-23T11:00:00Z',
                indexed_at        => '2026-05-23T12:00:00Z',
            },
        ),
        GPForum::Test::SearchRow->new(
            data => {
                entity_type       => 'post',
                entity_id         => 'post-denied',
                category_id       => $FILTER_CATEGORY,
                author_user_id    => $OTHER_AUTHOR,
                title             => 'Private GPForum result',
                title_normalized  => 'private gpforum result',
                body              => 'private text must not leak',
                visibility        => 'private',
                permission_scope  => 'private',
                source_created_at => '2026-05-23T10:00:00Z',
                indexed_at        => '2026-05-23T12:00:00Z',
            },
        ),
    ],
);
my $search_schema = GPForum::Test::SearchSchema->new(
    resultsets => { SearchDocument => $search_documents, }, );

my $permission_engine = GPForum::Test::SearchPermissionEngine->new(
    visibility      => [ 'public', 'private' ],
    denied_entities => { 'post-denied' => 1 },
);

# The search runs api.search_ranked and api.search_autocomplete; the double
# answers both with the documents' columns. search_resultset and
# autocomplete_resultset are the queries those functions are compared with
# (t/integration/postgres-search-plan.t), and their conditions are read here.
my $search_functions = GPForum::Test::AnsweringFunctions->new(
    answers => {
        search_ranked =>
          [ map { +{ %{ $_->data } } } @{ $search_documents->rows } ],
        search_autocomplete =>
          [ map { +{ %{ $_->data } } } @{ $search_documents->rows } ],
    }
);
my $searcher = GPForum::Service::Search::Searcher->new(
    functions         => $search_functions,
    schema            => $search_schema,
    permission_engine => $permission_engine,
);
my $search_filters = {
    limit          => $SEARCH_LIMIT,
    category_id    => $FILTER_CATEGORY,
    author_user_id => $FILTER_AUTHOR,
    from           => '2026-05-01',
    to             => '2026-06-01',
};
my $results =
  $searcher->search( { user_id => 'user-1' }, 'forum', $search_filters );

is( scalar @{$results}, 1, 'search filters denied render results' );
$searcher->search_resultset( { user_id => 'user-1' }, 'forum',
    $search_filters );

# This used to assert that the SQL asked for 'private' too, which pinned the
# defect: every logged-in actor was granted every visibility in the WHERE
# clause and the real check ran in Perl AFTER the database applied LIMIT. A
# member whose top matches were other people's private documents got a short
# page, or an empty one while public matches sat below the cut. Measured
# against PostgreSQL before the fix: anonymous 5 results, logged in 0.
is_deeply(
    $search_documents->last_query->{-and}[0]{-and}[0],
    { 'me.visibility' => { -in => [ 'public', 'private' ] } },
    'search applies the permission predicate in the WHERE clause'
);
is( $search_documents->last_query->{-and}[0]{'me.category_id'},
    $FILTER_CATEGORY, 'search applies category filter' );
is( $search_documents->last_query->{-and}[0]{'me.author_user_id'},
    $FILTER_AUTHOR, 'search applies author filter' );
ok(
    _author_qualified( [ keys %{ $search_documents->last_query->{-and}[0] } ] ),
    'search qualifies every column against the joined author'
);
is( $search_documents->last_query->{-and}[1]{'me.source_created_at'}{'>='},
    '2026-05-01', 'search applies lower date bound' );
is_deeply(
    $search_documents->last_query->{-and}[2]{'me.source_created_at'},
    { q{<} => '2026-06-02' },
    'and an upper one that covers the whole of its day'
);

# ADR 0102 for a moved thread. A document keeps the category it was indexed
# under until the outbox reindexes it, and the permission condition reads
# category and space through those columns: they must still be the thread's.
my ( undef, $live_category, $live_space ) =
  @{ $search_documents->last_query->{-and}[0]{-and} };
like(
    ${$live_category},
    qr/FROM [ ] threads .* FROM [ ] posts [ ] live_post/msx,
    q{search reads each document's live thread category, a post's included}
);
like(
    ${$live_category},
    qr/\A COALESCE[(]me[.]category_id [ ] = [ ] .* , [ ] false[)] \z/msx,
    'as a boolean the planner estimates at half, not an equality at 0.5%'
);
is_deeply(
    $live_space,
    { 'category.space_id' => { -ident => 'me.space_id' } },
    q{and that category's space}
);
like( ${ $search_documents->last_query->{-and}[0]{-or}[0] }->[0],
    qr/websearch_to_tsquery/msx, 'search applies PostgreSQL websearch query' );

# The tsquery used to take its configuration from me.language, a column of the
# same row. The planner only accepts an index clause whose other operand holds
# no Var of the indexed relation, so the GIN index on search_vector was
# unusable and every search read every row. The configuration is a bind now.
my $fts_arm = ${ $search_documents->last_query->{-and}[0]{-or}[0] };
like(
    $fts_arm->[0],
    qr/websearch_to_tsquery[(][?]::regconfig, \s* [?][)]/msx,
    'search binds the text-search configuration'
);
unlike( $fts_arm->[0], qr/me[.]language/msx,
    'search does not read the configuration from the row' );
is(
    $fts_arm->[1][1],
    GPForum::Service::Search::DocumentBuilder->search_config,
    'the bound configuration is the one documents are built with'
);

# similarity(...) >= ? is a function compared with a number, not a pg_trgm
# operator, so it could not use the trigram index. % can.
my $trigram_arm = ${ $search_documents->last_query->{-and}[0]{-or}[1] };
like(
    $trigram_arm->[0],
    qr/me[.]title_normalized \s+ % \s+ lower/msx,
    'search matches titles with the indexable trigram operator'
);
unlike( $trigram_arm->[0], qr/similarity/msx,
    'the fuzzy match is not a bare similarity comparison' );
is( $search_documents->last_attrs->{rows},
    $SEARCH_LIMIT, 'search applies limit' );
like( ${ $search_documents->last_attrs->{'+select'}[0] }->[0],
    qr/ts_rank_cd/msx, 'search selects deterministic rank score' );
like( $results->[0]{snippet_html},
    qr/<mark>forum<\/mark>/imsx, 'search highlights snippet safely' );
unlike( $results->[0]{snippet_html},
    qr/<script/msx, 'search snippet strips HTML tags' );

my $autocomplete =
  $searcher->autocomplete( { user_id => 'user-1' }, 'Wel', {} );
is( scalar @{$autocomplete}, 1, 'autocomplete filters denied render results' );
is( $search_functions->asked('search_autocomplete')->[-1]{like_pattern},
    'wel%', 'the autocomplete call binds the normalized title prefix' );
$searcher->autocomplete_resultset( { user_id => 'user-1' }, 'Wel', {} );
is( $search_documents->last_query->{'me.title_normalized'}{-like},
    'wel%', 'autocomplete uses normalized title prefix' );
is_deeply(
    [ @{ $search_documents->last_query->{-and} }[ 1, 2 ] ],
    [ $live_category, $live_space ],
    'autocomplete reads the live category and space too'
);

# A filter is bound only when it is well formed. Each was bound as it came:
# from=garbage reached PostgreSQL, which refused it, and the log line that
# reported the degraded page quoted what the visitor had typed.
$searcher->search_resultset(
    { user_id => 'user-1' },
    'forum',
    {
        author_user_id => q{1' OR '1'='1},
        category_id    => 'category-1',
        from           => 'garbage',
        to             => '2026-02-30',
    }
);
is_deeply(
    [ sort keys %{ $search_documents->last_query } ],
    [qw(-and -or)],
    'malformed filters bind nothing: the query is the permission and the match'
);

# Where the reader asked to look is the document's entity_type; any other
# word is both.
$searcher->search_resultset( { user_id => 'user-1' },
    'forum', { scope => 'threads' } );
is( $search_documents->last_query->{'me.entity_type'},
    'thread', 'a thread scope binds the thread documents' );
$searcher->search_resultset( { user_id => 'user-1' },
    'forum', { scope => 'posts' } );
is( $search_documents->last_query->{'me.entity_type'},
    'post', 'a post scope binds the post documents' );
$searcher->search_resultset( { user_id => 'user-1' },
    'forum', { scope => 'everything' } );
ok( !exists $search_documents->last_query->{'me.entity_type'},
    'and any other scope binds no entity type' );
is(
    $searcher->ranked_call( undef, 'forum', { scope => 'posts' } )
      ->[1]{entity_type},
    'post',
    'the function call carries the scope as its entity type'
);
is( $searcher->ranked_call( undef, 'forum', {} )->[1]{entity_type},
    undef, 'and none for the default' );
is_deeply(
    _date_conditions(
        $searcher, $search_documents,
        { from => '2026-05-01T10:00:00+02:00', to => '2026-05-01T10:30:00Z' }
    ),
    [
        { q{>=} => '2026-05-01T08:00:00Z' }, { q{<=} => '2026-05-01T10:30:00Z' }
    ],
    'an RFC 3339 time is bound as the instant it names'
);
is_deeply(
    _date_conditions( $searcher, $search_documents, { to => '2024-02-28' } ),
    [ { q{<} => '2024-02-29' } ],
    q{a day's end is the next day's start, in a leap year too}
);
is_deeply(
    _date_conditions(
        $searcher, $search_documents,
        { from => '0000-01-01', to => '2026-05-01T25:00:00Z' }
    ),
    [],
    'year 0 and hour 25 are not dates'
);

# Time::Local, under Mojo::Date, reads a year below 1000 as another: 0500
# would have been bound as 2400.
is_deeply(
    _date_conditions(
        $searcher, $search_documents,
        { from => '0500-01-01T00:00:00Z', to => '1969-12-31T23:59:59Z' }
    ),
    [],
    'an instant before 1970 is not read as another year'
);

# Mojo::Date takes an offset of any length. A hundred billion hours put the
# instant in year 11409972, past PostgreSQL's range, so the search failed
# there as the garbage had; RFC 3339's offset is at most 23:59.
is_deeply(
    _date_conditions(
        $searcher,
        $search_documents,
        {
            from => '2026-05-01T10:00:00-99999999999:00',
            to   => '2026-05-01T10:00:00+24:00',
        }
    ),
    [],
    'an offset RFC 3339 does not allow is not a time'
);
is_deeply(
    _date_conditions(
        $searcher, $search_documents,
        { from => '2026-05-01T10:00:00.25-23:59' }
    ),
    [ { q{>=} => '2026-05-02T09:59:00.25Z' } ],
    'the largest offset it does allow is still read'
);

# An instant a hair after 1970's first second parses to an epoch Perl prints
# as 1e-08, which Mojo::Date->new does not read as a date: the bound was
# rendered from no epoch, and what the visitor typed put two warnings in the
# log.
my @instant_warnings;
{
    local $SIG{__WARN__} = sub { push @instant_warnings, @_; return; };
    is_deeply(
        _date_conditions(
            $searcher, $search_documents,
            { from => '1970-01-01T00:00:00.00000001Z' }
        ),
        [ { q{>=} => '1970-01-01T00:00:00Z' } ],
        'an instant just after the epoch is bound from its own epoch'
    );
}
is_deeply( \@instant_warnings, [], 'and warns nothing' );

# A time was rendered from the epoch it parsed to, fraction and all, and a
# float holds fifteen digits: a typed microsecond came back as ten, and a
# second a hair short of the next as the next. The fraction is the one typed,
# to the microsecond a timestamp holds; PostgreSQL refuses hundreds of digits.
is_deeply(
    _date_conditions(
        $searcher,
        $search_documents,
        {
            from => '2026-05-01T10:00:00.123456Z',
            to   => '2026-05-01T10:00:59.' . $LONG_FRACTION . '+00:00',
        }
    ),
    [
        { q{>=} => '2026-05-01T10:00:00.123456Z' },
        { q{<=} => '2026-05-01T10:00:59.999999Z' },
    ],
    'a time is bound to the microsecond it names, however many digits it has'
);

# A time with no offset was bound as UTC, while a day is read in the
# session's time zone -- from=2026-05-01 and from=2026-05-01T00:00:00 named
# different instants -- and PostgreSQL had read the time in the session's
# zone too, before it was checked here. It is bound with no offset still.
is_deeply(
    _date_conditions(
        $searcher, $search_documents,
        { from => '2026-05-01T00:00:00', to => '2026-05-01 10:00:00.50' }
    ),
    [
        { q{>=} => '2026-05-01T00:00:00' },
        { q{<=} => '2026-05-01T10:00:00.5' },
    ],
    q{a time with no offset is read in the session's time zone, as a day is}
);

$searcher->search_resultset( { user_id => 'user-1' },
    'forum', { limit => 10_000 } );
is( $search_documents->last_attrs->{rows},
    $SEARCH_MAX, 'search clamps excessive limit' );
$searcher->autocomplete( { user_id => 'user-1' }, 'Wel', { limit => 10_000 } );
is( $search_functions->asked('search_autocomplete')->[-1]{row_limit},
    $SEARCH_MAX, 'autocomplete clamps excessive limit' );
$searcher->autocomplete( { user_id => 'user-1' }, 'Wel', { limit => 0 } );
is( $search_functions->asked('search_autocomplete')->[-1]{row_limit},
    $SEARCH_DEFAULT, 'autocomplete defaults invalid limit' );

my $real_permission = GPForum::Service::Search::PermissionEngine->new;
is_deeply( [ $real_permission->search_visibility_for( undef, {} ) ],
    ['public'], 'anonymous search scope is public only' );
ok(
    !$real_permission->permits(
        undef, 'search.view',
        { visibility => 'members', entity_type => 'thread' }, {}
    ),
    'anonymous user cannot render members-only search result'
);
ok(
    $real_permission->permits(
        {
            viewer => GPForum::Service::Forum::Viewer->new(
                member  => 1,
                user_id => 'user-1'
            )
        },
        'search.view',
        {
            author_user_id      => 'user-1',
            category_visibility => 'public',
            space_visibility    => 'public',
            visibility          => 'private',
        },
        {},
    ),
    'private author can render own search result'
);

# ADR 0102: a document's category and space are judged too. A public thread
# in a private category is not a public search result.
ok(
    !$real_permission->permits(
        undef,
        'search.view',
        {
            category_visibility => 'private',
            space_visibility    => 'public',
            visibility          => 'public',
        },
        {},
    ),
    'a public document in a private category is not shown to anonymous readers'
);
is_deeply(
    $real_permission->search_condition(undef)->{-and},
    [
        { 'space.visibility'    => { -in => ['public'] } },
        { 'category.visibility' => { -in => ['public'] } },
        { 'me.visibility'       => { -in => ['public'] } },
    ],
    'and the SQL judges space, category and document for them'
);

my $fake_indexer = GPForum::Test::SearchIndexer->new;
my $handler =
  GPForum::Worker::Handler::SearchIndexing->new( indexer => $fake_indexer, );
my $task = $handler->handle(
    {
        event_id       => 'event-1',
        event_type     => 'post.created',
        aggregate_type => 'post',
        aggregate_id   => 'post-1',
    }
);

is( $fake_indexer->calls->[0][0], 'post',   'worker calls search indexer' );
is( $fake_indexer->calls->[0][1], 'post-1', 'worker passes aggregate id' );
ok( $task->{indexed}{ok}, 'worker records indexer result' );

my $hide_task = $handler->handle(
    {
        event_id       => 'event-2',
        event_type     => 'post.hidden',
        aggregate_type => 'post',
        aggregate_id   => 'post-1',
    }
);
is( $hide_task->{action}, 'search.remove', 'hide event removes document' );
is( $fake_indexer->calls->[1][0],
    'remove_post', 'hide event calls remove_post' );

my $restore_task = $handler->handle(
    {
        event_id       => 'event-3',
        event_type     => 'post.restored',
        aggregate_type => 'post',
        aggregate_id   => 'post-1',
    }
);
is( $restore_task->{action},      'search.index', 'restore event reindexes' );
is( $fake_indexer->calls->[2][0], 'post', 'restore event calls index_post' );

my $undelete_task = $handler->handle(
    {
        event_id       => 'event-3b',
        event_type     => 'post.undeleted',
        aggregate_type => 'post',
        aggregate_id   => 'post-1',
    }
);
is( $undelete_task->{action}, 'search.index', 'undelete event reindexes' );
is( $fake_indexer->calls->[$UNDELETE_CALL_INDEX][0],
    'post', 'undelete event calls index_post' );

my $reversal_task = $handler->handle(
    {
        event_id       => 'event-4',
        event_type     => 'moderation_action.reversed',
        aggregate_type => 'moderation_action',
        aggregate_id   => 'action-1',
        domain_payload => {
            target_type => 'post',
            target_id   => 'post-1',
        },
    }
);
ok( $reversal_task->{indexed}{ok}, 'reversal event re-evaluates target index' );
is( $fake_indexer->calls->[$REVERSAL_CALL_INDEX][0],
    'post', 'reversal event indexes target post' );

my $thread_delete_task = $handler->handle(
    {
        event_id       => 'event-5',
        event_type     => 'thread.deleted',
        aggregate_type => 'thread',
        aggregate_id   => 'thread-1',
    }
);
is( $thread_delete_task->{action},
    'search.remove', 'thread delete event removes document' );
ok( _indexer_called( $fake_indexer->calls, 'remove_thread', 'thread-1' ),
    'thread delete event calls remove_thread' );

my $thread_hide_task = $handler->handle(
    {
        event_id       => 'event-6',
        event_type     => 'thread.hidden',
        aggregate_type => 'thread',
        aggregate_id   => 'thread-1',
    }
);
is( $thread_hide_task->{action},
    'search.remove', 'thread hide event removes document' );
ok( _indexer_called( $fake_indexer->calls, 'remove_thread', 'thread-1' ),
    'thread hide event calls remove_thread' );

my $thread_restore_task = $handler->handle(
    {
        event_id       => 'event-7',
        event_type     => 'thread.restored',
        aggregate_type => 'thread',
        aggregate_id   => 'thread-1',
    }
);
is( $thread_restore_task->{action},
    'search.index', 'thread restore event reindexes' );
ok( _indexer_called( $fake_indexer->calls, 'thread', 'thread-1' ),
    'thread restore event calls index_thread' );
ok( _indexer_called( $fake_indexer->calls, 'thread_posts', 'thread-1' ),
    'thread restore event reindexes posts in the thread' );

my $thread_undelete_task = $handler->handle(
    {
        event_id       => 'event-7b',
        event_type     => 'thread.undeleted',
        aggregate_type => 'thread',
        aggregate_id   => 'thread-1',
    }
);
is( $thread_undelete_task->{action},
    'search.index', 'thread undelete event reindexes' );
ok( _indexer_called( $fake_indexer->calls, 'thread', 'thread-1' ),
    'thread undelete event calls index_thread' );
ok(
    _indexer_called( $fake_indexer->calls, 'thread_posts', 'thread-1' ),
    'thread undelete event reindexes posts in the thread'
);

# A post's document carries its thread's title (weighted A) and category, so
# renaming or moving a thread must recompute its posts too: otherwise replies
# still match the old title, and a search inside the new category misses them
# while the old category keeps returning them.
for my $case (
    [ 'thread.updated', 'thread-renamed', 'a renamed thread' ],
    [ 'thread.moved',   'thread-moved',   'a moved thread' ],
  )
{
    my ( $event_type, $thread_id, $label ) = @{$case};
    $handler->handle(
        {
            aggregate_id   => $thread_id,
            aggregate_type => 'thread',
            event_id       => "event-$thread_id",
            event_type     => $event_type,
        }
    );
    ok( _indexer_called( $fake_indexer->calls, 'thread_posts', $thread_id ),
        "$label reindexes the posts in it" );
}

# A thread's posts are removed, and indexed again, a batch at a time. The
# removal was one transaction holding an advisory lock per post, and a thread
# of a few thousand posts could not get them from PostgreSQL's shared lock
# table: the removal was retried until it was dead-lettered, and the posts of
# the hidden thread stayed searchable.
my $long_forum = GPForum::Test::SearchIndexFunctions->new(
    threads => { 'thread-1' => 'visible', 'thread-long' => 'visible' },
    posts   => {
        'post-1' =>
          { thread_id => 'thread-1', position => 1, state => 'visible' },
        map {
            (
                "long-post-$_" => {
                    thread_id => 'thread-long',
                    position  => $_,
                    state     => 'visible'
                }
            )
        } 1 .. $LONG_THREAD_POSTS
    },
);
my $long_indexer = GPForum::Service::Search::Indexer->new(
    clock              => GPForum::Test::FixedClock->new,
    functions          => $long_forum,
    rebuild_batch_size => $SMALL_BATCH,
    schema             => {},
);
$long_indexer->index_thread('thread-long');
$long_indexer->index_post('post-1');
is( $long_indexer->index_thread_posts('thread-long')->{indexed},
    $LONG_THREAD_POSTS, 'a thread\'s posts are indexed, a batch at a time' );
is_deeply(
    [
        map {
            $long_indexer->index_thread_posts_batch( 'thread-long', $_ )
              ->{next_after}
        } ( undef, $SMALL_BATCH, $TWO_BATCHES )
    ],
    [ $SMALL_BATCH, $TWO_BATCHES, undef ],
    'a full batch says at which position the next starts, the last says none'
);

$long_forum->posts->{'long-post-3'}{state} = 'hidden';
is_deeply(
    [
        @{
            $long_indexer->index_thread_posts_batch( 'thread-long',
                $SMALL_BATCH )
        }{qw(indexed pruned unchanged)}
    ],
    [ 0, 1, 1 ],
    'a batch removes the document of a post that died'
);

$long_forum->threads->{'thread-long'} = 'hidden';
my $batches      = @{ $long_forum->asked('search_remove_post_batch') };
my $long_removed = $long_indexer->remove_thread('thread-long');
is_deeply(
    [
        map { $_->{post_ids} }
          @{ $long_forum->asked('search_remove_post_batch') }
          [ $batches .. $#{ $long_forum->asked('search_remove_post_batch') } ]
    ],
    [
        [qw(long-post-1 long-post-2)], [qw(long-post-3 long-post-4)],
        ['long-post-5']
    ],
    'each batch at most the batch size, in position order, dead posts included'
);
is(
    $long_removed->{posts_removed},
    $LONG_THREAD_POSTS - 1,
    'the documents removed are counted, not the one already gone'
);
ok( !_long_documents($long_forum),
    'and no document of the thread or its posts is left' );
is_deeply( $long_forum->documents_of('post'),
    ['post-1'], 'another thread\'s posts keep theirs' );

# Two dispatchers can deliver a hide and the restore after it in either
# order. A removal that came second deleted what the restore had just
# indexed; it now reads the thread again under its locks and stops.
$long_forum->threads->{'thread-long'} = 'visible';
$long_indexer->index_thread('thread-long');
$long_indexer->index_thread_posts('thread-long');
my $restored_documents = _long_documents($long_forum);
$batches = @{ $long_forum->asked('search_remove_post_batch') };
my $late_removal = $long_indexer->remove_thread('thread-long');
is( $late_removal->{posts_removed},
    0, 'a removal delivered after the restore removes no post document' );
is( _long_documents($long_forum),
    $restored_documents, 'and the restored thread keeps every document' );
is( @{ $long_forum->asked('search_remove_post_batch') } - $batches,
    1, 'it stops at the first batch that finds the thread live' );

# Renaming, moving or restoring a thread re-derives its posts one batch per
# outbox message: the first with the event, each next one recorded as its own
# event. All of them in the one message held the dispatcher -- and every
# reply's realtime push, notifications and cache purge behind it -- for as
# long as a large thread took.
my $batching_indexer = GPForum::Test::SearchIndexer->new(
    batch_size   => $SMALL_BATCH,
    thread_posts => { 'thread-long' => $LONG_THREAD_POSTS },
);
my $recorder = GPForum::Test::SearchEventRecorder->new;
my $batching = GPForum::Worker::Handler::SearchIndexing->new(
    indexer  => $batching_indexer,
    recorder => $recorder,
);
my %moved = (
    actor_id       => 'user-1',
    aggregate_id   => 'thread-long',
    aggregate_type => 'thread',
    correlation_id => 'correlation-1',
    event_id       => 'event-moved',
    event_type     => 'thread.moved',
);
is( $batching->handle( \%moved )->{indexed}{posts_indexed}{indexed},
    $SMALL_BATCH, 'a moved thread indexes one batch of its posts' );
is( scalar @{ $recorder->events }, 1, 'and records one event for the next' );
is_deeply(
    _event_fields( $recorder->events->[0] ),
    {
        aggregate_id    => 'thread-long',
        aggregate_type  => 'thread',
        causation_id    => 'event-moved',
        correlation_id  => 'correlation-1',
        event_type      => 'search.thread_posts_requested',
        idempotency_key => "search.thread_posts:event-moved:$SMALL_BATCH",
        payload         => {
            after          => $SMALL_BATCH,
            cause_event_id => 'event-moved',
            thread_id      => 'thread-long',
        },
    },
    'its own event on the thread, naming where the next batch starts'
);
$batching->handle( \%moved );
is( scalar @{ $recorder->events }, 1, 'a retried event records nothing new' );

_deliver_chain( $batching, $recorder );
is_deeply(
    [
        map  { $_->[2] }
        grep { $_->[0] eq 'thread_posts' } @{ $batching_indexer->calls }
    ],
    [ undef, undef, $SMALL_BATCH, $TWO_BATCHES ],
    'each batch starts where the one before ended'
);
is( scalar @{ $recorder->events },
    2, 'until the thread is done, when nothing more is recorded' );
is_deeply(
    [ @{ $recorder->events->[1] }{qw(idempotency_key causation_id)} ],
    [ "search.thread_posts:event-moved:$TWO_BATCHES", 'recorded-1' ],
    'every link keyed by the event that started the chain'
);
$batching->handle( $recorder->events->[0] );
is( scalar @{ $recorder->events }, 2, 'a retried batch records nothing new' );
ok(
    (
        none { $_->{event_type} eq 'search.rebuild_requested' }
          @{ $recorder->events }
    ),
    'and none is a console rebuild step: the last rebuild shown stays as it was'
);

$batching->handle(
    {
        aggregate_id   => 'action-2',
        aggregate_type => 'moderation_action',
        domain_payload => {
            target_id   => 'thread-long',
            target_type => 'thread',
        },
        event_id   => 'event-reversed',
        event_type => 'moderation_action.reversed',
    }
);
is(
    $recorder->events->[-1]{idempotency_key},
    "search.thread_posts:event-reversed:$SMALL_BATCH",
    'a reversed thread moderation starts a chain of its own'
);

done_testing();

# The conditions on source_created_at a search with these filters binds.
sub _date_conditions {
    my ( $search_service, $documents, $filters ) = @_;

    $search_service->search_resultset( { user_id => 'user-1' },
        'forum', $filters );
    my $query = $documents->last_query;
    return [] if exists $query->{-or};

    my ( undef, @bounds ) = @{ $query->{-and} };

    return [ map { $_->{'me.source_created_at'} } @bounds ];
}

sub _long_documents {
    my ($index) = @_;

    return scalar grep { /long/msx } keys %{ $index->documents };
}

sub _event_fields {
    my ($event) = @_;

    return {
        map { $_ => $event->{$_} }
          qw(aggregate_id aggregate_type causation_id correlation_id
          event_type idempotency_key payload)
    };
}

# Every recorded event, delivered once and in order, as the outbox would,
# including those recorded along the way.
sub _deliver_chain {
    my ( $indexing, $recorded ) = @_;

    my $delivered = 0;
    while ( $delivered < @{ $recorded->events } ) {
        $indexing->handle( $recorded->events->[$delivered] );
        $delivered++;
    }

    return $delivered;
}

sub _indexer_called {
    my ( $calls, $name, $id ) = @_;

    return grep { _call_is( $_, $name, $id ) } @{$calls};
}

sub _call_is {
    my ( $call, $name, $id ) = @_;

    if ( $call->[0] ne $name ) {
        return 0;
    }
    if ( $call->[1] ne $id ) {
        return 0;
    }

    return 1;
}

sub _author_qualified {
    my ($keys) = @_;

    return all { _is_qualified_column($_) } @{$keys};
}

sub _is_qualified_column {
    my ($name) = @_;

    if ( $name =~ /\A (?:-|me[.]) /msx ) {
        return 1;
    }

    return 0;
}

1;
