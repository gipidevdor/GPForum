# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::OS::ServiceManager;

use Mojo::Base 'Mojo::Server::Prefork', -signatures;
use v5.40;
use Carp qw(croak);
use GPForum::X::Io;
use English    qw(-no_match_vars);
use Errno      qw(EPERM);
use Fcntl      qw(O_CREAT O_EXCL O_NOFOLLOW O_WRONLY :flock);
use Mojo::File qw(path);
use Const::Fast;

our $VERSION = '0.001';
const my $STATE_MODE => oct '640';
has cleanup => 0;

# The public start method runs after Prefork has installed its scoped signal
# handlers and before it forks workers. Reuse its graceful handler; workers
# still receive Prefork's own independent signal policy after their fork.
sub start ($self) {
    $self->SUPER::start;
    if ( $self->{gp_service_running} ) {
        croak 'Prefork did not install its graceful shutdown handler'
          if ref $SIG{QUIT} ne 'CODE';
        $SIG{INT} = $SIG{TERM} = $SIG{QUIT};    ## no critic (Variables::RequireLocalizedPunctuationVars) -- these are local to Prefork::run, which called start
    }
    return $self;
}

# Prefork obtains the child's loop before installing worker callbacks or
# accepting requests. Close the inherited descriptor at that public boundary,
# rather than waiting for a timer or a first HTTP request.
sub ioloop ( $self, @arguments ) {
    my $guard = $self->{gp_service_lock};
    if ( $guard && $guard->{owner} != $PROCESS_ID ) {
        close $guard->{handle}
          or GPForum::X::Io->throw(
            message => 'cannot close inherited service lock' );
        delete $self->{gp_service_lock};
    }
    return $self->SUPER::ioloop(@arguments);
}

sub run ($self) {
    $self->cleanup(0);
    my $pid_file = path( $self->pid_file );
    my $lock     = _lock("$pid_file.lock");
    _write_pid($pid_file);
    my $owner    = $PROCESS_ID;
    my $graceful = 0;
    my $finish   = $self->on(
        finish => sub ( $, $draining ) { $graceful = $draining ? 1 : 0; } );
    my $rotation = $self->_rotation_watch($owner);
    my $failure;
    {
        ## no critic (Variables::ProhibitLocalVars) -- scoped service state around Prefork's blocking run
        local $self->{gp_service_running} = 1;
        local $self->{gp_service_lock} = { owner => $owner, handle => $lock };
        ## use critic
        local $SIG{HUP} = $rotation->{signal};
        try { $self->SUPER::run; }
        catch ($error) { $failure = $error; };
    }
    $self->unsubscribe( finish => $finish );
    $rotation->{dispose}->();
    $self->stop;
    if ( -e $pid_file && $pid_file->slurp eq "$owner\n" ) {
        $pid_file->remove;
    }
    close $lock
      or GPForum::X::Io->throw( message => 'cannot close service lock' );
    croak $failure if defined $failure;
    croak 'service manager stopped without a graceful shutdown' if !$graceful;
    return;
}

sub _rotation_watch ( $self, $owner ) {
    my %workers;
    my $spawn = $self->on( spawn => sub ( $, $pid ) { $workers{$pid} = 1; } );
    my $reap  = $self->on( reap => sub ( $, $pid ) { delete $workers{$pid}; } );
    my $rotate   = 0;
    my $previous = $SIG{HUP};
    my $wait     = $self->on(
        wait => sub {
            return if !$rotate || $PROCESS_ID != $owner;
            $rotate = 0;
            if (%workers) { kill 'HUP', keys %workers; }
            return;
        }
    );
    return {
        signal => sub {
            if ( ref $previous eq 'CODE' ) { $previous->(); }
            $rotate = 1;
            return;
        },
        dispose => sub {
            $self->unsubscribe( spawn => $spawn );
            $self->unsubscribe( reap  => $reap );
            $self->unsubscribe( wait  => $wait );
            return;
        }
    };
}

sub _lock ($file) {
    sysopen my $handle, $file, O_WRONLY | O_CREAT | O_NOFOLLOW, $STATE_MODE
      or GPForum::X::Io->throw(
        message => "cannot open service lock $file: $OS_ERROR" );
    croak "service lock is not a regular file: $file" if !-f $handle;
    flock $handle, LOCK_EX | LOCK_NB
      or croak "another service manager holds $file";
    return $handle;
}

sub _write_pid ($file) {
    croak "service PID file is a symlink: $file" if -l $file;
    if ( -e $file ) {
        my $pid = $file->slurp;
        croak "invalid service PID file: $file"
          if $pid !~ /\A [1-9]\d* \n? \z/amsx;
        chomp $pid;
        croak "service PID $pid is still running: $file"
          if kill( 0, $pid ) || $ERRNO == EPERM;
        $file->remove;
    }
    sysopen my $handle, "$file", O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW,
      $STATE_MODE
      or GPForum::X::Io->throw(
        message => "cannot create service PID file $file: $OS_ERROR" );
    print {$handle} "$PROCESS_ID\n"
      or GPForum::X::Io->throw( message => 'cannot write service PID' );
    close $handle
      or GPForum::X::Io->throw( message => 'cannot close service PID file' );
    return;
}

1;
