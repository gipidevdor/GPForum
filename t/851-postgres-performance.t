# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause
package main;
use v5.40;
use Test::More;
use Const::Fast;
use Test::Exception;
use lib 'lib', 't/lib';
use GPForum::Config;
use GPForum::Infrastructure::PostgresProfile;
use GPForum::Infrastructure::PostgresPerformance;
use GPForum::Test::PostgresSettingsDbh;
our $VERSION = '0.001';

const my $RAM_MB              => 16_384;
const my $CORES               => 8;
const my $WORKERS             => 4;
const my $MAX_CONNECTIONS     => 100;
const my $BLOCKS_4GB          => 524_288;
const my $KIB_8MB             => 8_192;
const my $TOO_FEW_CONNECTIONS => 5;
const my $EXCESSIVE_RESERVE   => 15_000;

my $config = GPForum::Config->new(
    postgres_profile   => 'dedicated',
    postgres_topology  => 'remote',
    postgres_memory_mb => $RAM_MB,
    postgres_cpu_count => $CORES,
    postgres_storage   => 'nvme',
    web_processes      => $WORKERS
);
my $profile = GPForum::Infrastructure::PostgresProfile->new( config => $config )
  ->recommendation;
is_deeply(
    $profile->{settings},
    {
        shared_buffers           => '4096MB',
        effective_cache_size     => '12288MB',
        work_mem                 => '8MB',
        maintenance_work_mem     => '512MB',
        random_page_cost         => '1.1',
        effective_io_concurrency => '100',
        jit                      => 'off',
        max_connections          => '100',
        track_io_timing          => 'on',
    },
    '16 GiB dedicated profile respects RAM, cache and concurrent allocations'
);
cmp_ok( $profile->{estimated_memory_mb},
    '<=', $profile->{budget_mb}, 'estimate fits reserved budget' );

my %rows;
for my $name ( keys %{ $profile->{settings} } ) {
    my $value = $profile->{settings}{$name};
    my $unit;
    if ( $value =~ s/MB\z//msx ) { $unit = 'MB'; }
    $rows{$name} = {
        setting => $value,
        unit    => $unit,
        source  => 'configuration file',
        context => $name eq 'shared_buffers'
          || $name eq 'max_connections' ? 'postmaster' : 'user',
        pending_restart => 0
    };
}
for my $name (qw(fsync full_page_writes synchronous_commit autovacuum)) {
    $rows{$name} = {
        setting         => 'on',
        source          => 'default',
        context         => 'sighup',
        pending_restart => 0
    };
}
$rows{superuser_reserved_connections} = { setting => '3' };
my $dbh     = GPForum::Test::PostgresSettingsDbh->new( rows => \%rows );
my $service = GPForum::Infrastructure::PostgresPerformance->new(
    config => $config,
    dbh    => $dbh
);
is( $service->inspect->{status},
    'ok', 'conforming remote instance needs no administrator rights' );
ok( $service->equivalent( { setting => $BLOCKS_4GB, unit => '8kB' }, '4GB' ),
    'block units normalize' );
ok( $service->equivalent( { setting => $KIB_8MB, unit => 'kB' }, '8MB' ),
    'memory units normalize' );
ok( !$service->equivalent( { setting => $KIB_8MB, unit => '8kB' }, '8MB' ),
    'different units cannot hide drift' );

for my $commit_mode (qw(local remote_write remote_apply)) {
    $rows{synchronous_commit}{setting} = $commit_mode;
    is( $service->inspect->{status}, 'ok',
"$commit_mode preserves local WAL durability and is not a tuning failure"
    );
}
$rows{synchronous_commit}{setting} = 'on';
$rows{work_mem}{setting}           = $WORKERS;
is( $service->inspect->{status}, 'degraded', 'ordinary tuning drift warns' );
my $warning;
{
    local $SIG{__WARN__} = sub ($message) { $warning .= $message; };
    lives_ok { $service->enforce } 'non-strict permits drift';
}
like( $warning, qr/work_mem/msx, 'runtime warning names mismatched parameter' );
$config->postgres_strict(1);
throws_ok { $service->enforce } qr/PostgreSQL[ ]performance/msx,
  'strict refuses drift';
$config->postgres_strict(0);
$rows{work_mem}{setting}               = $CORES;
$rows{shared_buffers}{pending_restart} = 1;
is( $service->inspect->{changes}[0]{activation},
    'restart',
    'pending restart is explicit even when current value matches target' );
$rows{shared_buffers}{pending_restart} = 0;
$rows{fsync}{setting}                  = 'off';
is( $service->inspect->{findings}[0]{severity},
    'critical', 'unsafe durability setting is critical' );
$rows{fsync}{setting}           = 'on';
$rows{max_connections}{setting} = $TOO_FEW_CONNECTIONS;
is( $service->inspect->{status},
    'fail', 'worker connection capacity is critical' );
$rows{max_connections}{setting} = $MAX_CONNECTIONS;
delete $rows{jit};
like(
    join( q{ }, map { $_->{reason} } @{ $service->inspect->{findings} } ),
    qr/setting[ ]unavailable/msx,
    'missing parameters are detected'
);

$config->postgres_cpu_count(0);
is( $service->inspect->{status},
    'degraded',
    'unknown remote CPU is a recommendation, not insufficient memory' );
$config->postgres_cpu_count($CORES);
$config->postgres_profile('shared');
my $shared = GPForum::Infrastructure::PostgresProfile->new( config => $config )
  ->recommendation;
is( $shared->{reserve_mb}, $KIB_8MB,
    'shared host reserves half of RAM for other services' );
is( $shared->{settings}{shared_buffers},
    '2048MB', 'shared host sizes from remaining budget' );
$config->postgres_reserve_mb($EXCESSIVE_RESERVE);
my $small = GPForum::Infrastructure::PostgresProfile->new( config => $config )
  ->recommendation;
ok( !$small->{valid}, 'insufficient concurrency memory refuses a profile' );
$config->postgres_reserve_mb(0);
$config->postgres_storage('hdd');
my $hdd = GPForum::Infrastructure::PostgresProfile->new( config => $config )
  ->recommendation;
is( $hdd->{settings}{random_page_cost},
    '4', 'rotating storage keeps conservative random-page cost' );
is( $hdd->{settings}{effective_io_concurrency},
    '2', 'storage profile changes the I/O concurrency recommendation' );
$config->postgres_memory_mb(0);
my $unknown = GPForum::Infrastructure::PostgresProfile->new( config => $config )
  ->recommendation;
is( $unknown->{memory_mb}, 0, 'remote host never borrows application RAM' );
is_deeply( $unknown->{settings}, {},
    'unknown remote hardware gets no invented tuning' );
$config->postgres_topology('managed');
throws_ok {
    $service->apply( { format => 'gpforum-postgres-plan-v1' },
        { controlled => 1 } )
}
qr/provider/msx, 'managed services cannot be altered by this tool';
throws_ok { $service->apply( { format => 'gpforum-postgres-plan-v1' }, {} ) }
qr/controlled-instance/msx, 'cluster authority must be explicit';
done_testing;
1;
