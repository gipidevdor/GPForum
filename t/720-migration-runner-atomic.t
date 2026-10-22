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
# unrecorded, to be run a second time by the next deploy. A migration
# numbered below one already applied is refused, and so is a database that
# records migrations the tree does not have: the 0.x chain's, which the 1.0
# baseline replaced (ADR 0150), or a newer release's.

subtest 'the record joins the transaction of the file' => sub {
    my ( $runner, $dbh ) = _runner(
        {
            '1119_one_transaction.sql' =>
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
        qr/CREATE [ ] TABLE [ ] t .* $RECORD [^;]* '1119', [ ] 'one/msx,
        'the version is written after the migration'
    );
    like(
        $sent,
        qr/$RECORD [^;]* 'o''brien', [ ] [(]extract/msx,
        'with who applied it, the name quoted, and how long it took'
    );
    is( scalar( () = $sent =~ /$RECORD/gmsx ), 1, 'in one row' );
    like( $sent, qr/;\s* COMMIT; \s* \z/msx, 'before its COMMIT' );
    is( scalar( () = $sent =~ /^COMMIT;/gmsx ), 1, 'which is the only one' );
};

subtest 'a file with no transaction of its own is given one' => sub {
    my ( $runner, $dbh ) =
      _runner( { '1119_bare.sql' => "CREATE INDEX i ON t (a);\n" } );
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
                '1119_concurrent.sql' => "-- gpforum:no-transaction\n"
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
        [ 'DROP', 'INDEX', 'CREATE', 'INDEX', 'INSERT', 'INTO' ],
        'each statement, then the record'
    );
};

subtest 'a file of several transactions is refused' => sub {
    my $several = "BEGIN;\nSELECT 1;\nCOMMIT;\nBEGIN;\nSELECT 2;\nCOMMIT;\n";
    my ( $refused, $dbh ) = _runner( { '1119_several.sql' => $several } );
    my $error = _error( sub { $refused->apply_pending } );
    ok( GPForum::X::Argument->caught($error), 'as a wrong argument' );
    like( "$error", qr/1119 .* more [ ] than [ ] one [ ] transaction/msx,
        'naming it' );
    is_deeply( $dbh->executed, [], 'before anything runs' );
};

subtest 'a migration numbered below an applied one is refused' => sub {
    my %files = map { ( "${_}_m$_.sql" => "BEGIN;\nSELECT $_;\nCOMMIT;\n" ) }
      qw(1110 1119 1121);
    my ( $late, $dbh ) = _runner( \%files, [qw(1110 1121)] );
    my $error = _error( sub { $late->apply_pending } );
    ok( GPForum::X::Check->caught($error), 'as a failed check' );
    like( "$error", qr/1121 .* 1119/msx, 'naming both' );
    is_deeply( $dbh->executed, [], 'before anything runs' );

    my ( $status, $said ) = _checked($late);
    is( $status, 1, 'migrate --check fails on it too' );
    like( $said, qr/1121 .* 1119/msx, 'and says why' );
};

subtest 'a database the 0.x chain built is refused' => sub {
    my %files = map { ( "${_}_m$_.sql" => "BEGIN;\nSELECT $_;\nCOMMIT;\n" ) }
      qw(1000 1001);
    my ( $old, $dbh ) = _runner( \%files, [qw(001 052 135)] );
    my $error = _error( sub { $old->apply_pending } );
    ok( GPForum::X::Check->caught($error), 'as a failed check' );
    like(
        "$error",
        qr/before [ ] 1[.]0 [ ] [(]migrations [ ] 001 [ ] to [ ] 135[)]/msx,
        'saying which history it holds'
    );
    like(
        "$error",
        qr/create [ ] an [ ] empty [ ] database/msx,
        'and what to do instead'
    );
    is_deeply( $dbh->executed, [], 'before anything runs' );

    my ( $status, $said ) = _checked($old);
    is( $status, 1, 'migrate --check fails on it too' );
    like( $said, qr/before [ ] 1[.]0/msx, 'and says why' );
};

subtest 'a database a newer release migrated is refused' => sub {
    my %files = map { ( "${_}_m$_.sql" => "BEGIN;\nSELECT $_;\nCOMMIT;\n" ) }
      qw(1000 1001);
    my ( $newer, $dbh ) = _runner( \%files, [qw(1000 1001 1024)] );
    my $error = _error( sub { $newer->apply_pending } );
    ok( GPForum::X::Check->caught($error), 'as a failed check' );
    like(
        "$error",
        qr/does [ ] not [ ] have [ ] [(]1024[)] .* newer/msx,
        'naming what it does not know'
    );
    is_deeply( $dbh->executed, [], 'before anything runs' );
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

# What migrate --check says on a runner, and its status.
sub _checked ($runner) {
    my ( $status, $said ) = ( undef, q{} );
    open my $captured, '>', \$said or croak 'cannot capture';
    {
        local *STDOUT = $captured;
        local *STDERR = $captured;
        $status =
          GPForum::Command::Migrate->new( runner => $runner )->run('--check');
    }
    close $captured or croak 'cannot capture';

    return ( $status, $said );
}

sub _error ($code) {
    my $error;
    try { $code->() } catch ($caught) {
        $error = $caught
    };

    return $error;
}

1;
