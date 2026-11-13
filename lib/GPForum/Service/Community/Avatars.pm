# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Community::Avatars;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -async_await;
use v5.40;

use GPForum::Infrastructure::Row qw(column_of);
use GPForum::Infrastructure::AsyncWork;
use GPForum::Infrastructure::ImageBytes;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Service::Attachment::Validator;
use GPForum::X::Unavailable;

our $VERSION = '0.001';

# ADR 0144: what a profile picture may be. Smaller than an attachment's
# 25 MiB, and refused by its declared size before any tool decodes it
# (GPForum::Infrastructure::ImageBytes::too_big).
const my $MAXIMUM_BYTES => 5 * 1_024 * 1_024;
const my $SQUARE_TYPE   => 'image/png';
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
has review =>
  undef;   # optional in legacy compositions; production supplies content review
has validator => sub { return GPForum::Service::Attachment::Validator->new; };
has bytes     => sub { return GPForum::Infrastructure::ImageBytes->new; };

# The call layer the pictures are read and written on: their store's.
has functions => sub ($self) { return $self->store->functions; };

# Each operation is written once, as its promise method (ADR 0177); the
# stores, the storage and the review it awaits block with its blocking twin.
GPForum::Infrastructure::SqlFunction->blocking_twins(
    qw(upload process remove_own moderate picture status erase_files));
GPForum::Infrastructure::SqlFunction->blocking_parts(
    qw(store attachments storage review));

sub maximum_bytes ($self) { return $MAXIMUM_BYTES; }

sub maximum_side ($self) { return $self->bytes->maximum_side; }

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
async sub upload_p ( $self, $input, $context = undef ) {
    return { status => 'unavailable' } if !$self->available;

    my $picture = $self->_picture($input);
    return $picture if $picture->{status};

    my $stored =
      await $self->_stored_p( _upload_request( $input, $picture ), $context );
    return { status => 'invalid', errors => $stored->{errors} }
      if !$stored->{ok};

    return await $self->_offered_p( $input->{user_id}, $stored->{attachment},
        $picture->{content}, $context );
}

# The pipeline's rows and bytes, in one transaction. Its scan runs in a
# child, which a blocking caller cannot wait on: there the pipeline's
# blocking upload scans in the process.
async sub _stored_p ( $self, $request, $context ) {
    return $self->pipeline->upload_and_link($request) if $self->_blocking;
    return await $self->pipeline->upload_and_link_p( $request, $context );
}

sub _upload_request ( $input, $picture ) {
    return {
        actor_user_id     => $input->{user_id},
        content           => $picture->{content},
        media_type        => $picture->{media_type},
        original_filename => _filename( $input, $picture->{media_type} ),
        target_id         => $input->{user_id},
        target_type       => 'profile',
        source_kind       => $input->{source_kind},
        source_url        => $input->{source_url},
        rights_confirmed  => $input->{rights_confirmed},
    };
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
    return { status => 'too_many_pixels' } if $self->bytes->too_big($size);

    return { content => $content, media_type => $media_type };
}

# A stored upload the scan did not refuse is offered as the member's
# picture, and cropped now when the scan has already passed it.
async sub _offered_p ( $self, $user_id, $attachment, $content, $context ) {
    return { status => 'refused' } if _scan_refused($attachment);

    my $attachment_id = $attachment->{attachment_id};
    my $offered =
      await $self->store->offer_p( $user_id, $attachment_id, $context );
    return { status => 'failed' } if !_was_offered($offered);
    await $self->_discard_p( $user_id, $offered->{replaced_attachment_id},
        $user_id, $REPLACED, $context );

    return { status => 'checking' } if !_available($attachment);

    my $processed;
    try {
        $processed =
          await $self->process_p( $attachment_id, $content, $context );
    }
    catch ($error) {
        $self->_log("profile picture $attachment_id left waiting: $error");
        return { status => 'checking' };
    };

    return _processed_status($processed);
}

sub _scan_refused ($attachment) {
    return exists $REFUSED_SCAN{ $attachment->{scan_status} // q{} } ? 1 : 0;
}

sub _was_offered ($offered) {
    return exists $OFFERED{ $offered->{status} // q{} } ? 1 : 0;
}

sub _available ($attachment) {
    return ( $attachment->{state} // q{} ) eq 'available' ? 1 : 0;
}

sub _processed_status ($processed) {
    return { status => ( $processed // {} )->{status} // 'checking' };
}

# The media pipeline's step for an upload waiting to be a member's picture
# (Attachment::MediaProcessor, the attachment worker): the image tool crops
# it to its squares, each is stored as a variant, and it is shown. Undef for
# an attachment that is no member's picture, which the pipeline treats as
# any other. Throws GPForum::X::Unavailable when the tool cannot run, so the
# outbox tries again.
#
# The image tool runs before the transaction opens: a crop may take the
# tool's whole timeout, and no row is held locked meanwhile. The squares,
# their variants, the settle and the discards then commit in one
# transaction, and the settle decides whether the picture is still the one
# waiting.
async sub process_p ( $self, $attachment_id, $content = undef,
    $context = undef )
{
    my $attachment =
      await $self->attachments->find_attachment_p( $attachment_id, $context );
    return undef if !$attachment;

    my $user_id = column_of( $attachment, 'owner_user_id' );
    my ( $skipped, $answer ) =
      $self->_skipped( $attachment,
        await $self->store->status_p( $user_id, $context ) );
    return $answer if $skipped;

    my $object_key = column_of( $attachment, 'object_key' );
    $content //= await $self->_object_p( $object_key, $context );
    my $media_type = column_of( $attachment, 'media_type' );
    my $squares    = await $self->_offloaded_p(
        sub { return $self->_squares( $content, $media_type ); } );
    return await $self->_unreadable_p( $user_id, $attachment_id, $context )
      if !$squares;

    return await $self->_functions->transaction_p(
        async sub ($scope) {
            return await $self->_show_p( $user_id, $attachment_id,
                $object_key, $squares, $context, $scope );
        },
        $context
    );
}

async sub _show_p ( $self, $user_id, $attachment_id, $object_key, $squares,
    $context, $scope )
{
    for my $side ( @{ $self->store->sides } ) {
        await $self->_store_square_p( $attachment_id, $object_key, $side,
            $squares->{$side}, $context, $scope );
    }
    my $settled =
      await $self->store->settle_p( $user_id, $attachment_id, 'ready',
        $context, $scope );
    if ( ( $settled->{status} // 'stale' ) eq 'stale' ) {
        await $self->_discard_p( $user_id, $attachment_id, $user_id,
            $REPLACED, $context, $scope );
        return { ok => 1, status => 'stale' };
    }
    await $self->_discard_p( $user_id, $settled->{replaced_attachment_id},
        $user_id, $REPLACED, $context, $scope );

    return { ok => 1, status => 'shown' };
}

# Whether the picture is past processing, and what process answers then:
# shown already, no longer the one waiting (undef), unreadable, or still
# checking (its scan, or a missing tool).
sub _skipped ( $self, $attachment, $status ) {
    my $attachment_id = column_of( $attachment, 'attachment_id' );
    return ( 1, { ok => 1, status => 'shown', skipped => 1 } )
      if _same( $status->{attachment_id}, $attachment_id );
    return ( 1, undef )
      if !_same( $status->{pending_attachment_id}, $attachment_id );
    return ( 1, { ok => 1, status => 'unreadable', skipped => 1 } )
      if ( $status->{pending_state} // q{} ) eq 'unreadable';
    return ( 1, { ok => 1, status => 'checking', skipped => 1 } )
      if ( column_of( $attachment, 'state' ) // q{} ) ne 'available'
      || !$self->image_tool;
    return ( 0, undef );
}

# The picture's squares by side, or undef for one the tool cannot read or
# that is too big. Pure work on the bytes, which may run in a child.
sub _squares ( $self, $content, $media_type ) {
    my $size = $self->bytes->dimensions( $content, $media_type );
    return undef if !$size || $self->bytes->too_big($size);
    return $self->image_tool->squares(
        { %{$size}, content => $content, media_type => $media_type },
        $self->store->sides );
}

# The member takes their picture away. Answers ok or not_found.
async sub remove_own_p ( $self, $user_id, $context = undef ) {
    my $removed = await $self->store->remove_own_p( $user_id, $context );
    for my $attachment_id ( @{ $removed->{attachment_ids} } ) {
        await $self->_discard_p( $user_id, $attachment_id, $user_id, $REMOVED,
            $context );
    }

    return { status => $removed->{status} };
}

# Staff take a member's picture away (audited). Answers ok, not_found or
# invalid.
async sub moderate_p ( $self, $input, $context = undef ) {
    my $removed = await $self->store->remove_by_staff_p( $input, $context );
    for my $attachment_id ( @{ $removed->{attachment_ids} } ) {
        await $self->_discard_p(
            $input->{subject_user_id},
            $attachment_id, $input->{actor_user_id},
            $MODERATED,     $context
        );
    }

    return { status => $removed->{status}, field => $removed->{field} };
}

# The square a picture's address names: { content, media_type,
# attachment_id, current }, current false when the address names an older
# picture the member has since replaced (a page cached before the change),
# which is answered with the one shown now. Undef when the member shows
# none, or when its bytes cannot be read.
async sub picture_p ( $self, $input, $request_context = undef ) {
    my $context = $input->{query_context} // $request_context;
    my $row =
      await $self->store->image_p( @{$input}{qw(user_id side)}, $context )
      or return undef;
    my $content = await $self->_square_bytes_p( $row, $context );
    return undef if !defined $content;

    return {
        attachment_id => $row->{attachment_id},
        content       => $content,
        current       => _same( $row->{attachment_id}, $input->{avatar_id} ),
        media_type    => $row->{media_type} // $SQUARE_TYPE,
    };
}

# A square's bytes. On the event loop PostgreSQL storage reads its chunks
# on the pooled connections; otherwise the object is read in a child, or in
# the process for a blocking caller, and one that cannot be read is logged
# and answers undef.
async sub _square_bytes_p ( $self, $row, $context ) {
    my $storage = $self->storage;
    return await $storage->read_object_p( $row->{object_key}, $MAXIMUM_BYTES,
        $context )
      if !$self->_blocking && $storage->can('read_object_p');
    my $read = await $self->_offloaded_p(
        sub {
            my %read;
            try {
                $read{content} = $storage->read_object( $row->{object_key} );
            }
            catch ($error) { $read{error} = "$error"; };
            return \%read;
        }
    );
    if ( defined $read->{error} ) {
        $self->_log(
            "profile picture $row->{attachment_id} unreadable: $read->{error}");
    }

    return $read->{content};
}

# The settings page's view of a member's picture: the attachment shown, if
# any, and the state of the one waiting, its content review read for one
# waiting.
async sub status_p ( $self, $user_id, $context = undef ) {
    my $status = await $self->store->status_p( $user_id, $context );
    my $held =
      $self->_reviewed($status)
      ? await $self->review->find_p( $status->{pending_attachment_id},
        $context )
      : undef;

    return $self->_status( $status, $held );
}

# Whether content review is asked about the picture waiting.
sub _reviewed ( $self, $status ) {
    return $self->review && $status->{pending_attachment_id} ? 1 : 0;
}

sub _status ( $self, $status, $held ) {
    if (   $held
        && $held->{status} eq 'pending'
        && $held->{scan_status} ne 'infected'
        && $held->{scan_status} ne 'failed' )
    {
        $status->{pending_state} = 'checking';
    }

    return {
        available     => $self->available,
        shown_id      => $status->{attachment_id},
        shown_at      => $status->{shown_at},
        pending_state => $status->{pending_state},
        pending_at    => $status->{pending_at},
    };
}

# Erasure, before the rows go (privacy_revoke_user's Avatar): every stored
# object of every upload the member linked to their profile is deleted, on
# the transaction $functions belongs to when one is given. Answers how many
# objects were deleted.
async sub erase_files_p ( $self, $user_id, $context = undef,
    $functions = undef )
{
    my $objects =
      await $self->store->objects_p( $user_id, undef, $context, $functions );
    for my $object ( @{$objects} ) {
        await $self->_delete_object_p( $object->{object_key}, $context,
            $functions );
    }

    return scalar @{$objects};
}

async sub _unreadable_p ( $self, $user_id, $attachment_id, $context ) {
    return await $self->_functions->transaction_p(
        async sub ($scope) {
            my $settled =
              await $self->store->settle_p( $user_id, $attachment_id,
                'unreadable', $context, $scope );
            await $self->_discard_p( $user_id, $attachment_id, $user_id,
                $UNREAD, $context, $scope );
            return {
                ok     => 1,
                status => ( $settled->{status} // q{} ) eq 'ok'
                ? 'unreadable'
                : 'stale'
            };
        },
        $context
    );
}

# A square written once under its key, in the transaction $scope belongs
# to; files on disk are written in place.
async sub _store_square_p ( $self, $attachment_id, $object_key, $side, $png,
    $context, $scope )
{
    my $key     = join q{-}, $object_key, 'avatar', $side;
    my $storage = $self->storage;
    if ( $storage->can('write_object_p') ) {
        if ( !await $storage->exists_object_p( $key, $context, $scope ) ) {
            await $storage->write_object_p( $key, $png, $context, $scope );
        }
    }
    elsif ( !$storage->exists_object($key) ) {
        $storage->write_object( $key, $png );
    }
    await $self->attachments->add_variant_p(
        {
            attachment_id => $attachment_id,
            byte_size     => length $png,
            media_type    => $SQUARE_TYPE,
            object_key    => $key,
            variant_type  => $self->store->variant_type($side),
        },
        $context, $scope
    );

    return;
}

# An upload no longer anybody's picture: its files go first, then its row
# is marked deleted with the attachment's own event and audit, in the
# transaction $scope belongs to when one is given. Removing a file that is
# not there is not an error, so a repeat does no harm.
async sub _discard_p ( $self, $user_id, $attachment_id, $actor_id, $reason,
    $context, $scope = undef )
{
    return if !defined $attachment_id;

    my $objects =
      await $self->store->objects_p( $user_id, $attachment_id, $context,
        $scope );
    for my $object ( @{$objects} ) {
        await $self->_delete_object_p( $object->{object_key}, $context,
            $scope );
    }
    await $self->attachments->soft_delete_p( $attachment_id, $actor_id,
        $reason, $context, $scope );

    return;
}

# An object deleted on the call layer $scope names; files on disk are
# unlinked in place.
async sub _delete_object_p ( $self, $key, $context, $scope ) {
    my $storage = $self->storage;
    return $storage->delete_object($key)
      if !$storage->can('delete_object_p');
    return await $storage->delete_object_p( $key, $context, $scope );
}

# An object's bytes, read on the pooled connections where the storage can,
# else in place; a blocking caller reads them in place too.
async sub _object_p ( $self, $key, $context ) {
    my $storage = $self->storage;
    return $storage->read_object($key)
      if $self->_blocking || !$storage->can('read_object_p');
    return await $storage->read_object_p( $key, $MAXIMUM_BYTES, $context );
}

# Work on bytes alone, in a child that cannot reach the database (cpu_p).
# A blocking caller waits on no event loop: there it runs in the process.
async sub _offloaded_p ( $self, $work ) {
    return $work->() if $self->_blocking;
    return await GPForum::Infrastructure::AsyncWork->shared->cpu_p($work);
}

sub _blocking ($self) {
    return $self->_functions->blocking ? 1 : 0;
}

sub _functions ($self) {
    return $self->functions // GPForum::X::Unavailable->throw(
        message => 'profile pictures need the PostgreSQL function layer' );
}

sub _slurped ($upload) {
    return $upload->can('asset') ? $upload->asset->slurp : undef;
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
pipeline once the scan is clean (L</process_p>, called by
L<GPForum::Service::Attachment::MediaProcessor>). The picture shown until
then stays; one the scan refuses or the tool cannot read is never shown.

A picture replaced or removed is discarded: its files are deleted, then
its attachment row is marked deleted. Erasure deletes the files of every
upload the member linked to their profile (L</erase_files_p>) before
C<privacy_revoke_user> removes the rows.

=head1 SUBROUTINES/METHODS

=head2 new

Constructor (L<GPForum::Base>). C<store>
(L<GPForum::Service::Community::AvatarStore>), C<attachments>
(L<GPForum::Service::Attachment::Store>), C<pipeline> and C<storage> are
required; C<image_tool>, C<logger> and C<review> are optional. Each
operation is written once, as its promise method, on the store's call
layer (ADR 0177); the blocking methods are that body settled on the
blocking layer, with the store, the attachments, the storage and the
review as its parts.

=head2 maximum_bytes

5 MB.

=head2 maximum_side

8,000 pixels.

=head2 available

True when an image tool is configured and installed.

=head2 upload_p

Takes C<user_id> and an C<upload> (a L<Mojo::Upload>) or C<content> with an
optional C<original_filename>, then an optional query context. Answers
C<< { status => ... } >>: C<unavailable>, C<missing>, C<too_large>,
C<not_image>, C<unreadable>, C<too_many_pixels>, C<invalid> (with the
validator's C<errors>), C<failed>, C<refused>, C<checking> or C<shown>. The
pipeline's rows and bytes commit in one transaction, then the offer and
the crop follow. On the event loop the antivirus scan and the image tool
run in a child that cannot reach the database.

C<upload> is its blocking twin, with the input: the pipeline's blocking
upload scans in the process, and the image tool runs in the process too.

=head2 process_p

Takes an attachment id and, optionally, its bytes, then an optional query
context. Undef when the attachment is not a member's waiting or shown
picture; otherwise C<< { ok => 1, status => ... } >>: C<shown>,
C<unreadable>, C<checking> (not yet clean, or no tool configured) or
C<stale> (replaced meanwhile). The image tool crops the bytes before the
transaction opens -- in a child on the event loop, in the process for a
blocking caller -- and the squares, their variants, the settle and the
discards commit in one transaction.

C<process> is its blocking twin, with the id and the bytes: the media
pipeline's step (L<GPForum::Service::Attachment::MediaProcessor>).

=head2 remove_own_p

Takes a member id, then an optional query context. Answers
C<< { status => 'ok' } >> or C<not_found>.

C<remove_own> is its blocking twin, with the member id.

=head2 moderate_p

Takes C<actor_user_id>, C<subject_user_id>, C<attachment_id> and an
optional C<reason>, then an optional query context. Answers
C<< { status => 'ok' } >>, C<not_found> or C<invalid> with C<field>.

C<moderate> is its blocking twin, with the input.

=head2 picture_p

Takes C<user_id>, C<avatar_id> (the attachment id the address names),
C<side> and an optional C<query_context>, then an optional request
context. Answers C<< { content, media_type, attachment_id, current } >>, or
undef. On the event loop PostgreSQL storage is read on the pooled
connections and files on disk in a child; a square that cannot be read
from disk is logged and answers undef.

C<picture> is its blocking twin, with the input.

=head2 status_p

Takes a member id, then an optional query context. Answers C<available>,
C<shown_id>, C<shown_at>, C<pending_state> and C<pending_at>: the
picture's row and, for one waiting, its content review.

C<status> is its blocking twin, with the member id.

=head2 erase_files_p

Takes a member id, then an optional query context and an optional
transaction call layer. Deletes the stored objects of every upload linked
to their profile and answers how many; a storage without asynchronous
deletes unlinks its files in place.

C<erase_files> is its blocking twin, with the member id.

=head1 DIAGNOSTICS

Refusals are returned. L</process_p> throws L<GPForum::X::Unavailable> when
the image tool cannot run, and every operation that reaches the database
throws it without the PostgreSQL function layer; errors of the storage and
the stores propagate, except in L</upload_p>, where a failing tool leaves
the picture waiting.

=head1 CONFIGURATION AND ENVIRONMENT

C<GPFORUM_IMAGE_TOOL> through the bootstrap's image tool.

=head1 DEPENDENCIES

L<GPForum::Service::Community::AvatarStore>,
L<GPForum::Service::Attachment::Store>,
L<GPForum::Service::Attachment::UploadPipeline>,
L<GPForum::Infrastructure::SqlFunction>,
L<GPForum::Infrastructure::AsyncWork>,
L<GPForum::Infrastructure::ImageBytes>,
L<GPForum::Infrastructure::ImageTool>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

A page cached before a picture changed may name the old picture's address
for the cache's lifetime; the address answers with the picture shown now.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
