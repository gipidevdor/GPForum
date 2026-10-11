# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause
package GPForum::PostgreSQL::PITR;
use v5.40;
use Carp           qw(carp croak);
use Cwd            qw(abs_path);
use English        qw(-no_match_vars);
use Fcntl          qw(O_WRONLY O_CREAT O_EXCL);
use File::Basename qw(dirname);
use File::Path     qw(remove_tree);
use File::Spec;
use File::Temp   qw(tempdir);
use Getopt::Long qw(GetOptionsFromArray);
use JSON::PP;
use List::Util  qw(any min);
use POSIX       qw(setsid strftime);
use Time::HiRes qw(sleep);
use GPForum::Performance::Support
  qw(root_dir monotonic run_bounded terminate read_json redact);
use GPForum::Performance::Schema qw(schema_validate secrets);

# Bootstrap validation must work before application dependency installation.
use constant {    ## no critic (ValuesAndExpressions::ProhibitConstantPragma)
    DEFAULT_PORT    => 55_444,
    MAX_PORT        => 65_535,
    DEFAULT_TIMEOUT => 180,
    MAX_TIMEOUT     => 1800,
    MIN_TIMEOUT     => 15,
    CLEANUP_RESERVE => 8,
    COMMAND_LIMIT   => 90,
    POLL_LIMIT      => 25,
    POLL_INTERVAL   => 0.1,
    PRIVATE_MODE    => 0o700,
    FILE_MODE       => 0o600,
    PRIVATE_UMASK   => 0o077,
    LOG_LIMIT       => 200_000,
    CHILD_FAILURE   => 126,
};
our $VERSION = '0.001';
my @TOOLS    = qw(initdb postgres pg_ctl pg_basebackup pg_verifybackup psql);
my @EXPECTED = (
    'before the backup',
    'kept: written before the target',
    'dropped: written after the target',
);

sub new ( $class, $options = {} ) {
    return bless { options => $options, servers => [], sequence => 0 }, $class;
}

sub main (@arguments) {
    my %options = ( port => DEFAULT_PORT, timeout => DEFAULT_TIMEOUT );
    _deprecated_defaults( \%options );
    my $valid = GetOptionsFromArray(
        \@arguments, \%options, 'port=i',    'dir=s',
        'keep',      'json',    'timeout=f', 'validate=s',
        'help|h'
    );
    if ( !$valid || @arguments ) { carp _usage(); return 2; }
    if ( $options{help} ) {
        print _usage() or croak 'Cannot write usage';
        return 0;
    }
    if ( $options{validate} ) { return _validate_file( $options{validate} ); }
    if ( !_valid_options( \%options ) ) {
        carp "pitr-drill: invalid port or timeout\n";
        return 2;
    }
    $options{port} = 0 + $options{port};
    my $evidence = __PACKAGE__->new( \%options )->run;
    _display( $evidence, $options{json} );
    carp "pitr-drill: $evidence->{reason}\n" if $evidence->{status} ne 'pass';
    return $evidence->{status} eq 'pass' ? 0 : 1;
}

sub _display ( $evidence, $json_output ) {
    if ($json_output) {
        my $json = JSON::PP->new->canonical->pretty;
        print $json->encode($evidence)
          or croak 'Cannot write PITR evidence';
    }
    else {
        printf "pitr-drill status=%s reason=%s duration=%.3fs\n",
          $evidence->{status}, $evidence->{reason},
          $evidence->{duration_seconds}
          or croak 'Cannot write PITR evidence';
    }
    return undef;
}

sub _valid_options ($options) {
    return
         $options->{port} =~ /\A\d+\z/amsx
      && $options->{port} >= 1
      && $options->{port} <= MAX_PORT
      && $options->{timeout} >= MIN_TIMEOUT
      && $options->{timeout} <= MAX_TIMEOUT;
}

# Keep the documented pre-v0.3.0 adapter. Defaults are assigned before option
# parsing so explicit flags always win, including over invalid old values.
sub _deprecated_defaults ($options) {
    for my $name (qw(port dir)) {
        my $variable = 'GPFORUM_PITR_' . uc $name;
        my $value    = $ENV{$variable};
        next if !defined $value || $value eq q{};
        my $printed = redact($value);
        $printed =~ s/\r/\\r/gmsx;
        $printed =~ s/\n/\\n/gmsx;
        print {*STDERR}
          "pitr-drill: $variable is deprecated; use --$name $printed\n"
          or croak 'Cannot write deprecated setting warning';
        $options->{$name} = $value;
    }
    return undef;
}

sub _usage {
    return <<'USAGE';
Usage: script/pitr-drill [--port N] [--dir PATH] [--keep] [--json] [--timeout N]
       script/pitr-drill --validate FILE

Rehearse physical backup and point-in-time recovery in an owned temporary
PostgreSQL cluster. No application database or environment DSN is used.
--dir must be new or empty and cannot be a symlink. --keep preserves evidence
and cluster files, but always stops the server. --timeout defaults to 180s
(15..1800s), including an 8s cleanup reserve. --port defaults to 55444.
--json writes only schema-versioned evidence to stdout. --validate checks
schema, secret exclusion and pass invariants without PostgreSQL.
Exit status: 0 verified recovery/valid evidence, 1 failed drill (including a
refused occupied or symlink workspace), 2 malformed arguments.
USAGE
}

sub _validate_file ($path) {
    my $status = 0;
    try { validate( read_json($path) ); }
    catch ($error) { carp "pitr-drill: invalid evidence\n"; $status = 1; };
    return $status;
}

sub validate ($evidence) {
    my $path = File::Spec->catfile( root_dir(),
        qw(docs ops postgres-pitr-schema-v1.json) );
    schema_validate( $evidence, read_json($path) );
    secrets($evidence);
    if ( $evidence->{status} eq 'pass' ) {
        my $checks = $evidence->{checks};
        croak 'Passing PITR evidence has unverified checks'
          if !$checks->{manifest_verified}
          || !$checks->{archive_completed}
          || !$checks->{recovery_completed}
          || !$checks->{records_exact}
          || !$checks->{counts_exact}
          || !$evidence->{cleanup}->{server_stopped};
        croak 'Passing PITR evidence has no recovery timing'
          if !defined $evidence->{recovery_seconds};
        croak 'Passing PITR evidence contains a failed phase'
          if any { $_->{status} ne 'pass' } @{ $evidence->{phases} };
        _pass_invariants($evidence);
    }
    return 1;
}

sub _pass_invariants ($evidence) {
    my @expected =
      qw(tool_versions initialize base_backup archive_target recover_target);
    my @actual         = map { $_->{name} } @{ $evidence->{phases} };
    my $actual_order   = join q{,}, @actual;
    my $expected_order = join q{,}, @expected;
    croak 'Passing PITR evidence has missing phases'
      if $actual_order ne $expected_order;
    my $dataset  = $evidence->{dataset};
    my $expected = JSON::PP->new->encode( [ @EXPECTED[ 0, 1 ] ] );
    croak 'Passing PITR evidence has inconsistent recovered data'
      if !defined $dataset->{rows_before}
      || $dataset->{rows_before} != @EXPECTED
      || !defined $dataset->{rows_after}
      || $dataset->{rows_after} != 2
      || JSON::PP->new->encode( $dataset->{recovered_bodies} ) ne $expected;
    croak 'Passing PITR evidence has no archive target'
      if !defined $dataset->{target} || !defined $evidence->{archived_segment};
    _pass_versions($evidence);
    return 1;
}

sub _pass_versions ($evidence) {
    my $metadata = $evidence->{metadata};
    my ($major) = ( $metadata->{postgresql} // q{} ) =~ /\A(\d+)/msx;
    croak 'Passing PITR evidence has no server version' if !defined $major;
    for my $tool (@TOOLS) {
        my ($selected) =
          ( $metadata->{tools}->{$tool} // q{} ) =~ /PostgreSQL[)]\s+(\d+)/msx;
        croak 'Passing PITR evidence has inconsistent tool versions'
          if !defined $selected || $selected != $major;
    }
    return 1;
}

sub _evidence ($self) {
    return {
        schema_version   => 1,
        check            => 'pitr_drill',
        status           => 'fail',
        reason           => 'not_completed',
        recorded_at      => strftime( '%Y-%m-%dT%H:%M:%SZ', gmtime ),
        duration_seconds => 0,
        recovery_seconds => undef,
        metadata         => {
            commit       => undef,
            source_dirty => undef,
            postgresql   => undef,
            tools        => {}
        },
        configuration => {
            port            => $self->{options}->{port}    // DEFAULT_PORT,
            timeout_seconds => $self->{options}->{timeout} // DEFAULT_TIMEOUT,
            isolated_cluster       => JSON::PP::true,
            external_database_used => JSON::PP::false
        },
        dataset => {
            name             => 'pitr-three-row-fixture',
            rows_before      => undef,
            rows_after       => undef,
            recovered_bodies => [],
            target           => undef
        },
        checks => {
            map { $_ => JSON::PP::false }
              qw(manifest_verified archive_completed recovery_completed records_exact counts_exact)
        },
        phases  => [],
        cleanup => {
            server_stopped    => JSON::PP::false,
            workspace_removed => JSON::PP::false,
            kept => $self->{options}->{keep} ? JSON::PP::true : JSON::PP::false
        },
        secrets_redacted     => JSON::PP::true,
        private_beta_claimed => 0,
        residual_gaps        => [
'A three-row isolated drill does not measure production RPO or RTO.',
'Attachment files and application attachment metadata are not recovered by this fixture.',
'Off-host archive durability and production backup retention require operator verification.'
        ],
    };
}

sub run ($self) {
    $self->{started} = monotonic();
    $self->{deadline} =
      $self->{started} +
      ( $self->{options}->{timeout} // DEFAULT_TIMEOUT ) -
      CLEANUP_RESERVE;
    $self->{evidence} = $self->_evidence;
    my $old_umask = umask PRIVATE_UMASK;
    local $SIG{TERM} =
      sub { $self->{interrupted} = 1; croak 'drill_interrupted'; };
    local $SIG{INT} = $SIG{TERM};
    try {
        $self->_workspace;
        $self->_phase( 'tool_versions', sub { $self->_tools; } );
        $self->_execute;
        $self->{evidence}->{status} = 'pass';
        $self->{evidence}->{reason} = 'verified_target';
    }
    catch ($error) { $self->{evidence}->{reason} = $self->_reason($error); };
    {
        local $SIG{TERM} = 'IGNORE';
        local $SIG{INT}  = 'IGNORE';
        try { $self->_cleanup; }
        catch ($error) {
            $self->{evidence}->{status} = 'fail';
            $self->{evidence}->{reason} = 'cleanup_failed';
        };
    }
    umask $old_umask;
    $self->{evidence}->{duration_seconds} = monotonic() - $self->{started};
    validate( $self->{evidence} );
    return $self->{evidence};
}

sub _reason ( $self, $error ) {
    return 'interrupted'       if $self->{interrupted};
    return 'deadline_exceeded' if ref($error) && $error->{timed_out};
    for my $reason (
        qw(owned_workspace_refused missing_required_tool tool_major_mismatch
        archive_not_completed recovered_data_mismatch recovery_not_completed)
      )
    {
        return $reason if "$error" =~ /\Q$reason\E/msx;
    }
    return 'operation_failed';
}

sub _phase ( $self, $name, $operation ) {
    my $phase = { name => $name, status => 'fail', duration_seconds => 0 };
    push @{ $self->{evidence}->{phases} }, $phase;
    my $started = monotonic();
    my $error;
    try { $operation->(); $phase->{status} = 'pass'; }
    catch ($caught) { $error = $caught; };
    $phase->{duration_seconds} = monotonic() - $started;
    croak $error if $error;
    return undef;
}

sub _workspace_path ($self) {
    my $requested = $self->{options}->{dir};
    if ( !defined $requested ) {
        $requested =
          tempdir( 'gpforum-pitr-XXXXXX', TMPDIR => 1, CLEANUP => 0 );
        $self->{made} = 1;
    }
    croak 'owned_workspace_refused' if $requested =~ /[\x00\r\n]/msx;
    my $path = File::Spec->rel2abs($requested);
    croak 'owned_workspace_refused' if -l $path;
    if ( -e $path ) {
        croak 'owned_workspace_refused' if !-d $path || !_empty($path);
    }
    else {
        my $parent = abs_path( dirname($path) );
        croak 'owned_workspace_refused' if !defined $parent || !-d $parent;
        mkdir $path, PRIVATE_MODE or croak 'owned_workspace_refused';
        $self->{made} = 1;
    }
    return abs_path($path);
}

sub _workspace ($self) {
    my $path   = $self->_workspace_path;
    my $marker = File::Spec->catfile( $path, '.gpforum-pitr-owned' );
    sysopen my $handle, $marker, O_WRONLY | O_CREAT | O_EXCL, FILE_MODE
      or croak 'owned_workspace_refused';
    $self->{marker_body} = "$PROCESS_ID " . monotonic();
    print {$handle} $self->{marker_body} or croak 'Cannot write owned marker';
    close $handle                        or croak 'Cannot close owned marker';
    $self->{workdir} = $path;
    my @identity = stat $path;
    $self->{identity} = [ @identity[ 0, 1 ] ];

    for my $name (qw(archive socket)) {
        mkdir File::Spec->catdir( $path, $name ), PRIVATE_MODE
          or croak 'Cannot make owned workspace child';
    }
    for my $name (qw(pgpass pgservice)) {
        _append( File::Spec->catfile( $path, $name ), q{} );
    }
    $self->{env} = {
        PATH                   => $ENV{PATH} // q{},
        GPFORUM_PITR_WORKSPACE => $path,
        PGPASSFILE             => File::Spec->catfile( $path, 'pgpass' ),
        PGSERVICEFILE          => File::Spec->catfile( $path, 'pgservice' ),
        LANG                   => 'C',
        LC_ALL                 => 'C',
        TZ                     => 'UTC',
        PGCONNECT_TIMEOUT      => 2,
    };
    return undef;
}

sub _empty ($path) {
    opendir my $directory, $path or return 0;
    my @entries = grep { $_ ne q{.} && $_ ne q{..} } readdir $directory;
    closedir $directory or croak 'Cannot close workspace inventory';
    return !@entries;
}

sub _owned ($self) {
    return 0 if !$self->{workdir} || -l $self->{workdir};
    my @identity = stat $self->{workdir};
    return 0
      if !@identity
      || $identity[0] != $self->{identity}->[0]
      || $identity[1] != $self->{identity}->[1];
    my $marker = File::Spec->catfile( $self->{workdir}, '.gpforum-pitr-owned' );
    return 0 if -l $marker || !-f $marker;
    return _read($marker) eq $self->{marker_body};
}

sub _tool ($name) {
    for my $directory ( File::Spec->path ) {
        my $path = File::Spec->catfile( $directory, $name );
        return abs_path($path) if -x $path && !-d $path;
    }
    croak 'missing_required_tool';
}

sub _tools ($self) {
    my $major;
    for my $name (@TOOLS) {
        my $path = _tool($name);
        $self->{tools}->{$name} = $path;
        my $version = $self->_command( [ $path, '--version' ] );
        $version =~ s/\s+\z//msx;
        my ($selected) = $version =~ /PostgreSQL[)]\s+(\d+)/msx;
        croak 'tool_major_mismatch'
          if !defined $selected || defined $major && $major != $selected;
        $major = $selected;
        $self->{evidence}->{metadata}->{tools}->{$name} = $version;
    }
    try {
        my $commit =
          $self->_command( [ 'git', '-C', root_dir(), 'rev-parse', 'HEAD' ] );
        $commit =~ s/\s+\z//msx;
        if ( $commit =~ /\A[\da-f]{40}\z/msx ) {
            $self->{evidence}->{metadata}->{commit} = $commit;
        }
        my $status = $self->_command(
            [
                'git',         '-C',
                root_dir(),    'status',
                '--porcelain', '--untracked-files=normal'
            ]
        );
        $self->{evidence}->{metadata}->{source_dirty} =
          length($status) ? JSON::PP::true : JSON::PP::false;
    }
    catch ($error) { croak $error if $self->{interrupted}; };
    return undef;
}

sub _command ( $self, $command, $options = {} ) {
    my $remaining = $self->{deadline} - monotonic();
    my $log = File::Spec->catfile( $self->{workdir}, sprintf 'command-%03d.log',
        ++$self->{sequence} );
    my $runner = $self->{options}->{runner} // \&run_bounded;
    return $runner->(
        $command,
        {
            timeout => min( $remaining, COMMAND_LIMIT ),
            log     => $log,
            env     => $self->{env},
            %{$options}
        }
    );
}

sub _sql ( $self, $sql, $database = 'gpforum_pitr' ) {
    my $output = $self->_command(
        [
            $self->{tools}->{psql}, '-X', '-w', '-qAt', '-v', 'ON_ERROR_STOP=1',
            '-h', File::Spec->catdir( $self->{workdir}, 'socket' ), '-p',
            $self->{evidence}->{configuration}->{port},
            '-U', 'gpforum', '-d', $database, '-c', $sql
        ]
    );
    $output =~ s/\s+\z//msx;
    return $output;
}

sub _execute ($self) {
    $self->_phase( 'initialize',     sub { $self->_initialize; } );
    $self->_phase( 'base_backup',    sub { $self->_backup; } );
    $self->_phase( 'archive_target', sub { $self->_archive_target; } );
    $self->_phase( 'recover_target', sub { $self->_recover; } );
    return undef;
}

sub _initialize ($self) {
    my $data = File::Spec->catdir( $self->{workdir}, 'data' );
    $self->_command(
        [
            $self->{tools}->{initdb}, '-D',
            $data,                    '--no-locale',
            '--encoding=UTF8',        '--auth-local=trust',
            '--auth-host=reject',     '-U',
            'gpforum'
        ]
    );
    my $archive = File::Spec->catdir( $self->{workdir}, 'archive' );
    my $copy =
        'test ! -f '
      . shell_quote("$archive/%f")
      . ' && cp '
      . shell_quote('%p') . q{ }
      . shell_quote("$archive/%f");
    _append(
        File::Spec->catfile( $data, 'postgresql.conf' ),
        "wal_level = replica\narchive_mode = on\nmax_wal_senders = 3\n"
          . 'archive_command = '
          . conf_quote($copy) . "\n"
    );
    $self->_start('primary.log');
    $self->_sql( 'CREATE DATABASE gpforum_pitr', 'postgres' );
    $self->{evidence}->{metadata}->{postgresql} =
      $self->_sql('SHOW server_version');
    $self->_sql(
        'CREATE TABLE posts (id serial primary key, body text NOT NULL)');
    $self->_sql("INSERT INTO posts (body) VALUES ('$EXPECTED[0]')");
    return undef;
}

sub _backup ($self) {
    my $backup = File::Spec->catdir( $self->{workdir}, 'backup' );
    $self->_command(
        [
            $self->{tools}->{pg_basebackup},
            '-h',
            File::Spec->catdir( $self->{workdir}, 'socket' ),
            '-p',
            $self->{evidence}->{configuration}->{port},
            '-U',
            'gpforum',
            '-D',
            $backup,
            '-Fp',
            '-Xs',
            '--checkpoint=fast',
            '--no-password'
        ]
    );
    $self->_command( [ $self->{tools}->{pg_verifybackup}, $backup ] );
    $self->{evidence}->{checks}->{manifest_verified} = JSON::PP::true;
    return undef;
}

sub _archive_target ($self) {
    $self->_sql("INSERT INTO posts (body) VALUES ('$EXPECTED[1]')");
    my $target = $self->_sql('SELECT clock_timestamp()');
    croak 'Invalid recovery timestamp' if $target !~ /\A[\d:+.\s-]+\z/msx;
    $self->{evidence}->{dataset}->{target} = $target;
    $self->_sql(
"INSERT INTO posts (body) SELECT '$EXPECTED[2]' WHERE clock_timestamp() > '$target'::timestamptz"
    );
    my $before = $self->_sql('SELECT count(*) FROM posts');
    $self->{evidence}->{dataset}->{rows_before} = 0 + $before;
    croak 'recovered_data_mismatch' if $before != @EXPECTED;
    my $segment = $self->_sql('SELECT pg_walfile_name(pg_current_wal_lsn())');
    croak 'Invalid archived segment' if $segment !~ /\A[\dA-F]{24}\z/msx;
    $self->_sql('SELECT pg_switch_wal()');
    my $archived = $self->_poll(
        sub {
            return $self->_sql(
"SELECT CASE WHEN last_archived_wal ~ '^[0-9A-F]{24}\$' AND last_archived_wal >= '$segment' THEN 1 ELSE 0 END FROM pg_stat_archiver"
              ) eq '1'
              && -f File::Spec->catfile( $self->{workdir}, 'archive',
                $segment );
        }
    );
    croak 'archive_not_completed' if !$archived;
    $self->{evidence}->{checks}->{archive_completed} = JSON::PP::true;
    $self->{evidence}->{archived_segment} = $segment;
    return undef;
}

sub _recover ($self) {
    $self->_stop;
    my $data = File::Spec->catdir( $self->{workdir}, 'data' );
    rename $data, File::Spec->catdir( $self->{workdir}, 'incident_data' )
      or croak 'Cannot preserve owned incident data';
    rename File::Spec->catdir( $self->{workdir}, 'backup' ), $data
      or croak 'Cannot activate owned base backup';
    my $archive = File::Spec->catdir( $self->{workdir}, 'archive' );
    my $restore = 'cp ' . shell_quote("$archive/%f") . q{ } . shell_quote('%p');
    _append(
        File::Spec->catfile( $data, 'postgresql.conf' ),
        'restore_command = '
          . conf_quote($restore) . "\n"
          . 'recovery_target_time = '
          . conf_quote( $self->{evidence}->{dataset}->{target} )
          . "\nrecovery_target_action = 'promote'\n"
    );
    _append( File::Spec->catfile( $data, 'recovery.signal' ), q{} );
    my $started = monotonic();
    $self->_start('recovery.log');
    $self->{evidence}->{checks}->{recovery_completed} = JSON::PP::true;
    my $raw = $self->_sql('SELECT json_agg(body ORDER BY id)::text FROM posts');
    my $rows = JSON::PP->new->decode($raw);
    $self->{evidence}->{dataset}->{recovered_bodies} = $rows;
    my $count = 0 + $self->_sql('SELECT count(*) FROM posts');
    $self->{evidence}->{dataset}->{rows_after} = $count;
    croak 'recovered_data_mismatch'
      if ref($rows) ne 'ARRAY'
      || @{$rows} != 2
      || $rows->[0] ne $EXPECTED[0]
      || $rows->[1] ne $EXPECTED[1]
      || $count != 2;
    $self->{evidence}->{checks}->{records_exact} = JSON::PP::true;
    $self->{evidence}->{checks}->{counts_exact}  = JSON::PP::true;
    $self->{evidence}->{recovery_seconds}        = monotonic() - $started;
    return undef;
}

sub _start ( $self, $log_name ) {
    my $data = File::Spec->catdir( $self->{workdir}, 'data' );
    my $pid  = fork;
    croak 'Cannot fork owned PostgreSQL server' if !defined $pid;
    if ( !$pid ) {
        setsid() >= 0 or POSIX::_exit(CHILD_FAILURE);
        local %ENV = %{ $self->{env} };
        open STDOUT, '>', File::Spec->catfile( $self->{workdir}, $log_name )
          or POSIX::_exit(CHILD_FAILURE);
        open STDERR, '>&', \*STDOUT or POSIX::_exit(CHILD_FAILURE);
        exec { $self->{tools}->{postgres} } $self->{tools}->{postgres}, '-D',
          $data,
          '-p', $self->{evidence}->{configuration}->{port}, '-k',
          File::Spec->catdir( $self->{workdir}, 'socket' ),
          '-c', 'listen_addresses=', '-c', 'shared_buffers=16MB', '-c',
          'max_connections=10'
          or POSIX::_exit(CHILD_FAILURE);
    }
    push @{ $self->{servers} }, $pid;
    $self->{server} = $pid;
    croak 'recovery_not_completed' if !$self->_poll(
        sub {
            my $ready = 0;
            try {
                $ready =
                  $self->_sql( 'SELECT pg_is_in_recovery()::int', 'postgres' )
                  eq '0';
            }
            catch ($error) { croak $error if $self->{interrupted}; };
            return $ready;
        }
    );
    return undef;
}

sub _poll ( $self, $predicate ) {
    my $until = min( $self->{deadline}, monotonic() + POLL_LIMIT );
    while ( monotonic() < $until ) {
        return 1 if $predicate->();
        if ( monotonic() < $until ) {
            sleep min( POLL_INTERVAL, $until - monotonic() );
        }
    }
    return 0;
}

sub _stop ($self) {
    return undef if !$self->{server};
    $self->_command(
        [
            $self->{tools}->{pg_ctl},                       '-D',
            File::Spec->catdir( $self->{workdir}, 'data' ), '-m',
            'immediate',                                    '-w',
            '-t',                                           CLEANUP_RESERVE,
            'stop'
        ]
    );
    terminate( $self->{server} );
    @{ $self->{servers} } =
      grep { $_ != $self->{server} } @{ $self->{servers} };
    $self->{server} = undef;
    return undef;
}

sub _cleanup ($self) {
    while ( my $pid = pop @{ $self->{servers} } ) { terminate($pid); }
    $self->{server} = undef;
    $self->{evidence}->{cleanup}->{server_stopped} = JSON::PP::true;
    return undef                    if !$self->{workdir};
    croak 'owned_workspace_refused' if !$self->_owned;
    $self->_sanitize_logs;
    return undef if $self->{options}->{keep};
    if ( $self->{made} ) { _remove( $self->{workdir} ); }
    else {
        opendir my $directory, $self->{workdir}
          or croak 'Cannot inventory owned workspace';
        my @entries = grep { $_ ne q{.} && $_ ne q{..} } readdir $directory;
        closedir $directory or croak 'Cannot close owned workspace inventory';
        for my $name (@entries) {
            _remove( File::Spec->catfile( $self->{workdir}, $name ) );
        }
    }
    $self->{evidence}->{cleanup}->{workspace_removed} = JSON::PP::true;
    return undef;
}

sub _sanitize_logs ($self) {
    opendir my $directory, $self->{workdir}
      or croak 'Cannot inventory diagnostic logs';
    my @logs = grep { /[.]log\z/msx } readdir $directory;
    closedir $directory or croak 'Cannot close diagnostic inventory';
    for my $name (@logs) {
        my $path = File::Spec->catfile( $self->{workdir}, $name );
        croak 'owned_workspace_refused' if -l $path;
        my $raw = substr _read($path), -LOG_LIMIT;
        open my $handle, '>', $path or croak 'Cannot sanitize diagnostic';
        print {$handle} redact($raw)
          or croak 'Cannot write sanitized diagnostic';
        close $handle or croak 'Cannot close sanitized diagnostic';
    }
    return undef;
}

sub _remove ($path) {
    if ( -d $path && !-l $path ) {
        my $errors;
        remove_tree( $path, { safe => 1, error => \$errors } );
        croak 'Cannot remove owned workspace' if @{$errors};
    }
    else { unlink $path or croak 'Cannot remove owned workspace entry'; }
    return undef;
}

sub _read ($path) {
    open my $handle, '<', $path or croak 'Cannot read owned file';
    my $raw = do { local $INPUT_RECORD_SEPARATOR = undef; <$handle> }
      // q{};
    close $handle or croak 'Cannot close owned file';
    return $raw;
}

sub _append ( $path, $content ) {
    open my $handle, '>>', $path or croak 'Cannot write owned configuration';
    print {$handle} $content or croak 'Cannot append owned configuration';
    close $handle            or croak 'Cannot close owned configuration';
    return undef;
}

sub shell_quote ($value) {
    croak 'Invalid shell argument' if $value =~ /[\x00\r\n]/msx;
    $value =~ s/'/'"'"'/gmsx;
    return "'$value'";
}

sub conf_quote ($value) {
    croak 'Invalid configuration value' if $value =~ /[\x00\r\n]/msx;
    $value                                        =~ s/\\/\\\\/gmsx;
    $value                                        =~ s/'/''/gmsx;
    return "'$value'";
}
1;
