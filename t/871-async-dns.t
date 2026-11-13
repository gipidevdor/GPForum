# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;
use v5.40;
use Const::Fast;
use Carp qw(croak);
use IO::Socket::INET;
use Mojo::IOLoop;
use Mojo::Promise;
use Net::DNS;
use Scalar::Util qw(refaddr);
use Test::More;
use lib 'lib', 't/lib';
use GPForum::Infrastructure::PublicResolver;
use GPForum::Service::Integration::HttpClient;
use GPForum::Test::PushResolver;

our $VERSION = '0.001';
const my $PACKET_BYTES  => 4096;
const my $DELAY_SECONDS => 0.04;
const my $TICK_SECONDS  => 0.005;
const my $TTL_SECONDS   => 30;

my $server = IO::Socket::INET->new(
    LocalAddr => '127.0.0.1',
    LocalPort => 0,
    Proto     => 'udp'
) or croak 'cannot create local DNS fixture';
my $reactor   = Mojo::IOLoop->singleton->reactor;
my @addresses = ('8.8.8.8');
my ( $queries, $truncated, $ticks ) = ( 0, 0, 0 );
$reactor->io(
    $server => sub {
        my $peer       = recv $server, my $data, $PACKET_BYTES, 0;
        my $request    = Net::DNS::Packet->new( \$data );
        my ($question) = $request->question;
        my $name       = $question->qname;
        my $reply      = Net::DNS::Packet->new( $name, 'A' );
        $reply->header->id( $request->header->id );
        $reply->header->qr(1);
        $reply->header->tc($truncated);

        for my $address (@addresses) {
            $reply->push(
                answer => Net::DNS::RR->new("$name $TTL_SECONDS IN A $address")
            );
        }
        $queries++;
        Mojo::IOLoop->timer( $DELAY_SECONDS =>
              sub { send $server, $reply->data, 0, $peer; return; } );
    }
)->watch( $server, 1, 0 );
my $dns = Net::DNS::Resolver->new(
    nameservers => ['127.0.0.1'],
    port        => $server->sockport,
    igntc       => 1,
    usevc       => 0
);
my $resolver = GPForum::Infrastructure::PublicResolver->new(
    resolver        => $dns,
    allowed_address => sub ($address) {
        return GPForum::Service::Integration::HttpClient->public_ipv4($address);
    }
);
my $timer = Mojo::IOLoop->recurring( $TICK_SECONDS => sub { $ticks++; } );
my $a     = $resolver->resolve_p('public.example');
my $b     = $resolver->resolve_p('public.example');
is( refaddr($a), refaddr($b),
    'concurrent resolutions share one pending DNS query' );
my $resolved;
$a->then( sub ($peer) { $resolved = $peer; return; } )->wait;
is( $resolved->{address}, '8.8.8.8',
    'native reactor reads a delayed UDP DNS response' );
is( $queries, 1, 'only one DNS packet was sent' );
cmp_ok( $ticks, '>', 1, 'timers continue while DNS waits' );
$resolver->resolve_p('public.example')->wait;
is( $queries, 1, 'unexpired positive answers are cached' );
@addresses = ( '8.8.8.8', '127.0.0.1' );
my $rejected;
$resolver->resolve_p('mixed.example')
  ->catch( sub ($error) { $rejected = $error; return; } )
  ->wait;
like( "$rejected", qr/permitted/msx,
    'one private address rejects the entire answer' );
@addresses = ('8.8.8.8');
$truncated = 1;
$rejected  = undef;
$resolver->resolve_p('truncated.example')
  ->catch( sub ($error) { $rejected = $error; return; } )
  ->wait;
ok( $rejected, 'truncated DNS is refused without synchronous TCP fallback' );
is_deeply( $resolver->pending, {},
    'success and failure remove pending DNS state' );
Mojo::IOLoop->remove($timer);
$reactor->remove($server);
close $server or croak 'cannot close DNS fixture';

my $opened = 0;
my $client = GPForum::Service::Integration::HttpClient->new(
    async_resolver =>
      GPForum::Test::PushResolver->new( peer => { address => '127.0.0.1' } ),
    client_factory => sub { $opened++; croak 'must not connect'; }
);
my $error;
$client->request_p( 'GET', 'https://approved.example/path' )
  ->catch( sub ($caught) { $error = $caught; return; } )
  ->wait;
isa_ok( $error, 'GPForum::X::Config',
    'transport revalidates an injected DNS peer' );
is( $opened, 0, 'a private peer never opens an HTTP connection' );
done_testing();

1;
