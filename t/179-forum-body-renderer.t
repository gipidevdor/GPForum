# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use Test::More;

use lib 'lib';

use GPForum::Service::Forum::BodyRenderer;
use GPForum::ViewModel::Forum::Rows;

our $VERSION = '0.001';

my $renderer = GPForum::Service::Forum::BodyRenderer->new;

is( $renderer->render_safe(undef), q{}, 'undef source renders empty' );
is( $renderer->render_safe(q{}),   q{}, 'empty source renders empty' );
is(
    $renderer->render_safe('Hello <forum> & welcome'),
    '<p>Hello &lt;forum&gt; &amp; welcome</p>',
    'plain text is escaped and wrapped'
);

my $xss = $renderer->render_safe(
    "<script>alert(1)</script>\n[bad](javascript:alert(1))");
unlike( $xss, qr/<script/imsx, 'script tags are not emitted' );
like( $xss, qr/&lt;script&gt;/msx, 'script tags are escaped as text' );
unlike( $xss, qr/<a\b/imsx, 'javascript links are not turned into anchors' );

my $fenced =
  $renderer->render_safe("intro\n```\n<script>alert(1)</script>\n```\nafter");
is(
    $fenced,
"<p>intro</p>\n<pre><code>&lt;script&gt;alert(1)&lt;/script&gt;</code></pre>\n<p>after</p>",
    'fenced code preserves escaped source'
);
unlike( $fenced, qr{<pre><code>.*<script}imsx,
    'fenced code does not contain a live script tag' );

# A code span shows what was typed: escaped, and read by nothing else.
is(
    $renderer->render_safe('Move it from `LIKE` to an index.'),
    '<p>Move it from <code>LIKE</code> to an index.</p>',
    'backticks on one line make a code span'
);
is(
    $renderer->render_safe('`<script>alert(1)</script>`'),
    '<p><code>&lt;script&gt;alert(1)&lt;/script&gt;</code></p>',
    'a code span escapes what it holds'
);
is(
    $renderer->render_safe('`**bold** [x](https://example.com)` and *this*'),
    '<p><code>**bold** [x](https://example.com)</code> and <em>this</em></p>',
    'emphasis and links are not read inside a code span'
);
is(
    $renderer->render_safe('a ` on its own'),
    '<p>a ` on its own</p>',
    'a backtick with no partner stays a backtick'
);
is( $renderer->render_safe("`one\ntwo`"),
    '<p>`one<br>two`</p>', 'a code span does not reach across a line' );

my $quote = $renderer->render_safe("> quoted <em>html</em>\n> **bold**");
is(
    $quote,
'<blockquote><p>quoted &lt;em&gt;html&lt;/em&gt;<br><strong>bold</strong></p></blockquote>',
    'quotes wrap escaped lines and still apply emphasis'
);

is(
    $renderer->render_safe('See [docs](https://example.com/a?x=1&y=2).'),
'<p>See <a href="https://example.com/a?x=1&amp;y=2" rel="nofollow noopener noreferrer">docs</a>.</p>',
    'http links are allowed after escaping'
);
is(
    $renderer->render_safe('*italic* and **bold**'),
    '<p><em>italic</em> and <strong>bold</strong></p>',
    'emphasis markers become em and strong'
);

my $mention = q{@} . 'alice';
my $leftover =
  $renderer->render_safe("![logo](https://example.com/x.png) and $mention");
unlike( $leftover, qr/<img\b/imsx,          'inline images are not rendered' );
unlike( $leftover, qr{href="[^"]*alice}msx, 'mentions are not linked' );
ok( index( $leftover, $mention ) >= 0, 'mentions remain literal text' );

my $rows = GPForum::ViewModel::Forum::Rows->new;
my $post = $rows->post(
    {
        body_source => '**Safe** <script>alert(1)</script>',
        post_id     => 'post-9',
        thread_id   => 'thread-1',
    }
);
is(
    $post->{body},
    '<p><strong>Safe</strong> &lt;script&gt;alert(1)&lt;/script&gt;</p>',
    'post presenter renders markdown source through the body renderer'
);
unlike( $post->{body}, qr/<script/imsx,
    'post presenter does not emit script tags from source' );

subtest 'inline markup and block boundaries' => sub {
    my $rel = 'rel="nofollow noopener noreferrer"';

    my @cases = (
        [
            '[x](https://e.x/"q)',
            '<p>[x](https://e.x/&quot;q)</p>',
            'a URL holding an entity other than &amp; is not linked'
        ],
        [
            '[x](https://e.x/?a=1&b=2)',
            qq{<p><a href="https://e.x/?a=1&amp;b=2" $rel>x</a></p>},
            'a URL whose only entity is &amp; is linked'
        ],
        [
            '[x](https://e.x/a b)',
            '<p>[x](https://e.x/a b)</p>',
            'a URL with a space is not linked'
        ],
        [
            '[x](HTTPS://e.x/)',
            qq{<p><a href="HTTPS://e.x/" $rel>x</a></p>},
'the scheme is matched without regard to case, the URL kept as typed'
        ],
        [
            '[x](MailTo:a@e.x)',
            qq{<p><a href="MailTo:a\@e.x" $rel>x</a></p>},
            'a mailto link of any case is linked'
        ],
        [
            '[x](javascript:alert(1))',
            '<p>[x](javascript:alert(1))</p>',
            'a scheme outside http, https and mailto is not linked'
        ],
        [
            '![x](https://e.x/i.png)',
            '<p>![x](https://e.x/i.png)</p>',
            'an image is not turned into a link'
        ],
        [ "*a\nb*", '<p>*a<br>b*</p>', 'emphasis does not cross a line' ],
        [ 'a ** b', '<p>a ** b</p>',   'a pair around nothing stays as typed' ],
        [ "a\rb",   '<p>a<br>b</p>',   'a lone carriage return ends a line' ],
        [
            "```a`b\nx\n```",
            "<p>``<code>a</code>b<br>x</p>\n<p>```</p>",
            'an info string with a backtick opens no fence'
        ],
        [
            "```\nx\n```y\nz\n```",
            "<pre><code>x\n```y\nz</code></pre>",
            'a backtick line with text after it does not close a fence'
        ],
        [
            '    > q',
            '<p>    &gt; q</p>',
            'a quote marker indented four spaces is text'
        ],
        [
            '   > q',
            '<blockquote><p>q</p></blockquote>',
            'a quote marker indented three spaces opens a quote'
        ],
        [
            "```\na\n```\n\n```\nb\n```",
            "<pre><code>a</code></pre>\n<pre><code>b</code></pre>",
            'blank prose between fences adds no empty line'
        ],
        [
            '[x](https://e.x/) wow!',
            qq{<p><a href="https://e.x/" $rel>x</a> wow!</p>},
            'a link at the start is linked when the text ends in "!"'
        ],
        [
            "    ```\nx\n```",
            "<p>    ```<br>x</p>\n<p>```</p>",
            'a fence marker indented four spaces is text'
        ],
        [ "a\n\nb", "<p>a</p>\n<p>b</p>", 'a blank line ends a paragraph' ],
        [
            "> a\n\n> b",
"<blockquote><p>a</p></blockquote>\n<blockquote><p>b</p></blockquote>",
            'a blank line ends a quote'
        ],
        [
            "> a\n>\n> b",
            "<blockquote><p>a</p>\n<p>b</p></blockquote>",
            'an empty quoted line splits the quote into paragraphs'
        ],
        [
            "`a\nb` `c`",
            q{<p>`a<br>b<code> </code>c`</p>},
            'a code span does not cross a line'
        ],
        [
            '[*x](https://e.x/) y*',
            qq{<p><a href="https://e.x/" $rel>*x</a> y*</p>},
            'emphasis does not reach across the end of a link'
        ],
        [
            '[x](https://e.x/) and (y)',
            qq{<p><a href="https://e.x/" $rel>x</a> and (y)</p>},
            'a link ends at the first ")" after its URL opens'
        ],
        [
            '[a](https://e.x/a) [b](https://e.x/b)',
            qq{<p><a href="https://e.x/a" $rel>a</a> }
              . qq{<a href="https://e.x/b" $rel>b</a></p>},
            'two links on a line are both linked'
        ],
        [
            "> a\nb",
            "<blockquote><p>a</p></blockquote>\n<p>b</p>",
            'an unquoted line after a quote starts a paragraph'
        ],
        [
            "a\n> b",
            "<p>a</p>\n<blockquote><p>b</p></blockquote>",
            'a quoted line after a paragraph starts a quote'
        ],
        [
            ">\n> a\n>",
            '<blockquote><p>a</p></blockquote>',
            'empty quoted lines around a quote add no empty paragraph'
        ],
    );

    for my $case (@cases) {
        my ( $source, $expected, $name ) = @{$case};
        is( $renderer->render_safe($source), $expected, $name );
    }
};

subtest 'ordered and unordered lists' => sub {
    my @cases = (
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
            "```\n- item\n```",
            '<pre><code>- item</code></pre>',
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
};

done_testing();

1;
