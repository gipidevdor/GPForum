-- SPDX-FileCopyrightText: 2026 GPForum Contributors
-- SPDX-License-Identifier: BSD-3-Clause

-- Fresh-database baseline: moderation.
-- Final definitions only; see migrations/README.md for the dependency order.

BEGIN;
SET LOCAL lock_timeout = '1s';

CREATE TABLE public.reports (
    report_id uuid NOT NULL,
    reporter_user_id uuid,
    target_type text NOT NULL,
    target_id uuid NOT NULL,
    reason text NOT NULL,
    details text NOT NULL DEFAULT '',
    status text NOT NULL DEFAULT 'open',
    assigned_moderator_user_id uuid,
    created_at timestamptz NOT NULL DEFAULT now(),
    resolved_at timestamptz,
    resolution text,
    CONSTRAINT reports_resolved_after_created_check CHECK ((resolved_at IS NULL) OR (resolved_at >= created_at)),
    CONSTRAINT reports_status_check CHECK (status IN ('open', 'triaged', 'resolved', 'rejected')),
    CONSTRAINT reports_target_type_check CHECK (target_type IN ('thread', 'post', 'user', 'message')),
    CONSTRAINT reports_pkey PRIMARY KEY (report_id)
);
COMMENT ON TABLE public.reports IS 'A report to the staff about a thread, a post or a member.';

CREATE INDEX idx_reports_queue ON public.reports (status, created_at, report_id);

CREATE UNIQUE INDEX idx_reports_reporter_target_open_unique ON public.reports (reporter_user_id, target_type, target_id) WHERE status IN ('open', 'triaged');

CREATE TABLE public.moderation_actions (
    moderation_action_id uuid NOT NULL,
    actor_user_id uuid NOT NULL,
    action_type text NOT NULL,
    target_type text NOT NULL,
    target_id uuid NOT NULL,
    reason text NOT NULL,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    reversed_at timestamptz,
    reversed_by_user_id uuid,
    command_id uuid,
    CONSTRAINT moderation_actions_reversed_after_created_check CHECK ((reversed_at IS NULL) OR (reversed_at >= created_at)),
    CONSTRAINT moderation_actions_target_type_check CHECK (target_type IN ('thread', 'post', 'user')),
    CONSTRAINT moderation_actions_pkey PRIMARY KEY (moderation_action_id)
);
COMMENT ON TABLE public.moderation_actions IS 'What staff did to a thread, a post or a member, and its reversal; one action per command.';

CREATE UNIQUE INDEX idx_moderation_actions_command_id ON public.moderation_actions (command_id) WHERE command_id IS NOT NULL;

CREATE INDEX idx_moderation_actions_target ON public.moderation_actions (target_type, target_id, created_at DESC);

CREATE TABLE public.suspensions (
    suspension_id uuid NOT NULL,
    user_id uuid NOT NULL,
    actor_user_id uuid NOT NULL,
    reason text NOT NULL,
    valid_from timestamptz NOT NULL DEFAULT now(),
    valid_to timestamptz,
    revoked_at timestamptz,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    CONSTRAINT suspensions_revoked_after_valid_from_check CHECK ((revoked_at IS NULL) OR (revoked_at >= valid_from)),
    CONSTRAINT suspensions_valid_range_check CHECK ((valid_to IS NULL) OR (valid_to >= valid_from)),
    CONSTRAINT suspensions_pkey PRIMARY KEY (suspension_id)
);
COMMENT ON TABLE public.suspensions IS 'A member''s suspension, from when to when, until revoked.';

CREATE INDEX idx_suspensions_active ON public.suspensions (user_id, valid_from, valid_to) WHERE revoked_at IS NULL;

CREATE TABLE public.watched_words (
    word_id uuid NOT NULL,
    phrase text NOT NULL,
    action text NOT NULL,
    replacement text NOT NULL DEFAULT '',
    created_by_user_id uuid,
    created_at timestamptz NOT NULL,
    CONSTRAINT watched_words_action_check CHECK (action IN ('block', 'flag', 'replace')),
    CONSTRAINT watched_words_phrase_check CHECK ((length(phrase) >= 1) AND (length(phrase) <= 100)),
    CONSTRAINT watched_words_replacement_check CHECK (length(replacement) <= 100),
    CONSTRAINT watched_words_phrase_key UNIQUE (phrase),
    CONSTRAINT watched_words_pkey PRIMARY KEY (word_id)
);
COMMENT ON TABLE public.watched_words IS 'The words and phrases staff watch for in new content: blocked, flagged or replaced.';

CREATE TABLE public.automod_settings (
    singleton boolean NOT NULL DEFAULT true,
    link_limit integer,
    link_trust_below integer NOT NULL DEFAULT 1,
    link_action text NOT NULL DEFAULT 'block',
    updated_by_user_id uuid,
    updated_at timestamptz NOT NULL,
    review_first_posts integer NOT NULL DEFAULT 0,
    review_flagged boolean NOT NULL DEFAULT false,
    CONSTRAINT automod_settings_link_action_check CHECK (link_action IN ('block', 'flag')),
    CONSTRAINT automod_settings_link_limit_check CHECK ((link_limit IS NULL) OR ((link_limit >= 0) AND (link_limit <= 100))),
    CONSTRAINT automod_settings_link_trust_below_check CHECK ((link_trust_below >= 0) AND (link_trust_below <= 100)),
    CONSTRAINT automod_settings_review_first_posts_check CHECK ((review_first_posts >= 0) AND (review_first_posts <= 20)),
    CONSTRAINT automod_settings_singleton_check CHECK (singleton),
    CONSTRAINT automod_settings_pkey PRIMARY KEY (singleton)
);
COMMENT ON TABLE public.automod_settings IS 'The automod link rule and the review queue switches: one row (singleton).';

CREATE TABLE public.held_posts (
    review_id uuid NOT NULL,
    author_user_id uuid NOT NULL,
    command_id text NOT NULL,
    kind text NOT NULL,
    category_id uuid,
    thread_id uuid,
    title text NOT NULL DEFAULT '',
    body_source text NOT NULL,
    body_rendered_safe text NOT NULL,
    visibility text,
    reply_to_post_id uuid,
    reason text NOT NULL,
    details jsonb NOT NULL DEFAULT '{}'::jsonb,
    status text NOT NULL DEFAULT 'pending',
    decided_by_user_id uuid,
    decided_at timestamptz,
    decision_reason text NOT NULL DEFAULT '',
    post_id uuid,
    created_at timestamptz NOT NULL,
    tags text NOT NULL DEFAULT '',
    CONSTRAINT held_posts_body_source_length_check CHECK (char_length(body_source) <= 50000),
    CONSTRAINT held_posts_command_id_check CHECK ((length(command_id) >= 1) AND (length(command_id) <= 200)),
    CONSTRAINT held_posts_decision_check CHECK (((status = 'pending') AND (decided_at IS NULL)) OR ((status <> 'pending') AND (decided_at IS NOT NULL))),
    CONSTRAINT held_posts_decision_reason_check CHECK (length(decision_reason) <= 500),
    CONSTRAINT held_posts_kind_check CHECK (((kind = 'thread') AND (category_id IS NOT NULL) AND (length(title) > 0)) OR ((kind = 'reply') AND (thread_id IS NOT NULL))),
    CONSTRAINT held_posts_published_check CHECK ((status <> 'approved') OR (post_id IS NOT NULL)),
    CONSTRAINT held_posts_reason_check CHECK (reason IN ('first_posts', 'flagged')),
    CONSTRAINT held_posts_status_check CHECK (status IN ('pending', 'approved', 'rejected', 'withdrawn')),
    CONSTRAINT held_posts_tags_check CHECK ((length(tags) <= 200) AND ((kind = 'thread') OR (tags = ''))),
    CONSTRAINT held_posts_title_check CHECK (length(title) <= 300),
    CONSTRAINT held_posts_visibility_check CHECK ((visibility IS NULL) OR (visibility IN ('public', 'members', 'private'))),
    CONSTRAINT held_posts_command_key UNIQUE (author_user_id, command_id),
    CONSTRAINT held_posts_pkey PRIMARY KEY (review_id)
);
COMMENT ON TABLE public.held_posts IS 'A post held for review before it is published: outside threads and posts until staff approve or reject it.';

CREATE INDEX idx_held_posts_author ON public.held_posts (author_user_id, created_at DESC, review_id DESC);

CREATE INDEX idx_held_posts_pending ON public.held_posts (created_at, review_id) WHERE status = 'pending';

CREATE TABLE public.member_notes (
    note_id uuid NOT NULL,
    subject_user_id uuid NOT NULL,
    author_user_id uuid,
    body text NOT NULL,
    created_at timestamptz NOT NULL,
    updated_at timestamptz,
    updated_by_user_id uuid,
    CONSTRAINT member_notes_body_check CHECK ((length(body) >= 1) AND (length(body) <= 2000)),
    CONSTRAINT member_notes_pkey PRIMARY KEY (note_id)
);
COMMENT ON TABLE public.member_notes IS 'Staff''s private notes about a member, never shown to the member.';

CREATE INDEX idx_member_notes_author ON public.member_notes (author_user_id);

CREATE INDEX idx_member_notes_subject ON public.member_notes (subject_user_id, created_at DESC, note_id DESC);

CREATE INDEX idx_member_notes_updated_by ON public.member_notes (updated_by_user_id);

COMMIT;
