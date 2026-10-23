# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::TemporaryPostgres;

use v5.40;

use Carp    qw(croak);
use English qw(-no_match_vars);

our $VERSION = '0.001';

# Loaded by the integration runner in each test process, before its DSN
# guards. Retained until global destruction; Test::PostgreSQL only stops a
# cluster in its owning process, so forked race workers cannot stop it.
my $cluster;
my $owner;

sub import ($class) {
    if ( $ENV{GPFORUM_DATABASE_DSN} || $ENV{GPFORUM_TEST_DSN} ) {
        $ENV{GPFORUM_DATABASE_DSN} //= $ENV{GPFORUM_TEST_DSN};
        $ENV{GPFORUM_TEST_DSN}     //= $ENV{GPFORUM_DATABASE_DSN};
        return;
    }
    $owner = $PROCESS_ID;
    require Test::PostgreSQL;
    $cluster = Test::PostgreSQL->new(
        unix_socket           => 1,
        extra_initdb_args     => '--encoding=UTF8 --no-locale',
        extra_postmaster_args => q{-c max_connections=40},
      )
      or croak
      'cannot start integration PostgreSQL; check initdb and postgres on PATH';
    ## no critic (Variables::RequireLocalizedPunctuationVars) -- each test and its children need these settings until process exit
    $ENV{GPFORUM_DATABASE_DSN}      = $cluster->dsn( dbname => 'postgres' );
    $ENV{GPFORUM_TEST_DSN}          = $ENV{GPFORUM_DATABASE_DSN};
    $ENV{GPFORUM_DATABASE_USER}     = 'postgres';
    $ENV{GPFORUM_DATABASE_PASSWORD} = q{};
    ## use critic
    return;
}

# PgDatabase's END runs first and removes its clones. Disconnect remaining
# statement caches before stopping the server, while preserving test status.
END {
    my $test_status = $CHILD_ERROR;
    if ( $cluster && $owner == $PROCESS_ID ) {
        for my $driver ( values %{ { DBI->installed_drivers } } ) {
            for my $dbh ( grep { defined && $_->{Active} }
                @{ $driver->{ChildHandles} || [] } )
            {
                try {
                    for my $statement ( grep { defined && $_->{Active} }
                        @{ $dbh->{ChildHandles} || [] } )
                    {
                        $statement->finish;
                    }
                    $dbh->disconnect;
                }
                catch ($error) {

                    # A test may deliberately terminate its own connection.
                };
            }
        }
        $cluster->stop;
        undef $cluster;
    }
    $CHILD_ERROR = $test_status;    ## no critic (Variables::RequireLocalizedPunctuationVars) -- localizing an exit status in END erases failures
}

1;
