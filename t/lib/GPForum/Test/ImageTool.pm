# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::ImageTool;

use Compress::Zlib ();
use Mojo::Base -base, -signatures;
use v5.40;

use GPForum::X::Unavailable;

our $VERSION = '0.001';

has installed => 1;
has answer    => 'squares';    # squares, unreadable or unavailable
has calls     => sub { return []; };

sub engine ($self) { return 'fake'; }

sub available ($self) { return $self->installed; }

sub squares ( $self, $image, $sides ) {
    push @{ $self->calls }, { %{$image}, sides => [ @{$sides} ] };
    GPForum::X::Unavailable->throw( message => 'image tool timed out' )
      if $self->answer eq 'unavailable';
    return undef if $self->answer eq 'unreadable';

    return { map { $_ => $self->png( $_, $_ ) } @{$sides} };
}

# A PNG of the size given, one colour, with a text chunk a real tool might
# have kept.
sub png ( $class, $width, $height, %option ) {
    my $row = "\0" . ( pack 'C3', 200, 120, 40 ) x $width;
    my $png =
        "\x89PNG\x0d\x0a\x1a\x0a"
      . _chunk( 'IHDR', pack 'N N C C C C C', $width, $height, 8, 2, 0, 0, 0 )
      . ( $option{comment} ? _chunk( 'tEXt', "Comment\0$option{comment}" ) : q{} )
      . _chunk( 'IDAT', Compress::Zlib::compress( $row x $height ) )
      . _chunk( 'IEND', q{} );

    return $png;
}

sub _chunk ( $type, $data ) {
    return
        pack( 'N', length $data )
      . $type
      . $data
      . pack( 'N', Compress::Zlib::crc32( $type . $data ) );
}

1;

__END__

=head1 NAME

GPForum::Test::ImageTool - An image tool that answers as a test asks.

=head1 SYNOPSIS

    my $tool = GPForum::Test::ImageTool->new;
    $app->helper( gp_image_tool => sub { return $tool; } );
    my $upload = GPForum::Test::ImageTool->png( 300, 200 );

=head1 DESCRIPTION

Stands in for L<GPForum::Infrastructure::ImageTool> (ADR 0144): squares of
the sides asked for, in one colour, or undef (C<unreadable>), or
L<GPForum::X::Unavailable> (C<unavailable>). C<png> builds a valid PNG of
any size, for uploads.

=cut
