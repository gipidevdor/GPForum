-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

-- Search ranks bounded readable candidates. Projection updates acquire the
-- same document advisory locks before reading canonical content and writing.
BEGIN;
SET LOCAL lock_timeout = '1s';

CREATE FUNCTION api.search_ranked_v1(
    p_permission_mode text,
    p_visibility_values text[],
    p_member boolean,
    p_global_read boolean,
    p_viewer_user_id uuid,
    p_category_ids uuid[],
    p_space_ids uuid[],
    p_query text,
    p_like_pattern text,
    p_config text,
    p_candidate_limit integer,
    p_category_filter uuid,
    p_author_filter uuid,
    p_from_at timestamptz,
    p_to_at timestamptz,
    p_to_exclusive boolean,
    p_row_limit integer
)
RETURNS TABLE (search_document_id uuid, entity_type text, entity_id uuid, category_id uuid, author_user_id uuid, space_id uuid, visibility text, permission_scope text, visibility_version bigint, permission_version bigint, language text, title text, title_normalized text, body text, search_vector tsvector, source_version bigint, source_created_at timestamptz, indexed_at timestamptz, rank_score double precision, author_username text, author_display_name text, category_visibility text, space_visibility text, candidate_count bigint, source_thread_id uuid, source_thread_title text)
LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
SELECT me.search_document_id, me.entity_type, me.entity_id, me.category_id, me.author_user_id, me.space_id, me.visibility, me.permission_scope, me.visibility_version, me.permission_version, me.language, me.title, me.title_normalized, me.body, me.search_vector, me.source_version, me.source_created_at, me.indexed_at, greatest(ts_rank_cd(me.search_vector, websearch_to_tsquery(p_config::regconfig, p_query), 32), public.similarity(me.title_normalized, lower(p_query)) * 0.2), a.username, a.display_name, c.visibility, s.visibility, count(*) OVER (),
  CASE me.entity_type WHEN 'thread' THEN me.entity_id WHEN 'post' THEN (SELECT p.thread_id FROM public.posts p WHERE p.post_id = me.entity_id) END, (SELECT t.title FROM public.threads t WHERE t.thread_id = CASE me.entity_type WHEN 'thread' THEN me.entity_id WHEN 'post' THEN (SELECT p.thread_id FROM public.posts p WHERE p.post_id = me.entity_id) END)
FROM (SELECT me.* FROM public.search_documents me JOIN public.categories c ON c.category_id = me.category_id JOIN public.spaces s ON s.space_id = me.space_id
  WHERE (CASE WHEN p_permission_mode = 'full' THEN c.deleted_at IS NULL AND (s.visibility IN ('public','members','private') AND (p_global_read OR s.visibility = 'public' OR (p_member AND s.visibility = 'members') OR (s.visibility = 'private' AND ((me.category_id = ANY(p_category_ids) OR me.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (c.visibility IN ('public','members','private') AND (p_global_read OR c.visibility = 'public' OR (p_member AND c.visibility = 'members') OR (c.visibility = 'private' AND ((me.category_id = ANY(p_category_ids) OR me.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (me.visibility IN ('public','members','private') AND (p_global_read OR me.visibility = 'public' OR (p_member AND me.visibility = 'members') OR (me.visibility = 'private' AND ((me.category_id = ANY(p_category_ids) OR me.space_id = ANY(p_space_ids)) OR (p_member AND (me.author_user_id = p_viewer_user_id)))))) ELSE me.visibility = ANY(p_visibility_values) END) AND me.category_id = (CASE me.entity_type WHEN 'thread' THEN (SELECT t.category_id FROM public.threads t WHERE t.thread_id = me.entity_id) WHEN 'post' THEN (SELECT t.category_id FROM public.threads t WHERE t.thread_id = (SELECT p.thread_id FROM public.posts p WHERE p.post_id = me.entity_id)) END) AND c.space_id = me.space_id AND (me.search_vector @@ websearch_to_tsquery(p_config::regconfig, p_query) OR me.title_normalized OPERATOR(public.%) lower(p_query) OR me.title_normalized LIKE lower(p_like_pattern) ESCAPE '\')
    AND (p_category_filter IS NULL OR me.category_id = p_category_filter) AND (p_author_filter IS NULL OR me.author_user_id = p_author_filter)
    AND (p_from_at IS NULL OR me.source_created_at >= p_from_at)
    AND (p_to_at IS NULL OR (p_to_exclusive AND me.source_created_at < p_to_at) OR (NOT p_to_exclusive AND me.source_created_at <= p_to_at))
  ORDER BY me.source_created_at DESC, me.entity_id DESC LIMIT p_candidate_limit) me
LEFT JOIN public.users a ON a.id = me.author_user_id JOIN public.categories c ON c.category_id = me.category_id JOIN public.spaces s ON s.space_id = me.space_id
ORDER BY greatest(ts_rank_cd(me.search_vector, websearch_to_tsquery(p_config::regconfig, p_query), 32), public.similarity(me.title_normalized, lower(p_query)) * 0.2) DESC, me.source_created_at DESC, me.indexed_at DESC, me.entity_type ASC, me.entity_id DESC LIMIT p_row_limit
$$;
REVOKE EXECUTE ON FUNCTION api.search_ranked_v1(text, text[], boolean, boolean, uuid, uuid[], uuid[], text, text, text, integer, uuid, uuid, timestamptz, timestamptz, boolean, integer) FROM PUBLIC;

CREATE FUNCTION api.search_autocomplete_v1(
    p_permission_mode text,
    p_visibility_values text[],
    p_member boolean,
    p_global_read boolean,
    p_viewer_user_id uuid,
    p_category_ids uuid[],
    p_space_ids uuid[],
    p_like_pattern text,
    p_row_limit integer
)
RETURNS TABLE (search_document_id uuid, entity_type text, entity_id uuid, category_id uuid, author_user_id uuid, space_id uuid, visibility text, permission_scope text, visibility_version bigint, permission_version bigint, language text, title text, title_normalized text, body text, search_vector tsvector, source_version bigint, source_created_at timestamptz, indexed_at timestamptz, author_username text, author_display_name text, category_visibility text, space_visibility text)
LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
SELECT me.search_document_id, me.entity_type, me.entity_id, me.category_id, me.author_user_id, me.space_id, me.visibility, me.permission_scope, me.visibility_version, me.permission_version, me.language, me.title, me.title_normalized, me.body, me.search_vector, me.source_version, me.source_created_at, me.indexed_at, a.username, a.display_name, c.visibility, s.visibility
FROM public.search_documents me LEFT JOIN public.users a ON a.id = me.author_user_id JOIN public.categories c ON c.category_id = me.category_id JOIN public.spaces s ON s.space_id = me.space_id
WHERE (CASE WHEN p_permission_mode = 'full' THEN c.deleted_at IS NULL AND (s.visibility IN ('public','members','private') AND (p_global_read OR s.visibility = 'public' OR (p_member AND s.visibility = 'members') OR (s.visibility = 'private' AND ((me.category_id = ANY(p_category_ids) OR me.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (c.visibility IN ('public','members','private') AND (p_global_read OR c.visibility = 'public' OR (p_member AND c.visibility = 'members') OR (c.visibility = 'private' AND ((me.category_id = ANY(p_category_ids) OR me.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (me.visibility IN ('public','members','private') AND (p_global_read OR me.visibility = 'public' OR (p_member AND me.visibility = 'members') OR (me.visibility = 'private' AND ((me.category_id = ANY(p_category_ids) OR me.space_id = ANY(p_space_ids)) OR (p_member AND (me.author_user_id = p_viewer_user_id)))))) ELSE me.visibility = ANY(p_visibility_values) END) AND me.category_id = (CASE me.entity_type WHEN 'thread' THEN (SELECT t.category_id FROM public.threads t WHERE t.thread_id = me.entity_id) WHEN 'post' THEN (SELECT t.category_id FROM public.threads t WHERE t.thread_id = (SELECT p.thread_id FROM public.posts p WHERE p.post_id = me.entity_id)) END) AND c.space_id = me.space_id AND me.entity_type = 'thread' AND me.title_normalized LIKE p_like_pattern
ORDER BY me.title_normalized, me.source_created_at DESC, me.entity_id DESC LIMIT p_row_limit
$$;
REVOKE EXECUTE ON FUNCTION api.search_autocomplete_v1(text, text[], boolean, boolean, uuid, uuid[], uuid[], text, integer) FROM PUBLIC;

CREATE FUNCTION api.search_set_timeout_v1(
    p_timeout text
)
RETURNS TABLE (timeout text)
LANGUAGE sql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT set_config('statement_timeout', p_timeout, true)
$$;
REVOKE EXECUTE ON FUNCTION api.search_set_timeout_v1(text) FROM PUBLIC;

CREATE FUNCTION api.search_index_entity_v1(
    p_entity_type text,
    p_entity_id uuid,
    p_document_id uuid,
    p_indexed_at text
)
RETURNS TABLE (result jsonb)
LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE v public.search_documents%ROWTYPE; v_document jsonb; v_deleted bigint;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended('search_document:' || p_entity_type || ':' || p_entity_id::text, 0));
  IF p_entity_type = 'thread' THEN SELECT jsonb_build_object('entity_type', 'thread', 'entity_id', t.thread_id, 'category_id', t.category_id, 'author_user_id', t.author_user_id, 'space_id', c.space_id, 'visibility', t.visibility, 'permission_scope', t.visibility, 'visibility_version', t.visibility_version, 'permission_version', t.permission_version, 'language', 'simple', 'title', t.title, 'body', t.title, 'source_version', t.version, 'source_created_at', t.created_at::text) INTO v_document FROM public.threads t JOIN public.categories c ON c.category_id = t.category_id WHERE t.thread_id = p_entity_id AND t.deleted_at IS NULL AND t.moderation_state IN ('visible','locked');
  ELSIF p_entity_type = 'post' THEN SELECT jsonb_build_object('entity_type', 'post', 'entity_id', p.post_id, 'category_id', t.category_id, 'author_user_id', p.author_user_id, 'space_id', c.space_id, 'visibility', p.visibility, 'permission_scope', p.visibility, 'visibility_version', p.visibility_version, 'permission_version', p.permission_version, 'language', 'simple', 'title', t.title, 'body', COALESCE(NULLIF(b.body_rendered_safe, ''), NULLIF(b.body_source, ''), ''), 'source_version', p.version, 'source_created_at', p.created_at::text) INTO v_document FROM public.posts p JOIN public.threads t ON t.thread_id = p.thread_id JOIN public.categories c ON c.category_id = t.category_id LEFT JOIN public.post_bodies b ON b.body_id = p.current_body_id WHERE p.post_id = p_entity_id AND t.deleted_at IS NULL AND t.moderation_state IN ('visible','locked') AND p.deleted_at IS NULL AND p.moderation_state = 'visible';
  ELSE RAISE EXCEPTION 'unknown search entity type' USING ERRCODE = '22023'; END IF;
  IF v_document IS NULL THEN
    DELETE FROM public.search_documents d WHERE d.entity_type = p_entity_type AND d.entity_id = p_entity_id;
    GET DIAGNOSTICS v_deleted = ROW_COUNT;
    RETURN QUERY SELECT jsonb_build_object('ok', 1, 'removed', 1, 'deleted', v_deleted, 'entity_type', p_entity_type, 'entity_id', p_entity_id); RETURN;
  END IF;
  SELECT d.* INTO v FROM public.search_documents d WHERE d.entity_type = p_entity_type AND d.entity_id = p_entity_id;
  IF v.search_document_id IS NOT NULL AND COALESCE(v.author_user_id::text, '') = COALESCE(v_document->>'author_user_id', '') AND COALESCE(v.body::text, '') = COALESCE(v_document->>'body', '') AND COALESCE(v.category_id::text, '') = COALESCE(v_document->>'category_id', '') AND COALESCE(v.language::text, '') = COALESCE(v_document->>'language', '') AND COALESCE(v.permission_scope::text, '') = COALESCE(v_document->>'permission_scope', '') AND COALESCE(v.permission_version::text, '') = COALESCE(v_document->>'permission_version', '') AND COALESCE(v.source_created_at::text, '') = COALESCE(v_document->>'source_created_at', '') AND COALESCE(v.source_version::text, '') = COALESCE(v_document->>'source_version', '') AND COALESCE(v.space_id::text, '') = COALESCE(v_document->>'space_id', '') AND COALESCE(v.title::text, '') = COALESCE(v_document->>'title', '') AND COALESCE(v.visibility::text, '') = COALESCE(v_document->>'visibility', '') AND COALESCE(v.visibility_version::text, '') = COALESCE(v_document->>'visibility_version', '') THEN
    RETURN QUERY SELECT jsonb_build_object('entity_id', v.entity_id, 'entity_type', v.entity_type, 'indexed_at', v.indexed_at::text, 'skipped', 1, 'source_version', v.source_version); RETURN;
  END IF;
  INSERT INTO public.search_documents (search_document_id, entity_type, entity_id, author_user_id, body, category_id, language, permission_scope, permission_version, source_created_at, source_version, space_id, title, visibility, visibility_version, indexed_at, search_vector) VALUES (p_document_id, (v_document->>'entity_type'), (v_document->>'entity_id')::uuid, (v_document->>'author_user_id')::uuid, (v_document->>'body'), (v_document->>'category_id')::uuid, (v_document->>'language'), (v_document->>'permission_scope'), (v_document->>'permission_version')::bigint, (v_document->>'source_created_at')::timestamptz, (v_document->>'source_version')::bigint, (v_document->>'space_id')::uuid, (v_document->>'title'), (v_document->>'visibility'), (v_document->>'visibility_version')::bigint, p_indexed_at::timestamptz, setweight(to_tsvector('simple', COALESCE(v_document->>'title','')), 'A') || setweight(to_tsvector('simple', COALESCE(v_document->>'body','')), 'B'))
  ON CONFLICT (entity_type, entity_id) DO UPDATE SET search_document_id = EXCLUDED.search_document_id, author_user_id = EXCLUDED.author_user_id, body = EXCLUDED.body, category_id = EXCLUDED.category_id, language = EXCLUDED.language, permission_scope = EXCLUDED.permission_scope, permission_version = EXCLUDED.permission_version, source_created_at = EXCLUDED.source_created_at, source_version = EXCLUDED.source_version, space_id = EXCLUDED.space_id, title = EXCLUDED.title, visibility = EXCLUDED.visibility, visibility_version = EXCLUDED.visibility_version, indexed_at = EXCLUDED.indexed_at, search_vector = EXCLUDED.search_vector;
  RETURN QUERY SELECT v_document || jsonb_build_object('search_document_id', p_document_id, 'indexed_at', p_indexed_at);
END;
$$;
REVOKE EXECUTE ON FUNCTION api.search_index_entity_v1(text, uuid, uuid, text) FROM PUBLIC;

CREATE FUNCTION api.search_remove_document_v1(
    p_entity_type text,
    p_entity_id uuid
)
RETURNS TABLE (result jsonb)
LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE v_deleted bigint;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended('search_document:' || p_entity_type || ':' || p_entity_id::text, 0));
  DELETE FROM public.search_documents d WHERE d.entity_type = p_entity_type AND d.entity_id = p_entity_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RETURN QUERY SELECT jsonb_build_object('ok', 1, 'removed', 1, 'deleted', v_deleted, 'entity_type', p_entity_type, 'entity_id', p_entity_id);
END;
$$;
REVOKE EXECUTE ON FUNCTION api.search_remove_document_v1(text, uuid) FROM PUBLIC;

CREATE FUNCTION api.search_thread_post_batch_v1(
    p_thread_id uuid,
    p_after_position bigint,
    p_row_limit integer
)
RETURNS TABLE (post_id uuid, "position" bigint)
LANGUAGE plpgsql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
  IF p_after_position IS NULL THEN RETURN QUERY SELECT p.post_id, p.position FROM public.posts p WHERE p.thread_id = p_thread_id ORDER BY p.position LIMIT p_row_limit;
  ELSE RETURN QUERY SELECT p.post_id, p.position FROM public.posts p WHERE p.thread_id = p_thread_id AND p.position > p_after_position ORDER BY p.position LIMIT p_row_limit; END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.search_thread_post_batch_v1(uuid, bigint, integer) FROM PUBLIC;

CREATE FUNCTION api.search_live_ids_v1(
    p_entity_type text,
    p_after_id uuid,
    p_row_limit integer
)
RETURNS TABLE (entity_id uuid)
LANGUAGE plpgsql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
  IF p_entity_type = 'thread' THEN
    IF p_after_id IS NULL THEN RETURN QUERY SELECT t.thread_id FROM public.threads t WHERE t.deleted_at IS NULL AND t.moderation_state IN ('visible','locked') ORDER BY t.thread_id LIMIT p_row_limit;
    ELSE RETURN QUERY SELECT t.thread_id FROM public.threads t WHERE t.deleted_at IS NULL AND t.moderation_state IN ('visible','locked') AND t.thread_id > p_after_id ORDER BY t.thread_id LIMIT p_row_limit; END IF;
  ELSIF p_entity_type = 'post' THEN
    IF p_after_id IS NULL THEN RETURN QUERY SELECT p.post_id FROM public.posts p JOIN public.threads t ON t.thread_id = p.thread_id WHERE p.deleted_at IS NULL AND p.moderation_state = 'visible' AND t.deleted_at IS NULL AND t.moderation_state IN ('visible','locked') ORDER BY p.post_id LIMIT p_row_limit;
    ELSE RETURN QUERY SELECT p.post_id FROM public.posts p JOIN public.threads t ON t.thread_id = p.thread_id WHERE p.deleted_at IS NULL AND p.moderation_state = 'visible' AND t.deleted_at IS NULL AND t.moderation_state IN ('visible','locked') AND p.post_id > p_after_id ORDER BY p.post_id LIMIT p_row_limit; END IF;
  ELSE RAISE EXCEPTION 'unknown search entity type' USING ERRCODE = '22023'; END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.search_live_ids_v1(text, uuid, integer) FROM PUBLIC;

CREATE FUNCTION api.search_prune_candidates_v1(
    p_entity_type text
)
RETURNS TABLE (entity_id uuid)
LANGUAGE plpgsql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
  IF p_entity_type = 'thread' THEN RETURN QUERY SELECT d.entity_id FROM public.search_documents d WHERE d.entity_type = 'thread' AND NOT EXISTS (SELECT 1 FROM public.threads t WHERE t.thread_id = d.entity_id AND t.deleted_at IS NULL AND t.moderation_state IN ('visible','locked'));
  ELSIF p_entity_type = 'post' THEN RETURN QUERY SELECT d.entity_id FROM public.search_documents d WHERE d.entity_type = 'post' AND NOT EXISTS (SELECT 1 FROM public.posts p JOIN public.threads t ON t.thread_id = p.thread_id WHERE p.post_id = d.entity_id AND p.deleted_at IS NULL AND p.moderation_state = 'visible' AND t.deleted_at IS NULL AND t.moderation_state IN ('visible','locked'));
  ELSE RAISE EXCEPTION 'unknown search entity type' USING ERRCODE = '22023'; END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.search_prune_candidates_v1(text) FROM PUBLIC;

CREATE FUNCTION api.search_remove_post_batch_v1(
    p_thread_id uuid,
    p_post_ids uuid[]
)
RETURNS TABLE (removed bigint)
LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE v_deleted bigint;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended(k.lock_key, 0)) FROM (SELECT 'search_document:post:' || u::text AS lock_key FROM unnest(p_post_ids) u ORDER BY lock_key) k;
  IF EXISTS (SELECT 1 FROM public.threads t WHERE t.thread_id = p_thread_id AND t.deleted_at IS NULL AND t.moderation_state IN ('visible','locked')) THEN RETURN QUERY SELECT NULL::bigint; RETURN; END IF;
  DELETE FROM public.search_documents d WHERE d.entity_type = 'post' AND d.entity_id = ANY(p_post_ids);
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RETURN QUERY SELECT v_deleted;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.search_remove_post_batch_v1(uuid, uuid[]) FROM PUBLIC;

CREATE FUNCTION api.search_observe_lag_v1(

)
RETURNS TABLE (pending bigint, oldest_pending_at text, lag_seconds bigint)
LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT count(*), to_char(min(o.created_at) AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'), COALESCE(floor(extract(epoch FROM now() - min(o.created_at))), 0)::bigint FROM public.outbox_messages o WHERE o.status IN ('pending','running','failed')
$$;
REVOKE EXECUTE ON FUNCTION api.search_observe_lag_v1() FROM PUBLIC;

CREATE FUNCTION api.search_latest_rebuild_v1(

)
RETURNS TABLE (event_type text, payload text, created_at timestamptz)
LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT e.event_type, e.payload::text, e.created_at FROM public.event_log e WHERE e.aggregate_type = 'search_rebuild' AND e.aggregate_id = (SELECT last.aggregate_id FROM public.event_log last WHERE last.aggregate_type = 'search_rebuild' ORDER BY last.created_at DESC, last.event_id DESC LIMIT 1) ORDER BY (e.payload->>'step')::integer DESC LIMIT 1
$$;
REVOKE EXECUTE ON FUNCTION api.search_latest_rebuild_v1() FROM PUBLIC;

COMMIT;
