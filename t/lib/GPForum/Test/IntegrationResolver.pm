# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::IntegrationResolver;
use Mojo::Base -base, -signatures;
use v5.40;
use Net::DNS;
our $VERSION = '0.001';
has addresses   => sub { return []; };
has unavailable => 0;
has queries     => sub { return []; };

sub query ( $self, $host, $kind ) {
    push @{ $self->queries }, [ $host, $kind ];
    return undef if $self->unavailable;
    my $packet = Net::DNS::Packet->new( $host, $kind );
    for my $address ( @{ $self->addresses } ) {
        $packet->push( answer => Net::DNS::RR->new("$host 1 IN A $address") );
    }
    return $packet;
}
1;
