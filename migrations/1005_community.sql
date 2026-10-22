-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

-- What members do with each other and with posts: bookmarks, follows,
-- mentions, likes and reactions, the lists of members they ignore or block,
-- the personal feed, reputation, direct messages, and the operators'
-- announcements.

BEGIN;
SET LOCAL lock_timeout = '1s';

-- A member's bookmark on a thread or a post.
CREATE TABLE public.bookmarks (
    bookmark_id uuid NOT NULL,
    user_id uuid NOT NULL,
    target_type text NOT NULL,
    target_id uuid NOT NULL,
    note text NOT NULL DEFAULT '',
    created_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    CONSTRAINT bookmarks_pkey PRIMARY KEY (bookmark_id),
    CONSTRAINT bookmarks_user_target_key UNIQUE (user_id, target_type, target_id),
    CONSTRAINT bookmarks_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users (id),
    CONSTRAINT bookmarks_deleted_after_created_check CHECK (deleted_at IS NULL OR deleted_at >= created_at),
    CONSTRAINT bookmarks_target_type_check CHECK (target_type IN ('thread', 'post'))
);
CREATE INDEX idx_bookmarks_user_created
    ON public.bookmarks (user_id, created_at DESC)
    WHERE deleted_at IS NULL;
COMMENT ON TABLE public.bookmarks IS 'A member''s bookmark on a thread or a post.';

-- The folder a bookmark is filed in, named by its member.
CREATE TABLE public.bookmark_folders (
    bookmark_id uuid NOT NULL,
    folder text NOT NULL,
    CONSTRAINT bookmark_folders_pkey PRIMARY KEY (bookmark_id),
    CONSTRAINT bookmark_folders_bookmark_id_fkey FOREIGN KEY (bookmark_id) REFERENCES public.bookmarks (bookmark_id) ON DELETE CASCADE,
    CONSTRAINT bookmark_folders_folder_check CHECK (length(folder) >= 1 AND length(folder) <= 40)
);
CREATE INDEX idx_bookmark_folders_folder
    ON public.bookmark_folders (folder);
COMMENT ON TABLE public.bookmark_folders IS 'The folder a bookmark is filed in, named by its member.';

-- What a member follows, and how much of it they want to hear about.
CREATE TABLE public.subscriptions (
    subscription_id uuid NOT NULL,
    user_id uuid NOT NULL,
    target_type text NOT NULL,
    target_id uuid NOT NULL,
    preference text NOT NULL DEFAULT 'all',
    created_at timestamptz NOT NULL DEFAULT now(),
    muted_at timestamptz,
    revoked_at timestamptz,
    CONSTRAINT subscriptions_pkey PRIMARY KEY (subscription_id),
    CONSTRAINT subscriptions_unique_target UNIQUE (user_id, target_type, target_id),
    CONSTRAINT subscriptions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users (id),
    CONSTRAINT subscriptions_muted_after_created_check CHECK (muted_at IS NULL OR muted_at >= created_at),
    CONSTRAINT subscriptions_preference_check CHECK (preference IN ('all', 'mentions', 'none')),
    CONSTRAINT subscriptions_revoked_after_created_check CHECK (revoked_at IS NULL OR revoked_at >= created_at)
);
CREATE INDEX idx_subscriptions_target_active
    ON public.subscriptions (target_type, target_id, preference)
    WHERE revoked_at IS NULL;
COMMENT ON TABLE public.subscriptions IS 'What a member follows, and how much of it they want to hear about.';

-- A member named in a post or a thread, once per source.
CREATE TABLE public.mentions (
    mention_id uuid NOT NULL,
    source_type text NOT NULL,
    source_id uuid NOT NULL,
    actor_id uuid NOT NULL,
    mentioned_user_id uuid NOT NULL,
    mentioned_username text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT mentions_pkey PRIMARY KEY (mention_id),
    CONSTRAINT mentions_source_user_key UNIQUE (source_type, source_id, mentioned_user_id),
    CONSTRAINT mentions_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES public.users (id),
    CONSTRAINT mentions_mentioned_user_id_fkey FOREIGN KEY (mentioned_user_id) REFERENCES public.users (id),
    CONSTRAINT mentions_source_type_check CHECK (source_type IN ('post', 'thread'))
);
CREATE INDEX idx_mentions_mentioned_created
    ON public.mentions (mentioned_user_id, created_at DESC);
COMMENT ON TABLE public.mentions IS 'A member named in a post or a thread, once per source.';

-- A member's like on a post, at most one; never on their own post.
CREATE TABLE public.post_likes (
    post_id uuid NOT NULL,
    user_id uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT post_likes_pkey PRIMARY KEY (post_id, user_id),
    CONSTRAINT post_likes_post_id_fkey FOREIGN KEY (post_id) REFERENCES public.posts (post_id),
    CONSTRAINT post_likes_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users (id)
);
CREATE INDEX idx_post_likes_user_created
    ON public.post_likes (user_id, created_at DESC);
COMMENT ON TABLE public.post_likes IS 'A member''s like on a post, at most one; never on their own post.';

-- A member's reactions on a post, one of four kinds each at most once; never
-- on their own post.
CREATE TABLE public.post_reactions (
    post_id uuid NOT NULL,
    user_id uuid NOT NULL,
    reaction text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT post_reactions_pkey PRIMARY KEY (post_id, user_id, reaction),
    CONSTRAINT post_reactions_post_id_fkey FOREIGN KEY (post_id) REFERENCES public.posts (post_id),
    CONSTRAINT post_reactions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users (id),
    CONSTRAINT post_reactions_reaction_check CHECK (reaction IN ('heart', 'laugh', 'celebrate', 'think'))
);
CREATE INDEX idx_post_reactions_user
    ON public.post_reactions (user_id);
COMMENT ON TABLE public.post_reactions IS 'A member''s reactions on a post, one of four kinds each at most once; never on their own post.';

-- The members a member ignores or blocks: their own private list.
CREATE TABLE public.member_relations (
    owner_user_id uuid NOT NULL,
    other_user_id uuid NOT NULL,
    kind text NOT NULL,
    created_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL,
    CONSTRAINT member_relations_pkey PRIMARY KEY (owner_user_id, other_user_id),
    CONSTRAINT member_relations_other_user_id_fkey FOREIGN KEY (other_user_id) REFERENCES public.users (id) ON DELETE CASCADE,
    CONSTRAINT member_relations_owner_user_id_fkey FOREIGN KEY (owner_user_id) REFERENCES public.users (id) ON DELETE CASCADE,
    CONSTRAINT member_relations_check CHECK (owner_user_id <> other_user_id),
    CONSTRAINT member_relations_check1 CHECK (updated_at >= created_at),
    CONSTRAINT member_relations_kind_check CHECK (kind IN ('ignore', 'block'))
);
CREATE INDEX idx_member_relations_other
    ON public.member_relations (other_user_id);
COMMENT ON TABLE public.member_relations IS 'The members a member ignores or blocks: their own private list.';

-- The personal feed of each member, written by the feed projection and read
-- newest first.
CREATE TABLE public.user_feed_items (
    user_id uuid NOT NULL,
    item_type text NOT NULL,
    item_id uuid NOT NULL,
    created_at timestamptz NOT NULL,
    rank_score numeric NOT NULL DEFAULT 0,
    visibility_version bigint NOT NULL,
    permission_version bigint NOT NULL,
    CONSTRAINT user_feed_items_pkey PRIMARY KEY (user_id, item_type, item_id),
    CONSTRAINT user_feed_items_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users (id),
    CONSTRAINT user_feed_items_permission_version_check CHECK (permission_version > 0),
    CONSTRAINT user_feed_items_visibility_version_check CHECK (visibility_version > 0)
);
CREATE INDEX idx_user_feed_items_item
    ON public.user_feed_items (item_type, item_id);
CREATE INDEX idx_user_feed_items_ranked
    ON public.user_feed_items (user_id, rank_score DESC, created_at DESC);
CREATE INDEX idx_user_feed_items_user_created
    ON public.user_feed_items (user_id, created_at DESC, item_id DESC)
    INCLUDE (item_type, rank_score, visibility_version, permission_version);
COMMENT ON TABLE public.user_feed_items IS 'The personal feed of each member, written by the feed projection and read newest first.';

-- The changes to a member's reputation, one per member and source.
CREATE TABLE public.reputation_events (
    reputation_event_id uuid NOT NULL,
    user_id uuid NOT NULL,
    actor_id uuid,
    source_type text NOT NULL,
    source_id uuid NOT NULL,
    delta integer NOT NULL,
    reason text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT reputation_events_pkey PRIMARY KEY (reputation_event_id),
    CONSTRAINT reputation_events_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES public.users (id),
    CONSTRAINT reputation_events_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users (id),
    CONSTRAINT reputation_events_reason_check CHECK (length(reason) > 0)
);
CREATE UNIQUE INDEX idx_reputation_events_source_unique
    ON public.reputation_events (user_id, source_type, source_id);
CREATE INDEX idx_reputation_events_user_created
    ON public.reputation_events (user_id, created_at DESC);
COMMENT ON TABLE public.reputation_events IS 'The changes to a member''s reputation, one per member and source.';

-- A member's computed score and trust level.
CREATE TABLE public.trust_score_snapshots (
    user_id uuid NOT NULL,
    score integer NOT NULL DEFAULT 0,
    trust_level integer NOT NULL DEFAULT 0,
    calculated_at timestamptz NOT NULL DEFAULT now(),
    version bigint NOT NULL DEFAULT 1,
    CONSTRAINT trust_score_snapshots_pkey PRIMARY KEY (user_id),
    CONSTRAINT trust_score_snapshots_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users (id),
    CONSTRAINT trust_score_snapshots_trust_level_check CHECK (trust_level >= 0 AND trust_level <= 4),
    CONSTRAINT trust_score_snapshots_version_check CHECK (version > 0)
);
COMMENT ON TABLE public.trust_score_snapshots IS 'A member''s computed score and trust level.';

-- A private conversation between two members, the pair ordered so it is stored
-- once.
CREATE TABLE public.direct_conversations (
    conversation_id uuid NOT NULL,
    first_user_id uuid NOT NULL,
    second_user_id uuid NOT NULL,
    started_by_user_id uuid,
    created_at timestamptz NOT NULL,
    last_message_at timestamptz NOT NULL,
    CONSTRAINT direct_conversations_pkey PRIMARY KEY (conversation_id),
    CONSTRAINT direct_conversations_pair_key UNIQUE (first_user_id, second_user_id),
    CONSTRAINT direct_conversations_first_user_id_fkey FOREIGN KEY (first_user_id) REFERENCES public.users (id) ON DELETE CASCADE,
    CONSTRAINT direct_conversations_second_user_id_fkey FOREIGN KEY (second_user_id) REFERENCES public.users (id) ON DELETE CASCADE,
    CONSTRAINT direct_conversations_started_by_user_id_fkey FOREIGN KEY (started_by_user_id) REFERENCES public.users (id) ON DELETE SET NULL,
    CONSTRAINT direct_conversations_pair_order_check CHECK (first_user_id < second_user_id)
);
CREATE INDEX idx_direct_conversations_second
    ON public.direct_conversations (second_user_id);
CREATE INDEX idx_direct_conversations_started
    ON public.direct_conversations (started_by_user_id, created_at);
COMMENT ON TABLE public.direct_conversations IS 'A private conversation between two members, the pair ordered so it is stored once.';

-- Each side of a conversation: its read state and unread count.
CREATE TABLE public.direct_conversation_members (
    conversation_id uuid NOT NULL,
    user_id uuid NOT NULL,
    other_user_id uuid NOT NULL,
    last_message_at timestamptz NOT NULL,
    last_read_at timestamptz,
    unread_count integer NOT NULL DEFAULT 0,
    CONSTRAINT direct_conversation_members_pkey PRIMARY KEY (conversation_id, user_id),
    CONSTRAINT direct_conversation_members_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES public.direct_conversations (conversation_id) ON DELETE CASCADE,
    CONSTRAINT direct_conversation_members_other_user_id_fkey FOREIGN KEY (other_user_id) REFERENCES public.users (id) ON DELETE CASCADE,
    CONSTRAINT direct_conversation_members_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users (id) ON DELETE CASCADE,
    CONSTRAINT direct_conversation_members_unread_count_check CHECK (unread_count >= 0)
);
CREATE INDEX idx_direct_conversation_members_inbox
    ON public.direct_conversation_members (user_id, last_message_at DESC, conversation_id DESC);
CREATE INDEX idx_direct_conversation_members_other
    ON public.direct_conversation_members (other_user_id);
COMMENT ON TABLE public.direct_conversation_members IS 'Each side of a conversation: its read state and unread count.';

-- The messages of a conversation, in the order of an identity position.
CREATE TABLE public.direct_messages (
    message_id uuid NOT NULL,
    conversation_id uuid NOT NULL,
    author_user_id uuid NOT NULL,
    body text NOT NULL,
    created_at timestamptz NOT NULL,
    position bigint GENERATED ALWAYS AS IDENTITY,
    CONSTRAINT direct_messages_pkey PRIMARY KEY (message_id),
    CONSTRAINT direct_messages_author_user_id_fkey FOREIGN KEY (author_user_id) REFERENCES public.users (id) ON DELETE CASCADE,
    CONSTRAINT direct_messages_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES public.direct_conversations (conversation_id) ON DELETE CASCADE,
    CONSTRAINT direct_messages_body_check CHECK (length(body) >= 1 AND length(body) <= 5000)
);
CREATE INDEX idx_direct_messages_author
    ON public.direct_messages (author_user_id);
CREATE INDEX idx_direct_messages_conversation
    ON public.direct_messages (conversation_id, "position" DESC);
COMMENT ON TABLE public.direct_messages IS 'The messages of a conversation, in the order of an identity position.';

-- A short notice from the operators on every page, until an administrator
-- retires it; nothing is deleted.
CREATE TABLE public.site_announcements (
    announcement_id uuid NOT NULL,
    message text NOT NULL,
    tone text NOT NULL DEFAULT 'notice',
    created_by uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    retired_by uuid,
    retired_at timestamptz,
    CONSTRAINT site_announcements_pkey PRIMARY KEY (announcement_id),
    CONSTRAINT site_announcements_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users (id),
    CONSTRAINT site_announcements_retired_by_fkey FOREIGN KEY (retired_by) REFERENCES public.users (id),
    CONSTRAINT site_announcements_message_check CHECK (char_length(message) >= 1 AND char_length(message) <= 500),
    CONSTRAINT site_announcements_retired_check CHECK ((retired_at IS NULL) = (retired_by IS NULL)),
    CONSTRAINT site_announcements_tone_check CHECK (tone IN ('notice', 'warning'))
);
CREATE INDEX idx_site_announcements_active
    ON public.site_announcements (created_at DESC)
    WHERE retired_at IS NULL;
COMMENT ON TABLE public.site_announcements IS 'A short notice from the operators on every page, until an administrator retires it; nothing is deleted.';

COMMIT;
