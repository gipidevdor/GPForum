-- SPDX-FileCopyrightText: 2026 GPForum Contributors
-- SPDX-License-Identifier: BSD-3-Clause

BEGIN;
SET LOCAL lock_timeout = '1s';

-- Published 2045 stays immutable. Guest reads omit unchanged settings; the
-- next member entry point uses that same fresh revision and privacy epoch.

CREATE FUNCTION api.admin_configuration_snapshot_v1(p_known_revision bigint)
RETURNS TABLE (revision bigint, public_cache_epoch bigint, settings jsonb)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT f.revision, e.epoch,
    CASE WHEN p_known_revision IS DISTINCT FROM f.revision THEN f.settings ELSE NULL END
FROM public.forum_configuration f CROSS JOIN public.public_cache_state e
WHERE f.singleton AND e.singleton;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_configuration_snapshot_v1(bigint) FROM PUBLIC;

CREATE FUNCTION api.admin_configuration_snapshot_v2(p_known_revision bigint)
RETURNS TABLE (revision bigint, public_cache_epoch bigint, settings jsonb)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_configuration_snapshot_v1(p_known_revision);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_configuration_snapshot_v2(bigint) FROM PUBLIC;

-- One statement owns the fresh configuration revision, public-cache epoch,
-- durable session validation and viewer. Only encrypted saved settings may
-- be omitted when this worker already holds that exact revision.

CREATE FUNCTION api.admin_request_context_v3(
    p_known_revision bigint,
    p_session_id uuid,
    p_user_id uuid,
    p_token_hash text,
    p_now timestamptz,
    p_touch_interval_seconds integer,
    p_resolve_viewer boolean
)
RETURNS TABLE (
    revision bigint, public_cache_epoch bigint, settings jsonb,
    validation jsonb, viewer jsonb
)
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE
    configuration record;
    checked record;
BEGIN
    SELECT * INTO STRICT configuration FROM api.admin_configuration_snapshot_v1(p_known_revision);
    revision := configuration.revision;
    public_cache_epoch := configuration.public_cache_epoch;
    settings := configuration.settings;

    IF p_session_id IS NOT NULL AND p_user_id IS NOT NULL THEN
        SELECT * INTO checked FROM api.session_validate_v1(
            p_session_id, p_user_id, p_token_hash, p_now,
            p_touch_interval_seconds
        );
        validation := jsonb_build_object('ok',
            CASE WHEN checked.result_code = 'ok' THEN 1 ELSE 0 END,
            'error', coalesce(checked.result_code, 'not_found'));
        IF checked.result_code IS DISTINCT FROM 'ok' THEN
            RETURN NEXT;
            RETURN;
        END IF;
    END IF;
    IF p_resolve_viewer AND p_user_id IS NOT NULL THEN
        SELECT to_jsonb(v) INTO viewer FROM api.forum_resolve_viewer_v9(p_user_id) v;
    END IF;
    RETURN NEXT;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.admin_request_context_v3(
    bigint,uuid,uuid,text,timestamptz,integer,boolean) FROM PUBLIC;

CREATE FUNCTION api.admin_request_context_v4(
    p_known_revision bigint,
    p_session_id uuid,
    p_user_id uuid,
    p_token_hash text,
    p_now timestamptz,
    p_touch_interval_seconds integer,
    p_resolve_viewer boolean
)
RETURNS TABLE (
    revision bigint, public_cache_epoch bigint, settings jsonb,
    validation jsonb, viewer jsonb
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.admin_request_context_v3(
    p_known_revision,p_session_id,p_user_id,p_token_hash,p_now,
    p_touch_interval_seconds,p_resolve_viewer);
$$;
REVOKE EXECUTE ON FUNCTION api.admin_request_context_v4(
    bigint,uuid,uuid,text,timestamptz,integer,boolean) FROM PUBLIC;

COMMIT;
