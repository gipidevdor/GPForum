# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use Test::Fatal qw(exception);
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Migration::Runner;
use GPForum::Test::RefusingMigrationDbh;
use GPForum::Test::RefusingMigrationSchema;

our $VERSION = '0.001';

const my $NO_TIMEOUT   => qr/set_config[(]'lock_timeout',[ ]'0'/msx;
const my $LOCK         => qr/pg_advisory_lock/msx;
const my $RESTORED     => qr/set_config[(]'lock_timeout',[ ][?]/msx;
const my $LOCK_WAITING => qr/$NO_TIMEOUT .* $LOCK .* $RESTORED/msx;

sub _runner ($dbh) {
    return GPForum::Migration::Runner->new(
        schema => GPForum::Test::RefusingMigrationSchema->new( dbh => $dbh ) );
}

# The migration lock waits past the session's lock_timeout, and a lock that
# PostgreSQL refuses stops the run: it read as "not locked", and a second
# deployer migrated beside the first.
my $waiting = GPForum::Test::RefusingMigrationDbh->new;
is( _runner($waiting)->_lock, 1, 'the lock is taken' );
like( join( "\n", @{ $waiting->statements } ),
    $LOCK_WAITING,
    'with no lock timeout while it waits, and the timeout restored after' );
my $refused = GPForum::Test::RefusingMigrationDbh->new(
    failing => 'pg_advisory_lock',
    fails   => '55P03'
);
ok( exception { _runner($refused)->_lock }, 'a refused lock stops the run' );

# The migration record reads as empty only when its table is not there.
my $denied = GPForum::Test::RefusingMigrationDbh->new(
    failing => 'schema_versions',
    fails   => '42501'
);
ok(
    exception { _runner($denied)->recorded_checksums },
    'a role that may not read schema_versions is told so'
);
my $fresh = GPForum::Test::RefusingMigrationDbh->new(
    failing => 'schema_versions',
    fails   => '42P01'
);
is_deeply( _runner($fresh)->recorded_checksums,
    {}, 'a database without the table has nothing applied' );

done_testing();

1;
