# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package main;
use v5.40;
use lib 'lib', 't/lib';
use Test::More;
use Mojo::Promise;
use GPForum::Infrastructure::AsyncGate;
use GPForum::Infrastructure::AsyncWork;
use GPForum::Infrastructure::Cancellation;
use GPForum::Service::Forum::BodyRenderer;
use GPForum::Test::Promise      qw(await_result);
use GPForum::Test::ReplacedSubs qw(with_replaced_subs);
our $VERSION = '0.001';
my $renderer = GPForum::Service::Forum::BodyRenderer->new;

subtest 'one departing reader leaves shared queued work for the other' => sub {
    _lane(
        sub ( $lane, $starts ) {
            my ( $hold, $blocker ) = _block($lane);
            my $first           = GPForum::Infrastructure::Cancellation->new;
            my $surviving_token = GPForum::Infrastructure::Cancellation->new;
            my $a = $renderer->render_many_p( ['Shared **queued** body'],
                { cancellation => $first } );
            my $b = $renderer->render_many_p( ['Shared **queued** body'],
                { cancellation => $surviving_token } );
            my $error;
            $a->catch( sub ($caught) { $error = $caught; return; } );
            $first->cancel;
            is( $lane->gate->snapshot->{pending},
                1, 'one shared batch still waits' );
            is( $lane->gate->snapshot->{cancelled},
                0, 'shared admission was not cancelled' );
            $hold->resolve;
            await_result($blocker);
            my $result = await_result($b);
            is(
                $result->{'plain:Shared **queued** body'},
                '<p>Shared <strong>queued</strong> body</p>',
                'surviving reader gets safe HTML'
            );
            isa_ok( $error, 'GPForum::X::Unavailable' );
            is( ${$starts}, 1, 'one real child served both readers' );
            is( scalar keys %{ $surviving_token->callbacks },
                0, 'completion releases the request subscription' );
        }
    );
};

subtest
  'the last departure removes queued work and permits a fresh subscriber' =>
  sub {
    _lane(
        sub ( $lane, $starts ) {
            my ( $hold, $blocker ) = _block($lane);
            my $token = GPForum::Infrastructure::Cancellation->new;
            my $error;
            $renderer->render_many_p( ['Abandoned and rejoined'],
                { cancellation => $token } )
              ->catch( sub ($caught) { $error = $caught; return; } );
            $token->cancel;
            is( $lane->gate->snapshot->{pending},
                0, 'abandoned batch immediately leaves the queue' );
            is( $lane->gate->snapshot->{cancelled},
                1, 'the queued admission records cancellation' );
            is( ${$starts}, 0, 'no child was created for abandoned work' );
            my $fresh = $renderer->render_many_p( ['Abandoned and rejoined'] );
            my $late;
            await_result(
                Mojo::Promise->resolve->then(
                    sub {
                        $late = $renderer->render_many_p(
                            ['Abandoned and rejoined'] );
                        return;
                    }
                )
            );
            is( $lane->gate->snapshot->{pending},
                1, 'old rejection cleanup cannot erase the replacement batch' );
            $hold->resolve;
            await_result($blocker);
            is_deeply( await_result($fresh), await_result($late),
                'both replacement readers get the same result' );
            isa_ok( $error, 'GPForum::X::Unavailable' );
            is( ${$starts}, 1, 'only the replacement batch starts a child' );
        }
    );
  };

subtest 'a reader without a cancellation context still owns its shared work' =>
  sub {
    _lane(
        sub ( $lane, $starts ) {
            my ( $hold, $blocker ) = _block($lane);
            my $token = GPForum::Infrastructure::Cancellation->new;
            $renderer->render_many_p( ['Legacy consumer remains'],
                { cancellation => $token } )->catch( sub { return; } );
            my $legacy =
              $renderer->render_many_p( ['Legacy consumer remains'] );
            $token->cancel;
            is( $lane->gate->snapshot->{pending},
                1, 'context-free reader retains the batch' );
            $hold->resolve;
            await_result($blocker);
            ok( await_result($legacy)->{'plain:Legacy consumer remains'},
                'legacy API remains usable' );
            is( ${$starts}, 1, 'legacy reader gets the shared child' );
        }
    );
  };

subtest 'admitted work remains joinable after its first consumer departs' =>
  sub {
    _lane(
        sub ( $lane, $starts ) {
            my $token = GPForum::Infrastructure::Cancellation->new;
            $renderer->render_many_p( ['Already admitted'],
                { cancellation => $token } )->catch( sub { return; } );
            is( $lane->gate->snapshot->{active},
                1, 'work is admitted before the reactor runs the child' );
            $token->cancel;
            my $next = $renderer->render_many_p( ['Already admitted'] );
            is( $lane->gate->snapshot->{pending},
                0,
                'a later reader joins instead of scheduling duplicate work' );
            ok(
                await_result($next)->{'plain:Already admitted'},
                'admitted rendering finishes normally'
            );
            is( ${$starts}, 1, 'only one actual child was used' );
        }
    );
  };

subtest 'partial overlap cancels only batches with no remaining consumers' =>
  sub {
    _lane(
        sub ( $lane, $starts ) {
            my ( $hold, $blocker ) = _block($lane);
            my $survivor = $renderer->render_many_p( ['Overlap shared'] );
            my $token    = GPForum::Infrastructure::Cancellation->new;
            $renderer->render_many_p( [ 'Overlap shared', 'Overlap unused' ],
                { cancellation => $token } )->catch( sub { return; } );
            $token->cancel;
            is( $lane->gate->snapshot->{pending},
                1, 'shared batch remains and unused batch is removed' );
            is( $lane->gate->snapshot->{cancelled},
                1, 'only one admission is cancelled' );
            $hold->resolve;
            await_result($blocker);
            ok(
                await_result($survivor)->{'plain:Overlap shared'},
                'overlapping survivor still receives its body'
            );
            is( ${$starts}, 1, 'unused body did not create a child' );
        }
    );
  };

subtest 'a request already closed admits no rendering' => sub {
    _lane(
        sub ( $lane, $starts ) {
            my $token = GPForum::Infrastructure::Cancellation->new;
            $token->cancel;
            my $error;
            await_result(
                $renderer->render_many_p( ['Never admitted'],
                    { cancellation => $token } )
                  ->catch( sub ($caught) { $error = $caught; return; } )
            );
            isa_ok( $error, 'GPForum::X::Unavailable' );
            is( $lane->gate->snapshot->{started}, 0, 'no gate work started' );
            is( ${$starts},                       0, 'no child started' );
        }
    );
};

done_testing;

sub _lane ($work) {
    my $lane     = GPForum::Infrastructure::AsyncWork->new;
    my $starts   = 0;
    my $original = GPForum::Infrastructure::Subprocess->can('_start');
    with_replaced_subs(
        'GPForum::Infrastructure::AsyncWork',
        { rendering => sub { return $lane; } },
        sub {
            with_replaced_subs(
                'GPForum::Infrastructure::Subprocess',
                {
                    _start => sub { ++$starts; return $original->(@_); }
                },
                sub { $work->( $lane, \$starts ); return; }
            );
            return;
        }
    );
    return;
}

sub _block ($lane) {
    my $hold    = Mojo::Promise->new;
    my $blocker = $lane->gate->run_p( sub { return $hold; } );
    return ( $hold, $blocker );
}
1;
