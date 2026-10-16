# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause
package GPForum::Performance::Server;
use v5.40;
use Carp    qw(croak);
use English qw(-no_match_vars);
our $VERSION = '0.001';
use File::Path                    qw(make_path);
use POSIX                         qw(setsid WNOHANG _exit);
use Time::HiRes                   qw(sleep);
use List::Util                    qw(min any);
use GPForum::Performance::Support qw(root_dir read_json redact monotonic);
use GPForum::Performance::HTTP
  qw(free_port probe_url process_snapshot native_backend_flags);

# Core constants keep startup and cleanup usable before application deps load.
use constant {    ## no critic (ValuesAndExpressions::ProhibitConstantPragma)
    SETUP_FAILURE      => 126,
    EXEC_FAILURE       => 127,
    STARTUP_SECONDS    => 30,
    READY_INTERVAL     => 0.1,
    TELEMETRY_INTERVAL => 0.01,
    STOP_SECONDS       => 5,
    STOP_INTERVAL      => 0.05,
    LOG_LIMIT          => 200_000,
    DEFAULT_CLIENTS    => 2048,
    DEFAULT_BACKLOG    => 1024,
};

sub new ( $class, $args ) {
    croak 'Native EV reactor required' if $args->{reactor} ne 'EV';
    my $self = bless { $args->%* }, $class;
    $self->{directory} = "$args->{output}/diagnostics/server-$args->{index}";
    if ( -e $self->{directory} ) {
        croak 'Server diagnostic directory already exists';
    }
    make_path( $self->{directory} );
    $self->{port}     = free_port();
    $self->{base}     = "http://127.0.0.1:$self->{port}";
    $self->{reactor}  = "Mojo::Reactor::$args->{reactor}";
    $self->{log_path} = "$self->{directory}/hypnotoad.log";
    my $env = _environment($self);
    $self->{pid} = _launch( $self, $env );
    my $until = min( $args->{deadline}, monotonic() + STARTUP_SECONDS );
    try {
        _await_live( $self, $until );
        _read_master($self);
        _await_workers( $self, $until );
    }
    catch ($error) { $self->close; croak $error; };
    return $self;
}

sub _environment($self) {
    my %env = %ENV;
    delete $env{LIBEV_FLAGS};
    %env = (
        %env,
        MOJO_REACTOR                  => $self->{reactor},
        GPFORUM_LOG_LEVEL             => 'fatal',
        GPFORUM_WEB_PROCESSES         => $self->{workers},
        GPFORUM_RUNTIME_WORKER_POLICY => 'configured',
        GPFORUM_RUNTIME_LISTEN        => $self->{base},
        GPFORUM_RUNTIME_PID_FILE      => "$self->{directory}/hypnotoad.pid",
        GPFORUM_RUNTIME_BACKLOG       => $self->{backlog} // DEFAULT_BACKLOG,
        GPFORUM_RUNTIME_CLIENTS       => $self->{clients} // DEFAULT_CLIENTS,
        GPFORUM_RUNTIME_REQUESTS           => 100_000_000,
        GPFORUM_RUNTIME_GRACEFUL_TIMEOUT   => 3,
        GPFORUM_FORUM_READ_RATE_LIMIT      => 100_000_000,
        GPFORUM_GLIFISTORE_URL             => q{},
        GPFORUM_LOCAL_CACHE_MAX_ENTRIES    => 4096,
        GPFORUM_CATEGORY_CACHE_TTL_SECONDS => 3600,
        GPFORUM_PERFORMANCE_CACHE_MODE     => $self->{cache_mode},
        GPFORUM_PERFORMANCE_TELEMETRY_DIR  => $self->{directory},
    );

    $env{LIBEV_FLAGS} = native_backend_flags();
    return \%env;
}

sub _launch( $self, $env ) {
    my $pid = fork;
    if ( !( defined $pid ) ) { croak "Cannot fork Hypnotoad: $ERRNO"; }
    if ( !$pid ) {
        setsid() >= 0    or _exit(SETUP_FAILURE);
        chdir root_dir() or _exit(SETUP_FAILURE);
        local %ENV = %{$env};
        open STDOUT, '>',  $self->{log_path} or _exit(SETUP_FAILURE);
        open STDERR, '>&', \*STDOUT          or _exit(SETUP_FAILURE);
        exec { root_dir() . '/script/gpforum-carton' } root_dir()
          . '/script/gpforum-carton', 'exec', 'hypnotoad', '-f',
          root_dir() . '/benchmarks/hypnotoad-app.pl'
          or _exit(EXEC_FAILURE);
    }
    return $pid;
}

sub _await_live( $self, $until ) {
    my $pid = $self->{pid};
    my $live;
    while ( monotonic() < $until ) {
        if ( waitpid( $pid, WNOHANG ) == $pid ) {
            croak 'Hypnotoad exited during startup';
        }
        my $ready;
        try {
            probe_url( $self->{base} . '/health/live', { timeout => 1 } );
            $ready = 1
        }
        catch ($error) { $ready = 0 };
        if ($ready) { $live = 1; last; }
        sleep READY_INTERVAL;
    }
    if ( !($live) ) { croak 'Hypnotoad did not become live in 30 seconds'; }
    return undef;
}

sub _read_master($self) {
    open my $fh, '<', "$self->{directory}/hypnotoad.pid"
      or croak 'Missing Hypnotoad PID';
    my $master = <$fh>;
    close $fh or croak 'Cannot close Hypnotoad PID';
    my ($master_pid) = $master =~ /\A\s*(\d+)\s*\z/msx;
    if ( !defined $master_pid ) {
        croak 'Invalid Hypnotoad PID';
    }
    $self->{master} = 0 + $master_pid;
    return undef;
}

sub _await_workers( $self, $until ) {
    my $all;
    while ( monotonic() < $until ) {
        probe_url( $self->{base} . '/health/live', { timeout => 1 } );
        my $observed;
        try { $self->telemetry; $observed = 1 } catch ($error) {
            $observed = 0
        };
        if ($observed) { $all = 1; last; }
        sleep TELEMETRY_INTERVAL;
    }
    if ( !($all) ) {
        croak
'all configured workers did not produce serving reactor telemetry before startup deadline';
    }
    return undef;
}

sub telemetry ($self) {
    my $actual = process_snapshot( $self->{master} );
    my @rows;
    for my $pid ( @{ $actual->{worker_pids} } ) {
        my $path = "$self->{directory}/worker-$pid.json";
        if ( -f $path ) { push @rows, read_json($path); }
    }
    if ( !@rows || any { ( $_->{reactor} // q{} ) ne $self->{reactor} } @rows )
    {
        croak "requested $self->{reactor} did not match serving worker reactor";
    }
    my $observed_pids = join q{,}, sort { $a <=> $b } map { $_->{pid} } @rows;
    my $actual_pids = join q{,}, sort { $a <=> $b } @{ $actual->{worker_pids} };
    if (
        !(
               @rows == @{ $actual->{worker_pids} }
            && $observed_pids eq $actual_pids
        )
      )
    {
        croak 'some serving workers have not produced actual reactor telemetry';
    }
    if ( $self->{reactor} eq 'Mojo::Reactor::EV'
        && any { ( $_->{ev_backend} // 0 ) != native_backend_flags() } @rows )
    {
        croak 'serving EV worker did not select the required native backend';
    }
    if (
        !(
            defined( $actual->{workers_actual} )
            && $actual->{workers_actual} == $self->{workers}
        )
      )
    {
        croak 'serving worker count changed during measurement';
    }
    return \@rows;
}

# Keep the public lifecycle API used by both HTTP and Extreme orchestrators.
sub close ($self) {    ## no critic (NamingConventions::ProhibitAmbiguousNames, Subroutines::ProhibitBuiltinHomonyms)
    if ( $self->{closed}++ ) { return undef; }
    if ( $self->{pid} ) {
        kill 'TERM', -$self->{pid};
        my $until = monotonic() + STOP_SECONDS;
        while ( monotonic() < $until ) {
            if ( waitpid( $self->{pid}, WNOHANG ) != 0 ) { last; }
            sleep STOP_INTERVAL;
        }
        kill 'KILL', -$self->{pid};
        waitpid $self->{pid}, 0;
    }
    _redact_log($self);
    return undef;
}

sub _redact_log($self) {
    if ( -f $self->{log_path} ) {
        open my $fh, '<:raw', $self->{log_path} or return undef;
        my $size = -s $fh;
        seek $fh, $size > LOG_LIMIT ? $size - LOG_LIMIT : 0, 0 or return undef;
        local $INPUT_RECORD_SEPARATOR = undef;
        my $raw = <$fh>;
        CORE::close $fh or return undef;
        open my $out, '>', $self->{log_path} or return undef;
        print {$out} redact($raw) or return undef;
        CORE::close $out          or return undef;
    }
    return undef;
}
1;
