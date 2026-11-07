# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use Mojo::Server::Hypnotoad;
use Mojolicious;
use Test::More;
use Test::Mojo;

use lib 'lib';
use lib 't/lib';

use GPForum::Config;
use GPForum::OS::Base;
use GPForum::OS::Linux;
use GPForum::OS::RuntimePolicy;
use GPForum::Runtime;
use GPForum::Service::Operations::MetricsSnapshot;
use GPForum::Service::Operations::Readiness;
use GPForum::Test::OSResourceSnapshot;
use GPForum::Test::OSTinyLinux;
use GPForum::Test::OperationsClock;
use GPForum::Test::ReadinessSchema;

our $VERSION = '0.001';

const my $WEB_PROCESSES           => 6;
const my $EXPECTED_WEB_CAP        => 2;
const my $LOW_BACKLOG             => 16;
const my $CONFIGURED_BACKLOG      => 256;
const my $CONFIGURED_CLIENTS      => 75;
const my $CONFIGURED_REQUESTS     => 120;
const my $WORKER_CONNECTION_LIMIT => 10_000;

my $resource = GPForum::Test::OSResourceSnapshot->new;
my $config   = GPForum::Config->new(
    web_processes           => $WEB_PROCESSES,
    runtime_listen          => 'http://*:9000',
    runtime_backlog         => $CONFIGURED_BACKLOG,
    runtime_clients         => $CONFIGURED_CLIENTS,
    runtime_requests        => $CONFIGURED_REQUESTS,
    runtime_worker_policy   => 'cap-to-cpu',
    os_reuseport            => 'auto',
    runtime_max_web_per_cpu => 2,
);
$config->validate;

my $runtime = GPForum::Runtime->new(
    web_processes => $WEB_PROCESSES,
    os_profile    => GPForum::Test::OSTinyLinux->new(
        resource_probe => $resource,
    ),
    os_feature_settings => $config->os_feature_settings,
);
my $policy = GPForum::OS::RuntimePolicy->new(
    config  => $config,
    runtime => $runtime,
);
my $hypnotoad = $policy->hypnotoad_config;

is( $hypnotoad->{workers},
    $EXPECTED_WEB_CAP, 'runtime policy caps workers to CPU policy' );
is_deeply(
    $hypnotoad->{trusted_proxies},
    [ '127.0.0.1', '::1' ],
    'X-Forwarded-For is believed from the loopback only, by default'
);
is(
    $hypnotoad->{listen}[0],
    'http://*:9000?single_accept=1&reuse=1',
    'TCP acceptance is fair while retaining reuseport'
);
is( $hypnotoad->{backlog},
    $CONFIGURED_BACKLOG, 'runtime policy applies configured backlog' );
is( $hypnotoad->{clients},
    $CONFIGURED_CLIENTS, 'runtime policy applies configured client budget' );
is( $hypnotoad->{requests},
    $CONFIGURED_REQUESTS, 'runtime policy applies keep-alive request budget' );
is( $hypnotoad->{accepts}, $WORKER_CONNECTION_LIMIT,
    'worker recycling is always active without a setting' );
is( $policy->report->{status},
    'degraded', 'worker capping is reported as degraded posture' );
ok(
    exists $policy->report->{backlog}{saturation},
    'runtime policy reports backlog saturation availability'
);

my $configured_policy = GPForum::OS::RuntimePolicy->new(
    config => GPForum::Config->new(
        web_processes         => $WEB_PROCESSES,
        runtime_worker_policy => 'configured',
        runtime_listen        => 'http://*:9000',
    ),
    runtime => $runtime,
);
is( $configured_policy->hypnotoad_config->{workers},
    $WEB_PROCESSES, 'configured worker policy preserves requested workers' );
is( $configured_policy->hypnotoad_config->{accepts},
    $WORKER_CONNECTION_LIMIT,
    'an explicit worker count also retains automatic recycling' );
my $server = Mojo::Server::Hypnotoad->new;
$server->prefork->app( Mojolicious->new );
$server->prefork->app->config(
    hypnotoad => $configured_policy->hypnotoad_config );
$server->configure('hypnotoad');
is( $server->prefork->accepts,
    $WORKER_CONNECTION_LIMIT,
    'Hypnotoad receives the built-in recycling limit' );
is(
    $server->prefork->max_requests,
    $configured_policy->config->runtime_requests,
    'recycling leaves the keep-alive request limit independent'
);

my $unknown_config = GPForum::Config->new(
    runtime_listen => 'http://*:9000',
    os_reuseport   => 'on',
);
my $unknown_runtime = GPForum::Runtime->new(
    os_profile => GPForum::OS::Base->new( resource_probe => $resource ),
    os_feature_settings => $unknown_config->os_feature_settings,
);
my $unknown_policy = GPForum::OS::RuntimePolicy->new(
    config  => $unknown_config,
    runtime => $unknown_runtime,
);
is(
    $unknown_policy->hypnotoad_config->{listen}[0],
    'http://*:9000?single_accept=1',
    'fair acceptance does not require reuseport support'
);
is( $unknown_policy->report->{status},
    'degraded', 'unsupported requested runtime feature degrades policy' );

for my $case (
    [
        'http://*:9000?single_accept=0',
        'http://*:9000?single_accept=0&reuse=1'
    ],
    [ 'http://*:9000?reuse=0', 'http://*:9000?reuse=0&single_accept=1' ],
    [ 'http://*:9000?fd=3',    'http://*:9000?fd=3&single_accept=1' ],
    [
        'http+unix://var%2Frun%2Fgpforum.sock',
        'http+unix://var%2Frun%2Fgpforum.sock?single_accept=1'
    ],
    [
        'http+unix://var%2Frun%2Fgpforum.sock?single_accept=0',
        'http+unix://var%2Frun%2Fgpforum.sock?single_accept=0'
    ],
  )
{
    my $listener_policy = GPForum::OS::RuntimePolicy->new(
        config  => GPForum::Config->new( runtime_listen => $case->[0] ),
        runtime => $runtime,
    );
    is( $listener_policy->hypnotoad_config->{listen}[0],
        $case->[1], 'acceptance preserves explicit socket options' );
}

my $low_backlog_policy = GPForum::OS::RuntimePolicy->new(
    config => GPForum::Config->new(
        runtime_listen  => 'http://*:9000',
        runtime_backlog => $LOW_BACKLOG,
    ),
    runtime => GPForum::Runtime->new(
        os_profile => GPForum::OS::Linux->new( resource_probe => $resource ),
        os_feature_settings => _default_features(),
    ),
);
ok( _has_check_status( $low_backlog_policy->report, 'backlog', 'degraded' ),
    'low backlog creates runtime enforcement warning' );

my $metrics = GPForum::Service::Operations::MetricsSnapshot->new(
    clock          => GPForum::Test::OperationsClock->new,
    runtime        => $runtime,
    runtime_policy => $policy,
)->collect;
is( $metrics->{runtime_enforcement}{hypnotoad}{workers},
    $EXPECTED_WEB_CAP, 'metrics expose effective runtime worker count' );

my $ready = GPForum::Service::Operations::Readiness->new(
    environment    => 'test',
    runtime        => $runtime,
    runtime_policy => $policy,
    schema         => GPForum::Test::ReadinessSchema->new,
)->check;
is( $ready->{status},
    'degraded', 'readiness reports degraded runtime enforcement posture' );

my $test = Test::Mojo->new('GPForum');
ok( exists $test->app->config->{hypnotoad},
    'application startup installs Hypnotoad runtime config' );
is( $test->app->config->{hypnotoad}{accepts}, $WORKER_CONNECTION_LIMIT,
    'an application started out of the box automatically recycles its workers'
);
ok(
    exists $test->app->config->{gpforum_runtime_enforcement},
    'application startup exposes runtime enforcement report'
);

subtest 'large native admission keeps explicit listener choices' => sub {
    my $large_config = GPForum::Config->new(
        runtime_clients => $WORKER_CONNECTION_LIMIT / 2,
        runtime_listen  =>
'http://*:9000,http://*:9001?single_accept=1,https://*:9443,http+unix://%2Ftmp%2Fgp.sock',
    );
    my $large_policy = GPForum::OS::RuntimePolicy->new(
        config  => $large_config,
        runtime => $runtime,
    );
    my $listeners = $large_policy->hypnotoad_config->{listen};
    like( $listeners->[0], qr/single_accept=0/msx,
        'large TCP budgets use batches' );
    like( $listeners->[1], qr/single_accept=1/msx,
        'explicit native admission is preserved' );
    like( $listeners->[2], qr/single_accept=1/msx,
        'TLS retains native handshake admission' );
    like( $listeners->[-1], qr/single_accept=0/msx,
        'large UNIX budgets also use batches' );
};

done_testing();

sub _default_features {
    return { reuseport => 'auto' };
}

sub _has_check_status {
    my ( $report, $name, $status ) = @_;

    for my $check ( @{ $report->{checks} } ) {
        return 1
          if $check->{name} eq $name && $check->{status} eq $status;
    }

    return 0;
}

1;
