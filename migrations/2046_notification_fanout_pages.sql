-- SPDX-FileCopyrightText: 2026 GPForum Contributors
-- SPDX-License-Identifier: BSD-3-Clause

BEGIN;
SET LOCAL lock_timeout = '1s';

-- The new keyset access path orders active recipients before evaluating
-- per-member plans and grants. Each source contributes at most one page.
CREATE INDEX subscriptions_fanout_cursor
ON public.subscriptions(target_type, target_id, user_id) INCLUDE(preference)
WHERE revoked_at IS NULL AND muted_at IS NULL AND preference <> 'none';

CREATE FUNCTION api.notification_fanout_page_v1(
    p_target_type text, p_target_id uuid, p_notification_type text,
    p_actor_id uuid, p_excluded_user_id uuid,
    p_after_user_id uuid, p_through_user_id uuid, p_row_limit integer
)
RETURNS TABLE (
    user_id uuid, in_app boolean, email boolean, email_address text,
    locale text, event_type text, silenced boolean, status text,
    suspended boolean, grants json, moderates boolean, listed uuid[],
    trust_level integer, web_push boolean, through_user_id uuid
)
LANGUAGE plpgsql STABLE SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE
    stop_at uuid := p_through_user_id;
    page_size integer := least(greatest(coalesce(p_row_limit, 100), 1), 1000);
BEGIN
    IF stop_at IS NULL THEN
        SELECT last_user.user_id INTO stop_at FROM (
            (SELECT s.user_id FROM public.subscriptions s
            WHERE s.target_type = p_target_type AND s.target_id = p_target_id
                AND s.revoked_at IS NULL AND s.muted_at IS NULL AND s.preference <> 'none'
                AND (s.preference = 'all' OR p_notification_type = 'mention')
                AND (p_excluded_user_id IS NULL OR s.user_id <> p_excluded_user_id)
            ORDER BY s.user_id DESC LIMIT 1)
            UNION ALL
            (SELECT s.user_id FROM public.threads t JOIN public.subscriptions s
                ON s.target_type = 'category' AND s.target_id = t.category_id
            WHERE p_target_type = 'thread' AND t.thread_id = p_target_id
                AND s.revoked_at IS NULL AND s.muted_at IS NULL AND s.preference <> 'none'
                AND (s.preference = 'all' OR p_notification_type = 'mention')
                AND (p_excluded_user_id IS NULL OR s.user_id <> p_excluded_user_id)
                AND NOT EXISTS (SELECT 1 FROM public.subscriptions own
                    WHERE own.user_id = s.user_id AND own.target_type = 'thread'
                        AND own.target_id = p_target_id AND own.revoked_at IS NULL)
            ORDER BY s.user_id DESC LIMIT 1)
        ) last_user ORDER BY last_user.user_id DESC LIMIT 1;
    END IF;
    IF stop_at IS NULL THEN RETURN; END IF;
    RETURN QUERY
    WITH candidates AS MATERIALIZED (
        (SELECT s.user_id FROM public.subscriptions s
        WHERE s.target_type = p_target_type AND s.target_id = p_target_id
            AND s.revoked_at IS NULL AND s.muted_at IS NULL AND s.preference <> 'none'
            AND (s.preference = 'all' OR p_notification_type = 'mention')
            AND (p_excluded_user_id IS NULL OR s.user_id <> p_excluded_user_id)
            AND s.user_id >= coalesce(p_after_user_id, '00000000-0000-0000-0000-000000000000'::uuid)
            AND (p_after_user_id IS NULL OR s.user_id <> p_after_user_id)
            AND s.user_id <= stop_at
        ORDER BY s.user_id LIMIT page_size)
        UNION
        (SELECT s.user_id FROM public.threads t JOIN public.subscriptions s
            ON s.target_type = 'category' AND s.target_id = t.category_id
        WHERE p_target_type = 'thread' AND t.thread_id = p_target_id
            AND s.revoked_at IS NULL AND s.muted_at IS NULL AND s.preference <> 'none'
            AND (s.preference = 'all' OR p_notification_type = 'mention')
            AND (p_excluded_user_id IS NULL OR s.user_id <> p_excluded_user_id)
            AND s.user_id >= coalesce(p_after_user_id, '00000000-0000-0000-0000-000000000000'::uuid)
            AND (p_after_user_id IS NULL OR s.user_id <> p_after_user_id)
            AND s.user_id <= stop_at
            AND NOT EXISTS (SELECT 1 FROM public.subscriptions own
                WHERE own.user_id = s.user_id AND own.target_type = 'thread'
                    AND own.target_id = p_target_id AND own.revoked_at IS NULL)
        ORDER BY s.user_id LIMIT page_size)
    )
    SELECT s.user_id, coalesce(plan.in_app, true), coalesce(plan.email, false),
        plan.email_address, plan.locale, plan.event_type,
        p_actor_id IS NOT NULL AND s.user_id <> p_actor_id AND EXISTS (
            SELECT 1 FROM api.community_relation_between_v1(s.user_id, p_actor_id)),
        v.status, v.suspended, v.grants, v.moderates, v.listed, v.trust_level,
        api.core_notification_push_enabled_v1(s.user_id,p_notification_type), stop_at
    FROM (SELECT c.user_id FROM candidates c ORDER BY c.user_id LIMIT page_size) s
    LEFT JOIN LATERAL api.notification_delivery_plan_v3(s.user_id,p_notification_type) plan ON true
    LEFT JOIN LATERAL api.forum_resolve_viewer_v9(s.user_id) v ON true
    ORDER BY s.user_id;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.notification_fanout_page_v1(
    text,uuid,text,uuid,uuid,uuid,uuid,integer) FROM PUBLIC;

CREATE FUNCTION api.notification_fanout_page_v2(
    p_target_type text, p_target_id uuid, p_notification_type text,
    p_actor_id uuid, p_excluded_user_id uuid,
    p_after_user_id uuid, p_through_user_id uuid, p_row_limit integer
)
RETURNS TABLE (
    user_id uuid, in_app boolean, email boolean, email_address text,
    locale text, event_type text, silenced boolean, status text,
    suspended boolean, grants json, moderates boolean, listed uuid[],
    trust_level integer, web_push boolean, through_user_id uuid
)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.notification_fanout_page_v1(
    p_target_type,p_target_id,p_notification_type,p_actor_id,p_excluded_user_id,
    p_after_user_id,p_through_user_id,p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_fanout_page_v2(
    text,uuid,text,uuid,uuid,uuid,uuid,integer) FROM PUBLIC;

COMMIT;
