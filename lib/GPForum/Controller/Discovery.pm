# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Controller::Discovery;

use Const::Fast;
use GPForum::Web::DiscoveryAccess;
use GPForum::Web::DiscoveryPayload;
use GPForum::Web::ClientAddress;
use Mojo::Base 'Mojolicious::Controller', -signatures;
use v5.40;

our $VERSION = '0.001';
const my $WEBSUB_MAX_REQUEST_BYTES => 4096;
const my $HTTP_NOT_FOUND           => 404;
const my $HTTP_TOO_LARGE           => 413;
const my $HTTP_UNSUPPORTED_TYPE    => 415;
const my $HTTP_RATE_LIMITED        => 429;
const my $HTTP_BAD_REQUEST         => 400;
const my $HTTP_ACCEPTED            => 202;
const my $HTTP_BAD_GATEWAY         => 502;

sub robots ($self) {
    return GPForum::Web::DiscoveryAccess->new->render_document(
        $self,
        GPForum::Web::DiscoveryPayload->robots(
            policy => $self->gp_robots_policy,
        )
    );
}

sub sitemap ($self) {
    my $access = GPForum::Web::DiscoveryAccess->new;
    my $limit  = $access->sitemap_limit;

    return $access->render_document(
        $self,
        GPForum::Web::DiscoveryPayload->sitemap(
            builder    => $self->gp_sitemap_builder,
            categories =>
              $self->gp_category_reader->list_categories( { limit => $limit } ),
            presenter => $self->gp_discovery_view_model,
            threads   => $self->gp_thread_reader->list_public_threads(
                { limit => $limit }
            ),
        )
    );
}

sub feed ($self) {
    my $access = GPForum::Web::DiscoveryAccess->new;
    my $hub    = $self->gp_websub;
    if ( $hub->enabled ) {
        $self->res->headers->link( '<'
              . $hub->hub_url
              . '>; rel="hub", <'
              . $hub->topic
              . '>; rel="self"' );
    }

    return $access->render_document(
        $self,
        GPForum::Web::DiscoveryPayload->feed(
            builder       => $self->gp_feed_builder,
            canonical_url => $self->gp_canonical_url,
            clock         => $self->gp_clock,
            page          => $self->gp_thread_reader->list_public_threads(
                { limit => $access->feed_limit( $self->param('limit') ) }
            ),
            presenter => $self->gp_discovery_view_model,
        )
    );
}

sub subscribe ($self) {
    my $publisher = $self->gp_websub;
    return $self->render(
        text   => 'WebSub is disabled',
        status => $HTTP_NOT_FOUND
    ) if !$publisher->enabled;
    return $self->render(
        text   => 'Request too large',
        status => $HTTP_TOO_LARGE
    ) if length( $self->req->body ) > $WEBSUB_MAX_REQUEST_BYTES;
    return $self->render(
        text   => 'Form required',
        status => $HTTP_UNSUPPORTED_TYPE
      )
      if ( $self->req->headers->content_type // q{} ) !~
      /\A application\/x-www-form-urlencoded(?:;|\z)/imsx;
    my $rate = $self->gp_rate_limiter->check(
        {
            scope          => 'websub',
            action         => 'subscribe',
            actor_id       => GPForum::Web::ClientAddress->of( $self->tx ),
            limit          => 10,
            window_seconds => 60
        }
    );
    return $self->render( text => 'Rate limited', status => $HTTP_RATE_LIMITED )
      if !$rate->{ok};
    my $form;
    try {
        $form = $publisher->subscription(
            {
                map { $_ => $self->param($_) }
                  qw(hub.mode hub.topic hub.callback hub.secret hub.lease_seconds)
            }
        );
    }
    catch ($error) {
        return $self->render(
            text   => 'Invalid subscription',
            status => $HTTP_BAD_REQUEST
        );
    };
    $self->render_later;
    my $pending =
      $publisher->ua->post_p( $publisher->hub_url => form => $form )->then(
        sub ($tx) {
            return $self->render(
                text   => q{},
                status => $tx->result->code == $HTTP_ACCEPTED
                ? $HTTP_ACCEPTED
                : $HTTP_BAD_GATEWAY
            );
        }
      );
    $pending->catch(
        sub ($error) {
            return $self->render(
                text   => 'Hub unavailable',
                status => $HTTP_BAD_GATEWAY
            );
        }
    );
    return;
}

1;
