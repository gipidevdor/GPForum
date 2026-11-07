# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package main;
use v5.40;
use Test::More;
use lib 'lib', 't/lib';
use GPForum::Infrastructure::AsyncWork;
use GPForum::Schema;
use GPForum::Test::Promise qw(await_result);
our $VERSION = '0.001';

use GPForum::Test::AsyncResult;

my $schema  = GPForum::Schema->connect('dbi:Pg:dbname=unused_async_result');
my $service = GPForum::Test::AsyncResult->new( schema => $schema );
my $work    = GPForum::Infrastructure::AsyncWork->new;
my $row     = await_result( $work->service_result_p( $service, 'inbox', [] ) );
isa_ok( $row, 'GPForum::Infrastructure::ResultRow::NotificationInbox' );
isa_ok( $row->notification,
    'GPForum::Infrastructure::ResultRow::Notification' );
is( $row->notification->get_column('notification_type'), 'direct_message',
    'prefetched relationships survive IPC without replaying their constructor'
);
is_deeply(
    $row->notification->get_column('payload'),
    { body => 'message' },
    'the notification payload retains its data'
);
is(
    $row->get_column('source_thread_title'),
    'prefetched title',
    'joined columns survive'
);
my $error;
$work->service_result_p( $service, 'invalid', [] )
  ->catch( sub ($failure) { $error = $failure; return; } )
  ->wait;
isa_ok( $error, 'GPForum::X::Argument' );
is( "$error", 'invalid endpoint',
    'typed refusal retains its original message' );
done_testing();
1;
