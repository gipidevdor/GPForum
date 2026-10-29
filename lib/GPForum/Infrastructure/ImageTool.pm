# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Infrastructure::ImageTool;

use Carp qw(croak);
use Const::Fast;
use English    qw(-no_match_vars);
use File::Path qw(remove_tree);
use File::Spec;
use File::Temp qw(tempdir);
use IPC::Open3 qw(open3);
use Mojo::Base -base, -signatures;
use v5.40;
use Symbol qw(gensym);

use GPForum::OS;
use GPForum::Infrastructure::ImageBytes;
use GPForum::X::Unavailable;

our $VERSION = '0.001';

const my $DEFAULT_TIMEOUT => 20;
const my $PRIVATE_FILE    => oct '600';
const my $PRIVATE_DIR     => oct '700';
const my $SIGNAL_MASK     => 127;
const my %EXTENSION => (
    'image/gif'  => 'gif',
    'image/jpeg' => 'jpg',
    'image/png'  => 'png',
    'image/webp' => 'webp',
);

# The program the operating system installed, or undef when it has none:
# the tool is then unavailable and profile pictures are off.
has program         => undef;              # optional: undef is "not installed"
has timeout_seconds => $DEFAULT_TIMEOUT;
has bytes           => sub { return GPForum::Infrastructure::ImageBytes->new; };

# GPFORUM_IMAGE_TOOL: system, the tool the operating system installed, or
# none (ADR 0144).
sub from_config ( $class, $config, $os = undef ) {
    return undef if ( $config->image_tool // 'none' ) eq 'none';

    return $class->system_tool($os);
}

# libvips' vipsthumbnail where the system package put it, else macOS's own
# sips; an unavailable tool when neither is there.
sub system_tool ( $class, $os = undef ) {
    my $packaging = ( $os || GPForum::OS->detect )->image_tool_packaging;
    for my $candidate ( @{ $packaging->{vips} // [] } ) {
        my $found = resolved($candidate);
        if ($found) {
            require GPForum::Infrastructure::ImageTool::Vips;
            return GPForum::Infrastructure::ImageTool::Vips->new(
                program => $found );
        }
    }
    my $sips = resolved( $packaging->{sips} );
    if ($sips) {
        require GPForum::Infrastructure::ImageTool::Sips;
        return GPForum::Infrastructure::ImageTool::Sips->new(
            program => $sips );
    }

    require GPForum::Infrastructure::ImageTool::Vips;
    return GPForum::Infrastructure::ImageTool::Vips->new;
}

# An executable file, through PATH for a bare name as exec would find it.
sub resolved ($program) {
    return undef if !defined $program || !length $program;
    if ( $program =~ m{/}msx ) {
        return -f $program && -x _ ? $program : undef;
    }
    for my $directory ( File::Spec->path ) {
        my $candidate = File::Spec->catfile( $directory, $program );
        return $candidate if -f $candidate && -x _;
    }

    return undef;
}

sub engine ($self) {
    return 'none';
}

sub available ($self) {
    return defined resolved( $self->program ) ? 1 : 0;
}

# Whether the tool reads pictures of this media type: the kinds it is
# given a file extension for. squares refuses any other as not an image.
sub reads ( $, $media_type ) {
    return exists $EXTENSION{ $media_type // q{} } ? 1 : 0;
}

# The commands that write avatar-<side>.png into $directory for each side,
# from $source; a subclass's.
sub commands ( $self, $source, $directory, $image, $sides ) {
    croak 'an image tool names its commands';
}

# Squares of the picture, centre-cropped, one PNG per side asked for, with
# nothing but the picture in them: { 64 => $bytes, ... }. Undef when the tool
# could not read the picture or wrote something else. Throws
# GPForum::X::Unavailable when there is no tool, it cannot be started, or it
# outruns its time: the picture is not at fault, and is tried again.
sub squares ( $self, $image, $sides ) {
    if ( !$self->available ) {
        GPForum::X::Unavailable->throw( message => 'no image tool installed' );
    }
    my $media_type = $image->{media_type} // q{};
    if ( !exists $EXTENSION{$media_type} ) {
        GPForum::X::Unavailable->throw( message => 'not an image' );
    }
    my $extension = $EXTENSION{$media_type};

    my $directory =
      tempdir( 'gpforum-avatar-XXXXXXXX', TMPDIR => 1, CLEANUP => 0 );
    my ( $squares, $failure );
    try {
        chmod $PRIVATE_DIR, $directory or croak "chmod $directory: $ERRNO";
        $squares = $self->_squares_in( $directory, $extension, $image, $sides );
    }
    catch ($error) {
        $failure = $error;
    };
    remove_tree($directory);
    if ( defined $failure ) {
        croak $failure;
    }

    return $squares;
}

sub _squares_in ( $self, $directory, $extension, $image, $sides ) {
    my $source = "$directory/source.$extension";
    _write_private( $source, $image->{content} );

    my $deadline = time + $self->timeout_seconds;
    for my $command ( $self->commands( $source, $directory, $image, $sides ) ) {
        return undef if !$self->_ran( $command, $deadline );
    }

    my %squares;
    for my $side ( @{$sides} ) {
        my $written = _slurp("$directory/avatar-$side.png") // return undef;
        my $plain   = $self->bytes->plain_png($written)     // return undef;
        my $size    = $self->bytes->dimensions( $plain, 'image/png' );
        return undef
          if !$size || $size->{width} != $side || $size->{height} != $side;
        $squares{$side} = $plain;
    }

    return \%squares;
}

# True for a run that exited 0. The time left until the deadline covers the
# whole run; a tool killed by a signal -- a crash on a crafted file -- did
# not read the picture.
sub _ran ( $self, $command, $deadline ) {
    my $remaining = $deadline - time;
    if ( $remaining <= 0 ) {
        GPForum::X::Unavailable->throw( message => 'image tool timed out' );
    }

    my $output = gensym;
    my $pid;
    try {
        $pid = open3( my $input, $output, undef, @{$command} );
        close $input or croak "close image tool input: $ERRNO";
    }
    catch ($error) {
        GPForum::X::Unavailable->throw(
            message => 'image tool could not be started' );
    };

    my $status;
    try {
        local $SIG{ALRM} = sub {
            GPForum::X::Unavailable->throw( message => 'image tool timed out' );
        };
        alarm $remaining;
        local $INPUT_RECORD_SEPARATOR = undef;
        my $ignored = <$output>;
        waitpid $pid, 0;
        $status = $CHILD_ERROR;
        alarm 0;
    }
    catch ($error) {
        alarm 0;
        kill 'KILL', $pid;
        waitpid $pid, 0;
        croak $error;
    };

    return 0 if $status & $SIGNAL_MASK;

    return $status == 0 ? 1 : 0;
}

sub _write_private ( $path, $content ) {
    if ( !utf8::downgrade( $content, 1 ) ) {
        croak 'image content must be bytes, not characters';
    }
    open my $handle, '>:raw', $path or croak "open $path: $ERRNO";
    chmod $PRIVATE_FILE, $path or croak "chmod $path: $ERRNO";
    print {$handle} $content or croak "write $path: $ERRNO";
    close $handle            or croak "close $path: $ERRNO";

    return;
}

sub _slurp ($path) {
    return undef if !-f $path;
    open my $handle, '<:raw', $path or return undef;
    local $INPUT_RECORD_SEPARATOR = undef;
    my $content = <$handle>;
    close $handle or return undef;

    return $content;
}

1;

__END__

=head1 NAME

GPForum::Infrastructure::ImageTool - Crop a picture to squares with the image tool the system installed.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $tool = GPForum::Infrastructure::ImageTool->from_config($config);
    my $squares = $tool && $tool->available
      ? $tool->squares(
        {
            content    => $bytes,
            media_type => 'image/jpeg',
            width      => 4032,
            height     => 3024,
        },
        [ 64, 128, 256 ]
      )
      : undef;
    # { 64 => $png, 128 => $png, 256 => $png }, or undef

=head1 DESCRIPTION

ADR 0144: GPForum decodes no image itself and installs no image library. As
it scans with the system's antivirus (ADR 0108), it crops profile pictures
with the system's image tool: libvips' C<vipsthumbnail>
(L<GPForum::Infrastructure::ImageTool::Vips>), which Debian, Ubuntu, FreeBSD
and Homebrew package, or, on macOS without it, the C<sips> every Mac has
(L<GPForum::Infrastructure::ImageTool::Sips>). The operating system layer
says where each package puts it (C<image_tool_packaging>).

The picture is written to a private temporary directory, the tool runs
without a shell, once per command, within one deadline for the whole
picture, and its PNGs are read back, each rewritten by
L<GPForum::Infrastructure::ImageBytes/plain_png> and checked to be the
square asked for. The directory is removed whatever happens.

=head1 SUBROUTINES/METHODS

=head2 from_config

The tool for a L<GPForum::Config>: undef when C<GPFORUM_IMAGE_TOOL> is
C<none>, otherwise L</system_tool>.

=head2 system_tool

Takes an optional L<GPForum::OS> profile. The first C<vipsthumbnail> the
profile names that is an executable file, else its C<sips>, else a tool
whose L</available> is false.

=head2 resolved

Takes a program: a path, or a name looked up on C<PATH>. Returns the
executable file, or undef.

=head2 engine

The tool's name: C<vips>, C<sips>, or C<none> here.

=head2 available

True when the program is an executable file.

=head2 reads

Takes a media type. True when the tool reads pictures of that kind: the
kinds L</squares> takes, C<image/gif>, C<image/jpeg>, C<image/png> and
C<image/webp>.

=head2 commands

A subclass's: the commands, as array references, that write
C<< avatar-<side>.png >> into the directory for each side.

=head2 squares

Takes C<< { content, media_type, width, height } >> and an array reference
of sides in pixels. Returns C<< { side => png } >>, or undef when the tool
exited with an error, was killed by a signal, or wrote no PNG of the size
asked for.

=head1 DIAGNOSTICS

Throws L<GPForum::X::Unavailable> when no tool is installed, it cannot be
started or it outruns C<timeout_seconds> (20 by default); croaks when the
temporary files cannot be written.

=head1 CONFIGURATION AND ENVIRONMENT

C<GPFORUM_IMAGE_TOOL>, through L</from_config>.

=head1 DEPENDENCIES

L<GPForum::OS>, L<GPForum::Infrastructure::ImageBytes>,
L<IPC::Open3>, L<File::Temp>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

C<sips> does not turn a photo by its EXIF orientation; C<vipsthumbnail>
does.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause
license.

=cut
