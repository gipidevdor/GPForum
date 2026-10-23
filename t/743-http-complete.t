# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause
package main;
use v5.40;
use Const::Fast;
use FindBin;
use File::Temp qw(tempdir);
use Mojo::File qw(path);
use Mojo::Message::Response;
use Test::More;
use lib "$FindBin::Bin/../script/lib", "$FindBin::Bin/../lib";
use GPForum::Performance::HTTPClient;
use GPForum::Performance::HTTPCatalog qw(reads journeys);
use GPForum::Performance::HTTPComplete;
use GPForum::Performance::HTTPReport qw(write_report);
use GPForum::Performance::Support    qw(monotonic);
our $VERSION = '0.001';
const my $ELAPSED => 12;
const my $SAMPLES => 20;
const my $P95     => 19;

my $timing = GPForum::Performance::HTTPClient::timing(
    'app;dur=10.500, db;dur=2.125;desc="PostgreSQL"');
is_deeply(
    $timing,
    { app => 10.5, db => 2.125 },
    'both real Server-Timing values are retained'
);
is_deeply( GPForum::Performance::HTTPClient::timing(undef),
    {}, 'missing timing is unavailable, never zero' );
is_deeply(
    GPForum::Performance::HTTPClient::timing('app;dur=1.2.3, db;dur=NaN'),
    {}, 'malformed timings cannot become misleading numeric samples' );
my @samples;
my $client = GPForum::Performance::HTTPClient->new(
    actor   => 'member',
    collect => sub ($row) { push @samples, $row; }
);
my $redirect = Mojo::Message::Response->new( code => 302 );
$redirect->headers->location('/login');
my $error;
try { $client->_received( { name => 'private_page' }, $redirect, $ELAPSED ); }
catch ($caught) { $error = "$caught"; };
like(
    $error,
    qr/HTTP[ ]302/msx,
    'a login redirect cannot pass as a fast authenticated page'
);
is( $samples[-1]{valid}, 0, 'failed request remains visible in measurements' );
$error = undef;
try {
    $client->_transport_failed( { name => 'timeout' }, monotonic(), 'timeout' );
}
catch ($caught) { $error = "$caught"; };
like( $error, qr/transport[ ]failure/msx,
    'transport errors fail the workload' );
is( $samples[-1]{status_code},
    0, 'a timed-out attempt is counted without inventing an HTTP response' );
my $body = Mojo::Message::Response->new( code => 200 );
$body->headers->content_type('application/json');
$body->body('{"status":"replayed","post_id":"existing"}');
$error = undef;
try {
    $client->_received(
        { name => 'reply', status => 'created', key => 'post_id' },
        $body, $ELAPSED );
}
catch ($caught) { $error = "$caught"; };
like(
    $error,
    qr/unexpected[ ]domain[ ]status/msx,
    'a replayed write is rejected even with HTTP 200'
);
$body = Mojo::Message::Response->new( code => 200 );
$body->body('{"status":"created"}');
$error = undef;
try {
    $client->_received(
        { name => 'reply', status => 'created', key => 'post_id' },
        $body, $ELAPSED );
}
catch ($caught) { $error = "$caught"; };
like(
    $error,
    qr/missing[ ]response[ ]identity/msx,
    'a success label without the created ID fails'
);
$body = Mojo::Message::Response->new( code => 200 );
$body->body('{"status":"created","post_id":"fresh"}');
$body->headers->header( 'Server-Timing'         => 'app;dur=10, db;dur=2' );
$body->headers->header( 'X-GPForum-Bench-Route' => 'reply_create' );
$client->_received( { name => 'reply', status => 'created', key => 'post_id' },
    $body, $ELAPSED );
is( $samples[-1]{valid},
    1, 'fresh write with the correct business response passes' );
is( $samples[-1]{route},
    'reply_create', 'coverage comes from actual dispatched route' );
is( $samples[-1]{identity},
    'fresh', 'persisted identity can be checked after the run' );
is( $samples[-1]{db_ms},
    2, 'database duration is carried with client duration' );
my @rows = map {
    {
        elapsed_ms  => $_,
        app_ms      => $_ - 1,
        db_ms       => 0,
        status_code => 200,
        valid       => 1
    }
} 1 .. $SAMPLES;
## no critic (Subroutines::ProtectPrivateSubs) -- verify aggregation math independently from the costly socket workload
my $metrics = GPForum::Performance::HTTPComplete::_summary( \@rows, 2 );
is(
    $metrics->{requests_per_second},
    $SAMPLES / 2,
    'cell throughput uses wall time, not sum of request durations'
);
is( $metrics->{latency}{p95_ms}, $P95,  'latency percentiles keep the tail' );
is( $metrics->{outside_app}{p50_ms}, 1, 'outside-app overhead is explicit' );
is( $metrics->{low_sample_count},
    0, 'adequate counts are distinguished from smoke samples' );
is(
    GPForum::Performance::HTTPComplete::_summary( \@rows, undef )
      ->{requests_per_second},
    undef,
    'operation aggregates cannot invent a throughput interval'
);
## use critic
my %names;

for my $scenario ( @{ reads() }, @{ journeys() } ) {
    ok( !$names{ $scenario->{name} }++, "unique scenario $scenario->{name}" );
}
for my $family (
    qw(messages polls privacy_export settings_notifications publishing_community staff_administration drafts_preview)
  )
{
    ok( $names{$family}, "real HTTP journey covers $family" );
}
my $directory = tempdir( CLEANUP => 1 );
write_report(
    $directory,
    {
        status   => 'fail',
        coverage => { observed => 0, total => 1, missing => ['<route>'] },
        duration_seconds => 1,
        generator        => 'test',
        policy           => 'test',
        operations       => [],
        cells            => [],
        failures         => ['<script>alert(1)</script>']
    }
);
my $html = path("$directory/report.html")->slurp;
like( $html, qr/&lt;script&gt;/msx, 'report escapes failure text' );
unlike( $html, qr/<script>/msx,
    'failure text cannot inject executable report markup' );
done_testing();
1;
