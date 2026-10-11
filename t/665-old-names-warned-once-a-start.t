# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use File::Temp qw(tempdir);
use Mojo::File qw(path);
use Mojo::Log;
use Mojolicious;
use Test::More;

use lib 'lib';

use GPForum::Bootstrap::Config;
use GPForum::CLI::start;
use GPForum::Config;

our $VERSION = '0.001';

# Walkthrough 4, friction 6: a service started with old names in its
# environment file logged each warning twice, 0.9 s apart -- once by
# gpforum start --service, once by Hypnotoad, which it runs in its place and
# which built the application again.

subtest 'the old names are warned of once a start' => sub {
    my $config = GPForum::Config->from_environment(
        {
            GPFORUM_ENV              => 'development',
            GPFORUM_WORKER_PROCESSES => 4,
            GPFORUM_SMTP_SSL         => 'off',
        }
    );
    local $ENV{GPFORUM_SETTINGS_WARNED} = undef;
    local $ENV{GPFORUM_ENV_FILE}        = undef;
    local $ENV{PERL5LIB}                = $ENV{PERL5LIB};
    is( scalar @{ _warnings($config) },
        2, 'the front door warns of each, as it builds the application' );

    my $root = tempdir( CLEANUP => 1 );
    path( $root, 'local', 'bin' )->make_path;
    path( $root, 'local', 'bin', 'hypnotoad' )->spew("#!perl\n");
    my %told;
    GPForum::CLI::start->new(
        root    => $root,
        replace => sub (@) { %told = %ENV; },
    )->run('--service');
    is( $told{GPFORUM_SETTINGS_WARNED},
        1, 'start --service tells Hypnotoad, run in its place, that it did' );

    local $ENV{GPFORUM_SETTINGS_WARNED} = 1;
    is_deeply( _warnings($config), [],
        'and Hypnotoad, building it again, does not warn again' );
};

done_testing();

# What Bootstrap::Config logs for a configuration, warning by warning.
sub _warnings ($config) {
    my $application = Mojolicious->new;
    my @warnings;
    $application->log( Mojo::Log->new( level => 'warn' ) );
    $application->log->unsubscribe('message')->on(
        message => sub ( $, $level, @lines ) {
            if ( $level eq 'warn' ) {
                push @warnings, join q{ }, @lines;
            }
        }
    );
    GPForum::Bootstrap::Config->register(
        application => $application,
        config      => $config,
    );

    return \@warnings;
}

1;
