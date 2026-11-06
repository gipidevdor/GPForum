# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Web::BoundedRealtimeStream;
use Const::Fast;
use Scalar::Util qw(weaken);
use Mojo::Base 'Mojo::IOLoop::Stream', -signatures;
use v5.40;
use GPForum::X::Argument;
our $VERSION = '0.001';
const my $MAX_PENDING_WRITES => 32;
const my $MAX_PENDING_BYTES  => 262_144;
has realtime_pending_writes => 0;
has realtime_overloaded     => 0;

# Preserve the server-owned stream, reactor subscriptions and TLS handle.
# Only native Mojo streams are supported; an unknown adapter fails closed.
sub protect ( $class, $stream ) {
    return $stream if $stream->isa($class);
    if ( ref $stream ne 'Mojo::IOLoop::Stream' ) {
        GPForum::X::Argument->throw(
            message => 'unsupported realtime stream adapter' );
    }
    return bless $stream, $class;
}

# The actual socket queue is the shared sink for JSON, automatic PONGs and
# close frames. Transaction drain only transfers bytes into this queue.
sub write ( $self, $chunk = undef, $callback = undef ) {    ## no critic (Subroutines::ProhibitBuiltinHomonyms) -- preserves the native stream write API
    return $self if $self->realtime_overloaded;
    my $bytes = length( $chunk // q{} );
    if ($bytes) {
        if (   $self->realtime_pending_writes >= $MAX_PENDING_WRITES
            || $self->bytes_waiting + $bytes > $MAX_PENDING_BYTES )
        {
            $self->realtime_overloaded(1);
            $self->close;
            return $self;
        }
        if ( !$self->realtime_pending_writes ) {
            my $stream = $self;
            weaken $stream;
            $self->once(
                drain => sub (@) {
                    if ($stream) { $stream->realtime_pending_writes(0); }
                }
            );
        }
        $self->realtime_pending_writes( $self->realtime_pending_writes + 1 );
    }
    return $self->SUPER::write( $chunk, $callback );
}

1;
__END__
=head1 NAME

GPForum::Web::BoundedRealtimeStream - Bounded native WebSocket socket output.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    GPForum::Web::BoundedRealtimeStream->protect($stream);

=head1 DESCRIPTION

Installs a per-connection native stream adapter before accepting realtime
output. Its byte and write budgets include application frames and automatic
protocol replies. Only the underlying stream's actual drain releases its
budget; transaction drain cannot release bytes still waiting on the socket.
Overload closes the transport without adding another response to its queue.
TLS state and the existing reactor subscriptions remain on the same object.

=head1 SUBROUTINES/METHODS

=head2 protect

Adapts a native Mojo stream in place. Repeated installation is harmless;
unknown stream subclasses are refused explicitly.

=head2 write

Preserves native callbacks and output while bounding retained bytes and
nonempty writes. An overloaded or closed transport accepts no further output.

=head2 realtime_pending_writes

Number of nonempty writes since the last socket drain.

=head2 realtime_overloaded

Whether an output limit closed this transport.

=head1 DIAGNOSTICS

Unsupported stream adapters throw L<GPForum::X::Argument>.

=head1 CONFIGURATION AND ENVIRONMENT

Fixed limits match the realtime controller: 32 queued writes and 256 KiB.

=head1 DEPENDENCIES

L<Mojo::IOLoop::Stream>, L<Const::Fast>, L<Scalar::Util>.

=head1 INCOMPATIBILITIES

Custom stream subclasses require an explicit compatible adapter.

=head1 BUGS AND LIMITATIONS

An overloaded connection is closed immediately; the client reconnects for
its current snapshot. Already transmitted bytes cannot be recalled.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. BSD-3-Clause.

=cut
