# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause
package main;
use v5.40;
use Test::More;
use lib 'lib';
use GPForum::Service::Forum::BodyRenderer;
our $VERSION = '0.001';
my $renderer = GPForum::Service::Forum::BodyRenderer->new;
my @cases    = (
    [
        "- first\n- second", '<ul><li>first</li><li>second</li></ul>',
        'bullets'
    ],
    [
        "+ first\n* second",
        '<ul><li>first</li><li>second</li></ul>',
        'mixed bullet markers'
    ],
    [
        "1. first\n2. second",
        '<ol><li>first</li><li>second</li></ol>',
        'numbered list'
    ],
    [
        "3) third\n4) fourth",
        '<ol start="3"><li>third</li><li>fourth</li></ol>',
        'non-default start'
    ],
    [ '0. zero', '<ol start="0"><li>zero</li></ol>', 'zero start' ],
    [
        "before\n- item\nafter",
        "<p>before</p>\n<ul><li>item</li></ul>\n<p>after</p>",
        'paragraph boundaries'
    ],
    [
        "- a\n\n- b",
        "<ul><li>a</li></ul>\n<ul><li>b</li></ul>",
        'blank ends list'
    ],
    [
        "- a\n1. b",
        "<ul><li>a</li></ul>\n<ol><li>b</li></ol>",
        'list type transition'
    ],
    [
        '- **bold** and `code`',
        '<ul><li><strong>bold</strong> and <code>code</code></li></ul>',
        'inline formatting'
    ],
    [
        '- <img src=x onerror=alert(1)>',
        '<ul><li>&lt;img src=x onerror=alert(1)&gt;</li></ul>',
        'HTML escaped'
    ],
    [
        '- [x](javascript:alert(1))',
        '<ul><li>[x](javascript:alert(1))</li></ul>',
        'unsafe link stays text'
    ],
    [
        '> - item',
        '<blockquote><p>- item</p></blockquote>',
        'quoted list marker stays quoted text'
    ],
    [
        "```\n- item\n```", '<pre><code>- item</code></pre>',
        'fence stays code'
    ],
    [ '    - item', '<p>    - item</p>',      'four spaces stays literal' ],
    [ '   - item',  '<ul><li>item</li></ul>', 'three spaces accepted' ],
    [
        '1234567890. item',
        '<p>1234567890. item</p>',
        'unbounded start rejected'
    ],
    [ '-nospace',   '<p>-nospace</p>', 'marker requires separator' ],
    [ "-\n*",       '<p>-<br>*</p>',   'empty markers stay literal' ],
    [ "- a\r\n- b", '<ul><li>a</li><li>b</li></ul>', 'CRLF normalization' ],
);

for my $case (@cases) {
    is( $renderer->render_safe( $case->[0] ), $case->[1], $case->[2] );
}
done_testing;
1;
