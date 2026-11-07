-- SPDX-FileCopyrightText: 2026 GPForum Contributors
-- SPDX-License-Identifier: BSD-3-Clause

BEGIN;
SET LOCAL lock_timeout = '1s';

-- Author attachment changes share the content-write lock order: thread, post.
-- SHARE conflicts with a moderator's ordinary non-key UPDATE of locked_at.
CREATE FUNCTION api.attachment_post_write_guard_v1(p_post_id uuid, p_actor uuid)
RETURNS TABLE (refusal text)
LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE target_thread uuid; held_thread public.threads; held_post public.posts;
BEGIN
    SELECT p.thread_id INTO target_thread FROM public.posts p WHERE p.post_id = p_post_id;
    SELECT t.* INTO held_thread FROM public.threads t WHERE t.thread_id = target_thread FOR SHARE;
    IF NOT FOUND THEN RETURN QUERY SELECT 'post not found'::text; RETURN; END IF;
    SELECT p.* INTO held_post FROM public.posts p
        WHERE p.post_id = p_post_id AND p.thread_id = target_thread FOR SHARE;
    IF NOT FOUND OR held_post.deleted_at IS NOT NULL OR held_post.hidden_at IS NOT NULL
        OR held_post.moderation_state <> 'visible' OR held_thread.deleted_at IS NOT NULL
        OR held_thread.moderation_state NOT IN ('visible', 'locked') THEN
        RETURN QUERY SELECT 'post not found'::text; RETURN;
    END IF;
    IF held_post.author_user_id IS DISTINCT FROM p_actor THEN
        RETURN QUERY SELECT 'post author required'::text; RETURN;
    END IF;
    IF held_thread.locked_at IS NOT NULL THEN
        RETURN QUERY SELECT 'thread is locked'::text; RETURN;
    END IF;
    RETURN QUERY SELECT NULL::text;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.attachment_post_write_guard_v1(p_post_id uuid, p_actor uuid) FROM PUBLIC;

CREATE FUNCTION api.attachment_post_write_guard_v2(p_post_id uuid, p_actor uuid)
RETURNS TABLE (refusal text)
LANGUAGE sql SECURITY DEFINER VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$ SELECT * FROM api.attachment_post_write_guard_v1(p_post_id, p_actor); $$;
REVOKE EXECUTE ON FUNCTION api.attachment_post_write_guard_v2(p_post_id uuid, p_actor uuid) FROM PUBLIC;

-- Advisory class 2026110201 is reserved for an owner's upload allowance.
-- Hash collisions only serialize different owners; they cannot admit excess.
-- The caller holds this transaction through storage write and metadata insert.
CREATE FUNCTION api.attachment_upload_quota_v1(p_owner_user_id uuid, p_byte_size bigint,
    p_max_bytes bigint, p_max_pending integer)
RETURNS TABLE (refusal text)
LANGUAGE plpgsql VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE retained numeric; pending bigint;
BEGIN
    IF p_owner_user_id IS NULL OR p_byte_size IS NULL OR p_byte_size < 1
        OR p_max_bytes IS NULL OR p_max_bytes < 1 OR p_max_pending IS NULL OR p_max_pending < 1 THEN
        RETURN QUERY SELECT 'upload quota unavailable'::text; RETURN;
    END IF;
    PERFORM pg_advisory_xact_lock(2026110201, hashtext(p_owner_user_id::text));
    -- Soft deletion retains source bytes, so every row still consumes quota.
    SELECT coalesce(sum(a.byte_size), 0), count(*) FILTER (
        WHERE a.deleted_at IS NULL AND a.state <> 'deleted'
            AND (a.scan_status = 'pending' OR a.state = 'intent'
            OR EXISTS (SELECT 1 FROM public.attachment_content_reviews r
                WHERE r.attachment_id = a.attachment_id AND r.status = 'pending')))
        INTO retained, pending FROM public.attachments a WHERE a.owner_user_id = p_owner_user_id;
    IF retained + p_byte_size > p_max_bytes THEN
        RETURN QUERY SELECT 'attachment storage quota exceeded'::text; RETURN;
    END IF;
    IF pending >= p_max_pending THEN
        RETURN QUERY SELECT 'too many pending attachments'::text; RETURN;
    END IF;
    RETURN QUERY SELECT NULL::text;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.attachment_upload_quota_v1(p_owner_user_id uuid, p_byte_size bigint, p_max_bytes bigint, p_max_pending integer) FROM PUBLIC;

CREATE FUNCTION api.attachment_upload_quota_v2(p_owner_user_id uuid, p_byte_size bigint,
    p_max_bytes bigint, p_max_pending integer)
RETURNS TABLE (refusal text)
LANGUAGE sql SECURITY DEFINER VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$ SELECT * FROM api.attachment_upload_quota_v1(p_owner_user_id, p_byte_size, p_max_bytes, p_max_pending); $$;
REVOKE EXECUTE ON FUNCTION api.attachment_upload_quota_v2(p_owner_user_id uuid, p_byte_size bigint, p_max_bytes bigint, p_max_pending integer) FROM PUBLIC;

CREATE FUNCTION api.core_configuration_valid_v2(p_section text, p_key text, p_value jsonb)
RETURNS boolean LANGUAGE sql IMMUTABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$ SELECT api.core_configuration_valid_v1(p_section, p_key, p_value)
    OR (p_section = 'general' AND p_key IN (
        'GPFORUM_ATTACHMENT_OWNER_MAX_MIB', 'GPFORUM_ATTACHMENT_OWNER_MAX_PENDING')
        AND jsonb_typeof(p_value) = 'string' AND length(p_value #>> '{}') <= 2000); $$;
REVOKE EXECUTE ON FUNCTION api.core_configuration_valid_v2(p_section text, p_key text, p_value jsonb) FROM PUBLIC;

CREATE FUNCTION api.admin_configuration_change_v3(p_actor uuid,p_command uuid,p_expected bigint,
    p_section text,p_key text,p_operation text,p_value jsonb,p_request_hash text)
RETURNS TABLE(result jsonb) LANGUAGE plpgsql VOLATILE
SET search_path=pg_catalog,pg_temp
SET plan_cache_mode=force_generic_plan
AS $$
DECLARE opened record; held public.forum_configuration; answer jsonb; item record; items jsonb;
BEGIN
    IF p_section IS NULL OR p_section NOT IN ('plugins','general') OR p_key IS NULL
        OR p_operation IS NULL OR p_operation NOT IN ('set','reset') OR p_expected IS NULL OR p_expected<0
        OR p_request_hash IS NULL OR p_request_hash !~ '^[a-f0-9]{64}$' THEN
        RETURN QUERY SELECT jsonb_build_object('status','invalid'); RETURN;
    END IF;
    IF p_key='__all__' THEN
        IF p_operation<>'set' OR jsonb_typeof(p_value) IS DISTINCT FROM 'object'
            OR (SELECT count(*) FROM jsonb_object_keys(p_value))>34 THEN
            RETURN QUERY SELECT jsonb_build_object('status','invalid'); RETURN;
        END IF;
        items:=p_value;
    ELSE
        items:=jsonb_build_object(p_key,CASE WHEN p_operation='reset' THEN
            CASE WHEN p_section='plugins' THEN '{"enabled":false,"mode":"link"}'::jsonb ELSE '"v1.reset"'::jsonb END
            ELSE p_value END);
    END IF;
    FOR item IN SELECT key,value FROM jsonb_each(items) LOOP
        IF NOT coalesce(api.core_configuration_valid_v2(p_section,item.key,item.value),false) THEN
            RETURN QUERY SELECT jsonb_build_object('status','invalid'); RETURN;
        END IF;
    END LOOP;
    PERFORM 1 FROM public.users u WHERE u.id=p_actor AND u.status='active' AND u.deleted_at IS NULL FOR SHARE;
    IF NOT FOUND OR NOT api.core_product_staff_v1(p_actor,'admin_console','manage') THEN
        RETURN QUERY SELECT jsonb_build_object('status','forbidden'); RETURN;
    END IF;
    SELECT * INTO opened FROM api.core_product_open_v1(p_actor,p_command,'admin.configuration',
        jsonb_build_object('expected',p_expected,'section',p_section,'key',p_key,'operation',p_operation,'request_hash',p_request_hash));
    IF opened.outcome<>'opened' THEN
        RETURN QUERY SELECT coalesce(opened.response,jsonb_build_object('status','conflict')); RETURN;
    END IF;
    SELECT * INTO held FROM public.forum_configuration f WHERE f.singleton FOR UPDATE;
    IF held.revision<>p_expected THEN
        answer:=jsonb_build_object('status','conflict','revision',held.revision);
    ELSE
        UPDATE public.forum_configuration f SET settings=CASE
            WHEN p_operation='reset' THEN f.settings #- ARRAY[p_section,p_key]
            WHEN p_key='__all__' THEN jsonb_set(f.settings,ARRAY[p_section],p_value,true)
            ELSE jsonb_set(f.settings,ARRAY[p_section,p_key],p_value,true) END,
            revision=f.revision+1,updated_at=clock_timestamp() WHERE f.singleton;
        PERFORM api.core_product_audit_v1(p_actor,p_command,'admin.configuration',
            '00000000-0000-4000-8000-000000000001'::uuid,'configuration',
            jsonb_build_object('section',p_section,'key',p_key,'operation',p_operation));
        answer:=jsonb_build_object('status','ok','revision',held.revision+1);
    END IF;
    RETURN QUERY SELECT api.core_product_close_v1(opened.command_id,opened.payload,answer);
END;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_configuration_change_v3(p_actor uuid, p_command uuid, p_expected bigint, p_section text, p_key text, p_operation text, p_value jsonb, p_request_hash text) FROM PUBLIC;

CREATE FUNCTION api.admin_configuration_change_v4(p_actor uuid,p_command uuid,p_expected bigint,
    p_section text,p_key text,p_operation text,p_value jsonb,p_request_hash text)
RETURNS TABLE(result jsonb) LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$ SELECT * FROM api.admin_configuration_change_v3(p_actor,p_command,p_expected,p_section,p_key,p_operation,p_value,p_request_hash); $$;
REVOKE EXECUTE ON FUNCTION api.admin_configuration_change_v4(p_actor uuid, p_command uuid, p_expected bigint, p_section text, p_key text, p_operation text, p_value jsonb, p_request_hash text) FROM PUBLIC;

COMMIT;
