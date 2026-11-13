# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Attachment::MediaProcessor;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -signatures;
use v5.40;

use GPForum::Infrastructure::ImageBytes;
use GPForum::Infrastructure::Row qw(column_of);
use GPForum::Service::Attachment::ImagePreview;

our $VERSION = '0.001';

const my $THUMBNAIL => 'thumbnail';

# The thumbnail's side, in pixels: a square, as the image tool makes them
# for profile pictures (ADR 0144), large enough for a grid of a thread's
# pictures and small beside the original.
const my $THUMBNAIL_SIDE => 320;
const my $THUMBNAIL_TYPE => 'image/png';

__PACKAGE__->requires(qw(storage store));

# ADR 0144: members' profile pictures (Service::Community::Avatars), which
# take the place of the thumbnail for an upload waiting to be one.
has avatars => undef;    # optional: without it every image gets a thumbnail

# The system's image tool (Infrastructure::ImageTool), which makes the
# thumbnail; without one, or with one the host has not installed, an image
# is left as it is and the event is done.
has image_tool => undef;          # optional: without it no thumbnail is made
has preview    => sub ($self) {
    return GPForum::Service::Attachment::ImagePreview->new(
        storage => $self->storage,
        store   => $self->store,
        tool    => $self->image_tool,
    );
};
has bytes => sub { return GPForum::Infrastructure::ImageBytes->new; };

# No transaction spans the image tool's runs: each variant is written once
# by its key (Store::add_variant answers the row a concurrent delivery
# wrote), its bytes before its row, and a member's picture commits its own
# rows (Community::Avatars).
sub process ( $self, $attachment_id ) {
    my $attachment = $self->store->find_attachment($attachment_id);
    my $rejected   = _rejected_attachment($attachment);
    if ($rejected) {
        return $rejected;
    }

    if ( $self->avatars ) {
        my $picture = $self->avatars->process($attachment_id);
        return { %{$picture}, avatar => 1 } if $picture;
    }

    my $existing = $self->_existing_thumbnail($attachment_id);
    if (
        $existing
        && (  !$self->preview->supported($attachment)
            || $self->preview->existing($attachment) )
      )
    {
        return $self->_skipped_variant($existing);
    }
    my $tool = $self->image_tool;
    if ( !$tool || !$tool->available ) {
        return { ok => 1, skipped => 'no_image_tool' };
    }
    if ( !$tool->reads( _text( column_of( $attachment, 'media_type' ) ) ) ) {
        return { ok => 1, skipped => 'unreadable_image' };
    }

    return $self->_write_thumbnail( $attachment, $existing );
}

sub _rejected_attachment ($attachment) {
    if ( !$attachment ) {
        return { error => 'not_found', ok => 0 };
    }

    return _skipped_attachment($attachment);
}

sub _skipped_attachment ($attachment) {
    if ( _not_available($attachment) ) {
        return { ok => 1, skipped => 'not_available' };
    }
    if ( _not_image($attachment) ) {
        return { ok => 1, skipped => 'not_image' };
    }

    return undef;
}

sub _not_available ($attachment) {
    if ( _text( column_of( $attachment, 'state' ) ) ne 'available' ) {
        return 1;
    }

    return 0;
}

sub _not_image ($attachment) {
    if ( _text( column_of( $attachment, 'media_type' ) ) !~ /\A image\//msx ) {
        return 1;
    }

    return 0;
}

sub _text ($value) {
    if ( defined $value ) {
        return $value;
    }

    return q{};
}

sub _existing_thumbnail ( $self, $attachment_id ) {
    return $self->store->find_variant(
        {
            attachment_id => $attachment_id,
            variant_type  => $THUMBNAIL,
        }
    );
}

# The variant comes from the database: Record::row_hash read none of its
# columns, so a redelivered event answered with a thumbnail that had no type,
# no key and no id.
sub _skipped_variant ( $self, $existing ) {
    return {
        ok      => 1,
        skipped => 1,
        variant => {
            %{ $self->store->lifecycle->row_columns($existing) },
            idempotent => 1,
        },
    };
}

# The thumbnail: a square of the picture, centre-cropped and scaled by the
# image tool, as PNG. The variant used to be the original's bytes under a
# second key -- a copy of every picture, which nothing read -- and no
# picture was decoded. A picture the tool cannot read makes none.
sub _write_thumbnail ( $self, $attachment, $existing = undef ) {
    my $object_key = column_of( $attachment, 'object_key' );
    my $content    = $self->storage->read_object($object_key);
    my $media_type = column_of( $attachment, 'media_type' );

    # The tool is told the picture's size, which sips crops by: without it
    # it ran with none and failed every picture. And it is not handed a
    # canvas past a profile picture's bounds: a small file may declare a
    # huge one, which cost the tool its whole timeout on every retry.
    my $size = $self->bytes->dimensions( $content, $media_type );
    return { ok => 1, skipped => 'unreadable_image' } if !$size;
    return { ok => 1, skipped => 'too_many_pixels' }
      if $self->bytes->too_big($size);
    my $image = { %{$size}, content => $content, media_type => $media_type };
    $self->preview->process( $attachment, $image );
    if ($existing) { return $self->_skipped_variant($existing); }
    my $squares = $self->image_tool->squares( $image, [$THUMBNAIL_SIDE] );

    if ( !$squares ) {
        return { ok => 1, skipped => 'unreadable_image' };
    }
    my $thumbnail   = $squares->{$THUMBNAIL_SIDE};
    my $variant_key = join q{-}, $object_key, $THUMBNAIL;
    $self->_store_thumbnail_object( $variant_key, $thumbnail );

    return {
        ok      => 1,
        variant => $self->store->add_variant(
            {
                attachment_id => column_of( $attachment, 'attachment_id' ),
                byte_size     => length $thumbnail,
                media_type    => $THUMBNAIL_TYPE,
                object_key    => $variant_key,
                variant_type  => $THUMBNAIL,
            }
        ),
    };
}

sub _store_thumbnail_object ( $self, $variant_key, $content ) {
    if ( $self->storage->exists_object($variant_key) ) {
        return;
    }

    $self->storage->write_object( $variant_key, $content );

    return;
}

1;

__END__

=head1 NAME

GPForum::Service::Attachment::MediaProcessor - Record thumbnails and inline image previews.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $processor = GPForum::Service::Attachment::MediaProcessor->new(
        image_tool => $image_tool,
        storage    => $attachment_storage,
        store      => $attachment_store,
    );
    my $result = $processor->process($attachment_id);
    # { ok => 1, variant => {...} }, { ok => 1, skipped => ... }
    # or { ok => 0, error => 'not_found' }

=head1 DESCRIPTION

Run by the media processing worker
(L<GPForum::Worker::Handler::MediaProcessing>) for an attachment event. For
an available attachment whose media type starts with C<image/>, it has the
system's image tool (L<GPForum::Infrastructure::ImageTool>, ADR 0144) make
a 320-pixel square of the picture, centre-cropped, as PNG, writes it under
the key C<< <object_key>-thumbnail >> and records it as the C<thumbnail>
variant through L<GPForum::Service::Attachment::Store>.

The source read and pixel bounds are shared with
L<GPForum::Service::Attachment::ImagePreview>, which records a proportional
1280-pixel inline preview when the configured tool supports it and its encoded
bytes are smaller. An existing thumbnail is reused while a missing preview may
be created. Existing preview objects and variant rows are reused on redelivery.
Without an installed image tool, or for an unreadable picture, the event
finishes without generating new variants. No conversion runs in an HTTP read.

=head1 SUBROUTINES/METHODS

=head2 preview

The optional image preview generator, sharing the source read and pixel bounds
with thumbnail processing. Previews run only with a supporting image tool.

=head2 new

Constructor (L<GPForum::Base>). C<storage> (an object with C<read_object>,
C<exists_object> and C<write_object>, such as
L<GPForum::Service::Attachment::FilesystemStorage>) and C<store>, the
L<GPForum::Service::Attachment::Store> that records the variant, are required:
a missing one throws L<GPForum::X::Argument>. C<avatars>, a
L<GPForum::Service::Community::Avatars>, is optional: an upload waiting to be
a member's profile picture is then cropped to its squares instead
(ADR 0144), and the answer is the avatars' with C<< avatar => 1 >>.
C<image_tool>, a L<GPForum::Infrastructure::ImageTool>, is optional: without
one no thumbnail or inline preview is made.

=head2 process

Takes an attachment id. Returns a hash reference:

=over 4

=item * C<< { ok => 0, error => 'not_found' } >> when there is no such
attachment;

=item * C<< { ok => 1, skipped => 'not_available' } >> when its state is
not C<available>;

=item * C<< { ok => 1, skipped => 'not_image' } >> when its media type does
not start with C<image/>;

=item * C<< { ok => 1, skipped => 1, variant => {...} } >> when a thumbnail
variant already exists (a missing supported preview may still be produced);
the variant's columns come with
C<< idempotent => 1 >>;

=item * C<< { ok => 1, skipped => 'no_image_tool' } >> without an image
tool, or with one the host has not installed;

=item * C<< { ok => 1, skipped => 'unreadable_image' } >> for a picture of
a kind the tool does not read, or one it could not read;

=item * C<< { ok => 1, variant => {...} } >> after writing the square and
adding the variant (C<media_type> C<image/png>, C<byte_size> the square's
length, also when the object was already there and not written).

=back

=head1 DIAGNOSTICS

Refusals are returned, not thrown. Errors from the storage backend or the
store propagate, and so does L<GPForum::X::Unavailable> from an image tool
that could not be started or outran its time: the outbox tries the event
again.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Service::Attachment::Store>, L<GPForum::Infrastructure::Row>,
L<GPForum::Infrastructure::ImageTool>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

None known.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
