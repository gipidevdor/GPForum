# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use Test::More;

use lib 'lib';

use GPForum::Infrastructure::Text qw(has_text plain_excerpt trimmed);

our $VERSION = '0.001';

const my $SHORT    => 12;
const my $WIDE     => 40;
const my $ELLIPSIS => "\N{HORIZONTAL ELLIPSIS}";

# The text helpers every layer asked of its own copy: thirty-five of
# has_text, twenty-five of a trim, in several spellings, and two of an
# excerpt that left its entities escaped.

is( has_text('it'),  1, 'a non-empty string is text' );
is( has_text('0'),   1, 'and so is 0, which is false' );
is( has_text(q{}),   0, 'the empty string is not' );
is( has_text(undef), 0, 'nor is undef' );

is( trimmed("  a name \n"), 'a name', 'both ends lose their whitespace' );
is( trimmed("a\n b"),       "a\n b",  'the middle keeps its own' );
is( trimmed(undef),         q{},      'undef reads as the empty string' );

is(
    plain_excerpt( "<p>Tom &amp; Jerry</p>\n<p>&lt;b&gt; is bold</p>", $WIDE ),
    'Tom & Jerry <b> is bold',
    'tags become spaces and entities their characters, once'
);
is(
    plain_excerpt( '<p>one two three four</p>', $SHORT ),
    "one two$ELLIPSIS",
    'a long text ends on a whole word and an ellipsis'
);
is(
    plain_excerpt( '<p>one two, three</p>', $SHORT ),
    "one two$ELLIPSIS",
    'without the comma the cut fell after'
);
is( plain_excerpt( '<p>abcdefghijklmnopqrstuvwxyz</p>', $SHORT ),
    "abcdefghijk$ELLIPSIS", 'one long word is cut where it must be' );
is(
    plain_excerpt( '<p>one two three</p>', $SHORT + 1 ),
    'one two three',
    'a text that fits is whole'
);
is(
    plain_excerpt(
        '<p>a fit</p><p>right <a href="https://forum.example/t', $WIDE
    ),
    'a fit right',
    'a tag the HTML was cut through goes'
);
is( plain_excerpt( '<p>Q &amp; A &am', $WIDE ),
    'Q & A', 'and so does an entity' );
is( plain_excerpt( "<p>\N{NO-BREAK SPACE}  spaced\n\tout </p>", $WIDE ),
    'spaced out', 'whitespace is one space, and none at the ends' );
is( plain_excerpt( undef, $SHORT ), q{}, 'undef has no excerpt' );

done_testing();

1;
