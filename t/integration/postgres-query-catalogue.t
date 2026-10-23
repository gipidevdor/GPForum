# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;
use Const::Fast;
use English qw(-no_match_vars);
use POSIX   qw(_exit);
use Test::Mojo;
use Test::More;
use Mojo::Server::Prefork;

use lib 'lib';
use lib 't/lib';

use GPForum::Infrastructure::SqlFunctionCatalogue;
use GPForum::Test::PgDatabase;
use GPForum::Test::ReplacedSubs qw(with_replaced_subs);
use GPForum::Web::Warmup;

our $VERSION = '0.001';
const my $HTTP_OK => 200;

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'set GPFORUM_TEST_DSN for the SQL catalogue boundary';
}

my $database  = GPForum::Test::PgDatabase->fresh( seed => 1 );
my $admin     = $database->dbh;
my ($preload) = $admin->selectrow_array('SHOW shared_preload_libraries');
if ( $preload !~ /\bpg_stat_statements\b/msx ) {
    plan skip_all =>
      'pg_stat_statements must be preloaded (PostgreSQL matrix enables it)';
}
$admin->do('CREATE EXTENSION IF NOT EXISTS pg_stat_statements');

# This administrative observer must never be mistaken for application SQL.
$admin->do(q{SET pg_stat_statements.track = 'none'});
my ($dbid) = $admin->selectrow_array(
    'SELECT oid FROM pg_database WHERE datname=current_database()');
my ($thread) = $admin->selectrow_array(
    'SELECT thread_id FROM threads ORDER BY thread_id LIMIT 1');

local $ENV{GPFORUM_DATABASE_DSN}              = $database->dsn;
local $ENV{GPFORUM_MINION_ENABLED}            = 0;
local $ENV{GPFORUM_REALTIME_LISTENER_ENABLED} = 0;
local $ENV{GPFORUM_WARMUP_ENABLED}            = 0;
local $ENV{GPFORUM_LOG_LEVEL}                 = 'error';
my $test              = Test::Mojo->new('GPForum');
my $schema            = $test->app->gp_schema;
my $storage           = $schema->storage;
my $handle            = $storage->dbh;
my ($manager_backend) = $handle->selectrow_array('SELECT pg_backend_pid()');

# before_server_start is pre-fork: even with warmup off, no open handle is
# left for workers. Calling the API afterwards creates a fresh connection.
$test->app->plugins->emit_hook(
    before_server_start => Mojo::Server::Prefork->new,
    $test->app
);
ok( !$handle->{Active}, 'the pre-fork hook disconnected the manager handle' );
my ($worker_backend) =
  $storage->dbh->selectrow_array('SELECT pg_backend_pid()');
isnt( $worker_backend, $manager_backend, 'the next use creates a new backend' );

_fork_check( $storage, $worker_backend );

# A failure halfway through warming still releases its handle and marker.
with_replaced_subs(
    'GPForum::Web::Warmup',
    {
        _fetched => sub { die "warming interrupted\n" },
    },
    sub {
        my $failure;
        try { GPForum::Web::Warmup->new( application => $test->app )->run; }
        catch ($error) { $failure = "$error"; };
        like(
            $failure,
            qr/warming[ ]interrupted/msx,
            'warmup preserves the failure'
        );
    }
);
ok( !exists $test->app->defaults->{'gpforum.warming'},
    'the warming marker was cleared' );
ok( !$storage->connected, 'failed warmup closed its database handle' );

# Warm connection setup and every page, including cache LISTEN registration,
# before measuring application statements. Reset only this disposable DB.
my @pages = ( q{/}, '/categories', "/t/$thread", '/search?q=performance' );
for my $page (@pages) {
    $test->get_ok($page)->status_is($HTTP_OK);
}
my %allowed;
my $catalogue = GPForum::Infrastructure::SqlFunctionCatalogue->new;
for my $name ( @{ $catalogue->names } ) {
    my $sql       = $catalogue->function($name)->{sql};
    my $parameter = 0;
    $sql =~ s/[?]/q{$} . ++$parameter/gemsx;
    $allowed{ _normalized($sql) } = 1;
}

# Transaction framing is protocol, never an alternative data query.
for my $framing (qw(BEGIN COMMIT ROLLBACK)) {
    $allowed{$framing} = 1;
}

for my $page (@pages) {
    $test->app->gp_local_cache->clear;
    $admin->selectrow_array( 'SELECT pg_stat_statements_reset(0, ?::oid, 0)',
        undef, $dbid );
    $test->get_ok($page)->status_is($HTTP_OK);
    my $queries = _queries();
    ok( @{$queries}, "$page executed SQL (the check is not vacuous)" );
    my @escaped = grep { !$allowed{ _normalized($_) } } @{$queries};
    is_deeply( \@escaped, [],
        "$page sends only complete catalogued statements" );
    my $headers = $test->tx->res->headers;
    like(
        $headers->header('Server-Timing'),
        qr/\bdb;desc="PostgreSQL";dur=\d+[.]\d+/msx,
        'the browser receives a numeric SQL duration in milliseconds'
    );
}

# Negative control: a harmless direct ORM read must appear as a violation,
# even though its table is also read legitimately inside API functions.
$admin->selectrow_array( 'SELECT pg_stat_statements_reset(0, ?::oid, 0)',
    undef, $dbid );
$schema->resultset('User')->search( {}, { rows => 1 } )->all;
my @escaped = grep { !$allowed{ _normalized($_) } } @{ _queries() };
ok( @escaped, 'a direct DBIx read is detected outside the catalogue' );
$storage->disconnect;
done_testing();

sub _fork_check ( $connection_storage, $parent_backend ) {
    pipe my $reader, my $writer or BAIL_OUT("pipe: $OS_ERROR");
    my $child = fork // BAIL_OUT("fork: $OS_ERROR");
    if ( !$child ) {
        close $reader or _exit(1);
        my ($backend) =
          $connection_storage->dbh->selectrow_array('SELECT pg_backend_pid()');
        print {$writer} "$backend\n" or _exit(1);
        close $writer                or _exit(1);
        $connection_storage->disconnect;
        _exit(0);
    }
    close $writer or BAIL_OUT("close: $OS_ERROR");
    my $child_backend = <$reader>;
    close $reader or BAIL_OUT("close: $OS_ERROR");
    waitpid $child, 0;
    is( $CHILD_ERROR, 0,
        'a real fork can query and disconnect its own connection' );
    chomp $child_backend;
    isnt( $child_backend, $parent_backend,
        'the child never uses the inherited backend' );
    is(
        scalar $connection_storage->dbh->selectrow_array(
            'SELECT pg_backend_pid()'),
        $parent_backend,
        'disconnecting the child leaves the parent connection alive'
    );
    return;
}

sub _queries {
    return $admin->selectcol_arrayref(
'SELECT query FROM pg_stat_statements WHERE dbid=? AND toplevel AND calls > 0 ORDER BY query',
        undef, $dbid
    );
}

sub _normalized ($sql) {
    $sql =~ s/\s+/ /gmsx;
    $sql =~ s/\A\s+|\s+\z//gmsx;
    my %framing = map { $_ => 1 } qw(BEGIN COMMIT ROLLBACK);
    return $framing{ uc $sql } ? uc $sql : $sql;
}

1;
