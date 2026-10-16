-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

-- ADR 0078 (notification types and one-click unsubscribe): a member turns
-- each kind of notification on or off for the inbox and for email, beside
-- the channel switches of notification_preferences. The kinds are replies
-- in followed threads, mentions and moderation notices about the member's
-- own posts. A kind with no stored row has its default: in the inbox, on;
-- by email, on for mentions and moderation notices and off for replies.
-- An email goes out only while the email channel and the kind's email are
-- on and the account is active with a verified address. An unsubscribe
-- link turns one kind's email off, or the whole email channel, and is
-- audited. Identity mail (verification, reset, email change) is
-- transactional and is never governed by any of this.

BEGIN;
SET LOCAL lock_timeout = '1s';

CREATE TABLE public.notification_type_preferences (
    user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    event_type text NOT NULL,
    channel text NOT NULL,
    enabled boolean NOT NULL,
    updated_at timestamptz NOT NULL,
    CONSTRAINT notification_type_preferences_pkey
        PRIMARY KEY (user_id, event_type, channel),
    CONSTRAINT notification_type_preferences_event_type_check
        CHECK (event_type IN ('reply', 'mention', 'moderation')),
    CONSTRAINT notification_type_preferences_channel_check
        CHECK (channel IN ('in_app', 'email'))
);

-- The kind a notification type belongs to, or NULL for one no member
-- control covers: such a notification follows the channel switches alone
-- and is never emailed.
CREATE FUNCTION api.core_notification_event_type_v1(p_notification_type text)
RETURNS text
LANGUAGE sql IMMUTABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT CASE
    WHEN p_notification_type IN ('reply', 'follow') THEN 'reply'
    WHEN p_notification_type = 'mention' THEN 'mention'
    WHEN p_notification_type IN ('review_approved', 'review_rejected')
        THEN 'moderation'
END;
$$;
REVOKE EXECUTE ON FUNCTION api.core_notification_event_type_v1(text)
    FROM PUBLIC;

-- A kind's default on a channel: the inbox always, email for mentions and
-- moderation notices.
CREATE FUNCTION api.core_notification_type_default_v1(p_event_type text,
    p_channel text)
RETURNS boolean
LANGUAGE sql IMMUTABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT p_channel = 'in_app' OR p_event_type IN ('mention', 'moderation');
$$;
REVOKE EXECUTE ON FUNCTION api.core_notification_type_default_v1(text, text)
    FROM PUBLIC;

-- Every kind on every channel for the member, stored or by default, in
-- the order the settings page shows them.
CREATE FUNCTION api.notification_type_preferences_v1(p_user_id uuid)
RETURNS TABLE(event_type text, channel text, enabled boolean,
    stored boolean)
LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT k.event_type, c.channel,
    coalesce(p.enabled,
        api.core_notification_type_default_v1(k.event_type, c.channel)),
    p.user_id IS NOT NULL
FROM (VALUES ('reply', 1), ('mention', 2), ('moderation', 3))
    AS k(event_type, rank)
CROSS JOIN (VALUES ('in_app', 1), ('email', 2)) AS c(channel, rank)
LEFT JOIN public.notification_type_preferences p
    ON p.user_id = p_user_id AND p.event_type = k.event_type
    AND p.channel = c.channel
ORDER BY k.rank, c.rank;
$$;
REVOKE EXECUTE ON FUNCTION api.notification_type_preferences_v1(uuid)
    FROM PUBLIC;

CREATE FUNCTION api.notification_type_preferences_v2(
p_user_id uuid
)
RETURNS TABLE(event_type text, channel text, enabled boolean,
    stored boolean)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.notification_type_preferences_v1(p_user_id);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_type_preferences_v2(uuid)
    FROM PUBLIC;

-- Stores the member's choices, an array of { event_type, channel,
-- enabled }. Every entry is checked before any is written: an unknown kind
-- or channel is invalid and nothing changes. Answers how many rows changed.
CREATE FUNCTION api.notification_set_type_preferences_v1(p_user_id uuid,
    p_preferences jsonb, p_now timestamptz)
RETURNS TABLE(status text, changed integer)
LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE amount integer;
BEGIN
    IF p_user_id IS NULL OR p_now IS NULL
        OR jsonb_typeof(p_preferences) IS DISTINCT FROM 'array' THEN
        RETURN QUERY SELECT 'invalid'::text, 0;
        RETURN;
    END IF;
    IF jsonb_array_length(p_preferences) > 6
        OR EXISTS (SELECT 1 FROM jsonb_array_elements(p_preferences) e(v)
            WHERE jsonb_typeof(e.v) IS DISTINCT FROM 'object'
                OR coalesce(e.v ->> 'event_type', '')
                    NOT IN ('reply', 'mention', 'moderation')
                OR coalesce(e.v ->> 'channel', '')
                    NOT IN ('in_app', 'email')
                OR jsonb_typeof(e.v -> 'enabled')
                    IS DISTINCT FROM 'boolean') THEN
        RETURN QUERY SELECT 'invalid'::text, 0;
        RETURN;
    END IF;
    PERFORM 1 FROM public.users u
        WHERE u.id = p_user_id AND u.deleted_at IS NULL;
    IF NOT FOUND THEN
        RETURN QUERY SELECT 'not_found'::text, 0;
        RETURN;
    END IF;
    INSERT INTO public.notification_type_preferences AS p (user_id,
        event_type, channel, enabled, updated_at)
    SELECT DISTINCT ON (e.v ->> 'event_type', e.v ->> 'channel') p_user_id,
        e.v ->> 'event_type', e.v ->> 'channel',
        (e.v ->> 'enabled')::boolean, p_now
    FROM jsonb_array_elements(p_preferences) WITH ORDINALITY e(v, n)
    ORDER BY e.v ->> 'event_type', e.v ->> 'channel', e.n DESC
    ON CONFLICT ON CONSTRAINT notification_type_preferences_pkey
    DO UPDATE SET enabled = excluded.enabled, updated_at = excluded.updated_at
        WHERE p.enabled IS DISTINCT FROM excluded.enabled;
    GET DIAGNOSTICS amount = ROW_COUNT;
    RETURN QUERY SELECT CASE WHEN amount > 0 THEN 'ok' ELSE 'unchanged' END,
        amount;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.notification_set_type_preferences_v1(uuid,
    jsonb, timestamptz) FROM PUBLIC;

CREATE FUNCTION api.notification_set_type_preferences_v2(
p_user_id uuid, p_preferences jsonb, p_now timestamptz
)
RETURNS TABLE(status text, changed integer)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.notification_set_type_preferences_v1(p_user_id,
    p_preferences, p_now);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_set_type_preferences_v2(uuid,
    jsonb, timestamptz) FROM PUBLIC;

-- Where a notification of this type goes for the member, in one read: the
-- inbox when the in-app channel and the kind's in-app switch are on, email
-- when the email channel and the kind's email switch are on and the account
-- is active with a verified address. The address and locale come with it
-- for the mail worker, which asks again when it sends, so an unsubscribe
-- that lands in between is kept.
CREATE FUNCTION api.notification_delivery_plan_v1(p_user_id uuid,
    p_notification_type text)
RETURNS TABLE(event_type text, in_app boolean, email boolean,
    email_address text, locale text)
LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
WITH kind AS (
    SELECT api.core_notification_event_type_v1(p_notification_type) AS k
)
SELECT kind.k,
    coalesce((SELECT c.enabled FROM public.notification_preferences c
        WHERE c.user_id = u.id AND c.channel = 'in_app'), true)
    AND (kind.k IS NULL OR coalesce(
        (SELECT t.enabled FROM public.notification_type_preferences t
            WHERE t.user_id = u.id AND t.event_type = kind.k
                AND t.channel = 'in_app'),
        api.core_notification_type_default_v1(kind.k, 'in_app'))),
    kind.k IS NOT NULL
    AND u.status = 'active' AND u.deleted_at IS NULL
    AND u.email_verified_at IS NOT NULL
    AND coalesce((SELECT c.enabled FROM public.notification_preferences c
        WHERE c.user_id = u.id AND c.channel = 'email'), true)
    AND coalesce(
        (SELECT t.enabled FROM public.notification_type_preferences t
            WHERE t.user_id = u.id AND t.event_type = kind.k
                AND t.channel = 'email'),
        api.core_notification_type_default_v1(kind.k, 'email')),
    u.email_normalized, u.preferred_locale
FROM public.users u CROSS JOIN kind
WHERE u.id = p_user_id;
$$;
REVOKE EXECUTE ON FUNCTION api.notification_delivery_plan_v1(uuid, text)
    FROM PUBLIC;

CREATE FUNCTION api.notification_delivery_plan_v2(
p_user_id uuid, p_notification_type text
)
RETURNS TABLE(event_type text, in_app boolean, email boolean,
    email_address text, locale text)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.notification_delivery_plan_v1(p_user_id,
    p_notification_type);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_delivery_plan_v2(uuid, text)
    FROM PUBLIC;

-- The one-click unsubscribe: scope names a kind, whose email is turned
-- off, or all, which turns the email channel off. Answers ok when it
-- changed something (and audits it), unchanged when it was already off,
-- not_found for an account that is gone and invalid for another scope.
CREATE FUNCTION api.notification_unsubscribe_v1(p_user_id uuid,
    p_scope text, p_now timestamptz, p_audit jsonb)
RETURNS TABLE(status text, scope text)
LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE was_on boolean;
BEGIN
    IF p_user_id IS NULL OR p_now IS NULL OR p_audit IS NULL
        OR coalesce(p_scope, '')
            NOT IN ('reply', 'mention', 'moderation', 'all') THEN
        RETURN QUERY SELECT 'invalid'::text, p_scope;
        RETURN;
    END IF;
    PERFORM 1 FROM public.users u
        WHERE u.id = p_user_id AND u.deleted_at IS NULL
        FOR UPDATE;
    IF NOT FOUND THEN
        RETURN QUERY SELECT 'not_found'::text, p_scope;
        RETURN;
    END IF;
    IF p_scope = 'all' THEN
        was_on := coalesce((SELECT c.enabled
            FROM public.notification_preferences c
            WHERE c.user_id = p_user_id AND c.channel = 'email'), true);
    ELSE
        was_on := coalesce((SELECT t.enabled
            FROM public.notification_type_preferences t
            WHERE t.user_id = p_user_id AND t.event_type = p_scope
                AND t.channel = 'email'),
            api.core_notification_type_default_v1(p_scope, 'email'));
    END IF;
    IF NOT was_on THEN
        RETURN QUERY SELECT 'unchanged'::text, p_scope;
        RETURN;
    END IF;
    IF p_scope = 'all' THEN
        INSERT INTO public.notification_preferences AS p (user_id, channel,
            enabled, digest_frequency, updated_at)
        VALUES (p_user_id, 'email', false, 'daily', p_now)
        ON CONFLICT (user_id, channel)
        DO UPDATE SET enabled = false, updated_at = excluded.updated_at;
    ELSE
        INSERT INTO public.notification_type_preferences AS p (user_id,
            event_type, channel, enabled, updated_at)
        VALUES (p_user_id, p_scope, 'email', false, p_now)
        ON CONFLICT ON CONSTRAINT notification_type_preferences_pkey
        DO UPDATE SET enabled = false, updated_at = excluded.updated_at;
    END IF;
    PERFORM api.ops_record_audit_v1(p_audit, false);
    RETURN QUERY SELECT 'ok'::text, p_scope;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.notification_unsubscribe_v1(uuid, text,
    timestamptz, jsonb) FROM PUBLIC;

CREATE FUNCTION api.notification_unsubscribe_v2(
p_user_id uuid, p_scope text, p_now timestamptz, p_audit jsonb
)
RETURNS TABLE(status text, scope text)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.notification_unsubscribe_v1(p_user_id, p_scope, p_now,
    p_audit);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_unsubscribe_v2(uuid, text,
    timestamptz, jsonb) FROM PUBLIC;

-- The export: the member's own choices for each kind of notification.
CREATE FUNCTION api.portability_export_parts_v13(p_user_id uuid)
RETURNS TABLE(document json) LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT (previous.document::jsonb || jsonb_build_object(
    'notification_type_preferences',
    (SELECT coalesce(jsonb_agg(jsonb_build_object('event_type', p.event_type,
        'channel', p.channel, 'enabled', p.enabled,
        'updated_at', p.updated_at)
        ORDER BY p.event_type, p.channel), '[]'::jsonb)
     FROM public.notification_type_preferences p
     WHERE p.user_id = p_user_id)))::json
FROM api.portability_export_parts_v11(p_user_id) previous;
$$;
REVOKE EXECUTE ON FUNCTION api.portability_export_parts_v13(uuid) FROM PUBLIC;

CREATE FUNCTION api.portability_export_parts_v14(p_user_id uuid)
RETURNS TABLE(document json) LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.portability_export_parts_v13(p_user_id);
$$;
REVOKE EXECUTE ON FUNCTION api.portability_export_parts_v14(uuid) FROM PUBLIC;

COMMIT;
