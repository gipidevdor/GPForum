-- SPDX-FileCopyrightText: 2026 GPForum Contributors
-- SPDX-License-Identifier: BSD-3-Clause

-- Fresh-database baseline: relations.
-- Final definitions only; see migrations/README.md for the dependency order.

BEGIN;
SET LOCAL lock_timeout = '1s';

ALTER TABLE public.address_bans
    ADD CONSTRAINT address_bans_created_by_user_id_fkey FOREIGN KEY (created_by_user_id) REFERENCES public.users(id) ON DELETE SET NULL;

ALTER TABLE public.address_bans
    ADD CONSTRAINT address_bans_lifted_by_user_id_fkey FOREIGN KEY (lifted_by_user_id) REFERENCES public.users(id) ON DELETE SET NULL;

ALTER TABLE public.address_bans
    ADD CONSTRAINT address_bans_updated_by_user_id_fkey FOREIGN KEY (updated_by_user_id) REFERENCES public.users(id) ON DELETE SET NULL;

ALTER TABLE public.attachment_content_blocks
    ADD CONSTRAINT attachment_content_blocks_blocked_by_fkey FOREIGN KEY (blocked_by) REFERENCES public.users(id);

ALTER TABLE public.attachment_content_reviews
    ADD CONSTRAINT attachment_content_reviews_attachment_id_fkey FOREIGN KEY (attachment_id) REFERENCES public.attachments(attachment_id) ON DELETE CASCADE;

ALTER TABLE public.attachment_content_reviews
    ADD CONSTRAINT attachment_content_reviews_reviewed_by_fkey FOREIGN KEY (reviewed_by) REFERENCES public.users(id);

ALTER TABLE public.attachment_links
    ADD CONSTRAINT attachment_links_attachment_id_fkey FOREIGN KEY (attachment_id) REFERENCES public.attachments(attachment_id);

ALTER TABLE public.attachment_object_chunks
    ADD CONSTRAINT attachment_object_chunks_object_key_fkey FOREIGN KEY (object_key) REFERENCES public.attachment_objects(object_key) ON DELETE CASCADE;

ALTER TABLE public.attachment_objects
    ADD CONSTRAINT attachment_objects_attachment_id_fkey FOREIGN KEY (attachment_id) REFERENCES public.attachments(attachment_id) ON DELETE CASCADE;

ALTER TABLE public.attachment_variants
    ADD CONSTRAINT attachment_variants_attachment_id_fkey FOREIGN KEY (attachment_id) REFERENCES public.attachments(attachment_id);

ALTER TABLE public.attachments
    ADD CONSTRAINT attachments_owner_user_id_fkey FOREIGN KEY (owner_user_id) REFERENCES public.users(id);

ALTER TABLE public.automod_settings
    ADD CONSTRAINT automod_settings_updated_by_user_id_fkey FOREIGN KEY (updated_by_user_id) REFERENCES public.users(id) ON DELETE SET NULL;

ALTER TABLE public.bookmark_folders
    ADD CONSTRAINT bookmark_folders_bookmark_id_fkey FOREIGN KEY (bookmark_id) REFERENCES public.bookmarks(bookmark_id) ON DELETE CASCADE;

ALTER TABLE public.bookmarks
    ADD CONSTRAINT bookmarks_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);

ALTER TABLE public.categories
    ADD CONSTRAINT categories_space_id_fkey FOREIGN KEY (space_id) REFERENCES public.spaces(space_id);

ALTER TABLE public.credentials
    ADD CONSTRAINT credentials_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);

ALTER TABLE public.deletion_actions
    ADD CONSTRAINT deletion_actions_request_id_fkey FOREIGN KEY (deletion_request_id) REFERENCES public.deletion_requests(deletion_request_id);

ALTER TABLE public.deletion_requests
    ADD CONSTRAINT deletion_requests_requester_user_id_fkey FOREIGN KEY (requester_user_id) REFERENCES public.users(id);

ALTER TABLE public.direct_conversation_members
    ADD CONSTRAINT direct_conversation_members_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES public.direct_conversations(conversation_id) ON DELETE CASCADE;

ALTER TABLE public.direct_conversation_members
    ADD CONSTRAINT direct_conversation_members_other_user_id_fkey FOREIGN KEY (other_user_id) REFERENCES public.users(id) ON DELETE CASCADE;

ALTER TABLE public.direct_conversation_members
    ADD CONSTRAINT direct_conversation_members_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;

ALTER TABLE public.direct_conversations
    ADD CONSTRAINT direct_conversations_first_user_id_fkey FOREIGN KEY (first_user_id) REFERENCES public.users(id) ON DELETE CASCADE;

ALTER TABLE public.direct_conversations
    ADD CONSTRAINT direct_conversations_second_user_id_fkey FOREIGN KEY (second_user_id) REFERENCES public.users(id) ON DELETE CASCADE;

ALTER TABLE public.direct_conversations
    ADD CONSTRAINT direct_conversations_started_by_user_id_fkey FOREIGN KEY (started_by_user_id) REFERENCES public.users(id) ON DELETE SET NULL;

ALTER TABLE public.direct_messages
    ADD CONSTRAINT direct_messages_author_user_id_fkey FOREIGN KEY (author_user_id) REFERENCES public.users(id) ON DELETE CASCADE;

ALTER TABLE public.direct_messages
    ADD CONSTRAINT direct_messages_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES public.direct_conversations(conversation_id) ON DELETE CASCADE;

ALTER TABLE public.erasure_jobs
    ADD CONSTRAINT erasure_jobs_request_id_fkey FOREIGN KEY (deletion_request_id) REFERENCES public.deletion_requests(deletion_request_id);

ALTER TABLE public.export_requests
    ADD CONSTRAINT export_requests_requester_user_id_fkey FOREIGN KEY (requester_user_id) REFERENCES public.users(id);

ALTER TABLE public.export_requests
    ADD CONSTRAINT export_requests_subject_user_id_fkey FOREIGN KEY (subject_user_id) REFERENCES public.users(id);

ALTER TABLE public.forum_drafts
    ADD CONSTRAINT forum_drafts_owner_user_id_fkey FOREIGN KEY (owner_user_id) REFERENCES public.users(id) ON DELETE CASCADE;

ALTER TABLE public.held_posts
    ADD CONSTRAINT held_posts_author_user_id_fkey FOREIGN KEY (author_user_id) REFERENCES public.users(id) ON DELETE CASCADE;

ALTER TABLE public.held_posts
    ADD CONSTRAINT held_posts_decided_by_user_id_fkey FOREIGN KEY (decided_by_user_id) REFERENCES public.users(id) ON DELETE SET NULL;

ALTER TABLE public.identity_tokens
    ADD CONSTRAINT identity_tokens_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);

ALTER TABLE public.member_avatars
    ADD CONSTRAINT member_avatars_attachment_id_fkey FOREIGN KEY (attachment_id) REFERENCES public.attachments(attachment_id);

ALTER TABLE public.member_avatars
    ADD CONSTRAINT member_avatars_pending_attachment_id_fkey FOREIGN KEY (pending_attachment_id) REFERENCES public.attachments(attachment_id);

ALTER TABLE public.member_avatars
    ADD CONSTRAINT member_avatars_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;

ALTER TABLE public.member_notes
    ADD CONSTRAINT member_notes_author_user_id_fkey FOREIGN KEY (author_user_id) REFERENCES public.users(id) ON DELETE SET NULL;

ALTER TABLE public.member_notes
    ADD CONSTRAINT member_notes_subject_user_id_fkey FOREIGN KEY (subject_user_id) REFERENCES public.users(id) ON DELETE CASCADE;

ALTER TABLE public.member_notes
    ADD CONSTRAINT member_notes_updated_by_user_id_fkey FOREIGN KEY (updated_by_user_id) REFERENCES public.users(id) ON DELETE SET NULL;

ALTER TABLE public.member_relations
    ADD CONSTRAINT member_relations_other_user_id_fkey FOREIGN KEY (other_user_id) REFERENCES public.users(id) ON DELETE CASCADE;

ALTER TABLE public.member_relations
    ADD CONSTRAINT member_relations_owner_user_id_fkey FOREIGN KEY (owner_user_id) REFERENCES public.users(id) ON DELETE CASCADE;

ALTER TABLE public.mentions
    ADD CONSTRAINT mentions_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES public.users(id);

ALTER TABLE public.mentions
    ADD CONSTRAINT mentions_mentioned_user_id_fkey FOREIGN KEY (mentioned_user_id) REFERENCES public.users(id);

ALTER TABLE public.moderation_actions
    ADD CONSTRAINT moderation_actions_actor_user_id_fkey FOREIGN KEY (actor_user_id) REFERENCES public.users(id);

ALTER TABLE public.moderation_actions
    ADD CONSTRAINT moderation_actions_reversed_by_user_id_fkey FOREIGN KEY (reversed_by_user_id) REFERENCES public.users(id);

ALTER TABLE public.notification_digests
    ADD CONSTRAINT notification_digests_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;

ALTER TABLE public.notification_inbox
    ADD CONSTRAINT notification_inbox_recipient_user_id_fkey FOREIGN KEY (recipient_user_id) REFERENCES public.users(id);

ALTER TABLE public.notification_preferences
    ADD CONSTRAINT notification_preferences_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);

ALTER TABLE public.notification_reads
    ADD CONSTRAINT notification_reads_recipient_user_id_fkey FOREIGN KEY (recipient_user_id) REFERENCES public.users(id);

ALTER TABLE public.notification_type_preferences
    ADD CONSTRAINT notification_type_preferences_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;

ALTER TABLE public.notifications
    ADD CONSTRAINT notifications_recipient_user_id_fkey FOREIGN KEY (recipient_user_id) REFERENCES public.users(id);

ALTER TABLE public.poll_ballot_extra_choices
    ADD CONSTRAINT poll_ballot_extra_choices_thread_id_option_number_fkey FOREIGN KEY (thread_id, option_number) REFERENCES public.poll_options(thread_id, option_number);

ALTER TABLE public.poll_ballot_extra_choices
    ADD CONSTRAINT poll_ballot_extra_choices_thread_id_user_id_fkey FOREIGN KEY (thread_id, user_id) REFERENCES public.poll_ballots(thread_id, user_id) ON DELETE CASCADE;

ALTER TABLE public.poll_ballots
    ADD CONSTRAINT poll_ballots_thread_id_option_number_fkey FOREIGN KEY (thread_id, option_number) REFERENCES public.poll_options(thread_id, option_number);

ALTER TABLE public.poll_ballots
    ADD CONSTRAINT poll_ballots_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;

ALTER TABLE public.poll_options
    ADD CONSTRAINT poll_options_thread_id_fkey FOREIGN KEY (thread_id) REFERENCES public.thread_polls(thread_id);

ALTER TABLE public.post_bodies
    ADD CONSTRAINT post_bodies_post_id_fkey FOREIGN KEY (post_id) REFERENCES public.posts(post_id);

ALTER TABLE public.post_likes
    ADD CONSTRAINT post_likes_post_id_fkey FOREIGN KEY (post_id) REFERENCES public.posts(post_id);

ALTER TABLE public.post_likes
    ADD CONSTRAINT post_likes_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);

ALTER TABLE public.post_reactions
    ADD CONSTRAINT post_reactions_post_id_fkey FOREIGN KEY (post_id) REFERENCES public.posts(post_id);

ALTER TABLE public.post_reactions
    ADD CONSTRAINT post_reactions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);

ALTER TABLE public.post_replies
    ADD CONSTRAINT post_replies_post_id_fkey FOREIGN KEY (post_id) REFERENCES public.posts(post_id);

ALTER TABLE public.post_replies
    ADD CONSTRAINT post_replies_reply_to_post_id_fkey FOREIGN KEY (reply_to_post_id) REFERENCES public.posts(post_id);

ALTER TABLE public.post_revisions
    ADD CONSTRAINT post_revisions_body_id_fkey FOREIGN KEY (body_id) REFERENCES public.post_bodies(body_id);

ALTER TABLE public.post_revisions
    ADD CONSTRAINT post_revisions_editor_user_id_fkey FOREIGN KEY (editor_user_id) REFERENCES public.users(id);

ALTER TABLE public.post_revisions
    ADD CONSTRAINT post_revisions_post_id_fkey FOREIGN KEY (post_id) REFERENCES public.posts(post_id);

ALTER TABLE public.post_signatures
    ADD CONSTRAINT post_signatures_body_id_fkey FOREIGN KEY (body_id) REFERENCES public.post_bodies(body_id) ON DELETE CASCADE;

ALTER TABLE public.posts
    ADD CONSTRAINT posts_author_user_id_fkey FOREIGN KEY (author_user_id) REFERENCES public.users(id);

ALTER TABLE public.posts
    ADD CONSTRAINT posts_current_body_id_fkey FOREIGN KEY (current_body_id) REFERENCES public.post_bodies(body_id) DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE public.posts
    ADD CONSTRAINT posts_current_revision_id_fkey FOREIGN KEY (current_revision_id) REFERENCES public.post_revisions(revision_id) DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE public.posts
    ADD CONSTRAINT posts_deleted_by_fkey FOREIGN KEY (deleted_by) REFERENCES public.users(id);

ALTER TABLE public.posts
    ADD CONSTRAINT posts_thread_id_fkey FOREIGN KEY (thread_id) REFERENCES public.threads(thread_id);

ALTER TABLE public.registration_invitations
    ADD CONSTRAINT registration_invitations_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id) ON DELETE SET NULL;

ALTER TABLE public.registration_invitations
    ADD CONSTRAINT registration_invitations_used_by_fkey FOREIGN KEY (used_by) REFERENCES public.users(id) ON DELETE SET NULL;

ALTER TABLE public.registration_policy
    ADD CONSTRAINT registration_policy_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id) ON DELETE SET NULL;

ALTER TABLE public.registration_reviews
    ADD CONSTRAINT registration_reviews_decided_by_fkey FOREIGN KEY (decided_by) REFERENCES public.users(id) ON DELETE SET NULL;

ALTER TABLE public.registration_reviews
    ADD CONSTRAINT registration_reviews_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;

ALTER TABLE public.reports
    ADD CONSTRAINT reports_assigned_moderator_user_id_fkey FOREIGN KEY (assigned_moderator_user_id) REFERENCES public.users(id);

ALTER TABLE public.reports
    ADD CONSTRAINT reports_reporter_user_id_fkey FOREIGN KEY (reporter_user_id) REFERENCES public.users(id);

ALTER TABLE public.reputation_events
    ADD CONSTRAINT reputation_events_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES public.users(id);

ALTER TABLE public.reputation_events
    ADD CONSTRAINT reputation_events_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);

ALTER TABLE public.role_bindings
    ADD CONSTRAINT role_bindings_role_id_fkey FOREIGN KEY (role_id) REFERENCES public.roles(role_id);

ALTER TABLE public.role_bindings
    ADD CONSTRAINT role_bindings_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);

ALTER TABLE public.role_permissions
    ADD CONSTRAINT role_permissions_permission_id_fkey FOREIGN KEY (permission_id) REFERENCES public.permissions(permission_id);

ALTER TABLE public.role_permissions
    ADD CONSTRAINT role_permissions_role_id_fkey FOREIGN KEY (role_id) REFERENCES public.roles(role_id);

ALTER TABLE public.second_factor_challenges
    ADD CONSTRAINT second_factor_challenges_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;

ALTER TABLE public.second_factor_policy
    ADD CONSTRAINT second_factor_policy_updated_by_user_id_fkey FOREIGN KEY (updated_by_user_id) REFERENCES public.users(id) ON DELETE SET NULL;

ALTER TABLE public.second_factor_recovery_codes
    ADD CONSTRAINT second_factor_recovery_codes_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;

ALTER TABLE public.second_factors
    ADD CONSTRAINT second_factors_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;

ALTER TABLE public.sessions
    ADD CONSTRAINT sessions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);

ALTER TABLE public.site_announcements
    ADD CONSTRAINT site_announcements_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);

ALTER TABLE public.site_announcements
    ADD CONSTRAINT site_announcements_retired_by_fkey FOREIGN KEY (retired_by) REFERENCES public.users(id);

ALTER TABLE public.subscriptions
    ADD CONSTRAINT subscriptions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);

ALTER TABLE public.suspensions
    ADD CONSTRAINT suspensions_actor_user_id_fkey FOREIGN KEY (actor_user_id) REFERENCES public.users(id);

ALTER TABLE public.suspensions
    ADD CONSTRAINT suspensions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);

ALTER TABLE public.thread_counters
    ADD CONSTRAINT thread_counters_thread_id_fkey FOREIGN KEY (thread_id) REFERENCES public.threads(thread_id);

ALTER TABLE public.thread_polls
    ADD CONSTRAINT thread_polls_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id) ON DELETE SET NULL;

ALTER TABLE public.thread_polls
    ADD CONSTRAINT thread_polls_thread_id_fkey FOREIGN KEY (thread_id) REFERENCES public.threads(thread_id);

ALTER TABLE public.thread_read_state
    ADD CONSTRAINT thread_read_state_thread_id_fkey FOREIGN KEY (thread_id) REFERENCES public.threads(thread_id);

ALTER TABLE public.thread_read_state
    ADD CONSTRAINT thread_read_state_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);

ALTER TABLE public.thread_tags
    ADD CONSTRAINT thread_tags_tag_id_fkey FOREIGN KEY (tag_id) REFERENCES public.tags(tag_id);

ALTER TABLE public.thread_tags
    ADD CONSTRAINT thread_tags_thread_id_fkey FOREIGN KEY (thread_id) REFERENCES public.threads(thread_id);

ALTER TABLE public.thread_transfers
    ADD CONSTRAINT thread_transfers_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES public.users(id) ON DELETE SET NULL;

ALTER TABLE public.thread_transfers
    ADD CONSTRAINT thread_transfers_source_id_fkey FOREIGN KEY (source_id) REFERENCES public.threads(thread_id);

ALTER TABLE public.thread_transfers
    ADD CONSTRAINT thread_transfers_target_id_fkey FOREIGN KEY (target_id) REFERENCES public.threads(thread_id);

ALTER TABLE public.threads
    ADD CONSTRAINT threads_author_user_id_fkey FOREIGN KEY (author_user_id) REFERENCES public.users(id);

ALTER TABLE public.threads
    ADD CONSTRAINT threads_category_id_fkey FOREIGN KEY (category_id) REFERENCES public.categories(category_id);

ALTER TABLE public.threads
    ADD CONSTRAINT threads_deleted_by_fkey FOREIGN KEY (deleted_by) REFERENCES public.users(id);

ALTER TABLE public.trust_score_snapshots
    ADD CONSTRAINT trust_score_snapshots_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);

ALTER TABLE public.user_feed_items
    ADD CONSTRAINT user_feed_items_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);

ALTER TABLE public.user_read_marker_deltas
    ADD CONSTRAINT user_read_marker_deltas_thread_id_fkey FOREIGN KEY (thread_id) REFERENCES public.threads(thread_id);

ALTER TABLE public.user_read_marker_deltas
    ADD CONSTRAINT user_read_marker_deltas_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);

ALTER TABLE public.watched_words
    ADD CONSTRAINT watched_words_created_by_user_id_fkey FOREIGN KEY (created_by_user_id) REFERENCES public.users(id) ON DELETE SET NULL;

COMMIT;
