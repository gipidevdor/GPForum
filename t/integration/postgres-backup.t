# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use DBI;
use English    qw(-no_match_vars);
use File::Temp qw(tempdir);
use Mojo::File qw(path);
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Config;
use GPForum::Migration::Plan;
use GPForum::Migration::Runner;
use GPForum::Schema;
use GPForum::Service::Operations::Backup;
use GPForum::Service::Operations::BackupVerifier;
use GPForum::Service::Operations::DatabaseProvisioning;
use GPForum::Service::Operations::StagingDrill::PgTools;
use GPForum::Service::I18N::CliCatalog;
use GPForum::Test::LosingRestore;

our $VERSION = '0.001';

const my $SERVER_VERSION_UNIT => 10_000;

if ( !$ENV{GPFORUM_DATABASE_DSN} ) {
    plan skip_all => 'set GPFORUM_DATABASE_DSN to run the backup on PostgreSQL';
}

# gpforum backup and restore --check on a real PostgreSQL: a migrated
# database of its own, with a row in it, is backed up with the host's
# pg_dump and tar; the check reads the dump with the host's pg_restore; and
# the dump, restored into a second database, holds the row. Both databases
# are dropped at the end.

my $source = GPForum::Service::Operations::DatabaseProvisioning->data_source(
    $ENV{GPFORUM_DATABASE_DSN} );
my $server = "host=$source->{host};port=$source->{port}";
my $admin  = DBI->connect(
    "dbi:Pg:dbname=postgres;$server",
    $ENV{GPFORUM_DATABASE_USER}     // q{},
    $ENV{GPFORUM_DATABASE_PASSWORD} // q{},
    { AutoCommit => 1, PrintError => 0, RaiseError => 1 }
);

my $tools;
try {
    $tools = GPForum::Service::Operations::StagingDrill::PgTools->find;
}
catch ($error) {
    plan skip_all => "no PostgreSQL client tools: $error";
};
my $major = int(
    $admin->selectrow_array('SHOW server_version_num') / $SERVER_VERSION_UNIT );
my ($client) = $tools->version_of('pg_dump') =~ /\A (\d+)/msx;
if ( $client < $major ) {
    plan skip_all => "pg_dump $client cannot dump a PostgreSQL $major server";
}

my $name     = "gpforum_t_backup_$PROCESS_ID";
my $restored = "${name}_restored";
my $scratch  = path( tempdir( CLEANUP => 1 ) );
my $uploads  = $scratch->child('uploads')->make_path;
my $nested   = $uploads->child('ab/cd')->make_path;
$nested->child('blob')->spew('an attachment');

for my $database ( $name, $restored ) {
    $admin->do("CREATE DATABASE $database");
}

try {
    local $ENV{GPFORUM_DATABASE_DSN}    = "dbi:Pg:dbname=$name;$server";
    local $ENV{GPFORUM_ATTACHMENT_ROOT} = "$uploads";
    local $ENV{GPFORUM_ENV}             = 'development';
    my $config = GPForum::Config->from_environment;
    my $schema = GPForum::Schema->connect_from_config($config);
    my $runner = GPForum::Migration::Runner->new( schema => $schema );
    $runner->apply_pending;
    $schema->storage->dbh->do(
        q{CREATE TABLE backup_probe (said text NOT NULL)});
    $schema->storage->dbh->do(
        q{INSERT INTO backup_probe (said) VALUES ('kept by the backup')});
    $schema->storage->disconnect;
    my $latest = GPForum::Migration::Plan->new->summary->[-1]{version};

    subtest 'gpforum backup takes the database and the uploads' => sub {
        my $backup = GPForum::Service::Operations::Backup->new(
            config => $config,
            root   => "$scratch/code",
        );
        my $taken    = $backup->take("$scratch/backups");
        my $manifest = $taken->{manifest};
        is( $manifest->{database}{name}, $name, 'the database the DSN names' );
        is( $manifest->{versions}{schema}, $latest, 'at the latest migration' );
        like(
            $manifest->{versions}{postgresql},
            qr/\A $major [.]/msx,
            q{the server's version}
        );
        is( $manifest->{attachments}{files}, 1, 'and the one upload' );

        my $check = $backup->check( $taken->{directory} );
        is( $check->{findings}->status, 'ok', 'restore --check finds it whole' )
          or diag explain $check->{findings}->document;

        $tools->restore_database(
            "dbi:Pg:dbname=$restored;$server",
            "$taken->{directory}/database.dump"
        );
        my $copy = DBI->connect(
            "dbi:Pg:dbname=$restored;$server",
            $ENV{GPFORUM_DATABASE_USER}     // q{},
            $ENV{GPFORUM_DATABASE_PASSWORD} // q{},
            { AutoCommit => 1, PrintError => 0, RaiseError => 1 }
        );
        is(
            scalar $copy->selectrow_array('SELECT said FROM backup_probe'),
            'kept by the backup',
            'and the dump restores the rows'
        );
        is(
            scalar $copy->selectrow_array(
                'SELECT max(version) FROM schema_versions'),
            $latest,
            'and the schema'
        );
        $copy->disconnect;
    };
    subtest 'backup --verify restores the dump and counts it the same' => sub {
        my $backup = GPForum::Service::Operations::Backup->new(
            config => $config,
            root   => "$scratch/code",
        );
        my $taken = $backup->take( "$scratch/verified", { verify => 1 } );
        is( $taken->{manifest}{verification}{status},
            'verified', 'the restore counts as the snapshot did' );
        is( _verify_databases(), 0, 'and its database is gone' );
    };

    subtest 'a restore that loses a row fails, and leaves no database' => sub {
        my $error;
        try {
            GPForum::Service::Operations::BackupVerifier->new(
                config => $config,
                tools  => GPForum::Test::LosingRestore->new( tools => $tools ),
            )->run("$scratch/losing.dump");
        }
        catch ($caught) {
            $error = $caught;
        };
        like(
            "$error",
            qr/\A backup [ ] restore [ ] mismatch: [ ] schema_versions/msx,
            'naming the table whose count differs'
        );
        is( _verify_databases(), 0, 'and its database is dropped' );
    };

    subtest 'an older pg_dump under --verify is said as without it' => sub {
        my $older = $scratch->child('pg_dump-16');
        $older->spew(<<'SH');
#!/bin/sh
case "$1" in --version) echo 'pg_dump (PostgreSQL) 16.4'; exit 0;; esac
echo 'pg_dump: error: aborting because of server version mismatch' >&2
echo 'pg_dump: detail: server version: 18.6; pg_dump version: 16.4' >&2
exit 1
SH
        $older->chmod( oct '755' );
        my $backup = GPForum::Service::Operations::Backup->new(
            catalog =>
              GPForum::Service::I18N::CliCatalog->new( language => 'en' ),
            clients => GPForum::Service::Operations::StagingDrill::PgTools->new(
                pg_dump    => "$older",
                pg_restore => $tools->pg_restore,
            ),
            config => $config,
            root   => "$scratch/code",
        );
        my $error;
        try {
            $backup->take( "$scratch/older", { verify => 1 } );
        }
        catch ($caught) {
            $error = $caught;
        };
        is(
            $error->message,
            'pg_dump 16.4 cannot back up PostgreSQL 18.6, which is newer:'
              . q{ install PostgreSQL 18's client programs, or name their}
              . ' pg_dump with GPFORUM_PG_DUMP.',
            'a pg_dump older than the server, with the client to install'
        );
        is( _verify_databases(), 0, 'and no database is left behind' );
    };

}
catch ($error) {
    fail("the backup on PostgreSQL: $error");
};

for my $database ( $restored, $name ) {
    $admin->do("DROP DATABASE IF EXISTS $database WITH (FORCE)");
}
$admin->disconnect;

done_testing;

# The verifications' temporary databases still on the server.
sub _verify_databases {
    return
      scalar $admin->selectrow_array( q{SELECT count(*) FROM pg_database}
          . q{ WHERE datname LIKE 'gpforum\_verify\_%'} );
}

1;
