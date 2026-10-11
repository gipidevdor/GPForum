# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause
package main;
use v5.40;
use Carp           qw(croak);
use Cwd            qw(abs_path);
use English        qw(-no_match_vars);
use File::Basename qw(basename);
use File::Copy     qw(copy);
use File::Path     qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use JSON::PP;
use POSIX qw(setsid);
use Test::More;
use lib "$FindBin::Bin/../script/lib";
use lib "$FindBin::Bin/lib";
use GPForum::PostgreSQL::PITR;
use GPForum::Performance::CommandError;
use GPForum::Performance::Support
  qw(write_json read_json run_bounded monotonic root_dir);
use GPForum::Test::ReplacedSubs qw(with_replaced_subs);
our $VERSION = '0.001';

# Tests use an explicit fixture runner; they do not claim a live PostgreSQL restore.
use constant {    ## no critic (ValuesAndExpressions::ProhibitConstantPragma)
    PRIVATE_MODE         => 0o700,
    INITIAL_COUNT        => 3,
    PHASE_COUNT          => 5,
    EXIT_SHIFT           => 8,
    SHA_LENGTH           => 40,
    PROCESS_TEST_TIMEOUT => 5,
    LEGACY_PORT          => 55_901,
    FLAG_PORT            => 55_902,
};
my $directory = tempdir( CLEANUP => 1 );
my $segment   = '000000010000000000000002';
my @bodies    = ( 'before the backup', 'kept: written before the target' );

sub write_file ( $path, $content ) {
    open my $handle, '>', $path or croak 'Cannot create fixture';
    print {$handle} $content or croak 'Cannot write fixture';
    close $handle            or croak 'Cannot close fixture';
    return undef;
}

sub read_file ($path) {
    open my $handle, '<', $path or croak 'Cannot read fixture';
    my $raw = do { local $INPUT_RECORD_SEPARATOR = undef; <$handle> };
    close $handle or croak 'Cannot close fixture';
    return $raw;
}

sub empty_directory ($path) {
    opendir my $handle, $path or croak 'Cannot inventory fixture';
    my @files = grep { $_ ne q{.} && $_ ne q{..} } readdir $handle;
    closedir $handle or croak 'Cannot close fixture inventory';
    return !@files;
}

sub fixture_sql ( $state, $sql, $environment ) {
    return '18.6' if $sql eq 'SHOW server_version';
    return '2026-10-11 10:00:00.123456+00'
      if $sql eq 'SELECT clock_timestamp()';
    return $segment if $sql eq 'SELECT pg_walfile_name(pg_current_wal_lsn())';
    return $state->{recovered} ? '2' : '3'
      if $sql eq 'SELECT count(*) FROM posts';
    return '0' if $sql eq 'SELECT pg_is_in_recovery()::int';
    if ( $sql =~ /pg_stat_archiver/msx ) {
        return '0' if $state->{archive_missing};
        write_file(
            File::Spec->catfile(
                $environment->{GPFORUM_PITR_WORKSPACE},
                'archive', $segment
            ),
            'fixture WAL'
        );
        return '1';
    }
    if ( $sql =~ /json_agg/msx ) {
        return JSON::PP->new->encode(
            $state->{wrong_rows}
            ? [ 'before the backup', 'dropped: written after the target' ]
            : \@bodies
        );
    }
    return q{};
}

sub fixture_command ( $state, $command, $control ) {
    $state->{environment} = $control->{env};
    push @{ $state->{commands} }, $command;
    my $tool = basename( $command->[0] );
    return "$tool (PostgreSQL) 18.6\n"     if $command->[-1] eq '--version';
    return fixture_git( $state, $command ) if $tool eq 'git';
    if ( $tool eq 'initdb' ) {
        if ( $state->{interrupt} ) { kill 'TERM', $PROCESS_ID; }
        croak GPForum::Performance::CommandError->new( 'synthetic timeout',
            1, undef )
          if $state->{timeout};
        make_path( $command->[2] );
        write_file( File::Spec->catfile( $command->[2], 'postgresql.conf' ),
            q{} );
    }
    if ( $tool eq 'pg_basebackup' ) {
        my $root = $control->{env}->{GPFORUM_PITR_WORKSPACE};
        make_path( File::Spec->catdir( $root, 'backup' ) );
        copy(
            File::Spec->catfile( $root, qw(data postgresql.conf) ),
            File::Spec->catfile( $root, qw(backup postgresql.conf) )
        ) or croak 'Cannot copy fixture backup';
    }
    if ( $tool eq 'pg_verifybackup' && $state->{bad_manifest} ) {
        croak GPForum::Performance::CommandError->new(
            'password=private-pitr-fixture invalid manifest',
            0, 1 );
    }
    return fixture_sql( $state, $command->[-1], $control->{env} )
      if $tool eq 'psql';
    return q{};
}

sub fixture_git ( $state, $command ) {
    croak 'fixture Git unavailable' if $state->{source_unavailable};
    return 'a' x SHA_LENGTH         if $command->[-1] eq 'HEAD';
    return $state->{source_status} // q{};
}

sub cli_fixture ( $environment, $arguments ) {
    local $ENV{GPFORUM_PITR_PORT} = $environment->{GPFORUM_PITR_PORT};
    local $ENV{GPFORUM_PITR_DIR}  = $environment->{GPFORUM_PITR_DIR};
    local $ENV{PATH}              = q{};
    my ( $output, $diagnostic ) = ( q{}, q{} );
    open my $out, '>', \$output     or croak 'Cannot capture CLI output';
    open my $err, '>', \$diagnostic or croak 'Cannot capture CLI diagnostics';
    my $status;
    {
        local *STDOUT = $out;
        local *STDERR = $err;
        $status = GPForum::PostgreSQL::PITR::main( @{$arguments} );
    }
    close $out or croak 'Cannot close CLI output';
    close $err or croak 'Cannot close CLI diagnostics';
    return { status => $status, out => $output, err => $diagnostic };
}

sub fixture_source ($state) {
    my $tools = GPForum::PostgreSQL::PITR->can('_tools');
    return with_replaced_subs(
        'GPForum::PostgreSQL::PITR',
        {
            _tool => sub ($name) { return $name; },
        },
        sub {
            return with_replaced_subs(
                'GPForum::Test::PITRFixture',
                { _tools => $tools },
                sub { return fixture($state)->run; }
            );
        }
    );
}

sub fixture ( $state = {}, $options = {} ) {
    my $runner = sub ( $command, $control ) {
        return fixture_command( $state, $command, $control );
    };
    return GPForum::Test::PITRFixture->new(
        { state => $state, runner => $runner, %{$options} } );
}

my $quoted = GPForum::PostgreSQL::PITR::shell_quote(q{a b'c});
is( $quoted, q{'a b'"'"'c'}, 'shell paths quote spaces and apostrophes' );
is(
    GPForum::PostgreSQL::PITR::conf_quote($quoted),
    q{'''a b''"''"''c'''},
    'PostgreSQL config adds its own quoting layer'
);

my $state   = {};
my $success = fixture($state)->run;
is( $success->{status}, 'pass', 'simulated complete verified recovery' );
is( $success->{dataset}->{rows_before},
    INITIAL_COUNT, 'incident count measured' );
is_deeply( $success->{dataset}->{recovered_bodies},
    \@bodies, 'exact initial and retained bodies' );
ok( $success->{checks}->{manifest_verified}, 'manifest verification executed' );
ok( $success->{checks}->{archive_completed},
    'archiver plus file evidence checked before recovery' );
ok(
    $success->{cleanup}->{workspace_removed},
    'success removes own temporary cluster'
);
is( scalar @{ $success->{phases} }, PHASE_COUNT, 'all five phases measured' );
ok(
    defined $success->{recovery_seconds},
    'recovery duration separately recorded'
);
ok( GPForum::PostgreSQL::PITR::validate($success),
    'successful evidence validates' );

my $source_state = { source_status => " M script/pitr-drill\n" };
my $dirty_source = fixture_source($source_state);
ok(
    $dirty_source->{metadata}->{source_dirty},
    'local source changes explicitly marked'
);
is(
    $dirty_source->{metadata}->{commit},
    'a' x SHA_LENGTH,
    'source commit retained separately from dirty flag'
);
my @git_commands = grep { $_->[0] eq 'git' } @{ $source_state->{commands} };
is_deeply(
    [ map { [ $_->[1], $_->[2] ] } @git_commands ],
    [ [ '-C', root_dir() ], [ '-C', root_dir() ] ],
    'both provenance commands explicitly target the source repository'
);
ok( !fixture_source( {} )->{metadata}->{source_dirty},
    'clean checkout explicitly marked' );
ok(
    !defined fixture_source( { source_unavailable => 1 } )->{metadata}
      ->{source_dirty},
    'unavailable Git provenance remains unknown'
);

{
    local $ENV{GPFORUM_DATABASE_DSN} =
      'dbi:Pg:dbname=production;host=production';
    local $ENV{PGPASSWORD} = 'private-pitr-fixture';
    local $ENV{PGOPTIONS}  = '-c search_path=private';
    local $ENV{PGSERVICE}  = 'production';
    my $isolated = {};
    fixture($isolated)->run;
    ok(
        !exists $isolated->{environment}->{PGPASSWORD}
          && !exists $isolated->{environment}->{PGSERVICE}
          && !exists $isolated->{environment}->{PGOPTIONS}
          && !exists $isolated->{environment}->{GPFORUM_DATABASE_DSN},
'child environment excludes credentials, client overrides and application DSN'
    );
}

for my $case (
    [ { bad_manifest    => 1 }, 'operation_failed',        'base_backup' ],
    [ { archive_missing => 1 }, 'archive_not_completed',   'archive_target' ],
    [ { wrong_rows      => 1 }, 'recovered_data_mismatch', 'recover_target' ],
    [ { timeout         => 1 }, 'deadline_exceeded',       'initialize' ],
    [ { interrupt       => 1 }, 'interrupted',             'initialize' ]
  )
{
    my ( $configuration, $reason, $phase ) = @{$case};
    my $evidence = fixture($configuration)->run;
    is( $evidence->{status}, 'fail', "$reason never claims PASS" );
    is( $evidence->{reason}, $reason,
        "$reason preserved with generic diagnostic" );
    is( $evidence->{phases}->[-1]->{name},
        $phase, 'failed phase retained alongside completed phases' );
    is( $evidence->{phases}->[-1]->{status}, 'fail', 'failure phase explicit' );
    ok(
        $evidence->{cleanup}->{workspace_removed},
        'failure cleanup removes only own workspace'
    );
    unlike(
        JSON::PP->new->encode($evidence),
        qr/private-pitr-fixture|password=/msx,
        'public evidence has no raw diagnostic secret'
    );
}

my $occupied = File::Spec->catdir( $directory, 'occupied' );
make_path($occupied);
write_file( File::Spec->catfile( $occupied, 'preserve' ), 'application bytes' );
my $refused = fixture( {}, { dir => $occupied } )->run;
is( $refused->{reason}, 'owned_workspace_refused',
    'occupied directory rejected' );
is(
    read_file( File::Spec->catfile( $occupied, 'preserve' ) ),
    'application bytes',
    'existing bytes unchanged'
);
my $link = File::Spec->catfile( $directory, 'link' );
symlink $occupied, $link or croak 'Cannot make fixture symlink';
is( fixture( {}, { dir => $link } )->run->{reason},
    'owned_workspace_refused', 'symlink workspace rejected' );
ok( -l $link, 'rejected link preserved' );

sub check_legacy_adapter ( $directory, $occupied, $link ) {
    my $legacy_directory = File::Spec->catdir( $directory, 'legacy-owned' );
    my $legacy           = cli_fixture(
        {
            GPFORUM_PITR_PORT => LEGACY_PORT,
            GPFORUM_PITR_DIR  => $legacy_directory
        },
        [ '--json', '--keep' ]
    );
    is( $legacy->{status}, 1,
        'legacy settings reach safe missing-tool failure' );
    my $legacy_evidence = JSON::PP->new->decode( $legacy->{out} );
    is( $legacy_evidence->{configuration}->{port},
        LEGACY_PORT, 'deprecated port becomes actual numeric configuration' );
    is( $legacy_evidence->{reason},
        'missing_required_tool',
        'legacy directory accepted without bypassing mandatory tools' );
    ok( -d $legacy_directory && $legacy_evidence->{cleanup}->{server_stopped},
        'legacy keep directory retained without a server' );
    like(
        $legacy->{err},
        qr/GPFORUM_PITR_PORT[ ]is[ ]deprecated;[ ]use[ ]--port/msx,
        'deprecated port warns with replacement flag'
    );
    like(
        $legacy->{err},
        qr/GPFORUM_PITR_DIR[ ]is[ ]deprecated;[ ]use[ ]--dir/msx,
        'deprecated directory warns with replacement flag'
    );
    ok(
        GPForum::PostgreSQL::PITR::validate($legacy_evidence),
        'legacy configuration produces valid failure evidence'
    );

    my $flag_directory = File::Spec->catdir( $directory, 'flag-owned' );
    my $precedence     = cli_fixture(
        { GPFORUM_PITR_PORT => 'many', GPFORUM_PITR_DIR => $occupied },
        [ '--port', FLAG_PORT, '--dir', $flag_directory, '--json' ]
    );
    my $flag_evidence = JSON::PP->new->decode( $precedence->{out} );
    is( $precedence->{status}, 1,
        'explicit flags override invalid legacy defaults' );
    is( $flag_evidence->{configuration}->{port},
        FLAG_PORT, 'explicit port takes precedence' );
    is( $flag_evidence->{reason}, 'missing_required_tool',
        'explicit new directory takes precedence over occupied legacy directory'
    );
    is(
        read_file( File::Spec->catfile( $occupied, 'preserve' ) ),
        'application bytes',
        'overridden legacy directory remains untouched'
    );

    for my $invalid (qw(many 12.5 0 65536)) {
        my $result =
          cli_fixture( { GPFORUM_PITR_PORT => $invalid }, ['--json'] );
        is( $result->{status}, 2,
            "invalid legacy port $invalid is usage error" );
        is( $result->{out}, q{},
            'invalid port starts no drill and emits no evidence' );
    }

    for my $path ( $occupied, $link ) {
        my $result = cli_fixture( { GPFORUM_PITR_DIR => $path }, ['--json'] );
        is( $result->{status}, 1,
            'unsafe legacy workspace fails without running tools' );
        is(
            JSON::PP->new->decode( $result->{out} )->{reason},
            'owned_workspace_refused',
            'unsafe legacy workspace uses modern JSON failure'
        );
    }
    is(
        read_file( File::Spec->catfile( $occupied, 'preserve' ) ),
        'application bytes',
        'refused legacy directory preserves existing bytes'
    );
    ok( -l $link, 'refused legacy symlink remains unchanged' );
    my $empty_legacy =
      cli_fixture( { GPFORUM_PITR_PORT => q{}, GPFORUM_PITR_DIR => q{} },
        ['--json'] );
    unlike(
        $empty_legacy->{err},
        qr/is[ ]deprecated/msx,
        'empty legacy environment does not emit deprecation warning'
    );
    return undef;
}

check_legacy_adapter( $directory, $occupied, $link );

my $empty = File::Spec->catdir( $directory, 'empty' );
mkdir $empty, PRIVATE_MODE or croak 'Cannot make empty fixture';
ok( fixture( {}, { dir => $empty } )->run->{cleanup}->{workspace_removed},
    'preexisting empty directory cleaned' );
ok(
    -d $empty && empty_directory($empty),
    'preexisting empty directory remains empty'
);
my $kept     = File::Spec->catdir( $directory, q{kept directory's data} );
my $kept_run = fixture( {}, { dir => $kept, keep => 1 } )->run;
ok(
    $kept_run->{cleanup}->{server_stopped},
    'keep still requires stopped server'
);
ok(
    !$kept_run->{cleanup}->{workspace_removed} && -d $kept,
    'keep retains diagnostics and fixture only'
);
my $saved = File::Spec->catfile( $directory, 'evidence.json' );
write_json( $saved, $success );
is( GPForum::PostgreSQL::PITR::main( '--validate', $saved ),
    0, 'CLI schema check succeeds without PostgreSQL' );
my $forged = read_json($saved);
$forged->{checks}->{manifest_verified} = JSON::PP::false;
my $error;
try { GPForum::PostgreSQL::PITR::validate($forged); }
catch ($caught) { $error = $caught; };
like(
    "$error",
    qr/unverified[ ]checks/msx,
    'PASS cannot hide unexecuted manifest verification'
);
$forged = read_json($saved);
$forged->{metadata}->{unexpected} = 'value';
try { GPForum::PostgreSQL::PITR::validate($forged); }
catch ($caught) { $error = $caught; };
like( "$error", qr/unexpected/msx,
    'schema rejects unversioned metadata drift' );

for my $alter (
    [ sub ($report) { $report->{phases} = []; }, qr/missing[ ]phases/msx ],
    [
        sub ($report) { $report->{dataset}->{rows_after} = 1; },
        qr/inconsistent[ ]recovered[ ]data/msx
    ],
    [
        sub ($report) {
            $report->{metadata}->{tools}->{pg_verifybackup} =
              'pg_verifybackup (PostgreSQL) 17.11';
        },
        qr/inconsistent[ ]tool[ ]versions/msx
    ],
  )
{
    my $report = read_json($saved);
    $alter->[0]->($report);
    my $caught;
    try { GPForum::PostgreSQL::PITR::validate($report); }
    catch ($failure) { $caught = $failure; };
    like( "$caught", $alter->[1],
        'PASS rejects incomplete or inconsistent executed evidence' );
}

# Exercise actual owned-process cleanup, independently of installed PG binaries.
my $owned           = GPForum::Test::PITRProcessFailure->new;
my $started         = monotonic();
my $process_failure = $owned->run;
is( $process_failure->{status},
    'fail', 'owned server process interruption fails drill' );
ok(
    !kill( 0, $owned->{fixture_pid} ),
    'owned persistent server process reaped'
);
cmp_ok( monotonic() - $started,
    '<', PROCESS_TEST_TIMEOUT, 'failure cleanup bounded' );

{
    local $ENV{PATH}              = q{};
    local $ENV{GPFORUM_PITR_PORT} = undef;
    local $ENV{GPFORUM_PITR_DIR}  = undef;
    open my $child, q{-|}, $EXECUTABLE_NAME, 'script/pitr-drill', '--json'
      or croak 'Cannot launch missing-tool fixture';
    my $output = do { local $INPUT_RECORD_SEPARATOR = undef; <$child> };
    my $closed = close $child;
    ok( !$closed && ( $CHILD_ERROR >> EXIT_SHIFT ) == 1,
        'failed real CLI exits one' );
    my $missing = JSON::PP->new->decode($output);
    is( $missing->{status}, 'fail',
        'missing tools fail real CLI with nonzero status' );
    is( $missing->{reason}, 'missing_required_tool',
        'missing tool diagnostic explicit' );
}

done_testing;

package GPForum::Test::PITRFixture {    ## no critic (Modules::ProhibitMultiplePackages) -- isolated test double, no application loading
    use v5.40;
    use parent -norequire, 'GPForum::PostgreSQL::PITR';

    sub _tools ($self) {                ## no critic (Subroutines::ProhibitUnusedPrivateSubroutines) -- overrides the drill step invoked by its base class
        $self->{tools} = { map { $_ => $_ }
              qw(initdb postgres pg_ctl pg_basebackup pg_verifybackup psql) };
        $self->{evidence}->{metadata}->{tools} =
          { map { $_ => "$_ (PostgreSQL) 18.6" } keys %{ $self->{tools} } };
        return undef;
    }

    sub _start ( $self, $name ) {       ## no critic (Subroutines::ProhibitUnusedPrivateSubroutines) -- overrides the drill step invoked by its base class
        $self->{options}->{state}->{recovered} = $name eq 'recovery.log';
        return undef;
    }

    sub _stop ($self) {                 ## no critic (Subroutines::ProhibitUnusedPrivateSubroutines) -- overrides the drill step invoked by its base class
        return undef;
    }

    sub _poll ( $self, $predicate ) {    ## no critic (Subroutines::ProhibitUnusedPrivateSubroutines) -- overrides the drill step invoked by its base class
        return $predicate->();
    }

}

package GPForum::Test::PITRProcessFailure {    ## no critic (Modules::ProhibitMultiplePackages) -- owned process cleanup fixture
    use v5.40;
    use Carp    qw(croak);
    use English qw(-no_match_vars);
    use POSIX   qw(setsid);
    use parent -norequire, 'GPForum::Test::PITRFixture';

    sub _execute ($self) {    ## no critic (Subroutines::ProhibitUnusedPrivateSubroutines) -- overrides the drill step invoked by its base class
        my $pid = fork;
        croak 'Cannot fork owned process fixture' if !defined $pid;
        if ( !$pid ) {
            setsid();
            exec {$EXECUTABLE_NAME} $EXECUTABLE_NAME, '-e', 'sleep 60'
              or POSIX::_exit(1);
        }
        $self->{fixture_pid} = $pid;
        push @{ $self->{servers} }, $pid;
        croak 'synthetic owned server failure';
    }
}
1;
