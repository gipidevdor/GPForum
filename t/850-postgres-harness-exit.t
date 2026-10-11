# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;
use Carp qw(croak);
use Const::Fast;
use English qw(-no_match_vars);
use Test::More;

our $VERSION = '0.001';
const my $EXIT_SHIFT    => 8;
const my $OTHER_FAILURE => 7;

# This needs no PostgreSQL connection: simply loading the harness must not
# let its END cleanup turn an explicit failure into a successful process.
for my $expected ( 0, 1, $OTHER_FAILURE ) {
    my $status = _exit_status("exit $expected;");
    is( $status, $expected,
        "harness END preserves explicit exit $expected without a database" );
}
cmp_ok( _exit_status('die "expected failure\\n";'),
    q{>}, 0, 'harness END preserves an uncaught exception without a database' );

done_testing();

sub _exit_status ($program) {
    my $pid = open my $output, q{-|}, $EXECUTABLE_NAME,
      '-Ilib', '-It/lib', '-MGPForum::Test::PostgresHarness', '-e',
      q{open STDERR, '>&', STDOUT or die $!; } . $program;
    defined $pid or croak "start harness exit check: $OS_ERROR";
    my $diagnostic = do { local $INPUT_RECORD_SEPARATOR = undef; <$output> };
    my $closed     = close $output;
    my $status     = $CHILD_ERROR >> $EXIT_SHIFT;
    croak "close harness output failed: $diagnostic" if !$closed && !$status;
    return $status;
}

1;
