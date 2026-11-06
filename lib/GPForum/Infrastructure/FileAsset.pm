# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Infrastructure::FileAsset;
use Mojo::Base 'Mojo::Asset::File', -signatures;
use v5.40;
use Carp qw(croak);
use Const::Fast;
use List::Util qw(min);
use GPForum::Infrastructure::AsyncWork;

our $VERSION = '0.001';
const my $STAT_SIZE  => 7;
const my $STAT_MTIME => 9;
has descriptor  => sub { return {}; };
has chunk_bytes => 262_144;

sub from_path_p ( $class, $path, $cleanup = 0 ) {
    return GPForum::Infrastructure::AsyncWork->shared->run_p(
        sub {
            my @stat = stat $path;
            croak 'file unavailable' if !@stat || !-f $path;
            return {
                path   => "$path",
                size   => $stat[$STAT_SIZE],
                mtime  => $stat[$STAT_MTIME],
                device => $stat[0],
                inode  => $stat[1]
            };
        }
    )->then(
        sub ($metadata) {
            return $class->from_descriptor( $metadata, $cleanup );
        }
    );
}

sub from_descriptor ( $class, $metadata, $cleanup = 0 ) {
    return $class->new(
        path       => $metadata->{path},
        descriptor => $metadata,
        cleanup    => $cleanup
    );
}

sub size  ($self) { return $self->descriptor->{size}; }
sub mtime ($self) { return $self->descriptor->{mtime}; }

sub get_chunk_p ( $self, $offset ) {
    my $metadata = $self->descriptor;
    my $start    = ( $self->start_range // 0 ) + $offset;
    my $end      = $self->end_range // ( $self->size - 1 );
    my $length   = min( $self->chunk_bytes, $end - $start + 1 );
    return GPForum::Infrastructure::AsyncWork->shared->run_p(
        sub {
            return q{} if $length <= 0;
            open my $file, '<:raw', $metadata->{path}    ## no critic (InputOutput::RequireBriefOpen) -- validate and read one bounded chunk before closing this descriptor
              or croak 'file unavailable';
            my @stat = stat $file;
            croak 'file changed while streaming'
              if !-f $file
              || $stat[0] != $metadata->{device}
              || $stat[1] != $metadata->{inode}
              || $stat[$STAT_SIZE] != $metadata->{size}
              || $stat[$STAT_MTIME] != $metadata->{mtime};
            defined( sysseek $file, $start, 0 )
              or croak 'cannot seek streamed file';
            my $bytes;
            my $count = read $file, $bytes, $length;
            croak 'cannot read streamed file' if !defined $count;
            close $file or croak 'cannot close streamed file';
            return $bytes;
        }
    );
}

1;

__END__

=head1 NAME

GPForum::Infrastructure::FileAsset - Bounded asynchronous local-file reads.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $asset = await GPForum::Infrastructure::FileAsset->from_path_p($path);

=head1 DESCRIPTION

Reads metadata and bounded chunks through the shared subprocess executor. The
HTTP controller requests the next chunk only after the preceding write drains.
Device, inode, size and modification time bind every read to the original file.

=head1 SUBROUTINES/METHODS

=head2 from_path_p

Loads a regular file's metadata without blocking the HTTP reactor.

=head2 from_descriptor

Adopts trusted metadata already produced by an isolated service.

=head2 size, mtime

Return the captured metadata without touching the filesystem.

=head2 get_chunk_p

Reads at most 256 KiB within the selected byte range.

=head1 DIAGNOSTICS

Missing, changed or unreadable files reject their promise.

=head1 CONFIGURATION AND ENVIRONMENT

Uses the per-worker shared executor and its admission limits.

=head1 DEPENDENCIES

Mojolicious and GPForum::Infrastructure::AsyncWork.

=head1 INCOMPATIBILITIES

The synchronous get_chunk interface is for framework compatibility only.

=head1 BUGS AND LIMITATIONS

Temporary-file unlinking follows Mojo::Asset::File's lifetime management.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. BSD-3-Clause.

=cut
