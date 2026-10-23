# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause
package main;
use v5.40;
use Carp qw(croak);
use Const::Fast;
use English     qw(-no_match_vars);
use Time::HiRes qw(clock_gettime CLOCK_MONOTONIC);
use JSON::PP;
use Digest::SHA qw(sha256_hex);
use Mojo::File  qw(path);
use lib 'lib';
use GPForum::Service::Realtime::ConnectionRegistry;
our $VERSION = '0.001';
const my @SCALES      => ( 100, 1000, 5000 );
const my $REPETITIONS => 3;
const my $LOOKUPS     => 5000;
my @results;

for my $connections (@SCALES) {
    for my $repetition ( 1 .. $REPETITIONS ) {
        my $registry = GPForum::Service::Realtime::ConnectionRegistry->new;
        my $start    = clock_gettime(CLOCK_MONOTONIC);
        for my $index ( 0 .. $connections - 1 ) {
            $registry->register( "c-$index", { user_id => "user-$index" },
                undef )
              or croak 'registration failed';
            $registry->subscribe( "c-$index", "notifications:user-$index" );
        }
        my $registered = clock_gettime(CLOCK_MONOTONIC);
        my $delivered  = 0;
        for ( 1 .. $LOOKUPS ) {
            my @subscribers = $registry->subscribers('notifications:user-0');
            $delivered += @subscribers;
        }
        my $looked_up = clock_gettime(CLOCK_MONOTONIC);
        croak 'incorrect recipient lookup' if $delivered != $LOOKUPS;
        for my $index ( 0 .. $connections - 1 ) {
            $registry->unregister("c-$index");
        }
        my $finished = clock_gettime(CLOCK_MONOTONIC);
        croak 'connections retained' if $registry->count;
        push @results,
          {
            connections           => $connections,
            repetition            => $repetition,
            lookups               => $LOOKUPS,
            recipients_per_lookup => 1,
            register_seconds      => $registered - $start,
            lookup_seconds        => $looked_up - $registered,
            cleanup_seconds       => $finished - $looked_up,
          };
    }
}
my $encoder = JSON::PP->new->canonical->pretty;
print $encoder->encode(
    {
        scope =>
          'In-process registry only; no database or network throughput claim',
        registry_sha256 => sha256_hex(
            path('lib/GPForum/Service/Realtime/ConnectionRegistry.pm')->slurp
        ),
        perl    => "$PERL_VERSION",
        results => \@results,
    }
) or croak 'cannot write benchmark results';
1;
