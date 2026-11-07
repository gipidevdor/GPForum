# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Integration::PinnedPeer;

use Mojo::Base 'Mojo::UserAgent::Transactor', -signatures;
use v5.40;
use Const::Fast;
use GPForum::X::Argument;
our $VERSION = '0.001';
const my $HTTPS_PORT => 443;
has 'address';

sub peer ( $self, $tx ) {
    my ( $protocol, undef, $port ) = $self->SUPER::peer($tx);
    if (   !defined $self->address
        || $protocol ne 'https'
        || $port != $HTTPS_PORT )
    {
        GPForum::X::Argument->throw(
            message => 'validated HTTPS peer required' );
    }
    return ( $protocol, $self->address, $port );
}

1;

__END__

=head1 NAME

GPForum::Service::Integration::PinnedPeer - Pin an outbound HTTPS connection to a checked address.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $service = GPForum::Service::Integration::PinnedPeer->new;

=head1 DESCRIPTION

Pin an outbound HTTPS connection to a checked address. Core owns configuration, authorization and presentation.

=head1 SUBROUTINES/METHODS

=head2 peer

Returns the checked peer address without changing Host or TLS identity.

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
