# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Portability::ExportBundleBuilder;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -signatures, -async_await;
use v5.40;

use GPForum::Infrastructure::EventRecorder;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Infrastructure::UniqueConflict;
use GPForum::X::Conflict;
use GPForum::X::Unavailable;
use GPForum::Service::Clock;

has functions => \&GPForum::Infrastructure::SqlFunction::for_service;

our $VERSION = '0.001';

const my $FORMAT_JSON        => 'json';
const my $SCHEMA_VERSION     => 1;
const my $USER_AGGREGATE     => 'user';
const my $STATUS_COMPLETED   => 'completed';
const my $ID_CONSTRAINT      => 'export_requests_pkey';
const my $PENDING_CONSTRAINT => 'idx_export_requests_pending_unique';

has clock      => sub { return GPForum::Service::Clock->new; };
has id_service => sub {
    require GPForum::Infrastructure::Id;
    return GPForum::Infrastructure::Id->new;
};
__PACKAGE__->requires(qw(schema));

# Each operation is written once, as its promise method (ADR 0177): one
# transaction on its call layer, the insert in its savepoints.
GPForum::Infrastructure::SqlFunction->blocking_twins(
    qw(create_request request_user_export complete_user_export));

# One transaction on the worker's pooled asynchronous connections, or a
# savepoint of the transaction $functions belongs to.
async sub create_request_p ( $self, $input, $context = undef,
    $functions = undef )
{
    $functions //= $self->_functions;
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

    return await GPForum::Infrastructure::UniqueConflict->once_more_p( $db,
        $insert );
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

# One transaction on the worker's pooled asynchronous connections, or a
# savepoint of the transaction $functions belongs to: the request, its
# parts in one statement (api.portability_export_parts), the stored bundle
# and its events.
async sub complete_user_export_p (
    $self, $export_request_id,
    $parts     = undef,
    $context   = undef,
    $functions = undef
  )
{
    $functions //= $self->_functions;
    return await $functions->transaction_p(
        async sub ($scope) {
            return await $self->_complete_request_p( $scope,
                $export_request_id, $parts, $context );
        },
        $context
    );
}

async sub _complete_request_p ( $self, $db, $export_request_id, $parts,
    $context )
{
    my $row = await $db->row_p( 'privacy_find',
        _find_request($export_request_id), $context );
    my $request = $row ? $row->{document} : undef;
    return undef                   if !$request;
    return _request_hash($request) if _is_completed($request);

    my $subject_user_id = $request->{subject_user_id};
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
    return ( $request->{status} || q{} ) eq $STATUS_COMPLETED;
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
    my $request_id = $request->{export_request_id};
    return {
        action   => 'privacy.export_completed',
        actor_id => $request->{requester_user_id},
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
        aggregate_id      => $request->{subject_user_id},
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
        target_id      => $request->{subject_user_id},
        correlation_id => $correlation_id,
        previous_hash  => undef,
        record_hash    => q{},
        metadata       => {
            export_request_id => $request->{export_request_id},
            %{ $input->{metadata} || {} },
        },
        created_at => $input->{created_at},
    );

    return ( \%event, \%audit );
}

sub _request_payload ($request) {
    return {
        export_request_id => $request->{export_request_id},
        export_type       => $request->{export_type},
        format            => $request->{format},
        status            => $request->{status},
        subject_user_id   => $request->{subject_user_id},
    };
}

sub _request_hash ($request) {
    return {
        export_request_id => $request->{export_request_id},
        requester_user_id => $request->{requester_user_id},
        subject_user_id   => $request->{subject_user_id},
        export_type       => $request->{export_type},
        format            => $request->{format},
        status            => $request->{status},
        created_at        => $request->{created_at},
        finished_at       => $request->{finished_at},
        manifest          => $request->{manifest} || {},
    };
}

sub _functions ($self) {
    return $self->functions // GPForum::X::Unavailable->throw(
        message => 'data exports need the PostgreSQL function layer' );
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

Completing gathers the bundle: every part
C<api.portability_export_parts> reads for the member in one statement,
bound by the member alone however many posts they wrote -- the profile
(username, display name, normalized email, status and preferences), every
post with its body source, their attachments' metadata, notifications,
subscriptions, preferences and the other parts L</build_user_bundle>
names. The bundle is stored as the request's manifest together with its
counts, the request is marked C<completed>, and a
C<privacy.export_completed> event and audit entry are recorded, whose
payload carries the safe manifest: the counts, not the data.

Each operation is written once, as its promise method, on the call layer
(ADR 0177); the blocking methods are that body settled on the blocking
layer.

=head1 SUBROUTINES/METHODS

=head2 create_request_p

Takes a hash reference with C<requester_user_id>, C<subject_user_id>,
C<export_type> and C<format> (default C<json>), then an optional query
context and an optional transaction call layer. In one transaction on the
worker's pooled asynchronous connections, or a savepoint of the given one,
answers the request as a hash (C<export_request_id>, requester, subject,
type, format, C<status>, C<created_at>, C<finished_at>, C<manifest>): the
pending one for the same requester, subject, type and format if there is
one, a new one otherwise. A collision on the minted id is retried once;
losing the race to another pending request answers that one.

C<create_request> is its blocking twin, with the input alone.

=head2 request_user_export_p

Takes a user id, then an optional query context and an optional
transaction call layer. L</create_request_p> for the user about
themselves, type C<user_data>, format C<json>.

C<request_user_export> is its blocking twin, with the user id alone.

=head2 complete_user_export_p

Takes an export request id and optional bundle parts, then an optional
query context and an optional transaction call layer. In one transaction,
builds the bundle from the parts given or from the database, stores it and
marks the request completed, its event and audit entry committing with it.
Answers the request hash with C<status> C<completed>, C<finished_at> and
the stored manifest (the safe manifest plus every part of the bundle). An
already completed request is answered as stored, and an unknown id with
undef.

C<complete_user_export> is its blocking twin, with the id and the parts.

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

An unknown request in C<complete_user_export_p> answers undef. An insert
error other than the two collisions above, or a collision whose winning
request cannot be found, is rethrown with C<croak>; other database errors
propagate. Either rolls the transaction back. Without the PostgreSQL
function layer every operation throws L<GPForum::X::Unavailable>.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Infrastructure::SqlFunction>,
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
