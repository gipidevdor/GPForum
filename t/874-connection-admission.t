# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;
use v5.40;
use lib 'lib';
use Carp qw(croak);
use Const::Fast;
use IO::Socket::INET;
use Mojo::IOLoop;
use Mojo::Server::Daemon;
use Mojo::Server::Prefork;
use Mojo::Util qw(steady_time);
use Mojolicious;
use Test::More;
use GPForum::Infrastructure::ConnectionAdmission;

our $VERSION = '0.001';
const my $CLASS            => 'GPForum::Infrastructure::ConnectionAdmission';
const my $CLIENTS          => 32;
const my $BATCH            => 4;
const my $LIMIT            => 8;
const my $DEADLINE         => 2;
const my $TICK             => 0.005;
const my $ORDINARY_CLIENTS => 250;
const my $LARGE_CLIENTS    => 1000;
const my $STRESS_CLIENTS   => 5000;
const my $HUGE_CLIENTS     => 100_000;
const my $MAX_BATCH        => 512;
const my $MEDIUM_BATCH     => 16;
const my $MEDIUM_CLIENTS   => 4096;
const my $MEDIUM_MAX_BATCH => 64;

is( $CLASS->batch_size($ORDINARY_CLIENTS),
    1, 'ordinary limits keep one accept per turn' );
is( $CLASS->batch_size($LARGE_CLIENTS),
    $MEDIUM_BATCH, 'larger budgets admit small batches' );
is( $CLASS->batch_size($MEDIUM_CLIENTS),
    $MEDIUM_MAX_BATCH,
    'ordinary high-connection budgets retain their bounded batch' );
is( $CLASS->batch_size($STRESS_CLIENTS),
    $MAX_BATCH, 'large bursts remain bounded' );
is( $CLASS->batch_size($HUGE_CLIENTS),
    $MAX_BATCH, 'the batch never grows without a limit' );
is( $CLASS->single_accept( 'https://localhost:443', $STRESS_CLIENTS ),
    1, 'TLS preserves native handshake admission' );

sub advance_until ($condition) {
    my $loop  = Mojo::IOLoop->singleton;
    my $timer = $loop->recurring( $TICK => sub { return; } );
    my $until = steady_time + $DEADLINE;
    while ( !$condition->() && steady_time < $until ) { $loop->one_tick; }
    $loop->remove($timer);
    return $condition->();
}

sub fixture ( $limit, $batch = $BATCH, $prefork = 0 ) {
    my $class  = $prefork ? 'Mojo::Server::Prefork' : 'Mojo::Server::Daemon';
    my $server = $class->new(
        app         => Mojolicious->new,
        listen      => ['http://127.0.0.1:0?single_accept=0'],
        max_clients => $limit,
        backlog     => $CLIENTS,
        silent      => 1,
    );
    if ($prefork) { $server->cleanup(0)->workers(2); }
    $server->start;
    $CLASS->install( $server, $batch, [0] );
    my $accepted = 0;
    Mojo::IOLoop->acceptor( $server->acceptors->[0] )
      ->on( accept => sub { $accepted++; return; } );
    my @clients = map {
        IO::Socket::INET->new(
            PeerAddr => '127.0.0.1',
            PeerPort => $server->ports->[0],
            Proto    => 'tcp',
            Timeout  => $DEADLINE,
        ) or croak 'cannot connect admission fixture';
    } 1 .. $CLIENTS;
    return ( $server, \@clients, \$accepted );
}

subtest 'native admission yields between bounded batches' => sub {
    my ( $server, $clients, $accepted ) = fixture($CLIENTS);
    ok( advance_until( sub { return ${$accepted} > 0; } ),
        'the listener accepts' );
    is( ${$accepted}, $BATCH, 'one event-loop turn accepts only its batch' );
    ok( advance_until( sub { return ${$accepted} == $CLIENTS; } ),
        'all queued clients are eventually admitted' );
    ok(
        advance_until(
            sub {
                return
                  defined Mojo::IOLoop->acceptor( $server->acceptors->[0] );
            }
        ),
        'the listener is registered again after yielding'
    );
    ok( !Mojo::IOLoop->acceptor( $server->acceptors->[0] )->is_accepting,
        'the native connection cap stops the listener' );
    for my $client ( $clients->@* ) {
        close $client or croak 'cannot close fixture client';
    }
    undef $server;
    Mojo::IOLoop->reset;
};

subtest 'yielding preserves capacity and reopens after a client closes' => sub {
    my ( $server, $clients, $accepted ) = fixture($LIMIT);
    ok( advance_until( sub { return ${$accepted} == $LIMIT; } ),
        'capacity fills' );
    my $ticks = 0;
    advance_until( sub { return ++$ticks > $BATCH; } );
    is( ${$accepted}, $LIMIT, 'a pending resume cannot bypass the native cap' );
    close shift $clients->@* or croak 'cannot close one fixture client';
    ok(
        advance_until( sub { return ${$accepted} > $LIMIT; } ),
        'closing a connection permits the next queued client'
    );
    is( ${$accepted}, $LIMIT + 1,
        'exactly the available capacity is admitted' );

    for my $client ( $clients->@* ) {
        close $client or croak 'cannot close fixture client';
    }
    undef $server;
    Mojo::IOLoop->reset;
};

subtest
  'large prefork bursts share admission without reducing native capacity' =>
  sub {
    my ( $server, $clients, $accepted ) = fixture( $CLIENTS, $MAX_BATCH, 1 );
    ok( advance_until( sub { return ${$accepted} > 0; } ), 'the burst starts' );
    is(
        ${$accepted},
        $CLIENTS / 2,
        'one worker yields after its share of the new connection cohort'
    );
    ok(
        advance_until( sub { return ${$accepted} == $CLIENTS; } ),
        'the same worker can still admit its full native capacity'
    );
    ok(
        advance_until(
            sub {
                return
                  defined Mojo::IOLoop->acceptor( $server->acceptors->[0] );
            }
        ),
        'the delayed listener is registered again'
    );
    ok(
        !Mojo::IOLoop->acceptor( $server->acceptors->[0] )->is_accepting,
        'the delayed resume preserves the native hard cap'
    );
    for my $client ( $clients->@* ) {
        close $client or croak 'cannot close fixture client';
    }
    undef $server;
    Mojo::IOLoop->reset;
  };

subtest 'graceful shutdown wins over a fairness timer' => sub {
    my ( $server, $clients, $accepted ) = fixture( $CLIENTS, $MAX_BATCH, 1 );
    advance_until( sub { return ${$accepted} > 0; } );
    Mojo::IOLoop->stop_gracefully;
    ok(
        advance_until(
            sub {
                return
                  defined Mojo::IOLoop->acceptor( $server->acceptors->[0] );
            }
        ),
        'the fairness timer completes'
    );
    is(
        ${$accepted},
        $CLIENTS / 2,
        'a draining worker never accepts the next cohort'
    );
    ok(
        !Mojo::IOLoop->acceptor( $server->acceptors->[0] )->is_accepting,
        'the fairness timer does not reopen a draining listener'
    );
    for my $client ( $clients->@* ) {
        close $client or croak 'cannot close fixture client';
    }
    undef $server;
    Mojo::IOLoop->reset;
};

subtest 'graceful stop wins over a scheduled listener resume' => sub {
    my ( $server, $clients, $accepted ) = fixture($CLIENTS);
    advance_until( sub { return ${$accepted} > 0; } );
    Mojo::IOLoop->stop_gracefully;
    my $ticks = 0;
    advance_until( sub { return ++$ticks > $BATCH; } );
    is( ${$accepted}, $BATCH, 'the listener admits no client while draining' );
    ok( !Mojo::IOLoop->acceptor( $server->acceptors->[0] )->is_accepting,
        'the re-registered listener remains stopped' );
    for my $client ( $clients->@* ) {
        close $client or croak 'cannot close fixture client';
    }
    undef $server;
    Mojo::IOLoop->reset;
};

done_testing;

1;
