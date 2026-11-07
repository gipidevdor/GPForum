# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Infrastructure::FileAsset;
use Mojo::Base 'Mojo::Asset::File', -signatures;
use v5.40;
use List::Util qw(min);
use Mojo::Promise;
use GPForum::Infrastructure::FileReader;

our $VERSION = '0.001';
has descriptor    => sub { return {}; };
has chunk_bytes   => 262_144;
has reader        => undef;    # optional: opened lazily for trusted descriptors
has query_context => undef;    # optional: HTTP admission cancellation

sub from_path_p ( $class, $path, $cleanup = 0, $context = undef ) {
    my $reader =
      GPForum::Infrastructure::FileReader->start( $path, undef, $context );
    return $reader->ready->then(
        sub ($metadata) {
            return $class->new(
                path          => $metadata->{path},
                descriptor    => $metadata,
                cleanup       => $cleanup,
                reader        => $reader,
                query_context => $context
            );
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
    return Mojo::Promise->resolve(q{}) if $length <= 0;
    my $reader = $self->reader // $self->reader(
        GPForum::Infrastructure::FileReader->start(
            $metadata->{path}, $metadata, $self->query_context
        )
    )->reader;
    return $reader->read_p( $start, $length );
}

sub release_stream ($self) {
    if ( $self->reader ) { $self->reader->release_stream; }
    return;
}

sub DESTROY ($self) {
    if ( ${^GLOBAL_PHASE} ne 'DESTRUCT' ) { $self->release_stream; }    ## no critic (Variables::ProhibitPunctuationVars) -- Perl exposes its destruction phase only through this special variable
    return $self->SUPER::DESTROY;
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

Reads metadata and bounded chunks through one persistent FileReader child per
transfer. Its admission lane is separate from rendering and blocking services.
The HTTP controller requests another chunk only after the preceding write
drains, and releases the reader on completion or disconnect. Device, inode,
size and modification time bind every read to the original file.

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

Uses FileReader's per-worker admission limit of two active transfers.

=head1 DEPENDENCIES

Mojolicious and GPForum::Infrastructure::FileReader.

=head1 INCOMPATIBILITIES

The synchronous get_chunk interface is for framework compatibility only.

=head1 BUGS AND LIMITATIONS

Temporary-file unlinking follows Mojo::Asset::File's lifetime management.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. BSD-3-Clause.

=cut
