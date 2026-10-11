#!/usr/bin/env perl
# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause
use v5.40;
our $VERSION = '0.001';
use lib 'script/lib';
use Test::More;
use File::Temp                           qw(tempdir);
use GPForum::Performance::WorkflowStatus qw(statuses main);
use GPForum::Performance::Evidence       qw(finalize);
use GPForum::Performance::Support        qw(read_json write_json);

# This fallback is required to work before CPAN installation.
use constant SHA_LENGTH => 40;    ## no critic (ValuesAndExpressions::ProhibitConstantPragma)

my $values = statuses(
    {
        PERF_CONTRACTS    => 'failure',
        PERF_SETUP        => 'failure',
        PERF_TOOLS        => 'skipped',
        GITHUB_EVENT_NAME => 'pull_request'
    }
);
is( $values->{contracts}{status}, 'failed', 'failed contract visible' );
is( $values->{contracts}{failure_kind},
    'infrastructure_or_harness', 'contract failure classified' );
is( $values->{setup}{status}, 'failed', 'failed dependency setup visible' );
is( $values->{http_workflow}{status}, 'skipped', 'unexecuted HTTP not PASS' );
is( $values->{baseline_http}{status},
    'skipped', 'unexecuted paired baseline not PASS' );
is( $values->{pr_comment}{status},
    'skipped', 'read token has no privileged comment' );
is(
    statuses(
        { PERF_BASE_REPORT => 'failure', GITHUB_EVENT_NAME => 'pull_request' }
    )->{baseline_report}{status},
    'failed',
    'baseline finalization failure recorded'
);
my $output = tempdir( CLEANUP => 1 );
local $ENV{PERF_COMMIT} = 'a' x SHA_LENGTH;
local $ENV{PERF_MODE}   = 'main';
is( main( '--output', $output ), 0, 'fallback checkpoint succeeds' );
is(
    read_json("$output/metadata.json")->{commit},
    'a' x SHA_LENGTH,
    'fallback uses measured commit'
);
is( main( '--output', $output, '--check' ), 1, 'absent summary not PASS' );
finalize($output);
is( main( '--output', $output, '--check' ), 1, 'skipped collection not PASS' );
write_json( "$output/summary.json", { status => 'partial' } );
is( main( '--output', $output, '--check' ),
    0, 'partial timing data does not block deterministically' );
write_json( "$output/summary.json", { status => 'failed' } );
is( main( '--output', $output, '--check' ), 1, 'failure remains blocking' );
write_json( "$output/summary.json", {} );
is( main( '--output', $output, '--check' ), 1,
    'malformed summary cannot pass' );
done_testing;
