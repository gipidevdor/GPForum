# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package main;
use v5.40;
use Const::Fast;
use FindBin;
use File::Temp qw(tempdir);
use Test::More;
use JSON::MaybeXS qw(decode_json);
use Mojo::File    qw(path);
use lib "$FindBin::Bin/../../script/lib", "$FindBin::Bin/../../lib";
use GPForum::Performance::Support qw(run_bounded read_json);
our $VERSION = '0.001';
const my $TIMEOUT             => 180;
const my $WORKER_CLIENTS      => 32;
const my $RECYCLE_CONNECTIONS => 10_000;
my $directory = tempdir( CLEANUP => 1 );
my $output    = "$directory/http";
local $ENV{GPFORUM_WARMUP_ENABLED} = 0;
my $log = run_bounded(
    [
        "$FindBin::Bin/../../script/gpforum-carton",
        'exec',
        "$FindBin::Bin/../../script/benchmark-http-complete",
        '--output',
        $output,
        '--profile',
        'smoke',
        '--worker-clients',
        $WORKER_CLIENTS,
    ],
    { timeout => $TIMEOUT }
);
my $report = read_json("$output/http-complete.json");
is( $report->{status}, 'ok', 'all real HTTP smoke scenarios passed' );
like(
    $report->{connection_policy},
    qr/Fresh[ ]connections[ ]per[ ]cell/msx,
    'cell connection isolation is explicit in the evidence'
);
is( $report->{configuration}{worker_clients},
    $WORKER_CLIENTS, 'the selected per-worker admission limit is recorded' );
is_deeply( $report->{failures}, [], 'no swallowed HTTP or business failure' );
is(
    scalar @{ $report->{worker_telemetry} },
    $report->{configuration}{workers},
    'every serving worker was observed'
);

for my $worker ( @{ $report->{worker_telemetry} } ) {
    is( $worker->{worker_clients},
        $WORKER_CLIENTS,
        "worker $worker->{pid} uses the requested admission limit" );
    is( $worker->{loop_max_connections},
        $WORKER_CLIENTS,
        "worker $worker->{pid} has the actual event-loop admission limit" );
    is( $worker->{loop_max_accepts},
        $RECYCLE_CONNECTIONS,
        "worker $worker->{pid} retains automatic process recycling" );
    is_deeply(
        $worker->{precompiled_templates},
        {
            map { $_ => 1 }
              qw(layouts/default.html.ep forum/thread.html.ep forum/_posts.html.ep)
        },
"worker $worker->{pid} inherited compiled templates before its first request"
    );
}
is(
    $report->{workload_coverage}{observed},
    $report->{workload_coverage}{planned},
    'every planned cell was measured'
);
is_deeply( $report->{workload_coverage}{missing},
    [], 'no silent omitted phase' );
is( $report->{correctness}{status},
    'ok', 'unique HTTP identities match persisted database deltas' );
ok(
    $report->{correctness}{created_threads} > 0,
    'threads were actually created over TCP'
);
ok(
    $report->{correctness}{created_replies} > 0,
    'replies were actually created over TCP'
);
my %routes = map { $_ => 1 } @{ $report->{coverage}{missing} };
ok( !$routes{thread_create}, 'actual thread creation route was exercised' );
ok( !$routes{reply_create},  'actual reply creation route was exercised' );
ok( !$routes{login_submit},  'sessions came from the real login endpoint' );
ok( !$routes{message_start}, 'private message write was exercised' );
ok( !$routes{thread_poll_change}, 'poll writes were exercised' );
ok( !$routes{admin_role_create},  'staff role creation was exercised' );

for my $route (
    qw(admin_plugins admin_configuration admin_plugin_probe admin_plugin_probe_math admin_configuration_change admin_plugin_change)
  )
{
    ok( !$routes{$route},
        "$route was exercised with real authorization and business checks" );
}
my ($configuration) = grep { $_->{scenario} eq 'journey.forum_configuration' }
  @{ $report->{cells} };
is( $configuration->{clients},
    1, 'global configuration changes avoid manufactured revision conflicts' );
ok( $configuration->{metrics}{response_bytes} > 0,
    'payload bytes accompany latency' );
ok( defined $configuration->{resources}{rss_bytes},
    'portable process RSS is observed' );
my %settings =
  map { $_->{name} => $_->{setting} } @{ $report->{postgres_settings} };

for my $setting (qw(fsync full_page_writes synchronous_commit)) {
    is( $settings{$setting}, 'on',
        "$setting stays enabled during write measurements" );
}
my %actors;
for my $op ( @{ $report->{operations} } ) {
    my ($actor) = split /:/msx, $op->{name};
    $actors{$actor}++;
    is( $op->{invalid_responses},
        0, "successful business responses for $op->{name}" );
    is( $op->{requests_per_second},
        undef, 'per-operation aggregate does not invent an interval' );
}
for my $actor (qw(guest member moderator admin)) {
    ok( $actors{$actor}, "$actor sent actual HTTP requests" );
}
ok( -s "$output/report.html", 'readable report accompanies raw JSON' );
if ( $ENV{GPFORUM_BENCHMARK_TRACE_DIR} ) {
    my %observed;
    my $files =
      path( $ENV{GPFORUM_BENCHMARK_TRACE_DIR} )
      ->list->grep(
        sub { $_->basename =~ /\Asamples-[[:digit:]]+[.]jsonl\z/msx } );
    for my $file ( $files->each ) {
        for my $line ( split /\n/msx, $file->slurp ) {
            my $sample = decode_json($line);
            $observed{"$sample->{kind}:$sample->{operation}"} = 1;
        }
    }
    ok( $observed{'sql:community_like_command'},
        'SQL inside the serving HTTP workers is observable' );
    ok( $observed{'http:post_like'},
        'HTTP inside the serving workers is observable' );
    is( $report->{diagnostic_trace},
        1, 'instrumented runs are explicitly labelled' );
}
like( $log, qr/authentication.*errors=0/msx, 'login/logout cell completed' );
done_testing();
1;
