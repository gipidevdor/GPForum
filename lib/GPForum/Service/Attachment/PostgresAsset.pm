# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Attachment::PostgresAsset;

use Mojo::Base 'Mojo::Asset', -signatures;
use v5.40;

use Carp qw(croak);
use Const::Fast;
use List::Util qw(min);

our $VERSION = '0.001';
const my $CHUNK_BYTES => 1_024 * 1_024;
const my $HTTP_CHUNK  => 131_072;

has [qw(storage object_key byte_size modified_at)];

sub size  ($self) { return $self->byte_size; }
sub mtime ($self) { return $self->modified_at; }

# One cached database chunk per response. Sequential HTTP reads reuse it;
# seeking replaces it. The cache never grows with the video's length.
sub get_chunk ( $self, $offset, $maximum = $HTTP_CHUNK ) {
    $maximum //= $HTTP_CHUNK;
    return q{} if $maximum == 0;

    $offset += $self->start_range;
    my $end = min( $self->end_range // ( $self->size - 1 ), $self->size - 1 );
    return q{} if $offset > $end;
    my $number = int( $offset / $CHUNK_BYTES );
    if ( !defined $self->{chunk_number} || $self->{chunk_number} != $number ) {
        $self->{chunk} =
          $self->storage->read_chunk( $self->object_key, $number );
        $self->{chunk_number} = $number;
    }
    my $inside = $offset % $CHUNK_BYTES;
    my $length = min( $maximum, $CHUNK_BYTES - $inside, $end - $offset + 1 );
    my $bytes  = substr $self->{chunk}, $inside, $length;
    croak 'stored attachment chunk is incomplete' if length $bytes != $length;
    return $bytes;
}

sub slurp ($self) {

    # Mojo assets return the complete object here, regardless of HTTP ranges.
    # A separate reader preserves the caller's range and its cached chunk.
    my $whole = __PACKAGE__->new(
        storage    => $self->storage,
        object_key => $self->object_key,
        byte_size  => $self->size,
    );
    my $bytes = q{};
    while ( length $bytes < $self->size ) {
        $bytes .= $whole->get_chunk( length $bytes, $CHUNK_BYTES );
    }
    return $bytes;
}

1;

__END__

=head1 NAME

GPForum::Service::Attachment::PostgresAsset - A seekable PostgreSQL HTTP asset.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $asset = $storage->asset_for($object_key);

=head1 DESCRIPTION

Reads immutable one MiB chunks by primary key and retains only the current
chunk. start_range and end_range bound each read, including the last byte.
The HTTP path uses get_chunk, never slurp.

=head1 SUBROUTINES/METHODS

=head2 size

Returns the full immutable object size.


=head2 mtime

Returns the object creation time as a Unix epoch.


=head2 get_chunk

Reads a bounded fragment, honoring both range limits and caching one database chunk.


=head2 slurp

Returns the complete object for small legacy consumers; HTTP delivery never uses this method.

=head1 DIAGNOSTICS

Throws when a requested stored chunk is absent or incomplete.

=head1 CONFIGURATION AND ENVIRONMENT

The composition layer supplies the schema, storage and source policy.

=head1 DEPENDENCIES

L<Mojo::Base> and the composed Good Phorum services.

=head1 INCOMPATIBILITIES

Read-only HTTP asset; mutable and multipart asset operations are unsupported.

=head1 BUGS AND LIMITATIONS

Read-only HTTP asset; mutable and multipart asset operations are unsupported.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. BSD-3-Clause.

=cut
