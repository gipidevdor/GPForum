# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Infrastructure::ImageTool::Vips;

use Mojo::Base 'GPForum::Infrastructure::ImageTool', -signatures;
use v5.40;

our $VERSION = '0.001';

sub engine ($self) {
    return 'vips';
}

# One run a side: vipsthumbnail shrinks (or enlarges) the picture until its
# shorter side fills the square, crops the rest away about the centre,
# turns it by its EXIF orientation, and takes the first frame of an
# animation.
sub commands ( $self, $source, $directory, $image, $sides ) {
    return map {
        [
            $self->program, $source,
            '--size',       "${_}x$_",
            '--smartcrop',  'centre',
            '-o',           "$directory/avatar-$_.png",
        ]
    } @{$sides};
}

1;

__END__

=head1 NAME

GPForum::Infrastructure::ImageTool::Vips - Square crops with libvips' vipsthumbnail.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $tool = GPForum::Infrastructure::ImageTool::Vips->new(
        program => '/usr/bin/vipsthumbnail' );
    my $squares = $tool->squares( $image, [ 64, 128, 256 ] );

=head1 DESCRIPTION

The image tool of Debian and Ubuntu (C<libvips-tools>), FreeBSD (C<vips>)
and Homebrew (C<vips>). See L<GPForum::Infrastructure::ImageTool>.

=head1 SUBROUTINES/METHODS

=head2 engine

C<vips>.

=head2 commands

One C<vipsthumbnail SOURCE --size NxN --smartcrop centre -o DIR/avatar-N.png>
for each side N.

=head1 DIAGNOSTICS

See L<GPForum::Infrastructure::ImageTool>.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Infrastructure::ImageTool>; vipsthumbnail 8.8 or later.

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
