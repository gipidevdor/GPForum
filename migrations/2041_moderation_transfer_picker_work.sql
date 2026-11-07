-- SPDX-FileCopyrightText: 2026 GPForum Contributors
-- SPDX-License-Identifier: BSD-3-Clause
BEGIN;
SET LOCAL lock_timeout = '3s';

-- Resolve the actor once for the whole picker, rather than once per candidate
-- thread. Keep v1/v2 unchanged for workers from the preceding release.
CREATE FUNCTION api.moderation_transfer_picker_v3(
    p_actor uuid, p_source_id uuid, p_query text, p_after_position bigint
)
RETURNS TABLE (result jsonb)
LANGUAGE plpgsql STABLE SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE
    source public.threads; choices jsonb; selected_posts jsonb; viewer record;
    member boolean := false; global_read boolean := false;
    category_ids uuid[] := '{}'; space_ids uuid[] := '{}';
BEGIN
    IF NOT api.core_product_staff_v1(p_actor,'thread','moderate') THEN
        RETURN QUERY SELECT jsonb_build_object('status','forbidden'); RETURN;
    END IF;
    IF length(coalesce(p_query,'')) > 100 OR coalesce(p_after_position,0) < 0 THEN
        RETURN QUERY SELECT jsonb_build_object('status','invalid'); RETURN;
    END IF;
    IF p_source_id IS NOT NULL THEN
        SELECT t.* INTO source FROM public.threads t
        WHERE t.thread_id = p_source_id AND t.deleted_at IS NULL
          AND t.moderation_state='visible' AND t.locked_at IS NULL
          AND t.visibility IN ('public','members')
          AND api.core_product_read_thread_v1(p_actor,t.thread_id)
          AND NOT EXISTS(SELECT 1 FROM public.thread_polls p WHERE p.thread_id=t.thread_id);
        IF source.thread_id IS NULL THEN
            RETURN QUERY SELECT jsonb_build_object('status','not_found'); RETURN;
        END IF;
    END IF;

    -- The same membership and grants as core_product_read_thread_v1, scoped
    -- to this statement. No permission state survives into another request.
    SELECT * INTO viewer FROM api.forum_resolve_viewer_v5(p_actor);
    member := FOUND AND viewer.status = 'active' AND NOT viewer.suspended;
    IF member THEN
        SELECT coalesce(bool_or(g->>'resource_type'='global'
                   AND g->>'resource_id' IS NULL AND g->>'space_id' IS NULL),false),
            coalesce(array_agg((g->>'resource_id')::uuid) FILTER (
                WHERE g->>'resource_type'='category' AND g->>'resource_id' IS NOT NULL),'{}'),
            coalesce(array_agg(coalesce(g->>'resource_id',g->>'space_id')::uuid) FILTER (
                WHERE g->>'resource_type'='space'
                  AND coalesce(g->>'resource_id',g->>'space_id') IS NOT NULL),'{}')
        INTO global_read,category_ids,space_ids
        FROM json_array_elements(viewer.grants) g;
    END IF;
    SELECT coalesce(jsonb_agg(x),'[]'::jsonb) INTO choices FROM (
        SELECT t.thread_id,t.title,c.title AS category_title
        FROM public.threads t JOIN public.categories c USING(category_id)
        JOIN public.spaces s USING(space_id)
        CROSS JOIN LATERAL (SELECT member AND (global_read
            OR c.category_id=ANY(category_ids) OR c.space_id=ANY(space_ids)) AS granted) scope
        WHERE t.deleted_at IS NULL AND t.moderation_state='visible'
          AND t.locked_at IS NULL AND t.visibility IN ('public','members')
          AND c.deleted_at IS NULL AND s.deleted_at IS NULL
          AND (s.visibility='public' OR (member AND s.visibility='members') OR scope.granted)
          AND (c.visibility='public' OR (member AND c.visibility='members') OR scope.granted)
          AND (t.visibility='public' OR (member AND t.visibility='members') OR scope.granted
            OR (member AND t.author_user_id=p_actor))
          AND (p_source_id IS NULL OR (t.thread_id<>p_source_id
            AND t.category_id=source.category_id AND t.visibility=source.visibility))
          AND t.title ILIKE '%' || coalesce(p_query,'') || '%'
          AND NOT EXISTS(SELECT 1 FROM public.thread_polls p WHERE p.thread_id=t.thread_id)
        ORDER BY t.last_activity_at DESC,t.thread_id DESC LIMIT 50
    ) x;
    SELECT coalesce(jsonb_agg(x),'[]'::jsonb) INTO selected_posts FROM (
        SELECT p.position,left(b.body_source,180) AS excerpt,u.display_name
        FROM public.posts p JOIN public.users u ON u.id=p.author_user_id
        LEFT JOIN public.post_bodies b ON b.body_id=p.current_body_id
        WHERE p.thread_id=p_source_id AND p.position>greatest(coalesce(p_after_position,0),1)
          AND p.deleted_at IS NULL AND p.visibility<>'private'
        ORDER BY p.position LIMIT 51
    ) x;
    RETURN QUERY SELECT jsonb_build_object('status','ok','choices',choices,'posts',selected_posts,
        'source',CASE WHEN p_source_id IS NULL THEN NULL ELSE
            jsonb_build_object('thread_id',source.thread_id,'title',source.title) END);
END;
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_transfer_picker_v3(uuid,uuid,text,bigint) FROM PUBLIC;

CREATE FUNCTION api.moderation_transfer_picker_v4(
    p_actor uuid,p_source_id uuid,p_query text,p_after_position bigint
)
RETURNS TABLE (result jsonb)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_transfer_picker_v3(p_actor,p_source_id,p_query,p_after_position);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_transfer_picker_v4(uuid,uuid,text,bigint) FROM PUBLIC;
COMMIT;
