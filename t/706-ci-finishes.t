# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use List::Util qw(any);
use Mojo::File qw(path);
use Test::More;

our $VERSION = '0.001';

const my $PUSH_LIMIT     => 30;
const my @JOBS           => qw(lint unit integration coverage);
const my @PER_PUSH       => qw(lint unit integration);
const my $SEPARATOR_CELL => qr/\A -+ \z/msx;
const my $NEVER_ON_MAIN =>
  q{cancel-in-progress: ${{ github.ref != 'refs/heads/main' }}};
const my $OWN_GROUP_ON_MAIN => q{group: ci-${{ github.event_name }}-}
  . q{${{ github.ref == 'refs/heads/main' && github.sha || github.ref }}};
const my $SCHEDULED => q{if: github.event_name == 'schedule' || }
  . q{(github.event_name == 'workflow_dispatch' && inputs.coverage)};

# ci.yml was one sequential job of about two hours with cancel-in-progress on
# every ref: each push to main cancelled the run before it, and main had no
# finished result. The integration tier ran twice and no prove ran in
# parallel. This holds the gate to the shape that finishes, and holds
# docs/CI.md to it: every check that ran before still runs.
my $ci   = path('.github/workflows/ci.yml')->slurp;
my $docs = path('docs/CI.md')->slurp;
my %job  = _jobs($ci);

is_deeply(
    [ sort keys %job ],
    [ sort @JOBS ],
    'ci.yml is four jobs: lint, unit, integration, coverage'
);

for my $name (@PER_PUSH) {
    my ($limit) = $job{$name} =~ /^[ ]{4}timeout-minutes: [ ] (\d+)$/msx;
    ok(
        defined $limit && $limit <= $PUSH_LIMIT,
        "$name stops within $PUSH_LIMIT minutes"
    );
    unlike( $job{$name}, qr/^[ ]{4}if:/msx,    "$name runs on every event" );
    unlike( $job{$name}, qr/^[ ]{4}needs:/msx, "$name waits for no other job" );
}

ok( index( $ci, $NEVER_ON_MAIN ) >= 0,
    'a run on main is never cancelled; other refs still cancel' );

# GitHub keeps one pending run per concurrency group and cancels the pending
# one when a newer run joins: with one group for main, a third push while a
# run was going cancelled the second before it started (39810565640 and
# 39812192048, 2026-10-22). Each commit on main has a group of its own.
ok( index( $ci, $OWN_GROUP_ON_MAIN ) >= 0,
    'each commit on main has its own group, so no pending run is dropped' );

my @integration = $ci =~ /(make [ ] integration)/gmsx;
is( scalar @integration, 1, 'the integration tier runs once' );
like(
    $job{integration},
    qr/make [ ] integration [ ] JOBS=\d+/msx,
    'in parallel, in the integration job'
);
like(
    $job{integration},
    qr/host=\/var\/run\/postgresql;/msx,
    'over the server\'s Unix socket'
);
like(
    $job{unit},
    qr/prove [ ] -l [ ] -j [ ] \d+ [ ] t$/msx,
    'the unit job runs t/ in parallel'
);
unlike(
    $ci,
    qr/prove [ ] -l\w*r\w* [ ] t$/msx,
    'and no prove recurses into t/integration again'
);
ok(
    index( $job{coverage}, $SCHEDULED ) >= 0,
    'coverage runs on the schedule and on demand only'
);
like(
    $ci,
    qr/^[ ]{2}schedule:\n(?:[ ]{4}[#][^\n]*\n)*[ ]{4}- [ ] cron:/msx,
    'on a schedule'
);

# The first coverage run that finished failed: t/performance runs the harness
# of script/lib/ in timed child processes, which Devel::Cover slows past their
# deadlines and whose output it mixes with the JSON they print, and the report
# selects lib/ only. Those tests run once, in the lint job. Nor could the
# artifact upload walk cover_db/'s thousands of files: it goes as one archive.
my $coverage = join "\n",
  grep { !/\A \s* [#]/msx } split /\n/msx, path('script/coverage')->slurp;
like(
    $coverage,
    qr/exec [ ] prove [ ] -l [ ] t [ ] t\/integration [ ] "[\$][@]"$/msx,
    'coverage measures t/ and t/integration'
);
unlike(
    $coverage,
    qr/t\/performance|prove [ ] -lr/msx,
    'and not the harness tests of t/performance'
);
ok( index( $job{coverage}, 'tar -czf cover_db.tar.gz cover_db' ) >= 0,
    'the coverage database is archived' );
like(
    $job{coverage},
    qr/name: [ ] gpforum-cover-db\n [ ]+ path: [ ] cover_db[.]tar[.]gz$/msx,
    'and uploaded as one file'
);

for my $check (
    'script/perlcritic',         'script/perltidy-check',
    'script/architecture-check', 'script/adr-index --check',
    'script/perl-syntax-check',  'node --test t/js/*.test.cjs',
  )
{
    ok( index( $job{lint}, $check ) >= 0, "lint runs $check" );
}

my @before = _table( $docs, 'Before: one job, in this order' );
my @after  = _table( $docs, 'After: four jobs' );
ok( @before > 0 && @after > 0, 'docs/CI.md lists the checks before and after' );

my %now = map { _code( $_->[1] ) => 1 } @after;
for my $row (@before) {
    my ( $was, $becomes ) = @{$row};
    my @commands =
      $becomes eq 'same'
      ? _code($was)
      : ( $becomes =~ /`([^`]+)`/gmsx );
    ok( ( !any { !$now{$_} } @commands ),
        "what ran as `${\ _code($was)}` still runs" );
}

for my $row (@after) {
    my ( $where, $command ) = ( _code( $row->[0] ), _code( $row->[1] ) );
    my @in = $where eq 'every job' ? @JOBS : ($where);
    for my $name (@in) {
        ok( index( $job{$name} // q{}, $command ) >= 0,
            "$name runs `$command`" );
    }
}

for my $step ( $ci =~ /^[ ]+run: [ ] ([^|>\n][^\n]*)$/gmsx ) {
    ok(
        ( any { index( $step, $_ ) == 0 } keys %now ),
        "docs/CI.md lists the step `$step`"
    );
}

done_testing;

# The jobs of a workflow, by name: each body runs from its two-space key to
# the next one, with every YAML alias (`*checkout`) replaced by the lines its
# anchor (`&checkout`) names, as GitHub reads them.
sub _jobs ($text) {
    my %anchor;
    my @lines = split /\n/msx, $text;
    for my $index ( 0 .. $#lines ) {
        my ( $indent, $name ) =
          $lines[$index] =~ /\A ([ ]*) (?:-[ ]|[\w-]+:[ ]) &([\w-]+) \z/msx
          or next;
        my @node;
        for my $line ( @lines[ $index + 1 .. $#lines ] ) {
            last if $line =~ /\A [ ]{0,${\ length $indent}} \S/msx;
            push @node, $line;
        }
        $anchor{$name} = join "\n", @node;
    }
    $text =~ s/[*]([\w-]+)$/$anchor{$1} \/\/ "*$1"/gemsx;
    my ($jobs) = $text =~ /^jobs:\n(.*)\z/msx;
    my @parts  = split /^[ ]{2}([\w-]+):\n/msx, $jobs;
    shift @parts;
    return @parts;
}

# The rows of the Markdown table under a ### heading, as lists of cells.
sub _table ( $text, $heading ) {
    my ($section) = $text =~ /^[#]{3} [ ] \Q$heading\E\n(.*?)(?:^[#]|\z)/msx;
    my @rows;
    for my $line ( split /\n/msx, $section // q{} ) {
        my ($inner) = $line =~ /\A [|] (.*) [|] \z/msx or next;
        my @cells   = map { s/\A \s+ | \s+ \z//grmsx } split /[|]/msx, $inner;
        next if $cells[0] =~ $SEPARATOR_CELL;
        push @rows, \@cells;
    }
    shift @rows;
    return @rows;
}

sub _code ($cell) {
    return $cell =~ /\A `([^`]+)` \z/msx ? $1 : $cell;
}

1;
