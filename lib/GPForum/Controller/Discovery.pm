# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Controller::Discovery;

use Const::Fast;
use GPForum::Web::DiscoveryAccess;
use GPForum::Web::DiscoveryPayload;
use GPForum::Web::ClientAddress;
use GPForum::Web::SiteIcon;
use GPForum::Web::ManifestPayload;
use Mojo::Base 'GPForum::Controller::Base', -async_await;
use v5.40;

use Mojo::Util qw(encode);

our $VERSION = '0.001';
const my $WEBSUB_MAX_REQUEST_BYTES => 4096;
const my $HTTP_NOT_FOUND           => 404;
const my $HTTP_TOO_LARGE           => 413;
const my $HTTP_UNSUPPORTED_TYPE    => 415;
const my $HTTP_RATE_LIMITED        => 429;
const my $HTTP_BAD_REQUEST         => 400;
const my $HTTP_ACCEPTED            => 202;
const my $HTTP_BAD_GATEWAY         => 502;

const my $MAXIMUM_SITEMAP_PAGE => 50_000;

sub robots ($self) {
    return GPForum::Web::DiscoveryAccess->new->render_document(
        $self,
        GPForum::Web::DiscoveryPayload->robots(
            policy => $self->gp_robots_policy,
        )
    );
}

# The forum's icon, from its name; a browser keeps it for a day.
sub icon ($self) {
    $self->res->headers->cache_control('public, max-age=86400');
    return $self->render(
        data => encode(
            'UTF-8', GPForum::Web::SiteIcon->svg( $self->gp_config->site_name )
        ),
        format => 'svg'
    );
}

# Home Screen installation needs a linked standalone manifest on the SSR
# origin too. Its contents contain no account data or receiver capabilities.
sub manifest ($self) {
    $self->res->headers->cache_control('private, max-age=3600');
    $self->res->headers->content_type('application/manifest+json');
    return $self->render(
        json => GPForum::Web::ManifestPayload->build(
            $self->gp_config, $self->ui_theme_registry
        )
    );
}

# The sitemaps are text, sent as the UTF-8 their XML declares, as every
# discovery document is (GPForum::Web::DiscoveryAccess).
async sub sitemap ($self) {
    $self->res->headers->cache_control('public, max-age=0, must-revalidate');
    return $self->render(
        data => encode(
            'UTF-8',
            ( await $self->call_p( $self->gp_sitemap_pages, 'sitemap_index' ) )
        ),
        format => 'xml'
    );
}

async sub sitemap_page ($self) {
    my $page = $self->param('page');
    return ( await $self->await_p( $self->reply ) )->not_found
      if $page !~ /\A[1-9][[:digit:]]{0,4}\z/amsx
      || $page > $MAXIMUM_SITEMAP_PAGE;
    my $document =
      ( await $self->call_p( $self->gp_sitemap_pages, 'page', $page ) );
    return ( await $self->await_p( $self->reply ) )->not_found
      if !defined $document;

    $self->res->headers->cache_control('public, max-age=0, must-revalidate');

    return $self->render(
        data   => encode( 'UTF-8', $document ),
        format => 'xml'
    );
}

async sub feed ($self) {
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
            page          => (
                await $self->call_p(
                    $self->gp_thread_reader,
                    'list_public_threads',
                    { limit => $access->feed_limit( $self->param('limit') ) }
                )
            ),
            presenter => $self->gp_discovery_view_model,
        )
    );
}

async sub subscribe ($self) {
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
    my $rate = (
        await $self->call_p(
            $self->gp_rate_limiter,
            'check',
            {
                scope          => 'websub',
                action         => 'subscribe',
                actor_id       => GPForum::Web::ClientAddress->of( $self->tx ),
                limit          => 10,
                window_seconds => 60
            }
        )
    );
    return $self->render( text => 'Rate limited', status => $HTTP_RATE_LIMITED )
      if !$rate->{ok};
    my $form;
    try {
        $form = (
            await $self->call_p(
                $publisher,
                'subscription',
                {
                    map { $_ => $self->param($_) }
                      qw(hub.mode hub.topic hub.callback hub.secret hub.lease_seconds)
                }
            )
        );
    }
    catch ($error) {
        return $self->render(
            text   => 'Invalid subscription',
            status => $HTTP_BAD_REQUEST
        );
    };
    $self->render_later;

    # The publisher owns the agent the forward runs on, and the helper makes
    # one for each request: held by nothing once this action returned, the
    # agent went and took the pending connection with it, and every
    # subscription answered 502. The chain holds it until the hub answers.
    return $self->respond_p(
        $publisher->forward_p($form),
        sub ($tx) {
            return $self->render(
                text   => q{},
                status => $tx->result->code == $HTTP_ACCEPTED
                ? $HTTP_ACCEPTED
                : $HTTP_BAD_GATEWAY
            );
        },
        sub ($error) {
            return $self->render(
                text   => 'Hub unavailable',
                status => $HTTP_BAD_GATEWAY
            );
        }
    );
}

1;
