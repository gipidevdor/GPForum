# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Carp qw(croak);
use Const::Fast;
use English    qw(-no_match_vars);
use IPC::Open3 qw(open3);
use Symbol     qw(gensym);
use Test::More;

use lib 'lib';
use GPForum::OS::Reactor ();

our $VERSION = '0.001';

const my $EPOLL         => 4;
const my $KQUEUE        => 8;
const my $NATIVE_CHECKS => 10;

for my $os (qw(linux darwin freebsd)) {
    my $expected =
      $os eq 'linux'
      ? { name => 'epoll',  flags => $EPOLL }
      : { name => 'kqueue', flags => $KQUEUE };
    is_deeply( GPForum::OS::Reactor->expected_backend($os),
        $expected, "$os requires its native backend" );
}
is( GPForum::OS::Reactor->expected_backend('unknown'),
    undef, 'an unknown OS keeps portable detection' );

my $native = GPForum::OS::Reactor->expected_backend;
SKIP: {
    if ( !$native ) {
        skip 'native backend checks require a supported OS', $NATIVE_CHECKS;
    }

    my ( $status, $output ) = _probe(
        ['-MGPForum::OS::Reactor'],
        'GPForum::OS::Reactor->assert_native; '
          . 'print ref(Mojo::IOLoop->singleton->reactor), q{:}, EV::backend();',
        MOJO_REACTOR => 'Mojo::Reactor::Poll',
        LIBEV_FLAGS  => 1,
    );
    is( $status, 0, 'inherited fallback settings cannot weaken the policy' );
    is(
        $output,
        "Mojo::Reactor::EV:$native->{flags}",
        'the actual singleton and libev backend are native'
    );

    ( $status, $output ) = _probe(
        [],
'use GPForum; my $app = GPForum->new; print q{native_backend=}, EV::backend(), qq{\n};',
        MOJO_REACTOR => 'Mojo::Reactor::Poll',
        LIBEV_FLAGS  => 1
    );
    is( $status, 0, 'direct application loading configures the loop early' );
    like(
        $output,
        qr/\A native_backend=\Q$native->{flags}\E\n/msx,
        'application startup uses the native backend'
    );

    ( $status, $output ) = _probe(
        ['-MEV'],
        'require GPForum::OS::Reactor; GPForum::OS::Reactor->assert_native;',
        MOJO_REACTOR => 'Mojo::Reactor::EV',
        LIBEV_FLAGS  => 1
    );
    isnt( $status, 0, 'a strict check refuses an EV loop already on select' );
    like(
        $output,
        qr/runs [ ] libev [ ] select [ ] [(]1[)]/msx,
        'the refusal reports the real backend, even with an EV reactor'
    );

    ( $status, $output ) = _probe(
        ['-MMojo::IOLoop'],
        'require GPForum::OS::Reactor; GPForum::OS::Reactor->assert_native;',
        MOJO_REACTOR => 'Mojo::Reactor::Poll',
        LIBEV_FLAGS  => $native->{flags}
    );
    isnt( $status, 0, 'a strict check refuses an existing Poll singleton' );
    like(
        $output,
        qr/runs [ ] Mojo::Reactor::Poll/msx,
        'the refusal identifies Poll without replacing an existing loop'
    );

    ( $status, $output ) = _probe( ['-MGPForum::OS::Reactor'],
        '$INC{"EV.pm"} = undef; GPForum::OS::Reactor->assert_native;' );
    isnt( $status, 0, 'missing EV fails instead of falling back' );
    like(
        $output,
        qr/install [ ] the [ ] locked [ ] dependencies/msx,
        'a missing native dependency gives installation guidance'
    );
}

done_testing();

# A new process is necessary: EV initialises its unique default loop at load
# time, so reconfiguring the test process would conceal the load-order bug.
sub _probe ( $preload, $code, %environment ) {
    local %ENV = ( %ENV, %environment );
    my $error = gensym;
    my $pid   = open3( my $input, my $output, $error,
        $EXECUTABLE_NAME, '-Ilib', @{$preload}, '-e', $code );
    close $input or croak "close child input: $OS_ERROR";
    my $text = do { local $INPUT_RECORD_SEPARATOR = undef; <$output> // q{} };
    $text .= do { local $INPUT_RECORD_SEPARATOR = undef; <$error> // q{} };
    close $output or croak "close child output: $OS_ERROR";
    close $error  or croak "close child error: $OS_ERROR";
    waitpid $pid, 0;

    return ( $CHILD_ERROR, $text );
}

1;
