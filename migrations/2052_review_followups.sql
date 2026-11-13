-- SPDX-FileCopyrightText: 2026 GPForum Contributors
-- SPDX-License-Identifier: BSD-3-Clause
BEGIN;
SET LOCAL lock_timeout = '3s';

-- Mark all read covers what the badge counts. The badge and the inbox
-- (notification_unread_count_v7, notification_list_inbox_v7) count a direct
-- message's notification while the member is in the conversation; marking
-- all read knew threads and posts only, so the DM notifications stayed
-- unread and the badge above zero after "mark all read". One statement
-- marks them all: the row-by-row loop called core_notification_read_v1 once
-- per notification. A notification read before keeps its first read time.
CREATE FUNCTION api.notification_mark_all_read_v3(
    p_user_id uuid,
    p_filter_sources boolean,
    p_member boolean,
    p_global_read boolean,
    p_viewer_user_id uuid,
    p_category_ids uuid[],
    p_space_ids uuid[],
    p_read_at text
)
RETURNS TABLE (result jsonb)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_custom_plan
AS $$
DECLARE v_count bigint;
BEGIN
  WITH picked AS (
    SELECT i.notification_id FROM public.notification_inbox i JOIN public.notifications n ON n.notification_id = i.notification_id AND n.created_at = i.created_at
    WHERE i.recipient_user_id = p_user_id AND i.read_at IS NULL AND (NOT p_filter_sources OR ((n.source_type = 'message' AND EXISTS (SELECT 1 FROM public.direct_messages dm JOIN public.direct_conversation_members dmm ON dmm.conversation_id = dm.conversation_id AND dmm.user_id = p_user_id WHERE dm.message_id = n.source_id)) OR (n.source_type = 'thread' AND EXISTS (SELECT 1 FROM public.threads t JOIN public.categories c ON c.category_id = t.category_id JOIN public.spaces s ON s.space_id = c.space_id WHERE t.thread_id = n.source_id AND t.deleted_at IS NULL AND t.moderation_state IN ('visible', 'locked') AND c.deleted_at IS NULL AND (s.visibility IN ('public', 'members', 'private') AND (p_global_read OR s.visibility = 'public' OR (p_member AND s.visibility = 'members') OR (s.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (c.visibility IN ('public', 'members', 'private') AND (p_global_read OR c.visibility = 'public' OR (p_member AND c.visibility = 'members') OR (c.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (t.visibility IN ('public', 'members', 'private') AND (p_global_read OR t.visibility = 'public' OR (p_member AND t.visibility = 'members') OR (t.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (t.author_user_id = p_viewer_user_id)))))))) OR (n.source_type = 'post' AND EXISTS (SELECT 1 FROM public.posts p JOIN public.threads t ON t.thread_id = p.thread_id JOIN public.categories c ON c.category_id = t.category_id JOIN public.spaces s ON s.space_id = c.space_id WHERE p.post_id = n.source_id AND p.deleted_at IS NULL AND p.moderation_state = 'visible' AND t.deleted_at IS NULL AND t.moderation_state IN ('visible', 'locked') AND c.deleted_at IS NULL AND (s.visibility IN ('public', 'members', 'private') AND (p_global_read OR s.visibility = 'public' OR (p_member AND s.visibility = 'members') OR (s.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (c.visibility IN ('public', 'members', 'private') AND (p_global_read OR c.visibility = 'public' OR (p_member AND c.visibility = 'members') OR (c.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (false)))))) AND (t.visibility IN ('public', 'members', 'private') AND (p_global_read OR t.visibility = 'public' OR (p_member AND t.visibility = 'members') OR (t.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (t.author_user_id = p_viewer_user_id)))))) AND (p.visibility IN ('public', 'members', 'private') AND (p_global_read OR p.visibility = 'public' OR (p_member AND p.visibility = 'members') OR (p.visibility = 'private' AND ((c.category_id = ANY(p_category_ids) OR c.space_id = ANY(p_space_ids)) OR (p_member AND (p.author_user_id = p_viewer_user_id OR (t.visibility = 'private' AND t.author_user_id = p_viewer_user_id))))))))))) FOR UPDATE OF i
  ), recorded AS (
    INSERT INTO public.notification_reads (notification_id, recipient_user_id, read_at)
    SELECT p.notification_id, p_user_id, p_read_at::timestamptz FROM picked p
    ON CONFLICT (notification_id, recipient_user_id) DO NOTHING
  ), marked AS (
    UPDATE public.notification_inbox i
    SET read_at = coalesce((SELECT r.read_at FROM public.notification_reads r
        WHERE r.notification_id = i.notification_id AND r.recipient_user_id = p_user_id), p_read_at::timestamptz)
    FROM picked p
    WHERE i.notification_id = p.notification_id AND i.recipient_user_id = p_user_id
    RETURNING 1
  )
  SELECT count(*) INTO v_count FROM marked;
  RETURN QUERY SELECT jsonb_build_object('ok', 1, 'duplicate', CASE WHEN v_count = 0 THEN 1 ELSE 0 END, 'marked_count', v_count, 'read_at', p_read_at, 'recipient_user_id', p_user_id);
END;
$$;
REVOKE EXECUTE ON FUNCTION api.notification_mark_all_read_v3(p_user_id uuid, p_filter_sources boolean, p_member boolean, p_global_read boolean, p_viewer_user_id uuid, p_category_ids uuid[], p_space_ids uuid[], p_read_at text) FROM PUBLIC;

CREATE FUNCTION api.notification_mark_all_read_v4(
    p_user_id uuid,
    p_filter_sources boolean,
    p_member boolean,
    p_global_read boolean,
    p_viewer_user_id uuid,
    p_category_ids uuid[],
    p_space_ids uuid[],
    p_read_at text
)
RETURNS TABLE (result jsonb)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.notification_mark_all_read_v3(p_user_id, p_filter_sources, p_member, p_global_read, p_viewer_user_id, p_category_ids, p_space_ids, p_read_at);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_mark_all_read_v4(p_user_id uuid, p_filter_sources boolean, p_member boolean, p_global_read boolean, p_viewer_user_id uuid, p_category_ids uuid[], p_space_ids uuid[], p_read_at text) FROM PUBLIC;

-- Handler claims leave the table. Every outbox event writes one key per
-- handler and one for realtime, and nothing deleted a completed one: the
-- table and its primary key grew by several rows per post for good. A
-- completed key goes once a replay can no longer need it, the dead-letter
-- retention and a margin after it completed (RetentionStore). An open claim
-- stays: it is what keeps a second worker off the side effect. Its index is
-- built by 2053, concurrently.
CREATE FUNCTION api.ops_retention_purge_v5(p_source text, p_cutoff timestamptz, p_row_limit integer)
RETURNS TABLE (deleted bigint, ok integer)
LANGUAGE plpgsql
VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    IF p_source = 'EventIdempotencyKey' THEN
        RETURN QUERY WITH picked AS (
            SELECT k.idempotency_key FROM public.event_idempotency_keys k
            WHERE k.completed_at IS NOT NULL AND k.completed_at <= p_cutoff
            ORDER BY k.completed_at LIMIT p_row_limit FOR UPDATE SKIP LOCKED
        ), removed AS (
            DELETE FROM public.event_idempotency_keys k USING picked x
            WHERE k.idempotency_key = x.idempotency_key RETURNING 1
        ) SELECT count(*), 1 FROM removed;
        RETURN;
    END IF;
    RETURN QUERY SELECT * FROM api.ops_retention_purge_v3(p_source, p_cutoff, p_row_limit);
END;
$$;
REVOKE EXECUTE ON FUNCTION api.ops_retention_purge_v5(p_source text, p_cutoff timestamp with time zone, p_row_limit integer) FROM PUBLIC;

CREATE FUNCTION api.ops_retention_purge_v6(p_source text, p_cutoff timestamptz, p_row_limit integer)
RETURNS TABLE (deleted bigint, ok integer)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.ops_retention_purge_v5(p_source, p_cutoff, p_row_limit);
$$;
REVOKE EXECUTE ON FUNCTION api.ops_retention_purge_v6(p_source text, p_cutoff timestamp with time zone, p_row_limit integer) FROM PUBLIC;

-- Erasure removes the sign-in pathways bound to the account. The account is
-- anonymised, not deleted, so ON DELETE CASCADE never fired: the external
-- issuer and subject of an OIDC link, and the passkeys with the label the
-- member typed, their public keys and the opaque user handle, stayed tied to
-- the erased account. They go with the credentials they belong to.
CREATE FUNCTION api.privacy_revoke_user_v33(p_source text,p_user_id uuid,p_at text)
RETURNS TABLE(revoked bigint) LANGUAGE plpgsql VOLATILE
SET search_path=pg_catalog,pg_temp
SET plan_cache_mode=force_generic_plan
AS $$
DECLARE v_revoked bigint; v_links bigint := 0; v_keys bigint := 0;
BEGIN
    SELECT r.revoked INTO v_revoked FROM api.privacy_revoke_user_v31(p_source,p_user_id,p_at) r;
    IF p_source='Credential' THEN
        DELETE FROM public.oidc_account_links l WHERE l.user_id=p_user_id;
        GET DIAGNOSTICS v_links = ROW_COUNT;
        DELETE FROM public.passkeys k WHERE k.user_id=p_user_id;
        GET DIAGNOSTICS v_keys = ROW_COUNT;
        DELETE FROM public.passkey_accounts a WHERE a.user_id=p_user_id;
    END IF;
    RETURN QUERY SELECT coalesce(v_revoked,0)+v_links+v_keys;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.privacy_revoke_user_v33(p_source text, p_user_id uuid, p_at text) FROM PUBLIC;

CREATE FUNCTION api.privacy_revoke_user_v34(p_source text,p_user_id uuid,p_at text)
RETURNS TABLE(revoked bigint) LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,pg_temp
SET plan_cache_mode=force_generic_plan
AS $$ SELECT * FROM api.privacy_revoke_user_v33(p_source,p_user_id,p_at); $$;
REVOKE EXECUTE ON FUNCTION api.privacy_revoke_user_v34(p_source text, p_user_id uuid, p_at text) FROM PUBLIC;
-- Nothing has shipped (ADR 0150): the versions these replace go, so that
-- every function in api is one the catalogue reaches.
DROP FUNCTION api.notification_mark_all_read_v2(p_user_id uuid, p_filter_sources boolean, p_member boolean, p_global_read boolean, p_viewer_user_id uuid, p_category_ids uuid[], p_space_ids uuid[], p_read_at text);
DROP FUNCTION api.notification_mark_all_read_v1(p_user_id uuid, p_filter_sources boolean, p_member boolean, p_global_read boolean, p_viewer_user_id uuid, p_category_ids uuid[], p_space_ids uuid[], p_read_at text);
DROP FUNCTION api.ops_retention_purge_v4(p_source text, p_cutoff timestamptz, p_row_limit integer);
DROP FUNCTION api.privacy_revoke_user_v32(p_source text, p_user_id uuid, p_at text);
COMMIT;
