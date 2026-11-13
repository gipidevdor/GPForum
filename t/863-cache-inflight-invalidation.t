# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Infrastructure::PgNotifications;
use GPForum::Service::Operations::CacheInvalidationBus;
use GPForum::Service::Operations::LocalCache;
use GPForum::Service::Operations::SharedCache;
use GPForum::Service::Operations::TieredCache;
use GPForum::Test::NotifyingFunctions;
use GPForum::Test::RealtimeBusDbh;
use GPForum::Test::RealtimeBusSchema;
use GPForum::Test::SharedCacheClient;

our $VERSION = '0.001';

sub _cache ($shared) {
    my $backing =
      $shared
      ? GPForum::Service::Operations::SharedCache->new(
        client => GPForum::Test::SharedCacheClient->new )
      : GPForum::Service::Operations::LocalCache->new;
    return GPForum::Service::Operations::TieredCache->new(
        l1 => GPForum::Service::Operations::LocalCache->new,
        l2 => $backing,
    );
}

sub _invalidate ( $cache, $kind ) {
    return $cache->invalidate('page')            if $kind eq 'key';
    return $cache->invalidate_tag('public')      if $kind eq 'tag';
    return $cache->invalidate_tags( ['public'] ) if $kind eq 'tags';
    return $cache->clear;
}

for my $shared ( 0, 1 ) {
    for my $kind (qw(key tag tags clear)) {
        subtest "a $kind purge retires a fill with shared=$shared" => sub {
            my $cache = _cache($shared);
            is(
                $cache->get_or_set(
                    'page',
                    sub {
                        _invalidate( $cache, $kind );
                        return 'old page';
                    },
                    { tags => ['public'] }
                ),
                'old page',
                'the current caller still receives its computed result'
            );
            is( $cache->l1->get('page'), undef,
                'L1 cannot retain that result' );
            is( $cache->l2->get('page'), undef,
                'L2 cannot retain that result' );
            is( $cache->snapshot->{stats}{writes}, 0, 'no fill was admitted' );
            is(
                $cache->get_or_set(
                    'page',
                    sub { return 'fresh page' },
                    { tags => ['public'] }
                ),
                'fresh page',
                'a subsequent fill uses the current generation'
            );
            is( $cache->get('page'), 'fresh page', 'that fill remains cached' );
        };
    }
}

for my $kind (qw(key tag clear)) {
    subtest
      "a remote $kind purge consumed by a nested read retires the fill" => sub {
        my $cache   = _cache(1);
        my $backend = GPForum::Test::RealtimeBusDbh->new;
        my $peer    = GPForum::Test::RealtimeBusDbh->new( pg_pid => 1 )
          ->join_network($backend);
        my $schema = GPForum::Test::RealtimeBusSchema->new( dbh => $backend );
        $cache->bus(
            GPForum::Service::Operations::CacheInvalidationBus->new(
                functions =>
                  GPForum::Test::NotifyingFunctions->new( dbh => $backend ),
                schema => $schema,
            )
        );
        my $publisher = GPForum::Service::Operations::CacheInvalidationBus->new(
            functions => GPForum::Test::NotifyingFunctions->new( dbh => $peer ),
            schema    => GPForum::Test::RealtimeBusSchema->new( dbh => $peer ),
        );
        my $request =
            $kind eq 'key' ? { keys => ['page'] }
          : $kind eq 'tag' ? { tags => ['public'] }
          :                  { clear => 1 };

        $cache->get_or_set(
            'page',
            sub {
                _invalidate( $cache->l2, $kind );
                ok( $publisher->publish($request),
                    'another backend publishes' );
                is( $cache->get('nested'),
                    undef, 'a nested read consumes the pending purge' );
                return 'old page';
            },
            { tags => ['public'] }
        );
        is_deeply( $cache->bus->drain, [], 'the purge will not arrive again' );
        is( $cache->get('page'), undef,
            'the completed stale fill cannot resurrect after the purge' );
        is( $cache->l2->get('page'), undef, 'neither layer admits it' );
      };
}

for my $shared ( 0, 1 ) {
    subtest "an explicit page ticket covers a purge with shared=$shared" =>
      sub {
        my $cache  = _cache($shared);
        my $ticket = $cache->ticket( ['public'], { mint => 1 } );
        $cache->invalidate('page');
        is(
            $cache->put(
                'page', 'old page', { tags => ['public'], ticket => $ticket }
            ),
            'old page',
            'put preserves its return contract'
        );
        is( $cache->get('page'), undef,
            'a retired ticket admits neither layer' );

        my $raw_ticket =
            $shared
          ? $cache->l2->ticket( ['public'], { mint => 1 } )
          : $cache->ticket( ['public'] );
        $cache->put( 'page', 'fresh page',
            { tags => ['public'], ticket => $raw_ticket } );
        is( $cache->get('page'), 'fresh page',
            'raw shared tickets remain supported' );
      };
}

subtest 'an empty tag purge does not discard a valid fill' => sub {
    my $cache = _cache(0);
    $cache->get_or_set(
        'page',
        sub {
            $cache->invalidate_tags( [] );
            return 'fresh page';
        }
    );
    is( $cache->get('page'), 'fresh page', 'a no-op does not retire a fill' );
};

done_testing();

1;
