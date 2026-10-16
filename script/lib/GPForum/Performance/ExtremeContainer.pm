# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Performance::ExtremeContainer;

use v5.40;
use Carp        qw(croak);
use Digest::SHA qw(sha256_hex);
use English     qw(-no_match_vars);
use Exporter    qw(import);
use File::Spec;
use File::Path  qw(make_path remove_tree);
use List::Util  qw(min);
use Time::HiRes qw(sleep);
use GPForum::Performance::Budget;
use GPForum::Performance::ExtremeState qw(load_state save_state);
use GPForum::Performance::Support qw(monotonic run_bounded read_json redact);

# Core-only cleanup/reporting after a failed dependency installation.
use constant {    ## no critic (ValuesAndExpressions::ProhibitConstantPragma)
    CONTAINER_SUFFIX_LENGTH => 80,
    ENTROPY_BYTES           => 32,
    READY_RESERVE_SECONDS   => 35,
    READY_PROBE_SECONDS     => 3,
    READY_INTERVAL          => 0.2,
    SETUP_MINIMUM_SECONDS   => 75,
    DATABASE_SUFFIX_LENGTH  => 12,
    CONTAINER_START_SECONDS => 45,
    REMOVE_SECONDS          => 15,
    SOCKET_ID_LENGTH        => 16,
    PRIVATE_DIRECTORY_MODE  => oct '700',
    SHARED_SOCKET_MODE      => oct '777',
};

our $VERSION   = '0.001';
our @EXPORT_OK = qw(start_database cleanup container_name);

sub container_name ($state) {
    my $suffix = lc "$state->{run_id}-$state->{run_attempt}";
    $suffix =~ s/[^[:alnum:]-]/-/gamsx;
    $suffix = substr $suffix, 0, CONTAINER_SUFFIX_LENGTH;
    return 'gpforum-extreme-' . $suffix;
}

sub _socket_directory ($state) {
    my $suffix = substr sha256_hex( container_name($state) ), 0,
      SOCKET_ID_LENGTH;
    return File::Spec->catdir( '/tmp', "gpforum-extreme-pg-$suffix" );
}

sub _random {
    open my $handle, '<:raw', '/dev/urandom'
      or croak "Cannot open entropy source: $OS_ERROR";
    my $count = read $handle, my $bytes, ENTROPY_BYTES;
    close $handle or croak "Cannot close entropy source: $OS_ERROR";
    croak 'Cannot read enough random bytes'
      if !defined $count || $count != ENTROPY_BYTES;
    return unpack 'H*', $bytes;
}

sub _ready ( $name, $database, $budget, $deadline, $output ) {
    while ( $budget->remaining($deadline) > READY_RESERVE_SECONDS ) {
        my $okay = 0;
        try {
            run_bounded(
                [
                    'docker',     'exec',     $name,      'pg_isready',
                    '--username', 'postgres', '--dbname', $database
                ],
                {
                    timeout => READY_PROBE_SECONDS,
                    log     => File::Spec->catfile(
                        $output, 'diagnostics/postgres-ready.log'
                    )
                }
            );
            $okay = 1;
        }
        catch ($error) { $okay = 0; };
        if ($okay) { return 1; }
        sleep READY_INTERVAL;
    }
    croak 'PostgreSQL startup exhausted the setup budget';
}

sub start_database ( $output, $state, $deadline ) {
    my $budget = GPForum::Performance::Budget->new(
        read_json( File::Spec->catfile( $output, 'clock.json' ) ) );
    croak 'Insufficient setup budget for a disposable database'
      if $budget->remaining($deadline) < SETUP_MINIMUM_SECONDS;
    my $name = container_name($state);
    $state->{owned_container} = $name;
    save_state( $output, $state );
    my $directory = _socket_directory($state);
    mkdir $directory, PRIVATE_DIRECTORY_MODE
      or croak "Cannot create owned PostgreSQL socket directory: $OS_ERROR";
    $state->{owned_socket_directory} = $directory;
    save_state( $output, $state );
    my $socket = File::Spec->catdir( $directory, 'socket' );
    make_path($socket);

    # The container's postgres uid differs from the runner's. Its socket
    # directory is shared inside an outer directory only this runner owns.
    chmod SHARED_SOCKET_MODE, $socket
      or croak "Cannot prepare PostgreSQL socket permissions: $OS_ERROR";
    my $password = _random();
    my $suffix   = substr _random(), 0, DATABASE_SUFFIX_LENGTH;
    my $database = 'gpforum_perf_extreme_' . $suffix;
    my %environment =
      ( %ENV, POSTGRES_PASSWORD => $password, POSTGRES_DB => $database );
    run_bounded(
        [
            'docker',
            'run',
            '--detach',
            '--name',
            $name,
            '--label',
            'gpforum.extreme.disposable=true',
            '--volume',
            "$socket:/gpforum-socket",
            '--env',
            'POSTGRES_PASSWORD',
            '--env',
            'POSTGRES_DB',
            '--env',
            'PGHOST=/gpforum-socket',
            'postgres:16',
            '-c',
            'listen_addresses=',
            '-c',
            'unix_socket_directories=/gpforum-socket',
        ],
        {
            timeout =>
              min( CONTAINER_START_SECONDS, $budget->remaining($deadline) ),
            env => \%environment,
            log =>
              File::Spec->catfile( $output, 'diagnostics/postgres-start.log' )
        }
    );
    my %runtime_environment = (
        GPFORUM_DATABASE_DSN =>
          "dbi:Pg:dbname=$database;host=$socket;port=5432",
        GPFORUM_DATABASE_USER     => 'postgres',
        GPFORUM_DATABASE_PASSWORD => $password,
        PGPASSWORD                => $password,
        PGHOST                    => $socket,
    );
    _ready( $name, $database, $budget, $deadline, $output );
    my $image =
      run_bounded( [ 'docker', 'inspect', '--format', '{{.Image}}', $name ],
        { timeout => READY_PROBE_SECONDS } );
    chomp $image;
    $state->{configuration}{postgres_image}     = $image;
    $state->{configuration}{database_transport} = 'unix';
    my $pid =
      run_bounded( [ 'docker', 'inspect', '--format', '{{.State.Pid}}', $name ],
        { timeout => READY_PROBE_SECONDS } );
    chomp $pid;

    if ( $pid =~ /\A\d+\z/amsx ) {
        $runtime_environment{GPFORUM_EXTREME_PG_MASTER_PID} = $pid;
    }
    save_state( $output, $state );
    return \%runtime_environment;
}

sub cleanup ( $output, $server = undef ) {
    my $state = load_state($output);
    my @errors;
    if ($server) {
        try { $server->close; }
        catch ($error) { push @errors, redact($error); };
    }
    if ( my $owned = $state->{owned_container} ) {
        if ( $owned ne container_name($state) ) {
            push @errors, 'Owned container identity mismatch; refused removal';
        }
        else {
            try {
                run_bounded(
                    [ 'docker', 'rm', '--force', '--volumes', $owned ],
                    {
                        timeout => REMOVE_SECONDS,
                        log     => File::Spec->catfile(
                            $output, 'diagnostics/container-cleanup.log'
                        )
                    }
                );
                delete $state->{owned_container};
            }
            catch ($error) { push @errors, redact($error); };
        }
    }
    if ( !$state->{owned_container} && $state->{owned_socket_directory} ) {
        try {
            my $directory = $state->{owned_socket_directory};
            croak 'Owned socket directory identity mismatch; refused removal'
              if $directory ne _socket_directory($state);
            remove_tree($directory);
            croak 'Could not remove owned PostgreSQL socket directory'
              if -e $directory;
            delete $state->{owned_socket_directory};
        }
        catch ($error) { push @errors, redact($error); };
    }
    $state->{phases}{cleanup} = {
        status => @errors ? 'failed' : 'ok',
        reason => @errors
        ? join( '; ', @errors )
        : 'Owned server stopped; owned disposable PostgreSQL container and volumes removed (or local cluster left to its owner)'
    };
    save_state( $output, $state );
    return @errors ? 0 : 1;
}

1;
