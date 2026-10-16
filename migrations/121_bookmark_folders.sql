-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

-- A member files a bookmark in a folder of their own naming (ADR 0136):
-- a row of its own beside the bookmark, written after the bookmark
-- command, so the command is as it was. The bookmarks page lists one
-- folder or all, through a list version that joins the folder, and names
-- every folder with its count.

BEGIN;
SET LOCAL lock_timeout = '1s';

CREATE TABLE public.bookmark_folders (
    bookmark_id uuid NOT NULL,
    folder text NOT NULL,
    CONSTRAINT bookmark_folders_pkey PRIMARY KEY (bookmark_id),
    CONSTRAINT bookmark_folders_bookmark_id_fkey FOREIGN KEY (bookmark_id)
        REFERENCES public.bookmarks (bookmark_id) ON DELETE CASCADE,
    CONSTRAINT bookmark_folders_folder_check CHECK (length(folder) BETWEEN 1 AND 40)
);
CREATE INDEX idx_bookmark_folders_folder ON public.bookmark_folders (folder);

-- Files the member's own active bookmark in a folder; an empty folder
-- takes it out of its folder. A bookmark that is not the member's, or is
-- removed, is not filed, and nothing is answered.
CREATE FUNCTION api.community_set_bookmark_folder_v1(p_bookmark_id uuid,
    p_user_id uuid, p_folder text)
RETURNS TABLE (bookmark_id uuid, folder text)
LANGUAGE plpgsql
VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.bookmarks b
        WHERE b.bookmark_id = p_bookmark_id AND b.user_id = p_user_id
            AND b.deleted_at IS NULL)
    THEN
        RETURN;
    END IF;
    IF p_folder IS NULL OR p_folder = '' THEN
        DELETE FROM public.bookmark_folders f WHERE f.bookmark_id = p_bookmark_id;
        RETURN QUERY SELECT p_bookmark_id, NULL::text;
        RETURN;
    END IF;
    INSERT INTO public.bookmark_folders (bookmark_id, folder)
    VALUES (p_bookmark_id, p_folder)
    ON CONFLICT ON CONSTRAINT bookmark_folders_pkey
        DO UPDATE SET folder = EXCLUDED.folder;
    RETURN QUERY SELECT p_bookmark_id, p_folder;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.community_set_bookmark_folder_v1(uuid, uuid, text)
    FROM PUBLIC;

-- The member's folders, each with how many active bookmarks it holds.
CREATE FUNCTION api.community_list_bookmark_folders_v1(p_user_id uuid)
RETURNS TABLE (folder text, bookmark_count bigint)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT f.folder, count(*)
FROM public.bookmark_folders f
JOIN public.bookmarks b ON b.bookmark_id = f.bookmark_id
WHERE b.user_id = p_user_id AND b.deleted_at IS NULL
GROUP BY f.folder
ORDER BY f.folder
$$;
REVOKE EXECUTE ON FUNCTION api.community_list_bookmark_folders_v1(uuid) FROM PUBLIC;

-- The bookmark list of migration 062, with each bookmark's folder and, when
-- p_folder is given, only the bookmarks in it.
CREATE FUNCTION api.community_list_bookmarks_v3(
    p_user_id uuid,
    p_filter_sources boolean,
    p_member boolean,
    p_global_read boolean,
    p_viewer_user_id uuid,
    p_category_ids uuid[],
    p_space_ids uuid[],
    p_target_type text,
    p_after_created_at timestamptz,
    p_after_id uuid,
    p_row_limit integer,
    p_folder text
)
RETURNS TABLE (bookmark_id uuid, user_id uuid, target_type text, target_id uuid, note text, created_at timestamptz, deleted_at timestamptz, source_thread_id uuid, source_thread_title text, folder text)
LANGUAGE plpgsql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
BEGIN
  IF p_after_created_at IS NULL THEN
    RETURN QUERY SELECT b.bookmark_id, b.user_id, b.target_type, b.target_id, b.note, b.created_at, b.deleted_at, CASE WHEN p_filter_sources THEN CASE b.target_type WHEN 'thread' THEN b.target_id WHEN 'post' THEN (SELECT p.thread_id FROM public.posts p WHERE p.post_id = b.target_id) END END, CASE WHEN p_filter_sources THEN (SELECT t.title FROM public.threads t WHERE t.thread_id = CASE b.target_type WHEN 'thread' THEN b.target_id WHEN 'post' THEN (SELECT p.thread_id FROM public.posts p WHERE p.post_id = b.target_id) END) END, f.folder FROM public.bookmarks b LEFT JOIN public.bookmark_folders f ON f.bookmark_id = b.bookmark_id WHERE b.user_id = p_user_id AND b.deleted_at IS NULL AND (p_target_type IS NULL OR b.target_type = p_target_type) AND (p_folder IS NULL OR f.folder = p_folder) AND (NOT p_filter_sources OR ((b.target_type = 'thread' AND EXISTS (SELECT 1 FROM public.threads t JOIN public.categories c ON c.category_id = t.category_id JOIN public.spaces s ON s.space_id = c.space_id WHERE t.thread_id = b.target_id AND t.deleted_at IS NULL AND t.moderation_state IN ('visible', 'locked') AND c.deleted_at IS NULL AND (s.visibility IN ('public', 'members', 'private') AND (p_global_read OR s.visibility = 'public' OR (p_member AND s.visibility = 'members') OR (s.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (c.visibility IN ('public', 'members', 'private') AND (p_global_read OR c.visibility = 'public' OR (p_member AND c.visibility = 'members') OR (c.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (t.visibility IN ('public', 'members', 'private') AND (p_global_read OR t.visibility = 'public' OR (p_member AND t.visibility = 'members') OR (t.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (t.author_user_id = p_viewer_user_id)))))))) OR (b.target_type = 'post' AND EXISTS (SELECT 1 FROM public.posts p JOIN public.threads t ON t.thread_id = p.thread_id JOIN public.categories c ON c.category_id = t.category_id JOIN public.spaces s ON s.space_id = c.space_id WHERE p.post_id = b.target_id AND p.deleted_at IS NULL AND p.moderation_state = 'visible' AND t.deleted_at IS NULL AND t.moderation_state IN ('visible', 'locked') AND c.deleted_at IS NULL AND (s.visibility IN ('public', 'members', 'private') AND (p_global_read OR s.visibility = 'public' OR (p_member AND s.visibility = 'members') OR (s.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (c.visibility IN ('public', 'members', 'private') AND (p_global_read OR c.visibility = 'public' OR (p_member AND c.visibility = 'members') OR (c.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (t.visibility IN ('public', 'members', 'private') AND (p_global_read OR t.visibility = 'public' OR (p_member AND t.visibility = 'members') OR (t.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (t.author_user_id = p_viewer_user_id)))))) AND (p.visibility IN ('public', 'members', 'private') AND (p_global_read OR p.visibility = 'public' OR (p_member AND p.visibility = 'members') OR (p.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (p.author_user_id = p_viewer_user_id OR (t.visibility = 'private' AND t.author_user_id = p_viewer_user_id)))))))))))
    ORDER BY b.created_at DESC, b.bookmark_id DESC LIMIT p_row_limit;
  ELSE
    RETURN QUERY SELECT b.bookmark_id, b.user_id, b.target_type, b.target_id, b.note, b.created_at, b.deleted_at, CASE WHEN p_filter_sources THEN CASE b.target_type WHEN 'thread' THEN b.target_id WHEN 'post' THEN (SELECT p.thread_id FROM public.posts p WHERE p.post_id = b.target_id) END END, CASE WHEN p_filter_sources THEN (SELECT t.title FROM public.threads t WHERE t.thread_id = CASE b.target_type WHEN 'thread' THEN b.target_id WHEN 'post' THEN (SELECT p.thread_id FROM public.posts p WHERE p.post_id = b.target_id) END) END, f.folder FROM public.bookmarks b LEFT JOIN public.bookmark_folders f ON f.bookmark_id = b.bookmark_id WHERE b.user_id = p_user_id AND b.deleted_at IS NULL AND (p_target_type IS NULL OR b.target_type = p_target_type) AND (p_folder IS NULL OR f.folder = p_folder) AND (NOT p_filter_sources OR ((b.target_type = 'thread' AND EXISTS (SELECT 1 FROM public.threads t JOIN public.categories c ON c.category_id = t.category_id JOIN public.spaces s ON s.space_id = c.space_id WHERE t.thread_id = b.target_id AND t.deleted_at IS NULL AND t.moderation_state IN ('visible', 'locked') AND c.deleted_at IS NULL AND (s.visibility IN ('public', 'members', 'private') AND (p_global_read OR s.visibility = 'public' OR (p_member AND s.visibility = 'members') OR (s.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (c.visibility IN ('public', 'members', 'private') AND (p_global_read OR c.visibility = 'public' OR (p_member AND c.visibility = 'members') OR (c.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (t.visibility IN ('public', 'members', 'private') AND (p_global_read OR t.visibility = 'public' OR (p_member AND t.visibility = 'members') OR (t.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (t.author_user_id = p_viewer_user_id)))))))) OR (b.target_type = 'post' AND EXISTS (SELECT 1 FROM public.posts p JOIN public.threads t ON t.thread_id = p.thread_id JOIN public.categories c ON c.category_id = t.category_id JOIN public.spaces s ON s.space_id = c.space_id WHERE p.post_id = b.target_id AND p.deleted_at IS NULL AND p.moderation_state = 'visible' AND t.deleted_at IS NULL AND t.moderation_state IN ('visible', 'locked') AND c.deleted_at IS NULL AND (s.visibility IN ('public', 'members', 'private') AND (p_global_read OR s.visibility = 'public' OR (p_member AND s.visibility = 'members') OR (s.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (c.visibility IN ('public', 'members', 'private') AND (p_global_read OR c.visibility = 'public' OR (p_member AND c.visibility = 'members') OR (c.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (t.visibility IN ('public', 'members', 'private') AND (p_global_read OR t.visibility = 'public' OR (p_member AND t.visibility = 'members') OR (t.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (t.author_user_id = p_viewer_user_id)))))) AND (p.visibility IN ('public', 'members', 'private') AND (p_global_read OR p.visibility = 'public' OR (p_member AND p.visibility = 'members') OR (p.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (p.author_user_id = p_viewer_user_id OR (t.visibility = 'private' AND t.author_user_id = p_viewer_user_id)))))))))))
      AND b.created_at <= p_after_created_at
      AND (b.created_at < p_after_created_at OR (b.created_at = p_after_created_at AND b.bookmark_id < p_after_id))
    ORDER BY b.created_at DESC, b.bookmark_id DESC LIMIT p_row_limit;
  END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.community_list_bookmarks_v3(uuid, boolean, boolean, boolean, uuid, uuid[], uuid[], text, timestamptz, uuid, integer, text) FROM PUBLIC;

-- ADR 0127: the typed boundaries the runtime role may call.
CREATE FUNCTION api.community_set_bookmark_folder_v2(
p_bookmark_id uuid, p_user_id uuid, p_folder text
)
RETURNS TABLE (bookmark_id uuid, folder text)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_set_bookmark_folder_v1(p_bookmark_id, p_user_id,
    p_folder);
$$;
REVOKE EXECUTE ON FUNCTION api.community_set_bookmark_folder_v2(uuid, uuid, text)
    FROM PUBLIC;

CREATE FUNCTION api.community_list_bookmark_folders_v2(
p_user_id uuid
)
RETURNS TABLE (folder text, bookmark_count bigint)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_list_bookmark_folders_v1(p_user_id);
$$;
REVOKE EXECUTE ON FUNCTION api.community_list_bookmark_folders_v2(uuid) FROM PUBLIC;

CREATE FUNCTION api.community_list_bookmarks_v4(
p_user_id uuid, p_filter_sources boolean, p_member boolean,
p_global_read boolean, p_viewer_user_id uuid, p_category_ids uuid[],
p_space_ids uuid[], p_target_type text, p_after_created_at timestamptz,
p_after_id uuid, p_row_limit integer, p_folder text
)
RETURNS TABLE (bookmark_id uuid, user_id uuid, target_type text, target_id uuid,
    note text, created_at timestamptz, deleted_at timestamptz,
    source_thread_id uuid, source_thread_title text, folder text)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
SELECT * FROM api.community_list_bookmarks_v3(p_user_id, p_filter_sources,
    p_member, p_global_read, p_viewer_user_id, p_category_ids, p_space_ids,
    p_target_type, p_after_created_at, p_after_id, p_row_limit, p_folder);
$$;
REVOKE EXECUTE ON FUNCTION api.community_list_bookmarks_v4(uuid, boolean, boolean,
    boolean, uuid, uuid[], uuid[], text, timestamptz, uuid, integer, text)
    FROM PUBLIC;

COMMIT;
