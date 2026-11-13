# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;
use Const::Fast;
use Test::More;
use Time::HiRes qw(time);
use lib 'lib';
use lib 't/lib';

use GPForum::Infrastructure::AsyncWork;

our $VERSION = '0.001';

const my $DEADLINE    => 1;
const my $HUNG        => 60;
const my $SLACK       => 10;
const my $ANSWER      => 42;
const my $UNAVAILABLE => 'GPForum::X::Unavailable';

# A cpu_p child that never returns is killed at the lane's deadline: its
# caller is refused, and the lane's one slot serves the next request.
my $work = GPForum::Infrastructure::AsyncWork->new( cpu_timeout => $DEADLINE );
my $started = time;
my $error;
$work->cpu_p( sub { sleep $HUNG; return 1; } )
  ->then( sub (@) { $error = 'answered' }, sub ($caught) { $error = $caught } )
  ->wait;
isa_ok( $error, $UNAVAILABLE, 'a hung child' );
like( "$error", qr/deadline/msx, 'is refused for its deadline' );
cmp_ok( time - $started, '<', $SLACK, 'long before it would have returned' );

my $answer;
$work->cpu_p( sub { return $ANSWER; } )
  ->then( sub ($value) { $answer = $value } )
  ->wait;
is( $answer, $ANSWER, 'the lane serves the next child' );

my $failure;
$work->cpu_p( sub { die "plain failure\n" } )
  ->catch( sub ($caught) { $failure = $caught } )
  ->wait;
like(
    "$failure",
    qr/\Aplain[ ]failure\n\z/msx,
    'an ordinary failure inside the deadline is passed through'
);

done_testing();

1;
