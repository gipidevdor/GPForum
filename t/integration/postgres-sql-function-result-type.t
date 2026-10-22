# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use English qw(-no_match_vars);
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Infrastructure::SqlFunction;
use GPForum::Test::ResultTypeCatalogue;
use GPForum::Test::PgDatabase;

our $VERSION = '0.001';

# A function that RETURNS SETOF public.<table> changes its result type when
# a migration adds a column to the table. A worker that prepared a call of it
# before the migration reads the old columns until anything invalidates the
# plan -- a function altered, a cache reset -- and from then on every call is
# refused: "cached plan must not change result type". The layer forgets the
# statement and calls once more, outside a transaction; inside one, which the
# error has ended, it forgets it, so the next call prepares it afresh.

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'set GPFORUM_TEST_DSN for the result type test';
}

my $database = GPForum::Test::PgDatabase->fresh;
my $schema   = $database->schema;
my $admin    = $database->dbh;
$admin->do(<<'SQL');
CREATE TABLE public.result_type_probe (a integer NOT NULL);
INSERT INTO public.result_type_probe (a) VALUES (1);
CREATE FUNCTION api.ops_result_type_probe_v1(p_a integer)
RETURNS SETOF public.result_type_probe
LANGUAGE sql STABLE AS $$
    SELECT * FROM public.result_type_probe WHERE a = p_a
$$;
SQL

my $functions = GPForum::Infrastructure::SqlFunction->new(
    catalogue => GPForum::Test::ResultTypeCatalogue->new,
    schema    => $schema,
);

is_deeply(
    $functions->rows( 'probe', { a => 1 } ),
    [ { a => 1 } ],
    'a call prepares its statement'
);
is_deeply(
    $functions->rows( 'probe', { a => 1 } ),
    [ { a => 1 } ],
    'and the next one runs it again'
);

$admin->do('ALTER TABLE public.result_type_probe ADD COLUMN b integer');
is_deeply(
    $functions->rows( 'probe', { a => 1 } ),
    [ { a => 1 } ],
    'a column added under it is not seen yet'
);
_invalidate();
is_deeply(
    $functions->rows( 'probe', { a => 1 } ),
    [ { a => 1, b => undef } ],
    'once the plan is invalidated, the call is made again, prepared afresh'
);

$admin->do('ALTER TABLE public.result_type_probe ADD COLUMN c integer');
_invalidate();
my $refused = !eval {
    $schema->txn_do( sub { $functions->rows( 'probe', { a => 1 } ) } );
    1;
};
ok( $refused, 'inside a transaction the call is not made again' );
like( $EVAL_ERROR, qr/cached [ ] plan/msx, 'the error is as it was' );
is_deeply(
    $schema->txn_do( sub { $functions->rows( 'probe', { a => 1 } ) } ),
    [ { a => 1, b => undef, c => undef } ],
    'but the statement is forgotten, and the next transaction prepares it'
);

# A statement run once, unnamed as DBD::Pg ran a first execution, and run
# again after the column was added came back with more columns than the
# handle had read, and DBD::Pg crashed the process reading them. Prepared
# on the server from the start, it reads the columns it was prepared with.
$admin->do(<<'SQL');
CREATE TABLE public.result_type_once (a integer NOT NULL);
INSERT INTO public.result_type_once (a) VALUES (1);
CREATE FUNCTION api.ops_result_type_once_v1(p_a integer)
RETURNS SETOF public.result_type_once
LANGUAGE sql STABLE AS $$
    SELECT * FROM public.result_type_once WHERE a = p_a
$$;
SQL
is_deeply(
    $functions->rows( 'once', { a => 1 } ),
    [ { a => 1 } ],
    'a call made once'
);
$admin->do('ALTER TABLE public.result_type_once ADD COLUMN b integer');
is_deeply(
    $functions->rows( 'once', { a => 1 } ),
    [ { a => 1 } ],
    'and again after a column was added, the worker alive'
);

my $other = !eval {
    $functions->rows( 'probe', { a => 'not a number' } );
    1;
};
ok( $other, 'another error is not tried again' );

$schema->storage->disconnect;

done_testing();

# What invalidates a cached plan that calls the function, as a cache reset
# would on a busy server.
sub _invalidate {
    $admin->do('ALTER FUNCTION api.ops_result_type_probe_v1(integer) COST 101');
    $admin->do('ALTER FUNCTION api.ops_result_type_probe_v1(integer) COST 100');

    return;
}

1;
