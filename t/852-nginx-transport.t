# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;
use Carp qw(croak);
use Const::Fast;
use English                qw(-no_match_vars);
use File::Temp             qw(tempdir);
use IO::Uncompress::Gunzip qw(gunzip);
use Mojo::File             qw(path);
use Mojo::IOLoop;
use Mojo::UserAgent;
use Test::More;
use lib 'lib';
use GPForum::Benchmark::Process
  qw(find_binary free_port spawn terminate wait_until_ready);

our $VERSION = '0.001';
const my $HTTP_OK           => 200;
const my $REPETITIONS       => 3;
const my $ASSET_REPETITIONS => 200;
const my $REQUEST_TIMEOUT   => 5;

my $nginx = $ENV{GPFORUM_TEST_NGINX} // find_binary('nginx');
if ( !$nginx ) {
    plan skip_all => 'nginx is required for the deployed proxy transport test';
}
my $directory =
  tempdir( 'gpforum-nginx-test-XXXXXX', TMPDIR => 1, CLEANUP => 1 );
my @running;

END {
    for my $runtime ( reverse @running ) { terminate($runtime); }
}

my $backend_port  = free_port();
my $port          = free_port();
my $socket        = "$directory/b.sock";
my $socket_listen = 'http+unix://' . ( $socket =~ s{/}{%2F}grmsx );
path("$directory/backend.pl")->spew(<<'APP');
use v5.40;
use Mojolicious::Lite;
websocket '/realtime' => sub ($c) {
    $c->on(message => sub ($c, $message) { $c->send($message) });
};
my $respond = sub ($c) {
    $c->render(json => {connection => $c->tx->connection,
        connection_header => $c->req->headers->connection // ''});
};
get '/' => $respond;
get '/*rest' => $respond;
app->start;
APP
my $backend =
  _start( 'backend', $EXECUTABLE_NAME, "$directory/backend.pl",
    'daemon', '-l', "http://127.0.0.1:$backend_port",
    '-l',     $socket_listen );
$backend->{base_url} = "http://127.0.0.1:$backend_port";
_ready( $backend, 'test backend' );

my $site = path('deploy/nginx/gpforum.conf')->slurp;

# Exercise the shipped HTTP locations and maps. Only the TLS listeners,
# certificate and deployment paths change for this isolated loopback test.
$site =~ s/server[ ][{]\n[ ]{4}listen[ ]80;.*?\n[}]\n\n//msx;
$site =~ s/listen[ ]443[ ]ssl;/listen 127.0.0.1:$port;/msx;
$site =~ s/^\s*listen[ ]\Q[::]:443\E[ ]ssl;\n//msx;
$site =~ s/^\s*http2[ ]on;\n//msx;
$site =~ s/^\s*ssl_certificate(?:_key)?[ ][^;]+;\n//gmsx;
$site =~ s{unix:/opt/gpforum/var/run/gpforum.sock}{unix:$socket}gmsx;
$site =~ s{/opt/gpforum}{$directory}gmsx;
path("$directory/assets/css")->make_path;
my $css = '.probe { color: #123456; }' x $ASSET_REPETITIONS;
path("$directory/assets/css/probe.css")->spew($css);
path("$directory/nginx.conf")
  ->spew( "daemon off;\npid $directory/nginx.pid;\n"
      . "error_log $directory/nginx.log;\nevents { worker_connections 64; }\n"
      . "http { access_log off; types { text/css css; }\n$site\n}\n" );
my $proxy =
  _start( 'nginx', $nginx, '-p', "$directory/", '-c', "$directory/nginx.conf" );
$proxy->{base_url} = "http://127.0.0.1:$port";
_ready( $proxy, 'shipped nginx site' );

for my $route (qw(/ /not-an-asset.css /attachments/example/download /metrics)) {
    my %connections;
    for ( 1 .. $REPETITIONS ) {
        my $tx = $proxy->{ua}->get("$proxy->{base_url}$route");
        is( $tx->result->code, $HTTP_OK, "$route reaches the application" );
        is( $tx->result->json->{connection_header},
            q{}, 'normal HTTP has no hop-by-hop Connection header' );
        $connections{ $tx->result->json->{connection} }++;
    }
    is( scalar keys %connections, 1, "$route reuses one upstream connection" );
}
for my $route ( '/probe.css?v=test', '/assets/css/probe.css?v=test' ) {
    my $tx = $proxy->{ua}->build_tx( GET => "$proxy->{base_url}$route" );
    $tx->req->headers->accept_encoding('gzip');
    $tx->res->content->auto_decompress(0);
    $proxy->{ua}->start($tx);
    is( $tx->result->code, $HTTP_OK, "$route is served from disk" );
    is( $tx->result->headers->content_encoding,
        'gzip', 'nginx compresses static text' );
    like( $tx->result->headers->vary,
        qr/Accept-Encoding/msx, 'encoding varies in downstream caches' );
    like( $tx->result->headers->cache_control,
        qr/immutable/msx, 'versioned asset keeps immutable caching' );
    my $decoded = q{};
    ok( gunzip( \( $tx->result->body ) => \$decoded ),
        'static response is valid gzip' );
    is( $decoded, $css, 'decompressed bytes match the file' );
    cmp_ok( length( $tx->result->body ),
        '<', length($css), 'compression reduces bytes on the wire' );
}
my $ws      = Mojo::UserAgent->new;
my $timeout = Mojo::IOLoop->timer(
    $REQUEST_TIMEOUT => sub {
        fail('WebSocket handshake and echo complete within the test deadline');
        Mojo::IOLoop->stop;
    }
);
$ws->websocket(
    "$proxy->{base_url}/realtime" => sub ( $ua, $tx ) {
        ok( $tx->is_websocket,
            'WebSocket upgrade still works through the shipped site' );
        if ( !$tx->is_websocket ) { Mojo::IOLoop->stop; return; }
        $tx->on(
            message => sub ( $tx, $message ) {
                is( $message, 'probe', 'upgraded connection carries messages' );
                $tx->finish;
                Mojo::IOLoop->stop;
            }
        );
        $tx->send('probe');
    }
);
Mojo::IOLoop->start;
Mojo::IOLoop->remove($timeout);

done_testing();

sub _start ( $name, @command ) {
    my $runtime = {
        log_file => "$directory/$name.log",
        ua       => Mojo::UserAgent->new( request_timeout => $REQUEST_TIMEOUT ),
    };
    $runtime->{process_pid} =
      spawn( { name => $name, log_file => $runtime->{log_file}, session => 1 },
        @command );
    push @running, $runtime;
    return $runtime;
}

sub _ready ( $runtime, $name ) {
    try { wait_until_ready( $runtime, $name ); }
    catch ($error) {
        diag( path( $runtime->{log_file} )->slurp );
        croak $error;
    };
    return;
}

1;
