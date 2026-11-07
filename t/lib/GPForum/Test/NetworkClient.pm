# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::NetworkClient;

use Mojo::Base -base, -signatures;
use v5.40;
use Carp qw(croak);
use Mojo::Promise;
use GPForum::Service::Integration::HttpClient;
our $VERSION = '0.001';
has responses => sub { return []; };
has calls     => sub { return []; };

sub https_url ( $self, $raw ) {
    return GPForum::Service::Integration::HttpClient->new->https_url($raw);
}

sub request ( $self, $method, $url, $input = {} ) {
    push @{ $self->calls }, { method => $method, url => $url, input => $input };
    my $response = shift @{ $self->responses };
    croak 'simulated response loss' if !defined $response;
    return ref $response eq 'CODE'
      ? $response->( $method, $url, $input )
      : $response;
}

sub request_p ( $self, @args ) {
    return Mojo::Promise->resolve->then(
        sub { return $self->request(@args); } );
}

1;
