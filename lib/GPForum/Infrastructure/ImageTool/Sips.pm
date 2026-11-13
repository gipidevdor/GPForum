# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Infrastructure::ImageTool::Sips;

use List::Util qw(min max);
use Mojo::Base 'GPForum::Infrastructure::ImageTool', -signatures;
use v5.40;

our $VERSION = '0.001';

sub engine ($self) {
    return 'sips';
}

# sips applies its operations in an order of its own, so the crop and the
# resampling are separate runs: the largest centred square first, as a PNG,
# then each side from it.
sub commands ( $self, $source, $directory, $image, $sides ) {
    my $side   = min( $image->{width}, $image->{height} );
    my $square = "$directory/square.png";

    return (
        [
            $self->program, '-s',  'format', 'png',
            '-c',           $side, $side,    $source,
            '--out',        $square,
        ],
        map {
            [
                $self->program, '-z', $_, $_, $square,
                '--out',        "$directory/avatar-$_.png",
            ]
        } @{$sides}
    );
}

sub preview_commands ( $self, $source, $directory, $image, $bounds ) {
    my $longest = max( $image->{width}, $image->{height} );
    return map {
        [
            $self->program, '-s',    'format', 'png', '-Z', min( $_, $longest ),
            $source,        '--out', "$directory/preview-$_.png"
        ]
    } @{$bounds};
}

1;

__END__

=head1 NAME

GPForum::Infrastructure::ImageTool::Sips - Square crops with macOS's sips.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $tool = GPForum::Infrastructure::ImageTool::Sips->new(
        program => '/usr/bin/sips' );
    my $squares = $tool->squares( $image, [ 64, 128, 256 ] );

=head1 DESCRIPTION

The image tool every Mac has, for a development machine without Homebrew's
vips. See L<GPForum::Infrastructure::ImageTool>.

=head1 SUBROUTINES/METHODS

=head2 engine

C<sips>.

=head2 preview_commands

Names bounded resampling commands that retain the full picture without cropping
or enlarging it. The common image-tool layer checks dimensions and strips metadata.

=head2 commands

C<sips -s format png -c S S SOURCE --out DIR/square.png>, S the picture's
shorter side, then C<sips -z N N DIR/square.png --out DIR/avatar-N.png> for
each side N.

=head1 DIAGNOSTICS

See L<GPForum::Infrastructure::ImageTool>.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Infrastructure::ImageTool>, L<List::Util>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

sips does not turn a photo by its EXIF orientation.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
