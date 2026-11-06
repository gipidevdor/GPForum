# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Integration::HttpClient;

use Mojo::Base -base, -signatures;
use v5.40;
use Const::Fast;
use Mojo::UserAgent;
use Mojo::URL;
use Net::DNS;
use List::Util qw(any);
use GPForum::Service::Integration::PinnedPeer;
use GPForum::Service::Integration::DirectProxy;
use GPForum::X::Config;
use GPForum::X::Unavailable;
our $VERSION = '0.001';
const my $HTTPS_PORT => 443;
const my $URL_LENGTH => 2048;
const my $HOST_CHAR  => qr{[[:lower:][:digit:]]}amsx;
const my $HOST_LABEL =>
  qr{$HOST_CHAR(?:[[:lower:][:digit:]-]{0,61}$HOST_CHAR)?}amsx;
const my $MAX_RESPONSE    => 1_048_576;
const my $REQUEST_SECONDS => 10;
const my $CONNECT_SECONDS => 3;
const my $DNS_SECONDS     => 2;
const my $MAX_ADDRESSES   => 16;
const my $IPV4_BITS       => 32;
const my $IPV4_OCTETS     => 4;
const my $MAX_OCTET       => 255;
const my @RESERVED_NETWORKS => map { _cidr($_) } qw(
  0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16
  172.16.0.0/12 192.0.0.0/24 192.0.2.0/24 192.88.99.0/24 192.168.0.0/16
  198.18.0.0/15 198.51.100.0/24 203.0.113.0/24 224.0.0.0/4 240.0.0.0/4
);

has resolver => sub {
    return Net::DNS::Resolver->new(
        udp_timeout => $DNS_SECONDS,
        tcp_timeout => $DNS_SECONDS,
        retry       => 1,
        retrans     => $DNS_SECONDS
    );
};

sub https_url ( $self, $raw ) {
    if (  !defined $raw
        || length($raw) > $URL_LENGTH
        || $raw =~ /[\x00-\x20\x7f<>"'\\]/msx )
    {
        GPForum::X::Config->throw(
            message => 'integration needs an approved HTTPS hostname' );
    }
    my $url  = Mojo::URL->new($raw);
    my $host = lc( $url->host // q{} );
    if (   ( $url->scheme // q{} ) ne 'https'
        || defined $url->userinfo
        || defined $url->fragment
        || ( defined $url->port && $url->port != $HTTPS_PORT )
        || $host !~ /\A (?:${HOST_LABEL}[.])+[[:lower:]]{2,63} \z/amsx
        || $host =~ /[.](?:localhost|local|internal|test|invalid)\z/msx )
    {
        GPForum::X::Config->throw(
            message => 'integration needs an approved HTTPS hostname' );
    }
    return $url;
}

sub public_ipv4 ( $class, $address ) {
    my @parts = split /[.]/msx, $address;
    return 0
      if @parts != $IPV4_OCTETS
      || any { !/\A [[:digit:]]{1,3} \z/amsx || $_ > $MAX_OCTET } @parts;
    my $packed  = pack 'C4', @parts;
    my $value   = unpack 'N', $packed;
    my $blocked = any { ( $value & $_->[1] ) == $_->[0] } @RESERVED_NETWORKS;
    return $blocked ? 0 : 1;
}

sub _cidr ($text) {
    my ( $network, $prefix ) = split m{/}msx, $text;
    my $packed = pack 'C4', split /[.]/msx, $network;
    my $mask   = ( 2**$IPV4_BITS - 1 ) ^ ( 2**( $IPV4_BITS - $prefix ) - 1 );
    return [ ( unpack 'N', $packed ), $mask ];
}

sub request ( $self, $method, $raw, $input = {} ) {
    my $url   = $self->https_url($raw);
    my $reply = $self->resolver->query( $url->host . q{.}, 'A' );
    if ( !$reply ) {
        GPForum::X::Unavailable->throw(
            message => 'integration DNS unavailable' );
    }

    my @addresses = map { $_->address } grep { $_->type eq 'A' } $reply->answer;
    if (  !@addresses
        || @addresses > $MAX_ADDRESSES
        || any { !__PACKAGE__->public_ipv4($_) } @addresses )
    {
        GPForum::X::Config->throw(
            message => 'integration endpoint has no permitted public address' );
    }

    my $ua = Mojo::UserAgent->new;
    $ua->proxy( GPForum::Service::Integration::DirectProxy->new );
    $ua->max_redirects(0)->max_connections(0);
    $ua->max_response_size($MAX_RESPONSE);
    $ua->connect_timeout($CONNECT_SECONDS)->request_timeout($REQUEST_SECONDS);
    $ua->transactor(
        GPForum::Service::Integration::PinnedPeer->new(
            address => $addresses[0]
        )
    );
    $ua->transactor->compressed(0);
    $ua->tls_options(
        {
            SSL_hostname        => $url->host,
            SSL_verifycn_name   => $url->host,
            SSL_verifycn_scheme => 'http'
        }
    );
    my %headers =
      ( %{ $input->{headers} // {} }, 'Accept-Encoding' => 'identity' );
    my @arguments = ( $method, $url, \%headers );
    if ( exists $input->{json} ) { push @arguments, json => $input->{json}; }
    if ( exists $input->{form} ) { push @arguments, form => $input->{form}; }

    my $tx;
    try { $tx = $ua->start( $ua->build_tx(@arguments) ); }
    catch ($error) {
        GPForum::X::Unavailable->throw(
            message => 'integration transport unavailable' );
    };

    if ( !$tx->res->code ) {
        GPForum::X::Unavailable->throw(
            message => 'integration transport unavailable' );
    }
    my $encoding = lc( $tx->res->headers->content_encoding // q{} );
    if ( length($encoding) && $encoding ne 'identity' ) {
        GPForum::X::Unavailable->throw(
            message => 'integration returned unsupported compressed content' );
    }
    return $tx->res;
}

1;

__END__

=head1 NAME

GPForum::Service::Integration::HttpClient - Fetch only pinned public HTTPS endpoints with bounded responses.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $service = GPForum::Service::Integration::HttpClient->new;

=head1 DESCRIPTION

Fetch only pinned public HTTPS endpoints with bounded responses. Core owns configuration, authorization and presentation.

=head1 SUBROUTINES/METHODS

=head2 https_url

Validates an absolute credential-free standard-port HTTPS URL.

=head2 public_ipv4

Rejects private, reserved and documentation IPv4 ranges.

=head2 request

Resolves and pins a public peer, verifies the original TLS hostname and performs one bounded request without redirects.

=head1 DIAGNOSTICS

Invalid configuration and transport failures raise typed exceptions.

=head1 CONFIGURATION AND ENVIRONMENT

The composition layer supplies validated settings and dependencies.

=head1 DEPENDENCIES

The Good Phorum runtime and the modules named above.

=head1 INCOMPATIBILITIES

Network capabilities are independent of the frozen local Plugin API v1.

=head1 BUGS AND LIMITATIONS

External operations depend on the configured provider and its availability.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. BSD-3-Clause.

=cut
