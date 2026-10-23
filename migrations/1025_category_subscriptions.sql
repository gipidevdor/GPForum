-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

BEGIN;
SET LOCAL lock_timeout = '1s';

CREATE FUNCTION api.core_product_open_v1(p_actor uuid, p_command uuid, p_action text, p_request jsonb)
RETURNS TABLE (outcome text, response jsonb, command_id text, payload jsonb)
LANGUAGE plpgsql
VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    IF p_command IS NULL OR p_action IS NULL OR p_request IS NULL THEN
        RAISE EXCEPTION 'command, action and request are required' USING ERRCODE = '22023';
    END IF;
    RETURN QUERY SELECT * FROM api.core_command_open_v1(jsonb_build_object(
        'actor_id', p_actor, 'command_id', api.core_uuid_v7_v1(),
        'command_correlation_id', p_command, 'command_at', clock_timestamp(),
        'command_type', p_action, 'idempotency_key', 'product:' || p_command::text,
        'request_hash', encode(sha256(convert_to(api.core_canonical_json_v1(
            jsonb_build_object('actor',p_actor,'action',p_action,'request',p_request)),
            'UTF8')), 'hex')));
END;
$$;
REVOKE EXECUTE ON FUNCTION api.core_product_open_v1(uuid, uuid, text, jsonb) FROM PUBLIC;

CREATE FUNCTION api.core_product_close_v1(p_command_id text, p_payload jsonb, p_answer jsonb)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    PERFORM api.core_command_close_v1(p_command_id, clock_timestamp()::text,
        p_payload, p_answer || jsonb_build_object('ok',p_answer->>'status' = 'ok'));
    RETURN p_answer || jsonb_build_object('ok',p_answer->>'status' = 'ok');
END;
$$;
REVOKE EXECUTE ON FUNCTION api.core_product_close_v1(text, jsonb, jsonb) FROM PUBLIC;

CREATE FUNCTION api.core_product_audit_v1(p_actor uuid, p_command uuid, p_action text, p_target uuid, p_kind text, p_metadata jsonb)
RETURNS void
LANGUAGE plpgsql
VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    PERFORM api.ops_record_audit_v1(jsonb_build_object(
        'action', p_action, 'actor_id', p_actor, 'audit_id', api.core_uuid_v7_v1(),
        'correlation_id',p_command,'created_at',clock_timestamp(),
        'metadata',p_metadata,'schema_version',1,'target_id',p_target,'target_type',p_kind),false);
END;
$$;
REVOKE EXECUTE ON FUNCTION api.core_product_audit_v1(uuid, uuid, text, uuid, text, jsonb) FROM PUBLIC;

CREATE FUNCTION api.core_product_staff_v1(p_actor uuid, p_resource text, p_action text)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT coalesce((SELECT p.allowed FROM api.admin_permission_allowed_v3(
    p_actor,p_resource,p_action,NULL,NULL) p),false)
    AND coalesce((SELECT m.ok = 1 FROM api.moderation_can_participate_v3(
        p_actor,statement_timestamp()) m),false)
    AND EXISTS(SELECT 1 FROM public.users u WHERE u.id = p_actor AND u.status = 'active')
$$;
REVOKE EXECUTE ON FUNCTION api.core_product_staff_v1(uuid, text, text) FROM PUBLIC;

CREATE FUNCTION api.notification_category_follow_v1(p_actor uuid, p_command uuid, p_category_id uuid, p_operation text)
RETURNS TABLE (result jsonb)
LANGUAGE plpgsql
VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE opened record; answer jsonb; now_at timestamptz := clock_timestamp();
BEGIN
    IF p_operation IS NULL OR p_operation NOT IN ('follow','mute','remove') THEN
        RETURN QUERY SELECT jsonb_build_object('status','invalid'); RETURN;
    END IF;
    PERFORM 1 FROM public.users u WHERE u.id = p_actor AND u.status = 'active' FOR SHARE;
    IF NOT FOUND THEN RETURN QUERY SELECT jsonb_build_object('status','forbidden'); RETURN; END IF;
    IF NOT EXISTS(SELECT 1 FROM public.categories c JOIN public.spaces s ON s.space_id = c.space_id
        WHERE c.category_id = p_category_id AND c.deleted_at IS NULL AND s.deleted_at IS NULL)
        OR NOT api.core_forum_draft_target_v1(p_actor,'thread',p_category_id,NULL) THEN
        RETURN QUERY SELECT jsonb_build_object('status','not_found'); RETURN;
    END IF;
    SELECT * INTO opened FROM api.core_product_open_v1(p_actor,p_command,
        'community.category_follow',jsonb_build_object('category',p_category_id,'operation',p_operation));
    IF opened.outcome <> 'opened' THEN
        RETURN QUERY SELECT coalesce(opened.response,jsonb_build_object('status','conflict')); RETURN;
    END IF;
    IF p_operation = 'follow' THEN
        INSERT INTO public.subscriptions (subscription_id,user_id,target_type,target_id,preference,created_at)
        VALUES (api.core_uuid_v7_v1(),p_actor,'category',p_category_id,'all',now_at)
        ON CONFLICT ON CONSTRAINT subscriptions_unique_target DO UPDATE SET revoked_at = NULL,muted_at = NULL,preference = 'all';
    ELSIF p_operation = 'mute' THEN
        UPDATE public.subscriptions s SET muted_at = coalesce(s.muted_at,now_at)
        WHERE s.user_id = p_actor AND s.target_type = 'category' AND s.target_id = p_category_id AND s.revoked_at IS NULL;
    ELSE
        UPDATE public.subscriptions s SET revoked_at = coalesce(s.revoked_at,now_at)
        WHERE s.user_id = p_actor AND s.target_type = 'category' AND s.target_id = p_category_id;
    END IF;
    PERFORM api.core_product_audit_v1(p_actor,p_command,'community.category_follow',p_category_id,'category',jsonb_build_object('operation',p_operation));
    answer := api.core_product_close_v1(opened.command_id,opened.payload,jsonb_build_object('status','ok'));
    RETURN QUERY SELECT answer;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.notification_category_follow_v1(uuid, uuid, uuid, text) FROM PUBLIC;

CREATE FUNCTION api.notification_category_follow_v2(p_actor uuid, p_command uuid, p_category_id uuid, p_operation text)
RETURNS TABLE (result jsonb)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.notification_category_follow_v1(p_actor, p_command, p_category_id, p_operation);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_category_follow_v2(uuid, uuid, uuid, text) FROM PUBLIC;

CREATE FUNCTION api.notification_subscribers_v3(p_target_type text, p_target_id uuid, p_notification_type text)
RETURNS TABLE (user_id uuid)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT d.user_id FROM api.notification_subscribers_v1(p_target_type,p_target_id,p_notification_type) d
UNION
SELECT s.user_id FROM public.threads t JOIN public.subscriptions s
    ON s.target_type = 'category' AND s.target_id = t.category_id
WHERE p_target_type = 'thread' AND t.thread_id = p_target_id
    AND s.revoked_at IS NULL AND s.muted_at IS NULL AND s.preference <> 'none'
    AND (s.preference = 'all' OR p_notification_type = 'mention')
    AND NOT EXISTS(SELECT 1 FROM public.subscriptions mute WHERE mute.user_id = s.user_id
        AND mute.target_type = 'thread' AND mute.target_id = p_target_id
        AND mute.revoked_at IS NULL AND mute.muted_at IS NOT NULL)
$$;
REVOKE EXECUTE ON FUNCTION api.notification_subscribers_v3(text, uuid, text) FROM PUBLIC;

CREATE FUNCTION api.notification_subscribers_v4(p_target_type text, p_target_id uuid, p_notification_type text)
RETURNS TABLE (user_id uuid)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.notification_subscribers_v3(p_target_type, p_target_id, p_notification_type);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_subscribers_v4(text, uuid, text) FROM PUBLIC;

COMMIT;
