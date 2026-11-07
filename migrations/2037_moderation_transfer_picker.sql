-- SPDX-FileCopyrightText: 2026 GPForum Contributors
-- SPDX-License-Identifier: BSD-3-Clause
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE FUNCTION api.moderation_transfer_picker_v1(
    p_actor uuid, p_source_id uuid, p_query text, p_after_position bigint
)
RETURNS TABLE (result jsonb)
LANGUAGE plpgsql STABLE SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE source public.threads; choices jsonb; selected_posts jsonb;
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
    SELECT coalesce(jsonb_agg(x),'[]'::jsonb) INTO choices FROM (
        SELECT t.thread_id,t.title,c.title AS category_title
        FROM public.threads t JOIN public.categories c USING(category_id)
        WHERE t.deleted_at IS NULL AND t.moderation_state='visible'
          AND t.locked_at IS NULL AND t.visibility IN ('public','members')
          AND (p_source_id IS NULL OR (t.thread_id<>p_source_id
            AND t.category_id=source.category_id AND t.visibility=source.visibility))
          AND t.title ILIKE '%' || coalesce(p_query,'') || '%'
          AND NOT EXISTS(SELECT 1 FROM public.thread_polls p WHERE p.thread_id=t.thread_id)
          AND api.core_product_read_thread_v1(p_actor,t.thread_id)
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
REVOKE EXECUTE ON FUNCTION api.moderation_transfer_picker_v1(uuid,uuid,text,bigint) FROM PUBLIC;

CREATE FUNCTION api.moderation_transfer_picker_v2(
    p_actor uuid,p_source_id uuid,p_query text,p_after_position bigint
)
RETURNS TABLE (result jsonb)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.moderation_transfer_picker_v1(p_actor,p_source_id,p_query,p_after_position);
$$;
REVOKE EXECUTE ON FUNCTION api.moderation_transfer_picker_v2(uuid,uuid,text,bigint) FROM PUBLIC;
COMMIT;
