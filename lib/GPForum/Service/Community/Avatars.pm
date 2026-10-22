# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Community::Avatars;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -signatures;
use v5.40;

use GPForum::Infrastructure::Id;
use GPForum::Infrastructure::Row;
use GPForum::Infrastructure::ImageBytes;
use GPForum::Service::Attachment::Validator;

our $VERSION = '0.001';

# ADR 0144: what a profile picture may be. Smaller than an attachment's
# 25 MB, and refused by its declared size before any tool decodes it.
const my $MAXIMUM_BYTES  => 5 * 1_024 * 1_024;
const my $MAXIMUM_SIDE   => 8_000;
const my $MAXIMUM_PIXELS => 40_000_000;
const my $SQUARE_TYPE    => 'image/png';
const my %IMAGE_TYPE => map { $_ => 1 } qw(
  image/gif image/jpeg image/png image/webp
);
const my %REFUSED_SCAN => map { $_ => 1 } qw(infected failed);
const my %OFFERED      => map { $_ => 1 } qw(ok replayed);
const my $REPLACED     => 'avatar replaced';
const my $REMOVED      => 'avatar removed';
const my $MODERATED    => 'avatar removed by staff';
const my $UNREAD       => 'avatar unreadable';

# The pictures' rows (Community::AvatarStore), the attachments they are
# (Attachment::Store), the upload pipeline that validates, stores and scans
# one, and the storage that holds the bytes.
__PACKAGE__->requires(qw(store attachments pipeline storage));

# The system's image tool (Infrastructure::ImageTool), or undef when the
# operator turned pictures off.
has image_tool => undef;    # optional: without one, no picture is taken
has logger     => undef;    # optional: a tool that fails is logged
has validator  => sub { return GPForum::Service::Attachment::Validator->new; };
has bytes      => sub { return GPForum::Infrastructure::ImageBytes->new; };

sub maximum_bytes ($self) { return $MAXIMUM_BYTES; }

sub maximum_side ($self) { return $MAXIMUM_SIDE; }

# Whether members can upload a picture now: a tool is configured and
# installed.
sub available ($self) {
    return $self->image_tool && $self->image_tool->available ? 1 : 0;
}

# A member's upload, start to finish. Refused before anything is stored:
# unavailable (no image tool), missing, too_large (bytes), not_image,
# unreadable (no size in its header), too_many_pixels, invalid (the
# attachment validator's). Once stored and scanned: refused (the scan
# found it infected or failed it), checking (the scan, or the tool, will
# answer later), shown, or unreadable (the tool could not read it).
sub upload ( $self, $input ) {
    return { status => 'unavailable' } if !$self->available;

    my $picture = $self->_picture($input);
    return $picture if $picture->{status};

    my $user_id = $input->{user_id};
    my $stored  = $self->pipeline->upload_and_link(
        {
            actor_user_id     => $user_id,
            content           => $picture->{content},
            media_type        => $picture->{media_type},
            original_filename => _filename( $input, $picture->{media_type} ),
            target_id         => $user_id,
            target_type       => 'profile',
        }
    );
    return { status => 'invalid', errors => $stored->{errors} }
      if !$stored->{ok};

    return $self->_offered( $user_id, $stored->{attachment},
        $picture->{content} );
}

# The bytes and their type, or the refusal that stops them before anything
# is stored.
sub _picture ( $self, $input ) {
    my $upload  = $input->{upload};
    my $content = $input->{content};
    if ( !defined $content && $upload ) {
        return { status => 'too_large' }
          if $upload->can('size') && $upload->size > $MAXIMUM_BYTES;
        $content = _slurped($upload);
    }
    return { status => 'missing' }   if !defined $content || !length $content;
    return { status => 'too_large' } if length $content > $MAXIMUM_BYTES;

    my $media_type = $self->validator->sniff_media_type($content);
    return { status => 'not_image' }
      if !exists $IMAGE_TYPE{ $media_type // q{} };
    my $size = $self->bytes->dimensions( $content, $media_type );
    return { status => 'unreadable' }      if !$size;
    return { status => 'too_many_pixels' } if _too_big($size);

    return { content => $content, media_type => $media_type };
}

# A stored upload the scan did not refuse is offered as the member's
# picture, and cropped now when the scan has already passed it.
sub _offered ( $self, $user_id, $attachment, $content ) {
    return { status => 'refused' }
      if exists $REFUSED_SCAN{ $attachment->{scan_status} // q{} };

    my $attachment_id = $attachment->{attachment_id};
    my $offered       = $self->store->offer( $user_id, $attachment_id );
    return { status => 'failed' }
      if !exists $OFFERED{ $offered->{status} // q{} };
    $self->_discard( $user_id, $offered->{replaced_attachment_id},
        $user_id, $REPLACED );

    return { status => 'checking' }
      if ( $attachment->{state} // q{} ) ne 'available';

    my $processed;
    try {
        $processed = $self->process( $attachment_id, $content );
    }
    catch ($error) {
        $self->_log("profile picture $attachment_id left waiting: $error");
        return { status => 'checking' };
    };

    return { status => ( $processed // {} )->{status} // 'checking' };
}

# The media pipeline's step for an upload waiting to be a member's picture
# (Attachment::MediaProcessor, the attachment worker): the image tool crops
# it to its squares, each is stored as a variant, and it is shown. Undef for
# an attachment that is no member's picture, which the pipeline treats as
# any other. Throws GPForum::X::Unavailable when the tool cannot run, so the
# outbox tries again.
sub process ( $self, $attachment_id, $content = undef ) {
    my $attachment = $self->attachments->find_attachment($attachment_id);
    return undef if !$attachment;

    my $user_id = _column( $attachment, 'owner_user_id' );
    my $status  = $self->store->status($user_id);
    return { ok => 1, status => 'shown', skipped => 1 }
      if _same( $status->{attachment_id}, $attachment_id );
    return undef
      if !_same( $status->{pending_attachment_id}, $attachment_id );
    return { ok => 1, status => 'unreadable', skipped => 1 }
      if ( $status->{pending_state} // q{} ) eq 'unreadable';
    return { ok => 1, status => 'checking', skipped => 1 }
      if ( _column( $attachment, 'state' ) // q{} ) ne 'available'
      || !$self->image_tool;

    my $object_key = _column( $attachment, 'object_key' );
    $content //= $self->storage->read_object($object_key);
    my $media_type = _column( $attachment, 'media_type' );
    my $size       = $self->bytes->dimensions( $content, $media_type );
    my $squares =
      $size && !_too_big($size)
      ? $self->image_tool->squares(
        { %{$size}, content => $content, media_type => $media_type },
        $self->store->sides )
      : undef;
    return $self->_unreadable( $user_id, $attachment_id ) if !$squares;

    for my $side ( @{ $self->store->sides } ) {
        $self->_store_square( $attachment_id, $object_key, $side,
            $squares->{$side} );
    }

    my $settled = $self->store->settle( $user_id, $attachment_id, 'ready' );
    my $outcome = $settled->{status} // 'stale';
    if ( $outcome eq 'stale' ) {
        $self->_discard( $user_id, $attachment_id, $user_id, $REPLACED );
        return { ok => 1, status => 'stale' };
    }
    $self->_discard( $user_id, $settled->{replaced_attachment_id},
        $user_id, $REPLACED );

    return { ok => 1, status => 'shown' };
}

# The member takes their picture away. Answers ok or not_found.
sub remove_own ( $self, $user_id ) {
    my $removed = $self->store->remove_own($user_id);
    for my $attachment_id ( @{ $removed->{attachment_ids} } ) {
        $self->_discard( $user_id, $attachment_id, $user_id, $REMOVED );
    }

    return { status => $removed->{status} };
}

# Staff take a member's picture away (audited). Answers ok, not_found or
# invalid.
sub moderate ( $self, $input ) {
    my $removed = $self->store->remove_by_staff($input);
    for my $attachment_id ( @{ $removed->{attachment_ids} } ) {
        $self->_discard(
            $input->{subject_user_id}, $attachment_id,
            $input->{actor_user_id},   $MODERATED
        );
    }

    return { status => $removed->{status}, field => $removed->{field} };
}

# The square a picture's address names: { content, media_type,
# attachment_id, current }, current false when the address names an older
# picture the member has since replaced (a page cached before the change),
# which is answered with the one shown now. Undef when the member shows
# none.
sub picture ( $self, $user_id, $avatar_id, $side ) {
    my $row = $self->store->image( $user_id, $side ) // return undef;
    my $content;
    try {
        $content = $self->storage->read_object( $row->{object_key} );
    }
    catch ($error) {
        $self->_log("profile picture $row->{attachment_id} unreadable: $error");
        return undef;
    };
    return undef if !defined $content;

    return {
        attachment_id => $row->{attachment_id},
        content       => $content,
        current       => _same( $row->{attachment_id}, $avatar_id ),
        media_type    => $row->{media_type} // $SQUARE_TYPE,
    };
}

# The settings page's view of a member's picture: the attachment shown, if
# any, and the state of the one waiting.
sub status ( $self, $user_id ) {
    my $status = $self->store->status($user_id);

    return {
        available     => $self->available,
        shown_id      => $status->{attachment_id},
        shown_at      => $status->{shown_at},
        pending_state => $status->{pending_state},
        pending_at    => $status->{pending_at},
    };
}

# The attachment a member shows as their picture, or undef.
sub shown_id ( $self, $user_id ) {
    return $self->store->status($user_id)->{attachment_id};
}

# Erasure, before the rows go (privacy_revoke_user's Avatar): every stored
# object of every upload the member linked to their profile is deleted.
# Returns how many objects were deleted.
sub erase_files ( $self, $user_id ) {
    my $objects = $self->store->objects($user_id);
    for my $object ( @{$objects} ) {
        $self->storage->delete_object( $object->{object_key} );
    }

    return scalar @{$objects};
}

sub _unreadable ( $self, $user_id, $attachment_id ) {
    my $settled =
      $self->store->settle( $user_id, $attachment_id, 'unreadable' );
    $self->_discard( $user_id, $attachment_id, $user_id, $UNREAD );

    return {
        ok     => 1,
        status => ( $settled->{status} // q{} ) eq 'ok'
        ? 'unreadable'
        : 'stale'
    };
}

sub _store_square ( $self, $attachment_id, $object_key, $side, $png ) {
    my $key = join q{-}, $object_key, 'avatar', $side;
    if ( !$self->storage->exists_object($key) ) {
        $self->storage->write_object( $key, $png );
    }
    $self->attachments->add_variant(
        {
            attachment_id => $attachment_id,
            byte_size     => length $png,
            media_type    => $SQUARE_TYPE,
            object_key    => $key,
            variant_type  => $self->store->variant_type($side),
        }
    );

    return;
}

# An upload no longer anybody's picture: its files go first, then its row
# is marked deleted with the attachment's own event and audit. Removing a
# file that is not there is not an error, so a repeat does no harm.
sub _discard ( $self, $user_id, $attachment_id, $actor_id, $reason ) {
    return if !defined $attachment_id;

    for my $object ( @{ $self->store->objects( $user_id, $attachment_id ) } ) {
        $self->storage->delete_object( $object->{object_key} );
    }
    $self->attachments->soft_delete( $attachment_id, $actor_id, $reason );

    return;
}

sub _slurped ($upload) {
    return $upload->can('asset') ? $upload->asset->slurp : undef;
}

sub _too_big ($size) {
    return
         $size->{width} > $MAXIMUM_SIDE
      || $size->{height} > $MAXIMUM_SIDE
      || $size->{width} * $size->{height} > $MAXIMUM_PIXELS ? 1 : 0;
}

sub _filename ( $input, $media_type ) {
    my $upload = $input->{upload};
    my $name   = $input->{original_filename};
    if (   ( !defined $name || !length $name )
        && $upload
        && $upload->can('filename') )
    {
        $name = $upload->filename;
    }
    return $name if defined $name && length $name;

    return 'avatar.' . ( $media_type =~ s{\A image/}{}rmsx );
}

sub _same ( $left, $right ) {
    return defined $left && defined $right && lc $left eq lc $right ? 1 : 0;
}

sub _column ( $row, $name ) {
    return GPForum::Infrastructure::Row->column( $row, $name );
}

sub _log ( $self, $message ) {
    if ( $self->logger ) {
        $self->logger->warn($message);
    }

    return;
}

1;

__END__

=head1 NAME

GPForum::Service::Community::Avatars - A member's profile picture: upload, crop, show, remove, erase.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $avatars = GPForum::Service::Community::Avatars->new(
        attachments => $attachment_store,
        image_tool  => $image_tool,
        pipeline    => $upload_pipeline,
        storage     => $attachment_storage,
        store       => $avatar_store,
    );
    my $answer = $avatars->upload(
        { user_id => $user_id, upload => $c->req->upload('avatar') } );
    # { status => 'shown' }, { status => 'checking' }, { status => 'not_image' }, ...

=head1 DESCRIPTION

ADR 0144. A picture is an attachment the member owns, linked to their
profile: it goes through the attachment validator, the storage and the
malware scan of L<GPForum::Service::Attachment::UploadPipeline> as every
upload does, after a check of its own that it is a PNG, GIF, JPEG or WebP
of at most 5 MB and 8,000 pixels a side (40 megapixels in all), read from
its header.

A clean picture is cropped about its centre to a square and kept at 64, 128
and 256 pixels as PNG variants (C<avatar_64>, C<avatar_128>,
C<avatar_256>), each stripped of everything but the picture, by the
system's image tool (L<GPForum::Infrastructure::ImageTool>). That happens in
the request when the scan answers at once, and otherwise in the media
pipeline once the scan is clean (L</process>, called by
L<GPForum::Service::Attachment::MediaProcessor>). The picture shown until
then stays; one the scan refuses or the tool cannot read is never shown.

A picture replaced or removed is discarded: its files are deleted, then
its attachment row is marked deleted. Erasure deletes the files of every
upload the member linked to their profile (L</erase_files>) before
C<privacy_revoke_user> removes the rows.

=head1 SUBROUTINES/METHODS

=head2 new

Constructor (L<GPForum::Base>). C<store>
(L<GPForum::Service::Community::AvatarStore>), C<attachments>
(L<GPForum::Service::Attachment::Store>), C<pipeline> and C<storage> are
required; C<image_tool> and C<logger> are optional.

=head2 maximum_bytes

5 MB.

=head2 maximum_side

8,000 pixels.

=head2 available

True when an image tool is configured and installed.

=head2 upload

Takes C<user_id> and an C<upload> (a L<Mojo::Upload>) or C<content> with an
optional C<original_filename>. Returns C<< { status => ... } >>:
C<unavailable>, C<missing>, C<too_large>, C<not_image>, C<unreadable>,
C<too_many_pixels>, C<invalid> (with the validator's C<errors>), C<failed>,
C<refused>, C<checking> or C<shown>.

=head2 process

Takes an attachment id and, optionally, its bytes. Undef when the
attachment is not a member's waiting or shown picture; otherwise
C<< { ok => 1, status => ... } >>: C<shown>, C<unreadable>, C<checking>
(not yet clean, or no tool configured) or C<stale> (replaced meanwhile).

=head2 remove_own

Takes a member id. Returns C<< { status => 'ok' } >> or C<not_found>.

=head2 moderate

Takes C<actor_user_id>, C<subject_user_id>, C<attachment_id> and an
optional C<reason>. Returns C<< { status => 'ok' } >>, C<not_found> or
C<invalid> with C<field>.

=head2 picture

Takes a member id, the attachment id an address names and a side. Returns
C<< { content, media_type, attachment_id, current } >>, or undef.

=head2 status

Takes a member id. Returns C<available>, C<shown_id>, C<shown_at>,
C<pending_state> and C<pending_at>.

=head2 shown_id

Takes a member id. Returns the attachment id of the picture shown, or
undef.

=head2 erase_files

Takes a member id. Deletes the stored objects of every upload linked to
their profile and returns how many.

=head1 DIAGNOSTICS

Refusals are returned. L</process> throws L<GPForum::X::Unavailable> when
the image tool cannot run; errors of the storage and the stores propagate,
except in L</upload>, where a failing tool leaves the picture waiting.

=head1 CONFIGURATION AND ENVIRONMENT

C<GPFORUM_IMAGE_TOOL> through the bootstrap's image tool.

=head1 DEPENDENCIES

L<GPForum::Service::Community::AvatarStore>,
L<GPForum::Service::Attachment::Store>,
L<GPForum::Service::Attachment::UploadPipeline>,
L<GPForum::Infrastructure::ImageBytes>,
L<GPForum::Infrastructure::ImageTool>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

A page cached before a picture changed may name the old picture's address
for the cache's lifetime; the address answers with the picture shown now.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause
license.

=cut
