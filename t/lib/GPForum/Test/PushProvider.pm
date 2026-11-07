# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package GPForum::Test::PushProvider;
use Mojo::Base -base, -signatures;
use v5.40;
use Const::Fast;
our $VERSION = '0.001';
const my $ACCEPTED => 201;
use Mojo::Message::Response;
use Mojo::Promise;
has on_prepare =>
  undef;    # optional: tests model revocation during asynchronous DNS
has sent => sub { return []; };
has code => $ACCEPTED;

sub prepare_p ( $self, $url ) {
    if ( $self->on_prepare ) { $self->on_prepare->(); }
    return Mojo::Promise->resolve($url);
}

sub send_prepared_p ( $self, $url, $headers, $body, $deadline ) {
    return $self->send_p( $url, $headers, $body );
}

sub send_p ( $self, $url, $headers, $body ) {
    push @{ $self->sent }, { url => $url, headers => $headers, body => $body };
    return Mojo::Promise->resolve(
        Mojo::Message::Response->new( code => $self->code ) );
}
1;
