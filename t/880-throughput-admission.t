# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package main;
use v5.40;
use Test::More;
use lib 'lib', 't/lib';
use Mojo::Promise;
use Time::HiRes qw(clock_gettime CLOCK_MONOTONIC);
use GPForum::Infrastructure::AsyncGate;
use GPForum::Infrastructure::Cancellation;
use GPForum::Service::Admin::Configuration;
use GPForum::Config;
use GPForum::Test::RequestContextFunctions;
use GPForum::Test::Promise qw(await_result);
our $VERSION = '0.001';

subtest
  'disconnect immediately frees queue residency without cancelling active work'
  => sub {
    my $gate = GPForum::Infrastructure::AsyncGate->new(
        concurrency => 1,
        max_pending => 1
    );
    my $active_cancel = GPForum::Infrastructure::Cancellation->new;
    my $hold          = Mojo::Promise->new;
    my $running =
      $gate->run_p( sub { return $hold; }, { cancellation => $active_cancel } );
    my $cancel = GPForum::Infrastructure::Cancellation->new;
    my ( $started, $error ) = ( 0, undef );
    my $queued =
      $gate->run_p( sub { ++$started; return 2; }, { cancellation => $cancel } )
      ->catch( sub ($caught) { $error = $caught; return; } );
    $cancel->cancel;
    is( scalar @{ $gate->pending },
        0, 'closed request leaves the queue immediately' );
    my $replacement = $gate->run_p( sub { return 'replacement'; } );
    $active_cancel->cancel;
    is( $gate->active, 1,
        'already admitted work retains ownership until completion' );
    $hold->resolve('committed');
    my $all =
      await_result( Mojo::Promise->all( $running, $queued, $replacement ) );
    is( $started, 0, 'disconnected queued operation never starts' );
    isa_ok( $error, 'GPForum::X::Unavailable' );
    is( await_result($running), 'committed', 'active work completes normally' );
    is( await_result($replacement),
        'replacement', 'replacement uses the released queue slot' );
    is( $gate->snapshot->{cancelled}, 1, 'cancellation is observable' );
    is( $gate->active,                0, 'no execution slot is lost' );
  };

subtest 'an expired request budget never starts new work' => sub {
    my $gate   = GPForum::Infrastructure::AsyncGate->new;
    my $cancel = GPForum::Infrastructure::Cancellation->new(
        deadline => clock_gettime(CLOCK_MONOTONIC) - 1 );
    my ( $started, $error ) = ( 0, undef );
    $gate->run_p( sub { ++$started; }, { cancellation => $cancel } )
      ->catch( sub ($caught) { $error = $caught; return; } )
      ->wait;
    is( $started, 0, 'expired work does not execute even with free capacity' );
    isa_ok( $error, 'GPForum::X::Unavailable' );
    is( $gate->active, 0, 'expired admission consumes no slot' );
};

subtest 'out-of-order configuration replies keep their own revision' => sub {
    my $schema    = bless {}, 'GPForum::Test::RequestContextSchema';
    my $functions = GPForum::Test::RequestContextFunctions->new;
    my $cache     = {
        schema   => $schema,
        revision => 0,
        settings => { general => { value => 'old' }, plugins => {} }
    };
    my @requests = map {
        GPForum::Service::Admin::Configuration->new(
            schema      => $schema,
            base_config => GPForum::Config->new,
            functions   => $functions,
            state_cache => $cache
        )
    } 1 .. 2;
    my @promises = map { $_->request_context_p( {} ) } @requests;
    $functions->calls->[1]{promise}->resolve(
        {
            revision           => 1,
            public_cache_epoch => 2,
            settings => { general => { value => 'new' }, plugins => {} }
        }
    );
    await_result( $promises[1] );
    $functions->calls->[0]{promise}->resolve(
        { revision => 0, public_cache_epoch => 1, settings => undef } );
    await_result( $promises[0] );
    is( $requests[0]->state->{settings}{general}{value},
        'old', 'old response uses the revision captured before awaiting' );
    is( $requests[1]->state->{settings}{general}{value},
        'new', 'new response uses new settings' );
    is( $cache->{revision}, 1,
        'late older response cannot roll back reusable settings' );
    $requests[0]->state->{settings}{general}{value} = 'request mutation';
    is( $cache->{settings}{general}{value},
        'new', 'request data does not mutate shared settings' );
};
done_testing;
1;
