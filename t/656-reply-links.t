# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use Test::Fatal;
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Infrastructure::SqlFunction;
use GPForum::Service::Forum::ReplyLinks;
use GPForum::Test::SqlFunctionHandle;

our $VERSION = '0.001';

# Which post a reply answers (ADR 0132), on a handle that records the call
# and answers what the test gives: a link, a target that is not an id, and
# the page's read of its posts' targets.

const my $REPLY  => '018f1005-0002-7000-8000-000000000002';
const my $TARGET => '018f1005-0001-7000-8000-000000000001';

sub fixture ( $rows = [] ) {
    my $handle = GPForum::Test::SqlFunctionHandle->new( rows => $rows );
    my $links  = GPForum::Service::Forum::ReplyLinks->new(
        functions =>
          GPForum::Infrastructure::SqlFunction->new( schema => $handle ),
        schema => $handle,
    );
    return ( $handle, $links );
}

subtest 'a reply is linked to the post it answers' => sub {
    my ( $handle, $links ) = fixture( [ { linked => 1 } ] );
    is( $links->link_reply( $REPLY, $TARGET ), 1, 'the link holds' );
    like(
        $handle->prepared->[0],
        qr/api[.]forum_link_reply_v2/msx,
        'through the link function'
    );
    is_deeply(
        [ @{ $handle->executed->[0] } ],
        [ $REPLY, $TARGET ],
        'with the reply and the post it answers'
    );
};

subtest 'a target that is not an id links nothing' => sub {
    my ( $handle, $links ) = fixture( [ { linked => 1 } ] );
    is( $links->link_reply( $REPLY, 'post-1' ), 0, 'nothing is linked' );
    is( scalar @{ $handle->executed }, 0, 'and the database heard nothing' );
};

subtest 'the page reads the targets of its posts in one call' => sub {
    my ( $handle, $links ) = fixture(
        [
            {
                post_id                  => $REPLY,
                reply_to_author_username => 'giacomo',
                reply_to_position        => 1,
                reply_to_post_id         => $TARGET,
            }
        ]
    );
    is_deeply(
        $links->targets_for_posts( [ $REPLY, $TARGET ] ),
        {
            $REPLY => {
                author_username => 'giacomo',
                position        => 1,
                post_id         => $TARGET
            }
        },
        'a post that answers one names it; one that answers none is absent'
    );
    like(
        $handle->prepared->[0],
        qr/api[.]forum_reply_targets_v2/msx,
        'through the targets function'
    );
    is_deeply( $links->targets_for_posts( [] ), {}, 'no posts ask nothing' );
    is( scalar @{ $handle->executed }, 1, 'of the database' );
};

subtest 'reply links exist only as functions' => sub {
    my $links = GPForum::Service::Forum::ReplyLinks->new(
        functions => undef,
        schema    => GPForum::Test::SqlFunctionHandle->new,
    );
    like(
        exception { $links->targets_for_posts( [$REPLY] ) },
        qr/SQL [ ] function [ ] layer/msx,
        'without the call layer the store refuses to guess'
    );
};

done_testing();

1;
