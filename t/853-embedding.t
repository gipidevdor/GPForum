# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package main;
use v5.40;
use utf8;
use Test::More;
use Const::Fast;
use English     qw(-no_match_vars);
use File::Temp  qw(tempdir);
use Time::HiRes qw(time);
use lib 'lib';
use GPForum::Infrastructure::Embedding;
use GPForum::Config;
our $VERSION = '0.001';
const my $DIMENSIONS => 384;
const my $TAIL       => $DIMENSIONS - 1;
const my $LONG_INPUT => 4000;
const my $DEADLINE   => 5;

my $provider = GPForum::Infrastructure::Embedding->new;
is( GPForum::Infrastructure::Embedding->from_config( GPForum::Config->new ),
    undef, 'semantic inference is off by default' );
my @valid = ( 1, (0) x $TAIL );
like( $provider->vector_literal( \@valid ), qr/\A\[1,0,/msx, 'vector literal' );
for my $invalid (
    [],
    [ (0) x $DIMENSIONS ],
    [ 'NaN', (0) x $TAIL ],
    [ undef, (0) x $TAIL ],
    [ 'Infinity', (0) x $TAIL ],
    [ 2, (0) x $TAIL ],
    [ {}, (0) x $TAIL ]
  )
{
    my $error;
    try { $provider->vector_literal($invalid); }
    catch ($caught) { $error = "$caught"; };
    like(
        $error,
        qr/local[ ]embedding[ ]unavailable/msx,
        'invalid vectors fail closed'
    );
}

# Exercise the real process transport without downloading an ML model.
my $echo = GPForum::Infrastructure::Embedding->new(
    command => [
        $EXECUTABLE_NAME,
        '-MJSON::PP',
        '-e',
'local $/; my $s=decode_json(<STDIN>); die if length($s)!=2000 || ord(substr($s,0,1))!=232; print encode_json([1,(0)x383]);'
    ]
);
like( $echo->embed( q{è} x $LONG_INPUT ),
    qr/\A\[1,0,/msx,
    'Unicode input reaches stdin and is bounded before inference' );

my $noisy = GPForum::Infrastructure::Embedding->new(
    command => [
        $EXECUTABLE_NAME,
        '-MJSON::PP',
        '-e',
'print STDERR "private model diagnostic\n" x 5000 or die "stderr write failed"; print encode_json([1,(0)x383]);'
    ]
);
like( $noisy->embed('private query'),
    qr/\A\[1,0,/msx,
    'model stderr is discarded without breaking its output or process' );

for my $program ( 'print "x" x 40000', 'exit 3', 'close STDOUT; sleep 20' ) {
    my $broken = GPForum::Infrastructure::Embedding->new(
        command         => [ $EXECUTABLE_NAME, '-e', $program ],
        timeout_seconds => 1
    );
    my $start = time;
    my $error;
    try { $broken->embed('private query'); }
    catch ($caught) { $error = "$caught"; };
    like(
        $error,
        qr/local[ ]embedding[ ]unavailable/msx,
        'failed or stalled process is rejected'
    );
    unlike( $error, qr/private[ ]query/msx,
        'input is absent from diagnostics' );
    cmp_ok( time - $start,
        '<', $DEADLINE, 'the whole process lifetime is bounded' );
}

my $directory = tempdir( CLEANUP => 1 );
for my $command (
    ["$directory/missing-python"],
    [ $EXECUTABLE_NAME, '-e', 'print "private audit sentinel"' ],
  )
{
    my $broken = GPForum::Infrastructure::Embedding->new( command => $command );
    my $error;
    try { $broken->embed('private audit sentinel'); }
    catch ($caught) { $error = $caught; };
    isa_ok( $error, 'GPForum::X::Unavailable',
        'launch and output failures use the declared exception' );
    unlike(
        "$error",
        qr/private[ ]audit[ ]sentinel|missing-python/msx,
        'diagnostics omit process output and executable paths'
    );
}
done_testing();
1;
