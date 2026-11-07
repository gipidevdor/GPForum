# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use File::Temp qw(tempdir);
use Mojo::File qw(path);
use Test::More;

use lib 'lib';

use GPForum::Service::Operations::EvidenceHost qw(
  evidence_capture
  evidence_executable
  evidence_repository_root
  evidence_trimmed
);

our $VERSION = '0.001';

# What the staging and deploy drills ask of the host, in one place: the
# copies each carried had drifted -- one counted a command a signal killed
# as having succeeded, one fell back to the working directory for a
# checkout it could not find.

my $said =
  evidence_capture( [ 'sh', '-c', 'echo first; echo second >&2; exit 3' ] );
is_deeply(
    $said,
    { ok => 0, exit => 3, output => "first\nsecond\n" },
    'a command that fails gives its exit and all it printed, errors too'
);
is( evidence_capture( [ 'sh', '-c', 'exit 0' ] )->{ok},
    1, 'one that exits 0 succeeded' );
is( evidence_capture( [ 'sh', '-c', 'kill -KILL $$' ] )->{ok},
    0, 'one a signal killed did not, though its exit code reads 0' );

my $bin = path( tempdir( CLEANUP => 1 ) );
$bin->child('probe')->make_path;
$bin->child('tool')->spew("#!/bin/sh\n")->chmod( oct '755' );
{
    local $ENV{PATH} = "$bin";
    is( evidence_executable('tool'),   "$bin/tool", 'a tool is found on PATH' );
    is( evidence_executable('probe'),  undef, 'a directory is not a tool' );
    is( evidence_executable('absent'), undef, 'nor is a missing name' );
}

ok(
    -f path( evidence_repository_root(), 'cpanfile' ),
    'the checkout is the directory with the cpanfile'
);

is(
    evidence_trimmed("refused at line 9.\n\n"),
    'refused at line 9.',
    'an error loses the blank lines it ends with'
);
is( evidence_trimmed(undef), q{}, 'and undef reads as nothing' );

done_testing();

1;
