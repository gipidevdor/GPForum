# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use English    qw(-no_match_vars);
use Mojo::Util qw(monkey_patch);
use Test::More;

use lib 'lib';

use GPForum::Service::Forum::BodyRenderer;

our $VERSION = '0.001';

# A body is rendered on every read, so the renderer must do work in
# proportion to the body, whatever the body holds. Time is not measured --
# a slow machine would fail a fast renderer and a fast one pass a slow one --
# the characters the renderer inspects are counted instead: every forward
# search for a bracket of a link, every scan for a flaw in its URL, and
# every line read to see whether it opens or closes a fence. N lines of
# "```a" once read the rest of the body for each line: 4,000 of them took
# three seconds.

const my $LINES         => 8_000;
const my $RUN           => 40_000;
const my $WORK_PER_CHAR => 6;
const my $SLACK         => 64;
const my $INDEX_MISS    => -1;

my $work = 0;

my %meters = (
    _closes => sub ( $line, @ ) { return length $line; },
    _flaw   => sub ( $text, $from, $found ) { return $found - $from + 1; },
    _opens  => sub ( $line, @ ) { return length $line; },
    _scan   => sub ( $text, $needle, $from, $found ) {
        return (
            $found == $INDEX_MISS ? length $text : $found + length $needle ) -
          $from;
    },
);

my @adversaries = (
    [ 'lines that each open a fence', "```a\n" x $LINES ],
    [ 'one fence never closed',       "```a\n" . ( "x\n" x $LINES ) ],
    [ 'openers closed by the last line', ( "```a\n" x $LINES ) . "```\n" ],
    [ 'fence marks alone',     "```\n" x $LINES ],
    [ 'brackets with no link', q{[} x $RUN ],
    [ 'brackets before one bad link', ( q{[} x $RUN ) . '](javascript:x)' ],
    [ 'link starts that never end', ( '[a](' x $LINES ) . ')' ],
    [
        'nested links with a space at the end',
        ( '[a](https://x' x $LINES ) . ' )'
    ],
    [ 'links holding a quote', ( '[a](https://x"' x $LINES ) . ')' ],
    [ 'stars',                    q{*} x $RUN ],
    [ 'stars on their own lines', "*\n" x $LINES ],
    [ 'backticks',                q{`} x $RUN ],
    [ 'unclosed code spans',      "`a\n" x $LINES ],
    [ 'quoted lines',             "> x\n" x $LINES ],
);

for my $adversary (@adversaries) {
    my ( $name, $source ) = @{$adversary};
    $work = 0;
    my $html = _metered( sub { return _render($source); } );
    ok( length $html, "$name: rendered" );
    cmp_ok( $work, '>=', length $source, "$name: every character is read" );
    cmp_ok(
        $work, '<=',
        $WORK_PER_CHAR * length($source) + $SLACK,
        "$name: in proportion to the body"
    );
}

# The single pass gives what the line-by-line search gave.
my @kept = (
    [ "```a\n```a\n", "<p>```a</p>\n<p>```a</p>", 'two openers, no close' ],
    [
        "x\n```a\ncode\n```\ny",
        "<p>x</p>\n<pre><code>code</code></pre>\n<p>y</p>",
        'a fence between prose'
    ],
    [
        "```a\n```b\n```\n",
        '<pre><code>```b</code></pre>',
        'an opener inside a fence is its text'
    ],
    [ "```a\nx\n```b", "<p>```a<br>x</p>\n<p>```b</p>", 'an unclosed fence' ],
    [ '```a',          '<p>```a</p>', 'an opener with no newline' ],
    [
        '[[a](https://x) [b](http://y z)',
        '<p><a href="https://x" rel="nofollow noopener noreferrer">[a</a> '
          . '[b](http://y z)</p>',
        'a link takes the first bracket, a space ends one'
    ],
    [
        '[a](https://x&amp;y) [b](https://x&y)',
        '<p><a href="https://x&amp;amp;y" rel="nofollow noopener noreferrer">'
          . 'a</a> <a href="https://x&amp;y" rel="nofollow noopener noreferrer">'
          . 'b</a></p>',
        'an ampersand typed escaped and bare'
    ],
    [
        '[a](https://x [b](https://y)',
        '<p>[a](https://x <a href="https://y" '
          . 'rel="nofollow noopener noreferrer">b</a></p>',
        'a link after a bad one that shares its end'
    ],
);
for my $case (@kept) {
    my ( $source, $html, $name ) = @{$case};
    is( _render($source), $html, $name );
}

done_testing();

sub _render ($source) {
    return GPForum::Service::Forum::BodyRenderer->new->render_safe($source);
}

# $original wrapped to add what it read, by the meter for $name, to $work.
sub _meter ( $name, $original ) {
    return sub (@arguments) {
        my $found = $original->(@arguments);
        $work += $meters{$name}->( @arguments, $found );
        return $found;
    };
}

# Runs $code with each counted helper wrapped, adding what it read to $work.
sub _metered ($code) {
    my $package = 'GPForum::Service::Forum::BodyRenderer';
    my %saved   = map { $_ => $package->can($_) } keys %meters;
    monkey_patch $package, map { $_ => _meter( $_, $saved{$_} ) } keys %meters;
    my $result = eval { $code->() };
    my $error  = $EVAL_ERROR;
    monkey_patch $package, %saved;
    die $error if !defined $result;    ## no critic (RequireCarping)

    return $result;
}

1;
