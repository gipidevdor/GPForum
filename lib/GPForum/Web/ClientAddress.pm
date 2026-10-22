# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Web::ClientAddress;

use Mojo::Base -strict, -signatures;
use v5.40;

use Const::Fast;
use English qw(-no_match_vars);

use GPForum::Web::AddressBans;

our $VERSION = '0.001';

# An address as nginx's $remote_addr and Caddy's {remote_host} write it:
# dotted IPv4 or colon-separated IPv6, at most 45 characters. nginx on a Unix
# socket of its own writes "unix:", which names nobody.
const my $IPV4            => qr{ \d{1,3} (?: [.] \d{1,3} ){3} }msx;
const my $IPV6            => qr{ [[:xdigit:]]* : [[:xdigit:]:.]* }msx;
const my $ADDRESS         => qr{ \A (?: $IPV4 | $IPV6 ) \z }msx;
const my $LONGEST_ADDRESS => 45;

my $unconnected = 0;

# Every request learns its client here, before anything is dispatched, so
# the rate limits, the audit rows and the sessions read one answer. And here,
# around the action that answers it, a write from an address a live ban
# covers is refused (ADR 0146): the one place bans are enforced.
sub register ( $class, $application ) {
    $application->hook(
        before_dispatch => sub ($controller) {
            $class->of( $controller->tx );
        }
    );
    my $bans = GPForum::Web::AddressBans->new;
    $application->hook(
        around_action => sub ( $next, $controller, $action, $last ) {
            return $next->()
              if !$last
              || $bans->admits( $controller, $class->of( $controller->tx ) );

            return 0;
        }
    );

    return;
}

# The client of a transaction, set on it once so that remote_address says
# the same to every later reader.
#
# A TCP peer is Mojolicious's to read: the peer itself, or with proxy on the
# last X-Forwarded-For entry no trusted proxy wrote. A transaction with no
# peer address came over the service's Unix socket, whose only client is the
# local proxy (deploy/nginx, deploy/caddy), so the client is the last entry,
# the one the proxy appended: what a client sent ahead of it is ignored, and
# so is the trusted list, which would walk past a loopback client to an
# entry that client forged. A request with no such entry -- `gpforum
# status`, curl on the socket -- gets its connection's own key rather than a
# constant every such client would share (ADR 0086).
sub of ( $class, $tx ) {
    return $tx->remote_address if defined $tx->original_remote_address;

    my @entries = split /\s*,\s*/msx,
      $tx->req->headers->header('X-Forwarded-For') // q{};
    my $appended = pop @entries;
    my $client =
      defined $appended
      && length $appended <= $LONGEST_ADDRESS && $appended =~ $ADDRESS
      ? $appended
      : 'connection:'
      . ( $tx->connection // "local-$PROCESS_ID-" . ++$unconnected );
    $tx->req->reverse_proxy(0);

    return $tx->original_remote_address($client)->original_remote_address;
}

1;

__END__

=head1 NAME

GPForum::Web::ClientAddress - The client a request comes from, on TCP and on
the service's Unix socket.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    GPForum::Web::ClientAddress->register($app);
    my $client = GPForum::Web::ClientAddress->of( $controller->tx );

=head1 DESCRIPTION

Mojolicious leaves a connection on a Unix socket without a peer address, so
C<remote_address> answered undef ahead of C<X-Forwarded-For>. This module
gives every transaction a client before dispatch: the TCP peer as
Mojolicious reads it, the entry the local proxy appended on the Unix socket,
or the connection's own key when there is none.

=head1 SUBROUTINES/METHODS

=head2 register

Takes the application. Adds the C<before_dispatch> hook that sets every
request's client, and the C<around_action> hook that refuses a write from a
banned address (L<GPForum::Web::AddressBans>, ADR 0146).

=head2 of

Takes a transaction. Returns its client address, setting it on the
transaction the first time.

=head1 DIAGNOSTICS

None.

=head1 CONFIGURATION AND ENVIRONMENT

C<GPFORUM_RUNTIME_PROXY> and C<GPFORUM_RUNTIME_TRUSTED_PROXIES> decide the
TCP case through Hypnotoad; the Unix socket needs neither.

=head1 DEPENDENCIES

L<Mojo::Base>, L<Const::Fast>, L<English>, L<GPForum::Web::AddressBans>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

A proxy that replaces X-Forwarded-For rather than appending to it is read
the same way: its single entry is the last.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

BSD-3-Clause.
