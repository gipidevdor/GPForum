# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;
use Const::Fast;
use Test::More;
use lib 'lib';

use GPForum::Infrastructure::ImageMetadata;
use GPForum::Service::Attachment::Source;

our $VERSION = '0.001';

const my $CLASS       => 'GPForum::Infrastructure::ImageMetadata';
const my $ORIENTATION => 0x01_12;
const my $GPS_INFO    => 0x88_25;
const my $LATITUDE    => 0x00_02;
const my $SHORT       => 3;
const my $LONG        => 4;
const my $RATIONAL    => 5;
const my $ROTATED     => 6;
const my $DEGREES     => 41;
const my $THREE       => 3;
const my $TIFF_MAGIC  => 42;
const my $MINUTES     => 54;
const my $TABLE_BYTES => 4;
const my $EXIF_HEADER => 6;
const my $ABSENT      => -1;
const my $OVERSIZED   => 400;
const my $IHDR_BYTES  => 13;
const my $VP8X_REST   => 9;
const my $METADATA    => 0x0c;
const my $IFD0        => 8;
const my $ENTRY       => 12;
const my $TWO_ENTRIES => 2 + 2 * $ENTRY + 4;
const my $ONE_ENTRY   => 2 + $ENTRY + 4;
const my $SCAN        => pack( 'H*', 'ffda000801010000003f00' ) . 'pixels';
const my $END         => pack 'H*', 'ffd9';
const my $XMP => "http://ns.adobe.com/xap/1.0/\0<x:xmpmeta>"
  . '<exif:GPSLatitude>41,54N</exif:GPSLatitude></x:xmpmeta>';

# A phone's JPEG: Exif with an orientation and a GPS directory whose
# latitude lies outside the entry, then an XMP packet repeating it.
sub _tiff ( $pack_short, $pack_long, $order ) {
    my $gps = $IFD0 + $TWO_ENTRIES;
    my $lat = $gps + $ONE_ENTRY;
    return
        $order
      . pack( $pack_short, $TIFF_MAGIC )
      . pack( $pack_long,  $IFD0 )
      . pack( $pack_short, 2 )
      . pack( "$pack_short$pack_short$pack_long$pack_short$pack_short",
        $ORIENTATION, $SHORT, 1, $ROTATED, 0 )
      . pack( "$pack_short$pack_short$pack_long$pack_long",
        $GPS_INFO, $LONG, 1, $gps )
      . pack( $pack_long,  0 )
      . pack( $pack_short, 1 )
      . pack( "$pack_short$pack_short$pack_long$pack_long",
        $LATITUDE, $RATIONAL, $THREE, $lat )
      . pack( $pack_long, 0 )
      . pack "$pack_long$pack_long" x $THREE, $DEGREES, 1, $MINUTES, 1, 0, 1;
}

sub _segment ( $marker, $payload ) {
    return pack( 'H2H2n', 'ff', $marker, 2 + length $payload ) . $payload;
}

for my $case ( [ 'II', 'v', 'V' ], [ 'MM', 'n', 'N' ] ) {
    my ( $order, $short, $long ) = @{$case};
    my $tiff = _tiff( $short, $long, $order );
    my $jpeg =
        pack( 'H*', 'ffd8' )
      . _segment( 'e1', "Exif\0\0$tiff" )
      . _segment( 'e1', $XMP )
      . _segment( 'db', 'q' x $TABLE_BYTES )
      . $SCAN
      . $END;
    my $clean = $CLASS->without_location($jpeg);
    my $exif  = index $clean, "Exif\0\0";
    my $kept  = substr $clean, $exif + $EXIF_HEADER, length $tiff;

    is(
        length $clean,
        length($jpeg) - length _segment( 'e1', $XMP ),
        "$order: only the XMP packet leaves"
    );
    is( index( $clean, 'GPSLatitude' ),
        $ABSENT, "$order: its latitude with it" );
    is(
        substr( $kept, 0, $IFD0 + $TWO_ENTRIES ),
        substr( $tiff, 0, $IFD0 + $TWO_ENTRIES ),
        "$order: the first directory, orientation included, is untouched"
    );
    is(
        substr( $kept, $IFD0 + $TWO_ENTRIES ),
        "\0" x ( length($tiff) - $IFD0 - $TWO_ENTRIES ),
        "$order: the GPS directory and its latitude are zeroed"
    );
    ok( $clean =~ /\Q$SCAN$END\E\z/msx, "$order: the scan is copied whole" );
}

my $plain =
  pack( 'H*', 'ffd8' ) . _segment( 'db', 'q' x $TABLE_BYTES ) . $SCAN . $END;
is( $CLASS->without_location($plain), $plain, 'a JPEG without them stays' );
is( $CLASS->without_location('%PDF-1.7'),
    '%PDF-1.7', 'other bytes are not touched' );
my $truncated = pack( 'H*', 'ffd8ffe1' ) . pack( 'n', $OVERSIZED ) . 'Exif';
is( $CLASS->without_location($truncated),
    $truncated, 'a file it cannot walk comes back as it was' );

sub _chunk ( $type, $data ) {
    return pack( 'Na4', length $data, $type ) . $data . 'crc!';
}
my $png_head =
  pack( 'H*', '89504e470d0a1a0a' ) . _chunk( 'IHDR', 'h' x $IHDR_BYTES );
my $png_tail = _chunk( 'IDAT', 'pixels' ) . _chunk( 'IEND', q{} );
is(
    $CLASS->without_location(
            $png_head
          . _chunk( 'eXIf', 'MM' )
          . _chunk( 'iTXt', "XML:com.adobe.xmp\0\0\0\0\0<x/>" )
          . _chunk( 'tEXt', "Title\0kept" )
          . $png_tail
    ),
    $png_head . _chunk( 'tEXt', "Title\0kept" ) . $png_tail,
    'a PNG loses its eXIf chunk and XMP text, nothing else'
);

sub _riff_chunk ( $type, $data ) {
    my $padded = length($data) % 2 ? "$data\0" : $data;
    return pack( 'a4V', $type, length $data ) . $padded;
}

sub _webp (@chunks) {
    my $body = join q{}, 'WEBP', @chunks;
    return 'RIFF' . pack( 'V', length $body ) . $body;
}
my $vp8x = sub ($flags) {
    return _riff_chunk( 'VP8X', pack( 'C', $flags ) . "\0" x $VP8X_REST );
};
is(
    $CLASS->without_location(
        _webp(
            $vp8x->($METADATA),
            _riff_chunk( 'VP8 ', 'frame' ),
            _riff_chunk( 'EXIF', 'MM' ),
            _riff_chunk( 'XMP ', '<x/>' )
        )
    ),
    _webp( $vp8x->(0), _riff_chunk( 'VP8 ', 'frame' ) ),
    'a WebP loses its EXIF and XMP chunks, its flags and size agreeing'
);

done_testing();

1;
