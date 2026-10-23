# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Bootstrap::Discovery;

use v5.40;

use GPForum::Service::Discovery::CanonicalUrl;
use GPForum::Service::Discovery::FeedBuilder;
use GPForum::Service::Discovery::MetadataBuilder;
use GPForum::Service::Discovery::RobotsPolicy;
use GPForum::Service::Discovery::SitemapBuilder;
use GPForum::Service::Discovery::Archive;
use GPForum::Service::Discovery::WebSub;
use GPForum::Service::Discovery::SitemapPages;

our $VERSION = '0.001';

sub register {
    my ( undef, %input ) = @_;

    my $application = $input{application};
    my $config      = $input{config};
    $application->helper(
        gp_websub => sub {
            return GPForum::Service::Discovery::WebSub->new(
                hub_url => $config->websub_hub_url,
                topic   => $config->public_base_url . '/feed.atom'
            );
        }
    );

    $application->helper(
        gp_archive => sub ($controller) {
            return GPForum::Service::Discovery::Archive->new(
                schema               => $controller->gp_schema,
                category_reader      => $controller->gp_category_reader,
                thread_reader        => $controller->gp_thread_reader,
                thread_detail_reader => $controller->gp_thread_detail_reader,
                post_reader          => $controller->gp_post_reader,
                signer               => $controller->gp_post_signer,
                base_url             => $config->public_base_url,
            );
        }
    );

    $application->helper(
        gp_canonical_url => sub {
            return GPForum::Service::Discovery::CanonicalUrl->new(
                base_url => $config->public_base_url );
        }
    );
    $application->helper(
        gp_feed_builder => sub {
            my ($controller) = @_;

            return GPForum::Service::Discovery::FeedBuilder->new(
                hub_url       => $config->websub_hub_url,
                canonical_url => $controller->gp_canonical_url
            );
        }
    );
    $application->helper(
        gp_metadata_builder => sub {
            my ($controller) = @_;

            return GPForum::Service::Discovery::MetadataBuilder->new(
                canonical_url => $controller->gp_canonical_url );
        }
    );
    $application->helper(
        gp_sitemap_builder => sub {
            my ($controller) = @_;

            return GPForum::Service::Discovery::SitemapBuilder->new(
                canonical_url => $controller->gp_canonical_url );
        }
    );
    $application->helper(
        gp_sitemap_pages => sub ($controller) {
            return GPForum::Service::Discovery::SitemapPages->new(
                schema  => $controller->gp_schema,
                builder => $controller->gp_sitemap_builder
            );
        }
    );
    $application->helper(
        gp_robots_policy => sub {
            my ($controller) = @_;

            return GPForum::Service::Discovery::RobotsPolicy->new(
                sitemap_url => $controller->gp_canonical_url->base_url
                  . '/sitemap.xml', );
        }
    );

    return;
}

1;
