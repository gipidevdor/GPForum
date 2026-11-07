# SPDX-FileCopyrightText: 2026 GPForum Contributors
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

my $held_before    = GPForum::Service::Forum::BodyRenderer->held_characters;
my $oversized      = q{"} x ( int( $budget / ( 1 + $EXPANSION ) ) + 1 );
my $oversized_html = $renderer->render_safe($oversized);
cmp_ok( length($oversized) + length($oversized_html),
    '>', $budget, 'the oversized result cannot fit in the memo' );
is( GPForum::Service::Forum::BodyRenderer->held_characters,
    $held_before, 'an oversized render leaves the existing hot bodies cached' );
is( $renderer->render_safe($source),
    $html, 'the previously cached body still has the same rendering' );
is( GPForum::Service::Forum::BodyRenderer->held_characters,
    $held_before, 'and reading it does not insert it again' );

subtest
  'one insertion evicts progressively instead of clearing every hot body' =>
  sub {
    my $render  = GPForum::Service::Forum::BodyRenderer->can('_render');
    my $renders = 0;
    no warnings 'redefine';
    local *GPForum::Service::Forum::BodyRenderer::_render = sub {
        ++$renders;
        return $render->(@_);
    };
    $renderer->render_safe("LRU retention body $_") for 1 .. 2048;
    my $hot = $renderer->render_safe('LRU retention body 2048');
    $renderer->render_safe('one additional LRU body');
    my $before = $renders;
    is( $renderer->render_safe('LRU retention body 2048'),
        $hot, 'recent body stays byte-identical' );
    is( $renders, $before,
        'recent body did not need rendering after capacity was reached' );
  };

subtest 'concurrent misses for the same source share one subprocess' => sub {
    my $start  = GPForum::Infrastructure::Subprocess->can('_start');
    my $starts = 0;
    no warnings 'redefine';
    local *GPForum::Infrastructure::Subprocess::_start = sub {
        ++$starts;
        return $start->(@_);
    };
    my $source = 'same concurrent source not previously rendered';
    my @work   = map { $renderer->render_many_p( [$source] ) } 1 .. 2;
    Mojo::Promise->all(@work)->wait;
    is( $starts, 1, 'only one actual subprocess starts' );
    my @result;
    $_->then( sub ($value) { push @result, $value; return; } )->wait for @work;
    is_deeply( $result[0], $result[1],
        'both consumers receive the same safe HTML' );
};

done_testing();

1;
