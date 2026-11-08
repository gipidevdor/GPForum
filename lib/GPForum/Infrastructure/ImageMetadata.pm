# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Infrastructure::ImageMetadata;

use Const::Fast;
use Mojo::Base -base, -signatures;
use v5.40;

our $VERSION = '0.001';

const my $JPEG_START     => pack 'H*', 'ffd8';
const my $PNG_SIGNATURE  => pack 'H*', '89504e470d0a1a0a';
const my $EXIF_HEADER    => "Exif\0\0";
const my $XMP_HEADER     => "http://ns.adobe.com/xap/1.0/\0";
const my $XMP_EXTENSION  => "http://ns.adobe.com/xmp/extension/\0";
const my $PNG_XMP        => "XML:com.adobe.xmp\0";
const my $MARKER         => 0xff;
const my $APP1           => 0xe1;
const my $START_OF_SCAN  => 0xda;
const my $END_OF_IMAGE   => 0xd9;
const my $RESTART_FIRST  => 0xd0;
const my $RESTART_LAST   => 0xd7;
const my $TEMPORARY      => 0x01;
const my $GPS_INFO       => 0x88_25;
const my $ENTRY          => 12;
const my $FIELD          => 4;
const my $PAIR           => 2;
const my $TIFF_HEADER    => 8;
const my $CHUNK_HEAD     => 8;
const my $CHUNK_CRC      => 4;
const my $RIFF_HEADER    => 12;
const my $VP8X_FLAGS     => 20;
const my $VP8X_METADATA  => 0x0c;
const my $SEGMENT_HEADER => 4;

# Bytes per value of each TIFF field type (TIFF 6.0 section 2).
const my %TYPE_SIZE => (
    1  => 1,
    2  => 1,
    3  => 2,
    4  => 4,
    5  => 8,
    6  => 1,
    7  => 1,
    8  => 2,
    9  => 4,
    10 => 8,
    11 => 4,
    12 => 8,
);

const my %REWRITE => ( jpeg => \&_jpeg, png => \&_png, webp => \&_webp );

# The picture's bytes without where it was taken: the GPS directory of a
# JPEG's Exif block is emptied in place (its other tags, the orientation
# among them, stay where they were), and XMP packets, which repeat the
# position, are dropped; a PNG loses its eXIf chunk and XMP text, a WebP its
# EXIF and XMP chunks. Pixels are never decoded; bytes of any other kind,
# and any structure this does not recognise, come back as they were.
sub without_location ( $class, $bytes ) {
    my $kind = $class->kind($bytes) or return $bytes;
    return $REWRITE{$kind}->($bytes) // $bytes;
}

# Which container the bytes begin as -- jpeg, png or webp -- or undef: the
# first dozen bytes are enough, so a caller can ask before reading a file.
sub kind ( $, $head ) {
    return undef  if !defined $head;
    return 'jpeg' if substr( $head, 0, $PAIR ) eq $JPEG_START;
    return 'png'
      if substr( $head, 0, length $PNG_SIGNATURE ) eq $PNG_SIGNATURE;
    return 'webp'
      if substr( $head, 0,           $FIELD ) eq 'RIFF'
      && substr( $head, $CHUNK_HEAD, $FIELD ) eq 'WEBP';
    return undef;
}

# Every marker segment before the scan, each kept or rewritten; the scan and
# whatever follows it are copied as they are. Undef for a malformed file.
sub _jpeg ($bytes) {
    my $out    = $JPEG_START;
    my $offset = $PAIR;
    while ( $offset + $SEGMENT_HEADER <= length $bytes ) {
        my ( $prefix, $marker ) = unpack 'CC', substr $bytes, $offset, $PAIR;
        return undef if $prefix != $MARKER;
        if ( _standalone($marker) ) {
            $out .= substr $bytes, $offset, $PAIR;
            $offset += $PAIR;
            next;
        }
        return $out . substr $bytes, $offset
          if $marker == $START_OF_SCAN || $marker == $END_OF_IMAGE;
        my $length = unpack 'n', substr $bytes, $offset + $PAIR, $PAIR;
        return undef
          if $length < $PAIR || $offset + $PAIR + $length > length $bytes;
        my $segment = substr $bytes, $offset, $PAIR + $length;
        $out .= _jpeg_segment( $marker, $segment );
        $offset += $PAIR + $length;
    }
    return undef;
}

sub _standalone ($marker) {
    return $marker == $TEMPORARY
      || ( $marker >= $RESTART_FIRST && $marker <= $RESTART_LAST );
}

sub _jpeg_segment ( $marker, $segment ) {
    return $segment if $marker != $APP1;
    my $payload = substr $segment, $SEGMENT_HEADER;
    return q{}
      if _starts( $payload, $XMP_HEADER )
      || _starts( $payload, $XMP_EXTENSION );
    return $segment if !_starts( $payload, $EXIF_HEADER );
    my $tiff = substr $payload, length $EXIF_HEADER;
    my $kept = _without_gps($tiff) // return $segment;
    return substr( $segment, 0, $SEGMENT_HEADER + length $EXIF_HEADER ) . $kept;
}

sub _starts ( $bytes, $prefix ) {
    return substr( $bytes, 0, length $prefix ) eq $prefix;
}

# The TIFF block with its GPS directory emptied: every entry and every value
# it points to is zeroed and its count set to none, so no offset elsewhere
# in the block moves. Undef when the block is not TIFF as this reads it.
sub _without_gps ($tiff) {
    my $order = substr $tiff, 0, $PAIR;
    return undef if $order ne 'II' && $order ne 'MM';
    my $read = _reader( \$tiff, $order eq 'II' ? qw(v V) : qw(n N) );
    my $gps  = _gps_directory($read) // return undef;
    return $tiff if !$gps;
    my $entries = $read->( $gps, $PAIR ) // return undef;
    my $table   = $PAIR + $entries * $ENTRY + $FIELD;
    return undef if $gps + $table > length $tiff;

    for my $index ( 0 .. $entries - 1 ) {
        my ( $at, $bytes ) =
          _out_of_line( $read, $gps + $PAIR + $index * $ENTRY );
        next if !$bytes || $at + $bytes > length $tiff;
        substr $tiff, $at, $bytes, "\0" x $bytes;
    }
    substr $tiff, $gps, $table, "\0" x $table;
    return $tiff;
}

# A reader of the block's unsigned fields, two or four bytes wide, in its
# byte order: undef past the block's end.
sub _reader ( $tiff, $short, $long ) {
    my %format = ( $PAIR => $short, $FIELD => $long );
    return sub ( $at, $width ) {
        return undef if $at < 0 || $at + $width > length ${$tiff};
        return unpack $format{$width}, substr ${$tiff}, $at, $width;
    };
}

# The GPS directory's offset, 0 when the first directory has none, or undef
# for a block that ends early.
sub _gps_directory ($read) {
    my $first = $read->( $FIELD, $FIELD ) // return undef;
    my $count = $read->( $first, $PAIR )  // return undef;
    for my $index ( 0 .. $count - 1 ) {
        my $entry = $first + $PAIR + $index * $ENTRY;
        my $tag   = $read->( $entry, $PAIR ) // return undef;
        next if $tag != $GPS_INFO;
        return $read->( $entry + $TIFF_HEADER, $FIELD );
    }
    return 0;
}

# Where an entry's value lies and its size, when it does not fit in the
# entry itself; nothing otherwise.
sub _out_of_line ( $read, $entry ) {
    my $type  = $read->( $entry + $PAIR,  $PAIR )  // return;
    my $many  = $read->( $entry + $FIELD, $FIELD ) // return;
    my $bytes = ( $TYPE_SIZE{$type} // 0 ) * $many;
    return if $bytes <= $FIELD;
    my $at = $read->( $entry + $TIFF_HEADER, $FIELD ) // return;
    return ( $at, $bytes );
}

# The PNG's chunks without eXIf and the XMP text; undef if it is malformed.
sub _png ($bytes) {
    my $out    = $PNG_SIGNATURE;
    my $offset = length $PNG_SIGNATURE;
    while ( $offset + $CHUNK_HEAD <= length $bytes ) {
        my ( $length, $type ) = unpack 'Na4', substr $bytes, $offset,
          $CHUNK_HEAD;
        my $size = $CHUNK_HEAD + $length + $CHUNK_CRC;
        return undef if $offset + $size > length $bytes;
        my $data = substr $bytes, $offset + $CHUNK_HEAD, $length;
        if ( $type ne 'eXIf'
            && !( $type eq 'iTXt' && _starts( $data, $PNG_XMP ) ) )
        {
            $out .= substr $bytes, $offset, $size;
        }
        $offset += $size;
        return $out . substr $bytes, $offset if $type eq 'IEND';
    }
    return undef;
}

# The WebP's chunks without EXIF and XMP, its VP8X flags and RIFF size made
# to agree; undef if it is malformed.
sub _webp ($bytes) {
    my $out    = substr $bytes, 0, $RIFF_HEADER;
    my $offset = $RIFF_HEADER;
    while ( $offset + $CHUNK_HEAD <= length $bytes ) {
        my ( $type, $length ) = unpack 'a4V', substr $bytes, $offset,
          $CHUNK_HEAD;
        my $size = $CHUNK_HEAD + $length + ( $length % $PAIR );
        return undef if $offset + $size > length $bytes;
        if ( $type ne 'EXIF' && $type ne 'XMP ' ) {
            $out .= substr $bytes, $offset, $size;
        }
        $offset += $size;
    }
    return undef if $offset != length $bytes;
    if ( substr( $out, $RIFF_HEADER, $FIELD ) eq 'VP8X' ) {
        my $flags = unpack 'C', substr $out, $VP8X_FLAGS, 1;
        substr $out, $VP8X_FLAGS, 1, pack 'C', $flags & ~$VP8X_METADATA;
    }
    substr $out, $FIELD, $FIELD, pack 'V', length($out) - $CHUNK_HEAD;
    return $out;
}

1;

__END__

=head1 NAME

GPForum::Infrastructure::ImageMetadata - Remove location metadata from uploaded pictures.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $clean = GPForum::Infrastructure::ImageMetadata->without_location($bytes);

=head1 DESCRIPTION

A phone's camera writes where a picture was taken into its Exif GPS
directory, and often again into an XMP packet. An original served as
uploaded publishes that position. This class rewrites the container
without it, by its structure alone: no pixel is decoded, so the cost is a
walk over the file's segments or chunks.

=head1 SUBROUTINES/METHODS

=head2 without_location

Answers the bytes of a JPEG, PNG or WebP without its GPS directory and XMP
packets; any other bytes, and a file it cannot walk, come back unchanged.

=head2 kind

Names the container the leading bytes open -- C<jpeg>, C<png> or C<webp> --
or answers undef.

=head1 DIAGNOSTICS

None: unrecognised structure is returned as it was.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

Const::Fast and Mojo::Base.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

The JPEG's Exif keeps its other tags (camera, time, orientation). A PNG or
WebP loses its whole Exif block, orientation included, since neither format
lets one directory be emptied as simply; such files are rare. HEIC and GIF
are not rewritten.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. BSD-3-Clause.

=cut
