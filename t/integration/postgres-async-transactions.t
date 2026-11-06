# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package main;
use v5.40;
use Mojo::Base -strict, -async_await;
use v5.40;
use Test::More;
use Const::Fast;
use Mojo::IOLoop;
use Mojo::Promise;
use lib 'lib', 't/lib';
use GPForum::Schema;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Infrastructure::SqlFunctionCatalogue;
use GPForum::Test::PgDatabase;
use GPForum::Test::Promise qw(await_result);
our $VERSION = '0.001';
const my $THIRD_VALUE    => 3;
const my $EXTERNAL_VALUE => 99;
const my $TICK_SECONDS   => 0.005;

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'PostgreSQL required';
}
my $database = GPForum::Test::PgDatabase->fresh;
my $schema   = GPForum::Schema->connect(
    $database->dsn,
    $ENV{GPFORUM_DATABASE_USER}     // q{},
    $ENV{GPFORUM_DATABASE_PASSWORD} // q{}
);
my $dbh = $schema->storage->dbh;
$dbh->do('CREATE TABLE api.async_txn_values (value integer)');
$dbh->do(
q{CREATE FUNCTION api.async_txn_write_v1(p_value integer) RETURNS TABLE(value integer, pid integer) LANGUAGE sql AS 'INSERT INTO api.async_txn_values VALUES (p_value) RETURNING value, pg_backend_pid()'}
);
my $functions = GPForum::Infrastructure::SqlFunction->new(
    schema    => $schema,
    catalogue => GPForum::Infrastructure::SqlFunctionCatalogue->new(
        entries => {
            async_txn_write =>
              { version => 1, parameters => [ value => 'integer' ] },
        }
    )
);
$schema->txn_begin;
$dbh->do('INSERT INTO api.async_txn_values VALUES (99)');
my @backends;
my $nested_error;
await_result(
    $functions->transaction_p(
        async sub ($transaction) {
            push @backends,
              ( await $transaction->row_p( 'async_txn_write', { value => 1 } ) )
              ->{pid};
            try {
                await $transaction->transaction_p(
                    async sub ($nested) {
                        await $nested->row_p( 'async_txn_write',
                            { value => 2 } );
                        die "nested rollback marker\n";
                    }
                );
            }
            catch ($error) { $nested_error = "$error"; };
            push @backends,
              ( await $transaction->row_p( 'async_txn_write', { value => 3 } ) )
              ->{pid};
            return;
        }
    )
);
like(
    $nested_error,
    qr/nested[ ]rollback[ ]marker/msx,
    'a savepoint preserves the original rejection'
);
is( $backends[0], $backends[1],
    'the complete promise transaction owns one backend' );
isnt( $backends[0], $dbh->{pg_pid},
    'an external synchronous transaction is never shared' );
is_deeply(
    $dbh->selectcol_arrayref(
        'SELECT value FROM api.async_txn_values ORDER BY value'),
    [ 1, $THIRD_VALUE, $EXTERNAL_VALUE ],
    'nested rollback removes its write while the outer transaction commits'
);
my $failed;
$functions->transaction_p(
    async sub ($transaction) {
        await $transaction->row_p( 'async_txn_write', { value => 4 } );
        die "outer rollback marker\n";
    }
)->catch( sub ($error) { $failed = "$error"; return; } )->wait;
like(
    $failed,
    qr/outer[ ]rollback[ ]marker/msx,
    'outer rollback preserves its cause'
);
is(
    $dbh->selectrow_array(
        'SELECT count(*) FROM api.async_txn_values WHERE value = 4'),
    0,
    'a rejected transaction persists no write'
);
my $swallowed;
$functions->transaction_p(
    async sub ($transaction) {
        await $transaction->row_p( 'async_txn_write', { value => 6 } );
        await $transaction->async_database->query_p('SELECT 1/0')
          ->catch( sub { return; } );
    }
)->catch( sub ($error) { $swallowed = "$error"; return; } )->wait;
like(
    $swallowed,
    qr/rolled[ ]back[ ]before[ ]commit/msx,
    'a swallowed SQL error cannot turn an aborted transaction into success'
);
is(
    $dbh->selectrow_array(
        'SELECT count(*) FROM api.async_txn_values WHERE value = 6'),
    0,
    'an aborted transaction never reports its rolled-back write as committed'
);
my ( $ticks, $timeout ) = ( 0, undef );
my $timer =
  Mojo::IOLoop->recurring( $TICK_SECONDS => sub { $ticks++; return; } );
$functions->transaction_p(
    async sub ($transaction) {
        await $transaction->async_database->query_p(
            q{SELECT set_config('statement_timeout', '80ms', true)});
        await $transaction->async_database->query_p('SELECT pg_sleep(0.3)');
    },
    undef,
    1
)->catch( sub ($error) { $timeout = "$error"; return; } )->wait;
Mojo::IOLoop->remove($timer);
like(
    $timeout,
    qr/statement[ ]timeout/msx,
    'native transaction-local deadlines cancel a slow statement'
);
cmp_ok( $ticks, '>=', $THIRD_VALUE,
    'the event loop continues during the timed query and its rollback' );
$schema->txn_rollback;
is_deeply(
    $dbh->selectcol_arrayref(
        'SELECT value FROM api.async_txn_values ORDER BY value'),
    [ 1, $THIRD_VALUE ],
    'native commits did not commit the caller\'s separate transaction'
);
$schema->storage->disconnect;
done_testing();

1;
