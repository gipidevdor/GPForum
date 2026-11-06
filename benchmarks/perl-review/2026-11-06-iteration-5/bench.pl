# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package main;
use v5.40;
use Config;
use JSON::MaybeXS;
use Time::HiRes qw(clock_gettime CLOCK_MONOTONIC);
use lib 'lib', 't/lib';
use GPForum::Infrastructure::PgNotifications;
use GPForum::Service::Operations::CacheInvalidationBus;
use GPForum::Service::Operations::LocalCache;
use GPForum::Service::Operations::NoSharedCache;
use GPForum::Service::Operations::SharedCache;
use GPForum::Service::Operations::TieredCache;
use GPForum::Test::RealtimeBusDbh;
use GPForum::Test::RealtimeBusSchema;
use GPForum::Test::SharedCacheClient;

sub queue_for ($count) {
    my $schema=GPForum::Test::RealtimeBusSchema->new(dbh=>GPForum::Test::RealtimeBusDbh->new);
    my $queue=GPForum::Infrastructure::PgNotifications->new(schema=>$schema);
    $queue->listen_to('channel_'.$_) for 1 .. $count;
    return $queue;
}
sub cache_for ($shared) {
    return GPForum::Service::Operations::TieredCache->new(
        l1=>GPForum::Service::Operations::LocalCache->new(ttl_seconds=>3600),
        l2=>$shared
          ? GPForum::Service::Operations::SharedCache->new(client=>GPForum::Test::SharedCacheClient->new,ttl_seconds=>3600)
          : GPForum::Service::Operations::NoSharedCache->new,
    );
}
my @cases;
for my $channels (1,2,8) {
    my $queue=queue_for($channels);
    push @cases,['idle_notify_'.$channels.'_channels',60_000,sub{return $queue->take('channel_1')->{available};},1];
}
my $local=cache_for(0);
$local->put('hot','value',{});
push @cases,['l1_hit_without_bus',200_000,sub{return $local->get('hot');},'value'];
my $schema=GPForum::Test::RealtimeBusSchema->new(dbh=>GPForum::Test::RealtimeBusDbh->new);
my $queue=GPForum::Infrastructure::PgNotifications->new(schema=>$schema);
$queue->listen_to('domain');
my $bussed=cache_for(0);
$bussed->bus(GPForum::Service::Operations::CacheInvalidationBus->new(schema=>$schema,notifications=>$queue));
$bussed->get('missing');
$bussed->put('hot','value',{});
push @cases,['l1_hit_with_bus_two_channels',60_000,sub{return $bussed->get('hot');},'value'];
my $producer=sub{return 'value';};
for my $shared (0,1) {
    my $cache=cache_for($shared);
    my $options={tags=>['public']};
    push @cases,[($shared?'shared':'local').'_invalidate_and_fill',($shared?6_000:30_000),sub{
        $cache->invalidate('page');
        return $cache->get_or_set('page',$producer,$options);
    },'value'];
}
my $purging=cache_for(0);
push @cases,['local_empty_tag_purge',120_000,sub{return $purging->invalidate_tag('public');},0];
my @results;
for my $case (@cases) {
    my ($name,$iterations,$code,$expected)=@{$case};my $sink;
    $sink=$code->() for 1 .. 100;
    for my $repetition (1 .. 3) {
        my $start=clock_gettime(CLOCK_MONOTONIC);
        $sink=$code->() for 1 .. $iterations;
        my $seconds=clock_gettime(CLOCK_MONOTONIC)-$start;
        die "Changed result for $name\n" if !defined $sink || "$sink" ne "$expected";
        push @results,{name=>$name,repetition=>$repetition,iterations=>$iterations,seconds=>$seconds,operations_per_second=>$iterations/$seconds};
    }
}
print JSON::MaybeXS->new(canonical=>1,utf8=>1,pretty=>1)->encode({
    perl=>"$^V",architecture=>$Config{archname},platform=>$^O,
    method=>'Three fixed-iteration batches after 100 warmups, monotonic wall time. Notification handles and shared cache clients are identical in-memory test doubles: these are Perl CPU costs, without SQL, network or storage latency. Empty idle polls still read pg_notifies on each call. Invalidate-and-fill cases include both the purge and a valid fresh fill. All timed results have the same semantics before/after; failed-read and stale-fill correctness is covered separately by red/green tests and real PostgreSQL integration. Eight channels are a scaling case; one or two are the common configuration. HTTP measures the real migrated database separately.',
    results=>\@results,
});
