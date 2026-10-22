# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Service::Forum::Viewer;
use GPForum::Service::Search::Indexer;
use GPForum::Service::Search::PermissionEngine;
use GPForum::Service::Search::Searcher;
use GPForum::Test::FixedClock;
use GPForum::Test::PgDatabase;

our $VERSION = '0.001';

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'set GPFORUM_TEST_DSN to search hidden content';
}

# A hide or a delete leaves the index through the outbox, a while after it
# was made. Until then search answered from the document alone, so a hidden
# thread, a hidden post or a deleted one stayed findable, title and body,
# for as long as the outbox took. Both search and the autocomplete now read
# the thread and the post as they are when the query runs: whatever is no
# longer visible is not shown, whether its document has gone yet or not.
my $database = GPForum::Test::PgDatabase->fresh( seed => 1 );
my $schema   = $database->schema;
my $dbh      = $database->dbh;
$dbh->do(q{SET client_min_messages = 'warning'});
my $indexer = GPForum::Service::Search::Indexer->new(
    schema => $schema,
    clock  => GPForum::Test::FixedClock->new,
);

my $thread_id =
  $dbh->selectrow_array( q{SELECT t.thread_id FROM threads t}
      . q{ WHERE t.deleted_at IS NULL AND t.moderation_state = 'visible'}
      . q{ AND (SELECT count(*) FROM posts p WHERE p.thread_id = t.thread_id}
      . q{ AND p.deleted_at IS NULL AND p.moderation_state = 'visible') >= 2}
      . q{ ORDER BY t.thread_id LIMIT 1} );
ok( $thread_id, 'the seed has a visible thread with two visible posts' );
$dbh->do(
    q{UPDATE threads SET title = 'Quokkaprobe hidden content',}
      . q{ version = version + 1 WHERE thread_id = ?},
    undef, $thread_id
);
$indexer->index_thread($thread_id);
$indexer->index_thread_posts($thread_id);
my ( $first_post, $second_post ) = @{
    $dbh->selectcol_arrayref(
        q{SELECT post_id FROM posts WHERE thread_id = ?}
          . q{ AND deleted_at IS NULL AND moderation_state = 'visible'}
          . q{ ORDER BY position LIMIT 2},
        undef, $thread_id
    )
};

my $actor = {
    viewer => GPForum::Service::Forum::Viewer->new(
        member      => 1,
        global_read => 1,
    )
};
my %searchers = (
    function => GPForum::Service::Search::Searcher->new(
        schema            => $schema,
        permission_engine => GPForum::Service::Search::PermissionEngine->new,
    ),
    resultset => GPForum::Service::Search::Searcher->new(
        schema            => $schema,
        permission_engine => GPForum::Service::Search::PermissionEngine->new,
        functions         => undef,
    ),
);

my $documents = _documents();
ok( $documents->{"thread:$thread_id"}, 'the thread is found' );
ok( $documents->{"post:$first_post"},  'so is its first post' );
ok( $documents->{"post:$second_post"}, 'and its second' );
_suggested( 1, 'the autocomplete offers the thread' );

_state( 'posts', 'moderation_state', 'hidden', 'post_id', $second_post );
$documents = _documents();
ok( !$documents->{"post:$second_post"}, 'a hidden post is not found' );
ok( $documents->{"post:$first_post"},   'the post beside it still is' );
_state( 'posts', 'moderation_state', 'visible', 'post_id', $second_post );

$dbh->do( q{UPDATE posts SET deleted_at = now() WHERE post_id = ?},
    undef, $second_post );
ok( !_documents()->{"post:$second_post"}, 'a deleted post is not found' );
$dbh->do( q{UPDATE posts SET deleted_at = NULL WHERE post_id = ?},
    undef, $second_post );

_state( 'threads', 'moderation_state', 'hidden', 'thread_id', $thread_id );
is_deeply( _documents(), {},
    'a hidden thread is not found, nor any of its posts' );
_suggested( 0, 'nor offered by the autocomplete' );
_state( 'threads', 'moderation_state', 'locked', 'thread_id', $thread_id );
ok( _documents()->{"thread:$thread_id"}, 'a locked thread is still found' );
_state( 'threads', 'moderation_state', 'visible', 'thread_id', $thread_id );

$dbh->do( q{UPDATE threads SET deleted_at = now() WHERE thread_id = ?},
    undef, $thread_id );
is_deeply( _documents(), {},
    'a deleted thread is not found, nor any of its posts' );
_suggested( 0, 'nor offered by the autocomplete once deleted' );

$schema->storage->disconnect;
undef $database;

done_testing();

# The documents found for the probe word, each searcher the same, keyed
# entity_type:entity_id.
sub _documents {
    my %found;
    for my $name ( sort keys %searchers ) {
        my %these = map { ( "$_->{entity_type}:$_->{entity_id}" => 1 ) }
          @{ $searchers{$name}->search( $actor, 'Quokkaprobe', {} ) };
        $found{$name} = \%these;
    }
    is_deeply( $found{resultset}, $found{function},
        'the function and the resultset agree' );

    return $found{function};
}

sub _suggested ( $expected, $name ) {
    for my $searcher_name ( sort keys %searchers ) {
        my $offered =
          grep { ( $_->{entity_id} // q{} ) eq $thread_id }
          @{ $searchers{$searcher_name}
              ->autocomplete( $actor, 'quokkaprobe', {} ) };
        is( $offered, $expected, "$name ($searcher_name)" );
    }

    return;
}

sub _state ( $table, $column, $value, $key, $id ) {
    $dbh->do( "UPDATE $table SET $column = ? WHERE $key = ?",
        undef, $value, $id );

    return;
}

1;
