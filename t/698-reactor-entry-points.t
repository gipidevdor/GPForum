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

# libev reads LIBEV_FLAGS when EV loads, and morbo, Test::Mojo, yath or a
# profiler load it before GPForum can choose. The front door chooses before
# any Perl starts; a runner that bypasses it still starts a development
# application, on the fallback and with a warning; production refuses it.

const my $SELECT => 1;
const my @PRODUCTION_ENVIRONMENT => (
    GPFORUM_ENV             => 'production',
    GPFORUM_SESSION_SECRET  => 'reactor-entry-points-secret-' . ( 'x' x 32 ),
    GPFORUM_GLIFISTORE_URL  => 'tcp://127.0.0.1:7379',
    GPFORUM_METRICS_TOKEN   => 'reactor-entry-points-metrics-token',
    GPFORUM_PUBLIC_BASE_URL => 'https://forum.example.test',
    GPFORUM_MAIL_FROM       => 'forum@forum.example.test',
);

my $native = GPForum::OS::Reactor->expected_backend;
if ( !$native ) {
    plan skip_all =>
      'the native backend is required on Linux, macOS and FreeBSD';
}

subtest 'the front door chooses the backend before any Perl starts' => sub {
    my ( $status, $output ) = _run(
        [
            'script/gpforum-carton', 'exec', 'perl', '-e',
            'print qq{$ENV{MOJO_REACTOR}:$ENV{LIBEV_FLAGS}}',
        ],
        MOJO_REACTOR => 'Mojo::Reactor::Poll',
        LIBEV_FLAGS  => $SELECT,
    );
    is( $status, 0, 'script/gpforum-carton exec runs perl' );
    is(
        $output,
        "Mojo::Reactor::EV:$native->{flags}",
        'it exports the same backend GPForum::OS::Reactor requires'
    );

    ( $status, $output ) = _run(
        [
            'script/gpforum-carton',
            'exec',
            'perl',
            '-Ilib',
            '-e',
            'use Test::Mojo; Test::Mojo->new(q{GPForum});'
              . ' print q{backend=}, EV::backend();',
        ],
        LIBEV_FLAGS => $SELECT,
    );
    is( $status, 0, 'a test that loads Test::Mojo first starts the app' );
    like(
        $output,
        qr/backend=\Q$native->{flags}\E(?!\d)/msx,
        'and runs on the native backend'
    );
    unlike( $output, qr/GPForum::OS::Reactor/msx, 'without a warning' );
};

subtest 'a bypassed front door still starts a development application' => sub {
    my ( $status, $output ) = _run(
        [
            $EXECUTABLE_NAME,
            '-Ilib',
            '-MEV',
            '-e',
            'require GPForum; GPForum->new; print q{backend=}, EV::backend();',
        ],
        GPFORUM_ENV => 'development',
        LIBEV_FLAGS => $SELECT,
    );
    is( $status, 0, 'development starts on the backend EV already chose' );
    like( $output, qr/backend=$SELECT(?!\d)/msx, 'the loop is left as it was' );
    like(
        $output,
        qr/runs [ ] libev [ ] select [ ] [(]1[)]/msx,
        'the log says what ran'
    );
    like(
        $output,
qr{LIBEV_FLAGS=\Q$native->{flags}\E .* script/gpforum-carton [ ] exec}msx,
        'and which entry point sets the backend'
    );
};

subtest 'production refuses the fallback' => sub {
    my ( $status, $output ) = _run(
        [
            $EXECUTABLE_NAME, '-Ilib', '-MEV', '-e',
            'require GPForum; GPForum->new; print q{started};',
        ],
        @PRODUCTION_ENVIRONMENT,
        LIBEV_FLAGS => $SELECT,
    );
    isnt( $status, 0, 'production does not start on select' );
    like(
        $output,
        qr/GPForum [ ] requires [ ] \Q$native->{name}\E;/msx,
        'it names the backend production requires'
    );
    like(
        $output,
qr/LIBEV_FLAGS=\Q$native->{flags}\E [ ] MOJO_REACTOR=Mojo::Reactor::EV/msx,
        'and the variables that choose it'
    );
    unlike( $output, qr/started/msx, 'nothing is served' );

    ( $status, $output ) = _run(
        [
            $EXECUTABLE_NAME,
            '-Ilib',
            '-e',
            'require GPForum; GPForum->new; print q{backend=}, EV::backend();',
        ],
        @PRODUCTION_ENVIRONMENT,
        LIBEV_FLAGS => $SELECT,
    );
    is( $status, 0, 'production loaded first starts' );
    like(
        $output,
        qr/backend=\Q$native->{flags}\E(?!\d)/msx,
        'on the native backend, whatever was inherited'
    );
};

done_testing();

sub _run ( $command, %environment ) {
    local %ENV = ( %ENV, %environment );
    delete local $ENV{HARNESS_ACTIVE};
    my $error = gensym;
    my $pid   = open3( my $input, my $output, $error, @{$command} );
    close $input or croak "close child input: $OS_ERROR";
    my $text = do { local $INPUT_RECORD_SEPARATOR = undef; <$output> // q{} };
    $text .= do { local $INPUT_RECORD_SEPARATOR = undef; <$error> // q{} };
    close $output or croak "close child output: $OS_ERROR";
    close $error  or croak "close child error: $OS_ERROR";
    waitpid $pid, 0;

    return ( $CHILD_ERROR, $text );
}

1;
