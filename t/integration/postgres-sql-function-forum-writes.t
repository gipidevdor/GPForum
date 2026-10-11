# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause
package main;
use v5.40;
use JSON::MaybeXS;
use POSIX qw(strftime);
use Test::More;
use lib 'lib';
use lib 't/lib';
use GPForum::Benchmark::SeedDataset qw(seed_id);
use GPForum::Service::Community::MentionStore;
use GPForum::Service::Forum::CategoryReader;
use GPForum::Service::Forum::PostComposer;
use GPForum::Service::Forum::PostReader;
use GPForum::Service::Forum::PostStore;
use GPForum::Service::Forum::PostingCommand;
use GPForum::Service::Forum::PostingWorkflow;
use GPForum::Service::Forum::ThreadComposer;
use GPForum::Service::Forum::ThreadDetailReader;
use GPForum::Service::Forum::ThreadStore;
use GPForum::Service::Forum::Viewer;
use GPForum::Service::Operations::CommandIdempotency;
use GPForum::Test::FixedClock;
use GPForum::Test::LogLines;
use GPForum::Test::PgDatabase;
use GPForum::Test::ReplacedSubs qw(with_replaced_subs);
use GPForum::Test::SequenceId;
our $VERSION = '0.001';

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'set GPFORUM_TEST_DSN for forum-write differential tests';
}
my $now   = strftime( '%Y-%m-%dT%H:%M:%SZ', gmtime );
my $json  = JSON::MaybeXS->new( canonical => 1 );
my $codec = GPForum::Service::Forum::PostingCommand->new;
my %pair =
  map { $_ => GPForum::Test::PgDatabase->fresh( seed => 1 ) } qw(function perl);
my $user = seed_id( user => 2 );
my $viewer =
  GPForum::Service::Forum::Viewer->new( member => 1, user_id => $user );
my $serial = 0;
my ( $thread, $post );
with_replaced_subs(
    'GPForum::Infrastructure::AuditRecord',
    { now_iso8601 => sub { return $now; } },
    sub {
        my $created = same(
            'create_thread',
            'thread.create',
            {
                category_id => seed_id( category => 1 ),
                title       => 'Stored procedure differential',
                body_source => 'Opening body',
                visibility  => 'public',
                command_id  => 'writes-create'
            }
        );
        $thread = $created->{stored}{thread}->thread_id;
        $post   = $created->{stored}{post}->post_id;
        same(
            'create_thread',
            'thread.create',
            {
                category_id => seed_id( category => 1 ),
                title       => 'Stored procedure differential',
                body_source => 'Opening body',
                visibility  => 'public',
                command_id  => 'writes-create'
            },
            'replayed'
        );
        same(
            'create_thread',
            'thread.create',
            {
                category_id => seed_id( category => 1 ),
                title       => 'A changed request',
                body_source => 'Opening body',
                visibility  => 'public',
                command_id  => 'writes-create'
            },
            'conflict'
        );
        same(
            'edit_thread',
            'thread.edit',
            {
                thread_id  => $thread,
                title      => 'A changed title',
                command_id => 'writes-title'
            }
        );
        same(
            'edit_thread',
            'thread.edit',
            {
                thread_id  => $thread,
                title      => 'A changed title',
                command_id => 'writes-title-skip'
            }
        );
        same(
            'move_thread',
            'thread.move',
            {
                thread_id   => $thread,
                category_id => seed_id( category => 2 ),
                command_id  => 'writes-move'
            }
        );
        same(
            'move_thread',
            'thread.move',
            {
                thread_id   => $thread,
                category_id => seed_id( category => 2 ),
                command_id  => 'writes-move-skip'
            }
        );
        same(
            'edit_post',
            'post.edit',
            {
                post_id     => $post,
                body_source => 'Opening revised',
                command_id  => 'writes-edit'
            }
        );
        same(
            'edit_post',
            'post.edit',
            {
                post_id     => $post,
                body_source => 'Opening revised',
                command_id  => 'writes-edit-skip'
            }
        );
        same( 'delete_post', 'post.delete',
            { post_id => $post, command_id => 'writes-delete-opening' } );
        same( 'restore_post', 'post.restore',
            { post_id => $post, command_id => 'writes-restore-opening' } );
        same( 'delete_thread', 'thread.delete',
            { thread_id => $thread, command_id => 'writes-delete-thread' } );
        same( 'delete_thread', 'thread.delete',
            { thread_id => $thread, command_id => 'writes-delete-thread' },
            'replayed' );
        same( 'restore_thread', 'thread.restore',
            { thread_id => $thread, command_id => 'writes-restore-thread' } );
        same( 'restore_thread', 'thread.restore',
            { thread_id => $thread, command_id => 'writes-restore-live' },
            'not_found' );
        same(
            'edit_thread',
            'thread.edit',
            {
                thread_id  => $thread,
                title      => q{},
                command_id => 'writes-invalid-title'
            },
            'invalid'
        );
        same(
            'edit_post',
            'post.edit',
            {
                post_id     => $post,
                body_source => q{},
                command_id  => 'writes-invalid-body'
            },
            'invalid'
        );
        same(
            'move_thread',
            'thread.move',
            {
                thread_id   => $thread,
                category_id => 'not-a-uuid',
                command_id  => 'writes-missing-category'
            },
            'not_found'
        );
        same(
            'edit_thread',
            'thread.edit',
            {
                thread_id      => $thread,
                title          => 'Not yours',
                author_user_id => seed_id( user => 3 ),
                command_id     => 'writes-foreign-thread'
            },
            'forbidden'
        );
        same(
            'delete_post',
            'post.delete',
            {
                post_id        => $post,
                author_user_id => seed_id( user => 3 ),
                command_id     => 'writes-foreign-post'
            },
            'forbidden'
        );
        my $reply = same(
            'create_reply',
            'reply.create',
            {
                thread_id   => $thread,
                body_source => 'A reply',
                command_id  => 'writes-reply'
            }
        );
        my $reply_id = $reply->{stored}{post}->post_id;
        same( 'delete_post', 'post.delete',
            { post_id => $reply_id, command_id => 'writes-delete-reply' } );
        same( 'restore_post', 'post.restore',
            { post_id => $reply_id, command_id => 'writes-restore-reply' } );

        for my $side ( values %pair ) {
            $side->dbh->do(
                'UPDATE threads SET locked_at = ? WHERE thread_id = ?',
                undef, $now, $thread );
        }
        same(
            'edit_thread',
            'thread.edit',
            {
                thread_id  => $thread,
                title      => 'Locked title',
                command_id => 'writes-locked-thread'
            },
            'forbidden'
        );
        same(
            'edit_post',
            'post.edit',
            {
                post_id     => $reply_id,
                body_source => 'Locked body',
                command_id  => 'writes-locked-post'
            },
            'forbidden'
        );
    }
);
done_testing();

sub same( $method, $type, $input, $expected = 'ok' ) {
    ++$serial;
    my %result;
    for my $path (qw(function perl)) {
        my $workflow = workflow($path);
        $result{$path} = $workflow->$method(
            { author_user_id => $user, viewer => $viewer, %{$input} } );
        if ( $result{$path}{status} eq 'failed' ) {
            diag explain $workflow->logger->lines;
        }
    }
    is_deeply(
        $codec->response( $type, $result{function} ),
        $codec->response( $type, $result{perl} ),
        "$serial $type: response unchanged"
    );
    if ( $expected eq 'replayed' ) {
        ok( $result{function}{idempotent}, "$serial $type: replayed" );
    }
    else {
        is( $result{function}{status},
            $expected, "$serial $type: expected outcome" );
    }
    for my $table (
        qw(threads posts post_bodies post_revisions thread_counters command_log event_log outbox_messages audit_log)
      )
    {
        is_deeply(
            snapshot( $pair{function}->dbh, $table ),
            snapshot( $pair{perl}->dbh,     $table ),
            "$serial $type: same $table"
        );
    }
    return $result{function};
}

sub workflow($path) {
    my $schema = $pair{$path}->schema;
    my %old    = $path eq 'perl' ? ( functions => undef ) : ();
    my $ids    = GPForum::Test::SequenceId->new(
        prefix => ( sprintf '018f%04x-0000-7000-8000', $serial ) );
    my $clock = GPForum::Test::FixedClock->new( iso8601 => $now );
    my $posts =
      GPForum::Service::Forum::PostReader->new( schema => $schema, %old );
    return GPForum::Service::Forum::PostingWorkflow->new(
        logger          => GPForum::Test::LogLines->new,
        category_reader => GPForum::Service::Forum::CategoryReader->new(
            schema => $schema,
            %old
        ),
        post_reader          => $posts,
        thread_detail_reader =>
          GPForum::Service::Forum::ThreadDetailReader->new(
            schema      => $schema,
            post_reader => $posts,
            %old
          ),
        mention_store =>
          GPForum::Service::Community::MentionStore->new( schema => $schema ),
        post_composer =>
          GPForum::Service::Forum::PostComposer->new( id_service => $ids ),
        thread_composer =>
          GPForum::Service::Forum::ThreadComposer->new( id_service => $ids ),
        post_store => GPForum::Service::Forum::PostStore->new(
            schema     => $schema,
            id_service => $ids,
            clock      => $clock,
            %old
        ),
        thread_store => GPForum::Service::Forum::ThreadStore->new(
            schema     => $schema,
            id_service => $ids,
            clock      => $clock,
            %old
        ),
        command_idempotency =>
          GPForum::Service::Operations::CommandIdempotency->new(
            schema     => $schema,
            id_service => $ids,
            clock      => $clock,
            %old
          ),
        %old,
    );
}

sub snapshot( $dbh, $table ) {
    my $rows =
      $dbh->selectall_arrayref( "SELECT * FROM $table", { Slice => {} } );
    for my $row ( @{$rows} ) {
        if (   $table ne 'audit_log'
            && $table ne 'command_log'
            && $table ne 'event_log' )
        {
            delete @{$row}{
                qw(created_at updated_at last_activity_at available_at next_attempt_at)
            };
        }
        for my $column (qw(payload metadata)) {
            if ( defined $row->{$column} ) {
                $row->{$column} = $json->decode( $row->{$column} );
            }
        }
    }
    return [ sort { $json->encode($a) cmp $json->encode($b) } @{$rows} ];
}

1;
