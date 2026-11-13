# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Service::Notification::Dispatcher;
use GPForum::Test::FixedClock;
use GPForum::Test::Id;
use GPForum::Test::NotificationInboxFunctions;
use GPForum::Test::PermissionEngine;
use GPForum::Test::RefusingNotifier;
use GPForum::X::Unavailable;

our $VERSION = '0.001';

# A badge NOTIFY the notifier refused was raised with die and a string, only
# so that the savepoint around it rolls back. It is an X::Unavailable (ADR
# 0118): the notifier is a dependency that did not answer. The delivery
# stands and the failure is counted with the same message.
# The delivery runs inside a transaction of its caller's, as a mention
# inside the command log's does: the badge runs in a savepoint of it.
my $functions  = GPForum::Test::NotificationInboxFunctions->new( depth => 1 );
my $dispatcher = GPForum::Service::Notification::Dispatcher->new(
    badge_errors      => {},
    clock             => GPForum::Test::FixedClock->new,
    id_service        => GPForum::Test::Id->new,
    permission_engine => GPForum::Test::PermissionEngine->new,
    realtime_notifier => GPForum::Test::RefusingNotifier->new,
    functions         => $functions,
    schema            => {},
    stats             => { badge_failures => 0 },
);

my $delivered = $dispatcher->create_notification(
    {
        notification_type => 'reply',
        payload           => { thread_id => 'thread-1' },
        recipient_user_id => 'user-1',
        source_id         => 'post-1',
        source_type       => 'post',
    }
);
ok( $delivered->{ok}, 'a delivery whose NOTIFY is refused succeeds' );
is( $delivered->{unread_count}, 1, 'and keeps the count it read' );

my @raised = @{ $functions->rolled_back };
is( scalar @raised,
    1, 'the refused NOTIFY is the one error its savepoint caught' );
ok( GPForum::X::Unavailable->caught( $raised[0] ),
    'as a GPForum::X::Unavailable' );
is(
    "$raised[0]",
    'badge NOTIFY failed: listener gone',
    'with the message the string carried'
);
is( $dispatcher->snapshot->{badge_failures}, 1, 'the failure is counted' );
is(
    $dispatcher->snapshot->{last_badge_error}{message},
    'badge NOTIFY failed: listener gone',
    'and kept for /metrics with the same text'
);

done_testing();

1;
