# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Attachment::Source;

use Mojo::Base 'GPForum::Base', -signatures;
use v5.40;

use Carp qw(croak);
use Const::Fast;
use Digest::SHA;
use Mojo::Asset::Memory;
use GPForum::X::Argument;

our $VERSION = '0.001';
const my $CHUNK_BYTES => 1_024 * 1_024;
const my $SHA_BITS    => 256;

__PACKAGE__->requires('asset');

sub from_input ( $class, $input ) {
    return $class->new(
        asset => Mojo::Asset::Memory->new->add_chunk( $input->{content} ) )
      if defined $input->{content};
    my $upload = $input->{upload} or return undef;
    return $class->new( asset => $upload->asset )
      if $upload->can('asset') && $upload->asset;
    return $class->new(
        asset => Mojo::Asset::Memory->new->add_chunk( $upload->slurp ) )
      if $upload->can('slurp');
    GPForum::X::Argument->throw( message => 'unsupported upload object' );
}

sub size   ($self) { return $self->asset->size; }
sub sample ($self) { return $self->asset->get_chunk( 0, $CHUNK_BYTES ); }

sub each_chunk ( $self, $consume ) {
    my $size   = $self->size;
    my $offset = 0;
    while ( $offset < $size ) {
        my $chunk = $self->chunk($offset);
        $consume->($chunk);
        $offset += length $chunk;
    }
    return;
}

# The bytes from $offset on, at most one chunk of them: what each_chunk
# hands its callback, for a caller that awaits between chunks.
sub chunk ( $self, $offset ) {
    my $chunk = $self->asset->get_chunk( $offset, $CHUNK_BYTES );
    croak 'upload ended before its declared size' if !length $chunk;
    croak 'upload content must be bytes' if !utf8::downgrade( $chunk, 1 );
    return $chunk;
}

sub checksum ($self) {
    my $digest = Digest::SHA->new($SHA_BITS);
    $self->each_chunk( sub ($chunk) { $digest->add($chunk); } );
    return $digest->hexdigest;
}

1;

__END__

=head1 NAME

GPForum::Service::Attachment::Source - Bounded reads of an uploaded asset.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $source = GPForum::Service::Attachment::Source->from_input($input);

=head1 DESCRIPTION

Wraps a Mojo asset without slurping a file-backed upload. Computes SHA-256
and visits its bytes in at most one MiB chunks. A short read is an error.

=head1 SUBROUTINES/METHODS

=head2 from_input

Builds a source from scalar content or a Mojo upload asset; returns undef without an upload.


=head2 size

Returns the byte length declared by the underlying asset.


=head2 sample

Reads at most one MiB from the beginning for media identification.


=head2 each_chunk

Calls the consumer for each bounded binary chunk; rejects an unexpected short read.


=head2 chunk

Takes an offset and returns the bytes from there on, at most one chunk, as
L</each_chunk> hands them over; it croaks on a source that ends early or
holds characters. A caller that awaits between chunks walks the source with
it.

=head2 checksum

Returns the SHA-256 digest, computed incrementally from the source.

=head1 DIAGNOSTICS

Throws for a short read, unsupported upload or non-byte content.

=head1 CONFIGURATION AND ENVIRONMENT

The composition layer supplies the schema, storage and source policy.

=head1 DEPENDENCIES

L<Mojo::Base> and the composed Good Phorum services.

=head1 INCOMPATIBILITIES

A read-only wrapper; its source must remain stable during validation and storage.

=head1 BUGS AND LIMITATIONS

A read-only wrapper; its source must remain stable during validation and storage.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. BSD-3-Clause.

=cut
