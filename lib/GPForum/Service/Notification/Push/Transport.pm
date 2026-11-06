# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Notification::Push::Transport;

use Mojo::Base -base, -signatures;
use v5.40;
use Const::Fast;
use Carp qw(croak);
use Mojo::Message::Response;
use Time::HiRes qw(time);
use POSIX       qw(floor);
use Mojo::UserAgent;
use GPForum::Service::Integration::DirectProxy;
use GPForum::Service::Integration::PinnedPeer;
use GPForum::Service::Notification::Push::Endpoint;
use GPForum::Service::Notification::Push::Resolver;

our $VERSION = '0.001';
const my $CONNECT_SECONDS => 3;
const my $REQUEST_SECONDS => 8;
const my $MAX_RESPONSE    => 4096;
const my $MAX_CLIENTS     => 16;
const my $HTTP_TIMEOUT    => 408;
has endpoint =>
  sub { return GPForum::Service::Notification::Push::Endpoint->new; };
has resolver =>
  sub { return GPForum::Service::Notification::Push::Resolver->new; };
has clients        => sub { return {}; };
has client_factory => sub {
    return sub { return Mojo::UserAgent->new; };
};
has per_provider => 2;

sub prepare_p ( $self, $raw ) {
    my $url  = $self->endpoint->parse($raw);
    my $host = $url->host;
    return $self->resolver->resolve_p($host)->then(
        sub ($peer) {
            if (
                !GPForum::Service::Notification::Push::Endpoint->public_address(
                    $peer->{address}
                )
              )
            {
                croak 'unpermitted Push peer';
            }
            my $entry = $self->clients->{$host};
            if (  !$entry
                || $entry->{expires} <= time
                || $entry->{address} ne $peer->{address} )
            {
                if ( keys %{ $self->clients } >= $MAX_CLIENTS ) {
                    my ($oldest) = sort {
                        $self->clients->{$a}{expires}
                          <=> $self->clients->{$b}{expires}
                    } keys %{ $self->clients };
                    delete $self->clients->{$oldest};
                }
                my $ua = $self->client_factory->();
                $ua->insecure(0);
                $ua->cert(undef)->key(undef);
                $ua->cookie_jar->ignore( sub { return 1; } );
                $ua->proxy( GPForum::Service::Integration::DirectProxy->new );
                $ua->max_redirects(0)->max_connections( $self->per_provider );
                $ua->connect_timeout($CONNECT_SECONDS)
                  ->request_timeout($REQUEST_SECONDS);
                $ua->inactivity_timeout($REQUEST_SECONDS)
                  ->max_response_size($MAX_RESPONSE);
                $ua->transactor(
                    GPForum::Service::Integration::PinnedPeer->new(
                        address => $peer->{address}
                    )
                );
                $ua->transactor->compressed(0);
                $ua->tls_options(
                    {
                        SSL_version  => 'SSLv23:!SSLv2:!SSLv3:!TLSv1:!TLSv1_1',
                        SSL_hostname => $host,
                        SSL_verifycn_name   => $host,
                        SSL_verifycn_scheme => 'http',
                        SSL_verify_mode     => 1
                    }
                );
                $entry = { %{$peer}, client => $ua };
                $self->clients->{$host} = $entry;
            }
            return { url => $url, client => $entry->{client} };
        }
    );
}

sub send_prepared_p ( $self, $prepared, $headers, $body, $deadline ) {
    my $ttl = floor( $deadline - time );
    return Mojo::Promise->resolve(
        Mojo::Message::Response->new( code => $HTTP_TIMEOUT ) )
      if $ttl <= 0;
    my $tx = $prepared->{client}->build_tx(
        POST => $prepared->{url} => {
            %{$headers},
            TTL                => $ttl,
            'Accept-Encoding'  => 'identity',
            'Content-Type'     => 'application/octet-stream',
            'Content-Encoding' => 'aes128gcm',
        } => $body
    );
    return $prepared->{client}->start_p($tx)
      ->then( sub ($done) { return $done->res; } );
}

sub send_p ( $self, $raw, $headers, $body ) {
    return $self->prepare_p($raw)->then(
        sub ($prepared) {
            return $self->send_prepared_p( $prepared, $headers, $body,
                time + ( $headers->{TTL} // 0 ) );
        }
    );
}

1;

__END__

=head1 NAME

GPForum::Service::Notification::Push::Transport - Send bounded HTTPS requests to pinned Push peers with connection reuse.

=head1 DESCRIPTION

Send bounded HTTPS requests to pinned Push peers with connection reuse. See docs/ops/web-push.md for deployment and lifecycle guarantees.

=head1 SUBROUTINES/METHODS

=head2 prepare_p

Resolve and validate a provider and return a pinned client/URL pair for immediate use after the batch authorization refresh.

=head2 send_prepared_p

Send through that validated peer without another DNS lookup. Recompute remaining TTL at the instant of sending and refuse an expired deadline.

=head2 send_p

Validate the endpoint and DNS answer, preserve TLS hostname verification and send one encrypted POST. No redirect or environment proxy is followed.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $service = GPForum::Service::Notification::Push::Transport->new();

=head1 DIAGNOSTICS

Invalid input fails closed. Transport failures are bounded and reported without receiver capability URLs or key material.

=head1 CONFIGURATION AND ENVIRONMENT

Dependencies and validated settings are supplied by the composition layer. See docs/ops/web-push.md.

=head1 DEPENDENCIES

CryptX supplies cryptographic primitives; Mojolicious supplies asynchronous HTTPS; versioned PostgreSQL API functions own persistence.

=head1 INCOMPATIBILITIES

Private key files require a persistent service account and restrictive filesystem permissions.

=head1 BUGS AND LIMITATIONS

A provider acceptance does not guarantee display. An already accepted notification cannot be recalled.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. BSD-3-Clause.

=cut
