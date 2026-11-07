# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Infrastructure::PublicResolver;

use Mojo::Base -base, -signatures;
use v5.40;
use Const::Fast;
use List::Util qw(min any);
use Mojo::IOLoop;
use Mojo::Promise;
use Net::DNS;

our $VERSION = '0.001';
const my $DNS_SECONDS   => 2;
const my $CACHE_SECONDS => 60;
const my $MAX_CACHED    => 128;
const my $MAX_ADDRESSES => 16;
has allowed_address => sub {
    return sub { return 0; };
};
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
    catch ($error) { return $promise->reject('DNS unavailable'); };
    return $promise->reject('DNS unavailable') if !$socket;
    $self->pending->{$host} = $promise;
    my $reactor = Mojo::IOLoop->singleton->reactor;
    my $timer;
    my $finished = 0;
    my $finish   = sub ($packet) {
        return if $finished++;
        $reactor->remove($socket);
        if ( defined $timer ) { Mojo::IOLoop->remove($timer); }
        if ( !close $socket ) {
            delete $self->pending->{$host};
            $promise->reject('DNS socket cleanup failed');
            return;
        }
        delete $self->pending->{$host};
        my @answers = $self->_answers($packet);
        if ( !@answers ) {
            $promise->reject('DNS has no permitted public address');
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
            my $packet;
            try {
                return if $self->resolver->bgbusy($socket);
                $packet = $self->resolver->bgread($socket);
            }
            catch ($error) { $packet = undef; };
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
      || any { !$self->allowed_address->( $_->address ) } @answers;
    return @answers;
}

1;

__END__

=head1 NAME

GPForum::Infrastructure::PublicResolver - Resolve approved public peers through the Mojolicious reactor.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $resolver = GPForum::Infrastructure::PublicResolver->new(
        allowed_address => $approved_address);
    $resolver->resolve_p('example.org');

=head1 DESCRIPTION

Uses UDP background DNS with a two-second timer, coalesces pending lookups, honors positive TTLs and rejects truncated answers. Every address must satisfy the supplied allowed_address predicate; the default denies all addresses. There is no synchronous TCP fallback.

=head1 SUBROUTINES/METHODS

=head2 resolve_p

Resolve approved public peers through the Mojolicious reactor.

=head1 DIAGNOSTICS

Failures reject promises. HTTP callers finish or reject their response through the controller's request context.

=head1 CONFIGURATION AND ENVIRONMENT

Runtime limits have safe built-in defaults. No environment setting is required.

=head1 DEPENDENCIES

Mojolicious and the modules named in the source.

=head1 INCOMPATIBILITIES

HTTP callers consume promises without starting a nested event loop.

=head1 BUGS AND LIMITATIONS

Admission is bounded per web worker, not across multiple hosts. CLI workflows keep their synchronous interfaces.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. BSD-3-Clause.

=cut
