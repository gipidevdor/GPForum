# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;
use Carp       qw(croak);
use English    qw(-no_match_vars);
use Mojo::File qw(path);
use Test::More;

use lib 'lib';
use lib 't/lib';
use GPForum::Test::PgDatabase;
use GPForum::Service::Operations::StagingDrill::PgTools;

our $VERSION = '0.001';

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'set GPFORUM_TEST_DSN to check schema snapshots';
}
my $database  = GPForum::Test::PgDatabase->fresh;
my $admin     = $database->dbh;
my ($version) = $admin->selectrow_array('SHOW server_version');
if ( index( $version, '18.' ) != 0 ) {
    plan skip_all => 'the canonical schema snapshot uses PostgreSQL 18';
}
my $parts = GPForum::Service::Operations::StagingDrill::PgTools->parse_dsn(
    $database->dsn );
local $ENV{PGHOST}     = $parts->{host};
local $ENV{PGPORT}     = $parts->{port};
local $ENV{PGUSER}     = $parts->{user};
local $ENV{PGPASSWORD} = $parts->{password} // q{};
my $snapshot = 'etc/schema/postgresql-18.sql';
my ( $first, $status ) = _dump();
is( $status, 0, 'the real pg_dump succeeded' );
ok( $first eq path($snapshot)->slurp,
    'the migrated schema matches the committed SQL' );
my ( $repeated, $repeated_status ) = _dump();
is( $repeated_status, 0, 'a second dump succeeded' );
is( $repeated, $first,
    'random psql restriction keys and owner names do not cause drift' );
my ( $checked, $check_status ) = _dump( '--check', $snapshot );
is( $check_status, 0, 'check mode accepts the committed schema' );
ok( !length $checked, 'a passing check emits no SQL' );

$admin->do('CREATE TABLE public.snapshot_drift (id integer)');
my ( $changed, $changed_status ) = _dump( '--check', $snapshot );
isnt( $changed_status, 0, 'an unrecorded schema change fails the gate' );
like(
    $changed,
    qr/CREATE[ ]TABLE[ ]public[.]snapshot_drift/msx,
    'a failed check emits the actual SQL for review'
);
done_testing();

sub _dump (@options) {
    open my $handle, q{-|}, $EXECUTABLE_NAME, 'script/schema-snapshot',
      @options, $database->name
      or croak "cannot run schema-snapshot: $OS_ERROR";
    my $output = do { local $INPUT_RECORD_SEPARATOR = undef; <$handle> };
    my $ok     = close $handle;
    return ( $output, $ok ? 0 : $CHILD_ERROR );
}

1;
