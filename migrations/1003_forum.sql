-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

-- Spaces, categories, threads, posts with their bodies and revisions, and what
-- readers keep of them: read positions, tags, drafts. A post's text is in
-- post_bodies and its count in thread_counters, so the rows a page lists stay
-- narrow and the rows a reply updates stay small.

BEGIN;
SET LOCAL lock_timeout = '1s';

-- The top level of the forum: groups of categories with their own visibility.
-- autovacuum_analyze_threshold 0: spaces change rarely, and the search planner
-- needs their statistics from the first change.
CREATE TABLE public.spaces (
    space_id uuid NOT NULL,
    slug text NOT NULL,
    title text NOT NULL,
    description text NOT NULL DEFAULT '',
    visibility text NOT NULL DEFAULT 'public',
    position integer NOT NULL DEFAULT 0,
    version bigint NOT NULL DEFAULT 1,
    permission_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    CONSTRAINT spaces_pkey PRIMARY KEY (space_id),
    CONSTRAINT spaces_slug_key UNIQUE (slug),
    CONSTRAINT spaces_permission_version_check CHECK (permission_version > 0),
    CONSTRAINT spaces_version_check CHECK (version > 0),
    CONSTRAINT spaces_visibility_check CHECK (visibility IN ('public', 'members', 'private'))
)
WITH (autovacuum_analyze_threshold = 0);
COMMENT ON TABLE public.spaces IS 'The top level of the forum: groups of categories with their own visibility.';

-- A category of threads within a space. autovacuum_analyze_threshold 0, as for
-- spaces.
CREATE TABLE public.categories (
    category_id uuid NOT NULL,
    space_id uuid NOT NULL,
    slug text NOT NULL,
    title text NOT NULL,
    description text NOT NULL DEFAULT '',
    visibility text NOT NULL DEFAULT 'public',
    position integer NOT NULL DEFAULT 0,
    version bigint NOT NULL DEFAULT 1,
    permission_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    CONSTRAINT categories_pkey PRIMARY KEY (category_id),
    CONSTRAINT categories_space_slug_key UNIQUE (space_id, slug),
    CONSTRAINT categories_space_id_fkey FOREIGN KEY (space_id) REFERENCES public.spaces (space_id),
    CONSTRAINT categories_permission_version_check CHECK (permission_version > 0),
    CONSTRAINT categories_version_check CHECK (version > 0),
    CONSTRAINT categories_visibility_check CHECK (visibility IN ('public', 'members', 'private'))
)
WITH (autovacuum_analyze_threshold = 0);
CREATE INDEX idx_categories_space_position
    ON public.categories (space_id, "position")
    WHERE deleted_at IS NULL;
COMMENT ON TABLE public.categories IS 'A category of threads within a space.';

-- A thread: its category, author, title, state and last activity. The partial
-- covering indexes serve the category list, the latest threads and the public
-- profile, each in its keyset order; fillfactor 90 leaves room for the
-- last-activity update.
CREATE TABLE public.threads (
    thread_id uuid NOT NULL,
    category_id uuid NOT NULL,
    author_user_id uuid NOT NULL,
    title text NOT NULL,
    slug text NOT NULL,
    pinned boolean NOT NULL DEFAULT false,
    visibility text NOT NULL DEFAULT 'public',
    moderation_state text NOT NULL DEFAULT 'visible',
    locked_at timestamptz,
    last_activity_at timestamptz NOT NULL DEFAULT now(),
    version bigint NOT NULL DEFAULT 1,
    visibility_version bigint NOT NULL DEFAULT 1,
    permission_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    deleted_by uuid,
    CONSTRAINT threads_pkey PRIMARY KEY (thread_id),
    CONSTRAINT threads_author_user_id_fkey FOREIGN KEY (author_user_id) REFERENCES public.users (id),
    CONSTRAINT threads_category_id_fkey FOREIGN KEY (category_id) REFERENCES public.categories (category_id),
    CONSTRAINT threads_deleted_by_fkey FOREIGN KEY (deleted_by) REFERENCES public.users (id),
    CONSTRAINT threads_moderation_state_check CHECK (moderation_state IN ('visible', 'hidden', 'locked', 'deleted')),
    CONSTRAINT threads_permission_version_check CHECK (permission_version > 0),
    CONSTRAINT threads_version_check CHECK (version > 0),
    CONSTRAINT threads_visibility_check CHECK (visibility IN ('public', 'members', 'private')),
    CONSTRAINT threads_visibility_version_check CHECK (visibility_version > 0)
)
WITH (fillfactor = 90);
CREATE INDEX idx_threads_author_public_activity
    ON public.threads (author_user_id, last_activity_at DESC, thread_id DESC)
    INCLUDE (category_id, title, slug, created_at)
    WHERE deleted_at IS NULL
      AND moderation_state IN ('visible', 'locked')
      AND visibility = 'public';
CREATE INDEX idx_threads_category_activity_visible_locked
    ON public.threads (category_id, pinned DESC, last_activity_at DESC, thread_id DESC)
    INCLUDE (title, author_user_id, slug, visibility, moderation_state, created_at)
    WHERE deleted_at IS NULL
      AND moderation_state IN ('visible', 'locked');
CREATE INDEX idx_threads_deleted_category_activity
    ON public.threads (category_id, pinned DESC, last_activity_at DESC, thread_id DESC)
    INCLUDE (author_user_id, visibility, moderation_state)
    WHERE deleted_at IS NOT NULL;
CREATE INDEX idx_threads_public_activity
    ON public.threads (last_activity_at DESC, thread_id DESC)
    INCLUDE (category_id, author_user_id, title, slug, pinned, visibility, moderation_state, created_at)
    WHERE deleted_at IS NULL
      AND visibility = 'public'
      AND moderation_state IN ('visible', 'locked');
COMMENT ON TABLE public.threads IS 'A thread: its category, author, title, state and last activity.';

-- A post: its thread, author, position and state; its text lives in
-- post_bodies. position is unique within a thread and orders the thread page
-- (idx_posts_visible_thread_position, keyset).
CREATE TABLE public.posts (
    post_id uuid NOT NULL,
    thread_id uuid NOT NULL,
    author_user_id uuid NOT NULL,
    current_body_id uuid,
    current_revision_id uuid,
    position bigint NOT NULL,
    visibility text NOT NULL DEFAULT 'public',
    moderation_state text NOT NULL DEFAULT 'visible',
    version bigint NOT NULL DEFAULT 1,
    visibility_version bigint NOT NULL DEFAULT 1,
    permission_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    hidden_at timestamptz,
    locked_at timestamptz,
    deleted_at timestamptz,
    deleted_by uuid,
    CONSTRAINT posts_pkey PRIMARY KEY (post_id),
    CONSTRAINT posts_thread_position_key UNIQUE (thread_id, "position"),
    CONSTRAINT posts_author_user_id_fkey FOREIGN KEY (author_user_id) REFERENCES public.users (id),
    CONSTRAINT posts_deleted_by_fkey FOREIGN KEY (deleted_by) REFERENCES public.users (id),
    CONSTRAINT posts_thread_id_fkey FOREIGN KEY (thread_id) REFERENCES public.threads (thread_id),
    CONSTRAINT posts_moderation_state_check CHECK (moderation_state IN ('visible', 'hidden', 'locked', 'deleted')),
    CONSTRAINT posts_permission_version_check CHECK (permission_version > 0),
    CONSTRAINT posts_version_check CHECK (version > 0),
    CONSTRAINT posts_visibility_check CHECK (visibility IN ('public', 'members', 'private')),
    CONSTRAINT posts_visibility_version_check CHECK (visibility_version > 0)
);
CREATE INDEX idx_posts_author_created
    ON public.posts (author_user_id, created_at DESC, post_id DESC);
CREATE INDEX idx_posts_visible_thread_position
    ON public.posts (thread_id, "position", post_id)
    INCLUDE (author_user_id, current_body_id, current_revision_id, visibility, moderation_state, created_at)
    WHERE deleted_at IS NULL
      AND moderation_state = 'visible';
COMMENT ON TABLE public.posts IS 'A post: its thread, author, position and state; its text lives in post_bodies.';

-- The text of a post, as written and as rendered safe; each edit adds a body.
-- body_source holds at most 50,000 characters.
CREATE TABLE public.post_bodies (
    body_id uuid NOT NULL,
    post_id uuid NOT NULL,
    body_format text NOT NULL DEFAULT 'markdown',
    body_source text NOT NULL,
    body_rendered_safe text NOT NULL,
    source_hash text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT post_bodies_pkey PRIMARY KEY (body_id),
    CONSTRAINT post_bodies_post_id_fkey FOREIGN KEY (post_id) REFERENCES public.posts (post_id),
    CONSTRAINT post_bodies_body_format_check CHECK (body_format IN ('markdown', 'plain')),
    CONSTRAINT post_bodies_body_source_length_check CHECK (char_length(body_source) <= 50000)
);
CREATE INDEX idx_post_bodies_post
    ON public.post_bodies (post_id);
COMMENT ON TABLE public.post_bodies IS 'The text of a post, as written and as rendered safe; each edit adds a body.';
ALTER TABLE public.posts
    ADD CONSTRAINT posts_current_body_id_fkey FOREIGN KEY (current_body_id) REFERENCES public.post_bodies (body_id) DEFERRABLE INITIALLY DEFERRED;

-- Each version of a post: which body, who edited it and why.
CREATE TABLE public.post_revisions (
    revision_id uuid NOT NULL,
    post_id uuid NOT NULL,
    body_id uuid NOT NULL,
    editor_user_id uuid NOT NULL,
    revision_number integer NOT NULL,
    edit_reason text,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT post_revisions_pkey PRIMARY KEY (revision_id),
    CONSTRAINT post_revisions_post_revision_number_key UNIQUE (post_id, revision_number),
    CONSTRAINT post_revisions_body_id_fkey FOREIGN KEY (body_id) REFERENCES public.post_bodies (body_id),
    CONSTRAINT post_revisions_editor_user_id_fkey FOREIGN KEY (editor_user_id) REFERENCES public.users (id),
    CONSTRAINT post_revisions_post_id_fkey FOREIGN KEY (post_id) REFERENCES public.posts (post_id),
    CONSTRAINT post_revisions_revision_number_check CHECK (revision_number > 0)
);
COMMENT ON TABLE public.post_revisions IS 'Each version of a post: which body, who edited it and why.';
ALTER TABLE public.posts
    ADD CONSTRAINT posts_current_revision_id_fkey FOREIGN KEY (current_revision_id) REFERENCES public.post_revisions (revision_id) DEFERRABLE INITIALLY DEFERRED;

-- A thread's reply count and last post, apart from threads so a reply updates
-- a small row (ADR 0119). fillfactor 80 keeps those updates HOT.
CREATE TABLE public.thread_counters (
    thread_id uuid NOT NULL,
    reply_count bigint NOT NULL DEFAULT 0,
    visible_reply_count bigint NOT NULL DEFAULT 0,
    last_post_id uuid,
    last_activity_at timestamptz NOT NULL DEFAULT now(),
    version bigint NOT NULL DEFAULT 1,
    reconciled_at timestamptz,
    CONSTRAINT thread_counters_pkey PRIMARY KEY (thread_id),
    CONSTRAINT thread_counters_last_post_id_fkey FOREIGN KEY (last_post_id) REFERENCES public.posts (post_id),
    CONSTRAINT thread_counters_thread_id_fkey FOREIGN KEY (thread_id) REFERENCES public.threads (thread_id),
    CONSTRAINT thread_counters_reply_count_check CHECK (reply_count >= 0),
    CONSTRAINT thread_counters_version_check CHECK (version > 0),
    CONSTRAINT thread_counters_visible_reply_count_check CHECK (visible_reply_count >= 0)
)
WITH (fillfactor = 80);
COMMENT ON TABLE public.thread_counters IS 'A thread''s reply count and last post, apart from threads so a reply updates a small row (ADR 0119).';

-- The post a reply answers, when it answers one: both posts in the same
-- thread.
CREATE TABLE public.post_replies (
    post_id uuid NOT NULL,
    reply_to_post_id uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT post_replies_pkey PRIMARY KEY (post_id),
    CONSTRAINT post_replies_post_id_fkey FOREIGN KEY (post_id) REFERENCES public.posts (post_id),
    CONSTRAINT post_replies_reply_to_post_id_fkey FOREIGN KEY (reply_to_post_id) REFERENCES public.posts (post_id),
    CONSTRAINT post_replies_not_self_check CHECK (post_id <> reply_to_post_id)
);
CREATE INDEX idx_post_replies_target
    ON public.post_replies (reply_to_post_id);
COMMENT ON TABLE public.post_replies IS 'The post a reply answers, when it answers one: both posts in the same thread.';

-- How far a member has read each thread.
CREATE TABLE public.thread_read_state (
    user_id uuid NOT NULL,
    thread_id uuid NOT NULL,
    last_read_position bigint NOT NULL,
    last_read_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT thread_read_state_pkey PRIMARY KEY (user_id, thread_id),
    CONSTRAINT thread_read_state_thread_id_fkey FOREIGN KEY (thread_id) REFERENCES public.threads (thread_id),
    CONSTRAINT thread_read_state_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users (id)
);
COMMENT ON TABLE public.thread_read_state IS 'How far a member has read each thread.';

-- Read positions waiting to be folded into thread_read_state.
CREATE TABLE public.user_read_marker_deltas (
    user_id uuid NOT NULL,
    thread_id uuid NOT NULL,
    last_read_position bigint NOT NULL,
    last_read_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT user_read_marker_deltas_pkey PRIMARY KEY (user_id, thread_id),
    CONSTRAINT user_read_marker_deltas_thread_id_fkey FOREIGN KEY (thread_id) REFERENCES public.threads (thread_id),
    CONSTRAINT user_read_marker_deltas_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users (id)
);
COMMENT ON TABLE public.user_read_marker_deltas IS 'Read positions waiting to be folded into thread_read_state.';

-- A tag, by its lower-case slug, with the name it was first given.
CREATE TABLE public.tags (
    tag_id uuid NOT NULL DEFAULT gen_random_uuid(),
    slug text NOT NULL,
    name text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT tags_pkey PRIMARY KEY (tag_id),
    CONSTRAINT tags_slug_key UNIQUE (slug),
    CONSTRAINT tags_name_check CHECK (length(name) >= 1 AND length(name) <= 30),
    CONSTRAINT tags_slug_check CHECK (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$' AND length(slug) <= 30)
);
COMMENT ON TABLE public.tags IS 'A tag, by its lower-case slug, with the name it was first given.';

-- The tags of a thread, at most five, in the order given.
CREATE TABLE public.thread_tags (
    thread_id uuid NOT NULL,
    tag_id uuid NOT NULL,
    position smallint NOT NULL,
    CONSTRAINT thread_tags_pkey PRIMARY KEY (thread_id, tag_id),
    CONSTRAINT thread_tags_tag_id_fkey FOREIGN KEY (tag_id) REFERENCES public.tags (tag_id),
    CONSTRAINT thread_tags_thread_id_fkey FOREIGN KEY (thread_id) REFERENCES public.threads (thread_id),
    CONSTRAINT thread_tags_position_check CHECK ("position" >= 1 AND "position" <= 5)
);
CREATE INDEX idx_thread_tags_tag
    ON public.thread_tags (tag_id);
COMMENT ON TABLE public.thread_tags IS 'The tags of a thread, at most five, in the order given.';

-- A member's unsent thread or reply, private to them, saved with a revision so
-- two tabs cannot overwrite each other.
CREATE TABLE public.forum_drafts (
    draft_id uuid NOT NULL,
    owner_user_id uuid NOT NULL,
    kind text NOT NULL,
    category_id uuid,
    thread_id uuid,
    title text NOT NULL DEFAULT '',
    body_source text NOT NULL DEFAULT '',
    visibility text,
    command_id text NOT NULL,
    draft_revision bigint NOT NULL,
    save_base_revision bigint NOT NULL,
    save_command_id text NOT NULL,
    created_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL,
    expires_at timestamptz NOT NULL,
    CONSTRAINT forum_drafts_pkey PRIMARY KEY (draft_id),
    CONSTRAINT forum_drafts_owner_user_id_fkey FOREIGN KEY (owner_user_id) REFERENCES public.users (id) ON DELETE CASCADE,
    CONSTRAINT forum_drafts_body_source_check CHECK (length(body_source) <= 50000),
    CONSTRAINT forum_drafts_check CHECK ((kind = 'thread'::text AND thread_id IS NULL) OR (kind = 'reply'::text AND thread_id IS NOT NULL AND category_id IS NULL)),
    CONSTRAINT forum_drafts_check1 CHECK (updated_at >= created_at AND expires_at > updated_at),
    CONSTRAINT forum_drafts_command_id_check CHECK (length(command_id) >= 1 AND length(command_id) <= 200),
    CONSTRAINT forum_drafts_draft_revision_check CHECK (draft_revision > 0),
    CONSTRAINT forum_drafts_kind_check CHECK (kind IN ('thread', 'reply')),
    CONSTRAINT forum_drafts_title_check CHECK (length(title) <= 300),
    CONSTRAINT forum_drafts_visibility_check CHECK (visibility IN ('public', 'members', 'private'))
);
CREATE INDEX idx_forum_drafts_expires
    ON public.forum_drafts (expires_at);
CREATE INDEX idx_forum_drafts_owner_updated
    ON public.forum_drafts (owner_user_id, updated_at DESC, draft_id DESC);
COMMENT ON TABLE public.forum_drafts IS 'A member''s unsent thread or reply, private to them, saved with a revision so two tabs cannot overwrite each other.';

COMMIT;
