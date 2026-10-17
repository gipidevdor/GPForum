# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Infrastructure::ImageBytes;

use Compress::Zlib ();
use Const::Fast;
use Mojo::Base -base, -signatures;
use v5.40;

our $VERSION = '0.001';

const my $PNG_SIGNATURE => pack 'H*', '89504e470d0a1a0a';
const my $JPEG_START    => pack 'H*', 'ffd8';
const my $ZERO_BYTE     => pack 'C',  0;
const my $PNG_IHDR_END  => 24;
const my $CHUNK_HEAD    => 8;
const my $CHUNK_CRC     => 4;
const my $FIELD         => 4;
const my $PAIR          => 2;
const my $GIF_HEADER    => 10;
const my $GIF_SIZE      => 6;
const my $WEBP_HEADER   => 30;
const my $WEBP_KIND     => 12;
const my $SOF_LENGTH    => 9;
const my $SOF_SIZE      => 5;
const my $MARKER_PREFIX => 0xff;
const my $FOURTEEN_BITS => 0x3fff;
const my $FOURTEEN      => 14;
const my $VP8_START     => 26;
const my $VP8L_START    => 21;
const my $VP8X_START    => 24;
const my $THREE_BYTES   => 3;

# The chunks a picture needs to be drawn: its header, palette and
# transparency, its pixels and its end. Everything else -- text, time,
# EXIF, colour profiles, private chunks -- is dropped.
const my %CRITICAL_PNG => map { $_ => 1 } qw(IHDR PLTE tRNS IDAT IEND);

# JPEG's start-of-frame markers: SOF0 to SOF15 but DHT (C4), JPG (C8) and
# DAC (CC), which are not frames; and the markers that carry no length.
const my %JPEG_FRAME => map { $_ => 1 }
  grep { $_ != 0xc4 && $_ != 0xc8 && $_ != 0xcc } 0xc0 .. 0xcf;
const my %JPEG_STANDALONE => map { $_ => 1 } 0x01,
  0xd0 .. 0xd8;

const my %READER => (
    'image/png'  => \&_png,
    'image/gif'  => \&_gif,
    'image/jpeg' => \&_jpeg,
    'image/webp' => \&_webp,
);

# The width and height an image declares, from its header alone -- nothing
# is decoded -- or undef when the bytes do not read as the media type says.
sub dimensions ( $self, $content, $media_type ) {
    return undef if !defined $content || !defined $media_type;
    return undef if !exists $READER{ lc $media_type };

    my ( $width, $height ) = $READER{ lc $media_type }->($content);
    return undef if !$width || !$height;

    return { width => $width, height => $height };
}

# A PNG of only the chunks a picture needs, each checked against its CRC,
# or undef when the bytes are not a well-formed PNG.
sub plain_png ( $self, $content ) {
    return undef if !defined $content;
    return undef if index( $content, $PNG_SIGNATURE ) != 0;

    my $kept   = $PNG_SIGNATURE;
    my $offset = length $PNG_SIGNATURE;
    while ( $offset + $CHUNK_HEAD <= length $content ) {
        my ( $type, $chunk ) = _chunk_at( $content, $offset );
        return undef if !defined $chunk;

        if ( exists $CRITICAL_PNG{$type} ) {
            $kept .= $chunk;
        }
        $offset += length $chunk;
        if ( $type eq 'IEND' ) {
            return _first_is_header($kept) ? $kept : undef;
        }
    }

    return undef;
}

# The chunk at an offset, whole, and its type; no chunk when it runs past
# the end or fails its CRC.
sub _chunk_at ( $content, $offset ) {
    my ( $length, $type ) = unpack 'N a4', substr $content, $offset,
      $CHUNK_HEAD;
    my $whole = $CHUNK_HEAD + $length + $CHUNK_CRC;
    return if $offset + $whole > length $content;

    my $chunk = substr $content, $offset, $whole;
    my $crc   = unpack 'N', substr $chunk, -$CHUNK_CRC;
    return
      if Compress::Zlib::crc32( substr $chunk, $FIELD, $length + $FIELD ) !=
      $crc;

    return ( $type, $chunk );
}

sub _first_is_header ($png) {
    return substr( $png, length($PNG_SIGNATURE) + $FIELD, $FIELD ) eq 'IHDR';
}

sub _png ($content) {
    return if length $content < $PNG_IHDR_END;
    return if index( $content, $PNG_SIGNATURE ) != 0;
    return if !_first_is_header($content);

    return unpack 'N N', substr $content, $PNG_IHDR_END - $CHUNK_HEAD,
      $CHUNK_HEAD;
}

sub _gif ($content) {
    return if length $content < $GIF_HEADER;
    return if $content !~ /\A GIF8[79]a/msx;

    return unpack 'v v', substr $content, $GIF_SIZE, $FIELD;
}

# Walks the markers to the first frame header, which holds the size.
sub _jpeg ($content) {
    return if substr( $content, 0, $PAIR ) ne $JPEG_START;

    my $offset = $PAIR;
    while ( $offset + $FIELD <= length $content ) {
        my ( $prefix, $marker ) = unpack 'C C', substr $content, $offset, $PAIR;
        return if $prefix != $MARKER_PREFIX;

        if ( $marker == $MARKER_PREFIX ) {
            $offset += 1;
        }
        elsif ( exists $JPEG_STANDALONE{$marker} ) {
            $offset += $PAIR;
        }
        elsif ( exists $JPEG_FRAME{$marker} ) {
            return if $offset + $SOF_LENGTH > length $content;
            my ( $height, $width ) = unpack 'n n',
              substr $content, $offset + $SOF_SIZE, $FIELD;
            return ( $width, $height );
        }
        else {
            my $length = unpack 'n', substr $content, $offset + $PAIR, $PAIR;
            return if $length < $PAIR;
            $offset += $PAIR + $length;
        }
    }

    return;
}

# VP8 (lossy), VP8L (lossless) and VP8X (extended, animation and alpha).
sub _webp ($content) {
    return if length $content < $WEBP_HEADER;
    return if $content !~ /\A RIFF .{4} WEBP/msx;

    my $kind = substr $content, $WEBP_KIND, $FIELD;
    if ( $kind eq 'VP8 ' ) {
        my ( $width, $height ) = unpack 'v v', substr $content, $VP8_START,
          $FIELD;
        return ( $width & $FOURTEEN_BITS, $height & $FOURTEEN_BITS );
    }
    if ( $kind eq 'VP8L' ) {
        my $bits = unpack 'V', substr $content, $VP8L_START, $FIELD;
        return ( ( $bits & $FOURTEEN_BITS ) + 1,
            ( ( $bits >> $FOURTEEN ) & $FOURTEEN_BITS ) + 1 );
    }
    if ( $kind eq 'VP8X' ) {
        return ( _three_bytes( $content, $VP8X_START ) + 1,
            _three_bytes( $content, $VP8X_START + $THREE_BYTES ) + 1 );
    }

    return;
}

# A 24-bit little-endian number.
sub _three_bytes ( $content, $offset ) {
    return unpack 'V', substr( $content, $offset, $THREE_BYTES ) . $ZERO_BYTE;
}

1;

__END__

=head1 NAME

GPForum::Infrastructure::ImageBytes - Read an image's size from its header, and keep only a PNG's picture.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $bytes = GPForum::Infrastructure::ImageBytes->new;
    my $size  = $bytes->dimensions( $content, 'image/jpeg' );
    # { width => 4032, height => 3024 }, or undef
    my $clean = $bytes->plain_png($png);    # undef when malformed

=head1 DESCRIPTION

Two small readers for profile pictures (ADR 0144). L</dimensions> reads the
size a PNG, GIF, JPEG or WebP declares without decoding it, so a picture
too large to be worth resizing is refused before any image tool runs.
L</plain_png> rewrites a PNG the image tool wrote with only the chunks that
draw it, so nothing of the original's metadata -- a camera's EXIF, a
location, a comment -- reaches the stored squares, whatever the tool kept.

=head1 SUBROUTINES/METHODS

=head2 new

Constructor; takes nothing.

=head2 dimensions

Takes the bytes and their sniffed media type (C<image/png>, C<image/gif>,
C<image/jpeg> or C<image/webp>). Returns C<< { width, height } >>, or undef
for another type or bytes whose header does not read.

=head2 plain_png

Takes a PNG's bytes. Returns the signature with the C<IHDR>, C<PLTE>,
C<tRNS>, C<IDAT> and C<IEND> chunks in their order, or undef when the bytes
are not a PNG, a chunk runs past the end or fails its CRC, or there is no
C<IEND>.

=head1 DIAGNOSTICS

None: unreadable bytes answer undef.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<Compress::Zlib> (core) for the CRC.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

The size read is the one the header declares; the image tool decodes the
pixels.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause
license.

=cut
