# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Carp qw(croak);
use Const::Fast;
use English       qw(-no_match_vars);
use JSON::MaybeXS qw(decode_json encode_json);
use POSIX         qw(_exit);
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Benchmark::SeedDataset qw(seed_id);
use GPForum::Infrastructure::Id;
use GPForum::Service::Community::MentionStore;
use GPForum::Service::Forum::CategoryReader;
use GPForum::Service::Forum::PostComposer;
use GPForum::Service::Forum::PostReader;
use GPForum::Service::Forum::PostStore;
use GPForum::Service::Forum::PostingWorkflow;
use GPForum::Service::Forum::ThreadComposer;
use GPForum::Service::Forum::ThreadDetailReader;
use GPForum::Service::Forum::ThreadStore;
use GPForum::Service::Forum::Viewer;
use GPForum::Service::Moderation::ActionStore;
use GPForum::Service::Operations::CommandIdempotency;
use GPForum::Test::PgDatabase;
use GPForum::Test::PostgresHarness;

our $VERSION = '0.001';

const my $RACERS             => 4;
const my $LOCK_TIMEOUT_MS    => 10_000;
const my $BLOCK_POLLS        => 200;
const my $BLOCK_POLL_SECONDS => 0.05;
const my $HOLD_THREAD_SQL =>
  'SELECT 1 FROM threads WHERE thread_id = ? FOR NO KEY UPDATE';
const my $LOCK_WAITERS_SQL => join q{ },
  'SELECT count(*) FROM pg_stat_activity',
  q{WHERE datname = current_database() AND wait_event_type = 'Lock'};
const my $ROW_WAIT_SQL => join q{ },
  'SELECT count(*) FROM pg_stat_activity',
  'WHERE ? = ANY (pg_blocking_pids(pid))',
  q{AND wait_event IN ('transactionid', 'tuple')};
const my $POSITIONS_SQL => join q{ },
  'SELECT position FROM posts',
  'WHERE thread_id = ? AND position > ? ORDER BY position';
const my $LAST_POSITION_SQL =>
  'SELECT COALESCE(MAX(position), 0) FROM posts WHERE thread_id = ?';
const my $COUNT_SQL =>
  'SELECT reply_count FROM thread_counters WHERE thread_id = ?';

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'set GPFORUM_TEST_DSN to race the reply function';
}

# ADR 0111's rules for a reply, held for api.forum_create_reply_v1 as
# t/integration/postgres-concurrency.t holds them for the Perl store: the
# thread row taken FOR NO KEY UPDATE hands out positions in commit order, a
# reply that waited on a moderator's lock or an author's delete reads the
# thread as committed and is refused, the lock does not hold a reader's
# first mark-read insert, and a reply queues on the counter row a delete
# holds and both are counted. Each reply is the workflow's one call, from a
# process of its own.
local $ENV{GPFORUM_DATABASE_LOCK_TIMEOUT_MS} = $LOCK_TIMEOUT_MS;
my $database = GPForum::Test::PgDatabase->fresh( seed => 1 );
local $ENV{GPFORUM_DATABASE_DSN} = $database->dsn;
my $dbh    = $database->dbh;
my $thread = seed_id( thread => 1 );
my $member = seed_id( user   => 2 );
ok( _workflow( GPForum::Test::PostgresHarness::connect_schema() )->functions,
    'the workflow replies through its function' );

subtest 'concurrent replies take the next positions, in commit order' => sub {
    my ($before) = $dbh->selectrow_array( $LAST_POSITION_SQL, undef, $thread );
    my $holder = GPForum::Test::PostgresHarness::connect_dbi( $database->dsn );
    $holder->begin_work;
    $holder->selectrow_array( $HOLD_THREAD_SQL, undef, $thread );

    my @replies = map { _spawn( "concurrent reply $_", $thread ) } 1 .. $RACERS;
    ok(
        _await( $LOCK_WAITERS_SQL, $RACERS ),
        'every reply queues on the thread row lock'
    );
    $holder->rollback;
    $holder->disconnect;

    my @outcomes = map { _collect($_) } @replies;
    is( scalar( grep { $_->{ok} } @outcomes ),
        $RACERS, 'every reply is stored' );
    is_deeply(
        $dbh->selectcol_arrayref( $POSITIONS_SQL, undef, $thread, $before ),
        [ map { $before + $_ } 1 .. $RACERS ],
        'each took the next position'
    );

    for my $outcome (@outcomes) {
        is(
            scalar $dbh->selectrow_array(
                q{SELECT count(*) FROM event_log WHERE aggregate_id = ?}
                  . q{ AND event_type = 'post.created'},
                undef,
                $outcome->{post_id}
            ),
            1,
            'and recorded one post.created'
        );
    }
};

subtest 'a reply waits on a moderator\'s lock and is refused' => sub {
    my $moderator = GPForum::Test::PostgresHarness::connect_schema();
    $moderator->txn_begin;
    ok(
        GPForum::Service::Moderation::ActionStore->new( schema => $moderator )
          ->lock_thread(
            {
                actor_user_id => seed_id( user => 1 ),
                command_id    => GPForum::Infrastructure::Id->new->uuid,
                reason        => 'racing a reply',
                thread_id     => $thread,
            }
          )->{ok},
        'a moderator locks the thread, not yet committed'
    );
    my $pid   = _pid($moderator);
    my $reply = _spawn( 'reply racing a lock', $thread );
    ok( _await( $ROW_WAIT_SQL, 1, $pid ), 'the reply waits on the lock' );
    $moderator->txn_commit;
    $moderator->storage->disconnect;

    my $outcome = _collect($reply);
    is_deeply(
        [ @{$outcome}{qw(status error)} ],
        [ 'forbidden', 'thread is locked' ],
        'it reads the lock as committed and is refused'
    );
    is(
        _response( $outcome->{command_id} )->{error},
        'thread is locked',
        'and the command log keeps the refusal'
    );
    is( _posts_by_body('reply racing a lock'),
        0, 'with no post in the locked thread' );

    $dbh->do(
        q{UPDATE threads SET moderation_state = 'visible', locked_at = NULL}
          . q{ WHERE thread_id = ?},
        undef, $thread
    );
};

subtest 'a reply waits on its thread\'s delete and is refused' => sub {
    my $other = $dbh->selectrow_hashref(
        q{SELECT thread_id, author_user_id, category_id FROM threads}
          . q{ WHERE author_user_id <> ? AND deleted_at IS NULL}
          . q{ AND locked_at IS NULL AND thread_id <> ? ORDER BY thread_id}
          . q{ LIMIT 1},
        undef, $member, $thread
    );
    my $author = GPForum::Test::PostgresHarness::connect_schema();
    $author->txn_begin;
    ok(
        GPForum::Service::Forum::ThreadStore->new( schema => $author )
          ->delete_thread(
            {
                idempotency_key => GPForum::Infrastructure::Id->new->uuid,
                thread          => {
                    category_id => $other->{category_id},
                    deleted_by  => $other->{author_user_id},
                    thread_id   => $other->{thread_id},
                },
            }
          )->{ok},
        'its author deletes the thread, not yet committed'
    );
    my $pid   = _pid($author);
    my $reply = _spawn( 'reply racing a delete', $other->{thread_id} );
    ok( _await( $ROW_WAIT_SQL, 1, $pid ), 'the reply waits on the delete' );
    $author->txn_commit;
    $author->storage->disconnect;

    my $outcome = _collect($reply);
    is_deeply(
        [ @{$outcome}{qw(status error)} ],
        [ 'not_found', 'thread not found' ],
        'it reads the delete as committed and is refused'
    );
    is( _posts_by_body('reply racing a delete'),
        0, 'with no post in the deleted thread' );
};

subtest 'the reply\'s lock does not hold a first mark-read insert' => sub {
    my $holder = GPForum::Test::PostgresHarness::connect_schema();
    $holder->txn_begin;
    ok(
        _workflow($holder)
          ->create_reply( _input( 'a reply in flight', $thread ) )->{ok},
        'a reply in flight, inside a transaction, holds the thread'
    );
    my $reader = GPForum::Test::PostgresHarness::connect_dbi( $database->dsn );
    my $next_reply = 1;
    try {
        $reader->selectrow_array( "$HOLD_THREAD_SQL NOWAIT", undef, $thread );
    }
    catch ($error) { $next_reply = 0; };
    ok( !$next_reply, 'from the next reply' );

    $reader->begin_work;
    $reader->do(q{SET LOCAL lock_timeout = '200ms'});
    $reader->do(
        'DELETE FROM thread_read_state WHERE user_id = ? AND thread_id = ?',
        undef, $member, $thread );
    my $inserted = 1;
    try {
        $reader->do(
            q{INSERT INTO thread_read_state (user_id, thread_id,}
              . q{ last_read_position) VALUES (?, ?, 1)},
            undef, $member, $thread
        );
    }
    catch ($error) { $inserted = 0; };
    ok( $inserted, 'and a first mark-read insert does not wait for it' );
    $reader->rollback;
    $reader->disconnect;
    $holder->txn_rollback;
    $holder->storage->disconnect;
};

subtest 'a reply queues on the counter row a delete holds' => sub {
    my $post = $dbh->selectrow_hashref(
        q{SELECT post_id, thread_id, author_user_id FROM posts}
          . q{ WHERE thread_id = ? AND position > 1 AND deleted_at IS NULL}
          . q{ ORDER BY position DESC LIMIT 1},
        undef, $thread
    );
    my ($before) = $dbh->selectrow_array( $COUNT_SQL, undef, $thread );
    my $holder = GPForum::Test::PostgresHarness::connect_schema();
    $holder->txn_begin;
    ok(
        GPForum::Service::Forum::PostStore->new( schema => $holder )
          ->delete_post(
            {
                idempotency_key => GPForum::Infrastructure::Id->new->uuid,
                post            => {
                    deleted_by => $post->{author_user_id},
                    post_id    => $post->{post_id},
                    thread_id  => $post->{thread_id},
                },
            }
          )->{ok},
        'a delete of a reply is in flight'
    );
    my $pid   = _pid($holder);
    my $reply = _spawn( 'reply behind a delete', $thread );
    ok( _await( $ROW_WAIT_SQL, 1, $pid ),
        'the reply queues on a row the delete holds' );
    $holder->txn_commit;
    $holder->storage->disconnect;

    ok( _collect($reply)->{ok}, 'it commits once the delete has' );
    is( scalar $dbh->selectrow_array( $COUNT_SQL, undef, $thread ),
        $before, 'and both are counted' );
};

done_testing();

# The workflow as Bootstrap::Forum builds it, on a schema.
sub _workflow ($schema) {
    my $posts = GPForum::Service::Forum::PostReader->new( schema => $schema );

    return GPForum::Service::Forum::PostingWorkflow->new(
        category_reader =>
          GPForum::Service::Forum::CategoryReader->new( schema => $schema ),
        command_idempotency =>
          GPForum::Service::Operations::CommandIdempotency->new(
            schema => $schema
          ),
        mention_store =>
          GPForum::Service::Community::MentionStore->new( schema => $schema ),
        post_composer => GPForum::Service::Forum::PostComposer->new,
        post_reader   => $posts,
        post_store    =>
          GPForum::Service::Forum::PostStore->new( schema => $schema ),
        thread_composer      => GPForum::Service::Forum::ThreadComposer->new,
        thread_detail_reader =>
          GPForum::Service::Forum::ThreadDetailReader->new(
            post_reader => $posts,
            schema      => $schema,
          ),
        thread_store =>
          GPForum::Service::Forum::ThreadStore->new( schema => $schema ),
    );
}

sub _input ( $body, $thread_id ) {
    return {
        author_user_id => $member,
        body_source    => $body,
        command_id     => GPForum::Infrastructure::Id->new->uuid,
        thread_id      => $thread_id,
        viewer         => GPForum::Service::Forum::Viewer->new(
            member  => 1,
            user_id => $member,
        ),
    };
}

# A reply from a process of its own, which answers its result as JSON.
sub _spawn ( $body, $thread_id ) {
    pipe my $reader, my $writer or croak 'pipe failed';
    my $pid = fork;
    croak "fork failed: $OS_ERROR" if !defined $pid;
    if ( $pid == 0 ) {
        close $reader or croak 'close failed';
        my $answer = { error => 'died' };
        try {
            my $input = _input( $body, $thread_id );
            my $result =
              _workflow( GPForum::Test::PostgresHarness::connect_schema() )
              ->create_reply($input);
            $answer = {
                command_id => $input->{command_id},
                error      => $result->{error},
                ok         => $result->{ok},
                post_id    => $result->{stored}
                ? $result->{stored}{post}->get_column('post_id')
                : undef,
                status => $result->{status},
            };
        }
        catch ($error) { $answer = { error => "$error" }; };
        print {$writer} encode_json($answer) or croak 'write failed';
        close $writer                        or croak 'close failed';
        _exit(0);
    }
    close $writer or croak 'close failed';

    return { pid => $pid, reader => $reader };
}

sub _collect ($child) {
    local $INPUT_RECORD_SEPARATOR = undef;
    my $json = readline $child->{reader};
    close $child->{reader} or croak 'close failed';
    waitpid $child->{pid}, 0;

    return decode_json($json);
}

sub _await ( $sql, $count, @bind ) {
    for ( 1 .. $BLOCK_POLLS ) {
        my ($waiting) = $dbh->selectrow_array( $sql, undef, @bind );
        return 1 if $waiting >= $count;
        $dbh->do( 'SELECT pg_sleep(?)', undef, $BLOCK_POLL_SECONDS );
    }

    return 0;
}

sub _pid ($schema) {
    my ($pid) =
      $schema->storage->dbh->selectrow_array('SELECT pg_backend_pid()');

    return $pid;
}

sub _response ($command_id) {
    my ($json) = $dbh->selectrow_array(
        q{SELECT payload -> 'response' FROM command_log}
          . q{ WHERE idempotency_key = ?},
        undef, $command_id
    );

    return decode_json( $json // '{}' );
}

sub _posts_by_body ($body) {
    my ($count) = $dbh->selectrow_array(
        'SELECT count(*) FROM post_bodies WHERE body_source = ?',
        undef, $body );

    return $count;
}

1;
