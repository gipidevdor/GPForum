# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Community::Avatars;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -async_await;
use v5.40;

use GPForum::Infrastructure::Row qw(column_of);
use GPForum::Infrastructure::ImageBytes;
use GPForum::Service::Attachment::Validator;

use Mojo::Promise;
use GPForum::Infrastructure::AsyncWork;

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
sub upload ( $self, $input ) {
    return { status => 'unavailable' } if !$self->available;

    my $picture = $self->_picture($input);
    return $picture if $picture->{status};

    my $user_id = $input->{user_id};
    my $stored =
      $self->pipeline->upload_and_link( _upload_request( $input, $picture ) );
    return { status => 'invalid', errors => $stored->{errors} }
      if !$stored->{ok};

    return $self->_offered( $user_id, $stored->{attachment},
        $picture->{content} );
}

# The same upload on the worker's pooled asynchronous connections: the
# pipeline's rows and bytes in one transaction, the offer, and the crop,
# whose image tool runs in a child that cannot reach the database.
async sub upload_p ( $self, $input, $context = undef ) {
    return { status => 'unavailable' } if !$self->available;
    return $self->upload($input)       if !$self->_native;

    my $picture = $self->_picture($input);
    return $picture if $picture->{status};

    my $stored =
      await $self->pipeline->upload_and_link_p(
        _upload_request( $input, $picture ), $context );
    return { status => 'invalid', errors => $stored->{errors} }
      if !$stored->{ok};

    return await $self->_offered_p( $input->{user_id}, $stored->{attachment},
        $picture->{content}, $context );
}

# Whether the collaborators answer on the pooled asynchronous connections:
# the in-memory doubles do not, and answer in place.
sub _native ($self) {
    return
         $self->store->can('offer_p')
      && $self->store->functions
      && $self->attachments->can('soft_delete_p')
      && $self->attachments->functions
      && $self->pipeline->can('upload_and_link_p') ? 1 : 0;
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
sub _offered ( $self, $user_id, $attachment, $content ) {
    return { status => 'refused' } if _scan_refused($attachment);

    my $attachment_id = $attachment->{attachment_id};
    my $offered       = $self->store->offer( $user_id, $attachment_id );
    return { status => 'failed' } if !_was_offered($offered);
    $self->_discard( $user_id, $offered->{replaced_attachment_id},
        $user_id, $REPLACED );

    return { status => 'checking' } if !_available($attachment);

    my $processed;
    try {
        $processed = $self->process( $attachment_id, $content );
    }
    catch ($error) {
        $self->_log("profile picture $attachment_id left waiting: $error");
        return { status => 'checking' };
    };

    return _processed_status($processed);
}

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
sub process ( $self, $attachment_id, $content = undef ) {
    my $attachment = $self->attachments->find_attachment($attachment_id);
    return undef if !$attachment;

    my $user_id = column_of( $attachment, 'owner_user_id' );
    my ( $skipped, $answer ) =
      $self->_skipped( $attachment, $self->store->status($user_id) );
    return $answer if $skipped;

    # The image tool runs before the transaction opens, as process_p runs
    # it: a crop may take the tool's whole timeout, and no row is held
    # locked meanwhile. The settle decides whether the picture is still the
    # one waiting.
    my $object_key = column_of( $attachment, 'object_key' );
    $content //= $self->storage->read_object($object_key);
    my $squares =
      $self->_squares( $content, column_of( $attachment, 'media_type' ) );
    return $self->_in_transaction(
        sub {
            return $self->_unreadable( $user_id, $attachment_id )
              if !$squares;
            return $self->_show( $user_id, $attachment_id, $object_key,
                $squares );
        }
    );
}

sub _in_transaction ( $self, $work ) {
    return $self->attachments->schema->txn_do($work)
      if $self->attachments->can('schema');
    return $work->();
}

sub _show ( $self, $user_id, $attachment_id, $object_key, $squares ) {
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

# process on the worker's pooled asynchronous connections: the rows are
# read, the image tool crops the bytes in a child that cannot reach the
# database, and the squares, their variants, the settle and the discards
# commit in one transaction. The settle decides whether the picture is
# still the one waiting.
async sub process_p ( $self, $attachment_id, $content = undef,
    $context = undef )
{
    return $self->process( $attachment_id, $content ) if !$self->_native;
    my $attachment =
      await $self->attachments->find_attachment_p( $attachment_id, $context );
    return undef if !$attachment;

    my $user_id = column_of( $attachment, 'owner_user_id' );
    my ( $skipped, $answer ) =
      $self->_skipped( $attachment,
        await $self->store->status_p( $user_id, $context ) );
    return $answer if $skipped;

    my $object_key = column_of( $attachment, 'object_key' );
    $content //=
      $self->storage->can('read_object_p')
      ? await $self->storage->read_object_p( $object_key, $MAXIMUM_BYTES,
        $context )
      : $self->storage->read_object($object_key);
    my $media_type = column_of( $attachment, 'media_type' );
    my $squares    = await GPForum::Infrastructure::AsyncWork->shared->cpu_p(
        sub { return $self->_squares( $content, $media_type ); } );
    return await $self->_unreadable_p( $user_id, $attachment_id, $context )
      if !$squares;

    return await $self->store->functions->transaction_p(
        async sub ($scope) {
            for my $side ( @{ $self->store->sides } ) {
                await $self->_store_square_p( $attachment_id, $object_key,
                    $side, $squares->{$side}, $context, $scope );
            }
            my $settled =
              await $self->store->settle_p( $user_id, $attachment_id, 'ready',
                $context, $scope );
            my $outcome = $settled->{status} // 'stale';
            if ( $outcome eq 'stale' ) {
                await $self->_discard_p( $user_id, $attachment_id, $user_id,
                    $REPLACED, $context, $scope );
                return { ok => 1, status => 'stale' };
            }
            await $self->_discard_p( $user_id,
                $settled->{replaced_attachment_id},
                $user_id, $REPLACED, $context, $scope );

            return { ok => 1, status => 'shown' };
        },
        $context
    );
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
# that is too big. Pure work on the bytes: process_p runs it in a child.
sub _squares ( $self, $content, $media_type ) {
    my $size = $self->bytes->dimensions( $content, $media_type );
    return undef if !$size || $self->bytes->too_big($size);
    return $self->image_tool->squares(
        { %{$size}, content => $content, media_type => $media_type },
        $self->store->sides );
}

# The member takes their picture away. Answers ok or not_found.
sub remove_own ( $self, $user_id ) {
    my $removed = $self->store->remove_own($user_id);
    for my $attachment_id ( @{ $removed->{attachment_ids} } ) {
        $self->_discard( $user_id, $attachment_id, $user_id, $REMOVED );
    }

    return { status => $removed->{status} };
}

# remove_own on the worker's pooled asynchronous connections.
async sub remove_own_p ( $self, $user_id, $context = undef ) {
    return $self->remove_own($user_id) if !$self->_native;
    my $removed = await $self->store->remove_own_p( $user_id, $context );
    for my $attachment_id ( @{ $removed->{attachment_ids} } ) {
        await $self->_discard_p( $user_id, $attachment_id, $user_id, $REMOVED,
            $context );
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

# moderate on the worker's pooled asynchronous connections.
async sub moderate_p ( $self, $input, $context = undef ) {
    return $self->moderate($input) if !$self->_native;
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
# none.
sub picture_p ( $self, $input, $request_context = undef ) {
    $input = {
        %{$input}, query_context => $input->{query_context} // $request_context
    };
    my ( $user_id, $avatar_id, $side, $context ) =
      @{$input}{qw(user_id avatar_id side query_context)};
    return Mojo::Promise->resolve->then(
        sub {
            return $self->picture_from_input($input)
              if !$self->store->can('image_p') || !$self->store->functions;
            return $self->store->image_p( $user_id, $side, $context )->then(
                sub ($row) {
                    return undef if !$row;
                    return $self->_read_p( $row, $context )->then(
                        sub ($content) {
                            return undef if !defined $content;
                            return {
                                attachment_id => $row->{attachment_id},
                                content       => $content,
                                current       =>
                                  _same( $row->{attachment_id}, $avatar_id ),
                                media_type => $row->{media_type} // $SQUARE_TYPE
                            };
                        }
                    );
                }
            );
        }
    );
}

# A square's bytes: PostgreSQL storage reads on the pooled connections;
# files on disk are read in a child, and one that cannot be read is
# logged and answers undef, as picture does.
sub _read_p ( $self, $row, $context ) {
    my $storage = $self->storage;
    return $storage->read_object_p( $row->{object_key}, $MAXIMUM_BYTES,
        $context )
      if $storage->can('read_object_p');
    return GPForum::Infrastructure::AsyncWork->shared->cpu_p(
        sub {
            my $read = {};
            try {
                $read->{content} = $storage->read_object( $row->{object_key} );
            }
            catch ($error) { $read->{error} = "$error"; };
            return $read;
        }
    )->then(
        sub ($read) {
            if ( defined $read->{error} ) {
                $self->_log( "profile picture $row->{attachment_id}"
                      . " unreadable: $read->{error}" );
            }
            return $read->{content};
        }
    );
}

sub picture_from_input ( $self, $input ) {
    return $self->picture( @{$input}{qw(user_id avatar_id side)} );
}

# picture_from_input on the worker's pooled asynchronous connections, as
# picture_p reads it.
sub picture_from_input_p ( $self, $input, $context = undef ) {
    return $self->picture_p( $input, $context );
}

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
    my $held =
        $self->_reviewed($status)
      ? $self->review->find( $status->{pending_attachment_id} )
      : undef;

    return $self->_status( $status, $held );
}

# The same answer read on the worker's pooled asynchronous connections. A
# store without them (a test double) answers the blocking read.
async sub status_p ( $self, $user_id, $context = undef ) {
    return $self->status($user_id) if !$self->store->can('status_p');
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
# object of every upload the member linked to their profile is deleted.
# Returns how many objects were deleted.
sub erase_files ( $self, $user_id ) {
    my $objects = $self->store->objects($user_id);
    for my $object ( @{$objects} ) {
        $self->storage->delete_object( $object->{object_key} );
    }

    return scalar @{$objects};
}

# erase_files on the worker's pooled asynchronous connections, or on the
# transaction $functions belongs to; a storage without asynchronous deletes
# (the filesystem) unlinks in place.
async sub erase_files_p ( $self, $user_id, $context = undef,
    $functions = undef )
{
    my $objects =
      await $self->store->objects_p( $user_id, undef, $context, $functions );
    my $storage = $self->storage;
    for my $object ( @{$objects} ) {
        if ( $storage->can('delete_object_p') ) {
            await $storage->delete_object_p( $object->{object_key},
                $context, $functions );
        }
        else { $storage->delete_object( $object->{object_key} ); }
    }

    return scalar @{$objects};
}

sub _unreadable ( $self, $user_id, $attachment_id ) {
    my $settled =
      $self->store->settle( $user_id, $attachment_id, 'unreadable' );
    $self->_discard( $user_id, $attachment_id, $user_id, $UNREAD );

    return _unreadable_answer($settled);
}

async sub _unreadable_p ( $self, $user_id, $attachment_id, $context ) {
    return await $self->store->functions->transaction_p(
        async sub ($scope) {
            my $settled =
              await $self->store->settle_p( $user_id, $attachment_id,
                'unreadable', $context, $scope );
            await $self->_discard_p( $user_id, $attachment_id, $user_id,
                $UNREAD, $context, $scope );
            return _unreadable_answer($settled);
        },
        $context
    );
}

sub _unreadable_answer ($settled) {
    return {
        ok     => 1,
        status => ( $settled->{status} // q{} ) eq 'ok'
        ? 'unreadable'
        : 'stale'
    };
}

sub _store_square ( $self, $attachment_id, $object_key, $side, $png ) {
    my $key = _square_key( $object_key, $side );
    if ( !$self->storage->exists_object($key) ) {
        $self->storage->write_object( $key, $png );
    }
    $self->attachments->add_variant(
        $self->_square_variant( $attachment_id, $key, $side, $png ) );

    return;
}

# _store_square in the transaction $scope belongs to; files on disk are
# written in place.
async sub _store_square_p ( $self, $attachment_id, $object_key, $side, $png,
    $context, $scope )
{
    my $key     = _square_key( $object_key, $side );
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
        $self->_square_variant( $attachment_id, $key, $side, $png ),
        $context, $scope );

    return;
}

sub _square_key ( $object_key, $side ) {
    return join q{-}, $object_key, 'avatar', $side;
}

sub _square_variant ( $self, $attachment_id, $key, $side, $png ) {
    return {
        attachment_id => $attachment_id,
        byte_size     => length $png,
        media_type    => $SQUARE_TYPE,
        object_key    => $key,
        variant_type  => $self->store->variant_type($side),
    };
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

# _discard on the worker's pooled asynchronous connections, in the
# transaction $scope belongs to when one is given; files on disk are
# removed in place.
async sub _discard_p ( $self, $user_id, $attachment_id, $actor_id, $reason,
    $context, $scope = undef )
{
    return if !defined $attachment_id;

    my $storage = $self->storage;
    my $objects =
      await $self->store->objects_p( $user_id, $attachment_id, $context,
        $scope );
    for my $object ( @{$objects} ) {
        if ( $storage->can('delete_object_p') ) {
            await $storage->delete_object_p( $object->{object_key},
                $context, $scope );
        }
        else { $storage->delete_object( $object->{object_key} ); }
    }
    await $self->attachments->soft_delete_p( $attachment_id, $actor_id,
        $reason, $context, $scope );

    return;
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

=head2 upload_p

L</upload> as a promise, with an optional query context last: the
pipeline's rows and bytes commit in one transaction on the worker's pooled
asynchronous connections, then the offer and the crop follow as in
L</upload>. The antivirus scan and the image tool run in a child that
cannot reach the database.

=head2 process

Takes an attachment id and, optionally, its bytes. Undef when the
attachment is not a member's waiting or shown picture; otherwise
C<< { ok => 1, status => ... } >>: C<shown>, C<unreadable>, C<checking>
(not yet clean, or no tool configured) or C<stale> (replaced meanwhile).

=head2 process_p

L</process> as a promise, with an optional query context last: the rows
are read on the worker's pooled asynchronous connections, the image tool
crops the bytes in a child that cannot reach the database, and the
squares, their variants, the settle and the discards commit in one
transaction.

=head2 remove_own

Takes a member id. Returns C<< { status => 'ok' } >> or C<not_found>.

=head2 remove_own_p

L</remove_own> as a promise, with an optional query context last, on the
worker's pooled asynchronous connections.

=head2 moderate

Takes C<actor_user_id>, C<subject_user_id>, C<attachment_id> and an
optional C<reason>. Returns C<< { status => 'ok' } >>, C<not_found> or
C<invalid> with C<field>.

=head2 moderate_p

L</moderate> as a promise, with an optional query context last, on the
worker's pooled asynchronous connections.

=head2 picture

Takes a member id, the attachment id an address names and a side. Returns
C<< { content, media_type, attachment_id, current } >>, or undef.

=head2 status

Takes a member id. Returns C<available>, C<shown_id>, C<shown_at>,
C<pending_state> and C<pending_at>.

=head2 status_p

L</status> as a promise, with an optional query context last, read on the
worker's pooled asynchronous connections: the picture's row and, for one
waiting, its content review. A store without asynchronous reads answers
the blocking read.

=head2 erase_files

Takes a member id. Deletes the stored objects of every upload linked to
their profile and returns how many.

=head2 erase_files_p

L</erase_files> as a promise, with an optional query context and an
optional transaction call layer last; a storage without asynchronous
deletes unlinks its files in place.

=head2 picture_p

Returns a promise for a bounded avatar image, with asynchronous database reads and isolated filesystem fallback.

=head2 picture_from_input

Adapts the positional picture interface to data-only subprocess inputs.

=head2 picture_from_input_p

L</picture_from_input> as a promise, with an optional query context last:
the read L</picture_p> makes.

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

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
