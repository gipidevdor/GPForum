# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use lib 'lib';
use lib 't/lib';

use GPForum::Service::Community::Workflow;
use GPForum::Service::Operations::CommandIdempotency;
use GPForum::Test::CommandIdempotency;
use GPForum::Test::CommunityFunctions;
use GPForum::Test::CommunityWorkflowServices;
use Test::More;

our $VERSION = '0.001';

# The workflow's own Perl over in-memory stores: each command's one call
# is stood in for by GPForum::Test::CommunityFunctions, which keeps the
# command log and hands the write to the store double (ADR 0177). A report
# runs under the command log's promise, here the double's.
my $services  = GPForum::Test::CommunityWorkflowServices->new;
my $functions = GPForum::Test::CommunityFunctions->new( sink => $services );
my $workflow  = _workflow( GPForum::Test::CommandIdempotency->new );

my $liked = $workflow->like_post(
    { command_id => 'like-1', post_id => 'post-1', user_id => 'user-1' } );
ok( $liked->{ok}, 'like_post succeeds for a post that is there' );
is_deeply(
    $liked->{stored},
    {
        like_count => 3,
        liked      => 1,
        ok         => 1,
        post_id    => 'post-1',
        thread_id  => 'thread-1',
        user_id    => 'user-1',
    },
    'like_post answers with the like\'s public fields'
);
is( $services->like_calls->[0][1]{user_id},
    'user-1', 'like_post scopes the write to the member' );
is(
    $workflow->like_post(
        {
            command_id => 'like-2',
            post_id    => 'post-missing',
            user_id    => 'user-1'
        }
    )->{status},
    'not_found',
    'like_post reports a post that is not there'
);
my $unliked = $workflow->unlike_post(
    { command_id => 'unlike-1', post_id => 'post-1', user_id => 'user-1' } );
is( $unliked->{stored}{liked}, 0, 'unlike_post answers with the like gone' );
is( $services->like_calls->[-1][0], 'unlike', 'through the store\'s unlike' );
is(
    $workflow->like_post( { post_id => 'post-1', user_id => 'user-1' } )
      ->{status},
    'invalid',
    'like_post rejects a missing command_id'
);

my $missing = $workflow->save_bookmark(
    {
        target_id   => 'thread-1',
        target_type => 'thread',
        user_id     => 'user-1',
    }
);
is( $missing->{status}, 'invalid',
    'save_bookmark rejects a missing command_id' );
is(
    $missing->{errors}{command_id},
    'command_id is required',
    'save_bookmark names the missing command_id'
);

my $saved = $workflow->save_bookmark(
    {
        command_id  => 'bookmark-1',
        note        => 'later',
        target_id   => 'thread-1',
        target_type => 'thread',
        user_id     => 'user-1',
    }
);
ok( $saved->{ok}, 'save_bookmark succeeds for a known member' );
is( $saved->{stored}{target_id},
    'thread-1', 'save_bookmark returns the stored target' );
is( $services->bookmark_saves->[0]{user_id},
    'user-1', 'save_bookmark scopes the write to the member' );

my $failed_bookmark = $workflow->save_bookmark(
    {
        command_id  => 'bookmark-failed-1',
        target_id   => 'thread-1',
        target_type => 'thread',
        user_id     => 'boom',
    }
);
is( $failed_bookmark->{status},
    'failed', 'save_bookmark maps store exceptions to failed' );

my $removed = $workflow->remove_bookmark(
    {
        command_id  => 'bookmark-remove-1',
        target_id   => 'thread-1',
        target_type => 'thread',
        user_id     => 'user-1',
    }
);
ok( $removed->{ok}, 'remove_bookmark succeeds for a known bookmark' );

my $missing_remove = $workflow->remove_bookmark(
    {
        command_id  => 'bookmark-remove-gone-1',
        target_id   => 'thread-1',
        target_type => 'thread',
        user_id     => 'gone',
    }
);
is( $missing_remove->{status},
    'not_found', 'remove_bookmark maps a missing row to not_found' );

my $subscribed = $workflow->save_subscription(
    {
        command_id  => 'subscribe-1',
        preference  => 'all',
        target_id   => 'thread-1',
        target_type => 'thread',
        user_id     => 'user-1',
    }
);
ok( $subscribed->{ok}, 'save_subscription succeeds for a known member' );
is( $subscribed->{stored}{preference},
    'all', 'save_subscription returns the stored preference' );

my $muted = $workflow->mute_subscription(
    {
        command_id  => 'mute-1',
        target_id   => 'thread-1',
        target_type => 'thread',
        user_id     => 'user-1',
    }
);
ok( $muted->{ok}, 'mute_subscription succeeds for a known subscription' );

my $revoked = $workflow->revoke_subscription(
    {
        command_id  => 'unsubscribe-1',
        target_id   => 'thread-1',
        target_type => 'thread',
        user_id     => 'user-1',
    }
);
ok( $revoked->{ok}, 'revoke_subscription succeeds for a known subscription' );

my $missing_mute = $workflow->mute_subscription(
    {
        command_id  => 'mute-gone-1',
        target_id   => 'thread-1',
        target_type => 'thread',
        user_id     => 'gone',
    }
);
is( $missing_mute->{status},
    'not_found', 'mute_subscription maps a missing row to not_found' );

my $missing_report = $workflow->create_report(
    {
        details          => 'Thread report',
        reason           => 'spam',
        reporter_user_id => 'user-1',
        target_id        => 'thread-1',
        target_type      => 'thread',
    }
);
is( $missing_report->{status},
    'invalid', 'create_report rejects a missing command_id' );
is(
    $missing_report->{errors}{command_id},
    'command_id is required',
    'create_report names the missing command_id'
);

my $reported = $workflow->create_report(
    {
        command_id       => 'report-1',
        details          => 'Thread report',
        reason           => 'spam',
        reporter_user_id => 'user-1',
        target_id        => 'thread-1',
        target_type      => 'thread',
    }
);
ok( $reported->{ok}, 'create_report succeeds for a known member' );
is( $reported->{stored}{target_id},
    'thread-1', 'create_report returns the stored target' );
is( $services->report_creates->[0]{reporter_user_id},
    'user-1', 'create_report scopes the write to the reporter' );

my $invalid_reason = $workflow->create_report(
    {
        command_id       => 'report-invalid-1',
        reason           => q{},
        reporter_user_id => 'user-1',
        target_id        => 'thread-1',
        target_type      => 'thread',
    }
);
is( $invalid_reason->{status},
    'invalid', 'create_report rejects a missing reason' );
is(
    $invalid_reason->{errors}{reason},
    'reason is required',
    'create_report names the missing reason'
);

my $failed_report = $workflow->create_report(
    {
        command_id       => 'report-failed-1',
        reason           => 'spam',
        reporter_user_id => 'boom',
        target_id        => 'thread-1',
        target_type      => 'thread',
    }
);
is( $failed_report->{status},
    'failed', 'create_report maps store exceptions to failed' );

# A command again replays its answer and writes nothing more; another
# request under its id is a conflict.
for my $case (
    [
        save_bookmark => 'bookmark_saves',
        {
            command_id  => 'bookmark-replay-1',
            note        => 'later',
            target_id   => 'thread-1',
            target_type => 'thread',
            user_id     => 'user-1',
        },
        { note => 'sooner' },
    ],
    [
        save_subscription => 'subscription_saves',
        {
            command_id  => 'subscribe-replay-1',
            preference  => 'all',
            target_id   => 'thread-1',
            target_type => 'thread',
            user_id     => 'user-1',
        },
        { preference => 'mentions' },
    ],
  )
{
    my ( $method, $counter, $input, $change ) = @{$case};
    my $issued = $workflow->$method( { %{$input} } );
    ok( $issued->{ok}, "$method records a command" );
    my $writes = _store_writes( $services, $counter );
    is_deeply( $workflow->$method( { %{$input} } ),
        $issued, "$method replays the recorded result" );
    is( _store_writes( $services, $counter ),
        $writes, "$method replay does not persist twice" );
    is( $workflow->$method( { %{$input}, %{$change} } )->{status},
        'conflict', "$method rejects a reused command_id for another request" );
}
is(
    $functions->log->{'bookmark-replay-1'}{hash},
    GPForum::Service::Operations::CommandIdempotency->request_hash(
        {
            note        => 'later',
            target_id   => 'thread-1',
            target_type => 'thread',
            user_id     => 'user-1',
        }
    ),
'the command log keeps the fingerprint of the target, the note and the actor'
);

my $idempotency = GPForum::Test::CommandIdempotency->new;
_replay_report(
    {
        commanded   => _workflow($idempotency),
        idempotency => $idempotency,
        input       => {
            command_id       => 'report-replay-1',
            details          => 'Thread report',
            reason           => 'spam',
            reporter_user_id => 'user-1',
            target_id        => 'thread-1',
            target_type      => 'thread',
        },
        request => {
            details          => 'Thread report',
            reason           => 'spam',
            reporter_user_id => 'user-1',
            target_id        => 'thread-1',
            target_type      => 'thread',
        },
    }
);

done_testing();

sub _store_writes {
    my ( $store, $counter ) = @_;

    return scalar @{ $store->$counter };
}

sub _workflow {
    my ($log) = @_;

    return GPForum::Service::Community::Workflow->new(
        bookmark_store      => $services,
        command_idempotency => $log,
        functions           => $functions,
        like_store          => $services,
        report_store        => $services,
        subscription_store  => $services,
    );
}

# A report under the command log: recorded, replayed as it was, and a
# conflict under another request.
sub _replay_report {
    my ($job) = @_;

    my $issued = $job->{commanded}->create_report( $job->{input} );
    ok( $issued->{ok}, 'create_report records a command' );
    is( $job->{idempotency}->last_input->{command_type},
        'community.report', 'create_report uses community.report' );
    is_deeply( $job->{idempotency}->last_input->{request},
        $job->{request}, 'create_report command log stores target and actor' );
    my $writes = _store_writes( $services, 'report_creates' );
    is_deeply(
        _workflow(
            GPForum::Test::CommandIdempotency->new(
                replay_response => $issued
            )
        )->create_report( $job->{input} ),
        $issued,
        'create_report replays the recorded result'
    );
    is( _store_writes( $services, 'report_creates' ),
        $writes, 'create_report replay does not persist twice' );
    is(
        _workflow( GPForum::Test::CommandIdempotency->new( conflict => 1 ) )
          ->create_report( $job->{input} )->{status},
        'conflict',
        'create_report rejects a reused command_id for another request'
    );

    return;
}

1;
