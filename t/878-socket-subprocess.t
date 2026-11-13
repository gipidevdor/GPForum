# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package main;
use v5.40;
use utf8;
use Carp qw(croak);
use Const::Fast;
use English qw(-no_match_vars);
use Mojo::IOLoop;
use POSIX       qw(WNOHANG);
use Storable    qw(nfreeze thaw);
use Time::HiRes qw(sleep);
use Digest::SHA qw(sha256_hex);
use Test::More;
use lib 'lib';
use GPForum::Infrastructure::Subprocess;

our $VERSION = '0.001';
const my $DEADLINE   => 30;
const my $SAMPLES    => 12;
const my $BYTES      => 1_048_576;
const my $DELAY      => 0.15;
const my $TICK       => 0.01;
const my $ERROR_EXIT => 7;
const my $NO_CHILD   => -1;

local $SIG{ALRM} =
  sub { BAIL_OUT('subprocess transport exceeded its deadline'); };
alarm $DEADLINE;

for my $number ( 1 .. $SAMPLES ) {
    my $child = _child();
    my ( $value, $error );
    my $pending =
      $child->run_p( sub { return pack 'H*', '00ff5c62696e61727900'; } );
    $pending->then( sub ($result) { $value = $result; return; } )
      ->catch( sub ($caught) { $error = $caught; return; } )
      ->wait;
    is( $error, undef, "subprocess $number completes without transport error" );
    is(
        $value,
        pack( 'H*', '00ff5c62696e61727900' ),
        "subprocess $number preserves binary IPC"
    );
    is( waitpid( $child->pid, WNOHANG ),
        $NO_CHILD, "subprocess $number leaves no zombie" );
}

my $child = _child();
my @progress;
$child->on( progress => sub ( $, @values ) { push @progress, \@values; } );
my @values;
my $binary = 'x' x $BYTES;
$child->run_p(
    sub ($process) {
        $process->progress('starting');
        return ( $PROCESS_ID, 'è🙂', $binary );
    }
)->then( sub (@results) { @values = @results; return; } )->wait;
is_deeply(
    \@progress,
    [ ['starting'] ],
    'native progress events retain their framing'
);
isnt( $values[0], $PROCESS_ID, 'work executes in a separate process' );
is( $values[1], 'è🙂', 'Unicode survives the subprocess boundary' );
is( sha256_hex( $values[2] ),
    sha256_hex($binary), 'large binary results survive socket backpressure' );

my $error;
_child()
  ->run_p( sub { croak 'expected child failure'; } )
  ->catch( sub ($caught) { $error = $caught; return; } )
  ->wait;
like(
    "$error",
    qr/expected[ ]child[ ]failure/msx,
    'child failures reject the native promise'
);
$error = undef;
_child()
  ->run_p( sub { POSIX::_exit($ERROR_EXIT); } )
  ->catch( sub ($caught) { $error = $caught; return; } )
  ->wait;
like(
    "$error",
    qr/without[ ]a[ ]result/msx,
    'an abruptly exited child cannot produce a false success'
);

my ( $callback_error, $callback_value );
_child()->run(
    sub { return 'callback-result'; },
    sub ( $, $caught, @results ) {
        $callback_error = $caught;
        $callback_value = $results[0];
        Mojo::IOLoop->stop;
        return;
    }
);
Mojo::IOLoop->start;
is( $callback_error, q{}, 'the inherited callback API receives no error' );
is( $callback_value, 'callback-result',
    'the inherited callback API preserves results' );

my ( $closing, $ticks ) = ( 0, 0 );
$child = _child();
$child->on( progress => sub { $closing = 1; return; } );
$child->on(
    cleanup => sub ($process) {
        close $process->{writer} or croak 'cannot close child IPC fixture';
        sleep $DELAY;
        return;
    }
);
my $ticker = Mojo::IOLoop->recurring(
    $TICK => sub {
        if ($closing) { $ticks++; }
        return;
    }
);
my $finished;
$child->run_p(
    sub ($process) { $process->progress('closing'); return 'finished'; } )
  ->then( sub ($result) { $finished = $result; return; } )
  ->wait;
Mojo::IOLoop->remove($ticker);
is( $finished, 'finished',
    'a child can finish cleanup after closing its transport' );
cmp_ok( $ticks, '>', 1, 'reaping after EOF leaves reactor timers responsive' );

alarm 0;
done_testing();

sub _child {
    return GPForum::Infrastructure::Subprocess->new(
        serialize   => sub { return nfreeze( $_[0] ); },
        deserialize => sub { return thaw( $_[0] ); }
    );
}
1;
