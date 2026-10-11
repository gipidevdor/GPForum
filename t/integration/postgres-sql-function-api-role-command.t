# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;
use v5.40;
use Carp qw(carp croak);
use DBI;
use English       qw(-no_match_vars);
use JSON::MaybeXS qw(decode_json);
use Test::Exception;
use Test::More;
use lib 'lib';
use lib 't/lib';
use GPForum::Command::ApiRole;
use GPForum::Config;
use GPForum::Infrastructure::SqlFunctionCatalogue;
use GPForum::Test::PgDatabase;

our $VERSION = '0.001';

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'set GPFORUM_TEST_DSN to exercise API role provisioning';
}
my $database  = GPForum::Test::PgDatabase->fresh( seed => 1 );
my $admin     = $database->dbh;
my $owner     = "gpf_cli_api_owner_$PROCESS_ID";
my $runtime   = "gpf_cli_api_runtime_$PROCESS_ID";
my $catalogue = GPForum::Infrastructure::SqlFunctionCatalogue->new;
my $connection;

END {
    if ($connection) { $connection->disconnect; }
    if ( $admin && $admin->{Active} ) {
        for my $role ( $runtime, $owner ) {
            try {
                $admin->do(
                    'DROP OWNED BY ' . $admin->quote_identifier($role) );
                $admin->do(
                    'DROP ROLE IF EXISTS ' . $admin->quote_identifier($role) );
            }
            catch ($error) { carp $error; };
        }
    }
}

for my $role ( $owner, $runtime ) {
    $admin->do( 'CREATE ROLE '
          . $admin->quote_identifier($role)
          . ' LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS NOINHERIT'
    );
}
my $quoted_owner = $admin->quote_identifier($owner);
$admin->do("GRANT USAGE ON SCHEMA api, public TO $quoted_owner");
$admin->do("GRANT ALL ON ALL TABLES IN SCHEMA public TO $quoted_owner");
$admin->do("GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO $quoted_owner");
$admin->do(
    "GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA api, public TO $quoted_owner");
for my $operation ( @{ $catalogue->names } ) {
    my $entry = $catalogue->function($operation);
    $admin->do( 'ALTER FUNCTION '
          . $entry->{function} . '('
          . join( ', ', @{ $entry->{types} } )
          . ") OWNER TO $quoted_owner" );
}
my $command = GPForum::Command::ApiRole->new( dbh => $admin );
my ( $plan_status, $plan_text ) =
  _run( $command, '--role', $runtime, '--json' );
is( $plan_status, 0, 'the default command plans successfully' );
my $plan = decode_json($plan_text);
is( $plan->{mode}, 'plan', 'the JSON result identifies the nonmutating plan' );
like(
    join( q{ }, @{ $plan->{statements} } ),
    qr/GRANT [ ] EXECUTE [ ] ON [ ] FUNCTION [ ] api[.]/msx,
    'the plan names concrete versioned signatures'
);
is(
    scalar $admin->selectrow_array(
        q{SELECT has_schema_privilege(?, 'api', 'USAGE')},
        undef, $runtime
    ),
    0,
    'planning grants no access'
);
my ( $apply_status, $apply_text ) =
  _run( $command, '--role', $runtime, '--apply', '--json' );
is( $apply_status, 0, 'the command provisions the reviewed role' );
is(
    decode_json($apply_text)->{functions},
    scalar @{ $catalogue->names },
    'the JSON result reports all granted entry points'
);
$connection = DBI->connect( $database->dsn, $runtime, q{},
    { RaiseError => 1, PrintError => 0, AutoCommit => 1 } );
throws_ok { $connection->selectrow_array('SELECT username FROM users LIMIT 1') }
qr/permission [ ] denied/msx, 'the provisioned login cannot read a forum table';
my $entry = $catalogue->function('ops_partition_horizon');
my $rows  = $connection->selectall_arrayref( $entry->{sql}, { Slice => {} } );
ok( @{$rows}, 'a permitted stored function reads through its ordinary owner' );
my $config = GPForum::Config->new(
    database_dsn            => 'dbi:Pg:dbname=runtime_must_not_be_used',
    database_user           => 'runtime_must_not_be_used',
    admin_database_dsn      => $database->dsn,
    admin_database_user     => $ENV{GPFORUM_DATABASE_USER}     // 'gpforum',
    admin_database_password => $ENV{GPFORUM_DATABASE_PASSWORD} // q{},
);
my ($configured_status) =
  _run( GPForum::Command::ApiRole->new( config => $config ),
    '--role', $runtime, '--plan', '--json' );
is( $configured_status, 0,
    'configured provisioning uses the separate administrative connection' );
done_testing();

sub _run ( $command, @arguments ) {
    my $text = q{};
    open my $output, '>', \$text or croak 'cannot capture command output';
    local *STDOUT = $output;
    my $status = $command->run(@arguments);
    close $output or croak 'cannot close command output';
    return ( $status, $text );
}

1;
