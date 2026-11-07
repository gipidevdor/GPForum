# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;
use v5.40;
use utf8;
use Const::Fast;
use Carp qw(croak);
use Mojo::IOLoop;
use Mojo::Promise;
use Test::More;
use lib 'lib', 't/lib';
use GPForum::Schema;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Infrastructure::AsyncQuery;
use GPForum::Infrastructure::AsyncWork;
use GPForum::Infrastructure::SqlFunctionCatalogue;
use GPForum::Service::Operations::DbQueryStats;
use GPForum::Test::PgDatabase;
use GPForum::Test::Promise qw(await_result);

our $VERSION = '0.001';
const my $SLOW_SECONDS   => 0.15;
const my $FAST_SECONDS   => 0.03;
const my $TICK_SECONDS   => 0.01;
const my $BURST_REQUESTS => 100;

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
$dbh->do(<<'SQL');
    CREATE FUNCTION api.async_probe_v1(p_delay text, p_document jsonb, p_bytes bytea)
    RETURNS TABLE(pid integer, document jsonb, bytes bytea) LANGUAGE sql AS
    'SELECT pg_backend_pid(), p_document, p_bytes FROM pg_sleep(p_delay::double precision)'
SQL
my $catalogue = GPForum::Infrastructure::SqlFunctionCatalogue->new(
    entries => {
        async_probe => {
            version    => 1,
            parameters =>
              [ delay => 'text', document => 'jsonb', bytes => 'bytea' ],
            json => ['document']
        },
    }
);
my $functions = GPForum::Infrastructure::SqlFunction->new(
    schema    => $schema,
    catalogue => $catalogue
);
my $stats = GPForum::Service::Operations::DbQueryStats->new;
$stats->attach_to_schema($schema);
my $executor = GPForum::Infrastructure::AsyncQuery->for_schema($schema);
is( await_result( $executor->prewarm_p ),
    2, 'worker startup retains two isolated asynchronous leases' );

for my $db ( @{ $executor->connections } ) {
    $db->dbh->{Callbacks} =
      { ping => sub { croak 'synchronous ping is forbidden'; } };
}
my $bytes    = pack 'H*', '00ff5c62696e61727900';
my $document = { text => 'è🙂', list => [ 1, undef ] };
my $sync_pid = $dbh->{pg_pid};
$schema->txn_begin;
my ( $slow, $fast, @finished, $ticks );
$ticks = 0;
my $timer = Mojo::IOLoop->recurring( $TICK_SECONDS => sub { $ticks++; } );
my $slow_context = $stats->start_request( { route => 'slow' } );
my $a            = $functions->row_p(
    'async_probe',
    {
        delay    => $SLOW_SECONDS,
        document => $document,
        bytes    => $bytes
    },
    $slow_context
)->then( sub ($row) { $slow = $row; push @finished, 'slow'; return; } );
my $fast_context = $stats->start_request( { route => 'fast' } );
my $b            = $functions->row_p(
    'async_probe',
    {
        delay    => $FAST_SECONDS,
        document => $document,
        bytes    => $bytes
    },
    $fast_context
)->then( sub ($row) { $fast = $row; push @finished, 'fast'; return; } );
my $error;
Mojo::Promise->all( $a, $b )
  ->catch( sub ($caught) { $error = $caught; return; } )
  ->wait;
Mojo::IOLoop->remove($timer);
ok( !$error, 'both asynchronous queries complete' ) or diag "$error";
is_deeply(
    \@finished,
    [ 'fast', 'slow' ],
    'queries progress concurrently on distinct connections'
);
cmp_ok( $ticks, '>', 1, 'event-loop timers advance while PostgreSQL waits' );

for my $row ( $slow, $fast ) {
    is_deeply( $row->{document}, $document,
        'JSON and Unicode survive asynchronous transport' );
    is( $row->{bytes}, $bytes,
        'binary NUL and non-UTF8 bytes survive asynchronous transport' );
    isnt( $row->{pid}, $sync_pid,
        'asynchronous query does not use the workflow transaction' );
}
isnt( $slow->{pid}, $fast->{pid},
    'concurrent requests own separate PostgreSQL backends' );
ok( !$dbh->{AutoCommit},
    'asynchronous completions did not commit the synchronous transaction' );
$schema->txn_rollback;
my $fast_stats = $stats->finish_request( $fast_context, { status => 200 } );
my $slow_stats = $stats->finish_request( $slow_context, { status => 200 } );
is( $fast_stats->{queries}, 1, 'fast request owns exactly its query' );
is( $slow_stats->{queries}, 1, 'slow request owns exactly its query' );
cmp_ok( $fast_stats->{db_duration_ms}, '>', 0,
    'fast query timing is retained' );
cmp_ok( $slow_stats->{db_duration_ms}, '>', 0,
    'slow query timing is retained' );
my $rejected;
$functions->row_p( 'async_probe', { unknown => 1 } )
  ->catch( sub ($caught) { $rejected = $caught; return; } )
  ->wait;
isa_ok( $rejected, 'GPForum::X::Argument',
    'parameter validation rejects through the promise' );
subtest 'a concurrent request burst retains the fixed connection budget' =>
  \&_burst_queries;
subtest 'dedicated asynchronous leases stay fork-safe' => \&_forked_leases;
$dbh->do('DROP FUNCTION api.async_probe_v1(text, jsonb, bytea)');
$dbh->do(<<'SQL');
    CREATE FUNCTION api.async_probe_v1(p_delay text, p_document jsonb, p_bytes bytea)
    RETURNS TABLE(pid bigint, document jsonb, bytes bytea) LANGUAGE sql AS
    'SELECT pg_backend_pid()::bigint, p_document, p_bytes FROM pg_sleep(p_delay::double precision)'
SQL
my ( $after_change, $change_error );
my $changed = $functions->row_p( 'async_probe',
    { delay => 0, document => $document, bytes => $bytes } );
$changed->then( sub ($row) { $after_change = $row; return; } )
  ->catch( sub ($caught) { $change_error = $caught; return; } )
  ->wait;
ok( !$change_error,
    'a changed function result invalidates and retries its cached plan once' )
  or diag "$change_error";
is_deeply( $after_change->{document},
    $document, 'asynchronous calls survive result-type migrations' );
subtest 'failed and retired leases leave no reusable handles' =>
  \&_retired_leases;
done_testing();

sub _burst_queries {
    my ( $failure, @rows );
    my $all = Mojo::Promise->all(
        map {
            $functions->row_p( 'async_probe',
                { delay => 0, document => { sequence => $_ }, bytes => $bytes }
            )
        } 1 .. $BURST_REQUESTS
    );
    $all->then(
        sub (@results) {
            @rows = map { $_->[0] } @results;
            return;
        }
    )->catch( sub ($caught) { $failure = $caught; return; } )->wait;
    ok( !$failure, 'all requests are admitted without capacity errors' )
      or diag "$failure";
    is( scalar @rows, $BURST_REQUESTS, 'every queued query completes' );
    is_deeply(
        [ map { $_->{document}{sequence} } @rows ],
        [ 1 .. $BURST_REQUESTS ],
        'results retain request identity and order'
    );
    my %backends = map { $_->{pid} => 1 } @rows;
    is( scalar keys %backends, 2, 'the burst still uses only two SQL leases' );
    return;
}

sub _forked_leases {
    my $work = GPForum::Infrastructure::AsyncWork->new;
    my ( $child_pid, $child_error );
    my $forked = $work->run_p(
        sub {
            my ( $row, $probe_error );
            my $probe = $functions->row_p( 'async_probe',
                { delay => 0, document => $document, bytes => $bytes } );
            $probe->then( sub ($value) { $row = $value; return; } )
              ->catch( sub ($caught) { $probe_error = $caught; return; } )
              ->wait;
            croak $probe_error if $probe_error;
            return $row->{pid};
        }
    );
    $forked->then( sub ($value) { $child_pid = $value; return; } )
      ->catch( sub ($caught) { $child_error = $caught; return; } )
      ->wait;
    ok( !$child_error,
        'a forked executor replaces inherited asynchronous leases' )
      or diag "$child_error";
    ok(
        $child_pid && $child_pid != $slow->{pid} && $child_pid != $fast->{pid},
        'the child uses a distinct PostgreSQL backend'
    );
    my $parent_after_child;
    $functions->row_p( 'async_probe',
        { delay => 0, document => $document, bytes => $bytes } )
      ->then( sub ($row) { $parent_after_child = $row; return; } )
      ->wait;
    ok(
        $parent_after_child->{pid} == $slow->{pid}
          || $parent_after_child->{pid} == $fast->{pid},
        'the child did not close either parent asynchronous socket'
    );
    return;
}

sub _retired_leases {
    my $failed;
    $executor->run_p( sub ($db) { return $db->query_p('SELECT 1/0'); } )
      ->catch( sub ($caught) { $failed = $caught; return; } )
      ->wait;
    ok( $failed, 'an execution failure rejects normally' );
    is( scalar @{ $executor->connections },
        1, 'a failed lease leaves the reusable set' );
    my $recovered;
    $functions->row_p( 'async_probe',
        { delay => 0, document => $document, bytes => $bytes } )
      ->then( sub ($row) { $recovered = $row; return; } )
      ->wait;
    is_deeply( $recovered->{document},
        $document, 'remaining leases keep working after a peer fails' );
    my ( $during_reset, $reset_error );
    my $in_flight = $functions->row_p( 'async_probe',
        { delay => $SLOW_SECONDS, document => $document, bytes => $bytes } );
    Mojo::IOLoop->timer(
        $TICK_SECONDS => sub { $executor->retire_connections; return; } );
    $in_flight->then( sub ($row) { $during_reset = $row; return; } )
      ->catch( sub ($caught) { $reset_error = $caught; return; } )
      ->wait;
    ok( !$reset_error && $during_reset,
        'reset lets an in-flight operation settle on its owned connection' );
    is( scalar @{ $executor->connections },
        0, 'reset retires active leases once they settle' );
    my $after_reset;
    $functions->row_p( 'async_probe',
        { delay => 0, document => $document, bytes => $bytes } )
      ->then( sub ($row) { $after_reset = $row; return; } )
      ->wait;
    ok( $after_reset && $after_reset->{pid} != $during_reset->{pid},
        'a reset operation obtains a fresh backend' );
    $schema->storage->disconnect;
    is( scalar @{ $executor->connections },
        0, 'storage disconnect also closes idle asynchronous leases' );
    return;
}

1;
