# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use English qw(-no_match_vars);
use Test::More;

use lib 'lib';

use GPForum::Benchmark::PostgresMetrics qw(process_snapshot ps_cpu_seconds);

our $VERSION = '0.001';

# The PostgreSQL backend's CPU, as bench-postgres-configuration reports it:
# ps's time column read in each form it takes. FreeBSD read one -o argument
# as a header and gave nothing, and Linux's hours were dropped.

for my $case (
    [ '0:01.23',    q{1.23},   'MM:SS.ss, as macOS and FreeBSD print it' ],
    [ '00:00:05',   q{5},      'HH:MM:SS, as Linux prints it' ],
    [ '1-02:03:04', q{93784},  'with the days Linux puts before a long one' ],
    [ '1:02:03.50', q{3723.5}, 'HH:MM:SS.ss' ],
  )
{
    my ( $time, $seconds, $name ) = @{$case};
    is( ps_cpu_seconds($time), $seconds, $name );
}
is( ps_cpu_seconds('TIME'), undef, 'a header is not a time' );
is( ps_cpu_seconds(undef),  undef, 'nor is nothing' );

my $self = process_snapshot($PROCESS_ID);
ok( defined $self && $self->{rss_kib} > 0, 'this process has a resident size' );
ok( defined $self && $self->{cpu_seconds} >= 0, 'and a CPU time' );
is( process_snapshot('1; ps'), undef, 'a pid is a number' );

done_testing();

1;
