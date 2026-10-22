-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

-- Reading and writing the forum: pages, threads, posts, read marks, drafts and
-- tags. The thread page reads each post's extras (likes, reactions, replies,
-- tags, attachments, bookmark and subscription) in one call
-- (forum_thread_page_reads).

BEGIN;
SET LOCAL lock_timeout = '1s';

-- What every page shows: the announcements not retired, newest first.
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
REVOKE EXECUTE ON FUNCTION api.forum_active_announcements_v1(integer)
    FROM PUBLIC;

-- Writes a reply as one idempotent command (ADR 0126): the command log, the
-- thread row FOR NO KEY UPDATE, the post, its body and revision, the counter,
-- the event, the outbox message and the audit row, and, when a draft is
-- published, the draft.
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
REVOKE EXECUTE ON FUNCTION api.forum_create_reply_v3(text, text, text, text, text, text, text, jsonb, jsonb, text, text, text, text, text, bigint, text, text, bigint, bigint, bigint, text, text, text, text, text, text, text, text, text, text, text, text, text, text, integer, text, text, text, text, text, text, uuid, bigint)
    FROM PUBLIC;

-- A member's draft, while it lasts and the member is active.
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
REVOKE EXECUTE ON FUNCTION api.forum_draft_find_v1(uuid, uuid, timestamptz)
    FROM PUBLIC;

-- A member's drafts, while they last, most recently saved first, without their
-- bodies.
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
REVOKE EXECUTE ON FUNCTION api.forum_draft_list_v1(uuid, timestamptz)
    FROM PUBLIC;

-- Deletes the drafts that expired, a bounded batch at a time, skipping rows
-- another transaction holds.
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
REVOKE EXECUTE ON FUNCTION api.forum_draft_purge_v1(timestamptz, integer)
    FROM PUBLIC;

-- Deletes a member's draft at the revision they read.
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
REVOKE EXECUTE ON FUNCTION api.forum_draft_remove_v1(uuid, uuid, bigint, timestamptz)
    FROM PUBLIC;

-- Saves a member's draft at the revision they read, so two tabs cannot
-- overwrite each other.
CREATE FUNCTION api.forum_draft_save_v1(
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
    -- One account lock serializes quota checks and prevents save after erasure.
    PERFORM 1 FROM public.users u WHERE u.id = p_owner_user_id
        AND u.status = 'active' AND u.deleted_at IS NULL FOR UPDATE;
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
REVOKE EXECUTE ON FUNCTION api.forum_draft_save_v1(uuid, uuid, bigint, text, uuid, uuid, text, text, text, text, timestamptz)
    FROM PUBLIC;

-- A category with its space's visibility.
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
REVOKE EXECUTE ON FUNCTION api.forum_find_category_v1(uuid) FROM PUBLIC;

-- A visible post of a thread, with its body and author, if the viewer may read
-- it.
CREATE FUNCTION api.forum_find_listed_post_v1(
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
SET plan_cache_mode = force_custom_plan
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
REVOKE EXECUTE ON FUNCTION api.forum_find_listed_post_v1(uuid, uuid, boolean, boolean, uuid, uuid)
    FROM PUBLIC;

-- The post with this id.
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
REVOKE EXECUTE ON FUNCTION api.forum_find_post_v1(uuid) FROM PUBLIC;

-- A post not deleted and visible, with the visibility of its thread, category
-- and space.
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
REVOKE EXECUTE ON FUNCTION api.forum_find_visible_post_v1(uuid) FROM PUBLIC;

-- Links a reply to the post it answers, when both are in one thread and the
-- post answered is there to be read; a link written twice is one.
CREATE FUNCTION api.forum_link_reply_v1(
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
    WHERE reply.post_id = p_post_id
        AND target.post_id = p_reply_to_post_id
        AND target.post_id <> reply.post_id
        AND target.deleted_at IS NULL
        AND target.moderation_state = 'visible'
    ON CONFLICT ON CONSTRAINT post_replies_pkey DO NOTHING;
    GET DIAGNOSTICS added = ROW_COUNT;
    RETURN QUERY SELECT added = 1
        OR EXISTS (SELECT 1 FROM public.post_replies r
            WHERE r.post_id = p_post_id
                AND r.reply_to_post_id = p_reply_to_post_id);
END;
$$;
REVOKE EXECUTE ON FUNCTION api.forum_link_reply_v1(uuid, uuid) FROM PUBLIC;

-- The categories a viewer may read, in the forum's order, with their thread
-- counts and last activity.
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
REVOKE EXECUTE ON FUNCTION api.forum_list_categories_v3(boolean, boolean, uuid[], uuid[], integer)
    FROM PUBLIC;

-- A page of a category's threads in keyset order (pinned first, latest
-- activity first), with the viewer's own deleted threads.
CREATE FUNCTION api.forum_list_category_threads_v1(
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
SET plan_cache_mode = force_custom_plan
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
REVOKE EXECUTE ON FUNCTION api.forum_list_category_threads_v1(uuid, boolean, boolean, uuid, uuid, boolean, timestamptz, uuid, integer)
    FROM PUBLIC;

-- A page of the latest threads the viewer may read, in keyset order.
CREATE FUNCTION api.forum_list_public_threads_v1(
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
    reply_count bigint
)
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
#variable_conflict use_column
BEGIN
    IF p_after_thread_id IS NULL THEN
        RETURN QUERY
        SELECT me.thread_id, me.category_id, me.author_user_id, me.title, me.slug, me.pinned, me.visibility, me.moderation_state, me.last_activity_at, me.created_at, me.deleted_at, author.username,
            author.display_name, COALESCE((SELECT counter.reply_count
                FROM public.thread_counters counter
                WHERE counter.thread_id = me.thread_id), 0)
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
                WHERE counter.thread_id = me.thread_id), 0)
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
REVOKE EXECUTE ON FUNCTION api.forum_list_public_threads_v1(boolean, boolean, uuid[], uuid[], timestamptz, uuid, integer)
    FROM PUBLIC;

-- The threads under one tag the reader may read (ADR 0102: the thread's
-- own visibility, then its category's and its space's), in every category
-- or in one, newest activity first.
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
REVOKE EXECUTE ON FUNCTION api.forum_list_tagged_threads_v1(text, uuid, boolean, boolean, uuid, uuid[], uuid[], integer)
    FROM PUBLIC;

-- Every tag with how many threads the reader may read under it, the most
-- used first; a tag with none the reader may read is absent.
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
REVOKE EXECUTE ON FUNCTION api.forum_list_tags_v1(boolean, boolean, uuid, uuid[], uuid[], integer)
    FROM PUBLIC;

-- Moves a member's read position in a thread forward, never back.
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
REVOKE EXECUTE ON FUNCTION api.forum_mark_read_v1(jsonb) FROM PUBLIC;

-- The position the next post of a thread takes.
CREATE FUNCTION api.forum_next_position_v1(p_thread_id uuid)
RETURNS TABLE (next_position bigint)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT COALESCE(MAX(p.position),0)+1 FROM public.posts p WHERE p.thread_id=p_thread_id;
$$;
REVOKE EXECUTE ON FUNCTION api.forum_next_position_v1(uuid) FROM PUBLIC;

-- The head of a thread page: the thread with its author, category and space,
-- and its counters.
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
REVOKE EXECUTE ON FUNCTION api.forum_thread_page_head_v1(uuid) FROM PUBLIC;

-- A post and its thread, as documents, for a write to check before it locks
-- them.
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
REVOKE EXECUTE ON FUNCTION api.forum_post_context_v1(uuid) FROM PUBLIC;

-- Where a post stands: its thread, category and space, and the visibility and
-- state of each, for the search and the feed to judge who may read it.
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
REVOKE EXECUTE ON FUNCTION api.forum_post_placement_v1(uuid) FROM PUBLIC;

-- Marking a thread read: the command log around api.forum_mark_read_v1, and
-- the answer ReadWorkflow records: whether the marker advanced, and the
-- state's four columns. p_answer, when given, is the store's refusal of the
-- request, recorded without running the mark.
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
REVOKE EXECUTE ON FUNCTION api.forum_read_marker_command_v1(jsonb, jsonb, jsonb)
    FROM PUBLIC;

-- How far a member has read a thread.
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
REVOKE EXECUTE ON FUNCTION api.forum_read_state_v1(uuid, uuid) FROM PUBLIC;

-- For the posts of a page, the post each answers, with its position and its
-- author's name.
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
REVOKE EXECUTE ON FUNCTION api.forum_reply_targets_v1(uuid[]) FROM PUBLIC;

-- A member's status, whether they are suspended, and their role bindings: what
-- a request needs to know about its viewer.
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
REVOKE EXECUTE ON FUNCTION api.forum_resolve_viewer_v1(uuid) FROM PUBLIC;

-- A member's status, whether they are suspended, their role bindings and
-- whether they moderate.
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
REVOKE EXECUTE ON FUNCTION api.forum_resolve_viewer_v3(uuid) FROM PUBLIC;

-- The reader of a request learns the members on their list with the rest of
-- who they are, in the viewer's one query: a thread page collapses their
-- posts without a second lookup.
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
REVOKE EXECUTE ON FUNCTION api.forum_resolve_viewer_v5(uuid) FROM PUBLIC;

-- Replaces a thread's tags with the slugs given, in their order, each with
-- the name given when the tag is new. Slugs and names are the caller's,
-- already normalised; a thread that does not exist takes none. Answers the
-- thread's tags as they are now.
CREATE FUNCTION api.forum_set_thread_tags_v1(
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
    IF NOT EXISTS (SELECT 1 FROM public.threads t WHERE t.thread_id = p_thread_id)
    THEN
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
REVOKE EXECUTE ON FUNCTION api.forum_set_thread_tags_v1(uuid, text[], text[])
    FROM PUBLIC;

-- The store's half of a forum write command: the reply, thread or post write
-- it names, answered as the store answers.
CREATE FUNCTION api.forum_store_write_v1(
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
      WHEN 'thread.created' THEN answer := api.core_forum_create_thread_v1(p_command,p_record);
      WHEN 'thread.updated','thread.moved','thread.deleted','thread.undeleted' THEN
        answer := api.core_forum_write_thread_v1(p_store_type,p_command,p_record);
      WHEN 'post.updated','post.deleted','post.undeleted' THEN
        answer := api.core_forum_write_post_v1(p_store_type,p_command,p_record);
      ELSE RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'unknown forum store type';
    END CASE;
    RETURN QUERY SELECT answer::json;
END $$;
REVOKE EXECUTE ON FUNCTION api.forum_store_write_v1(text, jsonb, jsonb)
    FROM PUBLIC;

-- The original prepared path permits different users for visibility scope
-- and ownership of deleted rows. Preserve that case without a client-built
-- resultset: its first and cursor pages keep independent statements.
CREATE FUNCTION api.forum_thread_page_posts_scoped_v1(
    p_thread_id uuid,
    p_standing text,
    p_scope_user_id uuid,
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
SET plan_cache_mode = force_custom_plan
AS $$
#variable_conflict use_column
BEGIN
    IF p_after_post_id IS NULL THEN
        RETURN QUERY
        SELECT me.post_id, me.thread_id, me.author_user_id, me.current_body_id,
            me.position, me.visibility, me.moderation_state, me.created_at,
            me.deleted_at, current_body.body_rendered_safe,
            current_body.body_source, author.username, author.display_name
        FROM public.posts me
        LEFT JOIN public.post_bodies current_body
            ON current_body.body_id = me.current_body_id
        JOIN public.users author ON author.id = me.author_user_id
        WHERE me.thread_id = p_thread_id
            AND me.moderation_state = 'visible'
            AND ((p_standing = 'global' AND me.visibility IN ('public', 'members', 'private'))
                OR (p_standing = 'member' AND
                    (me.visibility IN ('public', 'members')
                        OR (me.visibility = 'private' AND me.author_user_id = p_scope_user_id)))
                OR (p_standing = 'anonymous' AND me.visibility = 'public'))
            AND (me.deleted_at IS NULL OR me.author_user_id = p_viewer_user_id)
        ORDER BY me.position ASC, me.post_id ASC LIMIT p_row_limit;
    ELSE
        RETURN QUERY
        SELECT me.post_id, me.thread_id, me.author_user_id, me.current_body_id,
            me.position, me.visibility, me.moderation_state, me.created_at,
            me.deleted_at, current_body.body_rendered_safe,
            current_body.body_source, author.username, author.display_name
        FROM public.posts me
        LEFT JOIN public.post_bodies current_body
            ON current_body.body_id = me.current_body_id
        JOIN public.users author ON author.id = me.author_user_id
        WHERE me.thread_id = p_thread_id
            AND me.moderation_state = 'visible'
            AND ((p_standing = 'global' AND me.visibility IN ('public', 'members', 'private'))
                OR (p_standing = 'member' AND
                    (me.visibility IN ('public', 'members')
                        OR (me.visibility = 'private' AND me.author_user_id = p_scope_user_id)))
                OR (p_standing = 'anonymous' AND me.visibility = 'public'))
            AND (me.deleted_at IS NULL OR me.author_user_id = p_viewer_user_id)
            AND me.position >= p_after_position
            AND (me.position > p_after_position
                OR (me.position = p_after_position AND me.post_id > p_after_post_id))
        ORDER BY me.position ASC, me.post_id ASC LIMIT p_row_limit;
    END IF;
END
$$;
REVOKE EXECUTE ON FUNCTION api.forum_thread_page_posts_scoped_v1(uuid, text, uuid, uuid, bigint, uuid, integer)
    FROM PUBLIC;

-- The scoped thread page's posts with each author's picture, when they
-- show one: forum_thread_page_posts_scoped_v1's rows, in their order, and
-- the attachment shown.
CREATE FUNCTION api.forum_thread_page_posts_scoped_v3(
    p_thread_id uuid,
    p_standing text,
    p_scope_user_id uuid,
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
SET plan_cache_mode = force_custom_plan
AS $$
SELECT p.post_id, p.thread_id, p.author_user_id, p.current_body_id,
    p.position, p.visibility, p.moderation_state, p.created_at,
    p.deleted_at, p.body, p.body_source, p.author_username,
    p.author_display_name, shown.attachment_id
FROM api.forum_thread_page_posts_scoped_v1(p_thread_id, p_standing,
    p_scope_user_id, p_viewer_user_id, p_after_position, p_after_post_id,
    p_row_limit) WITH ORDINALITY AS p
LEFT JOIN public.member_avatars m ON m.user_id = p.author_user_id
LEFT JOIN public.attachments shown ON shown.attachment_id = m.attachment_id
    AND shown.state = 'available' AND shown.scan_status = 'clean'
    AND shown.deleted_at IS NULL
ORDER BY p.ordinality
$$;
REVOKE EXECUTE ON FUNCTION api.forum_thread_page_posts_scoped_v3(uuid, text, uuid, uuid, bigint, uuid, integer)
    FROM PUBLIC;

-- A page of a thread's posts in position order after the cursor, with bodies
-- and authors, as the viewer's standing allows; one statement per shape (ADR
-- 0126, section 4).
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
REVOKE EXECUTE ON FUNCTION api.forum_thread_page_posts_v1(uuid, text, uuid, bigint, uuid, integer)
    FROM PUBLIC;

-- The thread page's posts with each author's picture, when they show one:
-- forum_thread_page_posts_v1's rows, in their order, and the attachment shown.
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
REVOKE EXECUTE ON FUNCTION api.forum_thread_page_posts_v3(uuid, text, uuid, bigint, uuid, integer)
    FROM PUBLIC;

-- The tags of the threads of a page, in each thread's order.
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
REVOKE EXECUTE ON FUNCTION api.forum_thread_tags_v1(uuid[]) FROM PUBLIC;

-- The thread page's one read (124), answering the reactions too.
CREATE FUNCTION api.forum_thread_page_reads_v3(
    p_thread_id uuid,
    p_post_ids uuid[],
    p_viewer_user_id uuid,
    p_engagement_target_type text,
    p_link_target_type text,
    p_link_post_ids uuid[],
    p_link_row_limit integer
)
RETURNS TABLE (
    part text,
    ordinal bigint,
    post_id uuid,
    like_count bigint,
    liked boolean,
    reply_to_post_id uuid,
    reply_to_position bigint,
    reply_to_author_username text,
    thread_id uuid,
    slug text,
    name text,
    tag_position smallint,
    attachment_link_id uuid,
    attachment_id uuid,
    target_type text,
    target_id uuid,
    created_at timestamptz,
    bookmark_id uuid,
    user_id uuid,
    note text,
    deleted_at timestamptz,
    subscription_id uuid,
    preference text,
    muted_at timestamptz,
    revoked_at timestamptz,
    last_read_position bigint,
    last_read_at timestamptz,
    reaction text,
    reaction_count bigint,
    reacted boolean
)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
-- api.community_post_likes_v1
SELECT 'like'::text, row_number() OVER (), l.post_id, l.like_count, l.liked,
    NULL::uuid, NULL::bigint, NULL::text,
    NULL::uuid, NULL::text, NULL::text, NULL::smallint,
    NULL::uuid, NULL::uuid, NULL::text, NULL::uuid, NULL::timestamptz,
    NULL::uuid, NULL::uuid, NULL::text, NULL::timestamptz,
    NULL::uuid, NULL::text, NULL::timestamptz, NULL::timestamptz,
    NULL::bigint, NULL::timestamptz,
    NULL::text, NULL::bigint, NULL::boolean
FROM (
    SELECT pl.post_id, count(*)::bigint AS like_count,
        coalesce(bool_or(pl.user_id = p_viewer_user_id), false) AS liked
    FROM public.post_likes pl
    WHERE pl.post_id = ANY(p_post_ids)
    GROUP BY pl.post_id
) l
UNION ALL
-- api.forum_reply_targets_v1
SELECT 'reply_target', row_number() OVER (), r.post_id, NULL, NULL,
    r.reply_to_post_id, target.position, author.username,
    NULL, NULL, NULL, NULL,
    NULL, NULL, NULL, NULL, NULL,
    NULL, NULL, NULL, NULL,
    NULL, NULL, NULL, NULL,
    NULL, NULL,
    NULL, NULL, NULL
FROM public.post_replies r
JOIN public.posts target ON target.post_id = r.reply_to_post_id
LEFT JOIN public.users author ON author.id = target.author_user_id
WHERE r.post_id = ANY(p_post_ids)
UNION ALL
-- api.forum_thread_tags_v1, for the page's thread
SELECT 'tag', row_number() OVER (ORDER BY tt.thread_id, tt.position), NULL,
    NULL, NULL,
    NULL, NULL, NULL,
    tt.thread_id, t.slug, t.name, tt.position,
    NULL, NULL, NULL, NULL, NULL,
    NULL, NULL, NULL, NULL,
    NULL, NULL, NULL, NULL,
    NULL, NULL,
    NULL, NULL, NULL
FROM public.thread_tags tt
JOIN public.tags t ON t.tag_id = tt.tag_id
WHERE tt.thread_id = p_thread_id
UNION ALL
-- api.attachment_links_v1, by the posts' ids
SELECT 'attachment_link', row_number() OVER (), NULL, NULL, NULL,
    NULL, NULL, NULL,
    NULL, NULL, NULL, NULL,
    a.attachment_link_id, a.attachment_id, a.target_type, a.target_id,
    a.created_at,
    NULL, NULL, NULL, NULL,
    NULL, NULL, NULL, NULL,
    NULL, NULL,
    NULL, NULL, NULL
FROM (
    SELECT al.* FROM public.attachment_links al
    WHERE al.target_type = p_link_target_type
        AND al.target_id = ANY(p_link_post_ids)
    LIMIT p_link_row_limit
) a
UNION ALL
-- api.community_find_bookmark_v1
SELECT 'bookmark', row_number() OVER (), NULL, NULL, NULL,
    NULL, NULL, NULL,
    NULL, NULL, NULL, NULL,
    NULL, NULL, b.target_type, b.target_id, b.created_at,
    b.bookmark_id, b.user_id, b.note, b.deleted_at,
    NULL, NULL, NULL, NULL,
    NULL, NULL,
    NULL, NULL, NULL
FROM public.bookmarks b
WHERE b.user_id = p_viewer_user_id
    AND b.target_type = p_engagement_target_type
    AND b.target_id = p_thread_id
UNION ALL
-- api.notification_find_subscription_v1
SELECT 'subscription', row_number() OVER (), NULL, NULL, NULL,
    NULL, NULL, NULL,
    NULL, NULL, NULL, NULL,
    NULL, NULL, s.target_type, s.target_id, s.created_at,
    NULL, s.user_id, NULL, NULL,
    s.subscription_id, s.preference, s.muted_at, s.revoked_at,
    NULL, NULL,
    NULL, NULL, NULL
FROM public.subscriptions s
WHERE s.user_id = p_viewer_user_id
    AND s.target_type = p_engagement_target_type
    AND s.target_id = p_thread_id
UNION ALL
-- api.forum_read_state_v1
SELECT 'read_state', row_number() OVER (), NULL, NULL, NULL,
    NULL, NULL, NULL,
    rs.thread_id, NULL, NULL, NULL,
    NULL, NULL, NULL, NULL, NULL,
    NULL, rs.user_id, NULL, NULL,
    NULL, NULL, NULL, NULL,
    rs.last_read_position, rs.last_read_at,
    NULL, NULL, NULL
FROM public.thread_read_state rs
WHERE rs.user_id = p_viewer_user_id
    AND rs.thread_id = p_thread_id
UNION ALL
-- api.community_post_reactions_v1 (migration 133)
SELECT 'reaction', row_number() OVER (), x.post_id, NULL, NULL,
    NULL, NULL, NULL,
    NULL, NULL, NULL, NULL,
    NULL, NULL, NULL, NULL, NULL,
    NULL, NULL, NULL, NULL,
    NULL, NULL, NULL, NULL,
    NULL, NULL,
    x.reaction, x.reaction_count, x.reacted
FROM (
    SELECT pr.post_id, pr.reaction, count(*)::bigint AS reaction_count,
        coalesce(bool_or(pr.user_id = p_viewer_user_id), false) AS reacted
    FROM public.post_reactions pr
    WHERE pr.post_id = ANY(p_post_ids)
    GROUP BY pr.post_id, pr.reaction
) x
ORDER BY 1, 2
$$;
REVOKE EXECUTE ON FUNCTION api.forum_thread_page_reads_v3(uuid, uuid[], uuid, text, text, uuid[], integer)
    FROM PUBLIC;

-- Where a thread stands: its category and space, and the visibility and state
-- of each.
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
REVOKE EXECUTE ON FUNCTION api.forum_thread_placement_v1(uuid) FROM PUBLIC;

-- Writes a thread or post command as one idempotent call (ADR 0126): the
-- command log, the store's write, its records, and, when a draft is published,
-- the draft.
CREATE FUNCTION api.forum_write_command_v3(
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
        SELECT result.stored::jsonb INTO written FROM api.forum_store_write_v1(p_store_type,p_command,p_record) result;
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
REVOKE EXECUTE ON FUNCTION api.forum_write_command_v3(jsonb, jsonb, text, jsonb, jsonb, uuid, bigint)
    FROM PUBLIC;

COMMIT;
