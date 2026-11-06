-- SPDX-FileCopyrightText: 2026 GPForum Contributors
-- SPDX-License-Identifier: BSD-3-Clause
BEGIN;
SET LOCAL lock_timeout = '3s';

-- Install the pgvector package for this server major before migrating.
CREATE EXTENSION IF NOT EXISTS vector WITH SCHEMA public;

CREATE TABLE public.search_embeddings (
    search_document_id uuid PRIMARY KEY REFERENCES public.search_documents(search_document_id) ON DELETE CASCADE,
    model_key text NOT NULL CHECK (length(model_key) BETWEEN 1 AND 200),
    fingerprint text NOT NULL,
    embedding public.vector(384) NOT NULL CHECK (public.vector_norm(embedding) > 0),
    embedded_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.search_embeddings IS 'Rebuildable local semantic vectors for the current search projection; model keys must identify identical model weights and preprocessing.';
CREATE INDEX idx_search_embeddings_cosine ON public.search_embeddings
    USING hnsw (embedding public.vector_cosine_ops);

CREATE FUNCTION api.core_search_embedding_invalidate_v1()
RETURNS trigger LANGUAGE plpgsql VOLATILE SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    DELETE FROM public.search_embeddings e
    WHERE e.search_document_id = NEW.search_document_id;
    RETURN NEW;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.core_search_embedding_invalidate_v1() FROM PUBLIC;
CREATE TRIGGER search_embedding_invalidate AFTER UPDATE ON public.search_documents
FOR EACH ROW EXECUTE FUNCTION api.core_search_embedding_invalidate_v1();

CREATE FUNCTION api.search_embedding_source_v1(p_entity_type text,p_entity_id uuid,p_model_key text)
RETURNS TABLE(document_id uuid,fingerprint text,text text)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT d.search_document_id, md5(row(d.*)::text), left(d.title || E'\n' || d.body,2000)
FROM public.search_documents d
WHERE d.entity_type=p_entity_type AND d.entity_id=p_entity_id
AND NOT EXISTS (SELECT 1 FROM public.search_embeddings e
    WHERE e.search_document_id=d.search_document_id AND e.model_key=p_model_key
    AND e.fingerprint=md5(row(d.*)::text));
$$;
REVOKE EXECUTE ON FUNCTION api.search_embedding_source_v1(text,uuid,text) FROM PUBLIC;

CREATE FUNCTION api.search_embedding_source_v2(p_entity_type text,p_entity_id uuid,p_model_key text)
RETURNS TABLE(document_id uuid,fingerprint text,text text)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.search_embedding_source_v1(p_entity_type,p_entity_id,p_model_key);
$$;
REVOKE EXECUTE ON FUNCTION api.search_embedding_source_v2(text,uuid,text) FROM PUBLIC;

CREATE FUNCTION api.search_embedding_store_v1(p_document_id uuid,p_fingerprint text,p_model_key text,p_embedding text)
RETURNS TABLE(stored boolean)
LANGUAGE plpgsql VOLATILE SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE document public.search_documents;
BEGIN
    SELECT d.* INTO document FROM public.search_documents d
    WHERE d.search_document_id=p_document_id FOR UPDATE;
    IF document.search_document_id IS NULL OR md5(row(document.*)::text) <> p_fingerprint THEN
        RETURN QUERY SELECT false; RETURN;
    END IF;
    INSERT INTO public.search_embeddings(search_document_id,model_key,fingerprint,embedding)
    VALUES(p_document_id,p_model_key,p_fingerprint,p_embedding::public.vector(384))
    ON CONFLICT(search_document_id) DO UPDATE SET model_key=EXCLUDED.model_key,
        fingerprint=EXCLUDED.fingerprint,embedding=EXCLUDED.embedding,embedded_at=now();
    RETURN QUERY SELECT true;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.search_embedding_store_v1(uuid,text,text,text) FROM PUBLIC;

CREATE FUNCTION api.search_embedding_store_v2(p_document_id uuid,p_fingerprint text,p_model_key text,p_embedding text)
RETURNS TABLE(stored boolean)
LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.search_embedding_store_v1(p_document_id,p_fingerprint,p_model_key,p_embedding);
$$;
REVOKE EXECUTE ON FUNCTION api.search_embedding_store_v2(uuid,text,text,text) FROM PUBLIC;

CREATE FUNCTION api.search_semantic_ranked_v1(
    p_permission_mode text,
    p_visibility_values text[],
    p_member boolean,
    p_global_read boolean,
    p_viewer_user_id uuid,
    p_category_ids uuid[],
    p_space_ids uuid[],
    p_query text,
    p_config text,
    p_category_filter uuid,
    p_author_filter uuid,
    p_from_at timestamptz,
    p_to_at timestamptz,
    p_to_exclusive boolean,
    p_row_limit integer,
    p_entity_type text,
    p_thread_filter uuid,
    p_tag_slugs text[],
    p_tag_match text,
    p_model_key text,
    p_embedding text
)
RETURNS TABLE (
    entity_type text,
    entity_id uuid,
    category_id uuid,
    author_user_id uuid,
    space_id uuid,
    visibility text,
    title text,
    body text,
    source_created_at timestamptz,
    indexed_at timestamptz,
    rank_score double precision,
    author_username text,
    author_display_name text,
    category_visibility text,
    space_visibility text,
    candidate_count bigint,
    thread_owner_user_id uuid
)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
SET hnsw.iterative_scan = 'strict_order'
SET hnsw.ef_search = 100
AS $$
WITH nearest AS MATERIALIZED (
    SELECT me.search_document_id,
        1 - (e.embedding OPERATOR(public.<=>) p_embedding::public.vector(384)) AS score
    FROM public.search_embeddings e
    JOIN public.search_documents me USING(search_document_id)
    JOIN public.categories c ON c.category_id=me.category_id
    JOIN public.spaces s ON s.space_id=me.space_id
    WHERE e.model_key=p_model_key
    AND websearch_to_tsquery(p_config::regconfig,p_query)::text !~ '[!|<]'
    AND c.deleted_at IS NULL
    AND (p_permission_mode='full' OR (c.visibility='public' AND s.visibility='public'))
    -- Consult canonical visibility even while its reindex is queued. A
    -- post can be public while the thread containing it has become private.
    AND EXISTS (
        SELECT 1 FROM public.threads live_thread
        WHERE live_thread.thread_id=CASE me.entity_type WHEN 'thread' THEN me.entity_id
            ELSE (SELECT p.thread_id FROM public.posts p WHERE p.post_id=me.entity_id
                AND p.visibility=me.visibility) END
        AND (CASE WHEN p_permission_mode='full' THEN
            p_global_read OR live_thread.visibility='public'
            OR (p_member AND live_thread.visibility='members')
            OR (live_thread.visibility='private' AND (
                me.category_id=ANY(p_category_ids) OR me.space_id=ANY(p_space_ids)
                OR (p_member AND live_thread.author_user_id=p_viewer_user_id)))
            ELSE live_thread.visibility=ANY(p_visibility_values) END)
    )
    AND (CASE WHEN p_permission_mode = 'full' THEN c.deleted_at IS NULL AND (s.visibility IN ('public','members','private') AND (p_global_read OR s.visibility = 'public' OR (p_member AND s.visibility = 'members') OR (s.visibility = 'private' AND ((me.category_id = ANY(p_category_ids) OR me.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (c.visibility IN ('public','members','private') AND (p_global_read OR c.visibility = 'public' OR (p_member AND c.visibility = 'members') OR (c.visibility = 'private' AND ((me.category_id = ANY(p_category_ids) OR me.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (me.visibility IN ('public','members','private') AND (p_global_read OR me.visibility = 'public' OR (p_member AND me.visibility = 'members') OR (me.visibility = 'private' AND ((me.category_id = ANY(p_category_ids) OR me.space_id = ANY(p_space_ids)) OR (p_member AND (me.author_user_id = p_viewer_user_id OR (me.entity_type = 'post' AND EXISTS (SELECT 1 FROM public.posts op JOIN public.threads ot ON ot.thread_id = op.thread_id WHERE op.post_id = me.entity_id AND ot.visibility = 'private' AND ot.author_user_id = p_viewer_user_id)))))))) ELSE me.visibility = ANY(p_visibility_values) END) AND COALESCE(me.category_id = (CASE me.entity_type WHEN 'thread' THEN (SELECT t.category_id FROM public.threads t WHERE t.thread_id = me.entity_id AND t.deleted_at IS NULL AND t.moderation_state IN ('visible','locked')) WHEN 'post' THEN (SELECT t.category_id FROM public.threads t WHERE t.thread_id = (SELECT p.thread_id FROM public.posts p WHERE p.post_id = me.entity_id AND p.deleted_at IS NULL AND p.moderation_state = 'visible') AND t.deleted_at IS NULL AND t.moderation_state IN ('visible','locked')) END), false) AND c.space_id = me.space_id
    AND (p_category_filter IS NULL OR me.category_id = p_category_filter) AND (p_author_filter IS NULL OR me.author_user_id = p_author_filter)
    AND (p_entity_type IS NULL OR me.entity_type = p_entity_type)
    AND (p_from_at IS NULL OR me.source_created_at >= p_from_at)
    AND (p_to_at IS NULL OR (p_to_exclusive AND me.source_created_at < p_to_at) OR (NOT p_to_exclusive AND me.source_created_at <= p_to_at))

    AND (p_thread_filter IS NULL OR (me.entity_type,me.entity_id) IN (
        SELECT 'thread'::text,p_thread_filter UNION ALL
        SELECT 'post'::text,p.post_id FROM public.posts p WHERE p.thread_id=p_thread_filter))
    AND (cardinality(p_tag_slugs)=0 OR api.core_thread_matches_tags_v1(
        CASE me.entity_type WHEN 'thread' THEN me.entity_id
        ELSE (SELECT p.thread_id FROM public.posts p WHERE p.post_id=me.entity_id) END,
        p_tag_slugs,p_tag_match))
    AND e.embedding OPERATOR(public.<=>) p_embedding::public.vector(384) <= 0.6
    ORDER BY e.embedding OPERATOR(public.<=>) p_embedding::public.vector(384)
    LIMIT LEAST(GREATEST(p_row_limit,1),50)
)
SELECT me.entity_type,me.entity_id,me.category_id,me.author_user_id,me.space_id,
    me.visibility,me.title,me.body,me.source_created_at,me.indexed_at,
    n.score,author.username,author.display_name,c.visibility,s.visibility,
    count(*) OVER (),owner.author_user_id
FROM nearest n JOIN public.search_documents me USING(search_document_id)
JOIN public.categories c ON c.category_id=me.category_id
JOIN public.spaces s ON s.space_id=me.space_id
LEFT JOIN public.users author ON author.id=me.author_user_id
LEFT JOIN LATERAL (
    SELECT t.author_user_id FROM public.posts p JOIN public.threads t USING(thread_id)
    WHERE me.entity_type='post' AND p.post_id=me.entity_id AND t.visibility='private'
) owner ON true
ORDER BY n.score DESC,me.source_created_at DESC,me.entity_type,me.entity_id DESC;
$$;
REVOKE EXECUTE ON FUNCTION api.search_semantic_ranked_v1(text,text[],boolean,boolean,uuid,uuid[],uuid[],text,text,uuid,uuid,timestamptz,timestamptz,boolean,integer,text,uuid,text[],text,text,text) FROM PUBLIC;

CREATE FUNCTION api.search_semantic_ranked_v2(
    p_permission_mode text,
    p_visibility_values text[],
    p_member boolean,
    p_global_read boolean,
    p_viewer_user_id uuid,
    p_category_ids uuid[],
    p_space_ids uuid[],
    p_query text,
    p_config text,
    p_category_filter uuid,
    p_author_filter uuid,
    p_from_at timestamptz,
    p_to_at timestamptz,
    p_to_exclusive boolean,
    p_row_limit integer,
    p_entity_type text,
    p_thread_filter uuid,
    p_tag_slugs text[],
    p_tag_match text,
    p_model_key text,
    p_embedding text
)
RETURNS TABLE (
    entity_type text,
    entity_id uuid,
    category_id uuid,
    author_user_id uuid,
    space_id uuid,
    visibility text,
    title text,
    body text,
    source_created_at timestamptz,
    indexed_at timestamptz,
    rank_score double precision,
    author_username text,
    author_display_name text,
    category_visibility text,
    space_visibility text,
    candidate_count bigint,
    thread_owner_user_id uuid
)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
SELECT * FROM api.search_semantic_ranked_v1(p_permission_mode, p_visibility_values, p_member, p_global_read, p_viewer_user_id, p_category_ids, p_space_ids, p_query, p_config, p_category_filter, p_author_filter, p_from_at, p_to_at, p_to_exclusive, p_row_limit, p_entity_type, p_thread_filter, p_tag_slugs, p_tag_match, p_model_key, p_embedding);
$$;
REVOKE EXECUTE ON FUNCTION api.search_semantic_ranked_v2(text,text[],boolean,boolean,uuid,uuid[],uuid[],text,text,uuid,uuid,timestamptz,timestamptz,boolean,integer,text,uuid,text[],text,text,text) FROM PUBLIC;
COMMIT;
