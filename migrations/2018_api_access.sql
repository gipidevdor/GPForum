-- SPDX-FileCopyrightText: 2026 GPForum Contributors
-- SPDX-License-Identifier: BSD-3-Clause

-- Fresh-database baseline: api access.
-- Final definitions only; see migrations/README.md for the dependency order.

BEGIN;
SET LOCAL lock_timeout = '1s';

CREATE FUNCTION api.core_product_staff_v1(p_actor uuid, p_resource text, p_action text)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT coalesce((SELECT p.allowed FROM api.admin_permission_allowed_v3(
    p_actor,p_resource,p_action,NULL,NULL) p),false)
    AND coalesce((SELECT m.ok = 1 FROM api.moderation_can_participate_v3(
        p_actor,statement_timestamp()) m),false)
    AND EXISTS(SELECT 1 FROM public.users u WHERE u.id = p_actor AND u.status = 'active')
$$;
REVOKE EXECUTE ON FUNCTION api.core_product_staff_v1(p_actor uuid, p_resource text, p_action text) FROM PUBLIC;

COMMIT;
