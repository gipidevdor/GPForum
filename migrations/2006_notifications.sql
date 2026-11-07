-- SPDX-FileCopyrightText: 2026 GPForum Contributors
-- SPDX-License-Identifier: BSD-3-Clause

-- Fresh-database baseline: notifications.
-- Final definitions only; see migrations/README.md for the dependency order.

BEGIN;
SET LOCAL lock_timeout = '1s';

CREATE TABLE public.notifications (
    notification_id uuid NOT NULL,
    recipient_user_id uuid NOT NULL,
    source_type text NOT NULL,
    source_id uuid,
    notification_type text NOT NULL,
    payload jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT notifications_pkey PRIMARY KEY (notification_id, created_at)
)
PARTITION BY RANGE (created_at);
COMMENT ON TABLE public.notifications IS 'A notification for a member, append-only, partitioned by month on created_at.';

CREATE INDEX idx_notifications_created_at_brin ON public.notifications USING BRIN (created_at);

CREATE INDEX idx_notifications_recipient_created_at ON public.notifications (recipient_user_id, created_at DESC);

CREATE TABLE public.notification_inbox (
    recipient_user_id uuid NOT NULL,
    notification_id uuid NOT NULL,
    created_at timestamptz NOT NULL,
    read_at timestamptz,
    rank_score numeric NOT NULL DEFAULT 0,
    CONSTRAINT notification_inbox_pkey PRIMARY KEY (recipient_user_id, notification_id)
);
COMMENT ON TABLE public.notification_inbox IS 'The inbox projection: one row per notification a member sees, with its read time, newest first.';

CREATE INDEX idx_notification_inbox_recipient_created ON public.notification_inbox (recipient_user_id, created_at DESC, notification_id DESC) INCLUDE (read_at, rank_score);

CREATE TABLE public.notification_reads (
    notification_id uuid NOT NULL,
    recipient_user_id uuid NOT NULL,
    read_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT notification_reads_pkey PRIMARY KEY (notification_id, recipient_user_id)
);
COMMENT ON TABLE public.notification_reads IS 'When a member read a notification.';

CREATE TABLE public.notification_preferences (
    user_id uuid NOT NULL,
    channel text NOT NULL,
    enabled boolean NOT NULL DEFAULT true,
    digest_frequency text NOT NULL DEFAULT 'daily',
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT notification_preferences_channel_check CHECK (channel IN ('in_app', 'email', 'digest')),
    CONSTRAINT notification_preferences_digest_check CHECK (digest_frequency IN ('immediate', 'daily', 'weekly', 'never')),
    CONSTRAINT notification_preferences_pkey PRIMARY KEY (user_id, channel)
);
COMMENT ON TABLE public.notification_preferences IS 'A member''s channels (in the inbox, by email, as a digest) and how often the digest comes.';

CREATE INDEX idx_notification_preferences_enabled ON public.notification_preferences (channel, enabled);

CREATE TABLE public.notification_type_preferences (
    user_id uuid NOT NULL,
    event_type text NOT NULL,
    channel text NOT NULL,
    enabled boolean NOT NULL,
    updated_at timestamptz NOT NULL,
    CONSTRAINT notification_type_preferences_channel_check CHECK (channel IN ('in_app', 'email')),
    CONSTRAINT notification_type_preferences_event_type_check CHECK (event_type IN ('reply', 'mention', 'moderation', 'message')),
    CONSTRAINT notification_type_preferences_pkey PRIMARY KEY (user_id, event_type, channel)
);
COMMENT ON TABLE public.notification_type_preferences IS 'A member''s switch for each kind of notification on each channel; a kind with no row has its default.';

CREATE TABLE public.notification_digests (
    user_id uuid NOT NULL,
    frequency text NOT NULL,
    period_start timestamptz NOT NULL,
    period_end timestamptz NOT NULL,
    status text NOT NULL,
    thread_count integer NOT NULL,
    event_id uuid,
    created_at timestamptz NOT NULL,
    sent_at timestamptz,
    CONSTRAINT notification_digests_frequency_check CHECK (frequency IN ('daily', 'weekly')),
    CONSTRAINT notification_digests_period_check CHECK (period_end > period_start),
    CONSTRAINT notification_digests_queued_check CHECK ((status = 'queued') = (event_id IS NOT NULL)),
    CONSTRAINT notification_digests_status_check CHECK (status IN ('queued', 'empty')),
    CONSTRAINT notification_digests_thread_count_check CHECK (thread_count >= 0),
    CONSTRAINT notification_digests_pkey PRIMARY KEY (user_id, frequency, period_start)
);
COMMENT ON TABLE public.notification_digests IS 'Each digest period of each member, recorded once, so a run of the digest job queues each mail once.';

CREATE INDEX idx_notification_digests_period_end ON public.notification_digests (period_end);

CREATE TABLE public.notifications_default PARTITION OF public.notifications DEFAULT;

COMMIT;
