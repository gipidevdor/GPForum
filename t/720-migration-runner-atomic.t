# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Carp qw(croak);
use Const::Fast;
use File::Temp qw(tempdir);
use Mojo::File qw(path);
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Command::Migrate;
use GPForum::Migration::Plan;
use GPForum::Migration::Runner;
use GPForum::Test::MigrationDbh;
use GPForum::Test::MigrationSchema;
use GPForum::Test::MigrationStorage;
use GPForum::X::Argument;
use GPForum::X::Check;

our $VERSION = '0.001';

const my $RECORD => qr/INSERT [ ] INTO [ ] schema_versions/msx;

# A migration and the row that says it ran commit together: the runner
# writes the schema_versions row inside the file's own transaction, so a
# crash between the two can no longer leave a migration applied and
# unrecorded, to be run a second time by the next deploy. And a migration
# numbered below one already applied is refused, unless it is a gap the
# history lists.

subtest 'the record joins the transaction of the file' => sub {
    my ( $runner, $dbh ) = _runner(
        {
            '119_one_transaction.sql' =>
              "-- a comment\nBEGIN;\nCREATE TABLE t (a int);\nCOMMIT;\n"
        },
        [],
        q{o'brien},
    );
    $runner->apply_pending;
    is( scalar @{ $dbh->executed }, 1, 'one statement for the whole file' );
    my $sent = $dbh->executed->[0]{statement};
    like(
        $sent,
        qr/CREATE [ ] TABLE [ ] t .* $RECORD [^;]* '119', [ ] 'one/msx,
        'the version is written after the migration'
    );
    like(
        $sent,
        qr/INSERT [ ] INTO [ ] migration_safety [^;]* 'o''brien'/msx,
        'its safety row too, the names quoted'
    );
    like( $sent, qr/;\s* COMMIT; \s* \z/msx, 'and both before its COMMIT' );
    is( scalar( () = $sent =~ /^COMMIT;/gmsx ), 1, 'which is the only one' );
};

subtest 'a file with no transaction of its own is given one' => sub {
    my ( $runner, $dbh ) =
      _runner( { '119_bare.sql' => "CREATE INDEX i ON t (a);\n" } );
    $runner->apply_pending;
    my $sent = $dbh->executed->[0]{statement};
    like( $sent, qr/\A BEGIN; \s* CREATE [ ] INDEX/msx, 'opened before it' );
    like(
        $sent,
        qr/INSERT [ ] INTO [ ] schema_versions .* COMMIT; \s* \z/msx,
        'and closed after its record'
    );
};

subtest 'a no-transaction file is recorded after its statements' => sub {
    my ( $runner, $dbh ) = _runner(
        {
                '119_concurrent.sql' => "-- gpforum:no-transaction\n"
              . "DROP INDEX CONCURRENTLY IF EXISTS i;\n"
              . "CREATE INDEX CONCURRENTLY i ON t (a);\n"
        }
    );
    $runner->apply_pending;
    is_deeply(
        [
            map { ( split /\s/msx, $_->{statement} )[ 0, 1 ] }
              @{ $dbh->executed }
        ],
        [
            'DROP',   'INDEX', 'CREATE', 'INDEX',
            'INSERT', 'INTO',  'INSERT', 'INTO'
        ],
        'each statement, then the records'
    );
};

subtest 'a file of several transactions runs only where the history has one' =>
  sub {
    my $several = "BEGIN;\nSELECT 1;\nCOMMIT;\nBEGIN;\nSELECT 2;\nCOMMIT;\n";
    my ( $refused, $dbh ) = _runner( { '119_several.sql' => $several } );
    my $error = _error( sub { $refused->apply_pending } );
    ok( GPForum::X::Argument->caught($error), 'a new one is refused' );
    like( "$error", qr/119 .* more [ ] than [ ] one [ ] transaction/msx,
        'naming it' );
    is_deeply( $dbh->executed, [], 'before anything runs' );

    my ( $listed, $listed_dbh ) = _runner( { '049_several.sql' => $several } );
    $listed->apply_pending;
    is( $listed_dbh->executed->[0]{statement},
        $several, '049, written before the rule, runs as it is' );
    like(
        $listed_dbh->executed->[1]{statement},
        qr/\A INSERT [ ] INTO [ ] schema_versions/msx,
        'and is recorded after'
    );
  };

subtest 'a migration numbered below an applied one is refused' => sub {
    my %files = map { ( "${_}_m$_.sql" => "BEGIN;\nSELECT $_;\nCOMMIT;\n" ) }
      qw(110 119 120 121);
    my ( $late, $dbh ) = _runner( \%files, [qw(110 121)] );
    my $error = _error( sub { $late->apply_pending } );
    ok( GPForum::X::Check->caught($error), 'as a failed check' );
    like( "$error", qr/121 .* 119/msx, 'naming both' );
    unlike( "$error", qr/120/msx, 'but not a listed gap' );
    is_deeply( $dbh->executed, [], 'before anything runs' );

    my ( $status, $said ) = ( undef, q{} );
    {
        open my $captured, '>', \$said or croak 'cannot capture';
        local *STDOUT = $captured;
        local *STDERR = $captured;
        $status =
          GPForum::Command::Migrate->new( runner => $late )->run('--check');
        close $captured or croak 'cannot capture';
    }
    is( $status, 1, 'migrate --check fails on it too' );
    like( $said, qr/121 .* 119/msx, 'and says why' );

    delete $files{'119_m119.sql'};
    my ( $gap, $gap_dbh ) = _runner( \%files, [qw(110 121)] );
    is_deeply( [ map { $_->{version} } @{ $gap->apply_pending } ],
        ['120'], '120, a listed gap, runs after 121' );
};

done_testing();

sub _runner ( $files, $applied = [], $applied_by = 'test' ) {
    my $directory = path( tempdir( CLEANUP => 1 ) );
    for my $name ( keys %{$files} ) {
        $directory->child($name)->spew( $files->{$name} );
    }
    my $dbh =
      GPForum::Test::MigrationDbh->new( applied_versions => [ @{$applied} ] );
    my $runner = GPForum::Migration::Runner->new(
        applied_by => $applied_by,
        plan   => GPForum::Migration::Plan->new( directory => "$directory" ),
        schema => GPForum::Test::MigrationSchema->new(
            storage => GPForum::Test::MigrationStorage->new( dbh => $dbh )
        ),
    );

    return ( $runner, $dbh );
}

sub _error ($code) {
    my $error;
    try { $code->() } catch ($caught) {
        $error = $caught
    };

    return $error;
}

1;
