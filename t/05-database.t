# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use Mojo::File qw(path);
use Test::Exception;
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Config;
use GPForum::Migration::Plan;
use GPForum::Migration::Runner;
use GPForum::Schema;
use GPForum::Test::MigrationSchema;

our $VERSION = '0.001';

const my $EXPECTED_TESTS => 345;

# Derived from the directory instead of hardcoded: a literal turns every new
# migration into a spurious failure, which trains people to bump the number
# without reading the assertion. The checks below still prove the runner sees
# every migration file, in order, with its checksum.
const my $EXPECTED_MIGRATIONS =>
  scalar @{ GPForum::Migration::Plan->new->files };

# The runner sends each migration once, its schema_versions row inside its
# transaction. Derived so it stays exact without breaking every time a
# migration is added.
const my $EXPECTED_RUNNER_EXECUTIONS => $EXPECTED_MIGRATIONS;

# The 1.0 baseline (ADR 0150): its first and last versions, and its files.
const my $BASELINE_FIRST => q{1000};
const my $BASELINE_LAST  => 1_023;
const my $BASELINE_FILES => 24;

# The order PostReader pages a thread in, as the hot-path index spells it.
const my $POST_READER_ORDER => qr/thread_id, [ ] "position", [ ] post_id/msx;

plan tests => $EXPECTED_TESTS;

my $schema                         = GPForum::Schema->clone;
my $source                         = $schema->source('SchemaVersion');
my $event_source                   = $schema->source('EventLog');
my $event_idempotency_source       = $schema->source('EventIdempotencyKey');
my $audit_source                   = $schema->source('AuditLog');
my $outbox_source                  = $schema->source('OutboxMessage');
my $dead_letter_source             = $schema->source('DeadLetter');
my $notification_source            = $schema->source('Notification');
my $notification_inbox_source      = $schema->source('NotificationInbox');
my $notification_preference_source = $schema->source('NotificationPreference');
my $notification_read_source       = $schema->source('NotificationRead');
my $thread_read_state_source       = $schema->source('ThreadReadState');
my $read_marker_delta_source       = $schema->source('UserReadMarkerDelta');
my $attachment_source              = $schema->source('Attachment');
my $attachment_link_source         = $schema->source('AttachmentLink');
my $attachment_variant_source      = $schema->source('AttachmentVariant');
my $deletion_request_source        = $schema->source('DeletionRequest');
my $deletion_action_source         = $schema->source('DeletionAction');
my $erasure_job_source             = $schema->source('ErasureJob');
my $retention_hold_source          = $schema->source('RetentionHold');
my $bookmark_source                = $schema->source('Bookmark');
my $mention_source                 = $schema->source('Mention');
my $reputation_event_source        = $schema->source('ReputationEvent');
my $trust_score_snapshot_source    = $schema->source('TrustScoreSnapshot');
my $user_feed_item_source          = $schema->source('UserFeedItem');
my $report_source                  = $schema->source('Report');
my $moderation_action_source       = $schema->source('ModerationAction');
my $suspension_source              = $schema->source('Suspension');
my $role_source                    = $schema->source('Role');
my $permission_source              = $schema->source('Permission');
my $role_permission_source         = $schema->source('RolePermission');
my $role_binding_source            = $schema->source('RoleBinding');
my $projection_generation_source   = $schema->source('ProjectionGeneration');
my $export_request_source          = $schema->source('ExportRequest');
my $rate_limit_bucket_source       = $schema->source('RateLimitBucket');

is( $source->from, 'schema_versions', 'schema version source maps table' );
is_deeply( [ $source->primary_columns ],
    ['version'], 'schema version primary key is explicit' );
ok( $source->has_column('checksum'), 'schema version records checksums' );
ok(
    $source->has_column('applied_at'),
    'schema version records application time'
);

is( $event_source->from, 'event_log', 'event source maps event log table' );
is_deeply(
    [ $event_source->primary_columns ],
    [ 'event_id', 'created_at' ],
    'event log primary key is partition-safe'
);
ok( $event_source->has_column('event_type'), 'event log stores event type' );
ok(
    $event_source->has_column('schema_version'),
    'event log stores schema version'
);
ok(
    $event_source->has_column('correlation_id'),
    'event log stores correlation id'
);
ok( $event_source->has_column('causation_id'),
    'event log stores causation id' );
ok(
    $event_source->has_column('aggregate_version'),
    'event log stores aggregate stream version'
);
ok(
    $event_source->has_column('idempotency_key'),
    'event log stores idempotency key'
);
ok( $event_source->has_column('payload'), 'event log stores payload' );

is( $event_idempotency_source->from,
    'event_idempotency_keys', 'event idempotency source maps keys table' );
is_deeply( [ $event_idempotency_source->primary_columns ],
    ['idempotency_key'], 'event idempotency primary key is the worker key' );
ok(
    $event_idempotency_source->has_column('event_id'),
    'event idempotency stores the source event id'
);

is( $audit_source->from, 'audit_log', 'audit source maps audit log table' );
is_deeply(
    [ $audit_source->primary_columns ],
    [ 'audit_id', 'created_at' ],
    'audit log primary key is partition-safe'
);
ok( $audit_source->has_column('action'), 'audit log stores action' );
ok(
    $audit_source->has_column('schema_version'),
    'audit log stores schema version'
);
ok(
    $audit_source->has_column('correlation_id'),
    'audit log stores correlation id'
);
ok(
    $audit_source->has_column('previous_hash'),
    'audit log supports hash chain previous hash'
);
ok(
    $audit_source->has_column('record_hash'),
    'audit log supports hash chain record hash'
);
ok( $audit_source->has_column('metadata'), 'audit log stores metadata' );

is( $outbox_source->from, 'outbox_messages',
    'outbox source maps outbox messages table' );
is_deeply( [ $outbox_source->primary_columns ],
    ['outbox_id'], 'outbox primary key is explicit' );
ok( $outbox_source->has_column('event_id'), 'outbox links to event id' );
ok( $outbox_source->has_column('queue'),    'outbox stores queue' );
ok( $outbox_source->has_column('job_type'), 'outbox stores job type' );
ok( $outbox_source->has_column('next_attempt_at'),
    'outbox stores retry schedule' );
ok(
    $outbox_source->has_column('failure_type'),
    'outbox stores classified failure type'
);

is( $dead_letter_source->from, 'dead_letters',
    'dead letter source maps dead letters table' );
is_deeply( [ $dead_letter_source->primary_columns ],
    ['dead_letter_id'], 'dead letter primary key is explicit' );
ok( $dead_letter_source->has_column('source_table'),
    'dead letter stores source table' );
ok( $dead_letter_source->has_column('source_id'),
    'dead letter stores source id' );
is_deeply(
    [
        $dead_letter_source->unique_constraint_columns(
            'idx_dead_letters_source_unique')
    ],
    [qw(source_table source_id)],
    'dead letter is unique per source table and source id'
);
ok( $dead_letter_source->has_column('error_class'),
    'dead letter stores error class' );
ok( $dead_letter_source->has_column('retry_count'),
    'dead letter stores retry count' );
ok(
    $dead_letter_source->has_column('failure_type'),
    'dead letter stores classified failure type'
);

is( $notification_source->from,
    'notifications', 'notification source maps notifications table' );
is_deeply(
    [ $notification_source->primary_columns ],
    [ 'notification_id', 'created_at' ],
    'notification primary key is partition-safe'
);
ok( $notification_source->has_column('payload'),
    'notification stores payload' );
ok( $notification_source->has_relationship('recipient'),
    'notification belongs to recipient' );
ok(
    $notification_source->has_relationship('inbox_entries'),
    'notification has inbox projection entries'
);

is( $notification_read_source->from,
    'notification_reads', 'notification read source maps reads table' );
is_deeply(
    [ $notification_read_source->primary_columns ],
    [ 'notification_id', 'recipient_user_id' ],
    'notification read primary key is explicit'
);
ok( $notification_read_source->has_column('read_at'),
    'notification read stores timestamp' );

is( $thread_read_state_source->from,
    'thread_read_state', 'thread read state source maps read markers' );
is_deeply(
    [ $thread_read_state_source->primary_columns ],
    [ 'user_id', 'thread_id' ],
    'thread read state primary key is explicit'
);
ok( $thread_read_state_source->has_column('last_read_position'),
    'thread read state stores last read position' );
ok(
    $thread_read_state_source->has_column('last_read_at'),
    'thread read state stores read timestamp'
);
ok( $thread_read_state_source->has_relationship('thread'),
    'thread read state belongs to thread' );

is( $read_marker_delta_source->from,
    'user_read_marker_deltas', 'read marker delta source maps delta table' );
is_deeply(
    [ $read_marker_delta_source->primary_columns ],
    [ 'user_id', 'thread_id' ],
    'read marker delta primary key is explicit'
);
ok( $read_marker_delta_source->has_column('last_read_position'),
    'read marker delta stores last read position' );
ok(
    $read_marker_delta_source->has_column('last_read_at'),
    'read marker delta stores read timestamp'
);
ok( $read_marker_delta_source->has_relationship('thread'),
    'read marker delta belongs to thread' );

is( $notification_inbox_source->from,
    'notification_inbox', 'notification inbox source maps inbox table' );
is_deeply(
    [ $notification_inbox_source->primary_columns ],
    [ 'recipient_user_id', 'notification_id' ],
    'notification inbox primary key is explicit'
);
ok( $notification_inbox_source->has_column('rank_score'),
    'notification inbox stores rank score' );
ok(
    $notification_inbox_source->has_relationship('notification'),
    'notification inbox belongs to notification payload'
);

is( $notification_preference_source->from,
    'notification_preferences',
    'notification preference source maps preferences table' );
is_deeply(
    [ $notification_preference_source->primary_columns ],
    [ 'user_id', 'channel' ],
    'notification preference primary key is explicit'
);
ok(
    $notification_preference_source->has_column('digest_frequency'),
    'notification preference stores digest frequency'
);
ok( $notification_preference_source->has_relationship('user'),
    'notification preference belongs to user' );

is( $attachment_source->from, 'attachments', 'attachment source maps table' );
is_deeply( [ $attachment_source->primary_columns ],
    ['attachment_id'], 'attachment primary key is explicit' );
ok( $attachment_source->has_column('owner_user_id'),
    'attachment stores owner' );
ok( $attachment_source->has_column('object_key'),
    'attachment stores object key' );
is_deeply(
    [
        $attachment_source->unique_constraint_columns(
            'attachments_object_key_key')
    ],
    ['object_key'],
    'attachment object key is unique'
);
ok(
    $attachment_source->has_column('state'),
    'attachment stores lifecycle state'
);
ok( $attachment_source->has_column('scan_status'),
    'attachment stores scan status' );
is( $attachment_link_source->from,
    'attachment_links', 'attachment link source maps table' );
is_deeply( [ $attachment_link_source->primary_columns ],
    ['attachment_link_id'], 'attachment link primary key is explicit' );
ok( $attachment_link_source->has_column('target_type'),
    'attachment link stores target type' );
ok( $attachment_link_source->has_column('target_id'),
    'attachment link stores target id' );
is( $attachment_variant_source->from,
    'attachment_variants', 'attachment variant source maps table' );
is_deeply( [ $attachment_variant_source->primary_columns ],
    ['attachment_variant_id'], 'attachment variant primary key is explicit' );
ok( $attachment_variant_source->has_column('variant_type'),
    'attachment variant stores variant type' );
ok( $attachment_variant_source->has_column('object_key'),
    'attachment variant stores object key' );
is_deeply(
    [
        $attachment_variant_source->unique_constraint_columns(
            'attachment_variants_object_key_key')
    ],
    ['object_key'],
    'attachment variant object key is unique'
);

is( $deletion_request_source->from,
    'deletion_requests', 'deletion request source maps table' );
is_deeply( [ $deletion_request_source->primary_columns ],
    ['deletion_request_id'], 'deletion request primary key is explicit' );
ok( $deletion_request_source->has_column('request_type'),
    'deletion request stores request type' );
ok( $deletion_request_source->has_relationship('actions'),
    'deletion request has actions' );
ok( $deletion_request_source->has_relationship('erasure_jobs'),
    'deletion request has erasure jobs' );

is( $deletion_action_source->from,
    'deletion_actions', 'deletion action source maps table' );
is_deeply( [ $deletion_action_source->primary_columns ],
    ['deletion_action_id'], 'deletion action primary key is explicit' );
ok( $deletion_action_source->has_column('action_type'),
    'deletion action stores action type' );
ok( $deletion_action_source->has_relationship('deletion_request'),
    'deletion action belongs to deletion request' );

is( $erasure_job_source->from,
    'erasure_jobs', 'erasure job source maps table' );
is_deeply( [ $erasure_job_source->primary_columns ],
    ['erasure_job_id'], 'erasure job primary key is explicit' );
ok( $erasure_job_source->has_column('last_error'),
    'erasure job stores last error' );
is_deeply(
    [
        $erasure_job_source->unique_constraint_columns(
            'idx_erasure_jobs_request_unique')
    ],
    ['deletion_request_id'],
    'erasure job is unique per deletion request'
);
ok( $erasure_job_source->has_relationship('deletion_request'),
    'erasure job belongs to deletion request' );

is( $retention_hold_source->from,
    'retention_holds', 'retention hold source maps table' );
is_deeply( [ $retention_hold_source->primary_columns ],
    ['retention_hold_id'], 'retention hold primary key is explicit' );
ok(
    $retention_hold_source->has_column('ends_at'),
    'retention hold stores end timestamp'
);

is( $bookmark_source->from, 'bookmarks', 'bookmark source maps table' );
is_deeply( [ $bookmark_source->primary_columns ],
    ['bookmark_id'], 'bookmark primary key is explicit' );
ok( $bookmark_source->has_column('note'),       'bookmark stores note' );
ok( $bookmark_source->has_relationship('user'), 'bookmark belongs to user' );

is( $mention_source->from, 'mentions', 'mention source maps table' );
is_deeply( [ $mention_source->primary_columns ],
    ['mention_id'], 'mention primary key is explicit' );
ok( $mention_source->has_column('mentioned_username'),
    'mention stores username snapshot' );
ok( $mention_source->has_relationship('actor'), 'mention belongs to actor' );
ok( $mention_source->has_relationship('mentioned_user'),
    'mention belongs to mentioned user' );

is( $reputation_event_source->from,
    'reputation_events', 'reputation event source maps table' );
is_deeply( [ $reputation_event_source->primary_columns ],
    ['reputation_event_id'], 'reputation event primary key is explicit' );
ok( $reputation_event_source->has_column('delta'),
    'reputation event stores delta' );
is_deeply(
    [
        $reputation_event_source->unique_constraint_columns(
            'idx_reputation_events_source_unique')
    ],
    [ 'user_id', 'source_type', 'source_id' ],
    'reputation event is unique per user source'
);
ok( $reputation_event_source->has_relationship('user'),
    'reputation event belongs to user' );

is( $trust_score_snapshot_source->from,
    'trust_score_snapshots', 'trust score snapshot source maps table' );
is_deeply( [ $trust_score_snapshot_source->primary_columns ],
    ['user_id'], 'trust score snapshot primary key is user' );
ok( $trust_score_snapshot_source->has_column('trust_level'),
    'trust score snapshot stores trust level' );
ok( $trust_score_snapshot_source->has_relationship('user'),
    'trust score snapshot belongs to user' );

is( $user_feed_item_source->from,
    'user_feed_items', 'user feed item source maps table' );
is_deeply(
    [ $user_feed_item_source->primary_columns ],
    [ 'user_id', 'item_type', 'item_id' ],
    'user feed item primary key is explicit'
);
ok( $user_feed_item_source->has_column('rank_score'),
    'user feed item stores rank score' );
ok( $user_feed_item_source->has_column('permission_version'),
    'user feed item stores permission version' );
ok( $user_feed_item_source->has_relationship('user'),
    'user feed item belongs to user' );

is( $report_source->from, 'reports', 'report source maps table' );
is_deeply( [ $report_source->primary_columns ],
    ['report_id'], 'report primary key is explicit' );
ok( $report_source->has_column('status'),     'report stores status' );
ok( $report_source->has_column('resolution'), 'report stores resolution' );
ok( $report_source->has_relationship('reporter'),
    'report belongs to reporter' );

is( $moderation_action_source->from,
    'moderation_actions', 'moderation action source maps table' );
is_deeply( [ $moderation_action_source->primary_columns ],
    ['moderation_action_id'], 'moderation action primary key is explicit' );
ok( $moderation_action_source->has_column('action_type'),
    'moderation action stores action type' );
ok( $moderation_action_source->has_column('command_id'),
    'moderation action stores command id' );
is_deeply(
    [
        $moderation_action_source->unique_constraint_columns(
            'idx_moderation_actions_command_id')
    ],
    ['command_id'],
    'moderation action command id is unique'
);
ok( $moderation_action_source->has_column('reversed_at'),
    'moderation action supports reversal' );
ok( $moderation_action_source->has_relationship('actor'),
    'moderation action belongs to actor' );

is( $suspension_source->from, 'suspensions', 'suspension source maps table' );
is_deeply( [ $suspension_source->primary_columns ],
    ['suspension_id'], 'suspension primary key is explicit' );
ok( $suspension_source->has_column('valid_from'),
    'suspension stores valid_from' );
ok( $suspension_source->has_column('revoked_at'),
    'suspension supports revocation' );
ok( $suspension_source->has_relationship('user'),
    'suspension belongs to user' );

is( $role_source->from, 'roles', 'role source maps table' );
is_deeply( [ $role_source->primary_columns ],
    ['role_id'], 'role primary key is explicit' );
ok( $role_source->has_column('name'), 'role stores name' );
ok( $role_source->has_relationship('role_permissions'),
    'role has role permissions' );
ok( $role_source->has_relationship('role_bindings'), 'role has role bindings' );

is( $permission_source->from, 'permissions', 'permission source maps table' );
is_deeply( [ $permission_source->primary_columns ],
    ['permission_id'], 'permission primary key is explicit' );
ok( $permission_source->has_column('resource_type'),
    'permission stores resource type' );
ok( $permission_source->has_column('action'), 'permission stores action' );
ok( $permission_source->has_relationship('role_permissions'),
    'permission has role permissions' );

is( $role_permission_source->from,
    'role_permissions', 'role permission source maps table' );
is_deeply(
    [ $role_permission_source->primary_columns ],
    [ 'role_id', 'permission_id' ],
    'role permission primary key is explicit'
);
ok( $role_permission_source->has_relationship('role'),
    'role permission belongs to role' );
ok( $role_permission_source->has_relationship('permission'),
    'role permission belongs to permission' );

is( $role_binding_source->from,
    'role_bindings', 'role binding source maps table' );
is_deeply( [ $role_binding_source->primary_columns ],
    ['binding_id'], 'role binding primary key is explicit' );
ok( $role_binding_source->has_column('created_by_user_id'),
    'role binding stores creator' );
ok( $role_binding_source->has_relationship('user'),
    'role binding belongs to user' );
ok( $role_binding_source->has_relationship('role'),
    'role binding belongs to role' );
ok(
    !{ $role_binding_source->unique_constraints }
    ->{idx_role_bindings_active_unique},
    'role binding scope uniqueness among active rows is left to the database'
);

is( $projection_generation_source->from,
    'projection_generations',
    'projection generation source maps projection generations table' );
is_deeply( [ $projection_generation_source->primary_columns ],
    ['generation_id'], 'projection generation primary key is explicit' );
ok(
    $projection_generation_source->has_column('is_active'),
    'projection generation stores active marker'
);
is_deeply(
    [
        $projection_generation_source->unique_constraint_columns(
            'idx_projection_generations_source_unique')
    ],
    [qw(projection_name built_from_event_id)],
    'projection generation is unique per projection and source event'
);

is( $export_request_source->from,
    'export_requests', 'export request source maps table' );
is_deeply( [ $export_request_source->primary_columns ],
    ['export_request_id'], 'export request primary key is explicit' );
ok( $export_request_source->has_column('export_type'),
    'export request stores export type' );
ok( $export_request_source->has_relationship('requester'),
    'export request belongs to requester' );
ok( $export_request_source->has_relationship('subject'),
    'export request belongs to subject' );

my $user_source           = $schema->source('User');
my $credential_source     = $schema->source('Credential');
my $identity_token_source = $schema->source('IdentityToken');
my $session_source        = $schema->source('Session');
my $space_source          = $schema->source('Space');
my $subscription_source   = $schema->source('Subscription');
my $category_source       = $schema->source('Category');
my $thread_source         = $schema->source('Thread');
my $post_source           = $schema->source('Post');
my $body_source           = $schema->source('PostBody');
my $revision_source       = $schema->source('PostRevision');
my $counter_source        = $schema->source('ThreadCounter');
my $search_source         = $schema->source('SearchDocument');

is( $user_source->from, 'users', 'user source maps users table' );
is_deeply( [ $user_source->primary_columns ],
    ['id'], 'user primary key is explicit' );
ok( $user_source->has_column('email_normalized'),
    'user stores normalized email' );
ok(
    $user_source->has_column('email_verified_at'),
    'user supports email verification placeholder'
);
ok( $user_source->has_column('version'), 'user supports optimistic locking' );
ok(
    $user_source->has_column('permission_version'),
    'user supports permission cache invalidation'
);
ok( $user_source->has_column('preferred_locale'),
    'user stores preferred UI locale' );
ok( $user_source->has_column('preferred_theme'),
    'user stores preferred UI theme' );
ok(
    $user_source->has_relationship('credentials'),
    'user has credentials relationship'
);
ok( $user_source->has_relationship('sessions'),
    'user has sessions relationship' );
ok(
    $user_source->has_relationship('identity_tokens'),
    'user has identity token relationship'
);
ok(
    $user_source->has_relationship('thread_read_states'),
    'user has thread read states relationship'
);
ok(
    $user_source->has_relationship('read_marker_deltas'),
    'user has read marker delta relationship'
);
ok(
    $user_source->has_relationship('bookmarks'),
    'user has bookmarks relationship'
);
ok(
    $user_source->has_relationship('subscriptions'),
    'user has subscriptions relationship'
);
ok(
    $user_source->has_relationship('authored_mentions'),
    'user has authored mentions relationship'
);
ok(
    $user_source->has_relationship('mentions'),
    'user has received mentions relationship'
);

is( $credential_source->from, 'credentials',
    'credential source maps credentials table' );
ok(
    $credential_source->has_column('secret_hash'),
    'credential stores only secret hash'
);
ok( $credential_source->has_relationship('user'),
    'credential belongs to user' );
ok(
    !{ $credential_source->unique_constraints }
    ->{idx_credentials_active_password_unique},
    'one active password per user is left to the database'
);

is( $identity_token_source->from,
    'identity_tokens', 'identity token source maps identity_tokens table' );
is_deeply( [ $identity_token_source->primary_columns ],
    ['token_id'], 'identity token primary key is explicit' );
ok(
    $identity_token_source->has_column('token_hash'),
    'identity token stores only token hash'
);
ok(
    $identity_token_source->has_column('email_normalized'),
    'identity token stores pending email target'
);
ok(
    $identity_token_source->has_column('used_at'),
    'identity token supports one-time use'
);
is_deeply(
    [
        $identity_token_source->unique_constraint_columns(
            'identity_tokens_hash_key')
    ],
    ['token_hash'],
    'identity token hash is unique'
);
ok( $identity_token_source->has_relationship('user'),
    'identity token belongs to user' );

is( $session_source->from, 'sessions', 'session source maps sessions table' );
is_deeply( [ $session_source->primary_columns ],
    ['session_id'], 'session primary key is explicit' );
ok( $session_source->has_column('session_hash'), 'session stores token hash' );
is_deeply(
    [ $session_source->unique_constraint_columns('sessions_session_hash_key') ],
    ['session_hash'],
    'session hash is unique'
);
ok( $session_source->has_column('revoked_at'), 'session supports revocation' );
ok( $session_source->has_relationship('user'), 'session belongs to user' );

is( $rate_limit_bucket_source->from,
    'rate_limit_buckets', 'rate limit source maps buckets table' );
is_deeply(
    [ $rate_limit_bucket_source->primary_columns ],
    [qw(scope actor_hash action window_started_at)],
    'rate limit bucket primary key is scoped by window'
);
ok( $rate_limit_bucket_source->has_column('observed_count'),
    'rate limit bucket stores observed count' );
ok( $rate_limit_bucket_source->has_column('blocked_count'),
    'rate limit bucket stores blocked count' );
ok( $rate_limit_bucket_source->has_column('expires_at'),
    'rate limit bucket stores expiry' );

is( $space_source->from, 'spaces', 'space source maps spaces table' );
is_deeply( [ $space_source->primary_columns ],
    ['space_id'], 'space primary key is explicit' );
ok(
    $space_source->has_relationship('categories'),
    'space has categories relationship'
);

is( $subscription_source->from,
    'subscriptions', 'subscription source maps subscriptions table' );
is_deeply( [ $subscription_source->primary_columns ],
    ['subscription_id'], 'subscription primary key is explicit' );
ok( $subscription_source->has_column('preference'),
    'subscription stores preference' );
ok( $subscription_source->has_relationship('user'),
    'subscription belongs to user' );

is( $category_source->from, 'categories',
    'category source maps categories table' );
is_deeply( [ $category_source->primary_columns ],
    ['category_id'], 'category primary key is explicit' );
ok( $category_source->has_relationship('space'), 'category belongs to space' );
ok(
    $category_source->has_relationship('threads'),
    'category has threads relationship'
);

is( $thread_source->from, 'threads', 'thread source maps threads table' );
is_deeply( [ $thread_source->primary_columns ],
    ['thread_id'], 'thread primary key is explicit' );
ok( $thread_source->has_column('visibility_version'),
    'thread stores visibility version' );
ok( $thread_source->has_column('permission_version'),
    'thread stores permission version' );
ok( $thread_source->has_relationship('category'),
    'thread belongs to category' );
ok( $thread_source->has_relationship('author'), 'thread belongs to author' );
ok( $thread_source->has_relationship('posts'),
    'thread has posts relationship' );
ok(
    $thread_source->has_relationship('counters'),
    'thread has counters projection relationship'
);
ok(
    $thread_source->has_relationship('read_states'),
    'thread has read states relationship'
);
ok(
    $thread_source->has_relationship('read_marker_deltas'),
    'thread has read marker delta relationship'
);

is( $post_source->from, 'posts', 'post source maps posts table' );
is_deeply( [ $post_source->primary_columns ],
    ['post_id'], 'post primary key is explicit' );
ok(
    $post_source->has_column('current_body_id'),
    'post stores current body pointer'
);
ok(
    $post_source->has_column('current_revision_id'),
    'post stores current revision pointer'
);
ok( $post_source->has_column('position'), 'post stores thread position' );
is_deeply(
    [ $post_source->unique_constraint_columns('posts_thread_position_key') ],
    [qw(thread_id position)], 'post is unique per thread position' );
ok( $post_source->has_relationship('thread'),    'post belongs to thread' );
ok( $post_source->has_relationship('author'),    'post belongs to author' );
ok( $post_source->has_relationship('bodies'),    'post has bodies' );
ok( $post_source->has_relationship('revisions'), 'post has revisions' );
ok(
    $post_source->has_relationship('current_body'),
    'post has current body relationship'
);
ok(
    $post_source->has_relationship('current_revision'),
    'post has current revision relationship'
);

is( $body_source->from, 'post_bodies',
    'post body source maps post bodies table' );
is_deeply( [ $body_source->primary_columns ],
    ['body_id'], 'post body primary key is explicit' );
ok( $body_source->has_column('source_hash'), 'post body stores content hash' );
ok( $body_source->has_relationship('post'),  'post body belongs to post' );

is( $revision_source->from, 'post_revisions',
    'post revision source maps revisions table' );
is_deeply( [ $revision_source->primary_columns ],
    ['revision_id'], 'post revision primary key is explicit' );
ok( $revision_source->has_relationship('post'),
    'post revision belongs to post' );
is_deeply(
    [
        $revision_source->unique_constraint_columns(
            'post_revisions_post_revision_number_key')
    ],
    [qw(post_id revision_number)],
    'post revision is unique per post and revision number'
);
ok( $revision_source->has_relationship('body'),
    'post revision belongs to body' );
ok( $revision_source->has_relationship('editor'),
    'post revision belongs to editor' );

is( $counter_source->from, 'thread_counters',
    'thread counter source maps projection table' );
ok(
    $counter_source->has_relationship('thread'),
    'thread counter belongs to thread'
);

is( $search_source->from, 'search_documents',
    'search document source maps search projection table' );
ok(
    $search_source->has_column('search_vector'),
    'search document stores search vector'
);
ok(
    $search_source->has_column('source_version'),
    'search document stores source version'
);
ok(
    $search_source->has_column('category_id'),
    'search document stores category filter'
);
ok(
    $search_source->has_column('author_user_id'),
    'search document stores author filter'
);
ok(
    $search_source->has_column('source_created_at'),
    'search document stores source creation time'
);

my $config = GPForum::Config->from_environment(
    {
        GPFORUM_DATABASE_DSN  => 'dbi:Pg:dbname=gpforum_test',
        GPFORUM_DATABASE_USER => 'gpforum_test',
    }
);
my $connected_schema = GPForum::Schema->connect_from_config($config);

isa_ok( $connected_schema, 'GPForum::Schema' );
is(
    $connected_schema->storage->connect_info->[0],
    $config->database_connection_dsn,
    q{schema uses configured database dsn, with the startup options}
);

my $plan    = GPForum::Migration::Plan->new;
my $summary = $plan->summary;

is( scalar @{$summary}, $EXPECTED_MIGRATIONS,  'all migrations are planned' );
is( $summary->[0]->{version}, $BASELINE_FIRST, 'the baseline comes first' );
is( $summary->[0]->{description},
    'foundation', 'migration description is parsed' );

# The 1.0 baseline (ADR 0150): a file per area, numbered from 1000. Each
# table is created once, in the file of its area; the assertions below hold
# what the schema is, wherever a later migration may take it from there.
my %baseline;
for my $migration ( grep { $_->{version} <= $BASELINE_LAST } @{$summary} ) {
    $baseline{ $migration->{description} } = path( $migration->{file} )->slurp;
}
is( scalar keys %baseline, $BASELINE_FILES, 'the baseline has its files' );

my %created_in;
for my $area ( sort keys %baseline ) {
    while (
        $baseline{$area} =~ /^CREATE [ ] TABLE [ ] public[.](\w+) [ ] [(]/gmsx )
    {
        push @{ $created_in{$1} }, $area;
    }
}
is_deeply( [ grep { @{ $created_in{$_} } != 1 } sort keys %created_in ],
    [], 'every table is created once' );

# And says what it holds, where \d+ shows it: a migration that creates a
# table comments it, the baseline's and every one after.
my @uncommented;
for my $migration ( @{$summary} ) {
    my $sql = path( $migration->{file} )->slurp;
    while ( $sql =~ /^CREATE [ ] TABLE [ ] public[.](\w+) [ ] [(]/gmsx ) {
        my $table = $1;
        next
          if $sql =~ /^COMMENT [ ] ON [ ] TABLE [ ] public[.]\Q$table\E [ ]/msx;
        push @uncommented, "$migration->{version} $table";
    }
}
is_deeply( \@uncommented, [], 'every table a migration creates is commented' );

# The pieces the invariants below are made of: a table's columns, the
# options after them, and the two indexes whose columns are spelled out.
const my $BODY          => qr/[ ] [(] .*? [)] \s+/msx;
const my $FILLFACTOR_80 => qr/WITH [ ] [(]fillfactor [ ] = [ ] 80[)]/msx;
const my $FILLFACTOR_90 => qr/WITH [ ] [(]fillfactor [ ] = [ ] 90[)]/msx;
const my $ANALYSED =>
  qr/WITH [ ] [(]autovacuum_analyze_threshold [ ] = [ ] 0[)]/msx;
const my $BY_CREATED_AT =>
  qr/PARTITION [ ] BY [ ] RANGE [ ] [(]created_at[)]/msx;
const my $POST_INDEX =>
  qr/idx_posts_visible_thread_position \s+ ON [ ] public[.]posts/msx;
const my $DOCUMENTS       => qr/ON [ ] public[.]search_documents/msx;
const my $CANDIDATE_INDEX => qr/idx_search_documents_created \s+ $DOCUMENTS/msx;
const my $CANDIDATE_ORDER =>
  qr/[(]source_created_at [ ] DESC, [ ] entity_id [ ] DESC[)]/msx;

const my @SCHEMA_INVARIANTS => (
    [
        foundation => qr/CREATE [ ] TABLE [ ] public[.]schema_versions/msx,
        'the baseline creates the migration ledger first'
    ],
    [
        foundation => qr/applied_by [ ] text [ ] NOT [ ] NULL/msx,
        'the ledger records who applied each migration'
    ],
    [
        foundation => qr/execution_ms [ ] integer/msx,
        'and how long it took'
    ],
    [
        foundation => qr/CREATE [ ] EXTENSION [^;]* pg_trgm/msx,
        'the baseline installs the trigram extension search indexes use'
    ],
    [
        foundation =>
          qr/REVOKE [ ] ALL [ ] ON [ ] SCHEMA [ ] api [ ] FROM [ ] PUBLIC/msx,
        'schema api is closed to PUBLIC'
    ],
    [
        foundation =>
          qr/ALTER [ ] DEFAULT [ ] PRIVILEGES [ ] REVOKE [ ] EXECUTE/msx,
        'and so is every function the role creates'
    ],
    [
        foundation => qr/CREATE [ ] TABLE [ ] public[.]partition_registry/msx,
        'the baseline creates the partition registry'
    ],
    [
        foundation =>
          qr/CREATE [ ] TABLE [ ] public[.]endpoint_query_budgets/msx,
        'the baseline creates endpoint query budgets'
    ],
    [
        identity => qr/CREATE [ ] TABLE [ ] public[.]users/msx,
        'the identity file creates users'
    ],
    [
        identity => qr/preferred_locale [ ] text [ ] NOT [ ] NULL/msx,
        'a member keeps a preferred locale'
    ],
    [
        identity => qr/users_preferred_theme_check/msx,
        'and a theme among the supported ones'
    ],
    [
        identity => qr/public[.]sessions $BODY $FILLFACTOR_90/msx,
        'sessions leave room for their last-seen updates'
    ],
    [
        identity => qr/identity_tokens_hash_key/msx,
        'identity token hashes are unique'
    ],
    [
        identity => qr/idx_identity_tokens_open_user_type/msx,
        'one unused token per member and type'
    ],
    [
        identity => qr/email_verification/msx,
        'email verification tokens are allowed'
    ],
    [
        identity => qr/idx_credentials_active_password_unique/msx,
        'one active password per member'
    ],
    [
        identity =>
qr/revoked_at [ ] IS [ ] NULL \s+ AND [ ] type [ ] = [ ] 'password'/msx,
        'counted over the active password rows'
    ],
    [
        identity => qr/CREATE [ ] TABLE [ ] public[.]rate_limit_buckets/msx,
        'rate limits live in PostgreSQL buckets'
    ],
    [
        access => qr/created_by_user_id [ ] uuid/msx,
        'a role binding records who created it'
    ],
    [
        access => qr/idx_role_bindings_active_unique/msx,
        'one active binding per member, role and scope'
    ],
    [
        access => qr/NULLS [ ] NOT [ ] DISTINCT/msx,
        'a null resource and space counting as equal'
    ],
    [
        forum => qr/CREATE [ ] TABLE [ ] public[.]post_bodies/msx,
        'post bodies are stored apart from posts'
    ],
    [
        forum => qr/CREATE [ ] TABLE [ ] public[.]post_revisions/msx,
        'revisions are appended'
    ],
    [
        forum =>
qr/WHERE [ ] deleted_at [ ] IS [ ] NULL \s+ AND [ ] moderation_state/msx,
        'visible content has partial indexes'
    ],
    [
        forum => qr/public[.]thread_counters $BODY $FILLFACTOR_80/msx,
        'thread counters leave room for their updates'
    ],
    [
        forum => qr/visibility_version/msx,
        'threads and posts carry visibility snapshot versions'
    ],
    [
        forum => qr/idx_threads_author_public_activity/msx,
        'an author activity index serves public profiles'
    ],
    [
        forum => qr/idx_threads_public_activity/msx,
        'a public activity index serves the latest threads'
    ],
    [
        forum => qr/idx_threads_category_activity_visible_locked/msx,
        'a category index serves the thread keyset order'
    ],
    [
        forum =>
          qr/moderation_state [ ] IN [ ] [(]'visible', [ ] 'locked'[)]/msx,
        'locked threads stay readable through the partial indexes'
    ],
    [
        forum => qr/$POST_INDEX [ ] [(]$POST_READER_ORDER[)]/msx,
        'the post index matches the order PostReader pages a thread in'
    ],
    [
        forum =>
          qr/INCLUDE [ ] [(]category_id, [ ] author_user_id, [ ] title/msx,
        'the latest threads index covers the list metadata'
    ],
    [
        forum => qr/public[.]categories $BODY $ANALYSED/msx,
        'categories are analysed after any change'
    ],
    [
        forum => qr/public[.]spaces $BODY $ANALYSED/msx,
        'and so are spaces'
    ],
    [
        records => qr/public[.]event_log $BODY $BY_CREATED_AT/msx,
        'the event log is partitioned by created_at'
    ],
    [
        records => qr/public[.]audit_log $BODY $BY_CREATED_AT/msx,
        'and so is the audit log'
    ],
    [
        records => qr/PARTITION [ ] OF [ ] public[.]event_log [ ] DEFAULT/msx,
        'which have default partitions'
    ],
    [
        records => qr/USING [ ] BRIN [ ] [(]created_at[)]/msx,
        'append logs have BRIN indexes'
    ],
    [
        records => qr/aggregate_version [ ] bigint/msx,
        'events store aggregate versions'
    ],
    [
        records => qr/previous_hash [ ] text/msx,
        'the audit log links its hash chain'
    ],
    [
        records => qr/idx_audit_log_chain_tip/msx,
        'and indexes its tip'
    ],
    [
        records => qr/CREATE [ ] TABLE [ ] public[.]command_log/msx,
        'commands are logged'
    ],
    [
        records => qr/CREATE [ ] TABLE [ ] public[.]event_idempotency_keys/msx,
        'event handling is idempotent'
    ],
    [
        records => qr/next_attempt_at [ ] timestamptz/msx,
        'the outbox schedules its retries'
    ],
    [
        records => qr/failure_type [ ] text/msx,
        'and classifies its failures'
    ],
    [
        records => qr/CREATE [ ] TABLE [ ] public[.]dead_letters/msx,
        'failed deliveries are kept as dead letters'
    ],
    [
        records => qr/CREATE [ ] TABLE [ ] public[.]projection_generations/msx,
        'projections rebuild in generations'
    ],
    [
        community => qr/idx_user_feed_items_ranked/msx,
        'the ranked feed is indexed'
    ],
    [
        community => qr/idx_user_feed_items_user_created .*? INCLUDE/msx,
        'and its keyset order covers the item metadata'
    ],
    [
        community => qr/idx_reputation_events_source_unique/msx,
        'one reputation event per member and source'
    ],
    [
        community => qr/CREATE [ ] TABLE [ ] public[.]subscriptions/msx,
        'subscriptions are stored'
    ],
    [
        notifications => qr/public[.]notifications $BODY $BY_CREATED_AT/msx,
        'notifications are partitioned by created_at'
    ],
    [
        notifications =>
          qr/CREATE [ ] TABLE [ ] public[.]notification_reads/msx,
        'reads are stored apart from notifications'
    ],
    [
        notifications =>
          qr/CREATE [ ] TABLE [ ] public[.]notification_inbox/msx,
        'the inbox is a projection'
    ],
    [
        moderation => qr/idx_reports_queue/msx,
        'the report queue is indexed'
    ],
    [
        moderation => qr/idx_reports_reporter_target_open_unique/msx,
        'one open report per reporter and target'
    ],
    [
        moderation => qr/idx_moderation_actions_command_id/msx,
        'one moderation action per command'
    ],
    [
        attachments => qr/CREATE [ ] TABLE [ ] public[.]attachment_variants/msx,
        'attachments keep their variants'
    ],
    [
        search => qr/USING [ ] GIN [ ] [(]search_vector[)]/msx,
        'search vectors are indexed'
    ],
    [
        search => qr/gin_trgm_ops/msx,
        'and normalized titles by trigram'
    ],
    [
        search => qr/$CANDIDATE_INDEX [ ] $CANDIDATE_ORDER/msx,
        'search candidates are read newest first'
    ],
    [
        search => qr/source_created_at [ ] timestamptz/msx,
        'documents carry their source time'
    ],
    [
        privacy => qr/idx_erasure_jobs_request_unique/msx,
        'one erasure job per request'
    ],
    [
        privacy => qr/idx_deletion_requests_open_resource_unique/msx,
        'one open deletion per resource'
    ],
    [
        privacy => qr/idx_export_requests_pending_unique/msx,
        'one pending export per subject'
    ],
    [
        privacy => qr/idx_retention_holds_active_resource_unique/msx,
        'one active hold per resource'
    ],
);

for my $invariant (@SCHEMA_INVARIANTS) {
    my ( $area, $pattern, $name ) = @{$invariant};
    like( $baseline{$area} // q{}, $pattern, $name );
}

# The search indexes partial on permission_scope no statement states could
# never be used, and are not there.
for my $name (
    qw(idx_search_documents_public_latest idx_search_documents_public_title_prefix
    idx_search_documents_public_filter_rank idx_search_documents_source_created)
  )
{
    unlike( $baseline{search}, qr/\b\Q$name\E\b/msx, "no $name" );
}

my $migration_schema = GPForum::Test::MigrationSchema->new;
my $runner           = GPForum::Migration::Runner->new(
    schema     => $migration_schema,
    applied_by => 'test-runner',
);
my $pending = $runner->pending;

is( scalar @{$pending},
    $EXPECTED_MIGRATIONS, 'runner sees all migrations pending on empty DB' );

my $applied = $runner->apply_pending;
my $dbh     = $migration_schema->storage->dbh;

is( scalar @{$applied},
    $EXPECTED_MIGRATIONS, 'runner applies all pending migrations' );
is( scalar @{ $dbh->executed },
    $EXPECTED_RUNNER_EXECUTIONS,
    'runner executes migration SQL plus tracking inserts' );
like(
    $dbh->executed->[0]->{statement},
    qr/CREATE [ ] TABLE [ ] public[.]schema_versions/msx,
    'runner executes first migration SQL'
);
my $first_record = qr/INSERT [ ] INTO [ ] schema_versions [^;]* [(]'1000',/msx;
like(
    $dbh->executed->[0]->{statement},
    qr/$first_record [^;]* ; \s* COMMIT; \s* \z/msx,
    'runner records the schema version inside the migration transaction'
);
like(
    $applied->[0]->{checksum},
    qr/\A [[:xdigit:]]{64} \z/msx,
    'runner reports SHA-256 migration checksum'
);
like(
    $dbh->executed->[-1]->{statement},
    qr/INSERT [ ] INTO [ ] schema_versions [^;]* 'test-runner'/msx,
    'runner records who applied the migration'
);

throws_ok(
    sub {
        GPForum::Migration::Plan->new( directory => 'missing-migrations' )
          ->files;
    },
    qr/\A migration [ ] directory [ ] not [ ] found/msx,
    'missing migration directory fails clearly',
);

is_deeply( [ _json_columns_without_codec($schema) ],
    [], 'every json/jsonb column serializes Perl structures' );

# DBIx::Class calls a column codec as ->($value, $row). A codec that accepted
# only the value died on every JSON write against PostgreSQL, and no test here
# called it the way the ORM does.
{
    my $codec =
      $schema->source('OutboxMessage')->column_info('payload')->{_inflate_info};
    my $row     = bless {}, 'GPForum::Schema::Result::OutboxMessage';
    my $encoded = $codec->{deflate}->( { kind => 'probe' }, $row );
    is_deeply(
        $codec->{inflate}->( $encoded, $row ),
        { kind => 'probe' },
        'a JSON column round-trips when called with the row, as the ORM does'
    );
}

sub _json_columns_without_codec {
    my ($schema_class) = @_;

    my @missing;
    for my $moniker ( sort $schema_class->sources ) {
        my $result_source = $schema_class->source($moniker);
        push @missing, map { "$moniker.$_" }
          grep { _needs_json_codec( $result_source->column_info($_) ) }
          $result_source->columns;
    }

    return @missing;
}

sub _needs_json_codec {
    my ($column_info) = @_;

    my $data_type = lc( $column_info->{data_type} || q{} );
    if ( $data_type ne 'json' && $data_type ne 'jsonb' ) {
        return 0;
    }

    return exists $column_info->{_inflate_info} ? 0 : 1;
}

1;
