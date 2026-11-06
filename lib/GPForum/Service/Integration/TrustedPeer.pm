# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package GPForum::Service::Integration::TrustedPeer;
use Mojo::Base 'Mojo::UserAgent::Transactor', -signatures;
use v5.40;
use Socket qw(inet_pton AF_INET AF_INET6);
use GPForum::X::Argument;
our $VERSION = '0.001';
has 'address';

sub peer ( $self, $tx ) {
    my ( $scheme, $host, $port ) = $self->SUPER::peer($tx);
    my $address = $self->address;
    if (
        !defined $address
        || (   !inet_pton( AF_INET, $address )
            && !inet_pton( AF_INET6, $address ) )
      )
    {
        GPForum::X::Argument->throw(
            message => 'numeric trusted HTTPS peer required' );
    }
    return ( $scheme, $self->address, $port );
}
1;
__END__
=head1 NAME

GPForum::Service::Integration::TrustedPeer - Numeric peer for an operator-configured HTTPS hub.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    $ua->transactor(GPForum::Service::Integration::TrustedPeer->new(address => $numeric));

=head1 DESCRIPTION

Preserves the configured hub's hostname, scheme and port while connecting to an
address already resolved outside the reactor. This adapter belongs only to the
trusted WebSub configuration; untrusted integration URLs use PinnedPeer's policy.

=head1 SUBROUTINES/METHODS

=head2 peer

Returns the configured transaction's scheme and port with the resolved numeric address.

=head1 DIAGNOSTICS

Connection errors follow the user agent's promise contract.

=head1 CONFIGURATION AND ENVIRONMENT

WebSub validates its configured HTTPS endpoint before installing this adapter.

=head1 DEPENDENCIES

Mojolicious.

=head1 INCOMPATIBILITIES

This adapter does not validate URLs supplied by remote users.

=head1 BUGS AND LIMITATIONS

A hub's resolved address is pinned for one forwarding operation.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. BSD-3-Clause.

=cut
