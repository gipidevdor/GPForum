# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Portability::ExportBundleBuilder;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -signatures, -async_await;
use v5.40;

use GPForum::Infrastructure::SqlFunction;

use GPForum::Infrastructure::Row qw(column_of rows_in);
use GPForum::Infrastructure::EventRecorder;
use GPForum::Infrastructure::UniqueConflict;
use GPForum::X::Conflict;
use GPForum::Service::Clock;

has functions => \&GPForum::Infrastructure::SqlFunction::for_service;

our $VERSION = '0.001';

const my $FORMAT_JSON        => 'json';
const my $SCHEMA_VERSION     => 1;
const my $USER_AGGREGATE     => 'user';
const my $STATUS_COMPLETED   => 'completed';
const my $ID_CONSTRAINT      => 'export_requests_pkey';
const my $PENDING_CONSTRAINT => 'idx_export_requests_pending_unique';
const my @POST_FIELDS => qw(
  post_id thread_id visibility moderation_state
  position created_at updated_at deleted_at current_body_id
);
const my @ATTACHMENT_FIELDS => qw(
  attachment_id original_filename media_type byte_size
  checksum state scan_status created_at uploaded_at deleted_at
);
const my @NOTIFICATION_FIELDS => qw(
  notification_id created_at read_at
);
const my @SUBSCRIPTION_FIELDS => qw(
  subscription_id target_type target_id preference
  created_at muted_at revoked_at
);
const my @PREFERENCE_FIELDS => qw(
  channel enabled digest_frequency updated_at
);
const my @BODY_FIELDS => qw(
  body_id body_source body_format
);

# Each part a stored export reads: its resultset, the column naming the
# member, and the fields it keeps.
const my %EXPORT_PARTS => (
    attachments   => [ 'Attachment', 'owner_user_id', \@ATTACHMENT_FIELDS ],
    notifications =>
      [ 'NotificationInbox', 'recipient_user_id', \@NOTIFICATION_FIELDS ],
    posts       => [ 'Post', 'author_user_id',            \@POST_FIELDS ],
    preferences => [ 'NotificationPreference', 'user_id', \@PREFERENCE_FIELDS ],
    subscriptions => [ 'Subscription', 'user_id', \@SUBSCRIPTION_FIELDS ],
);

has clock      => sub { return GPForum::Service::Clock->new; };
has id_service => sub {
    require GPForum::Infrastructure::Id;
    return GPForum::Infrastructure::Id->new;
};
has recorder => sub {
    my ($self) = @_;

    return GPForum::Infrastructure::EventRecorder->new(
        id_service => $self->id_service,
        schema     => $self->schema,
        functions  => $self->functions,
    );
};
__PACKAGE__->requires(qw(schema));

# Post ids bound per statement when reading a member's post bodies: libpq
# refuses more than 65,535 parameters, and one bind per post of a long-time
# member of a large forum passed that, so the whole export failed.
has body_batch_size => 10_000;

sub create_request ( $self, $input ) {
    return $self->schema->txn_do(
        sub {
            return $self->_create_or_reuse_request($input);
        }
    );
}

# create_request in one transaction on the worker's pooled asynchronous
# connections, or in a savepoint of the transaction $functions belongs to.
async sub create_request_p ( $self, $input, $context = undef,
    $functions = undef )
{
    $functions //= $self->functions;
    return $self->create_request($input) if !$functions;

    return await $functions->transaction_p(
        async sub ($scope) {
            return await $self->_create_or_reuse_request_p( $scope, $input,
                $context );
        },
        $context
    );
}

# A member has one pending export at a time: a request that finds one, or
# loses the race to insert one, answers with it. A request id that collides
# is drawn again, once.
sub _create_or_reuse_request ( $self, $input ) {
    my $existing = $self->_pending_request($input);
    return $self->_finish_leftover_export($existing) if $existing;

    my ( $created, $error ) =
      GPForum::Infrastructure::UniqueConflict->attempt( $self->schema,
        sub { return $self->_insert_request($input); } );
    return $created if $created;

    my $conflict = _request_conflict($error);
    $existing = $self->_pending_request($input);
    return $self->_finish_leftover_export($existing) if $existing;
    _retry_only_a_taken_id( $conflict, $error );

    ( $created, $error ) =
      GPForum::Infrastructure::UniqueConflict->attempt( $self->schema,
        sub { return $self->_insert_request($input); } );
    return $created if $created;

    GPForum::Infrastructure::UniqueConflict->rethrow($error);
}

async sub _create_or_reuse_request_p ( $self, $db, $input, $context ) {
    my $existing = await $self->_pending_request_p( $db, $input, $context );
    return await $self->_finish_leftover_export_p( $db, $existing, $context )
      if $existing;

    my $insert = async sub ($savepoint) {
        return await $self->_insert_request_p( $savepoint, $input, $context );
    };
    my ( $created, $error ) =
      await GPForum::Infrastructure::UniqueConflict->attempt_p( $db, $insert );
    return $created if $created;

    my $conflict = _request_conflict($error);
    $existing = await $self->_pending_request_p( $db, $input, $context );
    return await $self->_finish_leftover_export_p( $db, $existing, $context )
      if $existing;
    _retry_only_a_taken_id( $conflict, $error );

    ( $created, $error ) =
      await GPForum::Infrastructure::UniqueConflict->attempt_p( $db, $insert );
    return $created if $created;

    GPForum::Infrastructure::UniqueConflict->rethrow($error);
}

# The conflict an insert lost to another pending request or a taken id;
# any other error is rethrown.
sub _request_conflict ($error) {
    my $conflict = GPForum::X::Conflict->caught($error);
    if (
        !$conflict
        || !(
            $conflict->on($ID_CONSTRAINT) || $conflict->on($PENDING_CONSTRAINT)
        )
      )
    {
        GPForum::Infrastructure::UniqueConflict->rethrow($error);
    }

    return $conflict;
}

# A pending request that won the race and is no longer found is final; only
# a minted id that collided is drawn again.
sub _retry_only_a_taken_id ( $conflict, $error ) {
    if ( $conflict->on($PENDING_CONSTRAINT) ) {
        GPForum::Infrastructure::UniqueConflict->rethrow($error);
    }

    return;
}

sub _pending_request ( $self, $input ) {
    if ( $self->functions ) {
        my $row =
          $self->functions->row( 'privacy_latest', _pending_query($input) );
        return $row ? $row->{document} : undef;
    }

    my $resultset = $self->schema->resultset('ExportRequest');
    my $search    = $resultset->search_rs(
        {
            export_type       => $input->{export_type},
            format            => $input->{format} || $FORMAT_JSON,
            requester_user_id => $input->{requester_user_id},
            status            => 'pending',
            subject_user_id   => $input->{subject_user_id},
        },
        {
            order_by => { -desc => 'created_at' },
            rows     => 1,
        }
    );
    my $row = $search->single;
    if ( !$row ) {
        return undef;
    }

    return _request_hash($row);
}

async sub _pending_request_p ( $self, $db, $input, $context ) {
    my $row =
      await $db->row_p( 'privacy_latest', _pending_query($input), $context );
    return $row ? $row->{document} : undef;
}

sub _pending_query ($input) {
    return {
        source => 'ExportRequest',
        query  => { %{$input}, format => $input->{format} || $FORMAT_JSON }
    };
}

sub _insert_request ( $self, $input ) {
    my $request = $self->_new_request($input);
    if ( $self->functions ) {
        $self->functions->row( 'privacy_insert',
            { source => 'ExportRequest', row => $request } );
    }
    else {
        $self->schema->resultset('ExportRequest')->create($request);
    }
    $self->_record_event_and_audit( _requested_record($request) );

    return $request;
}

async sub _insert_request_p ( $self, $db, $input, $context ) {
    my $request = $self->_new_request($input);
    await $db->row_p( 'privacy_insert',
        { source => 'ExportRequest', row => $request }, $context );
    await $self->_record_event_and_audit_p( $db, _requested_record($request),
        $context );

    return $request;
}

sub _new_request ( $self, $input ) {
    return {
        export_request_id => $self->id_service->uuid,
        requester_user_id => $input->{requester_user_id},
        subject_user_id   => $input->{subject_user_id},
        export_type       => $input->{export_type},
        format            => $input->{format} || $FORMAT_JSON,
        status            => 'pending',
        created_at        => $self->clock->now_iso8601,
        finished_at       => undef,
        manifest          => {},
    };
}

sub _requested_record ($request) {
    return {
        action      => 'privacy.export_requested',
        actor_id    => $request->{requester_user_id},
        request     => $request,
        payload     => _request_payload($request),
        metadata    => {},
        created_at  => $request->{created_at},
        idempotency => $request->{export_request_id},
    };
}

# A pending request left by a writer that stopped before its event: the
# event and audit row are written now, once.
sub _finish_leftover_export ( $self, $existing ) {
    my $recorded = $self->recorder->event_recorded( _requested_key($existing) );
    if ( !$recorded ) {
        $self->_record_event_and_audit( $self->_leftover_record($existing) );
    }

    return $existing;
}

async sub _finish_leftover_export_p ( $self, $db, $existing, $context ) {
    my $recorded = await $db->row_p( 'ops_event_recorded',
        { key => _requested_key($existing) }, $context );
    if ( !$recorded->{recorded} ) {
        await $self->_record_event_and_audit_p( $db,
            $self->_leftover_record($existing), $context );
    }

    return $existing;
}

sub _requested_key ($existing) {
    return join q{:}, 'privacy.export_requested',
      $existing->{export_request_id};
}

sub _leftover_record ( $self, $existing ) {
    return {
        %{ _requested_record($existing) },
        created_at => $existing->{created_at} || $self->clock->now_iso8601,
    };
}

sub request_user_export ( $self, $user_id ) {
    return $self->create_request( _user_export($user_id) );
}

# request_user_export on the worker's pooled asynchronous connections.
async sub request_user_export_p (
    $self, $user_id,
    $context = undef,
    $functions = undef
  )
{
    return await $self->create_request_p( _user_export($user_id), $context,
        $functions );
}

sub _user_export ($user_id) {
    return {
        requester_user_id => $user_id,
        subject_user_id   => $user_id,
        export_type       => 'user_data',
        format            => $FORMAT_JSON,
    };
}

sub complete_user_export ( $self, $export_request_id, $parts = undef ) {
    return $self->schema->txn_do(
        sub {
            return $self->_complete_request( $export_request_id, $parts );
        }
    );
}

# complete_user_export in one transaction on the worker's pooled
# asynchronous connections, or in a savepoint of the transaction $functions
# belongs to: the request, its parts in one statement
# (api.portability_export_parts), the stored bundle and its events.
async sub complete_user_export_p (
    $self, $export_request_id,
    $parts     = undef,
    $context   = undef,
    $functions = undef
  )
{
    $functions //= $self->functions;
    return $self->complete_user_export( $export_request_id, $parts )
      if !$functions;

    return await $functions->transaction_p(
        async sub ($scope) {
            return await $self->_complete_request_p( $scope,
                $export_request_id, $parts, $context );
        },
        $context
    );
}

sub _complete_request ( $self, $export_request_id, $parts ) {
    my $request;
    if ( $self->functions ) {
        my $row =
          $self->functions->row( 'privacy_find',
            _find_request($export_request_id) );
        $request = $row ? $row->{document} : undef;
    }
    else {
        $request =
          $self->schema->resultset('ExportRequest')->find($export_request_id);
    }
    if ( !$request ) {
        return undef;
    }
    if ( _is_completed($request) ) {
        return _request_hash($request);
    }

    my $subject_user_id = column_of( $request, 'subject_user_id' );
    my $done            = $self->_completion( $request,
          $parts
        ? $self->build_user_bundle( $subject_user_id, $parts )
        : $self->_build_user_bundle_from_storage($subject_user_id) );
    if ( $self->functions ) {
        $self->functions->row( 'privacy_update',
            _update_request( $export_request_id, $done->{changes} ) );
        @{$request}{ keys %{ $done->{changes} } } =
          values %{ $done->{changes} };
    }
    else { $request->update( $done->{changes} ); }
    $self->_record_event_and_audit( _completed_record( $request, $done ) );

    return _completed_hash( $request, $done );
}

async sub _complete_request_p ( $self, $db, $export_request_id, $parts,
    $context )
{
    my $row = await $db->row_p( 'privacy_find',
        _find_request($export_request_id), $context );
    my $request = $row ? $row->{document} : undef;
    return undef                   if !$request;
    return _request_hash($request) if _is_completed($request);

    my $subject_user_id = column_of( $request, 'subject_user_id' );
    $parts //= (
        await $db->row_p(
            'portability_export_parts', { user_id => $subject_user_id },
            $context
        )
    )->{document};
    my $done = $self->_completion( $request,
        $self->build_user_bundle( $subject_user_id, $parts ) );
    await $db->row_p( 'privacy_update',
        _update_request( $export_request_id, $done->{changes} ), $context );
    @{$request}{ keys %{ $done->{changes} } } = values %{ $done->{changes} };
    await $self->_record_event_and_audit_p( $db,
        _completed_record( $request, $done ), $context );

    return _completed_hash( $request, $done );
}

sub _find_request ($export_request_id) {
    return {
        source   => 'ExportRequest',
        id       => $export_request_id,
        lock_row => 0
    };
}

sub _update_request ( $export_request_id, $changes ) {
    return {
        source  => 'ExportRequest',
        id      => $export_request_id,
        changes => $changes
    };
}

sub _is_completed ($request) {
    return ( column_of( $request, 'status' ) || q{} ) eq $STATUS_COMPLETED;
}

# The stored manifest is what the member downloads: the summary and every
# part. Six named parts were kept and the rest counted only, so an export
# said "5 direct messages" and held none of them.
sub _completion ( $self, $request, $bundle ) {
    my $summary  = $self->safe_manifest($bundle);
    my $stored   = { %{$bundle}, %{$summary} };
    my $finished = $self->clock->now_iso8601;
    return {
        changes => {
            status      => $STATUS_COMPLETED,
            finished_at => $finished,
            manifest    => $stored
        },
        finished => $finished,
        stored   => $stored,
        summary  => $summary,
    };
}

sub _completed_record ( $request, $done ) {
    my $request_id = column_of( $request, 'export_request_id' );
    return {
        action   => 'privacy.export_completed',
        actor_id => column_of( $request, 'requester_user_id' ),
        request  => $request,
        payload  => {
            %{ _request_payload($request) }, manifest => $done->{summary},
        },
        metadata => {
            export_request_id => $request_id,
            counts            => $done->{summary}{counts},
        },
        created_at  => $done->{finished},
        idempotency => $request_id . q{:completed},
    };
}

sub _completed_hash ( $request, $done ) {
    return {
        %{ _request_hash($request) },
        status      => $STATUS_COMPLETED,
        finished_at => $done->{finished},
        manifest    => $done->{stored},
    };
}

# The parts of a bundle that are lists, each an empty one when the subject
# has none: what they wrote, kept, were sent and chose; the members they
# ignore or block (ADR 0130); their posts held for review, as written (ADR
# 0134); their choices by kind of notification (ADR 0078); their
# conversations and the messages they wrote (ADR 0139); the likes and the
# reactions they gave; their bookmarks, with notes and folders (ADR 0136).
const my @LIST_PARTS => qw(
  posts drafts attachments notifications subscriptions preferences
  member_relations held_posts notification_type_preferences direct_messages
  likes reactions bookmarks push_devices passkeys
);

sub build_user_bundle ( $self, $subject_user_id, $parts ) {
    return {
        subject_user_id => $subject_user_id,
        generated_at    => $self->clock->now_iso8601,
        format          => $FORMAT_JSON,
        %{ _community_parts($parts) },
        ( map { $_ => $parts->{$_} || [] } @LIST_PARTS ),
        profile => $parts->{profile} || {},

        # ADR 0142: whether two-step sign-in is on, since when, and the
        # recovery codes left; never the secret or the codes.
        second_factor => _second_factor_part($parts),

        # ADR 0144: the picture the subject shows, since when, and the one
        # waiting; the uploads themselves are among their attachments.
        avatar => _avatar_part($parts),
    };
}

sub _community_parts ($parts) {
    return {
        poll_ballots => $parts->{poll_ballots} || [],
        admission    => $parts->{admission}
    };
}

sub _second_factor_part ($parts) {
    return $parts->{second_factor} || { state => 'off' };
}

sub _avatar_part ($parts) {
    return $parts->{avatar} || { attachment_id => undef };
}

sub safe_manifest ( $self, $bundle ) {
    return {
        subject_user_id => $bundle->{subject_user_id},
        generated_at    => $bundle->{generated_at},
        format          => $bundle->{format},
        counts          => {
            posts            => scalar @{ $bundle->{posts} },
            drafts           => scalar @{ $bundle->{drafts} // [] },
            attachments      => scalar @{ $bundle->{attachments} },
            notifications    => scalar @{ $bundle->{notifications} },
            subscriptions    => scalar @{ $bundle->{subscriptions} },
            preferences      => scalar @{ $bundle->{preferences} },
            member_relations => scalar @{ $bundle->{member_relations} // [] },
            held_posts       => scalar @{ $bundle->{held_posts}       // [] },
            notification_type_preferences =>
              scalar @{ $bundle->{notification_type_preferences} // [] },
            direct_messages => scalar @{ $bundle->{direct_messages} // [] },
            likes           => scalar @{ $bundle->{likes}           // [] },
            reactions       => scalar @{ $bundle->{reactions}       // [] },
            poll_ballots    => scalar @{ $bundle->{poll_ballots}    // [] },
            bookmarks       => scalar @{ $bundle->{bookmarks}       // [] },
        },
    };
}

# Every part read from storage, the posts with their bodies.
sub _build_user_bundle_from_storage ( $self, $subject_user_id ) {
    if ( $self->functions ) {
        my $parts = $self->functions->row( 'portability_export_parts',
            { user_id => $subject_user_id } )->{document};
        return $self->build_user_bundle( $subject_user_id, $parts );
    }

    my %parts;
    for my $part ( sort keys %EXPORT_PARTS ) {
        my ( $resultset, $member_column, $fields ) = @{ $EXPORT_PARTS{$part} };
        $parts{$part} =
          $self->_search_hashes( $resultset,
            { $member_column => $subject_user_id }, $fields );
    }
    $self->_attach_post_bodies( $parts{posts} );
    $parts{profile} = $self->_safe_profile($subject_user_id);

    return $self->build_user_bundle( $subject_user_id, \%parts );
}

# Each post carries the body it shows, its current one, read body_batch_size
# posts at a time; the export does not name the body's id.
sub _attach_post_bodies ( $self, $posts ) {
    my @ids = grep { defined } map { $_->{current_body_id} } @{$posts};
    my %body_of;
    while ( my @batch = splice @ids, 0, $self->body_batch_size ) {
        my $bodies =
          $self->_search_hashes( 'PostBody', { body_id => { -in => \@batch } },
            \@BODY_FIELDS );
        for my $body ( @{$bodies} ) {
            $body_of{ $body->{body_id} } = $body;
        }
    }

    for my $post ( @{$posts} ) {
        my $body = $body_of{ delete $post->{current_body_id} // q{} } || {};
        $post->{body_format} = $body->{body_format};
        $post->{body_source} = $body->{body_source};
    }

    return;
}

sub _search_hashes ( $self, $name, $query, $fields ) {
    my $resultset;
    try {
        $resultset = $self->schema->resultset($name);
    }
    catch ($error) {
        return [];
    };
    if ( !$resultset ) {
        return [];
    }

    my @hashes;
    for my $row ( rows_in( $resultset->search_rs($query) ) ) {
        push @hashes, { map { $_ => column_of( $row, $_ ) } @{$fields} };
    }

    return \@hashes;
}

sub _safe_profile ( $self, $subject_user_id ) {
    my $user;
    try {
        $user = $self->schema->resultset('User')->find($subject_user_id);
    }
    catch ($error) {
        return {};
    };
    if ( !$user ) {
        return {};
    }

    return {
        created_at         => column_of( $user, 'created_at' ),
        display_name       => column_of( $user, 'display_name' ),
        email              => column_of( $user, 'email_normalized' ),
        email_verified_at  => column_of( $user, 'email_verified_at' ),
        preferred_locale   => column_of( $user, 'preferred_locale' ),
        preferred_theme    => column_of( $user, 'preferred_theme' ),
        preferred_timezone => column_of( $user, 'preferred_timezone' ),
        status             => column_of( $user, 'status' ),
        user_id            => column_of( $user, 'id' ),
        username           => column_of( $user, 'username' ),
    };
}

sub _record_event_and_audit ( $self, $input ) {
    my ( $event, $audit ) = $self->_event_and_audit($input);
    $self->recorder->record_event( %{$event} );
    $self->recorder->record_audit( %{$audit} );

    return;
}

# The event and the audit entry on the transaction's own call layer.
async sub _record_event_and_audit_p ( $self, $db, $input, $context ) {
    my ( $event, $audit ) = $self->_event_and_audit($input);
    my $recorder = GPForum::Infrastructure::EventRecorder->new(
        id_service => $self->id_service,
        schema     => $self->schema,
        functions  => $db,
    );
    await $recorder->record_event_p( $event, $context );
    await $recorder->record_audit_p( $audit, $context );

    return;
}

sub _event_and_audit ( $self, $input ) {
    my $request        = $input->{request};
    my $correlation_id = $self->id_service->uuid;
    my %event          = (
        event_type        => $input->{action},
        aggregate_type    => $USER_AGGREGATE,
        aggregate_id      => column_of( $request, 'subject_user_id' ),
        aggregate_version => $SCHEMA_VERSION,
        actor_id          => $input->{actor_id},
        correlation_id    => $correlation_id,
        causation_id      => undef,
        idempotency_key   =>
          join( q{:}, $input->{action}, $input->{idempotency} ),
        payload   => $input->{payload} || {},
        timestamp => $input->{created_at},
    );
    my %audit = (
        action         => $input->{action},
        schema_version => $SCHEMA_VERSION,
        actor_id       => $input->{actor_id},
        target_type    => $USER_AGGREGATE,
        target_id      => column_of( $request, 'subject_user_id' ),
        correlation_id => $correlation_id,
        previous_hash  => undef,
        record_hash    => q{},
        metadata       => {
            export_request_id => column_of( $request, 'export_request_id' ),
            %{ $input->{metadata} || {} },
        },
        created_at => $input->{created_at},
    );

    return ( \%event, \%audit );
}

sub _request_payload ($request) {
    return {
        export_request_id => column_of( $request, 'export_request_id' ),
        export_type       => column_of( $request, 'export_type' ),
        format            => column_of( $request, 'format' ),
        status            => column_of( $request, 'status' ),
        subject_user_id   => column_of( $request, 'subject_user_id' ),
    };
}

sub _request_hash ($request) {
    return {
        export_request_id => column_of( $request, 'export_request_id' ),
        requester_user_id => column_of( $request, 'requester_user_id' ),
        subject_user_id   => column_of( $request, 'subject_user_id' ),
        export_type       => column_of( $request, 'export_type' ),
        format            => column_of( $request, 'format' ),
        status            => column_of( $request, 'status' ),
        created_at        => column_of( $request, 'created_at' ),
        finished_at       => column_of( $request, 'finished_at' ),
        manifest          => _manifest($request) || {},
    };
}

# The manifest decoded: get_column returns the jsonb column's text, so an
# already completed export came back with its bundle as one string.
sub _manifest ($request) {
    if ( ref $request ne 'HASH' && $request->can('get_inflated_column') ) {
        return $request->get_inflated_column('manifest');
    }

    return column_of( $request, 'manifest' );
}

1;

__END__

=head1 NAME

GPForum::Service::Portability::ExportBundleBuilder - A member's data export: the request, the bundle and its completion.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $exports = GPForum::Service::Portability::ExportBundleBuilder->new(
        schema => $schema,
    );

    my $request = $exports->request_user_export($user_id);

    # Later, in the worker:
    my $done =
      $exports->complete_user_export( $request->{export_request_id} );
    # $done->{status} is 'completed'; $done->{manifest}{counts}{posts}

=head1 DESCRIPTION

Serves a member's right to a copy of their data. A request is an
C<export_requests> row in the C<pending> state, recorded with a
C<privacy.export_requested> event and audit entry. Asking again while one
is pending returns the pending one, and records its event first if an
earlier attempt left it out.

Completing gathers the bundle: the profile (username, display name,
normalized email, status and preferences), every post the member wrote with
its body source, their attachments' metadata, notifications, subscriptions
and notification preferences. The bundle is stored as the request's
manifest together with its counts, the request is marked C<completed>, and
a C<privacy.export_completed> event and audit entry are recorded, whose
payload carries the safe manifest: the counts, not the data. A table the
schema lacks is exported as an empty list.

Post bodies are read C<body_batch_size> post ids per statement: libpq
refuses more than 65,535 parameters, and binding one per post of a
long-time member of a large forum made the whole export fail.

=head1 SUBROUTINES/METHODS

=head2 create_request

Takes a hash reference with C<requester_user_id>, C<subject_user_id>,
C<export_type> and C<format> (default C<json>). In a transaction, returns
the request as a hash (C<export_request_id>, requester, subject, type,
format, C<status>, C<created_at>, C<finished_at>, C<manifest>): the pending
one for the same requester, subject, type and format if there is one, a new
one otherwise. A collision on the minted id is retried once; losing the race
to another pending request returns that one.

=head2 create_request_p

L</create_request> as a promise, with an optional query context and an
optional transaction call layer last: one transaction on the worker's
pooled asynchronous connections, or a savepoint of the given one.

=head2 request_user_export_p

L</request_user_export> as a promise, with an optional query context and an
optional transaction call layer last.

=head2 complete_user_export_p

L</complete_user_export> as a promise, with an optional query context and
an optional transaction call layer last: the request, the parts read in one
statement, the stored bundle and its event and audit entry commit together
on the pooled asynchronous connections, in a savepoint of the given
transaction when there is one.

=head2 request_user_export

Takes a user id. Calls C<create_request> for the user about themselves,
type C<user_data>, format C<json>.

=head2 complete_user_export

Takes an export request id and optional bundle parts. In a transaction,
builds the bundle from the parts given or from the database, stores it and
marks the request completed. Returns the request hash with C<status>
C<completed>, C<finished_at> and the stored manifest (the safe manifest plus
the bundle's profile, posts, attachments, notifications, subscriptions and
preferences). An already completed request is returned as stored, and an
unknown id gives undef.

=head2 build_user_bundle

Takes a subject user id and a hash reference of parts. Returns the bundle:
C<subject_user_id>, C<generated_at> (now), C<format> C<json>, C<profile> (a
hash) and C<posts>, C<attachments>, C<notifications>, C<subscriptions> and
C<preferences> (array references, empty when not in the parts). Reads
nothing.

=head2 safe_manifest

Takes a bundle. Returns the summary that may travel in events:
C<subject_user_id>, C<generated_at>, C<format> and C<counts> of each list.

=head1 DIAGNOSTICS

An unknown request in C<complete_user_export> gives undef. An insert error
other than the two collisions above, or a collision whose winning request
cannot be found, is rethrown with C<croak>; other database errors propagate.
Either rolls the transaction back.

=head1 CONFIGURATION AND ENVIRONMENT

C<body_batch_size>, the post ids bound per body query (default 10,000).

=head1 DEPENDENCIES

L<GPForum::Infrastructure::Row>, L<GPForum::Infrastructure::EventRecorder>,
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
