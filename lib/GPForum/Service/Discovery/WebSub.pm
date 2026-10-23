# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Discovery::WebSub;

use Mojo::Base 'GPForum::Base', -signatures;
use v5.40;
use Const::Fast;
use Carp   qw(croak);
use Encode qw(encode);
use Mojo::UserAgent;
use Mojo::URL;

our $VERSION = '0.001';
const my %SUBSCRIPTION_MODES => ( subscribe => 1, unsubscribe => 1 );
const my %CALLBACK_SCHEMES   => ( http      => 1, https       => 1 );

const my $CONNECT_TIMEOUT    => 5;
const my $MAX_RESPONSE_BYTES => 65_536;
const my $REQUEST_TIMEOUT    => 10;
const my $SECRET_MAX_BYTES   => 200;
__PACKAGE__->requires(qw(hub_url topic));
has ua => sub {
    return Mojo::UserAgent->new->max_redirects(0)
      ->connect_timeout($CONNECT_TIMEOUT)
      ->request_timeout($REQUEST_TIMEOUT)
      ->max_response_size($MAX_RESPONSE_BYTES);
};

sub enabled ($self) { return length( $self->hub_url ) ? 1 : 0; }

sub publish ($self) {
    return { skipped => 1 } if !$self->enabled;
    $self->_hub;
    my $response = $self->ua->post(
        $self->hub_url => form => {
            'hub.mode' => 'publish',
            'hub.url'  => $self->topic
        }
    )->result;
    croak 'WebSub hub rejected publication' if !$response->is_success;
    return { published => 1 };
}

sub subscription ( $self, $params ) {
    croak 'WebSub is disabled' if !$self->enabled;
    $self->_hub;
    croak 'unknown WebSub topic'
      if ( $params->{'hub.topic'} // q{} ) ne $self->topic;
    croak 'invalid WebSub mode'
      if !exists $SUBSCRIPTION_MODES{ $params->{'hub.mode'} // q{} };
    my $callback = Mojo::URL->new( $params->{'hub.callback'} // q{} );
    croak 'invalid WebSub callback'
      if !exists $CALLBACK_SCHEMES{ $callback->scheme // q{} }
      || !length( $callback->host // q{} )
      || defined $callback->userinfo
      || defined $callback->fragment;
    croak 'WebSub secret exceeds the protocol limit'
      if length( encode( 'UTF-8', $params->{'hub.secret'} // q{} ) ) >=
      $SECRET_MAX_BYTES;
    croak 'invalid WebSub lease'
      if defined $params->{'hub.lease_seconds'}
      && $params->{'hub.lease_seconds'} !~ /\A [1-9][[:digit:]]{0,8} \z/msx;
    return {
        map  { $_ => $params->{$_} }
        grep { defined $params->{$_} }
          qw(hub.mode hub.topic hub.callback hub.secret hub.lease_seconds)
    };
}

sub _hub ($self) {
    my $url = Mojo::URL->new( $self->hub_url );
    croak 'WebSub hub needs an absolute HTTPS URL'
      if ( $url->scheme // q{} ) ne 'https'
      || !length( $url->host // q{} )
      || defined $url->userinfo
      || defined $url->fragment;
    return;
}

1;

__END__

=head1 NAME

GPForum::Service::Discovery::WebSub - Publish to a trusted WebSub hub.

=head1 DESCRIPTION

The operator supplies an HTTPS hub. GPForum advertises it and publishes
changes from its durable outbox. The hub owns verification of callback
intent, finite leases, retries and optional HMAC delivery signatures as
specified by WebSub. Only the fixed public Atom topic can be subscribed.
The optional local subscription route validates and forwards requests;
GPForum never connects to subscriber-supplied callback URLs.

=head1 SUBROUTINES/METHODS

=head2 enabled

True when the operator configured a hub.

=head2 publish

Notifies the trusted HTTPS hub of the fixed public Atom topic; throws on failed delivery so the outbox retries.

=head2 subscription

Validates a subscription form and returns only protocol parameters for forwarding to the hub.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $result = $publisher->publish;

=head1 DIAGNOSTICS

Throws for invalid subscription parameters, an unsafe hub URL or failed publication.

=head1 CONFIGURATION AND ENVIRONMENT

The operator supplies hub_url and the canonical public feed topic.

=head1 DEPENDENCIES

Mojo::UserAgent and Mojo::URL.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Requires a WebSub hub that verifies callbacks and owns subscriber delivery.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause license.

=cut
