# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package GPForum::Infrastructure::Subprocess;

use Mojo::Base 'Mojo::IOLoop::Subprocess', -signatures;
use v5.40;
use English qw(-no_match_vars);
use Errno   qw(ECHILD EINTR);
use Carp    qw(carp croak);
use Socket  qw(AF_UNIX SOCK_STREAM PF_UNSPEC);
use POSIX   qw(WNOHANG);
use Const::Fast;
use Mojo::IOLoop::Stream;

our $VERSION = '0.001';
const my $REAP_INTERVAL => 0.01;
const my $EXIT_SHIFT    => 8;

# Keep Mojo's public run/run_p/progress API and wire format, but use sockets:
# FreeBSD kqueue can deliver pipe bytes without delivering the following EOF.
## no critic (Subroutines::ProhibitUnusedPrivateSubroutines) -- inherited run/run_p dispatch to this transport hook
sub _start ( $self, $work, $done ) {
    socketpair my $reader, my $writer, AF_UNIX, SOCK_STREAM, PF_UNSPEC
      or return $done->( $self, "cannot create subprocess socket: $OS_ERROR" );
    $writer->autoflush(1);
    my $pid = fork;
    if ( !defined $pid ) {
        my $error = "cannot fork subprocess: $OS_ERROR";
        $self->_close($reader);
        $self->_close($writer);
        return $done->( $self, $error );
    }
    if ( !$pid ) {
        $self->_close($reader);
        $self->{writer} = $writer;
        $self->_child( $writer, $work );
    }
    $self->{pid} = $pid;
    $self->_close($writer);
    $self->_watch( $reader, $done );
    return;
}

## use critic

sub _child ( $self, $writer, $work ) {
    my $status = 0;
    try {
        $self->ioloop->reset( { freeze => 1 } );
        my ( @values, $error );
        try { @values = $work->($self); }
        catch ($caught) { $error = $caught; };
        print {$writer} '0-', $self->serialize->( [ $error // q{}, @values ] )
          or croak "cannot write subprocess result: $OS_ERROR";
        $self->emit('cleanup');
    }
    catch ($caught) {
        carp "$caught";
        $status = 1;
    };
    $self->_close($writer);
    return POSIX::_exit($status);
}

sub _watch ( $self, $reader, $done ) {
    my $owner  = $PROCESS_ID;
    my $buffer = q{};
    my $stream = Mojo::IOLoop::Stream->new($reader)->timeout(0);
    $self->{channel} = $stream;
    $stream->on(
        read => sub ( $, $bytes ) {
            $buffer .= $bytes;
            $self->_progress( \$buffer );
            return;
        }
    );
    $stream->on(
        close => sub {
            return if $PROCESS_ID != $owner;
            delete $self->{channel};
            $self->_reap( $buffer, $done );
            return;
        }
    );
    $self->emit('spawn')->ioloop->stream($stream);
    return;
}

# Optional bounded parent-to-child commands. Ordinary run/run_p users never
# write to this channel; streaming readers use it to request one chunk at a time.
sub write_command ( $self, $bytes ) {
    croak 'subprocess command channel is closed' if !$self->{channel};
    $self->{channel}->write($bytes);
    return $self;
}

sub _progress ( $self, $buffer ) {
    while ( ${$buffer} =~ /\A([[:digit:]]+)-/msx ) {
        my $length = 0 + $1;
        my $header = $LAST_MATCH_END[0];
        last if !$length || length( ${$buffer} ) < $header + $length;
        substr ${$buffer}, 0, $header, q{};
        my $values = $self->deserialize->( substr ${$buffer}, 0, $length, q{} );
        $self->emit( progress => @{$values} );
    }
    return;
}

sub _reap ( $self, $buffer, $done ) {
    my $pid = waitpid $self->pid, WNOHANG;
    if ( !$pid || ( $pid < 0 && $ERRNO == EINTR ) ) {
        $self->ioloop->timer(
            $REAP_INTERVAL => sub { $self->_reap( $buffer, $done ); return; } );
        return;
    }
    return $done->( $self, "cannot reap subprocess: $OS_ERROR" )
      if $pid < 0 && $ERRNO != ECHILD;

    # libev may have reaped a child between EOF and this asynchronous check.
    # Its complete IPC result is still valid; the exit status is unavailable.
    $self->{exit_code} = $pid < 0 ? undef : $CHILD_ERROR >> $EXIT_SHIFT;
    my ( $values, $error );
    try {
        croak 'subprocess closed without a result' if $buffer !~ /\A0-/msx;
        $values = $self->deserialize->( substr $buffer, 2 );
    }
    catch ($caught) { $error = $caught; };
    return $done->( $self, $error ) if defined $error;
    return $done->( $self, @{$values} );
}

sub _close ( $, $handle ) {
    return if !defined fileno $handle;
    close $handle or carp "cannot close subprocess socket: $OS_ERROR";
    return;
}

1;

__END__

=head1 NAME

GPForum::Infrastructure::Subprocess - Mojo subprocesses over local sockets.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $child = GPForum::Infrastructure::Subprocess->new;
    $child->run_p(sub { return 'result'; })->then(sub ($result) { ... });

=head1 DESCRIPTION

Preserves the Mojolicious subprocess run, run_p, progress, serialization and
cleanup interfaces. A local socket pair replaces pipe IPC so FreeBSD kqueue
observes both data and EOF. The reactor stays native on every supported OS.
Child reaping uses nonblocking waitpid and a short timer after EOF. If another
reaper already collected the child, the complete IPC result is retained and
exit_code is unavailable rather than invented. No application signal handler
is replaced.

=head1 SUBROUTINES/METHODS

Inherits the public interface of Mojo::IOLoop::Subprocess.

=head1 DIAGNOSTICS

Promise rejection reports fork, transport, decoding and child execution errors.

=head1 CONFIGURATION AND ENVIRONMENT

Uses the caller's Mojo IOLoop and serializers; no extra setting is required.

=head1 DEPENDENCIES

Mojolicious, Socket, POSIX, English, Errno, Carp and Const::Fast.

=head1 INCOMPATIBILITIES

Requires Unix fork and local stream socket pairs, as provided by supported OSes.

=head1 BUGS AND LIMITATIONS

Inherited exit_code is unavailable if another child reaper collected the status.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. BSD-3-Clause.

=cut
