-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

-- A site announcement (ADR 0131): a few words from the operators that every
-- page shows above its content until an administrator retires it. Plain
-- text, up to 500 characters, in one of two tones. Nothing is deleted: a
-- retired announcement keeps who published and who retired it, and when.

BEGIN;
SET LOCAL lock_timeout = '1s';

CREATE TABLE public.site_announcements (
    announcement_id uuid NOT NULL,
    message text NOT NULL,
    tone text NOT NULL DEFAULT 'notice',
    created_by uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    retired_by uuid,
    retired_at timestamptz,
    CONSTRAINT site_announcements_pkey PRIMARY KEY (announcement_id),
    CONSTRAINT site_announcements_created_by_fkey FOREIGN KEY (created_by)
        REFERENCES public.users (id),
    CONSTRAINT site_announcements_retired_by_fkey FOREIGN KEY (retired_by)
        REFERENCES public.users (id),
    CONSTRAINT site_announcements_message_check
        CHECK (char_length(message) BETWEEN 1 AND 500),
    CONSTRAINT site_announcements_tone_check
        CHECK (tone IN ('notice', 'warning')),
    CONSTRAINT site_announcements_retired_check
        CHECK ((retired_at IS NULL) = (retired_by IS NULL))
);
CREATE INDEX idx_site_announcements_active
    ON public.site_announcements (created_at DESC)
    WHERE retired_at IS NULL;

CREATE FUNCTION api.admin_insert_announcement_v1(p_values jsonb)
RETURNS SETOF public.site_announcements
LANGUAGE sql
VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    INSERT INTO public.site_announcements (announcement_id, message, tone,
        created_by, created_at)
    VALUES ((p_values ->> 'announcement_id')::uuid, p_values ->> 'message',
        p_values ->> 'tone', (p_values ->> 'created_by')::uuid,
        (p_values ->> 'created_at')::timestamptz)
    RETURNING *;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_insert_announcement_v1(jsonb)
    FROM PUBLIC;

-- ADR 0127: the typed boundaries the runtime role may call.
CREATE FUNCTION api.admin_insert_announcement_v2(
p_values jsonb
)
RETURNS SETOF public.site_announcements
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_insert_announcement_v1(p_values);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_insert_announcement_v2(jsonb)
    FROM PUBLIC;

-- Retiring: once. An announcement already retired is returned as it is,
-- so a repeated request changes nothing.
CREATE FUNCTION api.admin_retire_announcement_v1(p_announcement_id uuid,
    p_values jsonb)
RETURNS SETOF public.site_announcements
LANGUAGE sql
VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    UPDATE public.site_announcements a
    SET retired_by = (p_values ->> 'retired_by')::uuid,
        retired_at = (p_values ->> 'retired_at')::timestamptz
    WHERE a.announcement_id = p_announcement_id AND a.retired_at IS NULL
    RETURNING *;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_retire_announcement_v1(uuid, jsonb)
    FROM PUBLIC;

CREATE FUNCTION api.admin_retire_announcement_v2(
p_announcement_id uuid, p_values jsonb
)
RETURNS SETOF public.site_announcements
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_retire_announcement_v1(p_announcement_id, p_values);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_retire_announcement_v2(uuid, jsonb)
    FROM PUBLIC;

CREATE FUNCTION api.admin_announcement_by_id_v1(p_announcement_id uuid)
RETURNS SETOF public.site_announcements
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    SELECT * FROM public.site_announcements a
    WHERE a.announcement_id = p_announcement_id;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_announcement_by_id_v1(uuid) FROM PUBLIC;

CREATE FUNCTION api.admin_announcement_by_id_v2(
p_announcement_id uuid
)
RETURNS SETOF public.site_announcements
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_announcement_by_id_v1(p_announcement_id);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_announcement_by_id_v2(uuid) FROM PUBLIC;

-- The console's list: every announcement, newest first.
CREATE FUNCTION api.admin_list_announcements_v1(p_row_limit integer)
RETURNS SETOF public.site_announcements
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    SELECT * FROM public.site_announcements a
    ORDER BY a.created_at DESC, a.announcement_id DESC
    LIMIT p_row_limit;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_list_announcements_v1(integer)
    FROM PUBLIC;

CREATE FUNCTION api.admin_list_announcements_v2(
p_row_limit integer
)
RETURNS SETOF public.site_announcements
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_list_announcements_v1(p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_list_announcements_v2(integer)
    FROM PUBLIC;

-- What every page shows: the announcements not retired, newest first.
CREATE FUNCTION api.forum_active_announcements_v1(p_row_limit integer)
RETURNS SETOF public.site_announcements
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    SELECT * FROM public.site_announcements a
    WHERE a.retired_at IS NULL
    ORDER BY a.created_at DESC, a.announcement_id DESC
    LIMIT p_row_limit;
$$;
REVOKE EXECUTE ON FUNCTION api.forum_active_announcements_v1(integer)
    FROM PUBLIC;

CREATE FUNCTION api.forum_active_announcements_v2(
p_row_limit integer
)
RETURNS SETOF public.site_announcements
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_active_announcements_v1(p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_active_announcements_v2(integer)
    FROM PUBLIC;

COMMIT;
