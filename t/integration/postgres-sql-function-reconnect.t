# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Infrastructure::SqlFunction;
use GPForum::Test::PgDatabase;
use GPForum::Test::PostgresHarness;

our $VERSION = '0.001';

# A call runs on the storage's handle as dbh_do ran it, without its block
# runner: a connection PostgreSQL closed -- a restart, an administrator --
# is made again and the call tried once more; inside a transaction it is
# not, since a new connection would not be in it.

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'set GPFORUM_TEST_DSN for the reconnect test';
}

my $database  = GPForum::Test::PgDatabase->fresh;
my $schema    = $database->schema;
my $storage   = $schema->storage;
my $functions = GPForum::Infrastructure::SqlFunction->for_schema($schema);
my %call      = (
    user_id   => '018f1002-0001-7000-8000-000000000001',
    thread_id => '018f1004-0001-7000-8000-000000000001',
);
my $admin = GPForum::Test::PostgresHarness::connect_dbi( $database->dsn );

is_deeply( $functions->rows( 'forum_read_state', \%call ),
    [], 'a call answers' );
_terminate();
is_deeply( $functions->rows( 'forum_read_state', \%call ),
    [], 'and answers again once its connection is gone' );
ok( $storage->connected, 'on a connection made again' );

$schema->txn_begin;
_terminate();
my $failed = !eval { $functions->rows( 'forum_read_state', \%call ); 1; };
ok( $failed, 'inside a transaction the call is not tried again' );
is( $storage->transaction_depth, 1, 'and the transaction is still open' );
eval { $schema->txn_rollback; 1; } or $storage->disconnect;
is_deeply( $functions->rows( 'forum_read_state', \%call ),
    [], 'and the next call outside one connects again' );

$storage->disconnect;
$admin->disconnect;

done_testing();

# Ends the storage's backend from another connection, as an administrator or
# a restart of PostgreSQL would.
sub _terminate {
    my $pid = $storage->dbh->{pg_pid};
    $admin->selectrow_array( 'SELECT pg_terminate_backend(?)', undef, $pid );

    return;
}

1;
