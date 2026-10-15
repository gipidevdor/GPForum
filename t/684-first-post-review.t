# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Service::Forum::PostingAutomod;
use GPForum::Service::Forum::PostingReview;
use GPForum::Service::Forum::Viewer;
use GPForum::Service::Moderation::ReviewStore;
use GPForum::Service::Moderation::ReviewWorkflow;
use GPForum::Service::Notification::Renderer;
use GPForum::Test::AutomodFunctions;
use GPForum::Test::ReviewCalls;

our $VERSION = '0.001';

const my $AUTHOR    => '11111111-1111-4111-8111-111111111111';
const my $STAFF     => '22222222-2222-4222-8222-222222222222';
const my $POST      => '33333333-3333-4333-8333-333333333333';
const my $THREAD    => '44444444-4444-4444-8444-444444444444';
const my $REVIEW    => '55555555-5555-4555-8555-555555555555';
const my $TARGET    => '66666666-6666-4666-8666-666666666666';
const my $FIRST     => 2;
const my $THREE     => 3;
const my $TOO_MANY  => 21;
const my $TOO_LONG  => 501;
const my $NO_WORDS  => [];
const my $FLAG_WORD => [ { phrase => 'casino', action => 'flag' } ];

# ADR 0134: when a write is held, how a hold is kept, and how staff and the
# author decide it.
subtest 'the review rule holds first posts, and flagged ones when asked' =>
  sub {
    my $rules = {
        words              => $NO_WORDS,
        link_limit         => undef,
        review_first_posts => $FIRST,
        review_flagged     => 0,
        published_posts    => 1,
    };
    my $store =
      GPForum::Test::ReviewCalls->new( answers => { rules_for => $rules } );
    my $guard = GPForum::Service::Forum::PostingAutomod->new( store => $store );
    my $input = { author_user_id => $AUTHOR, body_source => 'Hello' };

    is( $guard->screen( 'reply.create', $input )->{hold},
        'first_posts', 'a reply below the number is held' );
    is(
        $guard->screen( 'thread.create', { %{$input}, title => 'Hi there' } )
          ->{hold},
        'first_posts',
        'and so is a new thread'
    );
    ok( !$guard->screen( 'post.edit', $input )->{hold},
        'an edit is never held' );
    my $staff = GPForum::Service::Forum::Viewer->new( moderates => 1 );
    ok(
        !$guard->screen( 'reply.create', { %{$input}, viewer => $staff } )
          ->{hold},
        'nor is staff who moderate'
    );

    $rules->{published_posts} = $FIRST;
    ok(
        !$guard->screen( 'reply.create', $input )->{hold},
        'a member with that many published posts is not held'
    );

    %{$rules} = (
        %{$rules},
        words              => $FLAG_WORD,
        review_first_posts => 0,
        review_flagged     => 1,
    );
    my $screen = $guard->screen( 'reply.create',
        { %{$input}, body_source => 'Try my casino' } );
    is( $screen->{hold}, 'flagged', 'a flagged post is held when asked' );
    ok( $screen->{settle}, 'with the flag kept in its verdict' );
    $rules->{review_flagged} = 0;
    ok(
        !$guard->screen( 'reply.create',
            { %{$input}, body_source => 'Try my casino' } )->{hold},
        'and published with a report otherwise'
    );
    ok(
        !$guard->screen( 'reply.create', $input )->{hold},
        'an unflagged post is not held for it'
    );
  };

subtest 'a hold keeps the composed post, keyed by the command id' => sub {
    my $store = GPForum::Test::ReviewCalls->new(
        answers => {
            hold => {
                ok            => 1,
                status        => 'ok',
                review_id     => $REVIEW,
                review_status => 'pending',
                replayed      => 0,
            }
        }
    );
    my $review = GPForum::Service::Forum::PostingReview->new( store => $store );
    my $held   = $review->hold(
        'reply.create',
        {
            hold    => 'flagged',
            verdict => { flagged => ['casino'], replaced => [], links => 0 },
            input   => {
                author_user_id   => $AUTHOR,
                command_id       => ' cmd-1 ',
                visibility       => 'nonsense',
                reply_to_post_id => $TARGET,
                draft_id         => $POST,
                draft_revision   => 1,
            },
        },
        {
            post => { thread_id   => $THREAD },
            body => { body_source => 'Hi', body_rendered_safe => '<p>Hi</p>' },
        }
    );
    is_deeply(
        [ @{$held}{qw(ok status)}, $held->{held}{review_id} ],
        [ 1, 'held', $REVIEW ],
        'the post is held'
    );
    my ($kept) = @{ $store->made('hold')->[0] };
    is_deeply(
        [
            @{$kept}{
                qw(kind thread_id command_id visibility reason
                  body_rendered_safe reply_to_post_id draft_id)
            }
        ],
        [
            'reply',
            $THREAD,
            'cmd-1',
            undef,
            'flagged',
            '<p>Hi</p>',
            $TARGET,
            $POST
        ],
        'as composed, where it goes and why'
    );
    is_deeply( $kept->{details}{flagged},
        ['casino'], 'with what the rules found' );

    $store->answers->{hold} = sub { die "no database\n" };
    is( $review->hold( 'reply.create', { input => {} }, {} )->{status},
        'failed', 'a hold that cannot be stored fails' );
    is( $review->hold( 'post.edit', { input => {} }, {} )->{status},
        'failed', 'and an edit is no held command' );
};

subtest 'staff approve: published as the author\'s, once' => sub {
    my $calls    = GPForum::Test::ReviewCalls->new;
    my $workflow = _workflow($calls);
    is( $workflow->approve( { review_id => 'nope' } )->{status},
        'not_found', 'a malformed id is no entry' );
    is( scalar @{ $calls->calls }, 0, 'and asks nothing' );

    $calls->answers->{take} = sub { return; };
    is( $workflow->approve( { review_id => $REVIEW } )->{status},
        'not_found', 'a missing entry is not found' );

    $calls->answers->{take} = { %{ _held('approved') }, post_id => $POST };
    is( $workflow->approve( { review_id => $REVIEW } )->{status},
        'unchanged', 'an approved entry is approved' );
    $calls->answers->{take} = _held('rejected');
    is( $workflow->approve( { review_id => $REVIEW } )->{status},
        'conflict', 'a rejected one is not' );

    $calls->answers->{take}             = _held('pending');
    $calls->answers->{publish_reviewed} = {
        ok     => 0,
        status => 'conflict',
        error  => 'thread is locked'
    };
    is_deeply(
        $workflow->approve( { review_id => $REVIEW, actor_user_id => $STAFF } ),
        { ok => 0, status => 'refused', error => 'thread is locked' },
        'a post the thread no longer takes is refused'
    );
    is( scalar @{ $calls->made('decide') }, 0, 'and nothing is recorded' );

    $calls->answers->{publish_reviewed} = {
        ok     => 1,
        status => 'ok',
        stored => { post => { post_id => $POST, thread_id => $THREAD } },
    };
    my $approved =
      $workflow->approve( { review_id => $REVIEW, actor_user_id => $STAFF } );
    is_deeply(
        [ @{$approved}{qw(ok status post_id thread_id)} ],
        [ 1, 'ok', $POST, $THREAD ],
        'an approval publishes the post'
    );
    my ( $type, $published ) = @{ $calls->made('publish_reviewed')->[-1] };
    is_deeply(
        [ $type, @{$published}{qw(author_user_id command_id thread_id)} ],
        [ 'reply.create', $AUTHOR, 'cmd-1', $THREAD ],
        'as the author\'s command, with the command id they submitted'
    );
    is( $calls->made('resolve')->[-1][0], $AUTHOR, 'read as the author reads' );
    is_deeply(
        [ @{ $calls->made('decide')->[-1][0] }{qw(status post_id)} ],
        [ 'approved', $POST ],
        'the decision names the post'
    );
    is_deeply(
        $calls->made('link_reply')->[-1],
        [ $POST, $TARGET ],
        'the reply is linked to the post it answers'
    );
    my ($notice) = @{ $calls->made('create_notification')->[-1] };
    is_deeply(
        [ @{$notice}{qw(notification_type recipient_user_id source_type)} ],
        [ 'review_approved', $AUTHOR, 'post' ],
        'and the author told, on the post'
    );

    $calls->answers->{decide} = { status => 'decided' };
    is( $workflow->approve( { review_id => $REVIEW } )->{status},
        'failed', 'an approval that is not recorded fails' );
};

subtest 'staff reject, the author withdraws' => sub {
    my $calls = GPForum::Test::ReviewCalls->new(
        answers => {
            decide => {
                status         => 'ok',
                review_status  => 'rejected',
                author_user_id => $AUTHOR,
                kind           => 'reply',
                thread_id      => $THREAD,
            }
        }
    );
    my $workflow = _workflow($calls);
    is(
        $workflow->reject(
            { review_id => $REVIEW, reason => 'x' x $TOO_LONG }
        )->{field},
        'reason',
        'a reason is at most 500 characters'
    );
    my $rejected = $workflow->reject(
        {
            review_id     => $REVIEW,
            actor_user_id => $STAFF,
            reason        => '  Off topic  '
        }
    );
    is( $rejected->{status}, 'ok', 'a rejection is recorded' );
    is( $calls->made('decide')->[-1][0]{reason},
        'Off topic', 'with its reason trimmed' );
    my ($notice) = @{ $calls->made('create_notification')->[-1] };
    is_deeply(
        [ @{$notice}{qw(notification_type source_type source_id)} ],
        [ 'review_rejected', 'thread', $THREAD ],
        'a rejected reply is notified on its thread'
    );

    $calls->answers->{decide} = {
        status         => 'ok',
        author_user_id => $AUTHOR,
        kind           => 'thread',
    };
    my $before = @{ $calls->made('create_notification') };
    $workflow->reject( { review_id => $REVIEW, actor_user_id => $STAFF } );
    is( scalar @{ $calls->made('create_notification') },
        $before, 'a rejected thread has nowhere to be notified' );

    $calls->answers->{decide} = { status => 'not_found' };
    is(
        $workflow->withdraw(
            { review_id => $REVIEW, author_user_id => $STAFF }
        )->{status},
        'not_found',
        'only the author withdraws'
    );
    is_deeply(
        [ @{ $calls->made('decide')->[-1][0] }{qw(status actor_user_id)} ],
        [ 'withdrawn', $STAFF ],
        'the withdrawal is asked as its author'
    );
    $calls->answers->{decide} = sub { die "no database\n" };
    is( $workflow->withdraw( { review_id => $REVIEW } )->{status},
        'failed', 'a failure is a failure' );
};

subtest 'the store validates before it calls' => sub {
    my $functions = GPForum::Test::AutomodFunctions->new;
    my $store     = GPForum::Service::Moderation::ReviewStore->new(
        schema    => {},
        functions => $functions,
    );
    for my $first ( 'x', q{}, $TOO_MANY, '-1', '1.5' ) {
        is( $store->set_rule( { first_posts => $first } )->{field},
            'first_posts', "'$first' is no number of posts" );
    }
    is(
        $store->decide( { review_id => 'nope', status => 'approved' } )
          ->{status},
        'not_found',
        'a malformed id is no entry'
    );
    is(
        $store->decide( { review_id => $REVIEW, status => 'deleted' } )
          ->{status},
        'invalid',
        'an unknown decision is invalid'
    );
    is( $store->take('nope'), undef, 'a malformed id takes nothing' );
    is_deeply( $store->mine('nope'), [], 'and lists nothing' );
    is( scalar @{ $functions->calls }, 0, 'none of them called a function' );

    is( $store->set_rule( { first_posts => '3', flagged => 'on' } )->{status},
        'ok', 'a rule is set' );
    my ( $name, $values ) = @{ $functions->calls->[-1] };
    is_deeply(
        [ $name, @{$values}{qw(first_posts flagged)} ],
        [ 'moderation_review_settings_set', $THREE, 1 ],
        'through its function'
    );
    is( $values->{audit}{action}, 'review.rule_set', 'with its audit' );
};

subtest 'the decisions are notified in the reader\'s words' => sub {
    my $renderer = GPForum::Service::Notification::Renderer->new;
    my $approved = $renderer->render_inbox_item( 'it',
        { notification_type => 'review_approved', payload => {} } );
    is( $approved->{type_key}, 'review_approved', 'an approval is its type' );
    like( $approved->{title}, qr/pubblicato/msx, 'in Italian' );
    my $rejected = $renderer->render_inbox_item(
        'en',
        {
            notification_type => 'review_rejected',
            payload           => { reason => 'Off topic' }
        }
    );
    like( $rejected->{summary}, qr/Off [ ] topic/msx, 'with the reason' );
};

done_testing();

sub _workflow ($calls) {
    return GPForum::Service::Moderation::ReviewWorkflow->new(
        store           => $calls,
        posting         => $calls,
        viewer_resolver => $calls,
        notifications   => $calls,
        reply_links     => $calls,
    );
}

sub _held ($status) {
    return {
        review_id        => $REVIEW,
        author_user_id   => $AUTHOR,
        command_id       => 'cmd-1',
        kind             => 'reply',
        thread_id        => $THREAD,
        body_source      => 'Hi',
        reply_to_post_id => $TARGET,
        status           => $status,
    };
}

1;
