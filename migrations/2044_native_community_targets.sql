-- SPDX-FileCopyrightText: 2026 GPForum Contributors
-- SPDX-License-Identifier: BSD-3-Clause

BEGIN;
SET LOCAL lock_timeout = '1s';

-- The same command-log transaction and existing target stores in one round trip.
-- Columns and operations are fixed here, never supplied as SQL by the caller.
CREATE FUNCTION api.community_target_command_v1(
    p_log jsonb, p_answer jsonb, p_row jsonb
)
RETURNS TABLE (outcome text, response json)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE
    opened record;
    answer jsonb := p_answer;
    saved jsonb;
    stored jsonb;
    operation text := p_log ->> 'command_type';
    fields text[];
    noun text;
BEGIN
    IF operation IS NULL OR operation NOT IN
        ('community.bookmark_remove', 'community.subscription_mute', 'community.unsubscribe')
    THEN
        RAISE EXCEPTION 'invalid community target command' USING ERRCODE = '22023';
    END IF;
    IF (p_row ->> 'user_id')::uuid IS DISTINCT FROM (p_log ->> 'actor_id')::uuid THEN
        RAISE EXCEPTION 'community target actor mismatch' USING ERRCODE = '22023';
    END IF;
    SELECT * INTO opened FROM api.core_command_open_v1(p_log);
    IF opened.outcome <> 'opened' THEN
        RETURN QUERY SELECT opened.outcome, opened.response::json;
        RETURN;
    END IF;
    IF answer IS NULL THEN
        IF operation = 'community.bookmark_remove' THEN
            SELECT s.result INTO saved FROM api.community_stamp_bookmark_v3(
                (p_row ->> 'user_id')::uuid, p_row ->> 'target_type',
                (p_row ->> 'target_id')::uuid, 'deleted_at', p_row ->> 'stamped_at'
            ) s;
            fields := ARRAY['bookmark_id','created_at','deleted_at','note','ok',
                'target_id','target_type','user_id'];
            noun := 'bookmark';
        ELSE
            SELECT s.result INTO saved FROM api.notification_stamp_subscription_v1(
                NULL, true, (p_row ->> 'user_id')::uuid, p_row ->> 'target_type',
                (p_row ->> 'target_id')::uuid,
                CASE WHEN operation = 'community.subscription_mute'
                    THEN 'muted_at' ELSE 'revoked_at' END,
                p_row ->> 'stamped_at'
            ) s;
            fields := ARRAY['created_at','muted_at','ok','preference','revoked_at',
                'subscription_id','target_id','target_type','user_id'];
            noun := 'subscription';
        END IF;
        IF saved IS NULL OR NOT api.core_perl_true_v1(saved ->> 'ok') THEN
            answer := jsonb_build_object('error',coalesce(nullif(saved ->> 'error',''),
                noun || ' not found'),'errors',NULL,'ok',0,'status','not_found','stored',NULL);
        ELSE
            SELECT jsonb_object_agg(f.name, saved -> f.name) INTO stored
            FROM unnest(fields) f(name);
            answer := jsonb_build_object('error',NULL,'errors',NULL,
                'ok',1,'status','ok','stored',stored);
        END IF;
    END IF;
    PERFORM api.core_command_close_v1(opened.command_id,
        p_log ->> 'command_at', opened.payload, answer);
    RETURN QUERY SELECT 'recorded'::text, answer::json;
END
$$;
REVOKE EXECUTE ON FUNCTION api.community_target_command_v1(jsonb,jsonb,jsonb) FROM PUBLIC;

CREATE FUNCTION api.community_target_command_v2(
    p_log jsonb, p_answer jsonb, p_row jsonb
)
RETURNS TABLE (outcome text, response json)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_target_command_v1(p_log,p_answer,p_row);
$$;
REVOKE EXECUTE ON FUNCTION api.community_target_command_v2(jsonb,jsonb,jsonb) FROM PUBLIC;

COMMIT;
