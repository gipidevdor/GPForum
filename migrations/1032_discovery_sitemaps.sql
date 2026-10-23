-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause
BEGIN;
SET LOCAL lock_timeout = '1s';

CREATE FUNCTION api.core_forum_sitemap_resources_v1()
RETURNS TABLE(kind text, resource_id uuid, slug text, changed_at timestamptz)
LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    SELECT 'category'::text, c.category_id, c.slug, c.updated_at
    FROM public.categories c JOIN public.spaces s USING(space_id)
    WHERE c.visibility = 'public' AND s.visibility = 'public'
      AND c.deleted_at IS NULL AND s.deleted_at IS NULL
    UNION ALL
    SELECT 'thread'::text, t.thread_id, t.slug, greatest(t.updated_at, t.last_activity_at)
    FROM public.threads t JOIN public.categories c USING(category_id)
    JOIN public.spaces s ON s.space_id = c.space_id
    WHERE t.visibility = 'public' AND c.visibility = 'public'
      AND s.visibility = 'public' AND t.deleted_at IS NULL
      AND c.deleted_at IS NULL AND s.deleted_at IS NULL
      AND t.moderation_state IN ('visible', 'locked')
$$;
REVOKE EXECUTE ON FUNCTION api.core_forum_sitemap_resources_v1() FROM PUBLIC;

CREATE FUNCTION api.forum_sitemap_count_v1()
RETURNS TABLE(total bigint)
LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$ SELECT count(*) FROM api.core_forum_sitemap_resources_v1() $$;
REVOKE EXECUTE ON FUNCTION api.forum_sitemap_count_v1() FROM PUBLIC;

CREATE FUNCTION api.forum_sitemap_page_v1(p_page integer)
RETURNS TABLE(kind text, resource_id uuid, slug text, changed_at timestamptz)
LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    SELECT * FROM api.core_forum_sitemap_resources_v1()
    ORDER BY kind, resource_id
    LIMIT 1000 OFFSET ((greatest(1, least(p_page, 50000)) - 1)::bigint * 1000)
$$;
REVOKE EXECUTE ON FUNCTION api.forum_sitemap_page_v1(integer) FROM PUBLIC;
CREATE FUNCTION api.forum_sitemap_count_v2()
RETURNS TABLE(total bigint)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$ SELECT * FROM api.forum_sitemap_count_v1(); $$;
REVOKE EXECUTE ON FUNCTION api.forum_sitemap_count_v2() FROM PUBLIC;

CREATE FUNCTION api.forum_sitemap_page_v2(p_page integer)
RETURNS TABLE(kind text, resource_id uuid, slug text, changed_at timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$ SELECT * FROM api.forum_sitemap_page_v1(p_page); $$;
REVOKE EXECUTE ON FUNCTION api.forum_sitemap_page_v2(integer) FROM PUBLIC;
COMMIT;
