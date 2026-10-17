# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Test::More;

use lib 'lib';

use GPForum::Infrastructure::SqlFunction;

our $VERSION = '0.001';

# A call answered ahead takes its rows from the answers, once, and sends
# nothing; any other call, and every call once the code has returned or
# died, is sent. Sending is counted by replacing the one method that sends.
my @sent;
{
    no warnings 'redefine';    ## no critic (TestingAndDebugging::ProhibitNoWarnings) -- the one method that reaches the database, counted
    ## no critic (Variables::ProtectPrivateVars) -- that method is private, and counting it is the point
    *GPForum::Infrastructure::SqlFunction::_execute = sub {
        my ( $self, $entry, $bound ) = @_;
        push @sent, $entry->{function};
        return [ { sent => 1 } ];
    };
    ## use critic
}

my $functions =
  GPForum::Infrastructure::SqlFunction->new( schema => bless {}, 'Schema' );
my $post   = '018f1003-0001-7000-8000-000000000001';
my $other  = '018f1003-0002-7000-8000-000000000002';
my $viewer = '018f1002-0001-7000-8000-000000000001';
my %likes  = ( post_ids => [ $post, $other ], viewer_user_id => $viewer );
my $key    = $functions->answer_key( 'community_post_likes', \%likes );
my $rows   = [ { post_id => $post, like_count => 2, liked => 1 } ];

is(
    $key,
    $functions->answer_key( 'community_post_likes', {%likes} ),
    'the same call has the same key'
);
isnt(
    $key,
    $functions->answer_key(
        'community_post_likes', { %likes, viewer_user_id => undef }
    ),
    'a NULL is a value of its own'
);
isnt(
    $key,
    $functions->answer_key(
        'community_post_likes', { %likes, post_ids => [ $other, $post ] }
    ),
    'and so is another order of the same ids'
);

my @answered = GPForum::Infrastructure::SqlFunction->answering(
    { $key => $rows },
    sub {
        return (
            $functions->rows( 'community_post_likes', \%likes ),
            $functions->rows( 'community_post_likes', \%likes ),
            $functions->rows(
                'community_post_likes', { %likes, viewer_user_id => undef }
            ),
        );
    }
);
is_deeply( $answered[0], $rows, 'an answered call takes the rows given' );
is_deeply(
    $answered[1],
    [ { sent => 1 } ],
    'once: the same call again is sent'
);
is_deeply( $answered[2], [ { sent => 1 } ], 'a call no answer names is sent' );
is_deeply(
    [@sent],
    [ ('api.community_post_likes_v2') x 2 ],
    'two calls reached the database, the answered one did not'
);

@sent = ();
GPForum::Infrastructure::SqlFunction->answering( { $key => $rows },
    sub { return 1; } );
$functions->rows( 'community_post_likes', \%likes );
is( scalar @sent, 1, 'answers left untaken are dropped when the code returns' );

@sent = ();
my $died = !eval {
    GPForum::Infrastructure::SqlFunction->answering( { $key => $rows },
        sub { die "the page failed\n"; } );
    1;
};
ok( $died, 'a failure in the code propagates' );
$functions->rows( 'community_post_likes', \%likes );
is( scalar @sent, 1, 'and its answers are dropped all the same' );

@sent = ();
my $malformed = { %likes, post_ids => ['not a uuid'] };
my $empty     = GPForum::Infrastructure::SqlFunction->answering(
    {
        $functions->answer_key( 'community_post_likes', $malformed ) => $rows
    },
    sub { return $functions->rows( 'community_post_likes', $malformed ); }
);
is_deeply( $empty, [], 'a value PostgreSQL would refuse is no call at all' );
is( scalar @sent, 0, 'and nothing is sent for it' );

done_testing();

1;
