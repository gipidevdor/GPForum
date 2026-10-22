# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Mojo::Transaction::HTTP;
use Test::More;

use lib 'lib';

use GPForum::Web::ClientAddress;

our $VERSION = '0.001';

# Over the service's Unix socket Mojolicious gives a transaction no peer
# address, and Mojo::Transaction::remote_address answered undef ahead of
# X-Forwarded-For: every client of the site shared the controllers' constant
# fallback, one rate-limit bucket and no address in the audit rows. The
# socket's only client is the local proxy, so the client is the last entry
# the proxy appended; a request carrying none gets its connection's own key.

_unix_socket_client_is_the_entry_the_proxy_appended();
_forged_entries_do_not_move_the_client();
_a_request_without_an_address_gets_its_connection();
_tcp_keeps_the_trusted_proxy_walk();

done_testing();

sub _unix_socket_client_is_the_entry_the_proxy_appended {
    my $tx = _unix_tx( 'c1', '203.0.113.7' );
    is( GPForum::Web::ClientAddress->of($tx),
        '203.0.113.7', 'the client is the address the proxy appended' );
    is( $tx->remote_address, '203.0.113.7',
        'and remote_address says so to every later reader' );

    is( GPForum::Web::ClientAddress->of( _unix_tx( 'c2', '2001:db8::5' ) ),
        '2001:db8::5', 'an IPv6 client is taken as well' );

    return;
}

sub _forged_entries_do_not_move_the_client {
    my $forged = _unix_tx( 'c3', '198.51.100.9, 127.0.0.1, 203.0.113.7' );
    is( GPForum::Web::ClientAddress->of($forged),
        '203.0.113.7', 'entries a client sent ahead of the proxy are ignored' );

    # A client on the proxy's own host: Mojolicious would walk past the
    # trusted loopback to the entry the client forged.
    my $local = _unix_tx( 'c4', '198.51.100.9, 127.0.0.1' );
    is( GPForum::Web::ClientAddress->of($local),
        '127.0.0.1', 'a loopback client is not walked past to a forged entry' );

    return;
}

sub _a_request_without_an_address_gets_its_connection {
    my $first = GPForum::Web::ClientAddress->of( _unix_tx('c5') );
    my $other = GPForum::Web::ClientAddress->of( _unix_tx('c6') );
    is( $first, 'connection:c5',
        'a request without X-Forwarded-For is keyed by its connection' );
    isnt( $first, $other, 'two such connections never share a key' );

    is(
        GPForum::Web::ClientAddress->of( _unix_tx( 'c7', 'unix:' ) ),
        'connection:c7',
        'nor does an entry that is not an address'
    );

    my $bare = Mojo::Transaction::HTTP->new;
    my $one  = GPForum::Web::ClientAddress->of($bare);
    like(
        $one,
        qr/\A connection: /msx,
        'a transaction with no connection still gets a key of its own'
    );
    is( GPForum::Web::ClientAddress->of($bare),
        $one, 'and keeps it for the rest of the request' );
    isnt( GPForum::Web::ClientAddress->of( Mojo::Transaction::HTTP->new ),
        $one, 'which no other transaction shares' );

    return;
}

sub _tcp_keeps_the_trusted_proxy_walk {
    my $tx = Mojo::Transaction::HTTP->new;
    $tx->original_remote_address('127.0.0.1');
    $tx->req->reverse_proxy(1);
    $tx->req->trusted_proxies( ['127.0.0.1'] );
    $tx->req->headers->header(
        'X-Forwarded-For' => '198.51.100.9, 203.0.113.7' );
    is( GPForum::Web::ClientAddress->of($tx),
        '203.0.113.7', 'over TCP the trusted proxy list decides, as before' );

    my $direct = Mojo::Transaction::HTTP->new;
    $direct->original_remote_address('192.0.2.1');
    $direct->req->headers->header( 'X-Forwarded-For' => '203.0.113.7' );
    is( GPForum::Web::ClientAddress->of($direct),
        '192.0.2.1', 'and without a proxy the peer is the client' );

    return;
}

sub _unix_tx ( $connection, $forwarded = undef ) {
    my $tx = Mojo::Transaction::HTTP->new( connection => $connection );

    # What Hypnotoad sets with proxy on: believed from the loopback only.
    $tx->req->reverse_proxy(1);
    $tx->req->trusted_proxies( [ '127.0.0.1', '::1' ] );
    if ( defined $forwarded ) {
        $tx->req->headers->header( 'X-Forwarded-For' => $forwarded );
    }

    return $tx;
}

1;
