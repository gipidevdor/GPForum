# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause
package main;
use v5.40;
use DBI;
use Const::Fast;
use Carp          qw(carp croak);
use English       qw(-no_match_vars);
use File::Temp    qw(tempdir);
use JSON::MaybeXS qw(encode_json);
use Test::More;
use Test::Exception;
use Time::HiRes qw(sleep);
use lib 'lib', 't/lib';
use GPForum::Config;
use GPForum::Schema;
use GPForum::Command::PostgresPerformance;
use GPForum::Infrastructure::PostgresPerformance;
our $VERSION = '0.001';

const my $RAM_MB          => 16_384;
const my $CORES           => 8;
const my $RELOAD_ATTEMPTS => 30;
const my $RELOAD_INTERVAL => 0.05;
if ( ( $ENV{GPFORUM_POSTGRES_CONTROLLED_TEST} // q{} ) ne '1'
    || !$ENV{GPFORUM_DATABASE_DSN} )
{
    plan skip_all =>
'requires an explicitly disposable cluster: GPFORUM_POSTGRES_CONTROLLED_TEST=1';
}

my $dsn = $ENV{GPFORUM_DATABASE_DSN};
my $dbh = DBI->connect(
    $dsn,
    $ENV{GPFORUM_DATABASE_USER},
    $ENV{GPFORUM_DATABASE_PASSWORD},
    { RaiseError => 1, PrintError => 0, AutoCommit => 1 }
);
my $config = GPForum::Config->new(
    database_dsn       => $dsn,
    database_user      => $ENV{GPFORUM_DATABASE_USER},
    database_password  => $ENV{GPFORUM_DATABASE_PASSWORD} // q{},
    postgres_profile   => 'dedicated',
    postgres_topology  => 'remote',
    postgres_memory_mb => $RAM_MB,
    postgres_cpu_count => $CORES,
    postgres_storage   => 'ssd',
    web_processes      => 2
);
my $service = GPForum::Infrastructure::PostgresPerformance->new(
    config => $config,
    dbh    => $dbh
);
my $directory = tempdir( CLEANUP => 1 );
my $initial   = $service->plan;
my $instance  = $initial->{identity}{system_identifier};

if ( !$instance ) {
    plan skip_all => 'test requires superuser on the disposable cluster';
}
my $authorization = { instance => $instance, controlled => 1 };
my $rollback;
my $role = "gpf_tuning_$PROCESS_ID";

END {
    if ($rollback) {
        eval {
            $service->restore( $rollback,
                { %{$authorization}, journal => "$directory/emergency.jsonl" }
            );
            1;
        } or carp $EVAL_ERROR;
    }
    if ( $dbh && defined $role ) {
        $dbh->do( 'DROP ROLE IF EXISTS ' . $dbh->quote_identifier($role) );
    }
}

is( $initial->{settings}{work_mem}{source},
    'default', 'temporary server starts from original settings' );
ok( exists $initial->{settings}{shared_buffers}{pending_restart},
    'pending_restart is collected' );
my $bad = {
    %{$authorization},
    instance => 'wrong',
    journal  => "$directory/wrong.jsonl",
    allow    => ['work_mem']
};
throws_ok { $service->apply( $initial, $bad ) } qr/system_identifier/msx,
  'wrong instance refused';
my $other_endpoint =
  { %{$initial}, identity => { %{ $initial->{identity} }, port => '1' } };
throws_ok {
    $service->apply(
        $other_endpoint,
        {
            %{$authorization},
            journal => "$directory/endpoint.jsonl",
            allow   => ['work_mem']
        }
    )
}
qr/endpoint/msx, 'same cluster identifier at an unreviewed endpoint is refused';
throws_ok {
    $service->apply(
        $initial,
        {
            %{$authorization},
            journal => "$directory/unsafe.jsonl",
            allow   => ['fsync']
        }
    )
}
qr/allowlist/msx, 'durability cannot be altered';

# A crash after ALTER SYSTEM, before reload: restore must not depend on the
# server having processed SIGHUP or already set pending_restart.
my $write_journal =
  GPForum::Infrastructure::PostgresPerformance->can('_record');
{
    no warnings 'redefine';                                           ## no critic (TestingAndDebugging::ProhibitNoWarnings) -- scoped interruption injection around the journal writer
    local *GPForum::Infrastructure::PostgresPerformance::_record =    ## no critic (Variables::ProtectPrivateVars, NamingConventions::ProhibitAmbiguousNames) -- interrupt the existing private journal writer
      sub ( $fh, $journal ) {
        $write_journal->( $fh, $journal );
        croak 'simulated interruption before reload'
          if @{ $journal->{entries} }
          && $journal->{entries}[-1]{state} eq 'written';
        return;
      };
    throws_ok {
        $service->apply(
            $initial,
            {
                %{$authorization},
                journal => "$directory/interrupted.jsonl",
                allow   => ['shared_buffers']
            }
        )
    }
    qr/simulated/msx, 'interruption after write is reported before reload';
}
my $interrupted = GPForum::Command::PostgresPerformance::_read(    ## no critic (Subroutines::ProtectPrivateSubs) -- recover the actual interrupted run
    "$directory/interrupted.jsonl", 1
);
$rollback = $interrupted;
ok(
    !$service->settings->{shared_buffers}{pending_restart},
    'restart flag is not required to recover a pre-reload write'
);
is(
    $service->restore(
        $interrupted,
        {
            %{$authorization},
            journal => "$directory/interrupted-restore.jsonl"
        }
    )->{written},
    1,
    'pre-reload postmaster change is restored safely'
);
is_deeply( $service->plan->{overrides},
    $initial->{overrides},
    'interrupted restore preserves the original override state' );
$rollback = undef;

$dbh->do(q{SET work_mem = '6MB'});
my $session_plan = $service->plan;
throws_ok {
    $service->apply(
        $session_plan,
        {
            %{$authorization},
            journal => "$directory/session.jsonl",
            allow   => ['work_mem']
        }
    )
}
qr/globally/msx, 'session overrides cannot be silently overridden globally';
$dbh->do('RESET work_mem');

my $written = $service->apply(
    $initial,
    {
        %{$authorization},
        journal => "$directory/apply.jsonl",
        allow   => [qw(work_mem shared_buffers)]
    }
);
is( $written->{written}, 2, 'only explicitly allowed settings are written' );
$rollback =
  GPForum::Command::PostgresPerformance::_read( "$directory/apply.jsonl", 1 ); ## no critic (Subroutines::ProtectPrivateSubs) -- inspect the crash-recovery journal reader
is( scalar @{ $rollback->{entries} },
    2, 'journal records every previous override' );
is( ( stat "$directory/apply.jsonl" )[2] & oct('777'),
    oct('600'), 'journal is private to its owner' );
open my $truncated, '>', "$directory/truncated.jsonl"
  or croak 'cannot create journal fixture';
print {$truncated} encode_json($rollback), "\n", '{"interrupted":'
  or croak 'cannot write journal fixture';
close $truncated or croak 'cannot close journal fixture';
is_deeply(
    GPForum::Command::PostgresPerformance::_read(    ## no critic (Subroutines::ProtectPrivateSubs) -- verify crash recovery after an incomplete record
        "$directory/truncated.jsonl", 1
    ),
    $rollback,
    'interrupted final record preserves the last complete recovery snapshot'
);

is(
    $service->apply(
        $initial,
        {
            %{$authorization},
            journal => "$directory/reapply.jsonl",
            allow   => [qw(work_mem shared_buffers)]
        }
    )->{written},
    0,
    'reapply is idempotent while restart is pending'
);
my $fresh;

for ( 1 .. $RELOAD_ATTEMPTS ) {
    sleep $RELOAD_INTERVAL;
    $fresh = DBI->connect(
        $dsn,
        $ENV{GPFORUM_DATABASE_USER},
        $ENV{GPFORUM_DATABASE_PASSWORD},
        { RaiseError => 1, PrintError => 0, AutoCommit => 1 }
    );
    my $pending = $fresh->selectrow_array(
        q{SELECT pending_restart FROM pg_settings WHERE name = 'shared_buffers'}
    );
    last if $pending;
    $fresh->disconnect;
}
my $report = GPForum::Infrastructure::PostgresPerformance->new(
    config => $config,
    dbh    => $fresh
)->inspect;
is( $fresh->selectrow_array('SHOW work_mem'),
    '8MB', 'reloadable value is effective on a new connection' );
ok(
    $report->{settings}{shared_buffers}{pending_restart},
    'restart change stays pending; no automatic restart'
);
is(
    $report->{settings}{shared_buffers}{setting},
    $initial->{settings}{shared_buffers}{setting},
    'active shared memory is unchanged before restart'
);
$fresh->disconnect;
$config->postgres_strict(1);
my $strict = GPForum::Schema->connect_from_config($config);
throws_ok { $strict->storage->dbh } qr/PostgreSQL[ ]performance/msx,
  'actual schema connection enforces strict';
$strict->storage->disconnect;
$config->postgres_strict(0);

$dbh->do( 'CREATE ROLE '
      . $dbh->quote_identifier($role)
      . ' LOGIN PASSWORD '
      . $dbh->quote( $ENV{GPFORUM_DATABASE_PASSWORD} // q{} ) );
my $plain = DBI->connect(
    $dsn, $role,
    $ENV{GPFORUM_DATABASE_PASSWORD},
    { RaiseError => 1, PrintError => 0, AutoCommit => 1 }
);
my $restricted = GPForum::Infrastructure::PostgresPerformance->new(
    config => $config,
    dbh    => $plain
);
ok( $restricted->inspect->{available},
    'ordinary role can inspect pg_settings' );
throws_ok {
    $restricted->apply( $initial, { %{$authorization}, allow => ['work_mem'] } )
}
qr/superuser/msx, 'ordinary role cannot apply';
$plain->disconnect;

my $restored = $service->restore( $rollback,
    { %{$authorization}, journal => "$directory/restore.jsonl" } );
is( $restored->{written}, 2,
    'rollback restores both previous auto.conf entries' );
is_deeply( $service->plan->{overrides},
    $initial->{overrides},
    'rollback preserves absence of overrides, not just current values' );
is(
    $service->restore( $rollback,
        { %{$authorization}, journal => "$directory/restore-again.jsonl" } )
      ->{written},
    0,
    'rollback is idempotent'
);
$rollback = undef;
$dbh->do( 'DROP ROLE ' . $dbh->quote_identifier($role) );
$dbh->disconnect;
$dbh = undef;
done_testing;
1;
