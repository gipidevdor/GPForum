# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;
use v5.40;
use DBI;
use DBD::Pg qw(PG_ASYNC);
use Const::Fast;
use English qw(-no_match_vars);
use JSON::PP;
use Test::More;
use Test::Exception;
use Time::HiRes qw(sleep);
use lib 't/lib';
use lib 'script/lib';
use lib 'lib';
use GPForum::Test::PgDatabase;
use GPForum::Test::PostgresHarness;
use GPForum::Infrastructure::Id;
use GPForum::PostgreSQL::Diagnostics    qw(collect);
use GPForum::PostgreSQL::DiagnosticsCLI qw(validate_evidence);

our $VERSION = '0.001';
const my $LOCK_POLLS     => 50;
const my $LOCK_INTERVAL  => 0.01;
const my $PRIVATE_MARKER => 'GPForum-private-diagnostic-fixture-body';
const my $OBSERVATIONS   => 3;

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all =>
      'set GPFORUM_TEST_DSN for real read-only PostgreSQL diagnostics';
}
my $database = GPForum::Test::PgDatabase->fresh( seed => 1 );
my $dbh      = $database->dbh;
my $role     = 'gpf_diagnostics_' . $PROCESS_ID;
my ( $reader, $waiter, $observer );

END {
    if ($waiter)   { $waiter->disconnect; }
    if ($observer) { $observer->disconnect; }
    if ($reader)   { $reader->disconnect; }
    if ( $dbh && $dbh->{Active} ) {
        $dbh->do( 'DROP ROLE IF EXISTS ' . $dbh->quote_identifier($role) );
    }
}

my $missing = collect($dbh);
is( $missing->{status}, 'degraded',
    'missing optional extension does not disable the remaining diagnostics' );
is( $missing->{sections}{statements}{status},
    'unavailable', 'extension absence is explicitly unmeasured' );
is( $missing->{sections}{database}{status},
    'ok', 'database statistics were really inspected' );
lives_ok { validate_evidence($missing) } 'partial evidence validates';
ok( $dbh->{AutoCommit},
    'collector restores the dedicated connection to AutoCommit' );
my ($read_only) = $dbh->selectrow_array('SHOW transaction_read_only');
is( $read_only, 'off', 'read-only transaction setting is rolled back' );
my ($functions_before) = $dbh->selectrow_array(
    q{SELECT count(*) FROM pg_proc WHERE pronamespace = 'api'::regnamespace});

my ($preload) = $dbh->selectrow_array('SHOW shared_preload_libraries');
if ( $preload =~ /pg_stat_statements/msx ) {
    $dbh->do('CREATE EXTENSION pg_stat_statements');
    for ( 1 .. $OBSERVATIONS ) {
        $dbh->selectrow_array( q{SELECT pg_sleep(0.01), ?::text},
            undef, $PRIVATE_MARKER );
    }
    my $report = collect($dbh);
    is( $report->{sections}{statements}{status},
        'ok', 'preloaded extension yields real cumulative observations' );
    ok(
        @{ $report->{sections}{statements}{rows} },
        'executed statements exist in the evidence'
    );
    lives_ok { validate_evidence($report) }
    'all observed metrics validate their public schema';
    unlike(
        JSON::PP->new->encode($report),
        qr/GPForum-private-diagnostic-fixture-body|Query [ ] Text/msx,
'even a statement containing a private value has no public text or binds'
    );
    my $rows  = $report->{sections}{statements}{rows};
    my @costs = map { $_->{total_execution_ms} } @{$rows};
    is_deeply(
        \@costs,
        [ reverse sort { $a <=> $b } @costs ],
        'queries rank by cumulative execution cost'
    );
    $dbh->do('SET pg_stat_statements.track_planning = off');
    my $unplanned = collect($dbh);
    ok(
        !grep( { $_->{planning_measured} }
            @{ $unplanned->{sections}{statements}{rows} } ),
        'disabled planning instrumentation is explicitly unmeasured'
    );
    ok(
        !grep( { defined $_->{total_planning_ms} }
            @{ $unplanned->{sections}{statements}{rows} } ),
        'disabled planning time is null rather than a fabricated zero'
    );
    $dbh->do('RESET pg_stat_statements.track_planning');
    my $reenabled     = collect($dbh);
    my @without_plans = grep { defined $_->{plans} && $_->{plans} == 0 }
      @{ $reenabled->{sections}{statements}{rows} };
    ok( @without_plans, 'utility statements have no observed planning calls' );
    ok(
        !grep( { $_->{planning_measured} || defined $_->{total_planning_ms} }
            @without_plans ),
        'enabled planning without observations remains explicitly unmeasured'
    );
    $dbh->do('DROP EXTENSION pg_stat_statements');
}
else {
    note
'pg_stat_statements collection not executed: this server has no preload; the matrix enables it on disposable services';
}

# Three independent connections reproduce an actual row wait. The observer
# must report contention without reading the blocked statement or its values.
$dbh->do('CREATE TABLE diagnostics_lock_fixture (id integer PRIMARY KEY)');
$dbh->do('INSERT INTO diagnostics_lock_fixture VALUES (1)');
$waiter   = GPForum::Test::PostgresHarness::connect_dbi( $database->dsn );
$observer = GPForum::Test::PostgresHarness::connect_dbi( $database->dsn );
$waiter->do(q{SET statement_timeout = '3s'});
$dbh->begin_work;
$dbh->selectrow_array('SELECT id FROM diagnostics_lock_fixture FOR UPDATE');
$waiter->do( 'SELECT id FROM diagnostics_lock_fixture FOR UPDATE',
    { pg_async => PG_ASYNC } );
my $blocked;

for ( 1 .. $LOCK_POLLS ) {
    $blocked = collect($observer)->{sections}{activity}{rows}[0];
    last if $blocked->{blocked};
    sleep $LOCK_INTERVAL;
}
$dbh->rollback;
$waiter->pg_result;
cmp_ok( $blocked->{blocked}, '>=', 1,
    'independent row waiter is really observed' );
cmp_ok( $blocked->{lock_waiters},
    '>=', 1, 'real PostgreSQL lock wait is counted' );
cmp_ok( $blocked->{idle_in_transaction},
    '>=', 1, 'holder transaction is observed' );
$waiter->disconnect;
$observer->disconnect;
$waiter   = undef;
$observer = undef;

my $reader_password = GPForum::Infrastructure::Id->new->uuid;
$dbh->do( 'CREATE ROLE '
      . $dbh->quote_identifier($role)
      . ' LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS PASSWORD '
      . $dbh->quote($reader_password) );
$reader = DBI->connect( $database->dsn, $role, $reader_password,
    { AutoCommit => 1, RaiseError => 1, PrintError => 0 } );
my $limited = collect($reader);
is( $limited->{status}, 'degraded',
    'limited observer remains usable without new runtime grants' );
ok(
    !$limited->{environment}{all_statistics_visible},
    'restricted statistics visibility is recorded'
);
lives_ok { validate_evidence($limited) }
'restricted observer evidence validates';
throws_ok { $reader->selectall_arrayref('SELECT * FROM users') }
qr/permission [ ] denied/msx,
  'diagnostics did not grant direct access to forum data';
$reader->begin_work;
throws_ok { collect($reader) } qr/dedicated [ ] AutoCommit/msx,
  'collector cannot roll back a caller-owned transaction';
$reader->rollback;
my ($functions_after) = $dbh->selectrow_array(
    q{SELECT count(*) FROM pg_proc WHERE pronamespace = 'api'::regnamespace});
is( $functions_after, $functions_before, 'application SQL API is unchanged' );
done_testing;
1;
