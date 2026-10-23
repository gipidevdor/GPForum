# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::OS::SystemdNotify;

use Mojo::Base -base, -signatures;
use v5.40;
use Const::Fast;

use Carp    qw(croak);
use English qw(-no_match_vars);
use Mojo::UserAgent;
use Mojo::Util qw(steady_time);
use Socket     qw(AF_UNIX SOCK_DGRAM sockaddr_un);

our $VERSION = '0.001';

const my $HTTP_OK => 200;

has socket_path => sub { return $ENV{NOTIFY_SOCKET}; };
has interval    => 10;
has probe       => sub {
    my $ua = Mojo::UserAgent->new->connect_timeout(1)->request_timeout(2);
    return sub ( $listen, $path = '/health/live' ) {
        my $tx = $ua->get("$listen$path");
        return !$tx->error && ( $tx->res->code // 0 ) == $HTTP_OK;
    };
};

sub notify ( $self, $message ) {
    my $path = $self->socket_path;
    return false if !defined $path || !length $path;
    $path =~ s/\A@/\x00/msx;
    socket my $socket, AF_UNIX, SOCK_DGRAM, 0
      or croak "cannot open systemd notification socket: $OS_ERROR";
    CORE::send( $socket, $message, 0, sockaddr_un($path) )
      or croak "cannot notify systemd: $OS_ERROR";
    close $socket or croak "cannot close notification socket: $OS_ERROR";
    return true;
}

# Prefork's manager does not run Mojo::IOLoop: recurring timers there only
# run in children. Its public wait event runs once a second in the manager.
# A bounded HTTP probe proves a worker can answer, and a blocked manager
# cannot keep feeding the watchdog through independently running children.
sub attach ( $self, $server, $listen ) {
    return false
      if !$self->socket_path || !$server->isa('Mojo::Server::Prefork');
    my ( $ready, $last_probe ) = ( 0, 0 );
    $server->on(
        wait => sub {
            return
              if defined $ENV{WATCHDOG_PID}
              && $ENV{WATCHDOG_PID} != $PROCESS_ID;
            my $now = steady_time;
            return if $now - $last_probe < $self->interval;
            $last_probe = $now;
            my $path = $ready ? '/health/live' : '/health/ready';
            return if !$server->healthy || !$self->probe->( $listen, $path );
            if ( !$ready ) {
                $self->notify("READY=1\nSTATUS=GPForum is serving HTTP");
                $ready = 1;
            }
            $self->notify('WATCHDOG=1');
        }
    );
    return true;
}

1;
