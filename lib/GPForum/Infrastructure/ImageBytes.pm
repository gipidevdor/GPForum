# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Infrastructure::ImageBytes;

use Compress::Zlib ();
use Const::Fast;
use Mojo::Base -base, -signatures;
use v5.40;

our $VERSION = '0.001';

const my $PNG_SIGNATURE => "\x89PNG\x0d\x0a\x1a\x0a";
const my $PNG_IHDR_END  => 24;
const my $CHUNK_HEAD    => 8;
const my $CHUNK_CRC     => 4;
const my $GIF_HEADER    => 10;
const my $WEBP_HEADER   => 30;
const my $JPEG_SOI      => 2;
const my $MARKER_LENGTH => 4;
const my $SOF_LENGTH    => 9;
const my $FOURTEEN_BITS => 0x3fff;
const my $TWENTY_FOUR   => 0xffffff;
const my $BYTE          => 8;
const my $VP8_START     => 26;
const my $VP8L_START    => 21;
const my $VP8X_START    => 24;

# The chunks a picture needs to be drawn: its header, palette and
# transparency, its pixels and its end. Everything else -- text, time,
# EXIF, colour profiles, private chunks -- is dropped.
const my %CRITICAL_PNG => map { $_ => 1 } qw(IHDR PLTE tRNS IDAT IEND);

# JPEG's start-of-frame markers: SOF0 to SOF15 but DHT (C4), JPG (C8) and
# DAC (CC), which are not frames.
const my %JPEG_FRAME => map { $_ => 1 }
  grep { $_ != 0xc4 && $_ != 0xc8 && $_ != 0xcc } 0xc0 .. 0xcf;
const my %JPEG_STANDALONE => map { $_ => 1 } 0x01, 0xd0 .. 0xd8;

# The width and height an image declares, from its header alone -- nothing
# is decoded -- or undef when the bytes do not read as the media type says.
sub dimensions ( $self, $content, $media_type ) {
    return undef if !defined $content || !defined $media_type;

    my $reader = {
        'image/png'  => \&_png,
        'image/gif'  => \&_gif,
        'image/jpeg' => \&_jpeg,
        'image/webp' => \&_webp,
    }->{ lc $media_type };
    return undef if !$reader;

    my ( $width, $height ) = $reader->($content);
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
    my $ended  = 0;
    while ( $offset + $CHUNK_HEAD <= length $content ) {
        my ( $length, $type ) = unpack 'N a4', substr $content, $offset,
          $CHUNK_HEAD;
        my $whole = $CHUNK_HEAD + $length + $CHUNK_CRC;
        return undef if $offset + $whole > length $content;

        my $chunk = substr $content, $offset, $whole;
        my $crc   = unpack 'N', substr $chunk, -$CHUNK_CRC;
        return undef
          if _crc32( substr $chunk, $MARKER_LENGTH, $length + $MARKER_LENGTH )
          != $crc;
        $kept .= $chunk if exists $CRITICAL_PNG{$type};
        $offset += $whole;
        if ( $type eq 'IEND' ) {
            $ended = 1;
            last;
        }
    }
    return undef if !$ended;
    return undef if substr( $kept, length($PNG_SIGNATURE) + $MARKER_LENGTH,
        $MARKER_LENGTH ) ne 'IHDR';

    return $kept;
}

sub _png ($content) {
    return if length $content < $PNG_IHDR_END;
    return if index( $content, $PNG_SIGNATURE ) != 0;
    return if substr( $content, length($PNG_SIGNATURE) + $MARKER_LENGTH,
        $MARKER_LENGTH ) ne 'IHDR';

    return unpack 'N N', substr $content, $PNG_IHDR_END - $BYTE, $BYTE;
}

sub _gif ($content) {
    return if length $content < $GIF_HEADER;
    return if $content !~ /\A GIF8[79]a/msx;

    return unpack 'v v', substr $content, 6, $MARKER_LENGTH;
}

# Walks the markers to the first frame header, which holds the size.
sub _jpeg ($content) {
    return if substr( $content, 0, $JPEG_SOI ) ne "\xff\xd8";

    my $offset = $JPEG_SOI;
    while ( $offset + $MARKER_LENGTH <= length $content ) {
        my ( $prefix, $marker ) = unpack 'C C', substr $content, $offset, 2;
        return if $prefix != 0xff;
        if ( $marker == 0xff ) {
            $offset += 1;
            next;
        }
        if ( exists $JPEG_STANDALONE{$marker} ) {
            $offset += 2;
            next;
        }
        my $length = unpack 'n', substr $content, $offset + 2, 2;
        return if $length < 2;
        if ( exists $JPEG_FRAME{$marker} ) {
            return if $offset + $SOF_LENGTH > length $content;
            my ( $height, $width ) = unpack 'n n',
              substr $content, $offset + 5, $MARKER_LENGTH;
            return ( $width, $height );
        }
        $offset += 2 + $length;
    }

    return;
}

# VP8 (lossy), VP8L (lossless) and VP8X (extended, animation and alpha).
sub _webp ($content) {
    return if length $content < $WEBP_HEADER;
    return if $content !~ /\A RIFF .{4} WEBP/msx;

    my $kind = substr $content, 12, $MARKER_LENGTH;
    if ( $kind eq 'VP8 ' ) {
        my ( $width, $height ) = unpack 'v v', substr $content, $VP8_START,
          $MARKER_LENGTH;
        return ( $width & $FOURTEEN_BITS, $height & $FOURTEEN_BITS );
    }
    if ( $kind eq 'VP8L' ) {
        my $bits = unpack 'V', substr $content, $VP8L_START, $MARKER_LENGTH;
        return ( ( $bits & $FOURTEEN_BITS ) + 1,
            ( ( $bits >> 14 ) & $FOURTEEN_BITS ) + 1 );
    }
    if ( $kind eq 'VP8X' ) {
        my ( $w0, $w1, $w2, $h0, $h1, $h2 ) = unpack 'C6', substr $content,
          $VP8X_START, 6;
        return (
            ( ( $w0 | $w1 << $BYTE | $w2 << ( 2 * $BYTE ) ) & $TWENTY_FOUR ) +
              1,
            ( ( $h0 | $h1 << $BYTE | $h2 << ( 2 * $BYTE ) ) & $TWENTY_FOUR ) +
              1
        );
    }

    return;
}

sub _crc32 ($bytes) {
    return Compress::Zlib::crc32($bytes);
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
