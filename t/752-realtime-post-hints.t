# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Service::Realtime::OutboxEventMapper;

our $VERSION = '0.001';

const my $EVENT  => '018f1000-0000-7000-8000-000000000901';
const my $POST   => '018f1000-0000-7000-8000-000000000902';
const my $THREAD => '018f1000-0000-7000-8000-000000000903';

# A post's event is a hint on its thread's channel. The hub sends a hint
# naming a post to those who may read that post now; a deleted post nobody
# may read, so its hint names the thread alone, and reaches the thread's
# readers.
my $mapper = GPForum::Service::Realtime::OutboxEventMapper->new;
my %frame;
for my $type (qw(post.created post.deleted)) {
    ( $frame{$type} ) = $mapper->events_for_payload(
        {
            event_id       => $EVENT,
            event_type     => $type,
            aggregate_type => 'post',
            aggregate_id   => $POST,
            domain_payload => { post_id => $POST, thread_id => $THREAD },
        }
    );
}

is_deeply(
    $frame{'post.created'}{payload},
    { post_id => $POST, thread_id => $THREAD },
    'a new post names the post and its thread'
);
is_deeply(
    $frame{'post.deleted'}{payload},
    { thread_id => $THREAD },
    'a deleted one names only the thread it left'
);
is( $frame{'post.deleted'}{aggregate_id}, $THREAD, 'on the thread\'s channel' );

done_testing();

1;
