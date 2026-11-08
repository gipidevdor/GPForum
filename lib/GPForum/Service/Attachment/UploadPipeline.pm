# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Attachment::UploadPipeline;

use GPForum::Infrastructure::Text qw(has_text);
use Mojo::Base 'GPForum::Base', -signatures, -async_await;
use v5.40;
use Const::Fast;

use GPForum::Infrastructure::AsyncWork;
use GPForum::Infrastructure::Row qw(column_of);
use GPForum::Service::Attachment::IntentBuilder;
use GPForum::Service::Attachment::Validator;
use GPForum::Service::Attachment::Source;

our $VERSION = '0.001';
const my $OWNER_MAX_BYTES    => 1_024 * 1_024 * 1_024;
const my $OWNER_MAX_PENDING  => 20;
const my $REQUEST_SCAN_LIMIT => 25 * 1_024 * 1_024;

# Hashed in the worker below this; above it, in a child (cpu_p).
const my $INLINE_HASH_BYTES => 1_024 * 1_024;

has intent_builder => sub {
    return GPForum::Service::Attachment::IntentBuilder->new;
};

# The system antivirus (GPForum::Infrastructure::Antivirus), or undef when the
# operator turned scanning off. ADR 0108.
has antivirus => undef;  # optional: without one an upload waits for the scanner
__PACKAGE__->requires(qw(storage store));
has validator => sub { return GPForum::Service::Attachment::Validator->new; };
has review =>
  undef;    # optional for isolated test doubles; production requires review

# The objects written whose rows the caller's transaction may still roll
# back: the caller that owns it discards them when it does not commit
# (discard_written), and forgets them when it does (forget_written).
has written           => sub { return []; };
has owner_max_bytes   => $OWNER_MAX_BYTES;
has owner_max_pending => $OWNER_MAX_PENDING;

sub upload_and_link ( $self, $input ) {
    return $self->store->schema->txn_do(
        sub { return $self->_upload_and_link($input); } )
      if $self->store->can('schema');
    return $self->_upload_and_link($input);
}

sub _upload_and_link ( $self, $input ) {
    my $source = GPForum::Service::Attachment::Source->from_upload($input);
    return _missing() if !$source || !$source->size;

    my $validated = $self->_validate_source( $input, $source );
    return $validated if !$validated->{ok};

    my $quota = $self->_quota( $input->{actor_user_id}, $source->size );
    return $quota if !$quota->{ok};

    my $intent = $self->intent_builder->build_intent( $validated->{values} );
    $self->_write_source( $intent->{object_key}, $source, $intent->{checksum} );

    # The row is what the orphan purge walks: an object whose row was never
    # written (the insert failed) stayed on disk for good.
    my $created;
    try {
        $created = $self->store->create_intent($intent);
    }
    catch ($error) {
        _discard_object( $self->storage, $intent->{object_key} );
        die $error;    ## no critic (ErrorHandling::RequireCarping) -- the store's own exception, rethrown as raised
    };
    $intent = $self->_kept( $intent, $created, $source );
    push @{ $self->written }, $intent->{object_key};
    if ( $self->review ) {
        $self->review->submit( $intent->{attachment_id}, $input );
    }
    my $uploaded = $self->store->mark_uploaded( $intent->{attachment_id} );
    my $scanned  = $self->_scan_at_upload( $intent->{attachment_id}, $source );
    if ( $self->review ) {
        my $kept = $self->store->find_attachment( $intent->{attachment_id} );
        $scanned->{state} = column_of( $kept, 'state' );
    }
    my $link = $self->_link_target( $input, $intent->{attachment_id} );

    return _uploaded( $intent, $validated, $uploaded, $scanned, $created,
        $link );
}

# upload_and_link on the worker's pooled asynchronous connections: in the
# transaction $functions belongs to when one is given, else in one of its
# own. Hashing a large source and the antivirus scan run in a child that
# cannot reach the database (cpu_p), on the source alone; the scan runs
# before the transaction opens (prescan_p).
async sub upload_and_link_p ( $self, $input, $context = undef,
    $functions = undef )
{
    my $store = $self->store;
    return $self->upload_and_link($input)
      if !$store->can('create_intent_p') || !$store->functions;
    if ( !exists $input->{prescanned} ) {
        $input = { %{$input}, prescanned => await $self->prescan_p($input) };
    }
    return await $self->_upload_and_link_p( $input, $functions, $context )
      if $functions;
    return await $store->functions->transaction_p(
        async sub ($scope) {
            return await $self->_upload_and_link_p( $input, $scope, $context );
        },
        $context
    );
}

async sub _upload_and_link_p ( $self, $input, $scope, $context ) {
    my $store  = $self->store;
    my $source = GPForum::Service::Attachment::Source->from_upload($input);
    return _missing() if !$source || !$source->size;

    my $validated =
      await $self->_validate_source_p( $input, $source, $scope, $context );
    return $validated if !$validated->{ok};

    my $quota = await $self->_quota_p( $input->{actor_user_id},
        $source->size, $scope, $context );
    return $quota if !$quota->{ok};

    my $intent = $self->intent_builder->build_intent( $validated->{values} );
    await $self->_write_source_p( $intent->{object_key}, $source,
        $intent->{checksum}, $scope, $context );

    # As _upload_and_link; an object in transactional storage goes with the
    # rolled-back transaction by itself.
    my $created;
    try {
        $created = await $store->create_intent_p( $intent, $context, $scope );
    }
    catch ($error) {
        if ( !$self->_transactional ) {
            _discard_object( $self->storage, $intent->{object_key} );
        }
        die $error;    ## no critic (ErrorHandling::RequireCarping) -- the store's own exception, rethrown as raised
    };
    $intent =
      await $self->_kept_p( $intent, $created, $source, $scope, $context );
    push @{ $self->written }, $intent->{object_key};
    if ( $self->review ) {
        await $self->_submit_p( $intent->{attachment_id}, $input, $scope,
            $context );
    }
    my $uploaded =
      await $store->mark_uploaded_p( $intent->{attachment_id}, $context,
        $scope );
    my $scanned = await $self->_record_prescan_p( $intent->{attachment_id},
        $input->{prescanned}, $scope, $context );
    if ( $self->review ) {
        my $kept = await $store->find_attachment_p( $intent->{attachment_id},
            $context, $scope );
        $scanned->{state} = column_of( $kept, 'state' );
    }
    my $link = _link_values( $input, $intent->{attachment_id} );
    if ($link) {
        $link = await $store->link_attachment_p( $link, $context, $scope );
    }

    return _uploaded( $intent, $validated, $uploaded, $scanned, $created,
        $link );
}

sub _missing {
    return { ok => 0, errors => { attachment => 'attachment is required' } };
}

sub _uploaded ( $intent, $validated, $uploaded, $scanned, $created, $link ) {
    return {
        ok         => 1,
        attachment => {
            %{$intent},
            media_type  => $validated->{values}{media_type},
            state       => $scanned->{state}       || $uploaded->{state},
            scan_status => $scanned->{scan_status} || 'pending',
        },
        created => $created,
        link    => $link,
    };
}

sub _validate_source ( $self, $input, $source ) {
    my $validated = $self->_validated_upload( $input, $source );
    return $validated if !$validated->{ok};
    $validated->{values}{checksum} = $source->checksum;
    if ( $self->review ) {
        my $allowed =
          $self->review->validate_checksum( $validated->{values}{checksum} );
        return $allowed if !$allowed->{ok};
    }

    return $validated;
}

async sub _validate_source_p ( $self, $input, $source, $scope, $context ) {
    my $validated = $self->_validated_upload( $input, $source );
    return $validated if !$validated->{ok};
    $validated->{values}{checksum} =
      $source->size > $INLINE_HASH_BYTES
      ? await GPForum::Infrastructure::AsyncWork->shared->cpu_p(
        sub { return $source->checksum; } )
      : $source->checksum;
    if ( $self->review ) {
        my $checksum = $validated->{values}{checksum};
        my $allowed =
          $self->review->can('validate_checksum_p')
          ? await $self->review->validate_checksum_p( $checksum, $context,
            $scope )
          : $self->review->validate_checksum($checksum);
        return $allowed if !$allowed->{ok};
    }

    return $validated;
}

# The checks that need neither the whole source nor the database: the
# sniffed and declared type, the size, and the provenance.
sub _validated_upload ( $self, $input, $source ) {
    my $sniffed   = $self->validator->sniff_media_type( $source->sample );
    my $validated = $self->validator->validate_upload(
        {
            byte_size          => $source->size,
            checksum           => 'pending',
            media_type         => _client_media_type($input),
            original_filename  => _original_filename($input),
            owner_user_id      => $input->{actor_user_id},
            sniffed_media_type => $sniffed,
        }
    );
    return $validated if !$validated->{ok};
    if ( $self->review ) {
        my $provenance = $self->review->validate_source($input);
        return $provenance if !$provenance->{ok};
    }

    return $validated;
}

async sub _submit_p ( $self, $attachment_id, $input, $scope, $context ) {
    return $self->review->submit( $attachment_id, $input )
      if !$self->review->can('submit_p');
    return await $self->review->submit_p( $attachment_id, $input, $context,
        $scope );
}

sub _quota ( $self, $owner, $bytes ) {
    return { ok => 1 } if !$self->store->can('check_upload_quota');
    return $self->store->check_upload_quota(
        $self->_quota_values( $owner, $bytes ) );
}

async sub _quota_p ( $self, $owner, $bytes, $scope, $context ) {
    return { ok => 1 } if !$self->store->can('check_upload_quota');
    return await $self->store->check_upload_quota_p(
        $self->_quota_values( $owner, $bytes ),
        $context, $scope );
}

sub _quota_values ( $self, $owner, $bytes ) {
    return {
        owner_user_id => $owner,
        byte_size     => $bytes,
        max_bytes     => $self->owner_max_bytes,
        max_pending   => $self->owner_max_pending,
    };
}

sub _write_source ( $self, $key, $source, $checksum ) {
    return $self->storage->write_source( $key, $source, $checksum )
      if $self->storage->can('write_source');
    return $self->storage->write_object( $key, $source->asset->slurp );
}

# _write_source in the transaction $scope belongs to; a storage without the
# function layer (files on disk) writes as it always does.
async sub _write_source_p ( $self, $key, $source, $checksum, $scope, $context )
{
    return $self->_write_source( $key, $source, $checksum )
      if !$self->storage->can('write_source_p');
    return await $self->storage->write_source_p( $key, $source, $checksum,
        $context, $scope );
}

sub _transactional ($self) {
    return $self->storage->can('transactional')
      && $self->storage->transactional ? 1 : 0;
}

# The intent as the store kept it. On an id collision it reissued the id and
# the key: the bytes move to the new key, and the scan and the link follow
# the new id, where they landed on the attachment holding the old one.
sub _kept ( $self, $intent, $created, $source ) {
    my $kept = _reissued( $intent, $created ) or return $intent;

    $self->_write_source( $kept->{object_key}, $source, $intent->{checksum} );
    _discard_object( $self->storage, $intent->{object_key} );

    return $kept;
}

async sub _kept_p ( $self, $intent, $created, $source, $scope, $context ) {
    my $kept = _reissued( $intent, $created ) or return $intent;

    await $self->_write_source_p( $kept->{object_key}, $source,
        $intent->{checksum}, $scope, $context );
    await $self->_discard_object_p( $intent->{object_key}, $scope, $context );

    return $kept;
}

# _discard_object in the transaction $scope belongs to.
async sub _discard_object_p ( $self, $object_key, $scope, $context ) {
    my $storage = $self->storage;
    return _discard_object( $storage, $object_key )
      if !$storage->can('delete_object_p');
    try {
        await $storage->delete_object_p( $object_key, $context, $scope );
    }
    catch ($ignored) {
        return;
    };

    return;
}

# The intent under the id and key the store reissued, or undef when it kept
# the intent's own.
sub _reissued ( $intent, $created ) {
    my $row = $created->{attachment} or return undef;
    my $key = column_of( $row, 'object_key' );
    return undef if !defined $key || $key eq $intent->{object_key};

    return {
        %{$intent},
        attachment_id => column_of( $row, 'attachment_id' ),
        object_key    => $key,
    };
}

# The verdict the upload can reach by itself. With scanning off, the media
# type check that already passed is the whole verdict, and the row says so
# ('format-check'). With a fast scanner -- the system's clamd, a fraction of a
# second -- the bytes are scanned now, so the common case needs no wait. A
# slow scanner, or one that cannot answer, leaves the upload pending: the
# attachment worker scans it and the outbox retries until it can, and nothing
# pending is ever served.
sub _scan_at_upload ( $self, $attachment_id, $source ) {
    my $plan    = $self->_scan_plan($source) or return {};
    my $verdict = $plan->{verdict} // _verdict_values( $plan->{scan}->() )
      // return {};

    return $self->store->record_scan(
        { %{$verdict}, attachment_id => $attachment_id } );
}

# _scan_at_upload with the scan in a child that cannot reach the database,
# and the verdict recorded in the transaction $scope belongs to.
# The antivirus verdict for an upload's source, reached before any
# transaction opens: the scan runs in a child that cannot reach the
# database, and no pooled connection or post lock waits on it. Answers
# { verdict => ... }, the verdict undef when the scanner could not answer or
# the worker scans the object later.
async sub prescan_p ( $self, $input ) {
    my $source = GPForum::Service::Attachment::Source->from_upload($input);
    return { verdict => undef } if !$source || !$source->size;
    my $plan = $self->_scan_plan($source) or return { verdict => undef };
    return { verdict => $plan->{verdict} } if $plan->{verdict};
    my $scanned =
      await GPForum::Infrastructure::AsyncWork->shared->cpu_p( $plan->{scan} );
    return { verdict => _verdict_values($scanned) };
}

async sub _record_prescan_p ( $self, $attachment_id, $prescanned, $scope,
    $context )
{
    my $verdict = $prescanned && $prescanned->{verdict} or return {};
    return await $self->store->record_scan_p(
        { %{$verdict}, attachment_id => $attachment_id },
        $context, $scope );
}

# What the upload's scan is: a verdict already reached (scanning off), the
# scan to run now (on the source alone), or undef when the worker scans it.
sub _scan_plan ( $self, $source ) {
    my $antivirus = $self->antivirus;
    if ( !$antivirus ) {
        return {
            verdict => {
                actor_id    => 'format-check',
                scan_engine => 'format-check',
                scan_status => 'clean',
            }
        };
    }
    return undef if !$antivirus->answers_immediately;

    # Large media are scanned by the worker, outside the request deadline.
    return undef if $source->size > $REQUEST_SCAN_LIMIT;

    my $scanner = $antivirus->within_request;
    return {
        scan => sub {
            return $scanner->can('scan_source')
              ? $scanner->scan_source($source)
              : $scanner->scan( $source->asset->slurp );
        }
    };
}

# The scanner's verdict as record_scan takes it, or undef for a scanner
# that could not answer.
sub _verdict_values ($verdict) {
    return undef if $verdict->{status} eq 'error';

    return {
        actor_id       => 'antivirus',
        reason         => _verdict_reason($verdict),
        scan_engine    => $verdict->{engine},
        scan_signature => $verdict->{signature},
        scan_status    => $verdict->{status},
    };
}

sub _verdict_reason ($verdict) {
    return "malware: $verdict->{signature}" if $verdict->{status} eq 'infected';

    return undef;
}

sub _link_target ( $self, $input, $attachment_id ) {
    my $link = _link_values( $input, $attachment_id ) or return undef;

    return $self->store->link_attachment($link);
}

sub _link_values ( $input, $attachment_id ) {
    return undef if !has_text( $input->{target_type} );
    return undef if !has_text( $input->{target_id} );

    return {
        attachment_id => $attachment_id,
        target_id     => $input->{target_id},
        target_type   => $input->{target_type},
    };
}

sub _client_media_type ($input) {
    return $input->{media_type} if defined $input->{media_type};

    my $upload = $input->{upload};
    return undef if !$upload;
    return $upload->headers->content_type
      if $upload->can('headers') && $upload->headers;

    return undef;
}

# Deletes the objects written since the last settle: their rows rolled back,
# and the orphan purge, which walks rows, would never find them.
sub discard_written ($self) {
    if ( $self->_transactional ) {
        return $self->forget_written;
    }
    for my $object_key ( splice @{ $self->written } ) {
        _discard_object( $self->storage, $object_key );
    }

    return;
}

# The objects written since the last settle have their rows for good.
sub forget_written ($self) {
    @{ $self->written } = ();

    return;
}

# The object of a row that was never written. A storage that cannot delete
# it now leaves it to the operator: the insert's own error is the one to
# report.
sub _discard_object ( $storage, $object_key ) {
    try {
        $storage->delete_object($object_key);
    }
    catch ($ignored) {
        return;
    };

    return;
}

sub _original_filename ($input) {
    return $input->{original_filename}
      if has_text( $input->{original_filename} );

    my $upload = $input->{upload};
    return $upload->filename if $upload && $upload->can('filename');

    return undef;
}

1;

__END__

=head1 NAME

GPForum::Service::Attachment::UploadPipeline - Validate, store, scan and link an uploaded attachment.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $pipeline = GPForum::Service::Attachment::UploadPipeline->new(
        antivirus => $antivirus,    # or undef when scanning is off
        storage   => GPForum::Service::Attachment::FilesystemStorage->new,
        store     => $attachment_store,
    );

    my $result = $pipeline->upload_and_link(
        {
            actor_user_id => $user_id,
            target_id     => $post_id,
            target_type   => 'post',
            upload        => $controller->req->upload('attachment'),
        }
    );
    return $result->{errors} if !$result->{ok};

=head1 DESCRIPTION

One upload, start to finish. The bytes come from C<content> or from an
upload object; their media type is sniffed and the upload is checked by
L<GPForum::Service::Attachment::Validator>. A valid upload gets an intent from
L<GPForum::Service::Attachment::IntentBuilder>, its bytes are written to the
storage backend, and L<GPForum::Service::Attachment::Store> records the
intent and marks it uploaded. When a target is named, the attachment is
linked to it.

The scan verdict is the one the upload can reach by itself (ADR 0108). With
no C<antivirus> (scanning off) the media type check that already passed is
the whole verdict, recorded as a clean scan by C<format-check>. A scanner
that answers immediately, such as the system's clamd, scans the bytes during
the request. A slow scanner, or one that returns an error, leaves the upload
C<pending>: the attachment worker scans it later, and nothing pending is
served.

=head1 SUBROUTINES/METHODS

=head2 upload_and_link

Takes a hash reference with the bytes in C<content> or an C<upload> object
(one with C<asset> or C<slurp>, such as a L<Mojo::Upload>), and
C<actor_user_id>; optionally C<media_type> and C<original_filename>, which
otherwise come from the upload object, and C<target_type> and C<target_id>
to link the attachment.

Returns C<< { ok => 0, errors => { attachment => 'attachment is required' } } >>
when there are no bytes, and the validator's C<< { ok => 0, errors => ... } >>
when the upload is invalid. Otherwise returns C<< ok => 1 >> with
C<attachment> (the intent plus the validated C<media_type>, the C<state> and
the C<scan_status>, C<pending> unless a scan was recorded), C<created> (what
the store's C<create_intent> returned) and C<link> (the new link, or undef
when no target was given).

The stored object's key is kept in C<written> until the caller says what
became of the transaction its rows are in.

=head2 upload_and_link_p

L</upload_and_link> as a promise, with an optional query context and an
optional transaction call layer last. The rows and, in PostgreSQL storage,
the bytes are written on the worker's pooled asynchronous connections, in
that transaction when one is given. Hashing a large source and the
antivirus scan run in a child that cannot reach the database, on the
source alone.

=head2 prescan_p

Scans an upload's source before any transaction opens, in a child that
cannot reach PostgreSQL, and answers a promise of C<< { verdict => ... } >>;
L</upload_and_link_p> records that verdict instead of scanning inside its
transaction.

=head2 discard_written

Deletes the objects written since the last L</forget_written> or
L</discard_written>: the caller's transaction rolled their rows back, and
the orphan purge, which walks rows, would never find them. A storage that
cannot delete one leaves it.

=head2 forget_written

Forgets those objects: their rows were committed.

=head1 DIAGNOSTICS

Validation failures are returned. Croaks C<unsupported upload object> when
C<upload> has neither C<asset> nor C<slurp>. Errors from the storage
backend and the store propagate.

=head1 CONFIGURATION AND ENVIRONMENT

None here: the bootstrap passes C<antivirus> from the configuration, or undef
when the operator turned scanning off.

=head1 DEPENDENCIES

L<GPForum::Service::Attachment::IntentBuilder>,
L<GPForum::Service::Attachment::Store>,
L<GPForum::Service::Attachment::Validator>.

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
