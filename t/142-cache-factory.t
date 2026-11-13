# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use lib 'lib';
use lib 't/lib';

use GPForum::Config;
use GPForum::Service::Operations::CacheFactory;
use GPForum::Service::Operations::LocalCache;
use GPForum::Service::Operations::TieredCache;
use Test::More;

our $VERSION = '0.001';

my $tiered = GPForum::Service::Operations::CacheFactory->build(
    GPForum::Config->new( glifistore_url => 'tcp://127.0.0.1:7379' ) );
isa_ok(
    $tiered,
    'GPForum::Service::Operations::TieredCache',
    'a configured GlifiStore is wired behind a tiered cache'
);

my $local =
  GPForum::Service::Operations::CacheFactory->build( GPForum::Config->new );
isa_ok( $local->l2, 'GPForum::Service::Operations::NoSharedCache',
    'without GlifiStore, the default, each process keeps its own L1, over an'
      . ' empty shared layer' );

# GlifiStore is optional in production too (D2): no URL is L1 only, still a
# tiered stack, so the invalidation bus has somewhere to attach.
isa_ok(
    GPForum::Service::Operations::CacheFactory->build(
        GPForum::Config->new(
            environment    => 'production',
            glifistore_url => q{},
        )
    ),
    'GPForum::Service::Operations::TieredCache',
    'production without GlifiStore keeps each process to its own cache',
);

my $production = GPForum::Service::Operations::CacheFactory->build(
    GPForum::Config->new(
        environment    => 'production',
        glifistore_url => 'tcp://127.0.0.1:1',
        session_secret => 'rotated-production-secret',
    )
);
isa_ok(
    $production,
    'GPForum::Service::Operations::TieredCache',
    'production still wires L2 when GlifiStore is unreachable'
);

done_testing();

1;
