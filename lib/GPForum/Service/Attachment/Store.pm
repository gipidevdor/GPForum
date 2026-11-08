# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Attachment::Store;

use Const::Fast;
use List::Util qw(any);
use Mojo::Base 'GPForum::Base', -signatures, -async_await;
use v5.40;

use GPForum::Infrastructure::EventRecorder;
use GPForum::Infrastructure::PreparedQuery;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Infrastructure::ResultRow;
use GPForum::Infrastructure::UniqueConflict;
use GPForum::Service::Attachment::DownloadAccess;
use GPForum::Service::Attachment::Event;
use GPForum::Service::Attachment::Lifecycle;
use GPForum::Service::Attachment::Record;
use GPForum::Service::Attachment::ScanQueue;
use GPForum::Service::Clock;
use GPForum::X::Conflict;

our $VERSION = '0.001';

const my $STATE_DELETED             => 'deleted';
const my $STATE_UPLOADED            => 'uploaded';
const my $ID_CONSTRAINT             => 'attachments_pkey';
const my $KEY_CONSTRAINT            => 'attachments_object_key_key';
const my $LINK_ID_CONSTRAINT        => 'attachment_links_pkey';
const my $LINK_TARGET_CONSTRAINT    => 'attachment_links_target_key';
const my $VARIANT_ID_CONSTRAINT     => 'attachment_variants_pkey';
const my $VARIANT_KEY_CONSTRAINT    => 'attachment_variants_variant_key';
const my $VARIANT_OBJECT_CONSTRAINT => 'attachment_variants_object_key_key';
const my $LTE                       => q{<} . q{=};
const my $NO_STORAGE                => 'no attachment storage';
const my %TARGET_RESULTSET          => ( post => 'Post', thread => 'Thread' );

# Correlated on the candidate, so PostgreSQL answers it with the links' unique
# index (attachment_id first) as an anti-join.
const my $UNLINKED => join q{ },
  'NOT EXISTS (SELECT 1 FROM attachment_links',
  'WHERE attachment_links.attachment_id = me.attachment_id)';

has clock      => sub { return GPForum::Service::Clock->new; };
has prepared   => sub { return GPForum::Infrastructure::PreparedQuery->new; };
has id_service => sub {
    require GPForum::Infrastructure::Id;
    return GPForum::Infrastructure::Id->new;
};
has recorder => \&GPForum::Infrastructure::EventRecorder::for_service;
__PACKAGE__->requires(qw(schema));
has functions   => \&GPForum::Infrastructure::SqlFunction::for_service;
has record      => sub { return GPForum::Service::Attachment::Record->new; };
has readability => undef;    # optional: DownloadAccess's, optional there

# The attachment storage (FilesystemStorage, or anything with delete_object):
# the orphan purge removes the files with the rows, and does nothing without
# it.
has storage => undef;    # optional: without one orphan cleanup is skipped

has download_access => sub {
    my ($self) = @_;

    return GPForum::Service::Attachment::DownloadAccess->new(
        readability => $self->readability,
        record      => $self->record,
    );
};
has lifecycle => sub {
    my ($self) = @_;

    return GPForum::Service::Attachment::Lifecycle->new(
        clock  => $self->clock,
        record => $self->record,
    );
};
has events => sub {
    my ($self) = @_;

    return GPForum::Service::Attachment::Event->new(
        id_service => $self->id_service, );
};

# The rescan's and the backfill's queues (ADR 0108), answered here for the
# scanner and the scheduled jobs.
has scan_queue => sub {
    my ($self) = @_;

    return GPForum::Service::Attachment::ScanQueue->new(
        clock  => $self->clock,
        record => $self->record,
        schema => $self->schema,
    );
};

sub create_intent ( $self, $intent ) {
    return _intent_answer(
        $self->schema->txn_do(
            sub {
                return $self->_persist_intent($intent);
            }
        )
    );
}

# create_intent on the worker's pooled asynchronous connections: in the
# transaction $functions belongs to when one is given, else in one of its
# own.
async sub create_intent_p ( $self, $intent, $context = undef,
    $functions = undef )
{
    return $self->create_intent($intent) if !$self->functions;
    return _intent_answer(
        await $self->_in_transaction_p(
            $functions,
            $context,
            async sub ($scope) {
                return await $self->_persist_intent_p( $intent, $scope,
                    $context );
            }
        )
    );
}

sub _intent_answer ($result) {
    return {
        ok         => 1,
        attachment => $result->{attachment},
        ( $result->{skipped} ? ( skipped => 1 ) : () ),
    };
}

# The work on the transaction $functions belongs to, or in a transaction of
# its own on the worker's pooled asynchronous connections.
sub _in_transaction_p ( $self, $functions, $context, $work ) {
    return $work->($functions) if $functions;
    return $self->functions->transaction_p( $work, $context );
}

# Production schemas route through PostgreSQL functions. The thread lock is
# acquired before the post lock, as in the forum's author writes, and SHARE
# also waits for a plain UPDATE of locked_at (KEY SHARE would not).
sub with_post_write ( $self, $input, $work ) {
    return $self->_in_transaction(
        sub {
            if ( $self->functions ) {
                my $guard = $self->functions->row(
                    'attachment_post_write_guard',
                    {
                        post_id => $input->{post_id},
                        actor   => $input->{actor_user_id}
                    }
                );
                my $refusal = $guard ? $guard->{refusal} : 'post not found';
                return undef if ( $refusal // q{} ) eq 'post not found';
                return { error => $refusal, forbidden => 1 } if $refusal;
            }
            return $work->();
        }
    );
}

# with_post_write on the transaction $functions belongs to: the guard's
# locks, then $work_p, which takes the same call layer.
async sub with_post_write_p ( $self, $input, $work_p, $functions,
    $context = undef )
{
    my $guard =
      await $functions->row_p( 'attachment_post_write_guard',
        { post_id => $input->{post_id}, actor => $input->{actor_user_id} },
        $context );
    my $refusal = $guard ? $guard->{refusal} : 'post not found';
    return undef if ( $refusal // q{} ) eq 'post not found';
    return { error => $refusal, forbidden => 1 } if $refusal;
    return await $work_p->($functions);
}

# Called inside the pipeline's transaction before writing any source bytes.
# The owner advisory lock lasts until its attachment metadata commits.
sub check_upload_quota ( $self, $input ) {
    return { ok => 1 } if !$self->functions;
    return _quota_answer(
        $self->functions->row( 'attachment_upload_quota', $input ) );
}

# check_upload_quota on the transaction $functions belongs to, whose
# advisory lock it takes, or on a pooled connection of its own.
async sub check_upload_quota_p (
    $self, $input,
    $context = undef,
    $functions = undef
  )
{
    return { ok => 1 } if !$self->functions;
    $functions //= $self->functions;
    return _quota_answer(
        await $functions->row_p( 'attachment_upload_quota', $input, $context )
    );
}

sub _quota_answer ($quota) {
    return { ok => 1 } if $quota && !$quota->{refusal};
    return {
        ok     => 0,
        errors => {
            attachment => $quota
            ? $quota->{refusal}
            : 'upload quota unavailable'
        }
    };
}

# An intent that finds its attachment, or loses the race to insert it, under
# the same object key finishes that one: the writer that stored it stopped
# short of its event, and the event and audit row are written now, once.
# Under another key -- the id was issued twice -- it is issued a fresh id and
# key, before the insert or after the conflict on the id. So is one whose id
# conflicted although the look after the conflict found no row under it (a
# snapshot older than the holder's commit): the same id would only conflict
# again.
sub _persist_intent ( $self, $intent ) {
    return $self->_insert_once(
        {
            create => sub {
                my $attachment =
                  $self->functions
                  ? GPForum::Infrastructure::ResultRow->from(
                    $self->functions->row(
                        'attachment_insert', { values => $intent }
                    )
                  )
                  : $self->_attachments->create($intent);
                $self->_write_intent_event($intent);
                return { attachment => $attachment };
            },
            find => sub ( $on_key, $conflicted ) {
                return $self->_single_row( 'Attachment',
                    { object_key => $intent->{object_key} } )
                  if $on_key;

                my $taken;
                ( $taken, $intent ) =
                  $self->_taken_or_reissued( $intent,
                    $self->find_attachment( $intent->{attachment_id} ),
                    $conflicted );
                return $taken;
            },
            id_constraint   => $ID_CONSTRAINT,
            key_constraints => [$KEY_CONSTRAINT],
            reuse           => sub ($existing) {
                my $attachment_id =
                  $self->record->column( $existing, 'attachment_id' );
                my $recorded = $self->_single_row( 'EventLog',
                    { idempotency_key => _uploaded_key($attachment_id) } );
                if ( !$recorded ) {
                    $self->_write_intent_event(
                        { %{$intent}, attachment_id => $attachment_id } );
                }
                return { attachment => $existing, skipped => 1 };
            },
        }
    );
}

# _persist_intent on the transaction $functions belongs to: each insert in
# a savepoint of it, so a conflict undoes only that insert.
async sub _persist_intent_p ( $self, $intent, $functions, $context ) {
    return await $self->_insert_once_p(
        {
            create_p => async sub ($scope) {
                my $attachment = GPForum::Infrastructure::ResultRow->from(
                    await $scope->row_p(
                        'attachment_insert', { values => $intent },
                        $context
                    )
                );
                await $self->_record_p( $scope, $context,
                    $self->_intent_event($intent) );
                return { attachment => $attachment };
            },
            find_p => async sub ( $on_key, $conflicted ) {
                return await $self->_single_row_p( 'Attachment',
                    { object_key => $intent->{object_key} },
                    $context, $functions )
                  if $on_key;

                my $taken;
                ( $taken, $intent ) = $self->_taken_or_reissued(
                    $intent,
                    await $self->find_attachment_p(
                        $intent->{attachment_id},
                        $context, $functions
                    ),
                    $conflicted
                );
                return $taken;
            },
            id_constraint   => $ID_CONSTRAINT,
            key_constraints => [$KEY_CONSTRAINT],
            reuse_p         => async sub ($existing) {
                my $attachment_id =
                  $self->record->column( $existing, 'attachment_id' );
                my $recorded = await $functions->row_p( 'ops_event_recorded',
                    { key => _uploaded_key($attachment_id) }, $context );
                if ( !$recorded->{recorded} ) {
                    await $self->_record_p(
                        $functions,
                        $context,
                        $self->_intent_event(
                            { %{$intent}, attachment_id => $attachment_id }
                        )
                    );
                }
                return { attachment => $existing, skipped => 1 };
            },
        },
        $functions
    );
}

# The row an intent's id finds, when it holds the intent's own key, and the
# intent find goes on with: as it was, or under a fresh id and key when the
# id is taken by another key, or conflicted although nothing was found.
sub _taken_or_reissued ( $self, $intent, $taken, $conflicted ) {
    return ( undef, $intent ) if !$taken && !$conflicted;
    my $stored =
      ( $taken && $self->record->column( $taken, 'object_key' ) ) || q{};
    return ( $taken, $intent )
      if length $stored && $stored eq ( $intent->{object_key} || q{} );

    my $attachment_id = $self->id_service->uuid;
    return (
        undef,
        {
            %{$intent},
            attachment_id => $attachment_id,
            object_key    => join( q{/},
                'attachments', $intent->{owner_user_id},
                $attachment_id ),
        }
    );
}

sub _uploaded_key ($attachment_id) {
    return join q{:}, 'attachment.uploaded', $attachment_id;
}

sub link_attachment ( $self, $input ) {
    return $self->_insert_once(
        {
            create => sub {
                return $self->_create_row( 'AttachmentLink',
                    'attachment_link_id', _link_columns($input) );
            },
            find            => sub { return $self->_existing_link($input); },
            id_constraint   => $LINK_ID_CONSTRAINT,
            key_constraints => [$LINK_TARGET_CONSTRAINT],
        }
    );
}

# link_attachment on the transaction $functions belongs to, or in one of its
# own.
async sub link_attachment_p ( $self, $input, $context = undef,
    $functions = undef )
{
    return $self->link_attachment($input) if !$self->functions;
    return await $self->_in_transaction_p(
        $functions,
        $context,
        async sub ($scope) {
            return await $self->_insert_once_p(
                {
                    create_p => async sub ($savepoint) {
                        return await $self->_create_row_p( $savepoint,
                            $context, 'AttachmentLink', 'attachment_link_id',
                            _link_columns($input) );
                    },
                    find_p => async sub (@) {
                        return await $self->_single_row_p( 'AttachmentLink',
                            _link_columns($input), $context, $scope );
                    },
                    id_constraint   => $LINK_ID_CONSTRAINT,
                    key_constraints => [$LINK_TARGET_CONSTRAINT],
                },
                $scope
            );
        }
    );
}

sub _link_columns ($input) {
    return { %{$input}{qw(attachment_id target_id target_type)} };
}

# An intent, link or variant row, inserted unless an equivalent one is there:
# find, asked first and again after a unique conflict (told whether the
# conflict was on a key, and that there was one), names it, and reuse
# answers with it -- by default as an idempotent replay. An id that collides
# is drawn again, once: create draws a fresh one each call, or find reissues
# it.
sub _insert_once ( $self, $spec ) {
    my $reuse = $spec->{reuse}
      || sub ($row) { return $self->_idempotent_row($row) };
    my $existing = $spec->{find}->( 0, 0 );
    return $reuse->($existing) if $existing;

    my ( $created, $error ) =
      GPForum::Infrastructure::UniqueConflict->attempt( $self->schema,
        $spec->{create} );
    return $created if $created;

    my $on_key = _conflict_on_key( $spec, $error );
    $existing = $spec->{find}->( $on_key, 1 );
    return $reuse->($existing) if $existing;
    if ($on_key) {
        GPForum::Infrastructure::UniqueConflict->rethrow($error);
    }

    ( $created, $error ) =
      GPForum::Infrastructure::UniqueConflict->attempt( $self->schema,
        $spec->{create} );
    return $created if $created;

    GPForum::Infrastructure::UniqueConflict->rethrow($error);
}

# _insert_once on the transaction $functions belongs to: find_p, create_p
# and reuse_p answer promises, and each create_p runs in a savepoint.
async sub _insert_once_p ( $self, $spec, $functions ) {
    my $reuse = $spec->{reuse_p}
      || async sub ($row) { return $self->_idempotent_row($row) };
    my $existing = await $spec->{find_p}->( 0, 0 );
    return await $reuse->($existing) if $existing;

    my ( $created, $error ) =
      await GPForum::Infrastructure::UniqueConflict->attempt_p( $functions,
        $spec->{create_p} );
    return $created if $created;

    my $on_key = _conflict_on_key( $spec, $error );
    $existing = await $spec->{find_p}->( $on_key, 1 );
    return await $reuse->($existing) if $existing;
    if ($on_key) {
        GPForum::Infrastructure::UniqueConflict->rethrow($error);
    }

    ( $created, $error ) =
      await GPForum::Infrastructure::UniqueConflict->attempt_p( $functions,
        $spec->{create_p} );
    return $created if $created;

    GPForum::Infrastructure::UniqueConflict->rethrow($error);
}

# Whether an insert's error is a conflict on one of its keys (true) or on
# its id (false); any other error is rethrown.
sub _conflict_on_key ( $spec, $error ) {
    my $conflict = GPForum::X::Conflict->caught($error);
    my $on_key =
      $conflict && any { $conflict->on($_) } @{ $spec->{key_constraints} };
    if ( !$on_key && !( $conflict && $conflict->on( $spec->{id_constraint} ) ) )
    {
        GPForum::Infrastructure::UniqueConflict->rethrow($error);
    }
    return $on_key ? 1 : 0;
}

# A link or variant row under an id drawn on each call, as _insert_once
# expects of create.
sub _create_row ( $self, $resultset, $id_column, $columns ) {
    my $row = $self->_new_row( $id_column, $columns );
    if ( $self->functions ) {
        $self->functions->row( _insert_function($resultset),
            { values => $row } );
    }
    else {
        $self->schema->resultset($resultset)->create($row);
    }

    return $row;
}

# _create_row on the call layer $functions (a savepoint of the caller's
# transaction).
async sub _create_row_p ( $self, $functions, $context, $resultset, $id_column,
    $columns )
{
    my $row = $self->_new_row( $id_column, $columns );
    await $functions->row_p( _insert_function($resultset),
        { values => $row }, $context );
    return $row;
}

sub _new_row ( $self, $id_column, $columns ) {
    return {
        %{$columns},
        $id_column => $self->id_service->uuid,
        created_at => $self->clock->now_iso8601,
    };
}

sub _insert_function ($resultset) {
    return $resultset eq 'AttachmentLink'
      ? 'attachment_link_insert'
      : 'attachment_variant_insert';
}

sub mark_uploaded ( $self, $attachment_id ) {
    my $attachment = $self->find_attachment($attachment_id);
    return undef if !$attachment;
    if ( $self->lifecycle->already_uploaded($attachment) ) {
        return $self->lifecycle->uploaded_replay($attachment);
    }

    my $changes = $self->_uploaded_changes;
    $self->_update_attachment( $attachment, $changes );

    return { attachment_id => $attachment_id, %{$changes} };
}

# mark_uploaded on the worker's pooled asynchronous connections, or on the
# transaction $functions belongs to.
async sub mark_uploaded_p (
    $self, $attachment_id,
    $context = undef,
    $functions = undef
  )
{
    return $self->mark_uploaded($attachment_id) if !$self->functions;
    $functions //= $self->functions;
    my $attachment =
      await $self->find_attachment_p( $attachment_id, $context, $functions );
    return undef if !$attachment;
    if ( $self->lifecycle->already_uploaded($attachment) ) {
        return $self->lifecycle->uploaded_replay($attachment);
    }

    my $changes = $self->_uploaded_changes;
    await $functions->row_p( 'attachment_update',
        { attachment_id => $attachment_id, changes => $changes }, $context );

    return { attachment_id => $attachment_id, %{$changes} };
}

sub _uploaded_changes ($self) {
    return {
        state       => $STATE_UPLOADED,
        uploaded_at => $self->clock->now_iso8601,
    };
}

# A verdict and its event are written together, in one transaction, and only
# over a row the verdict may replace (Lifecycle::replaceable_verdicts): never a
# deleted one, and never 'clean' over 'infected' or 'failed'. The condition is
# in the UPDATE itself, so when two scans race -- the outbox retry and the
# hourly rescan, say -- the database decides, and the loser is a replay.
#
# A verdict is a system action. event_log.actor_id is a uuid, and the
# scanners are named, not users: a name there made PostgreSQL reject the
# insert, so every upload failed as it recorded its verdict. The actor stays
# NULL and the payload says which scanner decided (scanned_by).
sub record_scan ( $self, $input ) {
    my $attachment_id = $input->{attachment_id};

    return $self->_in_transaction(
        sub {
            return undef if !$self->find_attachment($attachment_id);

            my $changes = $self->lifecycle->scan_changes($input);
            my $updated =
              $self->functions
              ? $self->functions->row( 'attachment_scan_verdict',
                { attachment_id => $attachment_id, changes => $changes } )
              ->{changed_count}
              : $self->_attachments->search_rs(
                {
                    attachment_id => $attachment_id,
                    deleted_at    => undef,
                    -or           => $self->lifecycle->replaceable_verdicts(
                        $input->{scan_status}
                    ),
                }
              )->update($changes);

            # Numeric: DBI reports "no rows" as "0E0", which is true.
            if ( !( $updated + 0 ) ) {
                return $self->lifecycle->scanned_replay(
                    $self->find_attachment($attachment_id) );
            }
            $self->_record( $self->_scan_event($input) );

            return { attachment_id => $attachment_id, %{$changes} };
        }
    );
}

# record_scan on the transaction $functions belongs to, or in one of its
# own on the worker's pooled asynchronous connections.
async sub record_scan_p ( $self, $input, $context = undef, $functions = undef )
{
    return $self->record_scan($input) if !$self->functions;
    my $attachment_id = $input->{attachment_id};

    return await $self->_in_transaction_p(
        $functions,
        $context,
        async sub ($scope) {
            return undef
              if !await $self->find_attachment_p( $attachment_id, $context,
                $scope );

            my $changes = $self->lifecycle->scan_changes($input);
            my $verdict =
              await $scope->row_p( 'attachment_scan_verdict',
                { attachment_id => $attachment_id, changes => $changes },
                $context );
            if ( !( $verdict->{changed_count} + 0 ) ) {
                return $self->lifecycle->scanned_replay(
                    await $self->find_attachment_p(
                        $attachment_id, $context, $scope
                    )
                );
            }
            await $self->_record_p( $scope, $context,
                $self->_scan_event($input) );

            return { attachment_id => $attachment_id, %{$changes} };
        }
    );
}

sub _scan_event ( $self, $input ) {
    return {
        actor_id      => undef,
        attachment_id => $input->{attachment_id},
        event_type => $self->events->scan_event_type( $input->{scan_status} ),
        payload    => $self->events->scan_payload($input),
    };
}

sub pending_scan_ids ( $self, $limit ) {
    return $self->scan_queue->pending_scan_ids($limit);
}

sub unscanned_clean_ids ( $self, $limit ) {
    return $self->scan_queue->unscanned_clean_ids($limit);
}

sub confirm_clean ( $self, $input ) {
    return $self->scan_queue->confirm_clean($input);
}

sub record_scan_failure ( $self, $attachment_id, $error ) {
    return $self->scan_queue->record_scan_failure( $attachment_id, $error );
}

sub _attachments ($self) {
    return $self->schema->resultset('Attachment');
}

sub terminal_scan ( $self, $attachment ) {
    return $self->lifecycle->already_scanned($attachment)
      ? $self->lifecycle->scanned_replay($attachment)
      : undef;
}

# The variant of this type, or else the one already holding the object key.
sub find_variant ( $self, $input ) {
    my $existing = $self->_single_row(
        'AttachmentVariant',
        {
            attachment_id => $input->{attachment_id},
            variant_type  => $input->{variant_type},
        }
    );
    return $existing if $existing;

    my $object_key = $input->{object_key};
    return undef if !defined $object_key || !length $object_key;

    return $self->_single_row( 'AttachmentVariant',
        { object_key => $object_key } );
}

async sub find_variant_p ( $self, $input, $context = undef ) {
    return $self->find_variant($input) if !$self->functions;
    return await $self->_find_variant_on_p( $input, $context,
        $self->functions );
}

async sub _find_variant_on_p ( $self, $input, $context, $functions ) {
    my $existing = await $self->_single_row_p(
        'AttachmentVariant',
        {
            attachment_id => $input->{attachment_id},
            variant_type  => $input->{variant_type},
        },
        $context,
        $functions
    );
    return $existing if $existing;

    my $object_key = $input->{object_key};
    return undef if !defined $object_key || !length $object_key;

    return await $self->_single_row_p( 'AttachmentVariant',
        { object_key => $object_key },
        $context, $functions );
}

sub add_variant ( $self, $input ) {
    return $self->_insert_once(
        {
            create => sub {
                return $self->_create_row( 'AttachmentVariant',
                    'attachment_variant_id', _variant_columns($input) );
            },
            find            => sub { return $self->find_variant($input); },
            id_constraint   => $VARIANT_ID_CONSTRAINT,
            key_constraints =>
              [ $VARIANT_KEY_CONSTRAINT, $VARIANT_OBJECT_CONSTRAINT ],
        }
    );
}

# add_variant on the transaction $functions belongs to, or in one of its
# own on the worker's pooled asynchronous connections.
async sub add_variant_p ( $self, $input, $context = undef, $functions = undef )
{
    return $self->add_variant($input) if !$self->functions;
    return await $self->_in_transaction_p(
        $functions,
        $context,
        async sub ($scope) {
            return await $self->_insert_once_p(
                {
                    create_p => async sub ($savepoint) {
                        return await $self->_create_row_p( $savepoint,
                            $context,                'AttachmentVariant',
                            'attachment_variant_id', _variant_columns($input) );
                    },
                    find_p => async sub (@) {
                        return await $self->_find_variant_on_p( $input,
                            $context, $scope );
                    },
                    id_constraint   => $VARIANT_ID_CONSTRAINT,
                    key_constraints =>
                      [ $VARIANT_KEY_CONSTRAINT, $VARIANT_OBJECT_CONSTRAINT ],
                },
                $scope
            );
        }
    );
}

sub _variant_columns ($input) {
    return { %{$input}
          {qw(attachment_id byte_size media_type object_key variant_type)} };
}

sub _idempotent_row ( $self, $existing ) {
    return { %{ $self->lifecycle->row_columns($existing) }, idempotent => 1 };
}

# The row by its id, through a statement built once; an id that is not
# one finds nothing before any statement is sent.
sub find_attachment ( $self, $attachment_id ) {
    return undef if !defined $attachment_id || !length $attachment_id;

    if ( $self->functions ) {
        return GPForum::Infrastructure::ResultRow->from(
            $self->functions->row(
                _single_call(
                    'Attachment', { attachment_id => $attachment_id }
                )
            )
        );
    }
    my $attachments = $self->_attachments;

    return $self->prepared->row(
        schema    => $self->schema,
        shape     => 'attachment:by-id',
        source    => 'Attachment',
        resultset => sub {
            return $attachments->search_rs(
                { 'me.attachment_id' => $attachment_id } );
        },
        fallback =>
          sub { return [ $attachments->find($attachment_id) // () ]; },
        values => { 'me.attachment_id' => $attachment_id },
    );
}

sub download_for ( $self, $input ) {
    my $attachment = $self->find_attachment( $input->{attachment_id} );
    my $denied     = $self->download_access->unavailable($attachment);
    return $denied if $denied;

    my @links = $self->_attachment_links(
        $self->record->column( $attachment, 'attachment_id' ) );
    return $self->download_access->authorized(
        {
            attachment => $attachment,
            linked     => [
                map {
                    +{
                        link   => $_,
                        target => $self->_target_row(
                            $self->record->column( $_, 'target_type' ),
                            $self->record->column( $_, 'target_id' ),
                        ),
                    }
                } @links
            ],
            viewer         => $input->{viewer},
            viewer_user_id => $input->{viewer_user_id},
        }
    );
}

# The same decision on the worker's pooled asynchronous connections: the
# file, its links, their posts and whether the reader may read each are
# read first, and the access rules then decide on what was read.
async sub download_for_p ( $self, $input, $context = undef ) {
    return $self->download_for($input) if !$self->functions;
    my $attachment =
      await $self->find_attachment_p( $input->{attachment_id}, $context );
    my $denied = $self->download_access->unavailable($attachment);
    return $denied if $denied;

    my $reader = $input->{viewer} // $input->{viewer_user_id};
    my ( @linked, %readable );
    for my $link (
        await $self->_attachment_links_p(
            $self->record->column( $attachment, 'attachment_id' ), $context
        )
      )
    {
        my ( $type, $id ) =
          map { $self->record->column( $link, $_ ) } qw(target_type target_id);
        my @call = _target_call( $type, $id );
        my $target =
          @call
          ? GPForum::Infrastructure::ResultRow->from(
            await $self->functions->row_p( @call, $context ) )
          : undef;
        push @linked, { link => $link, target => $target };
        if ( $self->readability && @call ) {
            $readable{"$type:$id"} //=
              await $self->readability->readable_by_p( $reader, $type, $id,
                $context );
        }
    }
    return $self->download_access->authorized(
        {
            attachment     => $attachment,
            linked         => \@linked,
            readable       => \%readable,
            viewer         => $input->{viewer},
            viewer_user_id => $input->{viewer_user_id},
        }
    );
}

async sub find_attachment_p (
    $self, $attachment_id,
    $context = undef,
    $functions = undef
  )
{
    return $self->find_attachment($attachment_id) if !$self->functions;
    return undef if !defined $attachment_id || !length $attachment_id;
    $functions //= $self->functions;
    return GPForum::Infrastructure::ResultRow->from(
        await $functions->row_p(
            _single_call( 'Attachment', { attachment_id => $attachment_id } ),
            $context
        )
    );
}

sub attachments_for_posts ( $self, $post_ids, $input ) {
    my %requested = map { $_ => 1 } @{$post_ids};
    my @ids       = sort keys %requested;
    my $rows;
    if ( $self->functions ) {
        $rows = [
            map { GPForum::Infrastructure::ResultRow->from($_) } @{
                $self->functions->rows( @{ $self->post_files_call( \@ids ) } )
            }
        ];
    }
    else {
        my $links  = $self->schema->resultset('AttachmentLink');
        my $listed = sub {
            return $links->search_rs(
                {
                    'me.target_id'   => { -in => \@ids },
                    'me.target_type' => $self->lifecycle->post_link_target,
                },
                { rows => $self->lifecycle->post_link_rows( \@ids ) },
            );
        };

        # One statement per page size: the page's post ids fill the IN list.
        $rows = $self->prepared->rows(
            schema    => $self->schema,
            shape     => 'attachment_links:posts:' . scalar @ids,
            source    => 'AttachmentLink',
            resultset => $listed,
            fallback  => sub { return [ $self->record->rows( $listed->() ) ]; },
            values    => {
                'me.target_id' => \@ids,
                limit          => $self->lifecycle->post_link_rows( \@ids ),
            },
        );
    }
    my %by_post;
    for my $link ( @{$rows} ) {
        my $post_id = $self->record->column( $link, 'target_id' );
        next if !$requested{$post_id};

        # A row that carries its file and its post (attachment_post_files)
        # is decided on the spot; a bare link (the resultset path) is
        # decided as a download is, which asks for the file, its links and
        # the post, one statement each.
        if ( defined $self->record->column( $link, 'file_state' ) ) {
            my $listed =
              $self->download_access->listing_payload( $link, $input->{viewer},
                $input->{viewer_user_id} );
            if ($listed) {
                push @{ $by_post{$post_id} }, $self->record->view($listed);
            }
            next;
        }

        my $decision = $self->download_for(
            {
                attachment_id =>
                  $self->record->column( $link, 'attachment_id' ),

                # The request's resolved viewer: without it each attachment
                # resolved the reader again.
                viewer         => $input->{viewer},
                viewer_user_id => $input->{viewer_user_id},
            }
        );
        next if !$decision->{ok};

        # The decision's own columns: its attachment is a copy
        # Record::row_hash made of a DBIx::Class row, and came back empty, so
        # a thread page listed each file without its id or its name.
        push @{ $by_post{$post_id} }, $self->record->view($decision);
    }

    return \%by_post;
}

# A private metadata list includes unpublished files without granting downloads.
# Keyset pagination is scoped to one post and its author inside PostgreSQL.
sub owned_uploads_for_post ( $self, $post_id, $actor, $after = undef ) {
    return [] if !$self->functions;
    return $self->functions->rows( 'attachment_owned_post_files',
        { post_id => $post_id, actor_id => $actor, after_id => $after } );
}

async sub owned_uploads_for_post_p (
    $self, $post_id, $actor,
    $after = undef,
    $context = undef
  )
{
    return [] if !$self->functions;
    return await $self->functions->rows_p( 'attachment_owned_post_files',
        { post_id => $post_id, actor_id => $actor, after_id => $after },
        $context );
}

sub post_files_call ( $self, $post_ids ) {
    my %requested = map { $_ => 1 } @{$post_ids};
    my @ids       = sort keys %requested;

    return [
        'attachment_post_files',
        {
            target_type => $self->lifecycle->post_link_target,
            post_ids    => \@ids,
            row_limit   => $self->lifecycle->post_link_rows( \@ids ),
        }
    ];
}

# Uploads that never completed: intents nobody linked, old enough not to be
# an upload still in flight (Lifecycle::orphan_min_age). Each one's files go
# before its row (_purge_orphan). A deleted row is never selected again, so
# the files of a purge that failed after the delete would stay in storage for
# good. Without a storage there is no way to remove the files, and the rows
# stay where the next run finds them. One orphan that fails is reported and
# left; the others are purged all the same.
#
# Orphans only, so the row cap counts orphans: were the linked intents and
# the young ones fetched and skipped, enough of them at the head of the queue
# would keep every run from reaching an orphan behind them.
sub cleanup_orphans ( $self, $input ) {
    if ( !$self->storage ) {
        return {
            %{ $self->lifecycle->cleanup_result( [] ) },
            skipped => $NO_STORAGE
        };
    }

    my @candidates;
    if ( $self->functions ) {
        @candidates = map { GPForum::Infrastructure::ResultRow->from($_) } @{
            $self->functions->rows(
                'attachment_orphans',
                {
                    cutoff    => $self->lifecycle->orphan_cutoff($input),
                    row_limit => $self->lifecycle->orphan_limit($input)
                }
            )
        };
    }
    else {
        my $candidates = $self->_attachments->search_rs(
            {
                %{ $self->lifecycle->orphan_where },
                created_at =>
                  { $LTE => $self->lifecycle->orphan_cutoff($input) },
                -and => [ \$UNLINKED ],
            },
            $self->lifecycle->orphan_search_attrs($input),
        );
        @candidates = $self->record->rows($candidates);
    }
    my ( @deleted, @errors );
    for my $attachment (@candidates) {
        try {
            my $row = $self->_purge_orphan( $attachment, $input );
            if ($row) {
                push @deleted, $row;
            }
        }
        catch ($error) {
            push @errors, join q{: },
              $self->record->column( $attachment, 'attachment_id' ),
              _error_reason($error);
        };
    }

    return $self->lifecycle->cleanup_result( \@deleted, \@errors );
}

sub delete_linked ( $self, $input ) {
    if ( !$self->_existing_link($input) ) {
        return { error => 'not_found', ok => 0 };
    }

    return $self->soft_delete(
        $input->{attachment_id},
        $input->{actor_id}, $self->lifecycle->author_delete_reason($input),
    );
}

# delete_linked on the transaction $functions belongs to.
async sub delete_linked_p ( $self, $input, $functions, $context = undef ) {
    my $link =
      await $self->_single_row_p( 'AttachmentLink',
        { %{$input}{qw(attachment_id target_id target_type)} },
        $context, $functions );
    return { error => 'not_found', ok => 0 } if !$link;

    my $attachment =
      await $self->find_attachment_p( $input->{attachment_id}, $context,
        $functions );
    return { error => 'not_found', ok => 0 } if !$attachment;
    return $self->lifecycle->deleted_replay($attachment)
      if $self->lifecycle->already_deleted($attachment);

    return await $self->_delete_attachment_p( $attachment, $input->{actor_id},
        $self->lifecycle->author_delete_reason($input),
        $functions, $context );
}

# soft_delete on the transaction $functions belongs to, or in one of its
# own on the worker's pooled asynchronous connections.
async sub soft_delete_p (
    $self, $attachment_id, $actor_id, $reason,
    $context = undef,
    $functions = undef
  )
{
    return $self->soft_delete( $attachment_id, $actor_id, $reason )
      if !$self->functions;
    return await $self->_in_transaction_p(
        $functions,
        $context,
        async sub ($scope) {
            my $attachment =
              await $self->find_attachment_p( $attachment_id, $context,
                $scope );
            return { error => 'not_found', ok => 0 } if !$attachment;
            return $self->lifecycle->deleted_replay($attachment)
              if $self->lifecycle->already_deleted($attachment);

            return await $self->_delete_attachment_p( $attachment, $actor_id,
                $reason, $scope, $context );
        }
    );
}

# _delete_attachment on the call layer $functions.
async sub _delete_attachment_p ( $self, $attachment, $actor_id, $reason,
    $functions, $context )
{
    my ( $row, $update, $event, $audit ) =
      $self->_deletion( $attachment, $actor_id, $reason );
    await $functions->row_p( 'attachment_update', $update, $context );
    await $functions->row_p( 'ops_record_event',
        $self->recorder->event_call( %{$event} ), $context );
    await $functions->row_p( 'ops_record_audit',
        $self->recorder->audit_call( %{$audit} ), $context );
    return { attachment => $row, ok => 1 };
}

sub soft_delete ( $self, $attachment_id, $actor_id, $reason ) {
    return $self->_in_transaction(
        sub {
            my $attachment = $self->find_attachment($attachment_id);
            return { error => 'not_found', ok => 0 } if !$attachment;
            if ( $self->lifecycle->already_deleted($attachment) ) {
                return $self->lifecycle->deleted_replay($attachment);
            }

            return $self->_delete_attachment( $attachment, $actor_id, $reason );
        }
    );
}

sub _in_transaction ( $self, $work ) {
    return $self->schema->can('txn_do')
      ? $self->schema->txn_do($work)
      : $work->();
}

sub _existing_link ( $self, $input ) {
    return $self->_single_row( 'AttachmentLink',
        { %{$input}{qw(attachment_id target_id target_type)} } );
}

# Under the row's lock (FOR UPDATE, which a link's foreign-key check waits
# on), and asked again once it is held: a run that got there first has
# deleted the row, and a link committed while this run waited keeps it, so
# two runs at once purge an orphan once, and the files of an attachment just
# linked are not removed. The files go before the row, inside the
# transaction: one rolled back after the removal leaves the row for the next
# run, whose removals find nothing and succeed. The variants' objects go
# first, then the original's; removing an object that is not there is not an
# error, so a run that repeats a removal does no harm.
sub _purge_orphan ( $self, $attachment, $input ) {
    my $attachment_id = $self->record->column( $attachment, 'attachment_id' );

    return $self->schema->txn_do(
        sub {
            my $locked =
              $self->functions
              ? GPForum::Infrastructure::ResultRow->from(
                $self->functions->row(
                    'attachment_find',
                    {
                        attachment_id => $attachment_id,
                        object_key    => undef,
                        hold          => 1
                    }
                )
              )
              : $self->_attachments->find( $attachment_id,
                { for => 'update' } );
            return undef
              if !$locked || !$self->lifecycle->still_intent($locked);
            my @links = $self->_attachment_links($attachment_id);
            return undef if @links;

            my @variants;
            if ( $self->functions ) {
                @variants =
                  map { GPForum::Infrastructure::ResultRow->from($_) } @{
                    $self->functions->rows(
                        'attachment_variants',
                        {
                            attachment_id => $attachment_id,
                            variant_type  => undef,
                            object_key    => undef,
                            row_limit     => undef
                        }
                    )
                  };
            }
            else {
                my $variants =
                  $self->schema->resultset('AttachmentVariant')->search_rs(
                    { attachment_id => $attachment_id },
                    { columns       => ['object_key'] }
                  );
                @variants = $self->record->rows($variants);
            }
            for my $object ( @variants, $locked ) {
                $self->storage->delete_object(
                    $self->record->column( $object, 'object_key' ) );
            }

            return $self->_delete_attachment(
                $locked,
                $self->lifecycle->orphan_actor( $locked, $input ),
                $self->lifecycle->orphan_reason($input),
            )->{attachment};
        }
    );
}

# The reason alone: the first line, without the " at FILE line N." that croak
# and then txn_do's rethrow each add, nor the "{UNKNOWN}: " the rethrow puts
# before an error that is not a DBIx::Class one.
sub _error_reason ($error) {
    my ($line) = split /\n/msx, $error // q{};
    return q{} if !defined $line;
    $line =~ s/\A [{] UNKNOWN [}] : \s+//msx;
    $line =~ s/(?: \s+ at \s+ \S+ \s+ line \s+ \d+ [.]? )+ \s* \z//msx;

    return $line;
}

sub _delete_attachment ( $self, $attachment, $actor_id, $reason ) {
    my ( $row, $update, $event, $audit ) =
      $self->_deletion( $attachment, $actor_id, $reason );
    $self->_update_attachment( $attachment, $update->{changes} );
    $self->recorder->record_event( %{$event} );
    $self->recorder->record_audit( %{$audit} );

    return { attachment => $row, ok => 1 };
}

# A deletion as its statements: the row it answers, the update's values, and
# the event and audit _record would write, under one correlation id.
sub _deletion ( $self, $attachment, $actor_id, $reason ) {
    my $deletion = {
        deleted_at => $self->clock->now_iso8601,
        state      => $STATE_DELETED
    };
    my $attachment_id = $self->record->column( $attachment, 'attachment_id' );
    my $row = { %{ $self->lifecycle->row_columns($attachment) }, %{$deletion} };
    my ( $event, $audit ) = $self->_record_calls(
        _deleted_event( $self, $attachment_id, $actor_id, $reason ),
        { %{$row}, owner_user_id => $actor_id, reason => $reason },
    );
    return ( $row, { attachment_id => $attachment_id, changes => $deletion },
        $event, $audit );
}

sub _deleted_event ( $self, $attachment_id, $actor_id, $reason ) {
    return {
        actor_id      => $actor_id,
        attachment_id => $attachment_id,
        event_type    => 'attachment.deleted',
        payload       => $self->events->deleted_payload(
            { attachment_id => $attachment_id, reason => $reason }
        ),
    };
}

sub _write_intent_event ( $self, $intent ) {
    $self->_record( $self->_intent_event($intent) );

    return;
}

# The upload's event and its audit input, as _record takes them.
sub _intent_event ( $self, $intent ) {
    return (
        {
            actor_id      => $intent->{owner_user_id},
            attachment_id => $intent->{attachment_id},
            event_type    => 'attachment.uploaded',
            payload       => $self->events->uploaded_payload($intent),
        },
        $intent,
    );
}

# The event, and the audit row (for the event's own action) when there is
# one, under one correlation id.
sub _record ( $self, $event, $audit = undef ) {
    my ( $envelope, $audit_input ) = $self->_record_calls( $event, $audit );
    $self->recorder->record_event( %{$envelope} );
    if ($audit_input) {
        $self->recorder->record_audit( %{$audit_input} );
    }

    return;
}

# _record on the call layer $functions.
async sub _record_p ( $self, $functions, $context, $event, $audit = undef ) {
    my ( $envelope, $audit_input ) = $self->_record_calls( $event, $audit );
    await $functions->row_p( 'ops_record_event',
        $self->recorder->event_call( %{$envelope} ), $context );
    if ($audit_input) {
        await $functions->row_p( 'ops_record_audit',
            $self->recorder->audit_call( %{$audit_input} ), $context );
    }

    return;
}

# The event's envelope and the audit's input, under one correlation id.
sub _record_calls ( $self, $event, $audit = undef ) {
    my $correlation_id = $self->id_service->uuid;
    return (
        $self->events->envelope(
            { %{$event}, correlation_id => $correlation_id }
        ),
        $audit
        ? $self->events->audit( $event->{event_type}, $audit, $correlation_id )
        : undef
    );
}

sub _attachment_links ( $self, $attachment_id ) {
    if ( $self->functions ) {
        return
          map { GPForum::Infrastructure::ResultRow->from($_) }
          @{ $self->functions->rows( $self->_links_call($attachment_id) ) };
    }
    my $search = $self->schema->resultset('AttachmentLink')->search_rs(
        { attachment_id => $attachment_id },
        { rows          => $self->lifecycle->link_lookup_rows },
    );

    return $self->record->rows($search);
}

async sub _attachment_links_p ( $self, $attachment_id, $context ) {
    return
      map { GPForum::Infrastructure::ResultRow->from($_) }
      @{ await $self->functions->rows_p( $self->_links_call($attachment_id),
            $context )
      };
}

sub _links_call ( $self, $attachment_id ) {
    return (
        'attachment_links',
        {
            attachment_id => $attachment_id,
            target_type   => undef,
            target_id     => undef,
            row_limit     => $self->lifecycle->link_lookup_rows
        }
    );
}

# The function that reads a link's target, or nothing for a kind of target
# that has none.
sub _target_call ( $target_type, $target_id ) {
    return if !exists $TARGET_RESULTSET{ $target_type // q{} };
    return ( 'attachment_source_' . $target_type, { target_id => $target_id } );
}

sub _target_row ( $self, $target_type, $target_id ) {
    return undef if !exists $TARGET_RESULTSET{$target_type};
    if ( $self->functions ) {
        return GPForum::Infrastructure::ResultRow->from(
            $self->functions->row( _target_call( $target_type, $target_id ) ) );
    }
    my $resultset;
    try {
        $resultset =
          $self->schema->resultset( $TARGET_RESULTSET{$target_type} );
    }
    catch ($error) {
        return undef;
    };

    return $resultset ? $resultset->find($target_id) : undef;
}

sub _update_attachment ( $self, $row, $changes ) {
    return $row->update($changes) if !$self->functions;
    $self->functions->row(
        'attachment_update',
        {
            attachment_id => $self->record->column( $row, 'attachment_id' ),
            changes       => $changes
        }
    );
    %{$row} = ( %{$row}, %{$changes} );
    return $row;
}

sub _single_function_row ( $self, $source, $query ) {
    if ( $source eq 'EventLog' ) {
        return $self->recorder->event_recorded( $query->{idempotency_key} )
          ? { recorded => 1 }
          : undef;
    }
    return GPForum::Infrastructure::ResultRow->from(
        $self->functions->row( _single_call( $source, $query ) ) );
}

async sub _single_row_p ( $self, $source, $query, $context, $functions = undef )
{
    $functions //= $self->functions;
    return GPForum::Infrastructure::ResultRow->from(
        await $functions->row_p( _single_call( $source, $query ), $context ) );
}

# The function, and its values, that read one row of an attachment table.
sub _single_call ( $source, $query ) {
    my ( $name, $params );
    if ( $source eq 'Attachment' ) {
        $name = 'attachment_find';
        $params =
          { attachment_id => undef, object_key => undef, hold => 0, %{$query} };
    }
    elsif ( $source eq 'AttachmentLink' ) {
        $name   = 'attachment_links';
        $params = {
            attachment_id => undef,
            target_type   => undef,
            target_id     => undef,
            row_limit     => 1,
            %{$query}
        };
    }
    else {
        $name   = 'attachment_variants';
        $params = {
            attachment_id => undef,
            variant_type  => undef,
            object_key    => undef,
            row_limit     => 1,
            %{$query}
        };
    }
    return ( $name, $params );
}

sub _single_row ( $self, $resultset_name, $query ) {
    if ( $self->functions ) {
        return $self->_single_function_row( $resultset_name, $query );
    }
    my $search =
      $self->schema->resultset($resultset_name)
      ->search_rs( $query, { rows => 1 } );
    return $search->single if $search->can('single');

    my @rows = $self->record->rows($search);
    return $rows[0];
}

1;

__END__

=head1 NAME

GPForum::Service::Attachment::Store - Attachment rows, links, variants, scan verdicts and deletions.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $store = GPForum::Service::Attachment::Store->new(
        readability => GPForum::Service::Forum::Readability->new(
            schema => $schema,
        ),
        schema => $schema,
    );

    $store->create_intent($intent);    # from IntentBuilder
    $store->mark_uploaded( $intent->{attachment_id} );
    $store->record_scan(
        {
            actor_id      => 'antivirus',
            attachment_id => $intent->{attachment_id},
            scan_engine   => 'clamd',
            scan_status   => 'clean',
        }
    );
    $store->link_attachment(
        {
            attachment_id => $intent->{attachment_id},
            target_id     => $post_id,
            target_type   => 'post',
        }
    );

    my $download = $store->download_for(
        {
            attachment_id  => $attachment_id,
            viewer         => $viewer,
            viewer_user_id => $user_id,
        }
    );
    my $by_post = $store->attachments_for_posts( \@post_ids,
        { viewer => $viewer, viewer_user_id => $user_id } );

=head1 DESCRIPTION

The persistence of attachments. An upload goes through the states
C<intent>, C<uploaded>, then C<available> or C<quarantined> on its scan
verdict, and C<deleted> when it is removed; only an C<available>, C<clean>,
undeleted attachment is ever served. Links tie an attachment to a post, a
thread or a profile, and variants (such as a thumbnail) are further objects
derived from it. The storage of the bytes is elsewhere
(L<GPForum::Service::Attachment::FilesystemStorage>); this class writes rows
and the events and audit entries that go with them, through
L<GPForum::Infrastructure::EventRecorder>, and asks the storage only to
remove the files of the orphans it purges (L</cleanup_orphans>).

Every write can be repeated. Intents, links and variants are found before
they are inserted and inserted under savepoints through
L<GPForum::Infrastructure::UniqueConflict>, so a retry or a concurrent
writer ends on the row that is already there, reported with
C<< idempotent => 1 >> or C<< skipped => 1 >>; a conflict on a generated id
is retried once with a fresh id.

A scan verdict and its event are written in one transaction, and only over
a row the verdict may replace: never a deleted one, and never C<clean> over
C<infected> or C<failed>, while a verdict other than C<clean> may replace
C<clean>, so a later scan can quarantine a file that was being served. The
condition is in the C<UPDATE> itself, so when two scans race (the outbox
retry and the hourly rescan) the database decides and the loser is a
replay. Verdicts are recorded with no actor, because the scanners are not
users; the event payload names the scanner.

The rescan and the backfill of files served on a format check alone, once
an antivirus is configured, take their work from L</pending_scan_ids> and
L</unscanned_clean_ids> (ADR 0108), which
L<GPForum::Service::Attachment::ScanQueue> answers.

=head1 SUBROUTINES/METHODS

=head2 new

Mojo::Base constructor. C<schema> is required. C<readability> (an object
with C<readable_by>, such as L<GPForum::Service::Forum::Readability>) is
optional; without it, downloads through a post or thread are decided on the
target's own visibility column. C<storage> (an object with
C<delete_object>, such as L<GPForum::Service::Attachment::FilesystemStorage>)
is optional, and L</cleanup_orphans> does nothing without it. C<clock>,
C<id_service>, C<recorder>, C<record>, C<download_access>, C<lifecycle>,
C<events> and C<scan_queue> (a L<GPForum::Service::Attachment::ScanQueue>
on the same schema, clock and record) have defaults.

=head2 create_intent

Takes an intent hash reference as built by
L<GPForum::Service::Attachment::IntentBuilder> (C<attachment_id>,
C<owner_user_id>, C<object_key>, C<original_filename>, C<media_type>,
C<byte_size>, C<checksum>, C<< state => 'intent' >>,
C<< scan_status => 'pending' >> and the timestamps). In a transaction,
inserts the attachment and records its C<attachment.uploaded> event and
audit entry. Returns C<< { ok => 1, attachment => $row } >>.

When the id is already taken by a row with the same object key, the
existing row is returned with C<< skipped => 1 >>, and its event and audit
are written first if they are missing. When the id is taken by a row with a
different object key, the intent is reissued with a fresh id and the object
key C<< attachments/<owner_user_id>/<new id> >>.

=head2 create_intent_p

L</create_intent> as a promise, with an optional query context and an
optional transaction call layer last: the row, its event and audit are
written on the worker's pooled asynchronous connections, in that
transaction when one is given, each insert in a savepoint of it.

=head2 with_post_write

Runs a callback in a transaction after checking the input's C<post_id> and
C<actor_user_id> against current author-write rules. Shared thread and post
locks remain held through the callback. An unavailable post returns undef;
an author or lock refusal returns C<forbidden> with its error.

=head2 with_post_write_p

Takes the input, a work that takes the call layer and answers a promise, a
call layer and an optional query context. Runs L</with_post_write>'s guard,
then the work, on the transaction the call layer belongs to.

=head2 check_upload_quota

Checks C<owner_user_id>, C<byte_size>, C<max_bytes> and C<max_pending> inside
the upload transaction. Serializes uploads for that owner until commit;
returns C<ok> or attachment field errors. Retained source size includes
soft-deleted attachment rows because metadata deletion retains bytes.

=head2 check_upload_quota_p

L</check_upload_quota> as a promise, with an optional query context and an
optional transaction call layer last, whose advisory lock it takes.

=head2 mark_uploaded

Takes an attachment id. Moves an C<intent> attachment to C<uploaded> and
stamps C<uploaded_at>; returns C<< { attachment_id, state, uploaded_at } >>.
An attachment past the C<intent> state is left alone and returned as
C<< { attachment_id, idempotent => 1, state, uploaded_at } >>. Returns
C<undef> for an unknown id.

=head2 mark_uploaded_p

L</mark_uploaded> as a promise, with an optional query context and an
optional transaction call layer last.

=head2 record_scan

Takes a hash reference with C<attachment_id>, C<scan_status> (C<clean> or
another verdict), C<scan_engine> and the optional C<scan_signature>,
C<reason> and C<actor_id> (the scanner's name, put in the event payload as
C<scanned_by>). In a transaction, a C<clean> verdict makes the attachment
C<available>; any other makes it C<quarantined> and stamps
C<quarantined_at>. It records C<attachment.scanned> or
C<attachment.quarantined> and returns
C<< { attachment_id, scan_status, scan_engine, scan_signature, scan_error => undef, scanned_at, state } >>
(plus C<quarantined_at>). When the row may not take the verdict, nothing is
written and it returns C<< { attachment_id, idempotent => 1, scan_status, state } >>
with the stored values. Returns C<undef> for an unknown id.

=head2 record_scan_p

L</record_scan> as a promise, with an optional query context and an
optional transaction call layer last: the verdict and its event commit
together on the worker's pooled asynchronous connections.

=head2 terminal_scan

Takes an attachment row. Returns
C<< { attachment_id, idempotent => 1, scan_status, state } >> when its scan
is final (C<clean> and C<available>, or C<infected> and C<quarantined>),
otherwise C<undef>.

=head2 pending_scan_ids

As L<GPForum::Service::Attachment::ScanQueue/pending_scan_ids>.

=head2 unscanned_clean_ids

As L<GPForum::Service::Attachment::ScanQueue/unscanned_clean_ids>.

=head2 confirm_clean

As L<GPForum::Service::Attachment::ScanQueue/confirm_clean>.

=head2 record_scan_failure

As L<GPForum::Service::Attachment::ScanQueue/record_scan_failure>.

=head2 link_attachment

Takes a hash reference with C<attachment_id>, C<target_type> and
C<target_id>. Inserts the link and returns its hash
(C<attachment_link_id>, C<attachment_id>, C<target_type>, C<target_id>,
C<created_at>), or the existing link's columns with C<< idempotent => 1 >>
when the attachment is already linked to that target.

=head2 link_attachment_p

L</link_attachment> as a promise, with an optional query context and an
optional transaction call layer last; the insert runs in a savepoint, so a
conflict that finds the link already there undoes only its own write.

=head2 find_variant

Takes a hash reference with C<attachment_id>, C<variant_type> and an
optional C<object_key>. Returns the attachment's variant of that type, else
the variant stored under that object key, else C<undef>.

=head2 find_variant_p

L</find_variant> as a promise, with an optional query context last, read on
the worker's pooled asynchronous connections.

=head2 add_variant

Takes a hash reference with C<attachment_id>, C<variant_type>,
C<object_key>, C<media_type> and C<byte_size>. Inserts the variant and
returns its hash (with C<attachment_variant_id> and C<created_at>), or the
existing variant's columns with C<< idempotent => 1 >> when
L</find_variant> finds one.

=head2 add_variant_p

L</add_variant> as a promise, with an optional query context and an
optional transaction call layer last, as L</link_attachment_p>.

=head2 find_attachment

Takes an attachment id. Returns the C<Attachment> row, or C<undef>.

=head2 find_attachment_p

L</find_attachment> as a promise: takes the id, an optional query context
and an optional call layer to read on (a transaction's).

=head2 download_for

Takes a hash reference with C<attachment_id>, C<viewer> and
C<viewer_user_id>. Returns C<< { ok => 0, error => 'not_found' } >> when the
attachment is missing, deleted, not C<available> or not C<clean>. Otherwise
L<GPForum::Service::Attachment::DownloadAccess> decides from the
attachment's links: an unlinked attachment, or one linked to a profile, is
served to its owner only; one linked to a post or thread is served only
when the target is present and visible, and then to a viewer who can read
it or to the owner.
Returns C<< { ok => 0, error => 'forbidden' } >> when no link allows it, or
C<< { ok => 1, attachment, attachment_id, byte_size, media_type, object_key, original_filename } >>.

=head2 download_for_p

L</download_for> as a promise, with an optional query context last: the
file, its links, their targets and the reader's access to each are read on
the worker's pooled asynchronous connections first.

=head2 owned_uploads_for_post

Lists the author's undeleted upload metadata and review decisions for one post.
The optional link cursor returns the next keyset page, bounded to 51 rows for
50 items and a continuation marker. No storage keys or bytes are returned.

=head2 owned_uploads_for_post_p

L</owned_uploads_for_post> as a promise, with an optional query context last,
read on the worker's pooled asynchronous connections.

=head2 attachments_for_posts

Takes an array reference of post ids and a hash reference with C<viewer>
and C<viewer_user_id>. Returns a hash reference from post id to an array
reference of C<< { attachment_id, byte_size, media_type, original_filename } >>,
one per linked attachment that L</download_for> lets the viewer have, read
from the download decision's own columns. The link query is capped at ten
rows per requested post. Posts without such attachments have no key.

=head2 post_files_call

Takes an array reference of post ids. Returns the catalogue name and the
parameters of the call L</attachments_for_posts> makes on PostgreSQL,
C<attachment_post_files>: the links of those posts, each with its file and
its post, in one statement. A thread page that reads its posts' extras in
one statement answers it.

=head2 cleanup_orphans

Takes a hash reference with optional C<limit> (100), C<min_age> in seconds
(one day), C<actor_id> (each attachment's owner when absent) and C<reason>
(C<orphan cleanup>). Purges the orphans: attachments still in the C<intent>
state, without links, and created at least C<min_age> ago -- younger, an
intent may be an upload still in flight -- oldest first, up to the limit,
which counts orphans only.

Each orphan is purged in a transaction of its own, under its row's lock
(C<SELECT ... FOR UPDATE>), and only if, once the lock is held, it is still
an intent without links: two runs at once purge it once, and an attachment
linked while the run waited keeps its files. It removes the stored object of
every variant and then the attachment's own object through C<storage>, and
then soft-deletes the row as L</soft_delete> does, recording the deletion in
the actor's name for the reason. The files go first: a deleted row is never
selected again, while a row left by a purge that failed after the removal is
purged by the next run, whose removals find nothing and succeed. The variant
rows stay with the soft-deleted attachment.

Returns C<< { ok => 1, deleted => \@attachments } >>, the columns of each
attachment this run deleted. An orphan that could not be purged -- a file
the storage would not remove, a lock not had within the database's
C<lock_timeout> -- is left as it is, and the run goes on to the next and
returns C<< ok => 0 >> with C<errors>, one C<< "<attachment_id>: <reason>" >>
each. Without a C<storage> nothing is purged, and it returns
C<< { ok => 1, deleted => [], skipped => 'no attachment storage' } >>.

=head2 delete_linked

Takes a hash reference with C<attachment_id>, C<target_type>,
C<target_id>, C<actor_id> and an optional C<reason> (C<author delete>).
Soft-deletes the attachment when it is linked to that target; otherwise
returns C<< { ok => 0, error => 'not_found' } >>. Whether the actor may
delete it is the caller's decision.

=head2 delete_linked_p

L</delete_linked> on the transaction the given call layer belongs to: takes
the input, the call layer and an optional query context, and answers a
promise of what L</delete_linked> answers.

=head2 soft_delete

Takes an attachment id, an actor id and a reason. In a transaction, sets
C<state> to C<deleted>, stamps C<deleted_at> and records an
C<attachment.deleted> event and audit entry; returns
C<< { ok => 1, attachment => \%attachment } >>, the attachment's columns as
they now are. An attachment already deleted is returned, with its columns,
with C<< idempotent => 1 >> and nothing written; an unknown id returns
C<< { ok => 0, error => 'not_found' } >>.

=head2 soft_delete_p

L</soft_delete> as a promise, with an optional query context and an
optional transaction call layer last: the row, its event and audit are
written on the worker's pooled asynchronous connections.

=head1 DIAGNOSTICS

Missing attachments, refused downloads and replays are returned, not
thrown. Database errors other than the handled unique conflicts are
rethrown, and a write inside a transaction rolls back. L</cleanup_orphans>
alone catches what fails for one orphan, storage and database errors alike,
and reports it in C<errors>.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Service::Attachment::DownloadAccess>,
L<GPForum::Service::Attachment::Event>,
L<GPForum::Service::Attachment::Lifecycle>,
L<GPForum::Service::Attachment::Record>,
L<GPForum::Service::Attachment::ScanQueue>,
L<GPForum::Infrastructure::EventRecorder>,
L<GPForum::Infrastructure::UniqueConflict>, L<GPForum::Infrastructure::Id>,
L<GPForum::Service::Clock>.

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
