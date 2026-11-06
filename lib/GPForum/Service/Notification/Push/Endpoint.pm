# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Notification::Push::Endpoint;

use Mojo::Base -base, -signatures;
use v5.40;
use GPForum::Service::Integration::HttpClient;
use GPForum::X::Argument;

our $VERSION = '0.001';
has providers => sub {
    return [
        qw(fcm.googleapis.com updates.push.services.mozilla.com *.push.apple.com *.notify.windows.com)
    ];
};
has parser => sub { return GPForum::Service::Integration::HttpClient->new; };

sub parse ( $self, $raw ) {
    my $url;
    try { $url = $self->parser->https_url($raw); }
    catch ($error) {
        GPForum::X::Argument->throw( message => 'invalid push endpoint' );
    };
    my $host    = lc $url->host;
    my $allowed = 0;
    for my $provider ( @{ $self->providers } ) {
        my $suffix = $provider =~ s/\A[*][.]//rmsx;
        if (
            $host eq $provider
            || (   $provider ne $suffix
                && length($host) > length($suffix) + 1
                && substr( $host, -length($suffix) - 1 ) eq ".$suffix" )
          )
        {
            $allowed = 1;
        }
    }
    if ( !$allowed ) {
        GPForum::X::Argument->throw( message => 'unsupported push provider' );
    }
    if ( !length( $url->path->to_string ) || $url->path->to_string eq q{/} ) {
        GPForum::X::Argument->throw( message => 'invalid push endpoint' );
    }

    # Normalize the authority before fingerprinting: hostname case and an
    # explicit default port must not create a second account binding.
    # Preserve the opaque provider path and query bytes.
    $url->host($host)->port(undef);
    return $url;
}

sub public_address ( $, $address ) {

    # Connections are deliberately IPv4-only. An AAAA record or an IPv6
    # literal is never passed to the connector, including mapped addresses.
    return GPForum::Service::Integration::HttpClient->public_ipv4($address);
}

1;

__END__

=head1 NAME

GPForum::Service::Notification::Push::Endpoint - Validate approved HTTPS Push capability URLs.

=head1 DESCRIPTION

Validate approved HTTPS Push capability URLs. See docs/ops/web-push.md for deployment and lifecycle guarantees.

=head1 SUBROUTINES/METHODS

=head2 parse

Require HTTPS on port 443, no credentials or fragment, and an explicitly approved hostname. Wildcards match only complete subdomains.

=head2 public_address

Accept only public IPv4 destinations. The sender never connects through AAAA records or IPv6 literals.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $service = GPForum::Service::Notification::Push::Endpoint->new();

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
