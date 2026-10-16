# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::OS::UnixListener;

use Mojo::Base -strict, -signatures;
use v5.40;

use Carp qw(croak);
use Const::Fast;
use English qw(-no_match_vars);
use IO::Socket::UNIX;
use Mojo::URL;
use Socket qw(SOCK_STREAM SOMAXCONN);

our $VERSION = '0.001';

# srw-rw----: the gpforum group, which the proxy's account joins, connects;
# other accounts do not. Connecting takes write permission on the socket.
const my $GROUP_SOCKET_UMASK => oct '117';

# Mojo::IOLoop::Server's own setting: a listener survives the exec of a
# Hypnotoad upgrade, which finds it again through MOJO_REUSE.
const my $INHERITED_DESCRIPTORS => 1023;

# The sockets bound here, held for the life of the process: Mojolicious
# opens a second handle on the same descriptor, which closing this one
# would close under it.
my %held;

sub register ( $class, $application ) {
    $application->hook(
        before_server_start => sub ( $server, $app ) {
            $class->bind_listeners($server);
        }
    );

    return;
}

# The service runs under umask 027, so what it writes -- uploads, their
# directories -- is the group's to read and not to change. The socket is
# the one thing the group writes to: each http+unix listener is bound here
# under a umask that gives it that, just before the server would bind it,
# and handed to Mojolicious through MOJO_REUSE as Hypnotoad hands a
# listener to its upgrade. A listener already there -- an upgrade's -- is
# left to Mojolicious.
sub bind_listeners ( $class, $server ) {
    return if !$server->can('listen');

    for my $location ( @{ $server->listen } ) {
        my $url = Mojo::URL->new($location);
        next if ( $url->protocol // q{} ) ne 'http+unix';
        next if defined $url->query->param('fd');

        $class->_bind( $url->host, $server->backlog );
    }

    return;
}

sub _bind ( $class, $path, $backlog ) {
    my $reuse = $ENV{MOJO_REUSE} // q{};
    return if $reuse =~ /(?:\A|,) unix: \Q$path\E : \d+/msx;

    if ( -S $path ) {
        unlink $path or croak "Can't create listen socket: $OS_ERROR";
    }
    local $SYSTEM_FD_MAX = $INHERITED_DESCRIPTORS;
    my $previous = umask $GROUP_SOCKET_UMASK;
    my $socket   = IO::Socket::UNIX->new(
        Listen => $backlog // SOMAXCONN,
        Local  => $path,
        Type   => SOCK_STREAM,
    );
    my $error = $OS_ERROR;
    umask $previous;

    # Mojo::IOLoop::Server's words, which `gpforum start` explains.
    croak "Can't create listen socket: $error" if !$socket;

    $held{$path} = $socket;
    $ENV{MOJO_REUSE} = join q{,}, ( length $reuse ? $reuse : () ),    ## no critic (Variables::RequireLocalizedPunctuationVars) -- Mojolicious reads it to take the socket, and an upgrade inherits it
      join q{:}, 'unix', $path, fileno $socket;

    return;
}

1;

__END__

=head1 NAME

GPForum::OS::UnixListener - The service's Unix socket, open to the proxy's
group and to no one else.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    GPForum::OS::UnixListener->register($app);

=head1 DESCRIPTION

Binds each C<http+unix> listener of a Mojolicious server with mode C<0660>
while the process keeps umask C<027>, so the group the proxy's account
joins can connect to the socket and only read the files the service writes.

=head1 SUBROUTINES/METHODS

=head2 register

Takes the application. Adds the C<before_server_start> hook that binds the
server's Unix sockets.

=head2 bind_listeners

Takes a server. Binds each of its C<http+unix> listeners that MOJO_REUSE
does not already hold, and leaves the others to Mojolicious.

=head1 DIAGNOSTICS

C<Can't create listen socket: REASON>, Mojo::IOLoop::Server's own words, when
the socket cannot be bound.

=head1 CONFIGURATION AND ENVIRONMENT

Reads and extends C<MOJO_REUSE>. The listeners are C<GPFORUM_RUNTIME_LISTEN>.

=head1 DEPENDENCIES

L<IO::Socket::UNIX>, L<Mojo::URL>, L<Const::Fast>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Relies on MOJO_REUSE, the format Mojo::IOLoop::Server uses to hand listeners
to a Hypnotoad upgrade; t/692 holds it to that.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

BSD-3-Clause.
