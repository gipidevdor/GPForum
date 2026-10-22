# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::ImageTool;

use Compress::Zlib ();
use Const::Fast;
use Mojo::Base -base, -signatures;
use v5.40;

use GPForum::X::Unavailable;

our $VERSION = '0.001';

const my $PNG_SIGNATURE => pack 'H*', '89504e470d0a1a0a';
const my $ZERO          => pack 'C',  0;
const my $DEPTH         => 8;
const my $TRUE_COLOUR   => 2;
const my @COLOUR        => ( 200, 120, 40 );
const my $JFIF_LENGTH   => 16;
const my $SOF_LENGTH    => 11;
const my $MARKER_PREFIX => 0xff;

# JPEG's start, a JFIF segment, a frame header of the marker given and the
# end, around the frame's height and width.
const my $JPEG_HEAD => pack 'H*', 'ffd8ffe0';
const my $JFIF      => pack 'H*', '4a46494600010100000100010000';
const my $COMPONENT => pack 'H*', '011100';
const my $JPEG_END  => pack 'H*', 'ffd9';

has installed => 1;
has answer    => 'squares';            # squares, unreadable or unavailable
has calls     => sub { return []; };

sub engine ($self) { return 'fake'; }

sub available ($self) { return $self->installed; }

sub squares ( $self, $image, $sides ) {
    push @{ $self->calls }, { %{$image}, sides => [ @{$sides} ] };
    if ( $self->answer eq 'unavailable' ) {
        GPForum::X::Unavailable->throw( message => 'image tool timed out' );
    }
    return undef if $self->answer eq 'unreadable';

    return { map { $_ => $self->png( $_, $_ ) } @{$sides} };
}

# A PNG of the size given, one colour, with a text chunk a real tool might
# have kept when a comment is given.
sub png ( $class, $width, $height, %option ) {
    my $row = $ZERO . ( pack 'C3', @COLOUR ) x $width;
    my $comment =
      $option{comment}
      ? _chunk( 'tEXt', join $ZERO, 'Comment', $option{comment} )
      : q{};

    return
        $PNG_SIGNATURE
      . $class->png_header( $width, $height )
      . $comment
      . _chunk( 'IDAT', Compress::Zlib::compress( $row x $height ) )
      . _chunk( 'IEND', q{} );
}

# A PNG's header chunk alone: its size, and no picture.
sub png_header ( $class, $width, $height ) {
    return _chunk( 'IHDR', pack 'N N C C C C C',
        $width, $height, $DEPTH, $TRUE_COLOUR, 0, 0, 0 );
}

# A PNG's signature and header: enough to be sniffed and measured.
sub png_start ( $class, $width, $height ) {
    return $PNG_SIGNATURE . $class->png_header( $width, $height );
}

# A JPEG's start, a frame header of the marker given (0xc0 baseline, 0xc2
# progressive) and its end: enough to be sniffed and measured.
sub jpeg ( $class, $marker, $width, $height ) {
    return
        $JPEG_HEAD
      . pack( 'n', $JFIF_LENGTH )
      . $JFIF
      . pack( 'C C n C n n C',
        $MARKER_PREFIX, $marker, $SOF_LENGTH, $DEPTH, $height, $width, 1 )
      . $COMPONENT
      . $JPEG_END;
}

sub _chunk ( $type, $data ) {
    return pack( 'N', length $data ) . $type . $data . pack 'N',
      Compress::Zlib::crc32( $type . $data );
}

1;

__END__

=head1 NAME

GPForum::Test::ImageTool - An image tool that answers as a test asks, and the pictures to give it.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $tool = GPForum::Test::ImageTool->new;
    $app->helper( gp_image_tool => sub { return $tool; } );
    my $upload = GPForum::Test::ImageTool->png( 300, 200 );

=head1 DESCRIPTION

Stands in for L<GPForum::Infrastructure::ImageTool> (ADR 0144): squares of
the sides asked for, in one colour, or undef (C<unreadable>), or
L<GPForum::X::Unavailable> (C<unavailable>). Its class methods build the
pictures the tests upload.

=head1 SUBROUTINES/METHODS

=head2 installed

Whether the tool is installed (1).

=head2 answer

C<squares>, C<unreadable> or C<unavailable>.

=head2 calls

Each picture the tool was asked to square, with its C<sides>.

=head2 engine

C<fake>.

=head2 available

L</installed>.

=head2 squares

As the real tool's, answering as L</answer> says.

=head2 png

A valid PNG of a width and height; with C<< comment => TEXT >>, a C<tEXt>
chunk too.

=head2 png_header

The C<IHDR> chunk of a width and height.

=head2 png_start

A PNG's signature and header, with no picture.

=head2 jpeg

A JPEG's start, a frame header of the marker given and its end.

=head1 DIAGNOSTICS

None.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<Compress::Zlib>, L<GPForum::X::Unavailable>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

None known.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause
license.

=cut
