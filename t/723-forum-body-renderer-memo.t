# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use List::Util qw(max);
use Test::More;

use lib 'lib';

use GPForum::Service::Forum::BodyRenderer;

our $VERSION = '0.001';

# The renderer keeps the HTML of the bodies it rendered, by source, for the
# thread pages that render the same 25 bodies on every read. It was bounded
# by count alone: 2,048 bodies at the 50,000-character limit, each rendered
# six times as long ('"' becomes &quot;), and a member previewing distinct
# bodies grew a worker by more than 500 MB. What it keeps is bounded by the
# characters it holds.

const my $BODIES    => 200;
const my $LONGEST   => 50_000;
const my $SUFFIX    => 10;
const my $SMALL     => 'A *short* [link](https://example.com/a).';
const my $EXPANSION => 6;

my $renderer = GPForum::Service::Forum::BodyRenderer->new;
my $budget   = GPForum::Service::Forum::BodyRenderer->memo_characters;
ok( $budget > 0, 'the memo has a budget in characters' );
ok(
    $budget < $BODIES * $LONGEST * ( 1 + $EXPANSION ),
    'smaller than the bodies this test renders'
);

my $first = $renderer->render_safe($SMALL);
is( $renderer->render_safe($SMALL), $first, 'a body renders the same twice' );
ok( GPForum::Service::Forum::BodyRenderer->held_characters >= length $SMALL,
    'and is kept' );

my @held;
my ( $source, $html );
for my $number ( 1 .. $BODIES ) {
    $source = ( q{"} x ( $LONGEST - $SUFFIX ) ) . sprintf '%010d', $number;
    $html   = $renderer->render_safe($source);
    push @held, GPForum::Service::Forum::BodyRenderer->held_characters;
}
is( $renderer->render_safe($source), $html, 'the last body renders the same' );
my $largest = max @held;
ok( $largest <= $budget,
    "the memo never held more than its budget ($largest of $budget)" );
ok( $largest > 0, 'and still kept what fits' );

done_testing();

1;
