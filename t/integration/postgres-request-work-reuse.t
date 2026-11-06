# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;
use v5.40;
use Const::Fast;
use Carp qw(croak);
use Test::More;
use Test::Mojo;
use JSON::MaybeXS qw(encode_json);
use lib 'lib';
use lib 't/lib';
use GPForum::Test::PgDatabase;
use GPForum::Test::ReplacedSubs qw(with_replaced_subs);
use GPForum::Infrastructure::SqlFunction;
use GPForum::Service::Admin::Configuration;

our $VERSION = '0.001';
const my $HTTP_OK => 200;

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all =>
      'set GPFORUM_TEST_DSN to check request configuration reuse';
}
my $database = GPForum::Test::PgDatabase->fresh;
local $ENV{GPFORUM_ENV}                       = 'test';
local $ENV{GPFORUM_DATABASE_DSN}              = $database->dsn;
local $ENV{GPFORUM_MINION_ENABLED}            = 0;
local $ENV{GPFORUM_REALTIME_LISTENER_ENABLED} = 0;
local $ENV{GPFORUM_WARMUP_ENABLED}            = 0;
my $dbh = $database->dbh;
my @workers;

for ( 1 .. 2 ) {
    my $test   = Test::Mojo->new('GPForum');
    my $routes = $test->app->routes;
    $routes->get('/__request-policy')->to(
        cb => sub ($c) {
            my $plugins = $c->ui_integration_plugins;
            $c->render(
                json => {
                    site_name => $c->gp_config->site_name,
                    base_name => $c->gp_base_config->site_name,
                    frames    => $plugins->frame_origins,
                    variant   => $plugins->cache_variant,
                    available => $c->gp_configuration->state->{available},
                }
            );
        }
    );
    push @workers, $test;
}
my $read  = GPForum::Infrastructure::SqlFunction->can('rows');
my $build = GPForum::Service::Admin::Configuration->can('_effective_config');
my ( $reads, $builds ) = ( 0, 0 );
with_replaced_subs(
    'GPForum::Infrastructure::SqlFunction',
    {
        rows => sub {
            if ( $_[1] eq 'admin_configuration_state' ) { ++$reads; }
            return $read->(@_);
        },
    },
    sub {
        with_replaced_subs(
            'GPForum::Service::Admin::Configuration',
            {
                _effective_config => sub { ++$builds; return $build->(@_); },
            },
            sub {
                save_state( 'First forum', 1, 'embed' );
                for my $worker (@workers) {
                    policy($worker);
                    $worker->json_is( '/site_name', 'First forum' );
                    ok( has_spotify($worker),
                        'the selected player has a declared origin' );
                    policy($worker);
                }
                is( $builds, 2, 'each worker validates this revision once' );
                is( $reads, 2 + 2,
                    'even cache hits read durable state on every request' );
                my $old_variant = $workers[0]->tx->res->json->{variant};
                save_state( 'Changed forum', 1, 'link' );
                for my $worker (@workers) {
                    policy($worker);
                    $worker->json_is( '/site_name', 'Changed forum' );
                    ok( !has_spotify($worker),
                        'link-only mode removes permission on the next request'
                    );
                    isnt( policy_json($worker)->{variant}, $old_variant,
'both workers change the body-cache variant without waiting for a notification'
                    );
                }
                save_state( 'Changed forum', 0, 'embed' );
                for my $worker (@workers) {
                    policy($worker);
                    ok( !has_spotify($worker),
                        'a disabled player stays absent' );
                }
                with_replaced_subs(
                    'GPForum::Infrastructure::SqlFunction',
                    {
                        rows => sub {
                            croak 'fixture configuration read failed'
                              if $_[1] eq 'admin_configuration_state';
                            return $read->(@_);
                        },
                    },
                    sub {
                        for my $worker (@workers) {
                            policy($worker);
                            my $response = $worker->tx->res->json;
                            is( $response->{site_name}, $response->{base_name},
'an unavailable database does not serve a cached override'
                            );
                            is_deeply( $response->{frames}, [],
'unavailable policy fails closed for all players'
                            );
                            ok(
                                !$response->{available},
                                'failure remains explicit'
                            );
                        }
                    }
                );
                my $before_recovery = $builds;
                for my $worker (@workers) {
                    policy($worker);
                    $worker->json_is( '/site_name', 'Changed forum' );
                }
                is(
                    $builds,
                    $before_recovery + 2,
'recovery at the same revision rebuilds instead of retaining pre-failure objects'
                );
            }
        );
    }
);

done_testing();

sub save_state ( $title, $enabled, $mode ) {
    $dbh->do(
q{UPDATE public.forum_configuration SET settings=?::jsonb, revision=revision+1},
        undef,
        encode_json(
            {
                general => { GPFORUM_SITE_NAME => $title },
                plugins => {
                    spotify => { enabled => $enabled ? \1 : \0, mode => $mode }
                }
            }
        )
    );
    return;
}

sub policy ($test) {
    $test->get_ok('/__request-policy')->status_is($HTTP_OK);
    return;
}

sub policy_json ($test) {
    return $test->tx->res->json;
}

sub has_spotify ($test) {
    return
      scalar grep { $_ eq 'https://open.spotify.com' }
      @{ policy_json($test)->{frames} };
}

1;
