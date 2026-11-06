# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Notification::Push::Resolver;

use Mojo::Base -base, -signatures;
use v5.40;
use Const::Fast;
use Carp       qw(croak);
use List::Util qw(min any);
use Mojo::IOLoop;
use Mojo::Promise;
use Net::DNS;
use GPForum::Service::Notification::Push::Endpoint;

our $VERSION = '0.001';
const my $DNS_SECONDS   => 2;
const my $CACHE_SECONDS => 60;
const my $MAX_CACHED    => 128;
const my $MAX_ADDRESSES => 16;
has cache    => sub { return {}; };
has pending  => sub { return {}; };
has resolver => sub {
    return Net::DNS::Resolver->new(
        udp_timeout => $DNS_SECONDS,
        retry       => 1,
        igntc       => 1,
        usevc       => 0
    );
};

sub resolve_p ( $self, $host ) {
    my $entry = $self->cache->{$host};
    return Mojo::Promise->resolve($entry) if $entry && $entry->{expires} > time;
    return $self->pending->{$host}        if $self->pending->{$host};
    my $promise = Mojo::Promise->new;
    my $socket;
    try { $socket = $self->resolver->bgsend( "$host.", 'A' ); }
    catch ($error) { return $promise->reject('push DNS unavailable'); };
    return $promise->reject('push DNS unavailable') if !$socket;
    $self->pending->{$host} = $promise;
    my $reactor = Mojo::IOLoop->singleton->reactor;
    my $timer;
    my $finished = 0;
    my $finish   = sub ($packet) {
        return if $finished++;
        $reactor->remove($socket);
        if ( defined $timer ) { Mojo::IOLoop->remove($timer); }
        close $socket or croak 'cannot close Push DNS handle';
        delete $self->pending->{$host};
        my @answers = $self->_answers($packet);
        if ( !@answers ) {
            $promise->reject('push DNS has no permitted public address');
            return;
        }
        my $ttl = min( $CACHE_SECONDS, map { $_->ttl } @answers );
        my $resolved =
          { address => $answers[0]->address, expires => time + $ttl };
        if ( keys %{ $self->cache } >= $MAX_CACHED ) {
            my ($oldest) = sort {
                $self->cache->{$a}{expires} <=> $self->cache->{$b}{expires}
            } keys %{ $self->cache };
            delete $self->cache->{$oldest};
        }
        $self->cache->{$host} = $resolved;
        $promise->resolve($resolved);
        return;
    };
    $reactor->io(
        $socket => sub {

            # Never use bgread's waiting loop: first let bgbusy consume the
            # readable datagram. igntc prevents a synchronous TCP fallback.
            return if $self->resolver->bgbusy($socket);
            my $packet = $self->resolver->bgread($socket);
            $finish->($packet);
        }
    )->watch( $socket, 1, 0 );
    $timer = Mojo::IOLoop->timer( $DNS_SECONDS => sub { $finish->(undef); } );
    return $promise;
}

sub _answers ( $self, $packet ) {
    return
      if !$packet || $packet->header->tc || $packet->header->rcode ne 'NOERROR';
    my @answers = grep { $_->type eq 'A' } $packet->answer;
    return
         if !@answers
      || @answers > $MAX_ADDRESSES
      || any {
        !GPForum::Service::Notification::Push::Endpoint->public_address(
            $_->address )
      } @answers;
    return @answers;
}

1;

__END__

=head1 NAME

GPForum::Service::Notification::Push::Resolver - Resolve Push destinations asynchronously and fail closed on reserved addresses.

=head1 DESCRIPTION

Resolve Push destinations asynchronously and fail closed on reserved addresses. See docs/ops/web-push.md for deployment and lifecycle guarantees.

=head1 SUBROUTINES/METHODS

=head2 resolve_p

Return a promise for a validated public peer. Concurrent requests share one resolution; positive results are cached for at most 60 seconds and no longer than their TTL.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $service = GPForum::Service::Notification::Push::Resolver->new();

=head1 DIAGNOSTICS

Invalid input fails closed. Transport failures are bounded and reported without receiver capability URLs or key material.

=head1 CONFIGURATION AND ENVIRONMENT

Dependencies and validated settings are supplied by the composition layer. See docs/ops/web-push.md.

=head1 DEPENDENCIES

CryptX supplies cryptographic primitives; Mojolicious supplies asynchronous HTTPS; versioned PostgreSQL API functions own persistence.

=head1 INCOMPATIBILITIES

Private key files require a persistent service account and restrictive filesystem permissions.

=head1 BUGS AND LIMITATIONS

A provider acceptance does not guarantee display. An already accepted notification cannot be recalled.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. BSD-3-Clause.

=cut
