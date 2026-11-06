# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;
use v5.40;
use utf8;
use Const::Fast;
use Carp    qw(croak);
use English qw(-no_match_vars);
use Mojo::IOLoop;
use Mojo::Promise;
use Mojo::UserAgent;
use Mojolicious;
use Test::Mojo;
use Test::More;
use Time::HiRes qw(sleep);
use lib 'lib', 't/lib';
use GPForum::Controller::Base;
use GPForum::Infrastructure::AsyncGate;
use GPForum::Infrastructure::AsyncWork;
use GPForum::Log;
use GPForum::Service::Attachment::PostgresAsset;
use GPForum::Web::MediaResponse;
use GPForum::Test::AsyncChunkStorage;

our $VERSION = '0.001';
const my $REQUEST_SECONDS   => 3;
const my $QUEUE_SECONDS     => 0.01;
const my $SLOW_SECONDS      => 0.15;
const my $FAST_SECONDS      => 0.03;
const my $TICK_SECONDS      => 0.01;
const my $HTTP_OK           => 200;
const my $HTTP_PARTIAL      => 206;
const my $HTTP_NOT_MODIFIED => 304;
const my $HTTP_UNAVAILABLE  => 503;

subtest 'capacity is bounded and released after errors' => sub {
    my $gate = GPForum::Infrastructure::AsyncGate->new(
        concurrency => 1,
        max_pending => 1
    );
    my $hold = Mojo::Promise->new;
    my @started;
    my $first  = $gate->run_p( sub { push @started, 1; return $hold; } );
    my $queued = $gate->run_p( sub { push @started, 2; return 2; } );
    my $rejected;
    my $third = $gate->run_p( sub { croak 'must never start'; } )->catch(
        sub ($error) {
            $rejected = $error;
            return;
        }
    );
    Mojo::IOLoop->timer( $FAST_SECONDS => sub { $hold->resolve(1); } );
    Mojo::Promise->all( $first, $queued, $third )->wait;
    isa_ok( $rejected, 'GPForum::X::Unavailable' );
    is_deeply( \@started, [ 1, 2 ], 'queued operations start in order' );
    my $failed;
    $gate->run_p( sub { croak 'expected operation error'; } )
      ->catch( sub { $failed = 1; return; } )
      ->wait;
    ok( $failed, 'synchronous exceptions become promise rejections' );
    my $after;
    $gate->run_p( sub { return 'recovered'; } )
      ->then( sub ($value) { $after = $value; return; } )
      ->wait;
    is( $after, 'recovered', 'a failed operation does not retain capacity' );
};

subtest
  'queued work expires without starting and cancelled work never forks' => sub {
    my $gate = GPForum::Infrastructure::AsyncGate->new(
        concurrency   => 1,
        max_pending   => 1,
        queue_timeout => $QUEUE_SECONDS
    );
    my $hold    = Mojo::Promise->new;
    my $running = $gate->run_p( sub { return $hold; } );
    my ( $started, $expired ) = ( 0, undef );
    my $queued = $gate->run_p( sub { $started++; return; } )->catch(
        sub ($error) {
            $expired = $error;
            return;
        }
    );
    Mojo::IOLoop->timer( $FAST_SECONDS => sub { $hold->resolve; } );
    Mojo::Promise->all( $running, $queued )->wait;
    isa_ok( $expired, 'GPForum::X::Unavailable' );
    is( $started, 0, 'an expired queue entry performs no work' );
    is_deeply( $gate->pending, [], 'expired jobs release queue residency' );
    my $cancelled;
    my $cancel_work = GPForum::Infrastructure::AsyncWork->new;
    $cancel_work->run_p( sub { croak 'unexpected child'; }, sub { return 1; } )
      ->catch( sub ($error) { $cancelled = $error; return; } )
      ->wait;
    like(
        "$cancelled",
        qr/request [ ] closed/msx,
        'a disconnected queued request starts no subprocess'
    );
  };

subtest 'a slow subprocess leaves the HTTP event loop responsive' => sub {
    my $work   = GPForum::Infrastructure::AsyncWork->new;
    my $binary = pack 'H*', '00ff5c62696e61727900';
    $work->run_p( sub { return $binary; } )->then(
        sub ($value) {
            is( $value, $binary,
                'private IPC preserves arbitrary binary bytes' );
            ok( !utf8::is_utf8($value),
                'binary IPC does not turn bytes into characters' );
            return;
        }
    )->wait;
    my $context = { request_id => 'isolated-child' };
    my $logged  = GPForum::Log->in_context(
        $context,
        sub {
            return $work->run_p(
                sub {
                    return GPForum::Log->request_context->{request_id};
                }
            );
        }
    );
    is( GPForum::Log->request_context,
        undef, 'the parent context is restored before yielding' );
    $logged->then(
        sub ($value) {
            is( $value, 'isolated-child',
                'child work retains its originating log context' );
            return;
        }
    )->wait;
    my $app = Mojolicious->new;
    $app->log->level('fatal');
    $app->controller_class('GPForum::Controller::Base');
    my ( $finished, $ticks ) = ( 0, 0 );
    my $ticker = Mojo::IOLoop->recurring( $TICK_SECONDS => sub { $ticks++; } );
    $app->routes->get('/slow')->to(
        cb => sub ($c) {
            return $c->respond_p(
                $work->run_p(
                    sub {
                        sleep $SLOW_SECONDS;
                        return { pid => $PROCESS_ID, text => 'è🙂' };
                    }
                ),
                sub ($value) { return $c->render( json => $value ); }
            );
        }
    );
    $app->routes->get('/ready')
      ->to( cb => sub ($c) { return $c->render( text => 'ready' ); } );
    my $ua = Mojo::UserAgent->new->request_timeout($REQUEST_SECONDS);
    $ua->server->app($app);
    my $slow = $ua->get_p('/slow')->then(
        sub ($tx) {
            $finished = 1;
            is( $tx->res->code, $HTTP_OK, 'slow response completes' );
            isnt( $tx->res->json->{pid},
                $PROCESS_ID, 'blocking work ran in another process' );
            is( $tx->res->json->{text}, 'è🙂', 'IPC preserves Unicode data' );
            return;
        }
    );
    my $ready = Mojo::Promise->new;
    Mojo::IOLoop->timer(
        $FAST_SECONDS => sub {
            $ua->get_p('/ready')->then(
                sub ($tx) {
                    is( $tx->res->code, $HTTP_OK,
                        'another request completes meanwhile' );
                    ok( !$finished,
                        'health response precedes the slow operation' );
                    $ready->resolve;
                    return;
                }
            )->catch( sub ($error) { $ready->reject($error); return; } );
        }
    );
    Mojo::Promise->all( $slow, $ready )
      ->catch( sub ($error) { fail("concurrent requests: $error"); return; } )
      ->wait;
    Mojo::IOLoop->remove($ticker);
    cmp_ok( $ticks, '>', 1, 'timers advance during the blocking operation' );
};

subtest
  'database media use asynchronous reads, ranges and conditional requests' =>
  sub {
    my $storage = GPForum::Test::AsyncChunkStorage->new;
    my $app     = Mojolicious->new;
    $app->log->level('fatal');
    $app->routes->get('/media')->to(
        cb => sub ($c) {
            my $asset = GPForum::Service::Attachment::PostgresAsset->new(
                storage     => $storage,
                object_key  => 'test',
                byte_size   => length( $storage->bytes ),
                modified_at => 0
            );
            return GPForum::Web::MediaResponse->new->render( $c, $asset,
                'digest' );
        }
    );
    my $t = Test::Mojo->new($app);
    $t->get_ok('/media')->status_is($HTTP_OK)->content_is('0123456789');
    $t->get_ok( '/media' => { Range => 'bytes=2-5' } )
      ->status_is($HTTP_PARTIAL)
      ->content_is('2345');
    $storage->reads( [] );
    $t->head_ok('/media')->status_is($HTTP_OK)->content_is(q{});
    $t->get_ok( '/media' => { 'If-None-Match' => '"digest"' } )
      ->status_is($HTTP_NOT_MODIFIED);
    is_deeply( $storage->reads, [],
        'HEAD and conditional responses read no binary chunks' );
    $storage->fail(1);
    $t->get_ok('/media')->status_is($HTTP_UNAVAILABLE);
  };

done_testing();

1;
