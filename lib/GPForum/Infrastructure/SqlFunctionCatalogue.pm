# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Infrastructure::SqlFunctionCatalogue;

use Const::Fast;
use Mojo::Base -base, -signatures;
use v5.40;

use GPForum::X::Argument;

our $VERSION = '0.001';

# ADR 0126: the functions in schema api this release calls, by the name
# Perl asks for: the version it calls and its parameters, in order, each with
# its name (the function's own, without the p_ prefix) and its PostgreSQL
# type, and the result columns that hold a json document. A release moves to
# a function's next version by changing its line here. The core_ helpers the
# functions share are not listed: Perl never calls them.
# t/integration/postgres-sql-function-catalogue.t checks every entry against
# pg_proc on a migrated database.
# A reply command's post, body and revision as api.forum_create_reply_v4
# takes them, and the ids and the time the write records under.
const my @REPLY_COMMAND => (
    post_id             => 'text',
    thread_id           => 'text',
    author_user_id      => 'text',
    current_body_id     => 'text',
    current_revision_id => 'text',
    position            => 'bigint',
    visibility          => 'text',
    moderation_state    => 'text',
    version             => 'bigint',
    visibility_version  => 'bigint',
    permission_version  => 'bigint',
    hidden_at           => 'text',
    locked_at           => 'text',
    deleted_at          => 'text',
    deleted_by          => 'text',
    body_id             => 'text',
    body_post_id        => 'text',
    body_format         => 'text',
    body_source         => 'text',
    body_rendered_safe  => 'text',
    source_hash         => 'text',
    revision_id         => 'text',
    revision_post_id    => 'text',
    revision_body_id    => 'text',
    editor_user_id      => 'text',
    revision_number     => 'integer',
    edit_reason         => 'text',
);
const my @REPLY_RECORD => (
    correlation_id => 'text',
    event_id       => 'text',
    outbox_id      => 'text',
    audit_id       => 'text',
    recorded_at    => 'text',
);

const my %FUNCTION => (
    moderation_thread_transfer => {
        version    => 2,
        parameters => [
            actor        => 'uuid',
            command      => 'uuid',
            source_id    => 'uuid',
            target_id    => 'uuid',
            operation    => 'text',
            post_numbers => 'bigint[]',
            title        => 'text',
            reason       => 'text'
        ],
        json => ['result']
    },
    moderation_thread_transfer_undo => {
        version    => 2,
        parameters =>
          [ actor => 'uuid', command => 'uuid', transfer_id => 'uuid' ],
        json => ['result']
    },
    moderation_thread_transfers =>
      { version => 2, parameters => [ actor => 'uuid' ], json => ['result'] },
    forum_thread_redirect =>
      { version => 2, parameters => [ actor => 'uuid', thread_id => 'uuid' ] },
    forum_poll_read => {
        version    => 2,
        parameters => [ actor => 'uuid', thread_id => 'uuid' ],
        json       => ['result']
    },
    forum_poll_change => {
        version    => 2,
        parameters => [
            actor     => 'uuid',
            command   => 'uuid',
            thread_id => 'uuid',
            operation => 'text',
            values    => 'jsonb'
        ],
        json => ['result']
    },
    notification_category_follow => {
        version    => 2,
        parameters => [
            actor       => 'uuid',
            command     => 'uuid',
            category_id => 'uuid',
            operation   => 'text'
        ],
        json => ['result']
    },
    admin_registration_state =>
      { version => 2, parameters => [ actor => 'uuid' ], json => ['result'] },
    admin_registration_change => {
        version    => 2,
        parameters => [
            actor     => 'uuid',
            command   => 'uuid',
            operation => 'text',
            values    => 'jsonb'
        ],
        json => ['result']
    },
    forum_draft_find => {
        version    => 2,
        parameters =>
          [ owner_user_id => 'uuid', draft_id => 'uuid', now => 'timestamptz' ],
        json => ['draft'],
    },
    forum_draft_list => {
        version    => 2,
        parameters => [ owner_user_id => 'uuid', now => 'timestamptz' ],
        json       => ['draft'],
    },
    forum_draft_save => {
        version    => 2,
        parameters => [
            owner_user_id  => 'uuid',
            draft_id       => 'uuid',
            draft_revision => 'bigint',
            kind           => 'text',
            category_id    => 'uuid',
            thread_id      => 'uuid',
            title          => 'text',
            body_source    => 'text',
            visibility     => 'text',
            command_id     => 'text',
            now            => 'timestamptz'
        ],
        json => ['draft'],
    },
    forum_draft_remove => {
        version    => 2,
        parameters => [
            owner_user_id  => 'uuid',
            draft_id       => 'uuid',
            draft_revision => 'bigint',
            now            => 'timestamptz'
        ],
        json => ['draft'],
    },
    forum_draft_purge => {
        version    => 2,
        parameters => [ now => 'timestamptz', row_limit => 'integer' ],
    },
    ops_doctor_outbox => {
        version    => 2,
        parameters => [],
    },

    search_ranked => {
        version    => 10,
        parameters => [
            permission_mode   => 'text',
            visibility_values => 'text[]',
            member            => 'boolean',
            global_read       => 'boolean',
            viewer_user_id    => 'uuid',
            category_ids      => 'uuid[]',
            space_ids         => 'uuid[]',
            query             => 'text',
            like_pattern      => 'text',
            config            => 'text',
            candidate_limit   => 'integer',
            category_filter   => 'uuid',
            author_filter     => 'uuid',
            from_at           => 'timestamp with time zone',
            to_at             => 'timestamp with time zone',
            to_exclusive      => 'boolean',
            row_limit         => 'integer',
            entity_type       => 'text'
        ]
    },
    search_autocomplete => {
        version    => 8,
        parameters => [
            permission_mode   => 'text',
            visibility_values => 'text[]',
            member            => 'boolean',
            global_read       => 'boolean',
            viewer_user_id    => 'uuid',
            category_ids      => 'uuid[]',
            space_ids         => 'uuid[]',
            like_pattern      => 'text',
            row_limit         => 'integer'
        ]
    },
    search_set_timeout => { version => 2, parameters => [ timeout => 'text' ] },
    search_index_entity => {
        version    => 2,
        parameters => [
            entity_type => 'text',
            entity_id   => 'uuid',
            document_id => 'uuid',
            indexed_at  => 'text'
        ],
        json => ['result']
    },
    search_remove_document => {
        version    => 2,
        parameters => [ entity_type => 'text', entity_id => 'uuid' ],
        json       => ['result']
    },
    search_thread_post_batch => {
        version    => 2,
        parameters => [
            thread_id      => 'uuid',
            after_position => 'bigint',
            row_limit      => 'integer'
        ]
    },
    search_live_ids => {
        version    => 2,
        parameters =>
          [ entity_type => 'text', after_id => 'uuid', row_limit => 'integer' ]
    },
    search_prune_candidates =>
      { version => 2, parameters => [ entity_type => 'text' ] },
    search_remove_post_batch => {
        version    => 2,
        parameters => [ thread_id => 'uuid', post_ids => 'uuid[]' ]
    },
    search_observe_lag    => { version => 2, parameters => [] },
    search_latest_rebuild => { version => 2, parameters => [] },

    ops_partition_horizon => {
        version    => 2,
        parameters => [],
    },

    forum_next_position =>
      { version => 2, parameters => [ thread_id => 'uuid' ] },

    privacy_insert => {
        version    => 2,
        parameters => [ source => 'text', row => 'jsonb' ],
        json       => ['document']
    },
    privacy_find => {
        version    => 2,
        parameters => [ source => 'text', id => 'uuid', lock_row => 'boolean' ],
        json       => ['document']
    },
    privacy_latest => {
        version    => 2,
        parameters => [ source => 'text', query => 'jsonb' ],
        json       => ['document']
    },
    privacy_review => {
        version    => 2,
        parameters => [
            source    => 'text',
            query     => 'jsonb',
            row_limit => 'integer',
            oldest    => 'boolean'
        ],
        json => ['document']
    },
    privacy_update => {
        version    => 4,
        parameters => [ source => 'text', id => 'uuid', changes => 'jsonb' ],
        json       => ['document']
    },
    privacy_revoke_user => {
        version    => 24,
        parameters => [ source => 'text', user_id => 'uuid', at => 'text' ]
    },
    privacy_may_export => { version => 2, parameters => [ user_id => 'uuid' ] },
    privacy_discard_exports => {
        version    => 2,
        parameters => [ user_id => 'uuid' ],
        json       => ['document']
    },
    portability_export_parts => {
        version    => 24,
        parameters => [ user_id => 'uuid' ],
        json       => ['document']
    },

    ops_publish_notification =>
      { version => 2, parameters => [ channel => 'text', payload => 'text' ] },
    ops_retention_purge => {
        version    => 4,
        parameters =>
          [ source => 'text', cutoff => 'timestamptz', row_limit => 'integer' ]
    },
    ops_outbox_metrics =>
      { version => 2, parameters => [ now => 'timestamptz' ] },
    ops_readiness_probe => { version => 2, parameters => [ source => 'text' ] },
    ops_query_budget_list =>
      { version => 2, parameters => [ row_limit => 'integer' ] },
    ops_query_budget_sync => {
        version    => 2,
        parameters => [ rows => 'jsonb', endpoint_names => 'text[]' ]
    },
    ops_partition_registry => { version => 2, parameters => [] },
    ops_realtime_settled   =>
      { version => 2, parameters => [ settle_seconds => 'integer' ] },
    ops_realtime_poll => {
        version    => 2,
        json       => ['payload'],
        parameters => [
            after_next_at    => 'timestamptz',
            after_created_at => 'timestamptz',
            after_id         => 'uuid',
            settled_at       => 'timestamptz',
            settle_seconds   => 'integer',
            row_limit        => 'integer'
        ]
    },
    ops_replication_recovery => { version => 2, parameters => [] },
    ops_replication_standbys => { version => 2, parameters => [] },
    ops_replication_slots    =>
      { version => 2, parameters => [ standby => 'boolean' ] },
    ops_replication_position => { version => 2, parameters => [] },

    admin_lookup_role => {
        version    => 2,
        parameters => [ query => 'jsonb' ],
    },
    admin_lookup_permission => {
        version    => 2,
        parameters => [ query => 'jsonb' ],
    },
    admin_lookup_role_permission => {
        version    => 2,
        parameters => [ query => 'jsonb' ],
    },
    admin_lookup_audit => {
        version    => 2,
        parameters => [ query => 'jsonb' ],
    },
    admin_lookup_binding => {
        version    => 2,
        parameters => [ query => 'jsonb' ],
    },
    admin_attachment_audits => {
        version    => 2,
        parameters =>
          [ action => 'text', target_id => 'uuid', target_type => 'text' ],
        json => ['metadata'],
    },
    admin_insert_role => {
        version    => 2,
        parameters => [ values => 'jsonb' ],
    },
    admin_insert_permission => {
        version    => 2,
        parameters => [ values => 'jsonb' ],
    },
    admin_insert_role_permission => {
        version    => 2,
        parameters => [ values => 'jsonb' ],
    },
    admin_insert_binding => {
        version    => 2,
        parameters => [ values => 'jsonb' ],
    },
    admin_insert_space => {
        version    => 2,
        parameters => [ values => 'jsonb' ],
    },
    admin_insert_category => {
        version    => 2,
        parameters => [ values => 'jsonb' ],
    },
    admin_update_category => {
        version    => 2,
        parameters => [ category_id => 'uuid', values => 'jsonb' ],
    },
    admin_lock_binding => {
        version    => 2,
        parameters => [ binding_id => 'uuid' ],
    },
    admin_revoke_binding => {
        version    => 2,
        parameters => [ binding_id => 'uuid', revoked_at => 'timestamptz' ],
    },
    admin_list_roles => {
        version    => 2,
        parameters => [ row_limit => 'integer' ],
    },
    admin_list_permissions => {
        version    => 2,
        parameters => [ row_limit => 'integer' ],
    },
    admin_insert_announcement =>
      { version => 2, parameters => [ values => 'jsonb' ] },
    admin_retire_announcement => {
        version    => 2,
        parameters => [ announcement_id => 'uuid', values => 'jsonb' ]
    },

    # ADR 0145: address and range bans.
    admin_address_ban_place => {
        version    => 2,
        parameters => [
            ban_id        => 'uuid',
            range         => 'cidr',
            scope         => 'text',
            reason        => 'text',
            expires_at    => 'timestamptz',
            actor_user_id => 'uuid',
            actor_address => 'inet',
            now           => 'timestamptz',
            audit         => 'jsonb',
        ],
    },
    admin_address_ban_edit => {
        version    => 2,
        parameters => [
            ban_id        => 'uuid',
            scope         => 'text',
            reason        => 'text',
            expires_at    => 'timestamptz',
            actor_user_id => 'uuid',
            actor_address => 'inet',
            now           => 'timestamptz',
            audit         => 'jsonb',
        ],
    },
    admin_address_ban_lift => {
        version    => 2,
        parameters => [
            ban_id        => 'uuid',
            actor_user_id => 'uuid',
            now           => 'timestamptz',
            audit         => 'jsonb',
        ],
    },
    admin_address_bans => {
        version    => 2,
        parameters => [ now => 'timestamptz', row_limit => 'integer' ]
    },
    admin_address_ban_covering => {
        version    => 2,
        parameters => [ address => 'inet', now => 'timestamptz' ]
    },
    admin_announcement_by_id =>
      { version => 2, parameters => [ announcement_id => 'uuid' ] },
    admin_list_announcements =>
      { version => 2, parameters => [ row_limit => 'integer' ] },
    forum_active_announcements =>
      { version => 2, parameters => [ row_limit => 'integer' ] },
    admin_list_categories => {
        version    => 2,
        parameters => [ row_limit => 'integer' ],
    },
    admin_roles_for_user => {
        version    => 2,
        parameters => [ user_id => 'uuid', row_limit => 'integer' ],
    },
    admin_permissions_for_role => {
        version    => 2,
        parameters => [ role_id => 'uuid', row_limit => 'integer' ],
    },
    admin_space_by_id => {
        version    => 2,
        parameters => [ space_id => 'uuid' ],
    },
    admin_space_by_slug => {
        version    => 2,
        parameters => [ slug => 'text' ],
    },
    admin_first_live_space => {
        version    => 2,
        parameters => [],
    },
    admin_category_by_id => {
        version    => 2,
        parameters => [ category_id => 'uuid' ],
    },
    admin_live_category_by_slug => {
        version    => 2,
        parameters => [ space_id => 'uuid', slug => 'text' ],
    },
    admin_console_users => {
        version    => 2,
        parameters => [ status => 'text', row_limit => 'integer' ],
    },
    admin_console_reports => {
        version    => 2,
        parameters => [ status => 'text', row_limit => 'integer' ],
    },
    admin_console_outbox => {
        version    => 2,
        parameters => [ status => 'text', row_limit => 'integer' ],
    },
    admin_console_email => {
        version    => 2,
        parameters => [ user_id => 'uuid' ],
    },
    admin_console_counts => {
        version    => 2,
        parameters => [ dead_letters => 'boolean' ],
    },
    admin_console_dead_letters => {
        version    => 2,
        parameters => [ row_limit => 'integer' ],
    },
    admin_audit_recent => {
        version    => 2,
        parameters => [ row_limit => 'integer' ],
    },
    admin_audit_page => {
        version    => 2,
        parameters =>
          [ filters => 'jsonb', after => 'jsonb', row_limit => 'integer' ],
    },
    admin_allow_slow_answer => {
        version    => 2,
        parameters => [ idle_ms => 'integer' ],
    },

    forum_read_state => {
        version    => 2,
        parameters => [ user_id => 'uuid', thread_id => 'uuid' ]
    },
    forum_mark_read =>
      { version => 2, parameters => [ row => 'jsonb' ], json => ['result'] },

    # The thread actions as one call each (ADR 0126, section 5): the command
    # log and the work, with the answer the workflow records. p_answer is a
    # refusal decided before the call, recorded without the work.
    forum_read_marker_command => {
        version    => 2,
        parameters => [ log => 'jsonb', answer => 'jsonb', row => 'jsonb' ],
        json       => ['response']
    },

    attachment_find => {
        version    => 2,
        parameters =>
          [ attachment_id => 'uuid', object_key => 'text', hold => 'boolean' ]
    },
    attachment_links => {
        version    => 2,
        parameters => [
            attachment_id => 'uuid',
            target_type   => 'text',
            target_id     => 'uuid',
            post_ids      => 'uuid[]',
            row_limit     => 'integer'
        ]
    },
    attachment_variants => {
        version    => 2,
        parameters => [
            attachment_id => 'uuid',
            variant_type  => 'text',
            object_key    => 'text',
            row_limit     => 'integer'
        ]
    },
    attachment_insert => { version => 2, parameters => [ values => 'jsonb' ] },
    attachment_link_insert =>
      { version => 2, parameters => [ values => 'jsonb' ] },
    attachment_variant_insert =>
      { version => 2, parameters => [ values => 'jsonb' ] },
    attachment_update => {
        version    => 2,
        parameters => [ attachment_id => 'uuid', changes => 'jsonb' ]
    },
    attachment_scan_verdict => {
        version    => 2,
        parameters => [ attachment_id => 'uuid', changes => 'jsonb' ]
    },
    attachment_scan_queue => {
        version    => 2,
        parameters => [ pending => 'boolean', row_limit => 'integer' ]
    },
    attachment_confirm_clean => {
        version    => 2,
        parameters => [
            attachment_id => 'uuid',
            scan_engine   => 'text',
            scanned_at    => 'timestamptz'
        ]
    },
    attachment_scan_failure => {
        version    => 2,
        parameters => [ attachment_id => 'uuid', error => 'text' ]
    },
    attachment_orphans => {
        version    => 2,
        parameters => [ cutoff => 'timestamptz', row_limit => 'integer' ]
    },
    attachment_source_post =>
      { version => 2, parameters => [ target_id => 'uuid' ] },
    attachment_source_thread =>
      { version => 2, parameters => [ target_id => 'uuid' ] },

    community_list_bookmarks => {
        version    => 4,
        parameters => [
            user_id          => 'uuid',
            filter_sources   => 'boolean',
            member           => 'boolean',
            global_read      => 'boolean',
            viewer_user_id   => 'uuid',
            category_ids     => 'uuid[]',
            space_ids        => 'uuid[]',
            target_type      => 'text',
            after_created_at => 'timestamp with time zone',
            after_id         => 'uuid',
            row_limit        => 'integer',
            folder           => 'text'
        ]
    },
    community_list_feed => {
        version    => 4,
        parameters => [
            user_id          => 'uuid',
            filter_sources   => 'boolean',
            member           => 'boolean',
            global_read      => 'boolean',
            viewer_user_id   => 'uuid',
            category_ids     => 'uuid[]',
            space_ids        => 'uuid[]',
            after_created_at => 'timestamp with time zone',
            after_id         => 'uuid',
            row_limit        => 'integer'
        ]
    },
    community_list_mentions => {
        version    => 4,
        parameters => [
            user_id          => 'uuid',
            filter_sources   => 'boolean',
            member           => 'boolean',
            global_read      => 'boolean',
            viewer_user_id   => 'uuid',
            category_ids     => 'uuid[]',
            space_ids        => 'uuid[]',
            after_created_at => 'timestamp with time zone',
            after_id         => 'uuid',
            row_limit        => 'integer'
        ]
    },
    community_set_bookmark_folder => {
        version    => 2,
        parameters =>
          [ bookmark_id => 'uuid', user_id => 'uuid', folder => 'text' ]
    },
    community_list_bookmark_folders =>
      { version => 2, parameters => [ user_id => 'uuid' ] },
    community_save_bookmark => {
        version    => 2,
        parameters => [ row => 'jsonb', restore => 'boolean' ],
        json       => ['result']
    },
    community_bookmark_command => {
        version    => 2,
        parameters => [ log => 'jsonb', answer => 'jsonb', row => 'jsonb' ],
        json       => ['response']
    },
    community_like_command => {
        version    => 2,
        parameters => [ log => 'jsonb', answer => 'jsonb', row => 'jsonb' ],
        json       => ['response']
    },
    community_unlike_command => {
        version    => 2,
        parameters => [ log => 'jsonb', answer => 'jsonb', row => 'jsonb' ],
        json       => ['response']
    },
    community_like_post => {
        version    => 2,
        parameters => [ row => 'jsonb' ],
        json       => ['result']
    },
    community_unlike_post => {
        version    => 2,
        parameters => [ row => 'jsonb' ],
        json       => ['result']
    },
    forum_link_reply => {
        version    => 2,
        parameters => [ post_id => 'uuid', reply_to_post_id => 'uuid' ]
    },
    forum_reply_targets =>
      { version => 2, parameters => [ post_ids => 'uuid[]' ] },
    forum_set_thread_tags => {
        version    => 2,
        parameters =>
          [ thread_id => 'uuid', slugs => 'text[]', names => 'text[]' ]
    },
    forum_thread_tags =>
      { version => 2, parameters => [ thread_ids => 'uuid[]' ] },
    forum_list_tagged_threads => {
        version    => 2,
        parameters => [
            tag_slug      => 'text',
            category_id   => 'uuid',
            member        => 'boolean',
            global_read   => 'boolean',
            scope_user_id => 'uuid',
            category_ids  => 'uuid[]',
            space_ids     => 'uuid[]',
            row_limit     => 'integer'
        ]
    },
    forum_list_tags => {
        version    => 2,
        parameters => [
            member        => 'boolean',
            global_read   => 'boolean',
            scope_user_id => 'uuid',
            category_ids  => 'uuid[]',
            space_ids     => 'uuid[]',
            row_limit     => 'integer'
        ]
    },
    community_post_likes => {
        version    => 2,
        parameters => [ post_ids => 'uuid[]', viewer_user_id => 'uuid' ]
    },
    community_post_reactions => {
        version    => 2,
        parameters => [ post_ids => 'uuid[]', viewer_user_id => 'uuid' ]
    },
    community_react_post => {
        version    => 2,
        parameters => [ row => 'jsonb' ],
        json       => ['result']
    },
    community_unreact_post => {
        version    => 2,
        parameters => [ row => 'jsonb' ],
        json       => ['result']
    },
    community_react_command => {
        version    => 2,
        parameters => [ log => 'jsonb', answer => 'jsonb', row => 'jsonb' ],
        json       => ['response']
    },
    community_unreact_command => {
        version    => 2,
        parameters => [ log => 'jsonb', answer => 'jsonb', row => 'jsonb' ],
        json       => ['response']
    },
    community_subscribe_command => {
        version    => 2,
        parameters => [ log => 'jsonb', answer => 'jsonb', row => 'jsonb' ],
        json       => ['response']
    },
    community_relation_set => {
        version    => 2,
        parameters => [
            owner_user_id => 'uuid',
            username      => 'text',
            kind          => 'text',
            now           => 'timestamptz',
        ],
    },
    community_relation_remove => {
        version    => 2,
        parameters => [ owner_user_id => 'uuid', username => 'text' ],
    },
    community_relation_list =>
      { version => 2, parameters => [ owner_user_id => 'uuid' ] },
    community_relation_between => {
        version    => 2,
        parameters => [ owner_user_id => 'uuid', other_user_id => 'uuid' ],
    },

    # ADR 0139: direct messages between two members.
    community_message_start =>
      { version => 2, parameters => [ row => 'jsonb' ] },
    community_message_reply =>
      { version => 2, parameters => [ row => 'jsonb' ] },
    community_message_inbox => {
        version    => 2,
        parameters => [
            user_id   => 'uuid',
            after_at  => 'timestamptz',
            after_id  => 'uuid',
            row_limit => 'integer'
        ]
    },
    community_message_conversation => {
        version    => 2,
        parameters => [ conversation_id => 'uuid', user_id => 'uuid' ]
    },
    community_message_list => {
        version    => 2,
        parameters => [
            conversation_id => 'uuid',
            user_id         => 'uuid',
            before_position => 'bigint',
            row_limit       => 'integer'
        ]
    },
    community_message_mark_read => {
        version    => 2,
        parameters => [
            conversation_id => 'uuid',
            user_id         => 'uuid',
            now             => 'timestamptz'
        ]
    },
    community_message_conversation_with => {
        version    => 2,
        parameters => [ user_id => 'uuid', username => 'text' ]
    },
    community_message_for_report => {
        version    => 2,
        parameters => [ message_id => 'uuid', user_id => 'uuid' ]
    },
    community_message_participant => {
        version    => 2,
        parameters => [ message_id => 'uuid', user_id => 'uuid' ]
    },

    # Migration 132: members' profile pictures (ADR 0144).
    community_avatar_offer => {
        version    => 2,
        parameters => [
            user_id       => 'uuid',
            attachment_id => 'uuid',
            now           => 'timestamptz'
        ]
    },
    community_avatar_settle => {
        version    => 2,
        parameters => [
            user_id       => 'uuid',
            attachment_id => 'uuid',
            outcome       => 'text',
            now           => 'timestamptz'
        ]
    },
    community_avatar_remove => {
        version    => 2,
        parameters =>
          [ user_id => 'uuid', attachment_id => 'uuid', audit => 'jsonb' ]
    },
    community_avatar_status =>
      { version => 2, parameters => [ user_id => 'uuid' ] },
    community_avatar_image => {
        version    => 2,
        parameters => [ user_id => 'uuid', variant_type => 'text' ]
    },
    community_avatar_objects => {
        version    => 2,
        parameters => [ user_id => 'uuid', attachment_id => 'uuid' ]
    },
    community_find_bookmark => {
        version    => 2,
        parameters =>
          [ user_id => 'uuid', target_type => 'text', target_id => 'uuid' ]
    },
    community_stamp_bookmark => {
        version    => 2,
        parameters => [
            id          => 'uuid',
            by_target   => 'boolean',
            user_id     => 'uuid',
            target_type => 'text',
            target_id   => 'uuid',
            column      => 'text',
            stamped_at  => 'text'
        ],
        json => ['result']
    },
    notification_save_subscription => {
        version    => 2,
        parameters => [ row => 'jsonb', restore => 'boolean' ],
        json       => ['result']
    },
    notification_find_subscription => {
        version    => 2,
        parameters =>
          [ user_id => 'uuid', target_type => 'text', target_id => 'uuid' ]
    },
    notification_stamp_subscription => {
        version    => 2,
        parameters => [
            id          => 'uuid',
            by_target   => 'boolean',
            user_id     => 'uuid',
            target_type => 'text',
            target_id   => 'uuid',
            column      => 'text',
            stamped_at  => 'text'
        ],
        json => ['result']
    },
    notification_subscribers => {
        version    => 4,
        parameters => [
            target_type       => 'text',
            target_id         => 'uuid',
            notification_type => 'text'
        ]
    },
    notification_list_preferences =>
      { version => 2, parameters => [ user_id => 'uuid' ] },
    notification_set_preference =>
      { version => 2, parameters => [ row => 'jsonb' ], json => ['result'] },

    # ADR 0078: notification preferences by kind, and the unsubscribe link.
    notification_type_preferences =>
      { version => 4, parameters => [ user_id => 'uuid' ] },
    notification_set_type_preferences => {
        version    => 4,
        parameters =>
          [ user_id => 'uuid', preferences => 'jsonb', now => 'timestamptz' ]
    },
    notification_delivery_plan => {
        version    => 4,
        parameters => [ user_id => 'uuid', notification_type => 'text' ]
    },
    notification_unsubscribe => {
        version    => 4,
        parameters => [
            user_id => 'uuid',
            scope   => 'text',
            now     => 'timestamptz',
            audit   => 'jsonb'
        ]
    },

    # ADR 0078: the daily and weekly email digest.
    notification_digest_due => {
        version    => 4,
        parameters => [
            now           => 'timestamptz',
            after_start   => 'timestamptz',
            after_user_id => 'uuid',
            row_limit     => 'integer'
        ]
    },
    notification_digest_items => {
        version    => 4,
        parameters => [
            user_id      => 'uuid',
            period_start => 'timestamptz',
            period_end   => 'timestamptz',
            member       => 'boolean',
            global_read  => 'boolean',
            category_ids => 'uuid[]',
            space_ids    => 'uuid[]',
            row_limit    => 'integer'
        ]
    },
    notification_digest_record => {
        version    => 4,
        parameters => [
            user_id       => 'uuid',
            frequency     => 'text',
            period_start  => 'timestamptz',
            period_end    => 'timestamptz',
            thread_count  => 'integer',
            now           => 'timestamptz',
            event         => 'jsonb',
            outbox_id     => 'text',
            outbox_extras => 'jsonb',
            explicit      => 'boolean'
        ]
    },
    notification_digest_plan => {
        version    => 4,
        parameters => [ user_id => 'uuid', now => 'timestamptz' ]
    },
    notification_digest_unsubscribe => {
        version    => 2,
        parameters =>
          [ user_id => 'uuid', now => 'timestamptz', audit => 'jsonb' ]
    },
    notification_digest_purge => {
        version    => 2,
        parameters => [ before => 'timestamptz', row_limit => 'integer' ]
    },
    notification_digest_claim => {
        version    => 2,
        parameters => [
            user_id      => 'uuid',
            frequency    => 'text',
            period_start => 'timestamptz',
            event_id     => 'uuid',
            now          => 'timestamptz'
        ]
    },
    notification_digest_release => {
        version    => 2,
        parameters => [
            user_id      => 'uuid',
            frequency    => 'text',
            period_start => 'timestamptz',
            event_id     => 'uuid'
        ]
    },
    community_project_feed => {
        version    => 2,
        parameters => [ row => 'jsonb', user_ids => 'uuid[]' ],
        json       => ['result']
    },
    community_remove_feed => {
        version    => 2,
        parameters => [ item_type => 'text', item_id => 'uuid' ],
        json       => ['result']
    },
    community_remove_thread_feed => {
        version    => 2,
        parameters => [ thread_id => 'uuid' ],
        json       => ['result']
    },
    community_resolve_mention_users =>
      { version => 2, parameters => [ usernames => 'text[]' ] },
    community_create_mention =>
      { version => 2, parameters => [ row => 'jsonb' ], json => ['result'] },
    community_record_reputation =>
      { version => 2, parameters => [ row => 'jsonb' ], json => ['result'] },
    notification_deliver => {
        version    => 2,
        parameters => [
            notification    => 'jsonb',
            inbox           => 'jsonb',
            idempotency_key => 'text'
        ],
        json => ['result']
    },
    notification_mark_read => {
        version    => 2,
        parameters => [
            notification_id   => 'uuid',
            recipient_user_id => 'uuid',
            read_at           => 'text'
        ],
        json => ['result']
    },
    notification_mark_all_read => {
        version    => 2,
        parameters => [
            user_id        => 'uuid',
            filter_sources => 'boolean',
            member         => 'boolean',
            global_read    => 'boolean',
            viewer_user_id => 'uuid',
            category_ids   => 'uuid[]',
            space_ids      => 'uuid[]',
            read_at        => 'text'
        ],
        json => ['result']
    },

    moderation_target => {
        version    => 4,
        parameters => [ kind => 'text', target_id => 'uuid', hold => 'boolean' ]
    },
    moderation_target_update => {
        version    => 4,
        parameters =>
          [ kind => 'text', target_id => 'uuid', changes => 'jsonb' ]
    },
    moderation_action_find => {
        version    => 2,
        parameters => [
            action_id   => 'uuid',
            command_id  => 'uuid',
            action_type => 'text',
            target_type => 'text',
            target_id   => 'uuid'
        ]
    },
    moderation_action_update => {
        version    => 2,
        parameters => [ action_id => 'uuid', changes => 'jsonb' ]
    },
    moderation_report_find => {
        version    => 2,
        parameters => [
            report_id        => 'uuid',
            reporter_user_id => 'uuid',
            target_type      => 'text',
            target_id        => 'uuid',
            hold             => 'boolean'
        ]
    },
    moderation_report_update => {
        version    => 2,
        parameters => [ report_id => 'uuid', changes => 'jsonb' ]
    },
    moderation_report_queue => {
        version    => 2,
        parameters => [ status => 'text', row_limit => 'integer' ]
    },

    # ADR 0133: watched words and automod rules.
    moderation_watched_word_add => {
        version    => 2,
        parameters => [
            word_id       => 'uuid',
            phrase        => 'text',
            action        => 'text',
            replacement   => 'text',
            actor_user_id => 'uuid',
            now           => 'timestamptz',
            audit         => 'jsonb',
        ],
    },
    moderation_watched_word_remove =>
      { version => 2, parameters => [ word_id => 'uuid', audit => 'jsonb' ] },
    moderation_watched_word_list    => { version => 2, parameters => [] },
    moderation_automod_settings_set => {
        version    => 2,
        parameters => [
            link_limit       => 'integer',
            link_trust_below => 'integer',
            link_action      => 'text',
            actor_user_id    => 'uuid',
            now              => 'timestamptz',
            audit            => 'jsonb',
        ],
    },
    moderation_automod_rules => {
        version    => 4,
        parameters => [ user_id => 'uuid' ],
        json       => ['document']
    },
    moderation_automod_record => {
        version    => 4,
        parameters => [
            report          => 'jsonb',
            event           => 'jsonb',
            event_outbox_id => 'text',
            report_audit    => 'jsonb',
            audits          => 'jsonb',
        ],
    },

    # ADR 0134: the first-post review queue.
    moderation_review_hold => {
        version    => 2,
        parameters => [
            review_id          => 'uuid',
            author_user_id     => 'uuid',
            command_id         => 'text',
            kind               => 'text',
            category_id        => 'uuid',
            thread_id          => 'uuid',
            title              => 'text',
            body_source        => 'text',
            body_rendered_safe => 'text',
            visibility         => 'text',
            reply_to_post_id   => 'uuid',
            reason             => 'text',
            details            => 'jsonb',
            draft_id           => 'uuid',
            draft_revision     => 'bigint',
            now                => 'timestamptz',
            audit              => 'jsonb',
        ],
    },
    moderation_review_queue => {
        version    => 2,
        parameters => [ row_limit => 'integer' ],
        json       => ['details']
    },
    moderation_review_mine => {
        version    => 4,
        parameters => [
            user_id      => 'uuid',
            row_limit    => 'integer',
            member       => 'boolean',
            global_read  => 'boolean',
            category_ids => 'uuid[]',
            space_ids    => 'uuid[]'
        ]
    },
    moderation_review_take =>
      { version => 2, parameters => [ review_id => 'uuid' ] },
    moderation_review_decide => {
        version    => 2,
        parameters => [
            review_id     => 'uuid',
            status        => 'text',
            actor_user_id => 'uuid',
            reason        => 'text',
            post_id       => 'uuid',
            now           => 'timestamptz',
            audit         => 'jsonb',
        ],
    },
    moderation_review_settings_set => {
        version    => 2,
        parameters => [
            first_posts   => 'integer',
            flagged       => 'boolean',
            actor_user_id => 'uuid',
            now           => 'timestamptz',
            audit         => 'jsonb',
        ],
    },
    moderation_member_note_add => {
        version    => 2,
        parameters => [
            note_id         => 'uuid',
            subject_user_id => 'uuid',
            author_user_id  => 'uuid',
            body            => 'text',
            now             => 'timestamptz',
            audit           => 'jsonb',
        ],
    },
    moderation_member_note_edit => {
        version    => 2,
        parameters => [
            note_id         => 'uuid',
            subject_user_id => 'uuid',
            editor_user_id  => 'uuid',
            body            => 'text',
            now             => 'timestamptz',
            audit           => 'jsonb',
        ],
    },
    moderation_member_note_delete => {
        version    => 2,
        parameters =>
          [ note_id => 'uuid', subject_user_id => 'uuid', audit => 'jsonb' ],
    },
    moderation_member_notes => {
        version    => 2,
        parameters => [ subject_user_id => 'uuid', row_limit => 'integer' ]
    },
    moderation_member_notes_for_reports => {
        version    => 2,
        parameters => [ report_ids => 'uuid[]', per_member => 'integer' ]
    },

    # ADR 0139: staff read a reported message, audited.
    moderation_reported_message => {
        version    => 2,
        parameters => [ report_id => 'uuid', audit => 'jsonb' ]
    },
    moderation_suspension_find =>
      { version => 2, parameters => [ suspension_id => 'uuid' ] },
    moderation_suspension_update => {
        version    => 2,
        parameters => [ suspension_id => 'uuid', revoked_at => 'timestamptz' ]
    },
    moderation_action_insert =>
      { version => 2, parameters => [ values => 'jsonb' ] },
    moderation_report_insert =>
      { version => 2, parameters => [ values => 'jsonb' ] },
    moderation_suspension_insert =>
      { version => 2, parameters => [ values => 'jsonb' ] },
    moderation_action_list => {
        version    => 2,
        parameters => [
            target_type => 'text',
            target_id   => 'uuid',
            after_at    => 'timestamptz',
            after_id    => 'uuid',
            row_limit   => 'integer'
        ]
    },
    moderation_suspension_list => {
        version    => 2,
        parameters => [
            user_id     => 'uuid',
            active_only => 'boolean',
            now         => 'timestamptz',
            after_at    => 'timestamptz',
            after_id    => 'uuid',
            row_limit   => 'integer'
        ]
    },

    ops_record_event => {
        version    => 2,
        parameters => [
            event         => 'jsonb',
            outbox_id     => 'text',
            outbox_extras => 'jsonb',
            explicit      => 'boolean'
        ],
        json => ['event']
    },
    ops_record_audit => {
        version    => 2,
        parameters => [ audit => 'jsonb', explicit => 'boolean' ],
        json       => ['audit']
    },
    ops_event_recorded => { version => 2, parameters => [ key => 'text' ] },
    ops_command_lookup => {
        version    => 2,
        parameters => [ key => 'text', command_id => 'uuid' ],
        json       => ['document']
    },
    ops_command_insert => {
        version    => 2,
        parameters => [ command => 'jsonb' ],
        json       => ['document']
    },
    ops_command_finish => {
        version    => 2,
        parameters => [ command_id => 'uuid', changes => 'jsonb' ]
    },
    ops_event_claim => {
        version    => 2,
        parameters => [
            operation      => 'text',
            key            => 'text',
            event_id       => 'text',
            now            => 'text',
            expired_before => 'text'
        ]
    },
    outbox_claim_ready => {
        version    => 2,
        parameters => [
            now          => 'text',
            locked_until => 'text',
            worker_id    => 'text',
            row_limit    => 'integer'
        ],
        json => ['payload']
    },
    outbox_owned_write => {
        version    => 2,
        parameters =>
          [ outbox_id => 'uuid', worker_id => 'text', changes => 'jsonb' ]
    },
    outbox_dead_letter =>
      { version => 2, parameters => [ letter => 'jsonb' ], json => ['letter'] },
    outbox_replay_dead_letter => {
        version    => 2,
        parameters => [ input => 'jsonb', ids => 'jsonb', now => 'text' ],
        json       => ['result']
    },
    ops_worker_aggregate => {
        version    => 2,
        parameters => [ aggregate_type => 'text', aggregate_id => 'uuid' ]
    },
    ops_thread_activity =>
      { version => 2, parameters => [ thread_id => 'uuid', at => 'text' ] },

    identity_user_by_id => {
        version    => 2,
        parameters => [ user_id => 'uuid' ],
    },
    identity_user_by_identifier => {
        version    => 2,
        parameters => [ identifier => 'text', by_email => 'boolean' ],
    },

    # ADR 0142: two-step sign-in.
    identity_second_factor_status =>
      { version => 2, parameters => [ user_id => 'uuid' ] },
    identity_second_factor_begin => {
        version    => 2,
        parameters => [
            user_id       => 'uuid',
            secret_sealed => 'text',
            key_id        => 'text',
            now           => 'timestamptz',
        ],
    },
    identity_second_factor_cancel =>
      { version => 2, parameters => [ user_id => 'uuid' ] },
    identity_second_factor_confirm => {
        version    => 2,
        parameters => [
            user_id         => 'uuid',
            step            => 'bigint',
            code_hashes     => 'text[]',
            now             => 'timestamptz',
            keep_session_id => 'uuid',
            audit           => 'jsonb',
            mail            => 'jsonb',
        ],
    },
    identity_second_factor_disable => {
        version    => 2,
        parameters => [
            user_id       => 'uuid',
            step          => 'bigint',
            recovery_hash => 'text',
            now           => 'timestamptz',
            audit         => 'jsonb',
            mail          => 'jsonb',
        ],
    },
    identity_second_factor_renew => {
        version    => 2,
        parameters => [
            user_id     => 'uuid',
            step        => 'bigint',
            code_hashes => 'text[]',
            now         => 'timestamptz',
            audit       => 'jsonb',
        ],
    },
    identity_second_factor_challenge_open =>
      { version => 2, parameters => [ row => 'jsonb' ] },
    identity_second_factor_challenge => {
        version    => 2,
        parameters => [ token_hash => 'text', now => 'timestamptz' ],
    },
    identity_second_factor_challenge_answer => {
        version    => 2,
        parameters => [
            token_hash    => 'text',
            step          => 'bigint',
            recovery_hash => 'text',
            resealed      => 'text',
            key_id        => 'text',
            now           => 'timestamptz',
            audit         => 'jsonb',
            mail          => 'jsonb',
        ],
    },
    admin_second_factor_member =>
      { version => 2, parameters => [ user_id => 'uuid' ] },
    admin_second_factor_reset => {
        version    => 2,
        parameters => [
            user_id       => 'uuid',
            actor_user_id => 'uuid',
            now           => 'timestamptz',
            audit         => 'jsonb',
            mail          => 'jsonb',
        ],
    },
    admin_second_factor_policy => { version => 2, parameters => [] },
    admin_second_factor_staff  =>
      { version => 2, parameters => [ row_limit => 'integer' ] },
    admin_second_factor_policy_set => {
        version    => 2,
        parameters => [
            required      => 'boolean',
            actor_user_id => 'uuid',
            now           => 'timestamptz',
            audit         => 'jsonb',
        ],
    },
    identity_registration_duplicates => {
        version    => 2,
        parameters => [ username => 'text', email => 'text' ],
    },
    identity_insert_user => {
        version    => 2,
        parameters => [ values => 'jsonb' ],
    },
    identity_update_user => {
        version    => 6,
        parameters => [ user_id => 'uuid', changes => 'jsonb' ],
    },
    identity_insert_credential => {
        version    => 2,
        parameters => [ values => 'jsonb' ],
    },
    identity_credential_by_id => {
        version    => 2,
        parameters => [ credential_id => 'uuid' ],
    },
    identity_active_password => {
        version    => 2,
        parameters => [ user_id => 'uuid' ],
    },
    identity_hold_password => {
        version    => 2,
        parameters => [ user_id => 'uuid', credential_id => 'uuid' ],
    },

    # A registration as one call (ADR 0126, section 5): the command log, the
    # duplicates, the user, the credential, the registration's event and
    # audit, the verification token with its audit and mail.
    identity_register_command => {
        version    => 4,
        parameters => [
            log                => 'jsonb',
            answer             => 'jsonb',
            accepted           => 'jsonb',
            refused            => 'jsonb',
            user               => 'jsonb',
            credential         => 'jsonb',
            event              => 'jsonb',
            event_outbox_id    => 'text',
            audit              => 'jsonb',
            token              => 'jsonb',
            token_audit        => 'jsonb',
            mail_event         => 'jsonb',
            mail_outbox_id     => 'text',
            mail_outbox_extras => 'jsonb',
            invitation_hash    => 'text',
        ],
        json => [ 'response', 'stored_user' ],
    },
    identity_lock_passwords => {
        version    => 2,
        parameters => [ user_id => 'uuid' ],
    },
    identity_revoke_passwords => {
        version    => 2,
        parameters => [ ids => 'jsonb', revoked_at => 'timestamptz' ],
    },
    identity_insert_token => {
        version    => 2,
        parameters => [ values => 'jsonb' ],
    },
    identity_token_by_id => {
        version    => 2,
        parameters => [ token_id => 'uuid' ],
    },
    identity_unused_token => {
        version    => 2,
        parameters => [ user_id => 'uuid', token_type => 'text' ],
    },
    identity_rotate_token => {
        version    => 2,
        parameters => [ token_id => 'uuid', values => 'jsonb' ],
    },
    identity_consume_token => {
        version    => 2,
        parameters => [
            token_hash => 'text',
            token_type => 'text',
            now        => 'timestamptz',
            now_epoch  => 'bigint'
        ],
        json => ['token_row'],
    },
    identity_profile_trust => {
        version    => 2,
        parameters => [ user_id => 'uuid' ],
    },
    identity_profile_counts => {
        version    => 2,
        parameters => [ user_id => 'uuid' ],
    },
    identity_profile_threads => {
        version    => 2,
        parameters => [
            user_id   => 'uuid',
            after_at  => 'timestamptz',
            after_id  => 'uuid',
            row_limit => 'integer'
        ],
    },
    identity_profile_replies => {
        version    => 2,
        parameters => [
            user_id   => 'uuid',
            after_at  => 'timestamptz',
            after_id  => 'uuid',
            row_limit => 'integer'
        ],
    },

    forum_thread_page_posts_scoped => {
        version    => 4,
        parameters => [
            thread_id      => 'uuid',
            standing       => 'text',
            scope_user_id  => 'uuid',
            viewer_user_id => 'uuid',
            after_position => 'bigint',
            after_post_id  => 'uuid',
            row_limit      => 'integer'
        ],
    },
    session_lookup => {
        version    => 2,
        parameters => [
            session_id => 'uuid',
            user_id    => 'uuid',
        ],
    },
    session_create => {
        version    => 2,
        parameters => [
            session_id      => 'uuid',
            user_id         => 'uuid',
            session_hash    => 'text',
            created_at      => 'timestamptz',
            last_seen_at    => 'timestamptz',
            expires_at      => 'timestamptz',
            revoked_at      => 'timestamptz',
            ip_hash         => 'text',
            user_agent_hash => 'text',
            retry           => 'boolean',
        ],
    },
    session_validate => {
        version    => 2,
        parameters => [
            session_id             => 'uuid',
            user_id                => 'uuid',
            token_hash             => 'text',
            now                    => 'timestamptz',
            touch_interval_seconds => 'integer',
        ],
    },
    session_revoke => {
        version    => 2,
        parameters => [
            session_id => 'uuid',
            user_id    => 'uuid',
            revoked_at => 'timestamptz',
        ],
    },
    session_live => {
        version    => 2,
        parameters => [
            session_ids => 'uuid[]',
            now         => 'timestamptz',
        ],
    },
    session_revoke_user => {
        version    => 2,
        parameters => [
            user_id         => 'uuid',
            revoked_at      => 'timestamptz',
            keep_session_id => 'uuid',
        ],
    },
    forum_resolve_viewer => {
        version    => 6,
        parameters => [
            user_id => 'uuid',
        ],
        json => ['grants'],
    },
    ops_rate_limit_check => {
        version    => 2,
        parameters => [
            scope          => 'text',
            actor_hash     => 'text',
            action         => 'text',
            window_start   => 'timestamptz',
            window_seconds => 'integer',
            limit          => 'integer',
            now            => 'timestamptz',
            expires_at     => 'timestamptz',
        ],
    },
    ops_rate_limit_snapshot => {
        version    => 2,
        parameters => [
            now => 'timestamptz',
        ],
    },
    moderation_active_suspension => {
        version    => 4,
        parameters => [
            user_id => 'uuid',
            now     => 'timestamptz',
        ],
    },
    moderation_can_participate => {
        version    => 4,
        parameters => [
            user_id => 'uuid',
            now     => 'timestamptz',
        ],
    },
    admin_permission_allowed => {
        version    => 4,
        parameters => [
            user_id       => 'uuid',
            resource_type => 'text',
            action        => 'text',
            resource_id   => 'uuid',
            space_id      => 'uuid',
        ],
    },
    notification_list_inbox => {
        version    => 6,
        parameters => [
            recipient_user_id     => 'uuid',
            filter_sources        => 'boolean',
            member                => 'boolean',
            global_read           => 'boolean',
            viewer_user_id        => 'uuid',
            category_ids          => 'uuid[]',
            space_ids             => 'uuid[]',
            after_created_at      => 'timestamptz',
            after_notification_id => 'uuid',
            row_limit             => 'integer'
        ],
    },
    notification_unread_count => {
        version    => 6,
        parameters => [
            recipient_user_id => 'uuid',
            filter_sources    => 'boolean',
            member            => 'boolean',
            global_read       => 'boolean',
            viewer_user_id    => 'uuid',
            category_ids      => 'uuid[]',
            space_ids         => 'uuid[]'
        ]
    },
    forum_store_write => {
        version    => 2,
        parameters =>
          [ store_type => 'text', command => 'jsonb', record => 'jsonb' ],
        json => ['stored'],
    },
    forum_write_command => {
        version    => 4,
        parameters => [
            log            => 'jsonb',
            answer         => 'jsonb',
            store_type     => 'text',
            command        => 'jsonb',
            record         => 'jsonb',
            draft_id       => 'uuid',
            draft_revision => 'bigint',
        ],
        json => [qw(response stored)],
    },
    forum_find_category => {
        version    => 2,
        parameters => [ category_id => 'uuid' ],
    },
    forum_list_categories => {
        version    => 4,
        parameters => [
            member       => 'boolean',
            global_read  => 'boolean',
            category_ids => 'uuid[]',
            space_ids    => 'uuid[]',
            row_limit    => 'integer'
        ],
    },
    forum_list_category_threads => {
        version    => 2,
        parameters => [
            category_id     => 'uuid',
            member          => 'boolean',
            global_read     => 'boolean',
            scope_user_id   => 'uuid',
            viewer_user_id  => 'uuid',
            after_pinned    => 'boolean',
            after_activity  => 'timestamptz',
            after_thread_id => 'uuid',
            row_limit       => 'integer'
        ],
    },
    forum_list_public_threads => {
        version    => 2,
        parameters => [
            member          => 'boolean',
            global_read     => 'boolean',
            category_ids    => 'uuid[]',
            space_ids       => 'uuid[]',
            after_activity  => 'timestamptz',
            after_thread_id => 'uuid',
            row_limit       => 'integer'
        ],
    },
    forum_find_post => {
        version    => 2,
        parameters => [ post_id => 'uuid' ],
    },
    forum_post_context => {
        version    => 2,
        parameters => [ post_id => 'uuid' ],
        json       => [qw(post thread)],
    },
    forum_find_visible_post => {
        version    => 2,
        parameters => [ post_id => 'uuid' ],
    },
    forum_find_listed_post => {
        version    => 2,
        parameters => [
            post_id        => 'uuid',
            thread_id      => 'uuid',
            member         => 'boolean',
            global_read    => 'boolean',
            scope_user_id  => 'uuid',
            viewer_user_id => 'uuid'
        ],
    },
    forum_thread_placement => {
        version    => 2,
        parameters => [ source_id => 'uuid' ],
    },
    forum_post_placement => {
        version    => 2,
        parameters => [ source_id => 'uuid' ],
    },
    forum_thread_page_head => {
        version    => 2,
        parameters => [ thread_id => 'uuid' ],
    },
    forum_thread_page_posts => {
        version    => 4,
        parameters => [
            thread_id      => 'uuid',
            standing       => 'text',
            viewer_user_id => 'uuid',
            after_position => 'bigint',
            after_post_id  => 'uuid',
            row_limit      => 'integer',
        ],
    },

    # Migration 124: the seven reads a thread page makes once it has its
    # posts, in one call (GPForum::Service::Forum::ThreadPageReads).
    forum_thread_page_reads => {
        version    => 4,
        parameters => [
            thread_id              => 'uuid',
            post_ids               => 'uuid[]',
            viewer_user_id         => 'uuid',
            engagement_target_type => 'text',
            link_target_type       => 'text',
            link_post_ids          => 'uuid[]',
            link_row_limit         => 'integer',
        ],
    },
    forum_create_reply => {
        version    => 4,
        parameters => [
            idempotency_key        => 'text',
            command_type           => 'text',
            actor_id               => 'text',
            request_hash           => 'text',
            command_id             => 'text',
            command_correlation_id => 'text',
            command_at             => 'text',
            answer                 => 'jsonb',
            store_refusals         => 'jsonb',
            @REPLY_COMMAND,
            @REPLY_RECORD,
            draft_id       => 'uuid',
            draft_revision => 'bigint',
        ],
        json => ['response'],
    },
);

has entries => sub { return \%FUNCTION; };

sub names ($self) {
    return [ sort keys %{ $self->entries } ];
}

# The entry for a name: { name, version, function (api.NAME_vN), names,
# types, sql, json }, built once per catalogue. An unknown name is a
# caller's mistake.
sub function ( $self, $name ) {
    return $self->{built}{ $name // q{} } //=
      _built( $name, $self->entries );
}

sub _built ( $name, $entries ) {
    if ( !defined $name || !exists $entries->{$name} ) {
        GPForum::X::Argument->throw(
            message => 'unknown SQL function: ' . ( $name // q{} ) );
    }

    my $entry = $entries->{$name};
    my @pairs = @{ $entry->{parameters} };
    my ( @names, @types );
    while (@pairs) {
        push @names, shift @pairs;
        push @types, shift @pairs;
    }
    my $function = "api.${name}_v$entry->{version}";

    return {
        function => $function,
        json     => { map { $_ => 1 } @{ _listed( $entry, 'json' ) } },
        name     => $name,
        names    => \@names,
        sql      => "SELECT * FROM $function("
          . join( q{, }, map { "?::$_" } @types ) . ')',
        types   => \@types,
        version => $entry->{version},
    };
}

# A list an entry may leave out. The default entries are a Const::Fast hash,
# where reading a key that is not there dies.
sub _listed ( $entry, $key ) {
    return exists $entry->{$key} ? $entry->{$key} : [];
}

1;

__END__

=head1 NAME

GPForum::Infrastructure::SqlFunctionCatalogue - The PostgreSQL functions this release calls, and their versions.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $catalogue = GPForum::Infrastructure::SqlFunctionCatalogue->new;
    my $entry     = $catalogue->function('forum_thread_page_head');
    # $entry->{function}: api.forum_thread_page_head_v1
    # $entry->{sql}:      SELECT * FROM api.forum_thread_page_head_v1(?::uuid)

=head1 DESCRIPTION

ADR 0126 moves every statement into a function in schema C<api>, created by
a numbered migration and never changed after it ships: a change is the next
version, C<api.NAME_vN+1>. This module is the one place a release says which
version of each function it calls, with the function's parameters in order,
named and typed. L<GPForum::Infrastructure::SqlFunction> binds a call's
values by these names and casts each to its type in the statement it builds
from the entry, once per process.

=head1 SUBROUTINES/METHODS

=head2 entries

The functions listed, by name: C<version>, C<parameters> (name and type,
in order) and C<json> (the result columns that hold a json document). A
test gives its own.

=head2 names

The names of the functions listed, sorted.

=head2 function

The entry for a name: C<name>, C<version>, C<function> (the qualified
function name), C<names> and C<types> (the parameters, in order), C<sql>
(the call, C<SELECT * FROM api.NAME_vN(?::type, ...)>) and C<json> (a hash
of the result columns that hold a json document).

=head1 DIAGNOSTICS

L</function> throws L<GPForum::X::Argument> for a name that is not listed.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<Const::Fast>, L<Mojo::Base>, L<GPForum::X::Argument>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

None known.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause
license.

=cut
