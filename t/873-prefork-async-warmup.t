# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;
use v5.40;
use lib 'lib', 't/lib';
use Carp qw(croak);
use Const::Fast;
use English    qw(-no_match_vars);
use File::Temp qw(tempdir);
use Mojo::File qw(path);
use Mojo::IOLoop;
use Mojo::Promise;
use Mojo::JSON qw(encode_json decode_json);
use Mojo::Server::Prefork;
use POSIX ();
use Test::More;
use GPForum;
use GPForum::Test::ReplacedSubs qw(with_replaced_subs);

our $VERSION = '0.001';
const my $TICK_SECONDS => 0.02;
local $ENV{GPFORUM_MINION_ENABLED}            = 0;
local $ENV{GPFORUM_REALTIME_LISTENER_ENABLED} = 0;
local $ENV{GPFORUM_WARMUP_ENABLED}            = 0;
my $directory = tempdir( CLEANUP => 1 );
my $result    = path( $directory, 'worker.json' );
my $app       = GPForum->new;
$app->log->level('fatal');
my ( $hashes, @warmed );
$hashes = 0;
with_replaced_subs(
    'GPForum::Service::Password',
    {
        hash_password => sub { $hashes++; return 'private-test-decoy'; },
    },
    sub {
        with_replaced_subs(
            'GPForum::Infrastructure::AsyncQuery',
            {
                prewarm_p => sub {
                    push @warmed, $PROCESS_ID;
                    return Mojo::Promise->resolve(2);
                },
            },
            sub {
                my $server = Mojo::Server::Prefork->new( app => $app );
                $app->server($server);
                is( $hashes, 1,
'the real before_server_start hook warms Argon2 decoy once in the manager'
                );
                is_deeply( \@warmed, [],
                    'the manager opens no asynchronous worker connections' );
                my $child = fork;
                croak 'cannot fork warmup test' if !defined $child;
                if ( !$child ) {
                    Mojo::IOLoop->timer(
                        $TICK_SECONDS => sub {
                            $app->build_controller->gp_password->decoy_hash;
                            $result->spew(
                                encode_json(
                                    { hashes => $hashes, warmed => \@warmed }
                                )
                            );
                            Mojo::IOLoop->stop;
                            return;
                        }
                    );
                    Mojo::IOLoop->start;
                    POSIX::_exit(0);
                }
                waitpid $child, 0;
                is( $CHILD_ERROR, 0, 'the worker starts and exits cleanly' );
                my $observed = decode_json( $result->slurp );
                is_deeply( $observed->{warmed}, [$child],
                    'the inherited first worker tick prewarms once after fork'
                );
                is( $observed->{hashes}, 1,
                    'the child reuses the inherited decoy without another hash'
                );
                return;
            }
        );
        return;
    }
);
done_testing();

1;
