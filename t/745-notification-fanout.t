# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Infrastructure::Id;
use GPForum::Service::Community::RelationStore;
use GPForum::Service::Notification::Dispatcher;
use GPForum::Service::Notification::PreferenceStore;
use GPForum::Service::Notification::RecipientPolicy;
use GPForum::Test::BadgeBatchSpy;
use GPForum::Test::CountingNotifier;
use GPForum::Test::FanoutFunctions;
use GPForum::Test::FixedClock;

our $VERSION = '0.001';

const my $CANDIDATES   => 8;
const my $DELIVERED    => 5;
const my $PAGE         => 200;
const my $OVER_A_PAGE  => 201;
const my $ACTOR        => 'user-author';
const my $UUID         => GPForum::Infrastructure::Id->uuid_pattern;
const my $LOCK_TIMEOUT => 'canceling statement due to lock timeout';
const my $EMAIL_EVENT  => 'notification.email.requested';
const my $BADGE        => 'notification.badge';
const my @USERS        => map { "user-$_" } qw(a b c d e f g h);
const my $THREAD       => GPForum::Infrastructure::Id->new->uuid;
const my $POST         => GPForum::Infrastructure::Id->new->uuid;

# On PostgreSQL the fan-out is four statements however many the recipients
# (migration 1036): the candidates with their plans, relations and viewers,
# where the source sits, the deliveries, the badges. The screening is create_notification's, in its
# order, with the dispatcher's own collaborators; the function layer here
# answers from a script, and the recipient policy is the real one, judging
# a members-only post.
my ( $a, $b, $c, $d, $e, $f, $g, $h ) = @USERS;
my @candidates = (
    _candidate($a),
    _candidate( $b, in_app   => 0, email => 1 ),
    _candidate( $c, silenced => 1 ),
    _candidate( $d, status   => 'pending' ),
    _candidate( $e, in_app   => 0 ),
    _candidate($f),
    _candidate($g),
    _candidate($h),
);

subtest 'the screening and the statements' => sub {
    my $functions = GPForum::Test::FanoutFunctions->new(
        candidates => \@candidates,
        outcomes   => { $f => 'duplicate', $g => 'failed' },
        uncounted  => { $h => $LOCK_TIMEOUT },
    );
    my $spy        = GPForum::Test::BadgeBatchSpy->new;
    my $dispatcher = _dispatcher( $functions, $spy );

    my $fanned = $dispatcher->fanout_to_subscribers( _fanout() );
    ok( $fanned->{ok}, 'the fan-out answers ok' );
    is( $fanned->{attempted}, $CANDIDATES, 'every candidate is attempted' );
    is_deeply(
        [ map { $_->[0] } @{ $functions->calls } ],
        [
            qw(notification_fanout_candidates forum_post_placement
              notification_fanout_deliver)
        ],
'the candidates, where the post sits, then the deliveries; the badges go to the notifier'
    );
    is_deeply(
        $functions->calls->[0][1],
        {
            target_type       => 'thread',
            target_id         => $THREAD,
            notification_type => 'reply',
            actor_id          => $ACTOR,
            excluded_user_id  => $ACTOR,
        },
        'the candidates are asked for the target, the kind and the actor'
    );

    my @created = sort map { $_->{notification}{recipient_user_id} }
      @{ $fanned->{created} };
    is_deeply( \@created, [ $a, $h ], 'a delivery made is created' );
    is( $fanned->{created}[0]{unread_count},
        1, 'and carries the unread count the statement read' );
    is_deeply(
        [
            map { $_->{notification}{recipient_user_id} }
              @{ $fanned->{duplicates} }
        ],
        [$f],
        'an inbox row already there is a duplicate'
    );
    is_deeply(
        $fanned->{failed},
        [ { recipient_user_id => $g, error => 'refused' } ],
        'a recipient the database refused is failed, with the reason'
    );
    is_deeply(
        $fanned->{skipped},
        [
            { ok => 0, skipped => 'member_relation' },
            { ok => 0, skipped => 'permission_denied' },
            { ok => 0, skipped => 'channel_disabled', channel => 'in_app' },
            {
                ok           => 0,
                skipped      => 'channel_disabled',
                channel      => 'in_app',
                email_queued => 1
            },
        ],
'the refusals in order: a relation, a post they may not read, both channels off, and the mail alone after the deliveries'
    );

    my $recipients = $functions->calls->[2][1]{recipients};
    is_deeply(
        [ map { $_->{recipient_user_id} } @{$recipients} ],
        [ $a, $b, $f, $g, $h ],
        'only the recipients with a channel on reach the deliveries'
    );
    my ($first) = @{$recipients};
    is( $first->{in_app}, 1, 'a recipient with the inbox on is delivered to' );
    is( $first->{email},  0, 'and not mailed' );
    is(
        $first->{idempotency_key},
        "notification.reply:event-1:$a",
        'the delivery key is the fan-out key and the recipient'
    );
    like( $first->{notification}{notification_id},
        $UUID, 'the notification id is drawn from the key' );
    is( $first->{inbox}{created_at},
        '2026-05-23T12:00:00Z', 'the rows are stamped with the clock' );
    is(
        $first->{notification}{payload}{idempotency_key},
        "notification.reply:event-1:$a",
        'the payload names the key'
    );
    is_deeply(
        [ @{$first}{qw(filter_sources member global_read viewer_user_id)} ],
        [ 1, 1, 0, $a ],
        'the count sees the recipient as the viewer their row describes'
    );
    ok( !exists $first->{email_event}, 'no mail event without email' );

    my ($mailed) = grep { $_->{recipient_user_id} eq $b } @{$recipients};
    is( $mailed->{in_app}, 0, 'the mail-alone recipient is not delivered to' );
    is( $mailed->{email},  1, 'but mailed' );
    is( $mailed->{email_event}{event_type},
        $EMAIL_EVENT, 'with the mail event as record_event would draw it' );
    is( $mailed->{email_event}{aggregate_id}, $b, 'for the recipient' );
    is(
        $mailed->{email_event}{idempotency_key},
        "notification.email:notification.reply:event-1:$b",
        'keyed by the notification'
    );
    like( $mailed->{email_outbox_id}, $UUID, 'with an outbox id of its own' );
    is( $mailed->{email_explicit}, 1, 'and an explicit event id' );

    is( scalar @{ $spy->batches }, 1, 'the badges go in one statement' );
    is_deeply(
        [
            map {
                [ $_->{type}, $_->{aggregate_id}, $_->{payload}{unread_count} ]
            } @{ $spy->batches->[0] }
        ],
        [ [ $BADGE, $a, 1 ] ],
        'one badge per notification created and counted'
    );
    is( $dispatcher->snapshot->{badge_failures},
        1, 'a count that failed is a badge failure' );
    like(
        $dispatcher->snapshot->{last_badge_error}{message},
        qr/lock [ ] timeout/msx,
        'with the count\'s reason'
    );
};

subtest 'a page of two hundred deliveries at a time' => sub {
    my $functions = GPForum::Test::FanoutFunctions->new(
        candidates => [ map { _candidate("user-$_") } 1 .. $OVER_A_PAGE ] );
    my $spy = GPForum::Test::BadgeBatchSpy->new;
    my $fanned =
      _dispatcher( $functions, $spy )->fanout_to_subscribers( _fanout() );
    my @deliveries =
      grep { $_->[0] eq 'notification_fanout_deliver' } @{ $functions->calls };
    is( scalar @deliveries,
        2, 'two hundred and one recipients are two statements' );
    is_deeply(
        [ map { scalar @{ $_->[1]{recipients} } } @deliveries ],
        [ $PAGE, 1 ],
        'a full page, then the rest'
    );
    is( scalar @{ $fanned->{created} },
        $OVER_A_PAGE, 'every recipient is created' );
    is( scalar @{ $spy->batches->[0] },
        $OVER_A_PAGE, 'and every badge goes in the one NOTIFY statement' );
};

subtest 'a deliveries statement that fails fails its page alone' => sub {
    my $functions = GPForum::Test::FanoutFunctions->new(
        candidates => \@candidates,
        refuses    => 'connection lost',
    );
    my $spy = GPForum::Test::BadgeBatchSpy->new;
    my $fanned =
      _dispatcher( $functions, $spy )->fanout_to_subscribers( _fanout() );
    ok( $fanned->{ok}, 'the fan-out still answers' );
    is( scalar @{ $fanned->{failed} },
        $DELIVERED, 'every recipient of the page is failed' );
    like(
        $fanned->{failed}[0]{error},
        qr/connection [ ] lost/msx,
        'with the statement\'s error'
    );
    is( scalar @{ $fanned->{created} }, 0, 'and none is created' );
    is( scalar @{ $spy->batches },      0, 'so no badge goes' );
};

subtest 'a notifier without notify_many takes the badges one by one' => sub {
    my $functions = GPForum::Test::FanoutFunctions->new(
        candidates => [ _candidate($a), _candidate($f) ] );
    my $notifier = GPForum::Test::CountingNotifier->new;
    _dispatcher( $functions, $notifier )->fanout_to_subscribers( _fanout() );
    is_deeply(
        [ map { $_->{aggregate_id} } @{ $notifier->calls } ],
        [ $a, $f ],
        'one notify per badge'
    );
};

subtest 'a badge batch the notifier refuses is one badge failure' => sub {
    my $functions = GPForum::Test::FanoutFunctions->new(
        candidates => [ _candidate($a), _candidate($f) ] );
    my $spy = GPForum::Test::BadgeBatchSpy->new(
        refuses => { ok => 0, reason => 'notify_failed' } );
    my $dispatcher = _dispatcher( $functions, $spy );
    $dispatcher->fanout_to_subscribers( _fanout() );
    is( $dispatcher->snapshot->{badge_failures},
        1, 'the refusal is counted once' );
    like( $dispatcher->snapshot->{last_badge_error}{message},
        qr/notify_failed/msx, 'with the notifier\'s reason' );
};

subtest 'without a preference store the inbox alone is the plan' => sub {
    my $functions = GPForum::Test::FanoutFunctions->new(
        candidates => [ _candidate( $b, in_app => 0, email => 1 ) ] );
    my $dispatcher = GPForum::Service::Notification::Dispatcher->new(
        clock             => GPForum::Test::FixedClock->new,
        functions         => $functions,
        realtime_notifier => GPForum::Test::BadgeBatchSpy->new,
        schema            => {},
        stats             => { badge_failures => 0 },
    );
    my $fanned = $dispatcher->fanout_to_subscribers( _fanout() );
    is( scalar @{ $fanned->{created} },
        1, 'the recipient is delivered to, whatever the row says' );
    my ($recipient) = @{ $functions->calls->[-1][1]{recipients} };
    is_deeply(
        [ @{$recipient}{qw(in_app email filter_sources)} ],
        [ 1, 0, 0 ],
        'the inbox on, no mail, and every source counted without a readability'
    );
};

done_testing();

# What the outbox handler sends, fresh each time: the dispatcher reads the
# payload, and a restricted hash would refuse a key it lacks.
sub _fanout {
    return {
        target_type                => 'thread',
        target_id                  => $THREAD,
        source_type                => 'post',
        source_id                  => $POST,
        notification_type          => 'reply',
        excluded_recipient_user_id => $ACTOR,
        idempotency_key            => 'notification.reply:event-1',
        payload                    =>
          { event_id => 'event-1', actor_id => $ACTOR, post_id => $POST },
    };
}

sub _candidate ( $user_id, %row ) {
    return {
        user_id       => $user_id,
        in_app        => 1,
        email         => 0,
        email_address => undef,
        locale        => 'en',
        event_type    => 'reply',
        silenced      => 0,
        status        => 'active',
        suspended     => 0,
        grants        => [],
        moderates     => 0,
        listed        => [],
        trust_level   => 1,
        %row,
    };
}

# Wired as Bootstrap wires it, with the function layer scripted.
sub _dispatcher ( $functions, $notifier ) {
    my $policy = GPForum::Service::Notification::RecipientPolicy->new(
        functions => $functions,
        schema    => {},
    );

    return GPForum::Service::Notification::Dispatcher->new(
        clock             => GPForum::Test::FixedClock->new,
        functions         => $functions,
        permission_engine => $policy,
        preference_store  =>
          GPForum::Service::Notification::PreferenceStore->new(
            functions => $functions,
            schema    => {},
          ),
        readability       => $policy,
        realtime_notifier => $notifier,
        relations         =>
          GPForum::Service::Community::RelationStore->new( schema => {} ),
        schema => {},
        stats  => { badge_failures => 0 },
    );
}

1;
