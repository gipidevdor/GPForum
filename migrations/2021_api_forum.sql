-- SPDX-FileCopyrightText: 2026 GPForum Contributors
-- SPDX-License-Identifier: BSD-3-Clause

-- Fresh-database baseline: api forum.
-- Final definitions only; see migrations/README.md for the dependency order.

BEGIN;
SET LOCAL lock_timeout = '1s';

CREATE FUNCTION api.forum_active_announcements_v1(p_row_limit integer)
RETURNS SETOF api.admin_announcement_v1
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
    SELECT announcement_id, message, tone, created_by, created_at, retired_by,
        retired_at FROM public.site_announcements a
    WHERE a.retired_at IS NULL
    ORDER BY a.created_at DESC, a.announcement_id DESC
    LIMIT p_row_limit;
$$;
REVOKE EXECUTE ON FUNCTION api.forum_active_announcements_v1(p_row_limit integer) FROM PUBLIC;

CREATE FUNCTION api.forum_create_reply_v3(
    p_idempotency_key text,
    p_command_type text,
    p_actor_id text,
    p_request_hash text,
    p_command_id text,
    p_command_correlation_id text,
    p_command_at text,
    p_answer jsonb,
    p_store_refusals jsonb,
    p_post_id text,
    p_thread_id text,
    p_author_user_id text,
    p_current_body_id text,
    p_current_revision_id text,
    p_position bigint,
    p_visibility text,
    p_moderation_state text,
    p_version bigint,
    p_visibility_version bigint,
    p_permission_version bigint,
    p_hidden_at text,
    p_locked_at text,
    p_deleted_at text,
    p_deleted_by text,
    p_body_id text,
    p_body_post_id text,
    p_body_format text,
    p_body_source text,
    p_body_rendered_safe text,
    p_source_hash text,
    p_revision_id text,
    p_revision_post_id text,
    p_revision_body_id text,
    p_editor_user_id text,
    p_revision_number integer,
    p_edit_reason text,
    p_correlation_id text,
    p_event_id text,
    p_outbox_id text,
    p_audit_id text,
    p_recorded_at text,
    p_draft_id uuid,
    p_draft_revision bigint
)
RETURNS TABLE (
    outcome text,
    response json,
    skipped boolean,
    post_id text,
    thread_id text,
    author_user_id text,
    current_body_id text,
    current_revision_id text,
    "position" text,
    visibility text,
    moderation_state text,
    version text,
    visibility_version text,
    permission_version text,
    hidden_at text,
    locked_at text,
    deleted_at text,
    deleted_by text
)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
#variable_conflict use_column
DECLARE
    existing public.command_log;
    held record;
    row_command_id text := p_command_id;
    held_payload jsonb := jsonb_build_object('request_hash', p_request_hash);
    from_store boolean := false;
    reported text;
    answer jsonb;
    stored record;
    draft_error text;
BEGIN
    IF p_draft_id IS NOT NULL THEN
        PERFORM pg_advisory_xact_lock(hashtextextended('forum.draft.publish:' || p_idempotency_key,0));
    END IF;
    SELECT me.* INTO existing FROM public.command_log me
    WHERE me.idempotency_key = p_idempotency_key
    LIMIT 1;
    IF FOUND THEN
        SELECT * INTO held
        FROM api.core_command_existing_v1(existing.payload, p_request_hash);
        RETURN QUERY SELECT held.outcome, held.response::json,
            NULL::boolean, NULL::text, NULL::text, NULL::text, NULL::text,
            NULL::text, NULL::text, NULL::text, NULL::text, NULL::text,
            NULL::text, NULL::text, NULL::text, NULL::text, NULL::text,
            NULL::text;
        RETURN;
    END IF;

    IF p_draft_id IS NOT NULL THEN
        draft_error := api.core_forum_draft_publish_v1(p_actor_id::uuid,p_draft_id,
            p_draft_revision,'reply',NULL,p_thread_id::uuid,p_idempotency_key,
            p_command_at::timestamptz,p_answer IS NULL);
        IF draft_error IS NOT NULL THEN
            RETURN QUERY SELECT 'recorded'::text,
                json_build_object('ok',0,'status','conflict','error',draft_error),
                NULL::boolean, NULL::text, NULL::text, NULL::text, NULL::text,
                NULL::text, NULL::text, NULL::text, NULL::text, NULL::text,
                NULL::text, NULL::text, NULL::text, NULL::text, NULL::text,
                NULL::text;
            RETURN;
        END IF;
    END IF;
    BEGIN
        INSERT INTO public.command_log (actor_id, command_id, command_type,
            correlation_id, created_at, handled_at, idempotency_key, payload,
            response_hash, status)
        VALUES (p_actor_id::uuid, p_command_id::uuid, p_command_type,
            p_command_correlation_id::uuid, p_command_at::timestamptz, NULL,
            p_idempotency_key, held_payload, NULL, 'accepted');
    EXCEPTION WHEN unique_violation THEN
        GET STACKED DIAGNOSTICS reported = CONSTRAINT_NAME;
        IF api.core_unique_on_v1(reported, 'command_log_pkey') THEN
            SELECT me.* INTO existing FROM public.command_log me
            WHERE me.command_id = p_command_id::uuid;
            IF NOT FOUND OR existing.idempotency_key IS NULL
                OR existing.idempotency_key <> p_idempotency_key
            THEN
                row_command_id := api.core_uuid_v7_v1()::text;
                INSERT INTO public.command_log (actor_id, command_id,
                    command_type, correlation_id, created_at, handled_at,
                    idempotency_key, payload, response_hash, status)
                VALUES (p_actor_id::uuid, row_command_id::uuid,
                    p_command_type, p_command_correlation_id::uuid,
                    p_command_at::timestamptz, NULL, p_idempotency_key,
                    held_payload, NULL, 'accepted');
            ELSIF jsonb_typeof(existing.payload) = 'object'
                AND existing.payload ? 'response'
            THEN
                SELECT * INTO held FROM api.core_command_existing_v1(
                    existing.payload, p_request_hash);
                RETURN QUERY SELECT held.outcome, held.response::json,
                    NULL::boolean, NULL::text, NULL::text, NULL::text,
                    NULL::text, NULL::text, NULL::text, NULL::text,
                    NULL::text, NULL::text, NULL::text, NULL::text,
                    NULL::text, NULL::text, NULL::text, NULL::text;
                RETURN;
            ELSE
                row_command_id := existing.command_id::text;
                held_payload := CASE
                    WHEN jsonb_typeof(existing.payload) = 'object'
                    THEN existing.payload ELSE '{}'::jsonb END;
            END IF;
        ELSIF api.core_unique_on_v1(reported,
            'command_log_idempotency_key_key') THEN
            SELECT me.* INTO existing FROM public.command_log me
            WHERE me.idempotency_key = p_idempotency_key
            LIMIT 1;
            IF NOT FOUND THEN
                RAISE;
            END IF;
            SELECT * INTO held
            FROM api.core_command_existing_v1(existing.payload,
                p_request_hash);
            RETURN QUERY SELECT held.outcome, held.response::json,
                NULL::boolean, NULL::text, NULL::text, NULL::text,
                NULL::text, NULL::text, NULL::text, NULL::text, NULL::text,
                NULL::text, NULL::text, NULL::text, NULL::text, NULL::text,
                NULL::text, NULL::text;
            RETURN;
        ELSE
            RAISE;
        END IF;
    END;

    IF p_answer IS NOT NULL THEN
        answer := p_answer;
    ELSE
        from_store := true;
        SELECT * INTO stored FROM api.core_forum_store_reply_v1(p_post_id,
            p_thread_id, p_author_user_id, p_current_body_id,
            p_current_revision_id, p_position, p_visibility,
            p_moderation_state, p_version, p_visibility_version,
            p_permission_version, p_hidden_at, p_locked_at, p_deleted_at,
            p_deleted_by, p_body_id, p_body_post_id, p_body_format,
            p_body_source, p_body_rendered_safe, p_source_hash,
            p_revision_id, p_revision_post_id, p_revision_body_id,
            p_editor_user_id, p_revision_number, p_edit_reason,
            p_idempotency_key, p_correlation_id, p_event_id, p_outbox_id,
            p_audit_id, p_recorded_at);
        answer := CASE WHEN stored.refusal IS NOT NULL
            THEN p_store_refusals -> stored.refusal
            ELSE jsonb_build_object('ok', 1,
                'post_id', stored.post_id,
                'status', 'ok',
                'thread_id', stored.thread_id) END;
        IF answer IS NULL THEN
            RAISE EXCEPTION USING ERRCODE = 'invalid_parameter_value',
                MESSAGE = 'p_store_refusals has no words for '
                    || stored.refusal;
        END IF;
    END IF;

    UPDATE public.command_log me
    SET handled_at = p_command_at::timestamptz,
        payload = held_payload || jsonb_build_object('response', answer),
        response_hash = encode(sha256(convert_to(
            api.core_canonical_json_v1(answer), 'UTF8')), 'hex'),
        status = CASE WHEN api.core_perl_true_v1(answer ->> 'ok')
            THEN 'handled' ELSE 'rejected' END
    WHERE me.command_id = row_command_id::uuid;

    IF p_draft_id IS NOT NULL AND api.core_perl_true_v1(answer->>'ok') THEN
        DELETE FROM public.forum_drafts d WHERE d.draft_id=p_draft_id;
    END IF;

    IF NOT from_store THEN
        RETURN QUERY SELECT 'recorded'::text, answer::json, NULL::boolean,
            NULL::text, NULL::text, NULL::text, NULL::text, NULL::text,
            NULL::text, NULL::text, NULL::text, NULL::text, NULL::text,
            NULL::text, NULL::text, NULL::text, NULL::text, NULL::text;
        RETURN;
    END IF;
    RETURN QUERY SELECT 'recorded'::text, answer::json, stored.skipped,
        stored.post_id, stored.thread_id, stored.author_user_id,
        stored.current_body_id, stored.current_revision_id, stored.position,
        stored.visibility, stored.moderation_state, stored.version,
        stored.visibility_version, stored.permission_version,
        stored.hidden_at, stored.locked_at, stored.deleted_at,
        stored.deleted_by;
END
$$;
REVOKE EXECUTE ON FUNCTION api.forum_create_reply_v3(p_idempotency_key text, p_command_type text, p_actor_id text, p_request_hash text, p_command_id text, p_command_correlation_id text, p_command_at text, p_answer jsonb, p_store_refusals jsonb, p_post_id text, p_thread_id text, p_author_user_id text, p_current_body_id text, p_current_revision_id text, p_position bigint, p_visibility text, p_moderation_state text, p_version bigint, p_visibility_version bigint, p_permission_version bigint, p_hidden_at text, p_locked_at text, p_deleted_at text, p_deleted_by text, p_body_id text, p_body_post_id text, p_body_format text, p_body_source text, p_body_rendered_safe text, p_source_hash text, p_revision_id text, p_revision_post_id text, p_revision_body_id text, p_editor_user_id text, p_revision_number integer, p_edit_reason text, p_correlation_id text, p_event_id text, p_outbox_id text, p_audit_id text, p_recorded_at text, p_draft_id uuid, p_draft_revision bigint) FROM PUBLIC;

CREATE FUNCTION api.forum_draft_find_v1(
    p_owner_user_id uuid,
    p_draft_id uuid,
    p_now timestamptz
)
RETURNS TABLE (draft json)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT to_json(d) FROM public.forum_drafts d
JOIN public.users u ON u.id = d.owner_user_id
WHERE d.owner_user_id = p_owner_user_id AND d.draft_id = p_draft_id
    AND d.expires_at > p_now AND u.deleted_at IS NULL AND u.status = 'active';
$$;
REVOKE EXECUTE ON FUNCTION api.forum_draft_find_v1(p_owner_user_id uuid, p_draft_id uuid, p_now timestamp with time zone) FROM PUBLIC;

CREATE FUNCTION api.forum_draft_list_v1(
    p_owner_user_id uuid,
    p_now timestamptz
)
RETURNS TABLE (draft json)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT (to_jsonb(d) - 'body_source' - 'save_base_revision' - 'save_command_id')::json FROM public.forum_drafts d
JOIN public.users u ON u.id = d.owner_user_id
WHERE d.owner_user_id = p_owner_user_id AND d.expires_at > p_now
    AND u.deleted_at IS NULL AND u.status = 'active'
ORDER BY d.updated_at DESC, d.draft_id DESC LIMIT 100;
$$;
REVOKE EXECUTE ON FUNCTION api.forum_draft_list_v1(p_owner_user_id uuid, p_now timestamp with time zone) FROM PUBLIC;

CREATE FUNCTION api.forum_draft_purge_v1(
    p_now timestamptz,
    p_row_limit integer
)
RETURNS TABLE (deleted bigint)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE amount bigint;
BEGIN
    DELETE FROM public.forum_drafts d WHERE d.draft_id IN (
        SELECT expired.draft_id FROM public.forum_drafts expired
        WHERE expired.expires_at <= p_now ORDER BY expired.expires_at,expired.draft_id
        LIMIT least(greatest(coalesce(p_row_limit,100),1),1000)
        FOR UPDATE SKIP LOCKED);
    GET DIAGNOSTICS amount = ROW_COUNT;
    RETURN QUERY SELECT amount;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.forum_draft_purge_v1(p_now timestamp with time zone, p_row_limit integer) FROM PUBLIC;

CREATE FUNCTION api.forum_draft_remove_v1(
    p_owner_user_id uuid,
    p_draft_id uuid,
    p_draft_revision bigint,
    p_now timestamptz
)
RETURNS TABLE (status text, draft json, error text)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE held public.forum_drafts;
BEGIN
    SELECT d.* INTO held FROM public.forum_drafts d
        WHERE d.draft_id=p_draft_id AND d.owner_user_id=p_owner_user_id FOR UPDATE;
    IF NOT FOUND THEN RETURN QUERY SELECT 'not_found'::text,NULL::json,'draft not found'::text; RETURN; END IF;
    IF p_draft_revision IS NULL OR held.draft_revision <> p_draft_revision THEN
        RETURN QUERY SELECT 'conflict'::text,NULL::json,'draft changed'::text; RETURN;
    END IF;
    DELETE FROM public.forum_drafts d WHERE d.draft_id=p_draft_id;
    RETURN QUERY SELECT 'ok'::text,NULL::json,NULL::text;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.forum_draft_remove_v1(p_owner_user_id uuid, p_draft_id uuid, p_draft_revision bigint, p_now timestamp with time zone) FROM PUBLIC;

CREATE FUNCTION api.forum_find_category_v1(p_category_id uuid)
RETURNS TABLE (
    category_id uuid,
    space_id uuid,
    slug text,
    title text,
    description text,
    visibility text,
    "position" integer,
    version bigint,
    permission_version bigint,
    created_at timestamptz,
    updated_at timestamptz,
    deleted_at timestamptz,
    space_visibility text
)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT me.category_id, me.space_id, me.slug, me.title, me.description, me.visibility, me.position, me.version, me.permission_version, me.created_at, me.updated_at, me.deleted_at, space.visibility
FROM public.categories me
JOIN public.spaces space ON space.space_id = me.space_id
WHERE me.category_id = p_category_id
LIMIT 1
$$;
REVOKE EXECUTE ON FUNCTION api.forum_find_category_v1(p_category_id uuid) FROM PUBLIC;

CREATE FUNCTION api.forum_find_post_v1(p_post_id uuid)
RETURNS SETOF api.forum_post_v1
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT me.post_id, me.thread_id, me.author_user_id, me.current_body_id,
    me.current_revision_id, me."position", me.visibility, me.moderation_state,
    me.version, me.visibility_version, me.permission_version, me.created_at,
    me.updated_at, me.hidden_at, me.locked_at, me.deleted_at, me.deleted_by
FROM public.posts me WHERE me.post_id = p_post_id
$$;
REVOKE EXECUTE ON FUNCTION api.forum_find_post_v1(p_post_id uuid) FROM PUBLIC;

CREATE FUNCTION api.forum_find_visible_post_v1(p_post_id uuid)
RETURNS TABLE (
    post_id uuid,
    thread_id uuid,
    author_user_id uuid,
    current_body_id uuid,
    current_revision_id uuid,
    "position" bigint,
    visibility text,
    moderation_state text,
    version bigint,
    visibility_version bigint,
    permission_version bigint,
    created_at timestamptz,
    updated_at timestamptz,
    hidden_at timestamptz,
    locked_at timestamptz,
    deleted_at timestamptz,
    deleted_by uuid,
    thread_visibility text,
    thread_author uuid,
    category_id uuid,
    category_visibility text,
    space_id uuid,
    space_visibility text
)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT me.post_id, me.thread_id, me.author_user_id, me.current_body_id, me.current_revision_id, me.position, me.visibility, me.moderation_state, me.version, me.visibility_version, me.permission_version, me.created_at, me.updated_at, me.hidden_at, me.locked_at, me.deleted_at, me.deleted_by, thread.visibility,
    thread.author_user_id, thread.category_id, category.visibility,
    category.space_id, space.visibility
FROM public.posts me
JOIN public.threads thread ON thread.thread_id = me.thread_id
JOIN public.categories category ON category.category_id = thread.category_id
JOIN public.spaces space ON space.space_id = category.space_id
WHERE me.post_id = p_post_id
    AND me.deleted_at IS NULL AND me.moderation_state = 'visible'
    AND thread.deleted_at IS NULL
    AND thread.moderation_state IN ('visible', 'locked')
LIMIT 1
$$;
REVOKE EXECUTE ON FUNCTION api.forum_find_visible_post_v1(p_post_id uuid) FROM PUBLIC;

CREATE FUNCTION api.forum_list_categories_v3(
    p_member boolean,
    p_global_read boolean,
    p_category_ids uuid[],
    p_space_ids uuid[],
    p_row_limit integer
)
RETURNS TABLE (
    category_id uuid,
    space_id uuid,
    slug text,
    title text,
    description text,
    visibility text,
    "position" integer,
    version bigint,
    permission_version bigint,
    created_at timestamptz,
    updated_at timestamptz,
    deleted_at timestamptz,
    thread_count bigint,
    last_activity_at timestamptz
)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
SELECT me.category_id, me.space_id, me.slug, me.title, me.description,
    me.visibility, me.position, me.version, me.permission_version,
    me.created_at, me.updated_at, me.deleted_at,
    activity.thread_count, activity.last_activity_at
FROM public.categories me
JOIN public.spaces space ON space.space_id = me.space_id
CROSS JOIN LATERAL (
    SELECT count(*) AS thread_count,
        max(thread.last_activity_at) AS last_activity_at
    FROM public.threads thread
    WHERE thread.category_id = me.category_id
        AND thread.deleted_at IS NULL
        AND thread.moderation_state IN ('visible', 'locked')
        AND (p_global_read
            OR thread.visibility = 'public'
            OR (p_member AND thread.visibility = 'members'))
) AS activity
WHERE me.deleted_at IS NULL
    AND (me.visibility IN ('public', 'members', 'private')
        AND (p_global_read OR me.visibility = 'public'
            OR (p_member AND me.visibility = 'members')
            OR (me.visibility = 'private' AND
                (me.category_id = ANY(p_category_ids)
                    OR me.space_id = ANY(p_space_ids)))))
    AND (space.visibility IN ('public', 'members', 'private')
        AND (p_global_read OR space.visibility = 'public'
            OR (p_member AND space.visibility = 'members')
            OR (space.visibility = 'private' AND
                (me.category_id = ANY(p_category_ids)
                    OR me.space_id = ANY(p_space_ids)))))
ORDER BY me.position ASC, me.title ASC, me.category_id ASC
LIMIT p_row_limit
$$;
REVOKE EXECUTE ON FUNCTION api.forum_list_categories_v3(p_member boolean, p_global_read boolean, p_category_ids uuid[], p_space_ids uuid[], p_row_limit integer) FROM PUBLIC;

CREATE FUNCTION api.forum_list_tagged_threads_v1(
    p_tag_slug text,
    p_category_id uuid,
    p_member boolean,
    p_global_read boolean,
    p_scope_user_id uuid,
    p_category_ids uuid[],
    p_space_ids uuid[],
    p_row_limit integer
)
RETURNS TABLE (
    thread_id uuid,
    category_id uuid,
    author_user_id uuid,
    title text,
    slug text,
    pinned boolean,
    visibility text,
    moderation_state text,
    locked_at timestamptz,
    last_activity_at timestamptz,
    created_at timestamptz,
    deleted_at timestamptz,
    author_username text,
    author_display_name text,
    category_title text,
    reply_count bigint
)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT me.thread_id, me.category_id, me.author_user_id, me.title, me.slug,
    me.pinned, me.visibility, me.moderation_state, me.locked_at,
    me.last_activity_at, me.created_at, me.deleted_at, author.username,
    author.display_name, category.title,
    COALESCE((SELECT counter.reply_count
        FROM public.thread_counters counter
        WHERE counter.thread_id = me.thread_id), 0)
FROM public.thread_tags tt
JOIN public.tags tag ON tag.tag_id = tt.tag_id
JOIN public.threads me ON me.thread_id = tt.thread_id
JOIN public.users author ON author.id = me.author_user_id
JOIN public.categories category ON category.category_id = me.category_id
JOIN public.spaces space ON space.space_id = category.space_id
WHERE tag.slug = p_tag_slug
    AND (p_category_id IS NULL OR me.category_id = p_category_id)
    AND me.deleted_at IS NULL
    AND me.moderation_state IN ('visible', 'locked')
    AND (p_global_read OR me.visibility = 'public'
        OR (p_member AND me.visibility = 'members')
        OR (me.visibility = 'private' AND p_member
            AND me.author_user_id = p_scope_user_id))
    AND (p_global_read OR category.visibility = 'public'
        OR (p_member AND category.visibility = 'members')
        OR (category.visibility = 'private' AND
            (me.category_id = ANY(p_category_ids)
                OR category.space_id = ANY(p_space_ids))))
    AND (p_global_read OR space.visibility = 'public'
        OR (p_member AND space.visibility = 'members')
        OR (space.visibility = 'private' AND
            (me.category_id = ANY(p_category_ids)
                OR category.space_id = ANY(p_space_ids))))
ORDER BY me.last_activity_at DESC, me.thread_id DESC
LIMIT p_row_limit
$$;
REVOKE EXECUTE ON FUNCTION api.forum_list_tagged_threads_v1(p_tag_slug text, p_category_id uuid, p_member boolean, p_global_read boolean, p_scope_user_id uuid, p_category_ids uuid[], p_space_ids uuid[], p_row_limit integer) FROM PUBLIC;

CREATE FUNCTION api.forum_list_tags_v1(
    p_member boolean,
    p_global_read boolean,
    p_scope_user_id uuid,
    p_category_ids uuid[],
    p_space_ids uuid[],
    p_row_limit integer
)
RETURNS TABLE (slug text, name text, thread_count bigint)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT tag.slug, tag.name, count(*) AS thread_count
FROM public.thread_tags tt
JOIN public.tags tag ON tag.tag_id = tt.tag_id
JOIN public.threads me ON me.thread_id = tt.thread_id
JOIN public.categories category ON category.category_id = me.category_id
JOIN public.spaces space ON space.space_id = category.space_id
WHERE me.deleted_at IS NULL
    AND me.moderation_state IN ('visible', 'locked')
    AND (p_global_read OR me.visibility = 'public'
        OR (p_member AND me.visibility = 'members')
        OR (me.visibility = 'private' AND p_member
            AND me.author_user_id = p_scope_user_id))
    AND (p_global_read OR category.visibility = 'public'
        OR (p_member AND category.visibility = 'members')
        OR (category.visibility = 'private' AND
            (me.category_id = ANY(p_category_ids)
                OR category.space_id = ANY(p_space_ids))))
    AND (p_global_read OR space.visibility = 'public'
        OR (p_member AND space.visibility = 'members')
        OR (space.visibility = 'private' AND
            (me.category_id = ANY(p_category_ids)
                OR category.space_id = ANY(p_space_ids))))
GROUP BY tag.tag_id, tag.slug, tag.name
ORDER BY count(*) DESC, tag.name, tag.slug
LIMIT p_row_limit
$$;
REVOKE EXECUTE ON FUNCTION api.forum_list_tags_v1(p_member boolean, p_global_read boolean, p_scope_user_id uuid, p_category_ids uuid[], p_space_ids uuid[], p_row_limit integer) FROM PUBLIC;

CREATE FUNCTION api.forum_mark_read_v1(p_row jsonb)
RETURNS TABLE (result jsonb)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE v public.thread_read_state%ROWTYPE; v_position bigint := (p_row->>'last_read_position')::bigint;
  v_previous bigint := 0; v_raced boolean := false; v_state jsonb;
BEGIN
  SELECT r.* INTO v FROM public.thread_read_state r WHERE r.user_id = (p_row->>'user_id')::uuid AND r.thread_id = (p_row->>'thread_id')::uuid FOR UPDATE;
  IF v.user_id IS NULL THEN
    INSERT INTO public.thread_read_state (user_id, thread_id, last_read_position, last_read_at)
    VALUES ((p_row->>'user_id')::uuid, (p_row->>'thread_id')::uuid, v_position, (p_row->>'last_read_at')::timestamptz)
    ON CONFLICT (user_id, thread_id) DO NOTHING;
    IF FOUND THEN
      INSERT INTO public.user_read_marker_deltas (user_id, thread_id, last_read_position, last_read_at)
      VALUES ((p_row->>'user_id')::uuid, (p_row->>'thread_id')::uuid, v_position, (p_row->>'last_read_at')::timestamptz)
      ON CONFLICT (user_id, thread_id) DO NOTHING;
      RETURN QUERY SELECT jsonb_build_object('ok', 1, 'advanced', CASE WHEN v_position > 0 THEN 1 ELSE 0 END, 'read_state', p_row); RETURN;
    END IF;
    v_raced := true;
    SELECT r.* INTO v FROM public.thread_read_state r WHERE r.user_id = (p_row->>'user_id')::uuid AND r.thread_id = (p_row->>'thread_id')::uuid FOR UPDATE;
  END IF;
  v_previous := v.last_read_position;
  IF v.last_read_at IS NOT NULL AND v_position <= v_previous THEN
    IF v_raced THEN
      INSERT INTO public.user_read_marker_deltas (user_id, thread_id, last_read_position, last_read_at)
      VALUES (v.user_id, v.thread_id, v.last_read_position, v.last_read_at) ON CONFLICT (user_id, thread_id) DO NOTHING;
    END IF;
    RETURN QUERY SELECT jsonb_build_object('ok', 1, 'advanced', 0, 'skipped', 1,
      'read_state', to_jsonb(v) || jsonb_build_object('last_read_at', v.last_read_at::text)); RETURN;
  END IF;
  v_position := greatest(v_previous, v_position);
  UPDATE public.thread_read_state r SET last_read_position = v_position, last_read_at = (p_row->>'last_read_at')::timestamptz
  WHERE r.user_id = v.user_id AND r.thread_id = v.thread_id;
  INSERT INTO public.user_read_marker_deltas (user_id, thread_id, last_read_position, last_read_at)
  VALUES (v.user_id, v.thread_id, v_position, (p_row->>'last_read_at')::timestamptz)
  ON CONFLICT (user_id, thread_id) DO UPDATE SET last_read_position = EXCLUDED.last_read_position, last_read_at = EXCLUDED.last_read_at;
  v_state := p_row || jsonb_build_object('last_read_position', v_position);
  RETURN QUERY SELECT jsonb_build_object('ok', 1, 'advanced', CASE WHEN v_position > v_previous THEN 1 ELSE 0 END, 'read_state', v_state);
END;
$$;
REVOKE EXECUTE ON FUNCTION api.forum_mark_read_v1(p_row jsonb) FROM PUBLIC;

CREATE FUNCTION api.forum_thread_page_head_v1(p_thread_id uuid)
RETURNS TABLE (
    thread_id uuid,
    category_id uuid,
    author_user_id uuid,
    title text,
    slug text,
    pinned boolean,
    visibility text,
    moderation_state text,
    locked_at timestamptz,
    last_activity_at timestamptz,
    deleted_at timestamptz,
    author_username text,
    author_display_name text,
    category_title text,
    category_visibility text,
    space_id uuid,
    space_visibility text
)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT me.thread_id, me.category_id, me.author_user_id, me.title, me.slug,
    me.pinned, me.visibility, me.moderation_state, me.locked_at,
    me.last_activity_at, me.deleted_at, author.username, author.display_name,
    category.title, category.visibility, category.space_id, space.visibility
FROM public.threads me
JOIN public.users author ON author.id = me.author_user_id
JOIN public.categories category ON category.category_id = me.category_id
JOIN public.spaces space ON space.space_id = category.space_id
WHERE me.thread_id = p_thread_id
LIMIT 1
$$;
REVOKE EXECUTE ON FUNCTION api.forum_thread_page_head_v1(p_thread_id uuid) FROM PUBLIC;

CREATE FUNCTION api.forum_post_placement_v1(p_source_id uuid)
RETURNS TABLE (
    category_id uuid,
    category_visibility text,
    space_id uuid,
    space_visibility text,
    thread_author uuid,
    thread_visibility text,
    post_author uuid,
    post_visibility text,
    thread_deleted_at timestamptz,
    thread_state text,
    category_deleted_at timestamptz,
    post_deleted_at timestamptz,
    post_state text
)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT c.category_id, c.visibility, c.space_id, s.visibility,
    t.author_user_id, t.visibility, p.author_user_id, p.visibility,
    t.deleted_at, t.moderation_state, c.deleted_at, p.deleted_at, p.moderation_state
FROM public.posts p
JOIN public.threads t ON t.thread_id = p.thread_id
JOIN public.categories c ON c.category_id = t.category_id
JOIN public.spaces s ON s.space_id = c.space_id
WHERE p.post_id = p_source_id
$$;
REVOKE EXECUTE ON FUNCTION api.forum_post_placement_v1(p_source_id uuid) FROM PUBLIC;

CREATE FUNCTION api.forum_read_marker_command_v1(
    p_log jsonb,
    p_answer jsonb,
    p_row jsonb
)
RETURNS TABLE (outcome text, response json)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE
    opened record;
    answer jsonb := p_answer;
    marked jsonb;
    state jsonb;
BEGIN
    SELECT * INTO opened FROM api.core_command_open_v1(p_log);
    IF opened.outcome <> 'opened' THEN
        RETURN QUERY SELECT opened.outcome, opened.response::json;
        RETURN;
    END IF;
    IF answer IS NULL THEN
        SELECT result INTO marked FROM api.forum_mark_read_v1(p_row);
        state := CASE WHEN jsonb_typeof(marked -> 'read_state') = 'object'
            THEN marked -> 'read_state' ELSE '{}'::jsonb END;
        answer := jsonb_build_object(
            'advanced', CASE WHEN api.core_perl_true_v1(marked ->> 'advanced')
                THEN 1 ELSE 0 END,
            'ok', 1,
            'read_state', jsonb_build_object(
                'last_read_at', state -> 'last_read_at',
                'last_read_position', state -> 'last_read_position',
                'thread_id', state -> 'thread_id',
                'user_id', state -> 'user_id'),
            'status', 'ok');
    END IF;
    PERFORM api.core_command_close_v1(opened.command_id,
        p_log ->> 'command_at', opened.payload, answer);
    RETURN QUERY SELECT 'recorded'::text, answer::json;
END
$$;
REVOKE EXECUTE ON FUNCTION api.forum_read_marker_command_v1(p_log jsonb, p_answer jsonb, p_row jsonb) FROM PUBLIC;

CREATE FUNCTION api.forum_read_state_v1(p_user_id uuid, p_thread_id uuid)
RETURNS SETOF api.forum_read_state_v1
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT r.user_id, r.thread_id, r.last_read_position, r.last_read_at
FROM public.thread_read_state r WHERE r.user_id = p_user_id AND r.thread_id = p_thread_id
$$;
REVOKE EXECUTE ON FUNCTION api.forum_read_state_v1(p_user_id uuid, p_thread_id uuid) FROM PUBLIC;

CREATE FUNCTION api.forum_reply_targets_v1(p_post_ids uuid[])
RETURNS TABLE (
    post_id uuid,
    reply_to_post_id uuid,
    reply_to_position bigint,
    reply_to_author_username text
)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT r.post_id, r.reply_to_post_id, target.position, author.username
FROM public.post_replies r
JOIN public.posts target ON target.post_id = r.reply_to_post_id
LEFT JOIN public.users author ON author.id = target.author_user_id
WHERE r.post_id = ANY(p_post_ids)
$$;
REVOKE EXECUTE ON FUNCTION api.forum_reply_targets_v1(p_post_ids uuid[]) FROM PUBLIC;

CREATE FUNCTION api.forum_resolve_viewer_v1(p_user_id uuid)
RETURNS TABLE (status text, suspended boolean, grants json)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT u.status,
    EXISTS (SELECT 1 FROM public.suspensions s WHERE s.user_id = u.id
        AND s.revoked_at IS NULL AND s.valid_from <= now()
        AND (s.valid_to IS NULL OR s.valid_to > now())) AS suspended,
    coalesce((SELECT json_agg(json_build_object('resource_type',
        b.resource_type, 'resource_id', b.resource_id, 'space_id', b.space_id))
        FROM public.role_bindings b
        JOIN public.role_permissions rp ON rp.role_id = b.role_id
        JOIN public.permissions p ON p.permission_id = rp.permission_id
        WHERE b.user_id = u.id AND b.revoked_at IS NULL
            AND p.resource_type = 'category' AND p.action = 'read'), '[]')
    FROM public.users u WHERE u.id = p_user_id
$$;
REVOKE EXECUTE ON FUNCTION api.forum_resolve_viewer_v1(p_user_id uuid) FROM PUBLIC;

CREATE FUNCTION api.forum_resolve_viewer_v3(p_user_id uuid)
RETURNS TABLE (status text, suspended boolean, grants json, moderates boolean)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT u.status,
    EXISTS (SELECT 1 FROM public.suspensions s WHERE s.user_id = u.id
        AND s.revoked_at IS NULL AND s.valid_from <= now()
        AND (s.valid_to IS NULL OR s.valid_to > now())) AS suspended,
    coalesce((SELECT json_agg(json_build_object('resource_type',
        b.resource_type, 'resource_id', b.resource_id, 'space_id', b.space_id))
        FROM public.role_bindings b
        JOIN public.role_permissions rp ON rp.role_id = b.role_id
        JOIN public.permissions p ON p.permission_id = rp.permission_id
        WHERE b.user_id = u.id AND b.revoked_at IS NULL
            AND p.resource_type = 'category' AND p.action = 'read'), '[]')
        AS grants,
    -- The global binding is the one the moderation routes accept for every
    -- thread (Controller::Moderation::Base scopes a write to the thread or
    -- to nothing); a binding on one thread or one space is not the page's.
    EXISTS (SELECT 1 FROM public.role_bindings b
        JOIN public.role_permissions rp ON rp.role_id = b.role_id
        JOIN public.permissions p ON p.permission_id = rp.permission_id
        WHERE b.user_id = u.id AND b.revoked_at IS NULL
            AND b.resource_id IS NULL AND b.space_id IS NULL
            AND p.resource_type = 'thread' AND p.action = 'moderate')
        AS moderates
    FROM public.users u WHERE u.id = p_user_id
$$;
REVOKE EXECUTE ON FUNCTION api.forum_resolve_viewer_v3(p_user_id uuid) FROM PUBLIC;

CREATE FUNCTION api.forum_thread_page_posts_v1(
    p_thread_id uuid,
    p_standing text,
    p_viewer_user_id uuid,
    p_after_position bigint,
    p_after_post_id uuid,
    p_row_limit integer
)
RETURNS TABLE (
    post_id uuid,
    thread_id uuid,
    author_user_id uuid,
    current_body_id uuid,
    "position" bigint,
    visibility text,
    moderation_state text,
    created_at timestamptz,
    deleted_at timestamptz,
    body text,
    body_source text,
    author_username text,
    author_display_name text
)
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
#variable_conflict use_column
BEGIN
    IF p_standing = 'global' AND p_viewer_user_id IS NULL
          AND p_after_post_id IS NULL THEN
        -- posts:global:any:first
        RETURN QUERY
        SELECT me.post_id, me.thread_id, me.author_user_id,
            me.current_body_id, me.position, me.visibility, me.moderation_state, me.created_at,
            me.deleted_at, current_body.body_rendered_safe,
            current_body.body_source, author.username, author.display_name
        FROM public.posts me
        LEFT JOIN public.post_bodies current_body
            ON current_body.body_id = me.current_body_id
        JOIN public.users author ON author.id = me.author_user_id
        WHERE me.visibility IN ('public', 'members', 'private')
            AND me.deleted_at IS NULL
            AND me.moderation_state = 'visible'
            AND me.thread_id = p_thread_id
        ORDER BY me.position ASC, me.post_id ASC
        LIMIT p_row_limit;
    ELSIF p_standing = 'global' AND p_viewer_user_id IS NULL
          AND p_after_post_id IS NOT NULL THEN
        -- posts:global:any:after
        RETURN QUERY
        SELECT me.post_id, me.thread_id, me.author_user_id,
            me.current_body_id, me.position, me.visibility, me.moderation_state, me.created_at,
            me.deleted_at, current_body.body_rendered_safe,
            current_body.body_source, author.username, author.display_name
        FROM public.posts me
        LEFT JOIN public.post_bodies current_body
            ON current_body.body_id = me.current_body_id
        JOIN public.users author ON author.id = me.author_user_id
        WHERE ( me.visibility IN ('public', 'members', 'private')
                AND ( ( me.position > p_after_position
                    OR ( me.position = p_after_position
                        AND me.post_id > p_after_post_id ) )
                AND me.position >= p_after_position ) )
            AND me.deleted_at IS NULL
            AND me.moderation_state = 'visible'
            AND me.thread_id = p_thread_id
        ORDER BY me.position ASC, me.post_id ASC
        LIMIT p_row_limit;
    ELSIF p_standing = 'global' AND p_viewer_user_id IS NOT NULL
          AND p_after_post_id IS NULL THEN
        -- posts:global:own:first
        RETURN QUERY
        SELECT me.post_id, me.thread_id, me.author_user_id,
            me.current_body_id, me.position, me.visibility, me.moderation_state, me.created_at,
            me.deleted_at, current_body.body_rendered_safe,
            current_body.body_source, author.username, author.display_name
        FROM public.posts me
        LEFT JOIN public.post_bodies current_body
            ON current_body.body_id = me.current_body_id
        JOIN public.users author ON author.id = me.author_user_id
        WHERE me.visibility IN ('public', 'members', 'private')
            AND ( me.deleted_at IS NULL OR me.author_user_id = p_viewer_user_id )
            AND me.moderation_state = 'visible'
            AND me.thread_id = p_thread_id
        ORDER BY me.position ASC, me.post_id ASC
        LIMIT p_row_limit;
    ELSIF p_standing = 'global' AND p_viewer_user_id IS NOT NULL
          AND p_after_post_id IS NOT NULL THEN
        -- posts:global:own:after
        RETURN QUERY
        SELECT me.post_id, me.thread_id, me.author_user_id,
            me.current_body_id, me.position, me.visibility, me.moderation_state, me.created_at,
            me.deleted_at, current_body.body_rendered_safe,
            current_body.body_source, author.username, author.display_name
        FROM public.posts me
        LEFT JOIN public.post_bodies current_body
            ON current_body.body_id = me.current_body_id
        JOIN public.users author ON author.id = me.author_user_id
        WHERE ( me.visibility IN ('public', 'members', 'private')
                AND ( me.deleted_at IS NULL OR me.author_user_id = p_viewer_user_id )
                AND ( ( me.position > p_after_position
                    OR ( me.position = p_after_position
                        AND me.post_id > p_after_post_id ) )
                AND me.position >= p_after_position ) )
            AND me.moderation_state = 'visible'
            AND me.thread_id = p_thread_id
        ORDER BY me.position ASC, me.post_id ASC
        LIMIT p_row_limit;
    ELSIF p_standing = 'member' AND p_viewer_user_id IS NULL
          AND p_after_post_id IS NULL THEN
        -- posts:member:any:first
        RETURN QUERY
        SELECT me.post_id, me.thread_id, me.author_user_id,
            me.current_body_id, me.position, me.visibility, me.moderation_state, me.created_at,
            me.deleted_at, current_body.body_rendered_safe,
            current_body.body_source, author.username, author.display_name
        FROM public.posts me
        LEFT JOIN public.post_bodies current_body
            ON current_body.body_id = me.current_body_id
        JOIN public.users author ON author.id = me.author_user_id
        WHERE me.visibility IN ('public', 'members')
            AND me.deleted_at IS NULL
            AND me.moderation_state = 'visible'
            AND me.thread_id = p_thread_id
        ORDER BY me.position ASC, me.post_id ASC
        LIMIT p_row_limit;
    ELSIF p_standing = 'member' AND p_viewer_user_id IS NULL
          AND p_after_post_id IS NOT NULL THEN
        -- posts:member:any:after
        RETURN QUERY
        SELECT me.post_id, me.thread_id, me.author_user_id,
            me.current_body_id, me.position, me.visibility, me.moderation_state, me.created_at,
            me.deleted_at, current_body.body_rendered_safe,
            current_body.body_source, author.username, author.display_name
        FROM public.posts me
        LEFT JOIN public.post_bodies current_body
            ON current_body.body_id = me.current_body_id
        JOIN public.users author ON author.id = me.author_user_id
        WHERE ( me.visibility IN ('public', 'members')
                AND ( ( me.position > p_after_position
                    OR ( me.position = p_after_position
                        AND me.post_id > p_after_post_id ) )
                AND me.position >= p_after_position ) )
            AND me.deleted_at IS NULL
            AND me.moderation_state = 'visible'
            AND me.thread_id = p_thread_id
        ORDER BY me.position ASC, me.post_id ASC
        LIMIT p_row_limit;
    ELSIF p_standing = 'member' AND p_viewer_user_id IS NOT NULL
          AND p_after_post_id IS NULL THEN
        -- posts:member:own:first
        RETURN QUERY
        SELECT me.post_id, me.thread_id, me.author_user_id,
            me.current_body_id, me.position, me.visibility, me.moderation_state, me.created_at,
            me.deleted_at, current_body.body_rendered_safe,
            current_body.body_source, author.username, author.display_name
        FROM public.posts me
        LEFT JOIN public.post_bodies current_body
            ON current_body.body_id = me.current_body_id
        JOIN public.users author ON author.id = me.author_user_id
        WHERE ( me.visibility IN ('public', 'members')
                OR ( me.author_user_id = p_viewer_user_id
                    AND me.visibility = 'private' ) )
            AND ( me.deleted_at IS NULL OR me.author_user_id = p_viewer_user_id )
            AND me.moderation_state = 'visible'
            AND me.thread_id = p_thread_id
        ORDER BY me.position ASC, me.post_id ASC
        LIMIT p_row_limit;
    ELSIF p_standing = 'member' AND p_viewer_user_id IS NOT NULL
          AND p_after_post_id IS NOT NULL THEN
        -- posts:member:own:after
        RETURN QUERY
        SELECT me.post_id, me.thread_id, me.author_user_id,
            me.current_body_id, me.position, me.visibility, me.moderation_state, me.created_at,
            me.deleted_at, current_body.body_rendered_safe,
            current_body.body_source, author.username, author.display_name
        FROM public.posts me
        LEFT JOIN public.post_bodies current_body
            ON current_body.body_id = me.current_body_id
        JOIN public.users author ON author.id = me.author_user_id
        WHERE ( ( me.visibility IN ('public', 'members')
                OR ( me.author_user_id = p_viewer_user_id
                    AND me.visibility = 'private' ) )
                AND ( me.deleted_at IS NULL OR me.author_user_id = p_viewer_user_id )
                AND ( ( me.position > p_after_position
                    OR ( me.position = p_after_position
                        AND me.post_id > p_after_post_id ) )
                AND me.position >= p_after_position ) )
            AND me.moderation_state = 'visible'
            AND me.thread_id = p_thread_id
        ORDER BY me.position ASC, me.post_id ASC
        LIMIT p_row_limit;
    ELSIF p_standing = 'anonymous' AND p_viewer_user_id IS NULL
          AND p_after_post_id IS NULL THEN
        -- posts:anonymous:any:first
        RETURN QUERY
        SELECT me.post_id, me.thread_id, me.author_user_id,
            me.current_body_id, me.position, me.visibility, me.moderation_state, me.created_at,
            me.deleted_at, current_body.body_rendered_safe,
            current_body.body_source, author.username, author.display_name
        FROM public.posts me
        LEFT JOIN public.post_bodies current_body
            ON current_body.body_id = me.current_body_id
        JOIN public.users author ON author.id = me.author_user_id
        WHERE me.visibility IN ('public')
            AND me.deleted_at IS NULL
            AND me.moderation_state = 'visible'
            AND me.thread_id = p_thread_id
        ORDER BY me.position ASC, me.post_id ASC
        LIMIT p_row_limit;
    ELSIF p_standing = 'anonymous' AND p_viewer_user_id IS NULL
          AND p_after_post_id IS NOT NULL THEN
        -- posts:anonymous:any:after
        RETURN QUERY
        SELECT me.post_id, me.thread_id, me.author_user_id,
            me.current_body_id, me.position, me.visibility, me.moderation_state, me.created_at,
            me.deleted_at, current_body.body_rendered_safe,
            current_body.body_source, author.username, author.display_name
        FROM public.posts me
        LEFT JOIN public.post_bodies current_body
            ON current_body.body_id = me.current_body_id
        JOIN public.users author ON author.id = me.author_user_id
        WHERE ( me.visibility IN ('public')
                AND ( ( me.position > p_after_position
                    OR ( me.position = p_after_position
                        AND me.post_id > p_after_post_id ) )
                AND me.position >= p_after_position ) )
            AND me.deleted_at IS NULL
            AND me.moderation_state = 'visible'
            AND me.thread_id = p_thread_id
        ORDER BY me.position ASC, me.post_id ASC
        LIMIT p_row_limit;
    ELSIF p_standing = 'anonymous' AND p_viewer_user_id IS NOT NULL
          AND p_after_post_id IS NULL THEN
        -- posts:anonymous:own:first
        RETURN QUERY
        SELECT me.post_id, me.thread_id, me.author_user_id,
            me.current_body_id, me.position, me.visibility, me.moderation_state, me.created_at,
            me.deleted_at, current_body.body_rendered_safe,
            current_body.body_source, author.username, author.display_name
        FROM public.posts me
        LEFT JOIN public.post_bodies current_body
            ON current_body.body_id = me.current_body_id
        JOIN public.users author ON author.id = me.author_user_id
        WHERE me.visibility IN ('public')
            AND ( me.deleted_at IS NULL OR me.author_user_id = p_viewer_user_id )
            AND me.moderation_state = 'visible'
            AND me.thread_id = p_thread_id
        ORDER BY me.position ASC, me.post_id ASC
        LIMIT p_row_limit;
    ELSIF p_standing = 'anonymous' AND p_viewer_user_id IS NOT NULL
          AND p_after_post_id IS NOT NULL THEN
        -- posts:anonymous:own:after
        RETURN QUERY
        SELECT me.post_id, me.thread_id, me.author_user_id,
            me.current_body_id, me.position, me.visibility, me.moderation_state, me.created_at,
            me.deleted_at, current_body.body_rendered_safe,
            current_body.body_source, author.username, author.display_name
        FROM public.posts me
        LEFT JOIN public.post_bodies current_body
            ON current_body.body_id = me.current_body_id
        JOIN public.users author ON author.id = me.author_user_id
        WHERE ( me.visibility IN ('public')
                AND ( me.deleted_at IS NULL OR me.author_user_id = p_viewer_user_id )
                AND ( ( me.position > p_after_position
                    OR ( me.position = p_after_position
                        AND me.post_id > p_after_post_id ) )
                AND me.position >= p_after_position ) )
            AND me.moderation_state = 'visible'
            AND me.thread_id = p_thread_id
        ORDER BY me.position ASC, me.post_id ASC
        LIMIT p_row_limit;
    ELSE
        RAISE EXCEPTION USING ERRCODE = 'invalid_parameter_value',
            MESSAGE = 'standing must be global, member or anonymous, and a'
                || ' cursor needs its position';
    END IF;
END
$$;
REVOKE EXECUTE ON FUNCTION api.forum_thread_page_posts_v1(p_thread_id uuid, p_standing text, p_viewer_user_id uuid, p_after_position bigint, p_after_post_id uuid, p_row_limit integer) FROM PUBLIC;

CREATE FUNCTION api.forum_thread_tags_v1(p_thread_ids uuid[])
RETURNS TABLE (thread_id uuid, slug text, name text, tag_position smallint)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT tt.thread_id, t.slug, t.name, tt.position
FROM public.thread_tags tt
JOIN public.tags t ON t.tag_id = tt.tag_id
WHERE tt.thread_id = ANY(p_thread_ids)
ORDER BY tt.thread_id, tt.position
$$;
REVOKE EXECUTE ON FUNCTION api.forum_thread_tags_v1(p_thread_ids uuid[]) FROM PUBLIC;

CREATE FUNCTION api.forum_thread_placement_v1(p_source_id uuid)
RETURNS TABLE (
    category_id uuid,
    category_visibility text,
    space_id uuid,
    space_visibility text,
    thread_author uuid,
    thread_visibility text,
    thread_deleted_at timestamptz,
    thread_state text,
    category_deleted_at timestamptz
)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT c.category_id, c.visibility, c.space_id, s.visibility,
    t.author_user_id, t.visibility, t.deleted_at, t.moderation_state, c.deleted_at
FROM public.threads t
JOIN public.categories c ON c.category_id = t.category_id
JOIN public.spaces s ON s.space_id = c.space_id
WHERE t.thread_id = p_source_id
$$;
REVOKE EXECUTE ON FUNCTION api.forum_thread_placement_v1(p_source_id uuid) FROM PUBLIC;

CREATE FUNCTION api.forum_thread_redirect_v1(p_actor uuid, p_thread_id uuid)
RETURNS TABLE (target_id uuid)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
WITH RECURSIVE chain(id,depth) AS (
    SELECT p_thread_id,0 UNION ALL
    SELECT x.target_id,c.depth+1 FROM chain c JOIN public.thread_transfers x ON x.source_id = c.id
    WHERE x.operation = 'merge' AND x.undone_at IS NULL AND c.depth < 16
)
SELECT c.id FROM chain c WHERE c.depth > 0 AND api.core_product_read_thread_v1(p_actor,c.id)
ORDER BY c.depth DESC LIMIT 1
$$;
REVOKE EXECUTE ON FUNCTION api.forum_thread_redirect_v1(p_actor uuid, p_thread_id uuid) FROM PUBLIC;

CREATE FUNCTION api.forum_protocol_signature_v1(p_body_id uuid)
RETURNS TABLE (envelope json)
LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT s.envelope::json FROM public.post_signatures s WHERE s.body_id = p_body_id;
$$;
REVOKE EXECUTE ON FUNCTION api.forum_protocol_signature_v1(p_body_id uuid) FROM PUBLIC;

CREATE FUNCTION api.forum_protocol_member_v1(p_user_id uuid, p_email text)
RETURNS TABLE (id uuid, email_normalized text, trust_level integer, email_verified_at timestamptz)
LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT u.id,u.email_normalized,u.trust_level,u.email_verified_at FROM public.users u WHERE (u.id=p_user_id OR u.email_normalized=p_email) AND u.status='active' AND u.deleted_at IS NULL;
$$;
REVOKE EXECUTE ON FUNCTION api.forum_protocol_member_v1(p_user_id uuid, p_email text) FROM PUBLIC;

CREATE FUNCTION api.forum_protocol_attest_body_v1(p_body_id uuid, p_post_id uuid, p_source text, p_envelope jsonb)
RETURNS TABLE (saved boolean)
LANGUAGE sql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
WITH inserted AS (
INSERT INTO public.post_signatures(body_id,envelope)
SELECT b.body_id,p_envelope FROM public.post_bodies b
WHERE b.body_id=p_body_id AND b.post_id=p_post_id AND b.body_source=p_source
ON CONFLICT (body_id) DO NOTHING RETURNING body_id)
SELECT EXISTS (SELECT 1 FROM inserted);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_protocol_attest_body_v1(p_body_id uuid, p_post_id uuid, p_source text, p_envelope jsonb) FROM PUBLIC;

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
REVOKE EXECUTE ON FUNCTION api.forum_sitemap_page_v1(p_page integer) FROM PUBLIC;

CREATE FUNCTION api.forum_protocol_signatures_v1(p_body_ids uuid[])
RETURNS TABLE (body_id uuid, envelope json)
LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT s.body_id, s.envelope::json FROM public.post_signatures s WHERE s.body_id = ANY(p_body_ids);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_protocol_signatures_v1(p_body_ids uuid[]) FROM PUBLIC;

CREATE FUNCTION api.forum_find_listed_post_v3(
    p_post_id uuid,
    p_thread_id uuid,
    p_member boolean,
    p_global_read boolean,
    p_scope_user_id uuid,
    p_viewer_user_id uuid
)
RETURNS TABLE (
    post_id uuid,
    thread_id uuid,
    author_user_id uuid,
    current_body_id uuid,
    "position" bigint,
    visibility text,
    moderation_state text,
    created_at timestamptz,
    deleted_at timestamptz,
    body text,
    body_source text,
    author_username text,
    author_display_name text
)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT me.post_id, me.thread_id, me.author_user_id, me.current_body_id, me.position, me.visibility, me.moderation_state, me.created_at, me.deleted_at,
    current_body.body_rendered_safe, current_body.body_source,
    author.username, author.display_name
FROM public.posts me
LEFT JOIN public.post_bodies current_body ON current_body.body_id = me.current_body_id
JOIN public.users author ON author.id = me.author_user_id
WHERE me.post_id = p_post_id AND me.thread_id = p_thread_id
    AND me.moderation_state = 'visible'
    AND (me.visibility IN ('public', 'members', 'private')
        AND (p_global_read OR me.visibility = 'public'
            OR (p_member AND me.visibility = 'members')
            OR (me.visibility = 'private' AND p_member
                AND me.author_user_id = p_scope_user_id)))
    AND (me.deleted_at IS NULL OR me.author_user_id = p_viewer_user_id)
LIMIT 1
$$;
REVOKE EXECUTE ON FUNCTION api.forum_find_listed_post_v3(p_post_id uuid, p_thread_id uuid, p_member boolean, p_global_read boolean, p_scope_user_id uuid, p_viewer_user_id uuid) FROM PUBLIC;

CREATE FUNCTION api.forum_list_category_threads_v3(
    p_category_id uuid,
    p_member boolean,
    p_global_read boolean,
    p_scope_user_id uuid,
    p_viewer_user_id uuid,
    p_after_pinned boolean,
    p_after_activity timestamptz,
    p_after_thread_id uuid,
    p_row_limit integer
)
RETURNS TABLE (
    thread_id uuid,
    category_id uuid,
    author_user_id uuid,
    title text,
    slug text,
    pinned boolean,
    visibility text,
    moderation_state text,
    locked_at timestamptz,
    last_activity_at timestamptz,
    created_at timestamptz,
    deleted_at timestamptz,
    author_username text,
    author_display_name text,
    reply_count bigint
)
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
#variable_conflict use_column
BEGIN
    IF p_viewer_user_id IS NULL AND p_after_thread_id IS NULL THEN
        RETURN QUERY
        SELECT me.thread_id, me.category_id, me.author_user_id, me.title, me.slug, me.pinned, me.visibility, me.moderation_state, me.locked_at, me.last_activity_at, me.created_at, me.deleted_at, author.username,
            author.display_name, COALESCE((SELECT counter.reply_count
                FROM public.thread_counters counter
                WHERE counter.thread_id = me.thread_id), 0)
        FROM public.threads me
        JOIN public.users author ON author.id = me.author_user_id
        WHERE me.category_id = p_category_id
            AND me.moderation_state IN ('visible', 'locked')
            AND (me.visibility IN ('public', 'members', 'private')
        AND (p_global_read OR me.visibility = 'public'
            OR (p_member AND me.visibility = 'members')
            OR (me.visibility = 'private' AND p_member
                AND me.author_user_id = p_scope_user_id)))
            AND me.deleted_at IS NULL
        ORDER BY me.pinned DESC, me.last_activity_at DESC, me.thread_id DESC LIMIT p_row_limit;
    ELSIF p_viewer_user_id IS NULL AND p_after_thread_id IS NOT NULL AND p_after_pinned THEN
        RETURN QUERY
        SELECT me.thread_id, me.category_id, me.author_user_id, me.title, me.slug, me.pinned, me.visibility, me.moderation_state, me.locked_at, me.last_activity_at, me.created_at, me.deleted_at, author.username,
            author.display_name, COALESCE((SELECT counter.reply_count
                FROM public.thread_counters counter
                WHERE counter.thread_id = me.thread_id), 0)
        FROM public.threads me
        JOIN public.users author ON author.id = me.author_user_id
        WHERE me.category_id = p_category_id
            AND me.moderation_state IN ('visible', 'locked')
            AND (me.visibility IN ('public', 'members', 'private')
        AND (p_global_read OR me.visibility = 'public'
            OR (p_member AND me.visibility = 'members')
            OR (me.visibility = 'private' AND p_member
                AND me.author_user_id = p_scope_user_id)))
            AND me.deleted_at IS NULL
            AND me.pinned <= p_after_pinned
            AND (me.pinned < p_after_pinned
                OR (me.pinned = p_after_pinned
                    AND me.last_activity_at < p_after_activity)
                OR (me.pinned = p_after_pinned
                    AND me.last_activity_at = p_after_activity
                    AND me.thread_id < p_after_thread_id))
        ORDER BY me.pinned DESC, me.last_activity_at DESC, me.thread_id DESC LIMIT p_row_limit;
    ELSIF p_viewer_user_id IS NULL AND p_after_thread_id IS NOT NULL AND NOT p_after_pinned THEN
        RETURN QUERY
        SELECT me.thread_id, me.category_id, me.author_user_id, me.title, me.slug, me.pinned, me.visibility, me.moderation_state, me.locked_at, me.last_activity_at, me.created_at, me.deleted_at, author.username,
            author.display_name, COALESCE((SELECT counter.reply_count
                FROM public.thread_counters counter
                WHERE counter.thread_id = me.thread_id), 0)
        FROM public.threads me
        JOIN public.users author ON author.id = me.author_user_id
        WHERE me.category_id = p_category_id
            AND me.moderation_state IN ('visible', 'locked')
            AND (me.visibility IN ('public', 'members', 'private')
        AND (p_global_read OR me.visibility = 'public'
            OR (p_member AND me.visibility = 'members')
            OR (me.visibility = 'private' AND p_member
                AND me.author_user_id = p_scope_user_id)))
            AND me.deleted_at IS NULL
            AND me.pinned <= p_after_pinned
            AND me.last_activity_at <= p_after_activity
            AND (me.pinned < p_after_pinned
                OR (me.pinned = p_after_pinned
                    AND me.last_activity_at < p_after_activity)
                OR (me.pinned = p_after_pinned
                    AND me.last_activity_at = p_after_activity
                    AND me.thread_id < p_after_thread_id))
        ORDER BY me.pinned DESC, me.last_activity_at DESC, me.thread_id DESC LIMIT p_row_limit;
    ELSIF p_viewer_user_id IS NOT NULL AND p_after_thread_id IS NULL THEN
        RETURN QUERY
        SELECT me.thread_id, me.category_id, me.author_user_id, me.title, me.slug, me.pinned, me.visibility, me.moderation_state, me.locked_at, me.last_activity_at, me.created_at, me.deleted_at, author.username,
            author.display_name, COALESCE((SELECT counter.reply_count
                FROM public.thread_counters counter
                WHERE counter.thread_id = me.thread_id), 0)
        FROM public.threads me
        JOIN public.users author ON author.id = me.author_user_id
        WHERE me.thread_id IN (
            (SELECT me.thread_id FROM public.threads me
             WHERE me.category_id = p_category_id
            AND me.moderation_state IN ('visible', 'locked')
            AND (me.visibility IN ('public', 'members', 'private')
        AND (p_global_read OR me.visibility = 'public'
            OR (p_member AND me.visibility = 'members')
            OR (me.visibility = 'private' AND p_member
                AND me.author_user_id = p_scope_user_id)))
            AND me.deleted_at IS NULL
             ORDER BY me.pinned DESC, me.last_activity_at DESC, me.thread_id DESC LIMIT p_row_limit)
UNION ALL
            (SELECT me.thread_id FROM public.threads me
             WHERE me.category_id = p_category_id
            AND me.moderation_state IN ('visible', 'locked')
            AND (me.visibility IN ('public', 'members', 'private')
        AND (p_global_read OR me.visibility = 'public'
            OR (p_member AND me.visibility = 'members')
            OR (me.visibility = 'private' AND p_member
                AND me.author_user_id = p_scope_user_id)))
            AND me.deleted_at IS NOT NULL AND me.author_user_id = p_viewer_user_id
             ORDER BY me.pinned DESC, me.last_activity_at DESC, me.thread_id DESC LIMIT p_row_limit)
        )
        ORDER BY me.pinned DESC, me.last_activity_at DESC, me.thread_id DESC LIMIT p_row_limit;
    ELSIF p_viewer_user_id IS NOT NULL AND p_after_thread_id IS NOT NULL AND p_after_pinned THEN
        RETURN QUERY
        SELECT me.thread_id, me.category_id, me.author_user_id, me.title, me.slug, me.pinned, me.visibility, me.moderation_state, me.locked_at, me.last_activity_at, me.created_at, me.deleted_at, author.username,
            author.display_name, COALESCE((SELECT counter.reply_count
                FROM public.thread_counters counter
                WHERE counter.thread_id = me.thread_id), 0)
        FROM public.threads me
        JOIN public.users author ON author.id = me.author_user_id
        WHERE me.thread_id IN (
            (SELECT me.thread_id FROM public.threads me
             WHERE me.category_id = p_category_id
            AND me.moderation_state IN ('visible', 'locked')
            AND (me.visibility IN ('public', 'members', 'private')
        AND (p_global_read OR me.visibility = 'public'
            OR (p_member AND me.visibility = 'members')
            OR (me.visibility = 'private' AND p_member
                AND me.author_user_id = p_scope_user_id)))
            AND me.deleted_at IS NULL
            AND me.pinned <= p_after_pinned
            AND (me.pinned < p_after_pinned
                OR (me.pinned = p_after_pinned
                    AND me.last_activity_at < p_after_activity)
                OR (me.pinned = p_after_pinned
                    AND me.last_activity_at = p_after_activity
                    AND me.thread_id < p_after_thread_id))
             ORDER BY me.pinned DESC, me.last_activity_at DESC, me.thread_id DESC LIMIT p_row_limit)
UNION ALL
            (SELECT me.thread_id FROM public.threads me
             WHERE me.category_id = p_category_id
            AND me.moderation_state IN ('visible', 'locked')
            AND (me.visibility IN ('public', 'members', 'private')
        AND (p_global_read OR me.visibility = 'public'
            OR (p_member AND me.visibility = 'members')
            OR (me.visibility = 'private' AND p_member
                AND me.author_user_id = p_scope_user_id)))
            AND me.deleted_at IS NOT NULL AND me.author_user_id = p_viewer_user_id
            AND me.pinned <= p_after_pinned
            AND (me.pinned < p_after_pinned
                OR (me.pinned = p_after_pinned
                    AND me.last_activity_at < p_after_activity)
                OR (me.pinned = p_after_pinned
                    AND me.last_activity_at = p_after_activity
                    AND me.thread_id < p_after_thread_id))
             ORDER BY me.pinned DESC, me.last_activity_at DESC, me.thread_id DESC LIMIT p_row_limit)
        )
        ORDER BY me.pinned DESC, me.last_activity_at DESC, me.thread_id DESC LIMIT p_row_limit;
    ELSIF p_viewer_user_id IS NOT NULL AND p_after_thread_id IS NOT NULL AND NOT p_after_pinned THEN
        RETURN QUERY
        SELECT me.thread_id, me.category_id, me.author_user_id, me.title, me.slug, me.pinned, me.visibility, me.moderation_state, me.locked_at, me.last_activity_at, me.created_at, me.deleted_at, author.username,
            author.display_name, COALESCE((SELECT counter.reply_count
                FROM public.thread_counters counter
                WHERE counter.thread_id = me.thread_id), 0)
        FROM public.threads me
        JOIN public.users author ON author.id = me.author_user_id
        WHERE me.thread_id IN (
            (SELECT me.thread_id FROM public.threads me
             WHERE me.category_id = p_category_id
            AND me.moderation_state IN ('visible', 'locked')
            AND (me.visibility IN ('public', 'members', 'private')
        AND (p_global_read OR me.visibility = 'public'
            OR (p_member AND me.visibility = 'members')
            OR (me.visibility = 'private' AND p_member
                AND me.author_user_id = p_scope_user_id)))
            AND me.deleted_at IS NULL
            AND me.pinned <= p_after_pinned
            AND me.last_activity_at <= p_after_activity
            AND (me.pinned < p_after_pinned
                OR (me.pinned = p_after_pinned
                    AND me.last_activity_at < p_after_activity)
                OR (me.pinned = p_after_pinned
                    AND me.last_activity_at = p_after_activity
                    AND me.thread_id < p_after_thread_id))
             ORDER BY me.pinned DESC, me.last_activity_at DESC, me.thread_id DESC LIMIT p_row_limit)
UNION ALL
            (SELECT me.thread_id FROM public.threads me
             WHERE me.category_id = p_category_id
            AND me.moderation_state IN ('visible', 'locked')
            AND (me.visibility IN ('public', 'members', 'private')
        AND (p_global_read OR me.visibility = 'public'
            OR (p_member AND me.visibility = 'members')
            OR (me.visibility = 'private' AND p_member
                AND me.author_user_id = p_scope_user_id)))
            AND me.deleted_at IS NOT NULL AND me.author_user_id = p_viewer_user_id
            AND me.pinned <= p_after_pinned
            AND me.last_activity_at <= p_after_activity
            AND (me.pinned < p_after_pinned
                OR (me.pinned = p_after_pinned
                    AND me.last_activity_at < p_after_activity)
                OR (me.pinned = p_after_pinned
                    AND me.last_activity_at = p_after_activity
                    AND me.thread_id < p_after_thread_id))
             ORDER BY me.pinned DESC, me.last_activity_at DESC, me.thread_id DESC LIMIT p_row_limit)
        )
        ORDER BY me.pinned DESC, me.last_activity_at DESC, me.thread_id DESC LIMIT p_row_limit;
    ELSE
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'incomplete category cursor';
    END IF;
END
$$;
REVOKE EXECUTE ON FUNCTION api.forum_list_category_threads_v3(p_category_id uuid, p_member boolean, p_global_read boolean, p_scope_user_id uuid, p_viewer_user_id uuid, p_after_pinned boolean, p_after_activity timestamp with time zone, p_after_thread_id uuid, p_row_limit integer) FROM PUBLIC;

CREATE FUNCTION api.forum_set_thread_tags_v3(
    p_thread_id uuid,
    p_slugs text[],
    p_names text[]
)
RETURNS TABLE (slug text, name text, tag_position smallint)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    -- The thread's row first: two writes of one thread's tags take turns,
    -- so the second one's DELETE sees the rows the first wrote and the
    -- thread keeps at most five. A reply takes the same lock.
    PERFORM 1 FROM public.threads t WHERE t.thread_id = p_thread_id
        FOR NO KEY UPDATE;
    IF NOT FOUND THEN
        RETURN;
    END IF;
    INSERT INTO public.tags (slug, name)
    SELECT given.slug, given.name
    FROM unnest(p_slugs, p_names) AS given(slug, name)
    ON CONFLICT ON CONSTRAINT tags_slug_key DO NOTHING;
    DELETE FROM public.thread_tags tt
    WHERE tt.thread_id = p_thread_id
        AND tt.tag_id NOT IN (
            SELECT t.tag_id FROM public.tags t WHERE t.slug = ANY(p_slugs));
    INSERT INTO public.thread_tags (thread_id, tag_id, position)
    SELECT p_thread_id, t.tag_id, given.ordinality
    FROM unnest(p_slugs) WITH ORDINALITY AS given(slug, ordinality)
    JOIN public.tags t ON t.slug = given.slug
    ON CONFLICT ON CONSTRAINT thread_tags_pkey
        DO UPDATE SET position = EXCLUDED.position;
    RETURN QUERY
    SELECT t.slug, t.name, tt.position
    FROM public.thread_tags tt
    JOIN public.tags t ON t.tag_id = tt.tag_id
    WHERE tt.thread_id = p_thread_id
    ORDER BY tt.position;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.forum_set_thread_tags_v3(p_thread_id uuid, p_slugs text[], p_names text[]) FROM PUBLIC;

CREATE FUNCTION api.forum_draft_save_v3(
    p_owner_user_id uuid,
    p_draft_id uuid,
    p_draft_revision bigint,
    p_kind text,
    p_category_id uuid,
    p_thread_id uuid,
    p_title text,
    p_body_source text,
    p_visibility text,
    p_command_id text,
    p_now timestamptz
)
RETURNS TABLE (status text, draft json, error text)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE held public.forum_drafts; nonce text := p_command_id; amount bigint;
BEGIN
    IF p_draft_id IS NULL OR p_draft_revision IS NULL OR p_draft_revision < 0
        OR p_kind IS NULL OR p_kind NOT IN ('thread','reply')
        OR p_title IS NULL OR length(p_title) > 300
        OR p_body_source IS NULL OR length(p_body_source) > 50000
        OR p_command_id IS NULL OR length(p_command_id) NOT BETWEEN 1 AND 200
        OR (p_visibility IS NOT NULL AND p_visibility NOT IN ('public','members','private'))
        OR (p_kind = 'thread' AND p_thread_id IS NOT NULL)
        OR (p_kind = 'reply' AND (p_thread_id IS NULL OR p_category_id IS NOT NULL)) THEN
        RETURN QUERY SELECT 'invalid'::text,NULL::json,'invalid draft'::text; RETURN;
    END IF;
    -- One account lock serializes quota checks and prevents save after erasure;
    -- NO KEY UPDATE, so the member's own foreign-key checks (a reply, a
    -- session, a bookmark) do not wait for an autosave.
    PERFORM 1 FROM public.users u WHERE u.id = p_owner_user_id
        AND u.status = 'active' AND u.deleted_at IS NULL FOR NO KEY UPDATE;
    IF NOT FOUND THEN RETURN QUERY SELECT 'forbidden'::text,NULL::json,'account unavailable'::text; RETURN; END IF;
    DELETE FROM public.forum_drafts d WHERE d.owner_user_id = p_owner_user_id AND d.expires_at <= p_now;
    SELECT d.* INTO held FROM public.forum_drafts d WHERE d.draft_id = p_draft_id FOR UPDATE;
    IF FOUND AND held.owner_user_id <> p_owner_user_id THEN
        RETURN QUERY SELECT 'not_found'::text,NULL::json,'draft not found'::text; RETURN;
    END IF;
    IF held.draft_id IS NOT NULL THEN
        IF (held.save_base_revision = p_draft_revision AND held.save_command_id = p_command_id)
            AND held.kind = p_kind AND held.category_id IS NOT DISTINCT FROM p_category_id
            AND held.thread_id IS NOT DISTINCT FROM p_thread_id AND held.title = p_title
            AND held.body_source = p_body_source AND held.visibility IS NOT DISTINCT FROM p_visibility THEN
            RETURN QUERY SELECT 'ok'::text,to_json(held),NULL::text; RETURN;
        END IF;
        IF held.draft_revision = p_draft_revision AND held.command_id = p_command_id
            AND held.kind = p_kind AND held.category_id IS NOT DISTINCT FROM p_category_id
            AND held.thread_id IS NOT DISTINCT FROM p_thread_id AND held.title = p_title
            AND held.body_source = p_body_source AND held.visibility IS NOT DISTINCT FROM p_visibility
            AND NOT EXISTS (SELECT 1 FROM public.command_log c WHERE c.idempotency_key=held.command_id) THEN
            UPDATE public.forum_drafts d SET updated_at=greatest(p_now,d.updated_at),
                expires_at=greatest(p_now,d.updated_at)+interval '30 days'
            WHERE d.draft_id=p_draft_id RETURNING d.* INTO held;
            RETURN QUERY SELECT 'ok'::text,to_json(held),NULL::text; RETURN;
        END IF;
        IF held.draft_revision <> p_draft_revision THEN
            RETURN QUERY SELECT 'conflict'::text,NULL::json,'draft changed'::text; RETURN;
        END IF;
        IF held.kind <> p_kind OR held.thread_id IS DISTINCT FROM p_thread_id THEN
            RETURN QUERY SELECT 'invalid'::text,NULL::json,'draft context changed'::text; RETURN;
        END IF;
        -- The server's publish nonce survives refreshes and ordinary saves.
        nonce := held.command_id;
    ELSIF EXISTS (SELECT 1 FROM public.command_log c WHERE c.idempotency_key=p_command_id)
        OR p_draft_revision <> 0 THEN
        RETURN QUERY SELECT 'not_found'::text,NULL::json,'draft not found'::text; RETURN;
    ELSE
        SELECT count(*) INTO amount FROM public.forum_drafts d WHERE d.owner_user_id = p_owner_user_id;
        IF amount >= 100 THEN RETURN QUERY SELECT 'limit'::text,NULL::json,'draft limit reached'::text; RETURN; END IF;
    END IF;
    IF NOT api.core_forum_draft_target_v1(p_owner_user_id,p_kind,p_category_id,p_thread_id) THEN
        RETURN QUERY SELECT 'not_found'::text,NULL::json,'draft target unavailable'::text; RETURN;
    END IF;
    IF EXISTS (SELECT 1 FROM public.command_log c WHERE c.idempotency_key = nonce) THEN
        nonce := api.core_uuid_v7_v1()::text;
    END IF;
    IF held.draft_id IS NULL THEN
        INSERT INTO public.forum_drafts(draft_id,owner_user_id,kind,category_id,thread_id,
            title,body_source,visibility,command_id,draft_revision,save_base_revision,
            save_command_id,created_at,updated_at,expires_at)
        VALUES (p_draft_id,p_owner_user_id,p_kind,p_category_id,p_thread_id,p_title,
            p_body_source,p_visibility,nonce,1,p_draft_revision,p_command_id,p_now,p_now,
            p_now + interval '30 days') RETURNING * INTO held;
    ELSE
        UPDATE public.forum_drafts d SET category_id=p_category_id,title=p_title,
            body_source=p_body_source,visibility=p_visibility,command_id=nonce,
            draft_revision=d.draft_revision+1,save_base_revision=p_draft_revision,
            save_command_id=p_command_id,updated_at=greatest(p_now,d.updated_at),
            expires_at=greatest(p_now,d.updated_at)+interval '30 days'
        WHERE d.draft_id=p_draft_id RETURNING d.* INTO held;
    END IF;
    RETURN QUERY SELECT 'ok'::text,to_json(held),NULL::text;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.forum_draft_save_v3(p_owner_user_id uuid, p_draft_id uuid, p_draft_revision bigint, p_kind text, p_category_id uuid, p_thread_id uuid, p_title text, p_body_source text, p_visibility text, p_command_id text, p_now timestamp with time zone) FROM PUBLIC;

CREATE FUNCTION api.forum_link_reply_v3(
    p_post_id uuid,
    p_reply_to_post_id uuid
)
RETURNS TABLE (linked boolean)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE
    added integer := 0;
BEGIN
    INSERT INTO public.post_replies (post_id, reply_to_post_id)
    SELECT reply.post_id, target.post_id
    FROM public.posts reply
    JOIN public.posts target ON target.thread_id = reply.thread_id
    JOIN public.threads thread ON thread.thread_id = reply.thread_id
    JOIN public.categories category ON category.category_id = thread.category_id
    JOIN public.spaces space ON space.space_id = category.space_id
    WHERE reply.post_id = p_post_id
        AND target.post_id = p_reply_to_post_id
        AND target.post_id <> reply.post_id
        AND target.deleted_at IS NULL
        AND target.moderation_state = 'visible'
        AND (target.visibility = 'public'
            OR (target.visibility = 'members'
                AND 'public' <> ANY (ARRAY[reply.visibility, thread.visibility,
                    category.visibility, space.visibility]))
            OR (target.visibility = 'private'
                AND reply.visibility = 'private'
                AND reply.author_user_id = target.author_user_id))
    ON CONFLICT ON CONSTRAINT post_replies_pkey DO NOTHING;
    GET DIAGNOSTICS added = ROW_COUNT;
    RETURN QUERY SELECT added = 1
        OR EXISTS (SELECT 1 FROM public.post_replies r
            WHERE r.post_id = p_post_id
                AND r.reply_to_post_id = p_reply_to_post_id);
END;
$$;
REVOKE EXECUTE ON FUNCTION api.forum_link_reply_v3(p_post_id uuid, p_reply_to_post_id uuid) FROM PUBLIC;

CREATE FUNCTION api.forum_create_reply_v7(
    p_idempotency_key text,
    p_command_type text,
    p_actor_id text,
    p_request_hash text,
    p_command_id text,
    p_command_correlation_id text,
    p_command_at text,
    p_answer jsonb,
    p_store_refusals jsonb,
    p_post_id text,
    p_thread_id text,
    p_author_user_id text,
    p_current_body_id text,
    p_current_revision_id text,
    p_position bigint,
    p_visibility text,
    p_moderation_state text,
    p_version bigint,
    p_visibility_version bigint,
    p_permission_version bigint,
    p_hidden_at text,
    p_locked_at text,
    p_deleted_at text,
    p_deleted_by text,
    p_body_id text,
    p_body_post_id text,
    p_body_format text,
    p_body_source text,
    p_body_rendered_safe text,
    p_source_hash text,
    p_revision_id text,
    p_revision_post_id text,
    p_revision_body_id text,
    p_editor_user_id text,
    p_revision_number integer,
    p_edit_reason text,
    p_correlation_id text,
    p_event_id text,
    p_outbox_id text,
    p_audit_id text,
    p_recorded_at text,
    p_draft_id uuid,
    p_draft_revision bigint,
    p_post_signature jsonb
)
RETURNS TABLE (outcome text,
    response json,
    skipped boolean,
    post_id text,
    thread_id text,
    author_user_id text,
    current_body_id text,
    current_revision_id text,
    "position" text,
    visibility text,
    moderation_state text,
    version text,
    visibility_version text,
    permission_version text,
    hidden_at text,
    locked_at text,
    deleted_at text,
    deleted_by text)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE result record;
BEGIN
    SELECT * INTO result FROM api.forum_create_reply_v3(p_idempotency_key, p_command_type, p_actor_id, p_request_hash, p_command_id, p_command_correlation_id, p_command_at, p_answer, p_store_refusals, p_post_id, p_thread_id, p_author_user_id, p_current_body_id, p_current_revision_id, p_position, p_visibility, p_moderation_state, p_version, p_visibility_version, p_permission_version, p_hidden_at, p_locked_at, p_deleted_at, p_deleted_by, p_body_id, p_body_post_id, p_body_format, p_body_source, p_body_rendered_safe, p_source_hash, p_revision_id, p_revision_post_id, p_revision_body_id, p_editor_user_id, p_revision_number, p_edit_reason, p_correlation_id, p_event_id, p_outbox_id, p_audit_id, p_recorded_at, p_draft_id, p_draft_revision);
    IF result.post_id IS NOT NULL AND NOT coalesce(result.skipped, false) AND p_post_signature IS NOT NULL THEN
        PERFORM api.core_forum_attach_signature_v1(
            jsonb_build_object('post', jsonb_build_object('post_id', result.post_id)),
            jsonb_build_object('body', jsonb_build_object('post_signature', p_post_signature,
                'post_id', p_body_post_id, 'body_source', p_body_source)));
    END IF;
    RETURN QUERY SELECT result.outcome, result.response, result.skipped, result.post_id, result.thread_id, result.author_user_id, result.current_body_id, result.current_revision_id, result."position", result.visibility, result.moderation_state, result.version, result.visibility_version, result.permission_version, result.hidden_at, result.locked_at, result.deleted_at, result.deleted_by;
END
$$;
REVOKE EXECUTE ON FUNCTION api.forum_create_reply_v7(p_idempotency_key text, p_command_type text, p_actor_id text, p_request_hash text, p_command_id text, p_command_correlation_id text, p_command_at text, p_answer jsonb, p_store_refusals jsonb, p_post_id text, p_thread_id text, p_author_user_id text, p_current_body_id text, p_current_revision_id text, p_position bigint, p_visibility text, p_moderation_state text, p_version bigint, p_visibility_version bigint, p_permission_version bigint, p_hidden_at text, p_locked_at text, p_deleted_at text, p_deleted_by text, p_body_id text, p_body_post_id text, p_body_format text, p_body_source text, p_body_rendered_safe text, p_source_hash text, p_revision_id text, p_revision_post_id text, p_revision_body_id text, p_editor_user_id text, p_revision_number integer, p_edit_reason text, p_correlation_id text, p_event_id text, p_outbox_id text, p_audit_id text, p_recorded_at text, p_draft_id uuid, p_draft_revision bigint, p_post_signature jsonb) FROM PUBLIC;

CREATE FUNCTION api.forum_protocol_unsigned_bodies_v3(p_after uuid)
RETURNS TABLE (body_id uuid, post_id uuid, body_format text, body_source text)
LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT b.body_id,b.post_id,b.body_format,b.body_source FROM public.post_bodies b
WHERE b.body_id > coalesce(p_after, '00000000-0000-0000-0000-000000000000'::uuid)
AND NOT EXISTS (SELECT 1 FROM public.post_signatures s WHERE s.body_id=b.body_id)
ORDER BY b.body_id LIMIT 100;
$$;
REVOKE EXECUTE ON FUNCTION api.forum_protocol_unsigned_bodies_v3(p_after uuid) FROM PUBLIC;

CREATE FUNCTION api.forum_store_write_v7(
    p_store_type text,
    p_command jsonb,
    p_record jsonb
)
RETURNS TABLE (stored json)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
#variable_conflict use_variable
DECLARE answer jsonb;
BEGIN
    CASE p_store_type
      WHEN 'post.created' THEN
        SELECT CASE WHEN reply.refusal IS NOT NULL THEN
            jsonb_build_object('ok',0,'error',CASE reply.refusal
                WHEN 'thread_not_found' THEN 'thread not found' ELSE 'thread is locked' END)
            ELSE jsonb_build_object('ok',1,'skipped',reply.skipped,
                'post',to_jsonb(reply) - 'refusal' - 'skipped') END
        INTO answer FROM api.core_forum_store_reply_v1(
            (p_command #>> '{post,post_id}'),
            (p_command #>> '{post,thread_id}'),
            (p_command #>> '{post,author_user_id}'),
            (p_command #>> '{post,current_body_id}'),
            (p_command #>> '{post,current_revision_id}'),
            (p_command #>> '{post,position}')::bigint,
            (p_command #>> '{post,visibility}'),
            (p_command #>> '{post,moderation_state}'),
            (p_command #>> '{post,version}')::bigint,
            (p_command #>> '{post,visibility_version}')::bigint,
            (p_command #>> '{post,permission_version}')::bigint,
            (p_command #>> '{post,hidden_at}'),
            (p_command #>> '{post,locked_at}'),
            (p_command #>> '{post,deleted_at}'),
            (p_command #>> '{post,deleted_by}'),
            (p_command #>> '{body,body_id}'),
            (p_command #>> '{body,post_id}'),
            (p_command #>> '{body,body_format}'),
            (p_command #>> '{body,body_source}'),
            (p_command #>> '{body,body_rendered_safe}'),
            (p_command #>> '{body,source_hash}'),
            (p_command #>> '{revision,revision_id}'),
            (p_command #>> '{revision,post_id}'),
            (p_command #>> '{revision,body_id}'),
            (p_command #>> '{revision,editor_user_id}'),
            (p_command #>> '{revision,revision_number}')::integer,
            (p_command #>> '{revision,edit_reason}'),
            p_command->>'idempotency_key',
            p_record->>'correlation_id',
            p_record->>'event_id',
            p_record->>'outbox_id',
            p_record->>'audit_id',
            p_record->>'recorded_at') reply;
      WHEN 'thread.created' THEN answer := api.core_forum_create_thread_v2(p_command,p_record);
      WHEN 'thread.updated','thread.moved','thread.deleted','thread.undeleted' THEN
        answer := api.core_forum_write_thread_v1(p_store_type,p_command,p_record);
      WHEN 'post.updated','post.deleted','post.undeleted' THEN
        answer := api.core_forum_write_post_v1(p_store_type,p_command,p_record);
      ELSE RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'unknown forum store type';
    END CASE;
    PERFORM api.core_forum_attach_signature_v1(answer, p_command);
    RETURN QUERY SELECT answer::json;
END $$;
REVOKE EXECUTE ON FUNCTION api.forum_store_write_v7(p_store_type text, p_command jsonb, p_record jsonb) FROM PUBLIC;

CREATE FUNCTION api.forum_write_command_v9(
    p_log jsonb,
    p_answer jsonb,
    p_store_type text,
    p_command jsonb,
    p_record jsonb,
    p_draft_id uuid,
    p_draft_revision bigint
)
RETURNS TABLE (outcome text, response json, stored json)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
#variable_conflict use_variable
DECLARE existing public.command_log; held record; reported text;
    command_id text := p_log->>'command_id';
    payload jsonb := jsonb_build_object('request_hash',p_log->>'request_hash');
    answer jsonb := p_answer; written jsonb; message text; status text; draft_error text;
BEGIN
    IF p_draft_id IS NOT NULL THEN
        PERFORM pg_advisory_xact_lock(hashtextextended('forum.draft.publish:' || (p_log->>'idempotency_key'),0));
    END IF;
    SELECT me.* INTO existing FROM public.command_log me
        WHERE me.idempotency_key = p_log->>'idempotency_key' LIMIT 1;
    IF FOUND THEN
        SELECT * INTO held FROM api.core_command_existing_v1(existing.payload,p_log->>'request_hash');
        RETURN QUERY SELECT held.outcome,held.response::json,NULL::json; RETURN;
    END IF;
    IF p_draft_id IS NOT NULL THEN
        draft_error := api.core_forum_draft_publish_v1((p_log->>'actor_id')::uuid,
            p_draft_id,p_draft_revision,
            CASE WHEN p_store_type='thread.created' THEN 'thread' ELSE 'invalid' END,
            (p_command #>> '{thread,category_id}')::uuid,NULL,
            p_log->>'idempotency_key',(p_log->>'command_at')::timestamptz,p_answer IS NULL);
        IF draft_error IS NOT NULL THEN
            RETURN QUERY SELECT 'recorded'::text,
                json_build_object('ok',0,'status','conflict','error',draft_error),NULL::json;
            RETURN;
        END IF;
    END IF;
    BEGIN
        INSERT INTO public.command_log(actor_id,command_id,command_type,correlation_id,
            created_at,handled_at,idempotency_key,payload,response_hash,status)
        VALUES ((p_log->>'actor_id')::uuid,command_id::uuid,p_log->>'command_type',
            (p_log->>'command_correlation_id')::uuid,(p_log->>'command_at')::timestamptz,
            NULL,p_log->>'idempotency_key',payload,NULL,'accepted');
    EXCEPTION WHEN unique_violation THEN
        GET STACKED DIAGNOSTICS reported = CONSTRAINT_NAME;
        IF api.core_unique_on_v1(reported,'command_log_pkey') THEN
            SELECT me.* INTO existing FROM public.command_log me WHERE me.command_id = command_id::uuid;
            IF NOT FOUND OR existing.idempotency_key IS NULL OR existing.idempotency_key <> p_log->>'idempotency_key' THEN
                command_id := api.core_uuid_v7_v1()::text;
                INSERT INTO public.command_log(actor_id,command_id,command_type,correlation_id,
                    created_at,handled_at,idempotency_key,payload,response_hash,status)
                VALUES ((p_log->>'actor_id')::uuid,command_id::uuid,p_log->>'command_type',
                    (p_log->>'command_correlation_id')::uuid,(p_log->>'command_at')::timestamptz,
                    NULL,p_log->>'idempotency_key',payload,NULL,'accepted');
            ELSIF jsonb_typeof(existing.payload) = 'object' AND existing.payload ? 'response' THEN
                SELECT * INTO held FROM api.core_command_existing_v1(existing.payload,p_log->>'request_hash');
                RETURN QUERY SELECT held.outcome,held.response::json,NULL::json; RETURN;
            ELSE command_id := existing.command_id::text; payload := coalesce(existing.payload,'{}'::jsonb);
            END IF;
        ELSIF api.core_unique_on_v1(reported,'command_log_idempotency_key_key') THEN
            SELECT me.* INTO existing FROM public.command_log me WHERE me.idempotency_key = p_log->>'idempotency_key' LIMIT 1;
            IF NOT FOUND THEN RAISE; END IF;
            SELECT * INTO held FROM api.core_command_existing_v1(existing.payload,p_log->>'request_hash');
            RETURN QUERY SELECT held.outcome,held.response::json,NULL::json; RETURN;
        ELSE RAISE;
        END IF;
    END;
    IF answer IS NULL THEN
        SELECT result.stored::jsonb INTO written FROM api.forum_store_write_v7(p_store_type,p_command,p_record) result;
        IF api.core_perl_true_v1(written->>'ok') THEN
            answer := jsonb_build_object('ok',1,'status','ok');
            IF written ? 'post' THEN answer := answer || jsonb_build_object('post_id',written #> '{post,post_id}'); END IF;
            IF written ? 'thread' THEN
                answer := answer || jsonb_build_object('thread_id',written #> '{thread,thread_id}');
                IF p_log->>'command_type' = 'thread.edit' THEN
                    answer := answer || jsonb_build_object('slug',written #> '{thread,slug}','title',written #> '{thread,title}');
                ELSIF p_log->>'command_type' = 'thread.move' THEN
                    answer := answer || jsonb_build_object('category_id',written #> '{thread,category_id}');
                END IF;
            ELSIF written ? 'post' THEN answer := answer || jsonb_build_object('thread_id',written #> '{post,thread_id}'); END IF;
        ELSE
            message := written->>'error';
            status := CASE WHEN message IN ('thread not found','post not found') THEN 'not_found' ELSE 'forbidden' END;
            answer := jsonb_build_object('ok',0,'status',status,'error',message);
        END IF;
    END IF;
    UPDATE public.command_log me SET handled_at = (p_log->>'command_at')::timestamptz,
        payload = payload || jsonb_build_object('response',answer),
        response_hash = encode(sha256(convert_to(api.core_canonical_json_v1(answer),'UTF8')),'hex'),
        status = CASE WHEN api.core_perl_true_v1(answer->>'ok') THEN 'handled' ELSE 'rejected' END
        WHERE me.command_id = command_id::uuid;
    IF p_draft_id IS NOT NULL AND api.core_perl_true_v1(answer->>'ok') THEN
        DELETE FROM public.forum_drafts d WHERE d.draft_id=p_draft_id;
    END IF;
    RETURN QUERY SELECT 'recorded'::text,answer::json,written::json;
END $$;
REVOKE EXECUTE ON FUNCTION api.forum_write_command_v9(p_log jsonb, p_answer jsonb, p_store_type text, p_command jsonb, p_record jsonb, p_draft_id uuid, p_draft_revision bigint) FROM PUBLIC;

CREATE FUNCTION api.forum_list_public_threads_v5(
    p_member boolean,
    p_global_read boolean,
    p_category_ids uuid[],
    p_space_ids uuid[],
    p_after_activity timestamptz,
    p_after_thread_id uuid,
    p_row_limit integer
)
RETURNS TABLE (
    thread_id uuid,
    category_id uuid,
    author_user_id uuid,
    title text,
    slug text,
    pinned boolean,
    visibility text,
    moderation_state text,
    last_activity_at timestamptz,
    created_at timestamptz,
    deleted_at timestamptz,
    author_username text,
    author_display_name text,
    reply_count bigint,
    excerpt text
)
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
#variable_conflict use_column
BEGIN
    IF p_after_thread_id IS NULL THEN
        RETURN QUERY
        SELECT me.thread_id, me.category_id, me.author_user_id, me.title, me.slug, me.pinned, me.visibility, me.moderation_state, me.last_activity_at, me.created_at, me.deleted_at, author.username,
            author.display_name, COALESCE((SELECT counter.reply_count
                FROM public.thread_counters counter
                WHERE counter.thread_id = me.thread_id), 0),
            (SELECT left(opening_body.body_rendered_safe, 1000)
                FROM public.posts opening
                JOIN public.post_bodies opening_body
                    ON opening_body.body_id = opening.current_body_id
                WHERE opening.thread_id = me.thread_id
                    AND opening.position = 1
                    AND opening.deleted_at IS NULL
                    AND opening.hidden_at IS NULL
                    AND opening.visibility = 'public'
                    AND opening.moderation_state = 'visible')
        FROM public.threads me
        JOIN public.users author ON author.id = me.author_user_id
        JOIN public.categories category ON category.category_id = me.category_id
        JOIN public.spaces space ON space.space_id = category.space_id
        WHERE me.deleted_at IS NULL
            AND me.moderation_state IN ('visible', 'locked')
            AND me.visibility = 'public'
            AND (category.visibility IN ('public', 'members', 'private')
        AND (p_global_read OR category.visibility = 'public'
            OR (p_member AND category.visibility = 'members')
            OR (category.visibility = 'private' AND
                (me.category_id = ANY(p_category_ids)
                    OR category.space_id = ANY(p_space_ids)))))
            AND (space.visibility IN ('public', 'members', 'private')
        AND (p_global_read OR space.visibility = 'public'
            OR (p_member AND space.visibility = 'members')
            OR (space.visibility = 'private' AND
                (me.category_id = ANY(p_category_ids)
                    OR category.space_id = ANY(p_space_ids)))))
        ORDER BY me.last_activity_at DESC, me.thread_id DESC
        LIMIT p_row_limit;
    ELSE
        RETURN QUERY
        SELECT me.thread_id, me.category_id, me.author_user_id, me.title, me.slug, me.pinned, me.visibility, me.moderation_state, me.last_activity_at, me.created_at, me.deleted_at, author.username,
            author.display_name, COALESCE((SELECT counter.reply_count
                FROM public.thread_counters counter
                WHERE counter.thread_id = me.thread_id), 0),
            (SELECT left(opening_body.body_rendered_safe, 1000)
                FROM public.posts opening
                JOIN public.post_bodies opening_body
                    ON opening_body.body_id = opening.current_body_id
                WHERE opening.thread_id = me.thread_id
                    AND opening.position = 1
                    AND opening.deleted_at IS NULL
                    AND opening.hidden_at IS NULL
                    AND opening.visibility = 'public'
                    AND opening.moderation_state = 'visible')
        FROM public.threads me
        JOIN public.users author ON author.id = me.author_user_id
        JOIN public.categories category ON category.category_id = me.category_id
        JOIN public.spaces space ON space.space_id = category.space_id
        WHERE me.deleted_at IS NULL
            AND me.moderation_state IN ('visible', 'locked')
            AND me.visibility = 'public'
            AND (category.visibility IN ('public', 'members', 'private')
        AND (p_global_read OR category.visibility = 'public'
            OR (p_member AND category.visibility = 'members')
            OR (category.visibility = 'private' AND
                (me.category_id = ANY(p_category_ids)
                    OR category.space_id = ANY(p_space_ids)))))
            AND (space.visibility IN ('public', 'members', 'private')
        AND (p_global_read OR space.visibility = 'public'
            OR (p_member AND space.visibility = 'members')
            OR (space.visibility = 'private' AND
                (me.category_id = ANY(p_category_ids)
                    OR category.space_id = ANY(p_space_ids)))))
            AND me.last_activity_at <= p_after_activity
            AND (me.last_activity_at < p_after_activity
                OR (me.last_activity_at = p_after_activity
                    AND me.thread_id < p_after_thread_id))
        ORDER BY me.last_activity_at DESC, me.thread_id DESC
        LIMIT p_row_limit;
    END IF;
END
$$;
REVOKE EXECUTE ON FUNCTION api.forum_list_public_threads_v5(p_member boolean, p_global_read boolean, p_category_ids uuid[], p_space_ids uuid[], p_after_activity timestamp with time zone, p_after_thread_id uuid, p_row_limit integer) FROM PUBLIC;

CREATE FUNCTION api.forum_filter_tagged_threads_v1(
    p_tag_slugs text[],
    p_tag_match text,
    p_category_id uuid,
    p_member boolean,
    p_global_read boolean,
    p_scope_user_id uuid,
    p_category_ids uuid[],
    p_space_ids uuid[],
    p_row_limit integer,
    p_after_activity timestamptz,
    p_after_thread_id uuid
)
RETURNS TABLE (
    thread_id uuid,
    category_id uuid,
    author_user_id uuid,
    title text,
    slug text,
    pinned boolean,
    visibility text,
    moderation_state text,
    locked_at timestamptz,
    last_activity_at timestamptz,
    created_at timestamptz,
    deleted_at timestamptz,
    author_username text,
    author_display_name text,
    category_title text,
    reply_count bigint
)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT me.thread_id, me.category_id, me.author_user_id, me.title, me.slug,
    me.pinned, me.visibility, me.moderation_state, me.locked_at,
    me.last_activity_at, me.created_at, me.deleted_at, author.username,
    author.display_name, category.title,
    COALESCE((SELECT counter.reply_count
        FROM public.thread_counters counter
        WHERE counter.thread_id = me.thread_id), 0)
FROM public.threads me
JOIN public.users author ON author.id = me.author_user_id
JOIN public.categories category ON category.category_id = me.category_id
JOIN public.spaces space ON space.space_id = category.space_id
WHERE api.core_thread_matches_tags_v1(me.thread_id, p_tag_slugs, p_tag_match)
    AND category.deleted_at IS NULL AND space.deleted_at IS NULL
    AND (p_after_activity IS NULL OR (me.last_activity_at, me.thread_id) < (p_after_activity, p_after_thread_id))
    AND (p_category_id IS NULL OR me.category_id = p_category_id)
    AND me.deleted_at IS NULL
    AND me.moderation_state IN ('visible', 'locked')
    AND (p_global_read OR me.visibility = 'public'
        OR (p_member AND me.visibility = 'members')
        OR (me.visibility = 'private' AND p_member
            AND (me.author_user_id = p_scope_user_id
                OR me.category_id = ANY(p_category_ids)
                OR category.space_id = ANY(p_space_ids))))
    AND (p_global_read OR category.visibility = 'public'
        OR (p_member AND category.visibility = 'members')
        OR (category.visibility = 'private' AND
            (me.category_id = ANY(p_category_ids)
                OR category.space_id = ANY(p_space_ids))))
    AND (p_global_read OR space.visibility = 'public'
        OR (p_member AND space.visibility = 'members')
        OR (space.visibility = 'private' AND
            (me.category_id = ANY(p_category_ids)
                OR category.space_id = ANY(p_space_ids))))
ORDER BY me.last_activity_at DESC, me.thread_id DESC
LIMIT least(greatest(p_row_limit, 1), 101)
$$;
REVOKE EXECUTE ON FUNCTION api.forum_filter_tagged_threads_v1(p_tag_slugs text[], p_tag_match text, p_category_id uuid, p_member boolean, p_global_read boolean, p_scope_user_id uuid, p_category_ids uuid[], p_space_ids uuid[], p_row_limit integer, p_after_activity timestamp with time zone, p_after_thread_id uuid) FROM PUBLIC;

CREATE FUNCTION api.forum_poll_change_v7(p_actor uuid, p_command uuid, p_thread_id uuid, p_operation text, p_values jsonb)
RETURNS TABLE (result jsonb)
LANGUAGE plpgsql
VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE opened record; answer jsonb; thread public.threads; poll public.thread_polls;
    old_choice integer; choice integer; n integer; labels text[]; choices integer[]; maximum integer;
BEGIN
    IF jsonb_typeof(p_values) IS DISTINCT FROM 'object' OR p_operation IS NULL OR p_operation NOT IN ('create','vote','close') OR p_values IS NULL THEN
        RETURN QUERY SELECT jsonb_build_object('status','invalid'); RETURN;
    END IF;
    PERFORM 1 FROM public.users u WHERE u.id = p_actor AND u.status = 'active' FOR SHARE;
    IF NOT FOUND THEN RETURN QUERY SELECT jsonb_build_object('status','forbidden'); RETURN; END IF;
    IF NOT api.core_product_read_thread_v1(p_actor,p_thread_id)
        OR NOT api.core_forum_draft_target_v1(p_actor,'reply',NULL,p_thread_id) THEN
        RETURN QUERY SELECT jsonb_build_object('status','not_found'); RETURN;
    END IF;
    SELECT * INTO opened FROM api.core_product_open_v1(p_actor,p_command,'forum.poll.' || p_operation,
        jsonb_build_object('thread',p_thread_id,'values',p_values));
    IF opened.outcome <> 'opened' THEN
        RETURN QUERY SELECT coalesce(opened.response,jsonb_build_object('status','conflict')); RETURN;
    END IF;
    SELECT * INTO thread FROM public.threads t WHERE t.thread_id = p_thread_id FOR KEY SHARE;
    SELECT * INTO poll FROM public.thread_polls p WHERE p.thread_id = p_thread_id FOR UPDATE;
    answer := jsonb_build_object('status','ok');
    IF p_operation = 'create' THEN
        IF thread.author_user_id <> p_actor THEN answer := jsonb_build_object('status','forbidden');
        ELSIF thread.locked_at IS NOT NULL OR poll.thread_id IS NOT NULL THEN answer := jsonb_build_object('status','conflict');
        ELSIF coalesce(length(btrim(p_values->>'question')),0) NOT BETWEEN 1 AND 200
            OR jsonb_typeof(p_values->'options') IS DISTINCT FROM 'array' THEN answer := jsonb_build_object('status','invalid');
        ELSE
            IF EXISTS(SELECT 1 FROM jsonb_array_elements(p_values->'options') x WHERE jsonb_typeof(x) <> 'string') THEN
                RETURN QUERY SELECT api.core_product_close_v1(opened.command_id,opened.payload,jsonb_build_object('status','invalid')); RETURN;
            END IF;
            SELECT array_agg(btrim(x.label) ORDER BY x.n) INTO labels
                FROM jsonb_array_elements_text(p_values->'options') WITH ORDINALITY x(label,n);
            n := cardinality(labels);
            maximum := CASE WHEN coalesce(p_values->>'maximum_choices','1') ~ '^(10|[1-9])$' THEN coalesce(p_values->>'maximum_choices','1')::integer ELSE 0 END;
            IF maximum NOT BETWEEN 1 AND coalesce(n,0) OR n IS NULL OR n NOT BETWEEN 2 AND 10 OR EXISTS(SELECT 1 FROM unnest(labels) x WHERE x IS NULL OR length(x) NOT BETWEEN 1 AND 120)
                OR (SELECT count(DISTINCT x) FROM unnest(labels) x) <> n THEN answer := jsonb_build_object('status','invalid');
            ELSE
                INSERT INTO public.thread_polls(thread_id,question,created_by,closes_at,maximum_choices)
                VALUES (p_thread_id,btrim(p_values->>'question'),p_actor,clock_timestamp()+interval '30 days',maximum)
                ON CONFLICT (thread_id) DO NOTHING;
                IF NOT FOUND THEN answer := jsonb_build_object('status','conflict');
                ELSE
                    INSERT INTO public.poll_options(thread_id,option_number,label)
                        SELECT p_thread_id,x.n::integer,x.label FROM unnest(labels) WITH ORDINALITY x(label,n);
                END IF;
            END IF;
        END IF;
    ELSIF poll.thread_id IS NULL THEN answer := jsonb_build_object('status','not_found');
    ELSIF p_operation = 'close' THEN
        IF thread.author_user_id <> p_actor AND NOT api.core_product_staff_v1(p_actor,'thread','moderate') THEN answer := jsonb_build_object('status','forbidden');
        ELSE UPDATE public.thread_polls SET closed_at = coalesce(closed_at,clock_timestamp()) WHERE thread_id = p_thread_id; END IF;
    ELSIF thread.locked_at IS NOT NULL OR poll.closed_at IS NOT NULL OR poll.closes_at <= clock_timestamp() THEN answer := jsonb_build_object('status','closed');
    ELSE
        IF p_values ? 'choices' THEN
            IF jsonb_typeof(p_values->'choices') IS DISTINCT FROM 'array' THEN
                RETURN QUERY SELECT api.core_product_close_v1(opened.command_id,opened.payload,jsonb_build_object('status','invalid')); RETURN;
            END IF;
            IF jsonb_array_length(p_values->'choices') NOT BETWEEN 1 AND 10
                OR EXISTS(SELECT 1 FROM jsonb_array_elements_text(p_values->'choices') selected
                    WHERE selected IS NULL OR selected !~ '^(10|[1-9])$') THEN
                RETURN QUERY SELECT api.core_product_close_v1(opened.command_id,opened.payload,jsonb_build_object('status','invalid')); RETURN;
            END IF;
            SELECT array_agg(selected::integer ORDER BY selected::integer) INTO choices
                FROM jsonb_array_elements_text(p_values->'choices') selected;
        ELSIF coalesce(p_values->>'choice','') ~ '^(10|[1-9])$' THEN
            choices := ARRAY[(p_values->>'choice')::integer];
        END IF;
        IF choices IS NULL OR cardinality(choices) NOT BETWEEN 1 AND poll.maximum_choices
            OR (SELECT count(DISTINCT selected) FROM unnest(choices) selected) <> cardinality(choices)
            OR EXISTS(SELECT 1 FROM unnest(choices) selected WHERE NOT EXISTS (
                SELECT 1 FROM public.poll_options o WHERE o.thread_id=p_thread_id AND o.option_number=selected)) THEN
            answer := jsonb_build_object('status','invalid');
        ELSE
            choice := choices[1];
            DELETE FROM public.poll_ballot_extra_choices e WHERE e.thread_id=p_thread_id AND e.user_id=p_actor;
            SELECT b.option_number INTO old_choice FROM public.poll_ballots b WHERE b.thread_id=p_thread_id AND b.user_id=p_actor;
            IF old_choice IS DISTINCT FROM choice THEN
                UPDATE public.poll_options o SET votes=o.votes-1 WHERE o.thread_id=p_thread_id AND o.option_number=old_choice;
                INSERT INTO public.poll_ballots(thread_id,user_id,option_number) VALUES(p_thread_id,p_actor,choice)
                ON CONFLICT(thread_id,user_id) DO UPDATE SET option_number=EXCLUDED.option_number,updated_at=clock_timestamp();
                UPDATE public.poll_options o SET votes=o.votes+1 WHERE o.thread_id=p_thread_id AND o.option_number=choice;
            END IF;
            UPDATE public.poll_ballots SET updated_at=clock_timestamp() WHERE thread_id=p_thread_id AND user_id=p_actor;
            INSERT INTO public.poll_ballot_extra_choices(thread_id,user_id,option_number)
                SELECT p_thread_id,p_actor,selected FROM unnest(choices) selected WHERE selected <> choice ORDER BY selected;
        END IF;
    END IF;
    IF answer->>'status' = 'ok' THEN
        PERFORM api.core_product_audit_v1(p_actor,p_command,'forum.poll.' || p_operation,p_thread_id,'thread','{}'::jsonb);
    END IF;
    RETURN QUERY SELECT api.core_product_close_v1(opened.command_id,opened.payload,answer);
END;
$$;
REVOKE EXECUTE ON FUNCTION api.forum_poll_change_v7(p_actor uuid, p_command uuid, p_thread_id uuid, p_operation text, p_values jsonb) FROM PUBLIC;

CREATE FUNCTION api.forum_poll_read_v3(p_actor uuid, p_thread_id uuid)
RETURNS TABLE (result jsonb)
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    IF NOT api.core_product_read_thread_v1(p_actor,p_thread_id) THEN
        RETURN QUERY SELECT jsonb_build_object('status','not_found'); RETURN;
    END IF;
    RETURN QUERY SELECT jsonb_build_object('status','ok','poll',
        (SELECT jsonb_build_object('question',p.question,'closes_at',p.closes_at,
            'closed',p.closed_at IS NOT NULL OR p.closes_at <= statement_timestamp(),
            'maximum_choices',p.maximum_choices,
            'choices',coalesce((SELECT jsonb_agg(selection.option_number ORDER BY selection.option_number) FROM (SELECT b.option_number FROM public.poll_ballots b WHERE b.thread_id=p_thread_id AND b.user_id=p_actor UNION ALL SELECT e.option_number FROM public.poll_ballot_extra_choices e WHERE e.thread_id=p_thread_id AND e.user_id=p_actor) selection),'[]'::jsonb),
            'options',(SELECT jsonb_agg(jsonb_build_object('number',o.option_number,'label',o.label,'votes',o.votes)
                ORDER BY o.option_number) FROM public.poll_options o WHERE o.thread_id = p_thread_id),
            'choice',(SELECT b.option_number FROM public.poll_ballots b WHERE b.thread_id = p_thread_id AND b.user_id = p_actor))
        FROM public.thread_polls p WHERE p.thread_id = p_thread_id),
        'can_create',EXISTS(SELECT 1 FROM public.threads t WHERE t.thread_id = p_thread_id AND t.author_user_id = p_actor AND t.locked_at IS NULL),
        'can_close',EXISTS(SELECT 1 FROM public.threads t WHERE t.thread_id = p_thread_id AND t.author_user_id = p_actor)
            OR api.core_product_staff_v1(p_actor,'thread','moderate'));
END;
$$;
REVOKE EXECUTE ON FUNCTION api.forum_poll_read_v3(p_actor uuid, p_thread_id uuid) FROM PUBLIC;

CREATE FUNCTION api.forum_post_context_v1(p_post_id uuid)
RETURNS TABLE (post json, thread json)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT (to_jsonb(p) || jsonb_build_object(
        'created_at', p.created_at::text, 'updated_at', p.updated_at::text,
        'hidden_at', p.hidden_at::text, 'locked_at', p.locked_at::text,
        'deleted_at', p.deleted_at::text))::json,
    CASE WHEN head.thread_id IS NOT NULL THEN
        (to_jsonb(head) || jsonb_build_object(
            'pinned', CASE WHEN head.pinned THEN 1 ELSE 0 END,
            'locked_at', head.locked_at::text,
            'last_activity_at', head.last_activity_at::text,
            'deleted_at', head.deleted_at::text))::json
    END
FROM public.posts p
LEFT JOIN LATERAL api.forum_thread_page_head_v1(p.thread_id) head ON true
WHERE p.post_id = p_post_id;
$$;
REVOKE EXECUTE ON FUNCTION api.forum_post_context_v1(p_post_id uuid) FROM PUBLIC;

CREATE FUNCTION api.forum_resolve_viewer_v5(p_user_id uuid)
RETURNS TABLE (
    status text,
    suspended boolean,
    grants json,
    moderates boolean,
    listed uuid[]
)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT v.status, v.suspended, v.grants, v.moderates,
    coalesce((SELECT array_agg(r.other_user_id ORDER BY r.other_user_id)
        FROM public.member_relations r WHERE r.owner_user_id = p_user_id),
        '{}'::uuid[]) AS listed
FROM api.forum_resolve_viewer_v3(p_user_id) v
$$;
REVOKE EXECUTE ON FUNCTION api.forum_resolve_viewer_v5(p_user_id uuid) FROM PUBLIC;

CREATE FUNCTION api.forum_thread_page_posts_v3(
    p_thread_id uuid,
    p_standing text,
    p_viewer_user_id uuid,
    p_after_position bigint,
    p_after_post_id uuid,
    p_row_limit integer
)
RETURNS TABLE (
    post_id uuid,
    thread_id uuid,
    author_user_id uuid,
    current_body_id uuid,
    "position" bigint,
    visibility text,
    moderation_state text,
    created_at timestamptz,
    deleted_at timestamptz,
    body text,
    body_source text,
    author_username text,
    author_display_name text,
    author_avatar_id uuid
)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT p.post_id, p.thread_id, p.author_user_id, p.current_body_id,
    p.position, p.visibility, p.moderation_state, p.created_at,
    p.deleted_at, p.body, p.body_source, p.author_username,
    p.author_display_name, shown.attachment_id
FROM api.forum_thread_page_posts_v1(p_thread_id, p_standing,
    p_viewer_user_id, p_after_position, p_after_post_id, p_row_limit)
    WITH ORDINALITY AS p
LEFT JOIN public.member_avatars m ON m.user_id = p.author_user_id
LEFT JOIN public.attachments shown ON shown.attachment_id = m.attachment_id
    AND shown.state = 'available' AND shown.scan_status = 'clean'
    AND shown.deleted_at IS NULL
ORDER BY p.ordinality
$$;
REVOKE EXECUTE ON FUNCTION api.forum_thread_page_posts_v3(p_thread_id uuid, p_standing text, p_viewer_user_id uuid, p_after_position bigint, p_after_post_id uuid, p_row_limit integer) FROM PUBLIC;

CREATE FUNCTION api.forum_resolve_viewer_v9(p_user_id uuid)
RETURNS TABLE (
    status text,
    suspended boolean,
    grants json,
    moderates boolean,
    listed uuid[],
    trust_level integer
)
LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT v.status, v.suspended, v.grants, v.moderates, v.listed,
    CASE WHEN v.status = 'active' AND NOT v.suspended AND u.deleted_at IS NULL
         THEN u.trust_level ELSE 0 END
FROM api.forum_resolve_viewer_v5(p_user_id) v
JOIN public.users u ON u.id = p_user_id;
$$;
REVOKE EXECUTE ON FUNCTION api.forum_resolve_viewer_v9(p_user_id uuid) FROM PUBLIC;

COMMIT;
