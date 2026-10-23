# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause
package main;
use v5.40;
use Const::Fast;
use FindBin;
use File::Temp qw(tempdir);
use Test::More;
use lib "$FindBin::Bin/../../script/lib", "$FindBin::Bin/../../lib";
use GPForum::Performance::Support qw(run_bounded read_json);
our $VERSION = '0.001';
const my $TIMEOUT => 180;
my $directory = tempdir( CLEANUP => 1 );
my $output    = "$directory/http";
my $log       = run_bounded(
    [
        "$FindBin::Bin/../../script/gpforum-carton",          'exec',
        "$FindBin::Bin/../../script/benchmark-http-complete", '--output',
        $output,                                              '--profile',
        'smoke',
    ],
    { timeout => $TIMEOUT }
);
my $report = read_json("$output/http-complete.json");
is( $report->{status}, 'ok', 'all real HTTP smoke scenarios passed' );
is_deeply( $report->{failures}, [], 'no swallowed HTTP or business failure' );
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
like( $log, qr/authentication.*errors=0/msx, 'login/logout cell completed' );
done_testing();
1;
