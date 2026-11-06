-- SPDX-FileCopyrightText: 2026 GPForum Contributors
-- SPDX-License-Identifier: BSD-3-Clause
BEGIN;
SET LOCAL lock_timeout = '3s';

-- One bounded permission read on the menu page, never one read per link.
CREATE FUNCTION api.admin_navigation_context_v1(p_user_id uuid)
RETURNS TABLE (username text, permissions jsonb)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT u.username,
    CASE WHEN EXISTS (
        SELECT 1 FROM public.suspensions s
        WHERE s.user_id = u.id AND s.revoked_at IS NULL
          AND s.valid_from <= now() AND (s.valid_to IS NULL OR s.valid_to > now())
    ) THEN '{}'::jsonb ELSE COALESCE((
        SELECT jsonb_object_agg(granted.name, true)
        FROM (
            SELECT DISTINCT p.resource_type || '.' || p.action AS name
            FROM public.role_bindings b
            JOIN public.role_permissions rp ON rp.role_id = b.role_id
            JOIN public.permissions p ON p.permission_id = rp.permission_id
            WHERE b.user_id = u.id AND b.revoked_at IS NULL
              AND b.resource_id IS NULL AND b.space_id IS NULL
              AND (p.resource_type, p.action) IN (
                  ('admin_console', 'view'), ('thread', 'moderate'),
                  ('report', 'view_queue'), ('moderation_action', 'view'),
                  ('suspension', 'view'), ('privacy_rights', 'view')
              )
        ) granted
    ), '{}'::jsonb) END
FROM public.users u
WHERE u.id = p_user_id AND u.status = 'active' AND u.deleted_at IS NULL;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_navigation_context_v1(uuid) FROM PUBLIC;

CREATE FUNCTION api.admin_navigation_context_v2(p_user_id uuid)
RETURNS TABLE (username text, permissions jsonb)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_navigation_context_v1(p_user_id);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_navigation_context_v2(uuid) FROM PUBLIC;

COMMIT;
