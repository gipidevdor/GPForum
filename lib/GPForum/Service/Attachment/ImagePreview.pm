# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Attachment::ImagePreview;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -signatures;
use v5.40;
use GPForum::Infrastructure::Row;

our $VERSION = '0.001';
const my $BOUND   => 1_280;
const my $VARIANT => 'preview-v1-1280';

__PACKAGE__->requires(qw(storage store));
has tool => undef;    # optional: previews require an installed image tool

sub variant_type { return $VARIANT; }

sub supported ( $self, $attachment ) {
    my $type =
      GPForum::Infrastructure::Row->column( $attachment, 'media_type' ) // q{};
    return
         $self->tool
      && $self->tool->can('previews')
      && $type =~ m{\Aimage/(?:png|jpeg)\z}msx;
}

sub existing ( $self, $attachment ) {
    return $self->store->find_variant(
        {
            attachment_id => GPForum::Infrastructure::Row->column(
                $attachment, 'attachment_id'
            ),
            variant_type => $VARIANT,
        }
    );
}

sub process ( $self, $attachment, $image ) {
    if ( !$self->supported($attachment) || $self->existing($attachment) ) {
        return;
    }

    if ( $self->_preserve_original($image) )                       { return; }
    if ( $image->{width} <= $BOUND && $image->{height} <= $BOUND ) { return; }
    my $previews = $self->tool->previews( $image, [$BOUND] );
    if ( !$previews ) { return; }
    my $content = $previews->{$BOUND}{content};
    if ( !defined $content || length($content) >= length( $image->{content} ) )
    {
        return;
    }
    my $key = join q{-},
      GPForum::Infrastructure::Row->column( $attachment, 'object_key' ),
      $VARIANT;
    if ( !$self->storage->exists_object($key) ) {
        $self->storage->write_object( $key, $content );
    }
    return $self->store->add_variant(
        {
            attachment_id => GPForum::Infrastructure::Row->column(
                $attachment, 'attachment_id'
            ),
            variant_type => $VARIANT,
            object_key   => $key,
            byte_size    => length($content),
            media_type   => 'image/png',
        }
    );
}

sub _preserve_original ( $self, $image ) {

    # Preserve animation. sips does not normalize EXIF orientation, so retain
    # the original for JPEGs with EXIF rather than strip their display rotation.
    if (
        (
            $image->{media_type} eq 'image/png'
            && index( $image->{content}, 'acTL' ) >= 0
        )
        || (   $self->tool->engine eq 'sips'
            && $image->{media_type} eq 'image/jpeg'
            && index( $image->{content}, "Exif\0\0" ) >= 0 )
      )
    {
        return 1;
    }
    return 0;
}

1;

__END__

=head1 NAME

GPForum::Service::Attachment::ImagePreview - Bounded image previews produced by the media worker.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    $preview->process($attachment, $bounded_source_image);

=head1 DESCRIPTION

Creates a metadata-free PNG fitting within 1280 by 1280 pixels without cropping
or enlarging the original. Stores only outputs smaller than the original using
the existing PostgreSQL attachment variant contract and storage backend.
The caller has checked availability, approval and source pixel bounds. GIF,
WebP and animated PNG retain their original representation. On macOS, JPEGs
with EXIF retain the original until an orientation-aware tool is installed.

=head1 SUBROUTINES/METHODS

=head2 variant_type

The versioned variant name used by generation and authorized delivery.

=head2 supported

Whether the configured tool can produce previews for this attachment type.

=head2 existing

Find the stored preview by the attachment's indexed identifier and variant type.

=head2 process

Accepts attachment metadata and an already read, dimension-checked source image.
Existing previews are reused. Small or unprofitable conversions are skipped.
Tool and storage failures propagate so the worker can retry.

=head1 DIAGNOSTICS

Native tool failures propagate as unavailable errors.

=head1 CONFIGURATION AND ENVIRONMENT

Uses the configured system image tool and attachment storage.

=head1 DEPENDENCIES

L<GPForum::Infrastructure::ImageTool>, L<GPForum::Service::Attachment::Store>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Previously processed images retain the original until media processing is rerun.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. BSD-3-Clause.

=cut
