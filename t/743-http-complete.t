# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package main;
use v5.40;
use Const::Fast;
use FindBin;
use File::Temp qw(tempdir);
use Mojo::File qw(path);
use Mojo::Message::Response;
use Mojo::IOLoop;
use Mojo::Promise;
use Mojo::UserAgent;
use Test::More;
use lib "$FindBin::Bin/../script/lib", "$FindBin::Bin/../lib";
use GPForum::Performance::HTTPClient;
use GPForum::Performance::HTTPCatalog qw(reads journeys);
use GPForum::Performance::HTTPComplete;
use GPForum::Performance::Server;
use GPForum::Performance::HTTPReport       qw(write_report);
use GPForum::Performance::HTTPIntegrations qw(link_fixtures);
use GPForum::Service::Integration::Registry;
use GPForum::Performance::Support qw(monotonic);
our $VERSION = '0.001';
const my $ELAPSED => 12;
const my $SAMPLES => 20;
const my $P95     => 19;
const my $CLIENTS => 10;

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
my $old_agent = $client->ua;
my $cookies   = $old_agent->cookie_jar;
$client->csrf('cell-csrf');
$client->context->{thread_id} = 'cell-thread';
$client->reset_connections;
isnt( $client->ua, $old_agent, 'a cell gets an independent connection pool' );
is( $client->ua->cookie_jar,
    $cookies, 'the same authenticated cookie jar survives the cell boundary' );
is( $client->csrf, 'cell-csrf', 'CSRF state survives the connection boundary' );
is( $client->context->{thread_id},
    'cell-thread', 'journey context survives the connection boundary' );
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
$error = undef;
try {
    $client->_received(
        {
            name  => 'checked_response',
            check => sub { return 'durable state did not change'; }
        },
        $body,
        $ELAPSED
    );
}
catch ($caught) { $error = "$caught"; };
like(
    $error,
    qr/durable[ ]state/msx,
    'failed business postconditions fail the workload'
);
is( $samples[-1]{valid},
    0, 'failed postconditions remain invalid measurements' );
my @rows = map {
    {
        elapsed_ms  => $_,
        app_ms      => $_ - 1,
        db_ms       => 0,
        status_code => 200,
        valid       => 1,
        worker      => $_ <= $SAMPLES / 2 ? 'worker-a' : 'worker-b'
    }
} 1 .. $SAMPLES;
## no critic (Subroutines::ProtectPrivateSubs) -- verify aggregation math independently from the costly socket workload
my $metrics = GPForum::Performance::HTTPComplete::_summary( \@rows, 2 );
is(
    $metrics->{requests_per_second},
    $SAMPLES / 2,
    'cell throughput uses wall time, not sum of request durations'
);
is( $metrics->{latency}{p95_ms}, $P95, 'latency percentiles keep the tail' );
is_deeply(
    $metrics->{worker_requests},
    { 'worker-a' => $SAMPLES / 2, 'worker-b' => $SAMPLES / 2 },
    'worker request shares remain available to diagnose uneven serving'
);
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
    qw(messages polls privacy_export settings_notifications publishing_community staff_administration drafts_preview plugin_probes integrations_preview forum_configuration)
  )
{
    ok( $names{$family}, "real HTTP journey covers $family" );
}
my $registry = GPForum::Service::Integration::Registry->new(
    enabled => [ ( map { $_->[0] } @{ link_fixtures() } ), 'mathematics' ],
    mastodon_hosts => ['social.example.org'],
    peertube_hosts => ['video.example.org']
);
for my $fixture ( @{ link_fixtures() } ) {
    is(
        $registry->resolve( $fixture->[1] )->{provider},
        $fixture->[0],
        "benchmark exercises a supported $fixture->[0] URL without fetching it"
    );
}
my $planned = GPForum::Performance::HTTPComplete->new(
    options => {
        scenario      => [ 'journey.forum_configuration', 'mixed' ],
        repetitions   => 2,
        write_clients => $CLIENTS,
        concurrency   => [ 1, $CLIENTS ]
    }
);
my $plan = $planned->planned_cells;
is( scalar @{$plan},
    2 + 2, 'the full selected workload is planned before running' );
is( $plan->[0]{clients},
    1, 'global revision writes are deliberately serialized' );
is( $plan->[-1]{clients}, $CLIENTS,
    'independent mixed work keeps concurrency' );
$planned->report->{planned_cells} = $plan;
$planned->report->{cells}         = [ $plan->[0] ];
is( scalar @{ $planned->workload_coverage->{missing} },
    2 + 1,
    'an omitted mixed phase cannot disappear from completeness accounting' );
$planned->report->{cells} = [ @{$plan}, $plan->[0] ];
is( scalar @{ $planned->workload_coverage->{duplicates} },
    1, 'duplicate cells cannot count as independent repetitions' );
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

subtest 'mixed setup renews clients left idle by preceding journeys' => sub {
    my $member     = GPForum::Performance::HTTPClient->new( actor => 'member' );
    my $idle_agent = $member->ua;
    my $authenticated_cookies = $idle_agent->cookie_jar;
    my $prepared              = 0;
    no warnings 'redefine';    ## no critic (TestingAndDebugging::ProhibitNoWarnings) -- inspect the TCP pool at the real mixed preparation boundary
    local *GPForum::Performance::HTTPClient::steps_p = sub ( $actor, $steps ) {
        ++$prepared;
        isnt( $actor->ua, $idle_agent,
            'publishing starts without reusing an expired idle socket' );
        is( $actor->ua->cookie_jar,
            $authenticated_cookies,
            'the authenticated session survives setup' );
        return Mojo::Promise->resolve;
    };
    my $benchmark = GPForum::Performance::HTTPComplete->new(
        options => {
            scenario      => [],
            expires       => monotonic() + 1,
            write_clients => 1,
            repetitions   => 0,
        },
        pools => { member => [$member] },
    );
    $benchmark->can('_mixed')->($benchmark);
    is( $prepared, 1, 'publishing preparation still executes once' );
};

subtest 'startup probes reach workers concurrently before measurement' => sub {
    my @probe_requests;
    my $first_completion_count;
    my $expected_probes = 2 * 2;
    no warnings 'redefine';    ## no critic (TestingAndDebugging::ProhibitNoWarnings) -- observe public HTTP calls without opening a network connection
    local *Mojo::UserAgent::get_p = sub ( $probe_agent, $url, $headers ) {
        push @probe_requests, { url => $url, headers => $headers };
        is( $probe_agent->max_connections,
            $expected_probes,
            'the startup pool accommodates the concurrent burst' );
        my $pending_probe = Mojo::Promise->new;
        Mojo::IOLoop->next_tick(
            sub {
                $first_completion_count //= scalar @probe_requests;
                $pending_probe->resolve(1);
            }
        );
        return $pending_probe;
    };
    my $probe_server = bless { workers => 2, base => 'http://127.0.0.1:1' },
      'GPForum::Performance::Server';
    GPForum::Performance::Server->can('_probe_workers')
      ->( $probe_server, monotonic() + 1 );
    is( scalar @probe_requests, $expected_probes, 'two requests per worker' );
    is( $first_completion_count, $expected_probes,
        'all requests start before the first response completes' );
    is_deeply(
        [ map { $_->{url} } @probe_requests ],
        [ ( $probe_server->{base} . '/health/live' ) x $expected_probes ],
        'only the existing health endpoint is probed'
    );
    is_deeply(
        [ map { $_->{headers}{Connection} } @probe_requests ],
        [ ('close') x $expected_probes ],
        'probe sockets are not kept idle'
    );
    GPForum::Performance::Server->can('_probe_workers')
      ->( $probe_server, monotonic() );
    is( scalar @probe_requests,
        $expected_probes, 'an expired deadline launches no more requests' );
};

done_testing();
1;
