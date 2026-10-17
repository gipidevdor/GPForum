-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

-- Search reads the thread and the post as they are when the query runs. A
-- hide or a delete leaves the index through the outbox, a while after it is
-- made, and until then the ranked search and the autocomplete answered from
-- the document alone: a hidden or deleted thread, and a hidden or deleted
-- post, stayed findable, title and body, for as long as the outbox took.
-- Both already read the thread's live category for each candidate (a
-- primary-key lookup, migration 102); that lookup now finds the thread only
-- when it is not deleted and visible or locked, and the post only when it
-- is not deleted and visible -- the rule search_index_entity_v1 indexes by.
-- A document the outbox has not removed yet matches no category and is not
-- shown. Everything else is api.search_ranked_v7 and
-- api.search_autocomplete_v5 as shipped. New versions, as ADR 0126 section 2
-- asks: the shipped ones stay.

BEGIN;
SET LOCAL lock_timeout = '1s';

CREATE FUNCTION api.search_ranked_v9(
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
    p_row_limit integer,
    p_entity_type text
)
RETURNS TABLE (entity_type text, entity_id uuid, category_id uuid, author_user_id uuid, space_id uuid, visibility text, title text, body text, source_created_at timestamptz, indexed_at timestamptz, rank_score double precision, author_username text, author_display_name text, category_visibility text, space_visibility text, candidate_count bigint)
LANGUAGE plpgsql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
BEGIN
RETURN QUERY
WITH ranked_page AS MATERIALIZED (
    SELECT candidate.search_document_id,
           candidate.entity_type, candidate.entity_id,
           candidate.source_created_at, candidate.indexed_at,
           candidate.category_visibility, candidate.space_visibility,
           greatest(
               ts_rank_cd(candidate.search_vector,
                   websearch_to_tsquery(p_config::regconfig, p_query), 32),
               public.similarity(candidate.title_normalized, lower(p_query)) * 0.2
           )::double precision AS rank_score,
           count(*) OVER () AS candidate_count
    FROM (
        SELECT me.search_document_id, me.entity_type, me.entity_id,
               me.source_created_at, me.indexed_at,
               me.search_vector, me.title_normalized,
               c.visibility AS category_visibility,
               s.visibility AS space_visibility
        FROM public.search_documents me
        JOIN public.categories c ON c.category_id = me.category_id
        JOIN public.spaces s ON s.space_id = me.space_id
        WHERE (CASE WHEN p_permission_mode = 'full' THEN c.deleted_at IS NULL AND (s.visibility IN ('public','members','private') AND (p_global_read OR s.visibility = 'public' OR (p_member AND s.visibility = 'members') OR (s.visibility = 'private' AND ((me.category_id = ANY(p_category_ids) OR me.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (c.visibility IN ('public','members','private') AND (p_global_read OR c.visibility = 'public' OR (p_member AND c.visibility = 'members') OR (c.visibility = 'private' AND ((me.category_id = ANY(p_category_ids) OR me.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (me.visibility IN ('public','members','private') AND (p_global_read OR me.visibility = 'public' OR (p_member AND me.visibility = 'members') OR (me.visibility = 'private' AND ((me.category_id = ANY(p_category_ids) OR me.space_id = ANY(p_space_ids)) OR (p_member AND (me.author_user_id = p_viewer_user_id)))))) ELSE me.visibility = ANY(p_visibility_values) END) AND me.category_id = (CASE me.entity_type WHEN 'thread' THEN (SELECT t.category_id FROM public.threads t WHERE t.thread_id = me.entity_id AND t.deleted_at IS NULL AND t.moderation_state IN ('visible','locked')) WHEN 'post' THEN (SELECT t.category_id FROM public.threads t WHERE t.thread_id = (SELECT p.thread_id FROM public.posts p WHERE p.post_id = me.entity_id AND p.deleted_at IS NULL AND p.moderation_state = 'visible') AND t.deleted_at IS NULL AND t.moderation_state IN ('visible','locked')) END) AND c.space_id = me.space_id AND (me.search_vector @@ websearch_to_tsquery(p_config::regconfig, p_query) OR me.title_normalized OPERATOR(public.%) lower(p_query) OR me.title_normalized LIKE lower(p_like_pattern) ESCAPE '\')
    AND (p_category_filter IS NULL OR me.category_id = p_category_filter) AND (p_author_filter IS NULL OR me.author_user_id = p_author_filter)
    AND (p_entity_type IS NULL OR me.entity_type = p_entity_type)
    AND (p_from_at IS NULL OR me.source_created_at >= p_from_at)
    AND (p_to_at IS NULL OR (p_to_exclusive AND me.source_created_at < p_to_at) OR (NOT p_to_exclusive AND me.source_created_at <= p_to_at))
        ORDER BY me.source_created_at DESC, me.entity_id DESC
        LIMIT p_candidate_limit
    ) candidate
    ORDER BY rank_score DESC, candidate.source_created_at DESC,
             candidate.indexed_at DESC, candidate.entity_type ASC,
             candidate.entity_id DESC
    LIMIT p_row_limit
)
SELECT page.entity_type, page.entity_id,
       document.category_id, document.author_user_id, document.space_id,
       document.visibility, document.title, document.body,
       page.source_created_at, page.indexed_at, page.rank_score,
       author.username, author.display_name,
       page.category_visibility, page.space_visibility, page.candidate_count
FROM ranked_page page
JOIN public.search_documents document
  ON document.search_document_id = page.search_document_id
LEFT JOIN public.users author ON author.id = document.author_user_id
ORDER BY page.rank_score DESC, page.source_created_at DESC,
         page.indexed_at DESC, page.entity_type ASC, page.entity_id DESC;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.search_ranked_v9(text, text[], boolean, boolean, uuid, uuid[], uuid[], text, text, text, integer, uuid, uuid, timestamptz, timestamptz, boolean, integer, text) FROM PUBLIC;

-- ADR 0127: the typed boundary the runtime role may call.
CREATE FUNCTION api.search_ranked_v10(
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
    p_row_limit integer,
    p_entity_type text
)
RETURNS TABLE (entity_type text, entity_id uuid, category_id uuid, author_user_id uuid, space_id uuid, visibility text, title text, body text, source_created_at timestamptz, indexed_at timestamptz, rank_score double precision, author_username text, author_display_name text, category_visibility text, space_visibility text, candidate_count bigint)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.search_ranked_v9(p_permission_mode, p_visibility_values, p_member, p_global_read, p_viewer_user_id, p_category_ids, p_space_ids, p_query, p_like_pattern, p_config, p_candidate_limit, p_category_filter, p_author_filter, p_from_at, p_to_at, p_to_exclusive, p_row_limit, p_entity_type)
$$;
REVOKE EXECUTE ON FUNCTION api.search_ranked_v10(text, text[], boolean, boolean, uuid, uuid[], uuid[], text, text, text, integer, uuid, uuid, timestamptz, timestamptz, boolean, integer, text) FROM PUBLIC;

CREATE FUNCTION api.search_autocomplete_v7(
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
RETURNS TABLE (entity_type text, entity_id uuid, category_id uuid, author_user_id uuid, space_id uuid, visibility text, title text, source_created_at timestamptz, author_username text, author_display_name text, category_visibility text, space_visibility text)
LANGUAGE plpgsql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
BEGIN
RETURN QUERY
WITH suggestion_page AS MATERIALIZED (
    SELECT me.search_document_id, me.entity_id,
           me.title_normalized, me.source_created_at,
           c.visibility AS category_visibility,
           s.visibility AS space_visibility
    FROM public.search_documents me
    JOIN public.categories c ON c.category_id = me.category_id
    JOIN public.spaces s ON s.space_id = me.space_id
    WHERE (CASE WHEN p_permission_mode = 'full' THEN c.deleted_at IS NULL AND (s.visibility IN ('public','members','private') AND (p_global_read OR s.visibility = 'public' OR (p_member AND s.visibility = 'members') OR (s.visibility = 'private' AND ((me.category_id = ANY(p_category_ids) OR me.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (c.visibility IN ('public','members','private') AND (p_global_read OR c.visibility = 'public' OR (p_member AND c.visibility = 'members') OR (c.visibility = 'private' AND ((me.category_id = ANY(p_category_ids) OR me.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (me.visibility IN ('public','members','private') AND (p_global_read OR me.visibility = 'public' OR (p_member AND me.visibility = 'members') OR (me.visibility = 'private' AND ((me.category_id = ANY(p_category_ids) OR me.space_id = ANY(p_space_ids)) OR (p_member AND (me.author_user_id = p_viewer_user_id)))))) ELSE me.visibility = ANY(p_visibility_values) END) AND me.category_id = (CASE me.entity_type WHEN 'thread' THEN (SELECT t.category_id FROM public.threads t WHERE t.thread_id = me.entity_id AND t.deleted_at IS NULL AND t.moderation_state IN ('visible','locked')) WHEN 'post' THEN (SELECT t.category_id FROM public.threads t WHERE t.thread_id = (SELECT p.thread_id FROM public.posts p WHERE p.post_id = me.entity_id AND p.deleted_at IS NULL AND p.moderation_state = 'visible') AND t.deleted_at IS NULL AND t.moderation_state IN ('visible','locked')) END) AND c.space_id = me.space_id AND me.entity_type = 'thread' AND me.title_normalized LIKE p_like_pattern
    ORDER BY me.title_normalized, me.source_created_at DESC, me.entity_id DESC
    LIMIT p_row_limit
)
SELECT document.entity_type, page.entity_id,
       document.category_id, document.author_user_id, document.space_id,
       document.visibility, document.title, page.source_created_at,
       author.username, author.display_name,
       page.category_visibility, page.space_visibility
FROM suggestion_page page
JOIN public.search_documents document
  ON document.search_document_id = page.search_document_id
LEFT JOIN public.users author ON author.id = document.author_user_id
ORDER BY page.title_normalized, page.source_created_at DESC, page.entity_id DESC;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.search_autocomplete_v7(text, text[], boolean, boolean, uuid, uuid[], uuid[], text, integer) FROM PUBLIC;

CREATE FUNCTION api.search_autocomplete_v8(
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
RETURNS TABLE (entity_type text, entity_id uuid, category_id uuid, author_user_id uuid, space_id uuid, visibility text, title text, source_created_at timestamptz, author_username text, author_display_name text, category_visibility text, space_visibility text)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.search_autocomplete_v7(p_permission_mode, p_visibility_values, p_member, p_global_read, p_viewer_user_id, p_category_ids, p_space_ids, p_like_pattern, p_row_limit)
$$;
REVOKE EXECUTE ON FUNCTION api.search_autocomplete_v8(text, text[], boolean, boolean, uuid, uuid[], uuid[], text, integer) FROM PUBLIC;

COMMIT;
