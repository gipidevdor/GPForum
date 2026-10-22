# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use English    qw(-no_match_vars);
use File::Temp qw(tempdir);
use Mojo::File qw(path);
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Migration::Plan;
use GPForum::Migration::Runner;
use GPForum::Test::PgDatabase;

our $VERSION = '0.001';

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'set GPFORUM_TEST_DSN to run against PostgreSQL';
}

# A migration committed itself and the schema_versions row came after, in a
# statement of its own: a crash, a lost connection or a failed insert in
# between left the migration applied and unrecorded, and the next deploy ran
# it again -- CREATE TABLE twice, here. Now the row is written inside the
# migration's transaction, so the two commit together or not at all.

my $database = GPForum::Test::PgDatabase->fresh;
my $schema   = $database->schema;
my $dbh      = $schema->storage->dbh;
$dbh->do(<<'SQL');
CREATE FUNCTION pg_temp.refuse_9000() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.version = '9000' THEN
        RAISE EXCEPTION 'the record of 9000 is lost';
    END IF;
    RETURN NEW;
END
$$;
CREATE TRIGGER refuse_9000 BEFORE INSERT ON schema_versions
    FOR EACH ROW EXECUTE FUNCTION pg_temp.refuse_9000();
SQL

my $directory = path( tempdir( CLEANUP => 1 ) );
for my $name ( @{ GPForum::Migration::Plan->new->files } ) {
    path($name)->copy_to( $directory->child( path($name)->basename ) );
}
$directory->child('9000_test_atomic.sql')
  ->spew("BEGIN;\nCREATE TABLE test_atomic (a integer);\nCOMMIT;\n");
my $runner = GPForum::Migration::Runner->new(
    applied_by => 'test',
    plan       => GPForum::Migration::Plan->new( directory => "$directory" ),
    schema     => $schema,
);

my $failed = !eval { $runner->apply_pending; 1 };
ok( $failed, 'a migration whose record fails fails' );
is( _count(q{SELECT count(*) FROM pg_class WHERE relname = 'test_atomic'}),
    0, 'and leaves nothing applied' );
is( _count(q{SELECT count(*) FROM schema_versions WHERE version = '9000'}),
    0, 'nor recorded' );
is(
    _count(
            q{SELECT count(*) FROM pg_locks WHERE locktype = 'advisory'}
          . q{ AND pid = pg_backend_pid()}
    ),
    0,
    'and lets go of the migration lock'
);

$dbh->do('DROP TRIGGER refuse_9000 ON schema_versions');
my $applied = eval { $runner->apply_pending } // [];
is_deeply( [ map { $_->{version} } @{$applied} ],
    ['9000'], 'so the next run applies it once' )
  or diag $EVAL_ERROR;
is( _count(q{SELECT count(*) FROM schema_versions WHERE version = '9000'}),
    1, 'and records it' );
is(
    _count(
            q{SELECT count(*) FROM schema_versions}
          . q{ WHERE version = '9000' AND applied_by = 'test'}
          . q{ AND execution_ms >= 0}
    ),
    1,
    'with who applied it and how long it took'
);

$schema->storage->disconnect;

done_testing();

sub _count ($sql) {
    return scalar $schema->storage->dbh->selectrow_array($sql);
}

1;
