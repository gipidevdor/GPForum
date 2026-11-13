-- SPDX-FileCopyrightText: 2026 GPForum Contributors
-- SPDX-License-Identifier: BSD-3-Clause
BEGIN;
SET LOCAL lock_timeout = '3s';

-- Whom an actor may suspend. A suspended member can no longer write in the
-- admin or moderation consoles, lifting a suspension included, so a
-- moderator who suspended the administrators locked them out of the web and
-- left only the command line to undo it. Staff -- a member holding any
-- permission beyond what members do (read, write, create): view, moderate,
-- suspend, manage, review, in any scope -- are suspended only by an actor
-- who manages the admin console, and nobody suspends themselves. Asked under
-- the member's lock, before the insert. (core_identity_is_staff_v1 counts
-- every role but category reading, the members' forum writing included.)
CREATE FUNCTION api.moderation_suspension_target_v1(p_actor uuid, p_user_id uuid)
RETURNS TABLE (result text)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT CASE
    WHEN p_actor IS NOT DISTINCT FROM p_user_id THEN 'self'
    WHEN EXISTS (SELECT 1 FROM public.role_bindings b
            JOIN public.role_permissions rp ON rp.role_id = b.role_id
            JOIN public.permissions p ON p.permission_id = rp.permission_id
            WHERE b.user_id = p_user_id AND b.revoked_at IS NULL
                AND p.action NOT IN ('read', 'write', 'create'))
        AND NOT coalesce(api.core_product_staff_v1(p_actor, 'admin_console', 'manage'), false)
        THEN 'staff'
    ELSE 'allowed'
END;
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_suspension_target_v1(p_actor uuid, p_user_id uuid) FROM PUBLIC;

CREATE FUNCTION api.moderation_suspension_target_v2(p_actor uuid, p_user_id uuid)
RETURNS TABLE (result text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_suspension_target_v1(p_actor, p_user_id);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_suspension_target_v2(p_actor uuid, p_user_id uuid) FROM PUBLIC;
COMMIT;
