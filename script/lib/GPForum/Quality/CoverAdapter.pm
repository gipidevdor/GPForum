# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package GPForum::Quality::CoverAdapter;
use v5.40;
use B::Deparse ();
use Carp       qw(croak);
use English    qw(-no_match_vars);
use Const::Fast;
use Mojo::Util qw(monkey_patch);
our $VERSION = '0.001';

# Loaded by script/coverage after Devel::Cover 1.52, which writes a full
# report at every exec as well as at the end of each test. Two of its habits
# broke the tests it measured, and both are undone here, for coverage runs
# only.

# The precedence B::Deparse gives the operand of a named unary operator.
const my $UNARY_OPERAND => 16;

# The process this test runs in; a different $$ is a child it forked.
const my $TEST_PROCESS => $PROCESS_ID;

# 1. Devel::Cover names each condition by deparsing it. B::Deparse knows no
# Future::AsyncAwait op (nor, on newer perls, every signature op) and warned
# once per unknown op from its AUTOLOAD -- 1.16 million lines in one run --
# which a child that redirected STDERR carried into the output its test reads.

# `await EXPR`: the awaited expression is the op's only child.
sub _await ( $deparse, $op, $context ) {
    return 'await ' . $deparse->deparse( $op->first, $UNARY_OPERAND );
}

# Any other op B::Deparse has no handler for -- the async epilogue, the list
# mark ahead of its wrapper -- is no source of its own: name it with nothing,
# quietly. A method that is not an op handler stays an error, as before.
# Installed as B::Deparse::AUTOLOAD, it finds the name in that package.
sub _unhandled ( $deparse, @ ) {
    my $called = $B::Deparse::AUTOLOAD;
    return q{} if $called =~ /::pp_\w+\z/msx;
    croak "Undefined subroutine $called called";
}

monkey_patch 'B::Deparse', pp_await => \&_await, AUTOLOAD => \&_unhandled;

# 2. A child forked only to exec a server or a tool ran a handful of lines
# since the fork, yet its report at exec deparsed the whole application: more
# than a minute per child, while its test waited for the program it started
# (the Gemini listener never came up in time). Such a report is skipped; a
# child that runs to its own end still reports there, and so does the test.
if ( my $report = Devel::Cover->can('report') ) {
    monkey_patch 'Devel::Cover', report => sub (@arguments) {
        my $phase = ${^GLOBAL_PHASE};    ## no critic (Variables::ProhibitPunctuationVars) -- Perl exposes the phase only through this special variable
        return if $PROCESS_ID != $TEST_PROCESS && $phase ne 'END';
        return $report->(@arguments);
    };
}

1;
