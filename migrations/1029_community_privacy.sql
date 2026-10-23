-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

BEGIN;
SET LOCAL lock_timeout = '1s';

CREATE FUNCTION api.privacy_revoke_user_v23(p_source text, p_user_id uuid, p_at text)
RETURNS TABLE (revoked bigint)
LANGUAGE plpgsql
VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE amount bigint;
BEGIN
    IF p_source = 'PollBallot' THEN
        PERFORM 1 FROM public.threads t WHERE t.thread_id IN(SELECT b.thread_id FROM public.poll_ballots b WHERE b.user_id = p_user_id)
            ORDER BY t.thread_id FOR UPDATE;
        PERFORM 1 FROM public.thread_polls p WHERE p.thread_id IN(SELECT b.thread_id FROM public.poll_ballots b WHERE b.user_id = p_user_id)
            ORDER BY p.thread_id FOR UPDATE;
        WITH removed AS (DELETE FROM public.poll_ballots b WHERE b.user_id = p_user_id RETURNING b.thread_id,b.option_number),
        counts AS (SELECT r.thread_id,r.option_number,count(*) AS n FROM removed r GROUP BY r.thread_id,r.option_number)
        UPDATE public.poll_options o SET votes = o.votes - c.n FROM counts c
            WHERE o.thread_id = c.thread_id AND o.option_number = c.option_number;
        GET DIAGNOSTICS amount = ROW_COUNT;
        UPDATE public.thread_polls SET created_by = NULL WHERE created_by = p_user_id;
        RETURN QUERY SELECT amount;
    ELSIF p_source = 'Admission' THEN
        DELETE FROM public.registration_invitations i WHERE i.created_by = p_user_id OR i.used_by = p_user_id;
        DELETE FROM public.registration_reviews r WHERE r.user_id = p_user_id;
        GET DIAGNOSTICS amount = ROW_COUNT;
        UPDATE public.registration_reviews SET decided_by = NULL WHERE decided_by = p_user_id;
        UPDATE public.registration_policy SET updated_by = NULL WHERE updated_by = p_user_id;
        UPDATE public.thread_transfers SET actor_id = NULL WHERE actor_id = p_user_id;
        RETURN QUERY SELECT amount;
    ELSE RETURN QUERY SELECT * FROM api.privacy_revoke_user_v21(p_source,p_user_id,p_at);
    END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.privacy_revoke_user_v23(text, uuid, text) FROM PUBLIC;

CREATE FUNCTION api.privacy_revoke_user_v24(p_source text, p_user_id uuid, p_at text)
RETURNS TABLE (revoked bigint)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.privacy_revoke_user_v23(p_source, p_user_id, p_at);
$$;
REVOKE EXECUTE ON FUNCTION api.privacy_revoke_user_v24(text, uuid, text) FROM PUBLIC;

CREATE FUNCTION api.portability_export_parts_v23(p_user_id uuid)
RETURNS TABLE (document json)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT (previous.document::jsonb || jsonb_build_object(
    'poll_ballots',coalesce((SELECT jsonb_agg(jsonb_build_object('thread_id',b.thread_id,
        'option_number',b.option_number,'updated_at',b.updated_at) ORDER BY b.thread_id)
        FROM public.poll_ballots b WHERE b.user_id = p_user_id),'[]'::jsonb),
    'admission',(SELECT jsonb_build_object('decision',r.decision,'created_at',r.created_at,'decided_at',r.decided_at)
        FROM public.registration_reviews r WHERE r.user_id = p_user_id)))::json
FROM api.portability_export_parts_v21(p_user_id) previous
$$;
REVOKE EXECUTE ON FUNCTION api.portability_export_parts_v23(uuid) FROM PUBLIC;

CREATE FUNCTION api.portability_export_parts_v24(p_user_id uuid)
RETURNS TABLE (document json)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.portability_export_parts_v23(p_user_id);
$$;
REVOKE EXECUTE ON FUNCTION api.portability_export_parts_v24(uuid) FROM PUBLIC;

CREATE FUNCTION api.ops_retention_purge_v3(p_source text, p_cutoff timestamptz, p_row_limit integer)
RETURNS TABLE (deleted bigint, ok integer)
LANGUAGE plpgsql
VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE previous record; invitations bigint := 0;
BEGIN
    SELECT * INTO previous FROM api.ops_retention_purge_v1(p_source,p_cutoff,p_row_limit);
    IF p_source = 'IdentityToken' AND previous.deleted < p_row_limit THEN
        WITH picked AS (SELECT i.invitation_id FROM public.registration_invitations i WHERE i.expires_at <= p_cutoff
            ORDER BY i.expires_at,i.invitation_id LIMIT greatest(p_row_limit-previous.deleted,0) FOR UPDATE SKIP LOCKED),
        removed AS (DELETE FROM public.registration_invitations i USING picked x WHERE i.invitation_id = x.invitation_id RETURNING 1)
        SELECT count(*) INTO invitations FROM removed;
    END IF;
    RETURN QUERY SELECT previous.deleted+invitations,previous.ok;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.ops_retention_purge_v3(text, timestamptz, integer) FROM PUBLIC;

CREATE FUNCTION api.ops_retention_purge_v4(p_source text, p_cutoff timestamptz, p_row_limit integer)
RETURNS TABLE (deleted bigint, ok integer)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.ops_retention_purge_v3(p_source, p_cutoff, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.ops_retention_purge_v4(text, timestamptz, integer) FROM PUBLIC;

COMMIT;
