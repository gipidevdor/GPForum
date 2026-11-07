# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package main;
use v5.40;
use Carp qw(croak);
use Const::Fast;
use English qw(-no_match_vars);
use utf8;
use Test::More;
use Test::Exception;
use POSIX qw(_exit);
use lib 'lib', 't/lib';
use GPForum::Config;
use GPForum::Schema;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Infrastructure::SqlFunctionCatalogue;
use GPForum::Infrastructure::PgNotifications;
use GPForum::Test::PgDatabase;
our $VERSION = '0.001';
const my $AFTER_NESTED => 3;
const my $ROLLED_BACK  => 4;
const my $EXTERNAL     => 5;

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'set GPFORUM_TEST_DSN for native Mojo::Pg coverage';
}
my $database = GPForum::Test::PgDatabase->fresh;
my $schema   = GPForum::Schema->connect(
    $database->dsn,
    $ENV{GPFORUM_DATABASE_USER}     // q{},
    $ENV{GPFORUM_DATABASE_PASSWORD} // q{}
);
isa_ok( $schema->pg,                'Mojo::Pg' );
isa_ok( $schema->storage->database, 'Mojo::Pg::Database' );
ok( !$schema->isa('DBIx::Class::Schema'), 'the runtime is not an ORM schema' );
ok( !$schema->can('resultset'), 'runtime has no table-query escape hatch' );
is_deeply( [ grep { m{\ADBIx/}msx } keys %INC ], [], 'DBIx is not loaded' );
my $dbh = $schema->storage->dbh;
$dbh->do('CREATE TEMP TABLE mojo_probe(id integer PRIMARY KEY)');
$dbh->do(
    join q{ },
    'CREATE FUNCTION api.native_probe_v1(p_document jsonb, p_bytes bytea)',
q{RETURNS TABLE(document jsonb, bytes bytea) LANGUAGE sql AS 'SELECT p_document, p_bytes'}
);
$dbh->do(
    join q{ },
    'CREATE FUNCTION api.native_insert_v1(p_id integer) RETURNS integer',
q{LANGUAGE sql AS 'INSERT INTO pg_temp.mojo_probe VALUES (p_id) RETURNING id'}
);
my $catalogue = GPForum::Infrastructure::SqlFunctionCatalogue->new(
    entries => {
        native_probe => {
            version    => 1,
            parameters => [ document => 'jsonb', bytes => 'bytea' ],
            json       => ['document']
        },
        native_insert => { version => 1, parameters => [ id => 'integer' ] },
    }
);
my $functions = GPForum::Infrastructure::SqlFunction->new(
    schema    => $schema,
    catalogue => $catalogue
);
my $bytes = pack 'H*', '00ff5c62696e61727900';
my $probe = $functions->row(
    'native_probe',
    {
        document => { text => 'città', values => [ 1, undef ] },
        bytes    => $bytes
    }
);
is_deeply(
    $probe->{document},
    { text => 'città', values => [ 1, undef ] },
    'JSON is decoded once'
);
is( $probe->{bytes}, $bytes, 'binary values retain NUL and non-UTF8 bytes' );

$schema->txn_do(
    sub {
        $functions->row( 'native_insert', { id => 1 } );
        throws_ok {
            $schema->txn_do(
                sub {
                    $functions->row( 'native_insert', { id => 2 } );
                    $functions->row( 'native_insert', { id => 1 } );
                }
            );
        }
        'GPForum::X::Conflict',
          'nested failure is classified and rolled back to a savepoint';
        $functions->row( 'native_insert', { id => $AFTER_NESTED } );
    }
);
is_deeply(
    $dbh->selectcol_arrayref('SELECT id FROM mojo_probe ORDER BY id'),
    [ 1, $AFTER_NESTED ],
    'outer transaction commits after nested rollback'
);
throws_ok {
    $schema->txn_do(
        sub {
            $functions->row( 'native_insert', { id => $ROLLED_BACK } );
            croak "original transaction failure\n";
        }
    );
}
qr/original [ ] transaction [ ] failure/msx, 'outer failure propagates';
is( $dbh->selectrow_array('SELECT count(*) FROM mojo_probe WHERE id=4'),
    0, 'outer failure rolls back' );
$dbh->begin_work;
$schema->txn_do(
    sub { $functions->row( 'native_insert', { id => $EXTERNAL } ); } );
ok( !$dbh->{AutoCommit},
    'joining an existing transaction does not commit its caller' );
$dbh->rollback;
is( $dbh->selectrow_array('SELECT count(*) FROM mojo_probe WHERE id=5'),
    0, 'caller rollback remains effective' );
is( $schema->storage->transaction_depth, 0, 'transaction frames are balanced' );
is_deeply(
    [ $schema->txn_do( sub { return ( 1, 2 ); } ) ],
    [ 1, 2 ],
    'list context is preserved'
);

my $notifications =
  GPForum::Infrastructure::PgNotifications->new( schema => $schema );
ok( $notifications->listen_to('mojo_native_probe'),
    'native connection listens' );
$dbh->selectrow_array(
    q{SELECT pg_notify('mojo_native_probe','delivered during query')});
$functions->row( 'native_probe', { document => {}, bytes => q{} } );
my $taken = $notifications->take('mojo_native_probe');
is_deeply(
    [ map { $_->[2] } @{ $taken->{notifications} } ],
    ['delivered during query'],
    'Mojo query events cannot consume the broker notifications'
);

my $parent_pid = $dbh->{pg_pid};
pipe my $read, my $write or croak "pipe: $OS_ERROR";
my $child = fork;
croak "fork: $OS_ERROR" if !defined $child;
if ( !$child ) {
    close $read or croak "close read pipe: $OS_ERROR";
    my $child_db = $schema->storage->database;
    my $pid      = $child_db->dbh->{pg_pid};
    print {$write} "$pid\n" or croak "write child pid: $OS_ERROR";
    close $write            or croak "close write pipe: $OS_ERROR";
    _exit(0);
}
close $write or croak "close write pipe: $OS_ERROR";
my $child_pid = <$read>;
close $read or croak "close read pipe: $OS_ERROR";
is( scalar waitpid( $child, 0 ), $child, 'the child is reaped' );
chomp $child_pid;
isnt( $child_pid, $parent_pid, 'a fork obtains its own Mojo::Pg connection' );
is( $dbh->selectrow_array('SELECT pg_backend_pid()'),
    $parent_pid, 'child disposal leaves the parent connection alive' );

# A swallowed inner exception cannot turn a lost outer transaction into
# successful autocommit work on a replacement connection.
my $peer = $schema->pg->db;
my $lost_outer;
try {
    $schema->txn_do(
        sub {
            throws_ok {
                $schema->txn_do(
                    sub {
                        $peer->query( 'SELECT pg_terminate_backend(?)',
                            $dbh->{pg_pid} );
                        croak "original connection failure\n";
                    }
                );
            }
            qr/original [ ] connection [ ] failure/msx,
              'rollback failure preserves the original nested exception';
            throws_ok {
                $functions->row( 'native_probe',
                    { document => {}, bytes => q{} } );
            }
            qr/Connection [ ] lost [ ] inside [ ] a [ ] transaction/msx,
              'the enclosing transaction cannot reconnect and autocommit';
        }
    );
}
catch ($error) { $lost_outer = $error; };
like(
    "$lost_outer",
    qr/Connection [ ] lost [ ] inside [ ] a [ ] transaction/msx,
    'a caught nested failure still prevents the outer commit'
);
is( $schema->storage->transaction_depth,
    0, 'failed rollback unwinds all frames' );
is_deeply(
    $functions->row( 'native_probe', { document => {}, bytes => q{} } )
      ->{document},
    {},
    'a subsequent independent call reconnects'
);
$schema->storage->disconnect;
done_testing;
1;
