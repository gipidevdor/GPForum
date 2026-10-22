# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use English qw(-no_match_vars);
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Config;
use GPForum::Schema;
use GPForum::Test::PostgresHarness;

our $VERSION = '0.001';

if ( !$ENV{GPFORUM_DATABASE_DSN} ) {
    plan skip_all => 'set GPFORUM_DATABASE_DSN to run against PostgreSQL';
}

# Production connects as an ordinary role that owns its database, not as a
# superuser. Every connection ran SET lc_messages, which PostgreSQL allows
# only to a superuser, so such a role could neither migrate nor connect.
my $admin_dsn = $ENV{GPFORUM_DATABASE_DSN};
my $admin     = GPForum::Test::PostgresHarness::connect_dbi($admin_dsn);
my $role      = "gpf_plain_$PROCESS_ID";
my $name      = "gpforum_plain_$PROCESS_ID";
my $password  = "plain-role-$PROCESS_ID";
$admin->do( qq{CREATE ROLE "$role" LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE}
      . ' PASSWORD '
      . $admin->quote($password) );
$admin->do(qq{CREATE DATABASE "$name" OWNER "$role"});
( my $dsn = $admin_dsn ) =~ s/dbname=[^;]+/dbname=$name/msx;

{
    local $ENV{GPFORUM_DATABASE_DSN}      = $dsn;
    local $ENV{GPFORUM_DATABASE_USER}     = $role;
    local $ENV{GPFORUM_DATABASE_PASSWORD} = $password;

    is( GPForum::Test::PostgresHarness::prepare_database()->{migrate},
        0, 'a role without superuser migrates its own database' );

    my $schema =
      GPForum::Schema->connect_from_config( GPForum::Config->from_environment );
    my $dbh = $schema->storage->dbh;
    is(
        scalar $dbh->selectrow_array('SELECT count(*) FROM schema_versions') >
          0,
        1,
        'and the application connects as it'
    );
    is(
        scalar $dbh->selectrow_array(q{SELECT current_setting('lock_timeout')}),
        '3s',
        'with the session settings applied'
    );

    # ADR 0137: one statement sets the session, and the startup packet
    # names the process. A role that may not set lc_messages keeps the
    # server's, and still connects.
    is_deeply(
        $dbh->selectrow_arrayref(
                q{SELECT current_setting('pg_trgm.similarity_threshold'),}
              . q{ current_setting('statement_timeout'),}
              . q{ current_setting('application_name')}
        ),
        [ '0.18', '15s', 'gpforum' ],
        'the search threshold, the timeouts and the name, in one statement'
    );
    is(
        scalar $dbh->selectrow_array(q{SELECT current_setting('lc_messages')}),
        scalar $admin->selectrow_array(q{SHOW lc_messages}),
        q{and the server's message locale where the role may not set it}
    );
    $schema->storage->disconnect;
}

{
    local $ENV{GPFORUM_DATABASE_DSN} = $dsn;
    my $schema =
      GPForum::Schema->connect_from_config( GPForum::Config->from_environment );
    my ($superuser) = $admin->selectrow_array(
        'SELECT rolsuper FROM pg_roles WHERE rolname = current_user');
  SKIP: {
        if ( !$superuser ) {
            skip 'the test login is not a superuser', 1;
        }
        is(
            scalar $schema->storage->dbh->selectrow_array(
                q{SELECT current_setting('lc_messages')}),
            'C',
            'a role that may set lc_messages gets C'
        );
    }
    $schema->storage->disconnect;
}

$admin->do(qq{DROP DATABASE IF EXISTS "$name" WITH (FORCE)});
$admin->do(qq{DROP ROLE IF EXISTS "$role"});
$admin->disconnect;

done_testing();

1;
