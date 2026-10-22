-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

-- Data rights: deletion and erasure, revoking a member's rows, exports and
-- retention holds.

BEGIN;
SET LOCAL lock_timeout = '1s';

-- The parts of a member's export: their profile, uploads, notifications,
-- subscriptions, preferences and posts.
CREATE FUNCTION api.portability_export_parts_v1(p_user_id uuid)
RETURNS TABLE (document json)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT jsonb_build_object(
'profile',(SELECT COALESCE(jsonb_build_object('created_at',u.created_at::text,'display_name',u.display_name,'email',u.email_normalized,'email_verified_at',u.email_verified_at::text,'preferred_locale',u.preferred_locale,'preferred_theme',u.preferred_theme,'preferred_timezone',u.preferred_timezone,'status',u.status,'user_id',u.id,'username',u.username),'{}'::jsonb) FROM public.users u WHERE u.id=p_user_id),
'attachments',(SELECT COALESCE(jsonb_agg(jsonb_build_object('attachment_id',r.attachment_id,'original_filename',r.original_filename,'media_type',r.media_type,'byte_size',r.byte_size,'checksum',r.checksum,'state',r.state,'scan_status',r.scan_status,'created_at',r.created_at::text,'uploaded_at',r.uploaded_at::text,'deleted_at',r.deleted_at::text)),'[]'::jsonb) FROM public.attachments r WHERE r.owner_user_id=p_user_id),
'notifications',(SELECT COALESCE(jsonb_agg(jsonb_build_object('notification_id',r.notification_id,'created_at',r.created_at::text,'read_at',r.read_at::text)),'[]'::jsonb) FROM public.notification_inbox r WHERE r.recipient_user_id=p_user_id),
'subscriptions',(SELECT COALESCE(jsonb_agg(jsonb_build_object('subscription_id',r.subscription_id,'target_type',r.target_type,'target_id',r.target_id,'preference',r.preference,'created_at',r.created_at::text,'muted_at',r.muted_at::text,'revoked_at',r.revoked_at::text)),'[]'::jsonb) FROM public.subscriptions r WHERE r.user_id=p_user_id),
'preferences',(SELECT COALESCE(jsonb_agg(jsonb_build_object('channel',r.channel,'enabled',r.enabled::integer,'digest_frequency',r.digest_frequency,'updated_at',r.updated_at::text)),'[]'::jsonb) FROM public.notification_preferences r WHERE r.user_id=p_user_id),
'posts',(SELECT COALESCE(jsonb_agg(jsonb_build_object('post_id',p.post_id,'thread_id',p.thread_id,'visibility',p.visibility,'moderation_state',p.moderation_state,'position',p.position,'created_at',p.created_at::text,'updated_at',p.updated_at::text,'deleted_at',p.deleted_at::text,'body_format',b.body_format,'body_source',b.body_source)),'[]'::jsonb) FROM public.posts p LEFT JOIN public.post_bodies b USING(post_id) WHERE p.author_user_id=p_user_id))::json;
$$;
REVOKE EXECUTE ON FUNCTION api.portability_export_parts_v1(uuid) FROM PUBLIC;

-- The parts of portability_export_parts_v1, and the member's drafts.
CREATE FUNCTION api.portability_export_parts_v3(p_user_id uuid)
RETURNS TABLE (document json)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT (previous.document::jsonb || jsonb_build_object('drafts',
    (SELECT coalesce(jsonb_agg(to_jsonb(d) - 'save_base_revision' - 'save_command_id'),'[]'::jsonb)
        FROM public.forum_drafts d WHERE d.owner_user_id=p_user_id AND d.expires_at>now())))::json
FROM api.portability_export_parts_v1(p_user_id) previous;
$$;
REVOKE EXECUTE ON FUNCTION api.portability_export_parts_v3(uuid) FROM PUBLIC;

-- A member's export lists the posts they liked and when.
CREATE FUNCTION api.portability_export_parts_v5(p_user_id uuid)
RETURNS TABLE (document json)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT (previous.document::jsonb || jsonb_build_object('likes',
    (SELECT coalesce(jsonb_agg(jsonb_build_object('post_id', l.post_id,
        'created_at', l.created_at) ORDER BY l.created_at, l.post_id),
        '[]'::jsonb)
    FROM public.post_likes l WHERE l.user_id = p_user_id)))::json
FROM api.portability_export_parts_v3(p_user_id) previous
$$;
REVOKE EXECUTE ON FUNCTION api.portability_export_parts_v5(uuid) FROM PUBLIC;

-- A member's export carries their bio under profile.
CREATE FUNCTION api.portability_export_parts_v7(p_user_id uuid)
RETURNS TABLE (document json)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT jsonb_set(previous.document::jsonb, '{profile,bio}',
    to_jsonb(coalesce((SELECT u.bio FROM public.users u
        WHERE u.id = p_user_id), '')), true)::json
FROM api.portability_export_parts_v5(p_user_id) previous
$$;
REVOKE EXECUTE ON FUNCTION api.portability_export_parts_v7(uuid) FROM PUBLIC;

-- The export: the owner's own list, never who listed them.
CREATE FUNCTION api.portability_export_parts_v9(p_user_id uuid)
RETURNS TABLE (document json)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT (previous.document::jsonb || jsonb_build_object('member_relations',
    (SELECT coalesce(jsonb_agg(jsonb_build_object('username', u.username,
        'kind', r.kind, 'created_at', r.created_at,
        'updated_at', r.updated_at) ORDER BY r.created_at, u.username),
        '[]'::jsonb)
     FROM public.member_relations r
     JOIN public.users u ON u.id = r.other_user_id
     WHERE r.owner_user_id = p_user_id)))::json
FROM api.portability_export_parts_v7(p_user_id) previous;
$$;
REVOKE EXECUTE ON FUNCTION api.portability_export_parts_v9(uuid) FROM PUBLIC;

-- The export: the member's own held posts, as written, with their
-- decisions; never who decided.
CREATE FUNCTION api.portability_export_parts_v11(p_user_id uuid)
RETURNS TABLE (document json)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT (previous.document::jsonb || jsonb_build_object('held_posts',
    (SELECT coalesce(jsonb_agg(jsonb_build_object('kind', h.kind,
        'category_id', h.category_id, 'thread_id', h.thread_id,
        'title', h.title, 'body_source', h.body_source,
        'status', h.status, 'decision_reason', h.decision_reason,
        'post_id', h.post_id, 'created_at', h.created_at,
        'decided_at', h.decided_at) ORDER BY h.created_at, h.review_id),
        '[]'::jsonb)
     FROM public.held_posts h
     WHERE h.author_user_id = p_user_id)))::json
FROM api.portability_export_parts_v9(p_user_id) previous;
$$;
REVOKE EXECUTE ON FUNCTION api.portability_export_parts_v11(uuid) FROM PUBLIC;

-- The export: the member's own choices for each kind of notification.
CREATE FUNCTION api.portability_export_parts_v13(p_user_id uuid)
RETURNS TABLE (document json)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT (previous.document::jsonb || jsonb_build_object(
    'notification_type_preferences',
    (SELECT coalesce(jsonb_agg(jsonb_build_object('event_type', p.event_type,
        'channel', p.channel, 'enabled', p.enabled,
        'updated_at', p.updated_at)
        ORDER BY p.event_type, p.channel), '[]'::jsonb)
     FROM public.notification_type_preferences p
     WHERE p.user_id = p_user_id)))::json
FROM api.portability_export_parts_v11(p_user_id) previous;
$$;
REVOKE EXECUTE ON FUNCTION api.portability_export_parts_v13(uuid) FROM PUBLIC;

-- The export: the member's conversations, with whom, and the messages
-- they wrote; never the other member's messages (ADR 0074).
CREATE FUNCTION api.portability_export_parts_v15(p_user_id uuid)
RETURNS TABLE (document json)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT (previous.document::jsonb || jsonb_build_object(
    'direct_messages',
    (SELECT coalesce(jsonb_agg(jsonb_build_object(
        'conversation_id', m.conversation_id,
        'with_username', u.username,
        'started_at', c.created_at,
        'messages', (SELECT coalesce(jsonb_agg(jsonb_build_object(
                'message_id', d.message_id, 'body', d.body,
                'created_at', d.created_at)
                ORDER BY d.position), '[]'::jsonb)
            FROM public.direct_messages d
            WHERE d.conversation_id = m.conversation_id
                AND d.author_user_id = p_user_id))
        ORDER BY c.created_at, m.conversation_id), '[]'::jsonb)
     FROM public.direct_conversation_members m
     JOIN public.direct_conversations c
        ON c.conversation_id = m.conversation_id
     JOIN public.users u ON u.id = m.other_user_id
     WHERE m.user_id = p_user_id)))::json
FROM api.portability_export_parts_v13(p_user_id) previous;
$$;
REVOKE EXECUTE ON FUNCTION api.portability_export_parts_v15(uuid) FROM PUBLIC;

-- The export says whether two-step sign-in is on, since when, and how many
-- recovery codes are left; never the secret or the codes' hashes.
CREATE FUNCTION api.portability_export_parts_v17(p_user_id uuid)
RETURNS TABLE (document json)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT (previous.document::jsonb || jsonb_build_object(
    'second_factor', (SELECT jsonb_build_object(
        'state', coalesce(f.state, 'off'),
        'confirmed_at', f.confirmed_at,
        'recovery_codes_left', (SELECT count(*)
            FROM public.second_factor_recovery_codes c
            WHERE c.user_id = p_user_id AND c.used_at IS NULL
                AND f.state = 'active'))
        FROM (SELECT p_user_id AS user_id) me
        LEFT JOIN public.second_factors f ON f.user_id = me.user_id)))::json
FROM api.portability_export_parts_v15(p_user_id) previous;
$$;
REVOKE EXECUTE ON FUNCTION api.portability_export_parts_v17(uuid) FROM PUBLIC;

-- The export says whether the member shows a picture, since when, and
-- whether one is waiting; the upload itself is among their attachments.
CREATE FUNCTION api.portability_export_parts_v19(p_user_id uuid)
RETURNS TABLE (document json)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT (previous.document::jsonb || jsonb_build_object(
    'avatar', (SELECT jsonb_build_object(
        'attachment_id', s.attachment_id,
        'shown_at', s.shown_at,
        'pending_attachment_id', s.pending_attachment_id,
        'pending_state', s.pending_state)
        FROM (SELECT p_user_id AS user_id) me
        LEFT JOIN api.community_avatar_status_v1(p_user_id) s ON true)))::json
FROM api.portability_export_parts_v17(p_user_id) previous;
$$;
REVOKE EXECUTE ON FUNCTION api.portability_export_parts_v19(uuid) FROM PUBLIC;

-- The export lists the member's reactions, post by post, with the rest.
CREATE FUNCTION api.portability_export_parts_v21(p_user_id uuid)
RETURNS TABLE (document json)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT (previous.document::jsonb || jsonb_build_object('reactions',
    (SELECT coalesce(jsonb_agg(jsonb_build_object('post_id', r.post_id,
        'reaction', r.reaction, 'created_at', r.created_at)
        ORDER BY r.created_at, r.post_id, r.reaction), '[]'::jsonb)
    FROM public.post_reactions r WHERE r.user_id = p_user_id)))::json
FROM api.portability_export_parts_v19(p_user_id) previous
$$;
REVOKE EXECUTE ON FUNCTION api.portability_export_parts_v21(uuid) FROM PUBLIC;

-- Deletes a member's export requests and takes the manifests out of the
-- answers stored for them.
CREATE FUNCTION api.privacy_discard_exports_v1(p_user_id uuid)
RETURNS TABLE (document json)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
#variable_conflict use_variable
DECLARE ids jsonb; answer record; payload jsonb; response jsonb;
BEGIN
 WITH discarded AS (DELETE FROM public.export_requests WHERE subject_user_id=p_user_id RETURNING export_request_id)
 SELECT COALESCE(jsonb_agg(export_request_id ORDER BY export_request_id),'[]'::jsonb) INTO ids FROM discarded;
 FOR answer IN SELECT c.command_id,c.payload FROM public.command_log c WHERE actor_id=p_user_id AND command_type='privacy.export' FOR UPDATE LOOP
   payload=answer.payload;
   IF jsonb_typeof(payload->'response'->'stored')='object' AND payload->'response'->'stored' ? 'manifest' THEN
     response=jsonb_set(payload->'response','{stored}',(payload->'response'->'stored')-'manifest');
     UPDATE public.command_log SET payload=jsonb_set(payload,'{response}',response),
       response_hash=encode(sha256(convert_to(api.core_canonical_json_v1(response),'UTF8')),'hex') WHERE command_id=answer.command_id;
   END IF;
 END LOOP;
 RETURN QUERY SELECT ids::json;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.privacy_discard_exports_v1(uuid) FROM PUBLIC;

-- A deletion request, export request, retention hold or erasure job by id, as
-- a document, locked when p_lock_row is true.
CREATE FUNCTION api.privacy_find_v1(
    p_source text,
    p_id uuid,
    p_lock_row boolean
)
RETURNS TABLE (document json)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
#variable_conflict use_variable
DECLARE held jsonb;
BEGIN
    CASE p_source
    WHEN 'DeletionRequest' THEN
        IF p_lock_row THEN SELECT (to_jsonb(r)||jsonb_build_object('created_at',r.created_at::text,'completed_at',r.completed_at::text)) INTO held FROM public.deletion_requests r WHERE deletion_request_id=p_id FOR UPDATE;
        ELSE SELECT (to_jsonb(r)||jsonb_build_object('created_at',r.created_at::text,'completed_at',r.completed_at::text)) INTO held FROM public.deletion_requests r WHERE deletion_request_id=p_id; END IF;
    WHEN 'ErasureJob' THEN SELECT (to_jsonb(r)||jsonb_build_object('scheduled_at',r.scheduled_at::text,'completed_at',r.completed_at::text)) INTO held FROM public.erasure_jobs r WHERE erasure_job_id=p_id;
    WHEN 'ExportRequest' THEN SELECT (to_jsonb(r)||jsonb_build_object('created_at',r.created_at::text,'finished_at',r.finished_at::text)) INTO held FROM public.export_requests r WHERE export_request_id=p_id;
    WHEN 'User' THEN SELECT (to_jsonb(r)||jsonb_build_object('created_at',r.created_at::text,'updated_at',r.updated_at::text,'deleted_at',r.deleted_at::text,'email_verified_at',r.email_verified_at::text)) INTO held FROM public.users r WHERE r.id=p_id;
    ELSE RAISE EXCEPTION 'unsupported privacy source %', p_source USING ERRCODE='22023';
    END CASE;
    IF held IS NOT NULL THEN RETURN QUERY SELECT held::json; END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.privacy_find_v1(text, uuid, boolean)
    FROM PUBLIC;

-- Stores a retention hold, deletion request, deletion action, erasure job or
-- export request, as a document.
CREATE FUNCTION api.privacy_insert_v1(p_source text, p_row jsonb)
RETURNS TABLE (document json)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
#variable_conflict use_variable
BEGIN
    CASE p_source
    WHEN 'RetentionHold' THEN
        INSERT INTO public.retention_holds (retention_hold_id, resource_type, resource_id, reason, starts_at, ends_at, created_by, created_at)
        VALUES ((p_row->>'retention_hold_id')::uuid, (p_row->>'resource_type')::text, (p_row->>'resource_id')::uuid, (p_row->>'reason')::text, (p_row->>'starts_at')::timestamptz, (p_row->>'ends_at')::timestamptz, (p_row->>'created_by')::uuid, (p_row->>'created_at')::timestamptz);
    WHEN 'DeletionRequest' THEN
        INSERT INTO public.deletion_requests (deletion_request_id, requester_user_id, resource_type, resource_id, request_type, reason, status, created_at, completed_at)
        VALUES ((p_row->>'deletion_request_id')::uuid, (p_row->>'requester_user_id')::uuid, (p_row->>'resource_type')::text, (p_row->>'resource_id')::uuid, (p_row->>'request_type')::text, (p_row->>'reason')::text, (p_row->>'status')::text, (p_row->>'created_at')::timestamptz, (p_row->>'completed_at')::timestamptz);
    WHEN 'DeletionAction' THEN
        INSERT INTO public.deletion_actions (deletion_action_id, deletion_request_id, actor_id, action_type, metadata, created_at)
        VALUES ((p_row->>'deletion_action_id')::uuid, (p_row->>'deletion_request_id')::uuid, (p_row->>'actor_id')::uuid, (p_row->>'action_type')::text, p_row->'metadata', (p_row->>'created_at')::timestamptz);
    WHEN 'ErasureJob' THEN
        INSERT INTO public.erasure_jobs (erasure_job_id, deletion_request_id, status, scheduled_at, completed_at, last_error)
        VALUES ((p_row->>'erasure_job_id')::uuid, (p_row->>'deletion_request_id')::uuid, (p_row->>'status')::text, (p_row->>'scheduled_at')::timestamptz, (p_row->>'completed_at')::timestamptz, (p_row->>'last_error')::text);
    WHEN 'ExportRequest' THEN
        INSERT INTO public.export_requests (export_request_id, requester_user_id, subject_user_id, export_type, format, status, created_at, finished_at, manifest)
        VALUES ((p_row->>'export_request_id')::uuid, (p_row->>'requester_user_id')::uuid, (p_row->>'subject_user_id')::uuid, (p_row->>'export_type')::text, (p_row->>'format')::text, (p_row->>'status')::text, (p_row->>'created_at')::timestamptz, (p_row->>'finished_at')::timestamptz, p_row->'manifest');
    ELSE RAISE EXCEPTION 'unsupported persistence source %', p_source USING ERRCODE = '22023';
    END CASE;
    RETURN QUERY SELECT p_row::json;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.privacy_insert_v1(text, jsonb) FROM PUBLIC;

-- The latest data-rights record of one kind that matches the query, as a
-- document.
CREATE FUNCTION api.privacy_latest_v1(p_source text, p_query jsonb)
RETURNS TABLE (document json)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
#variable_conflict use_variable
BEGIN
    CASE p_source
    WHEN 'DeletionRequest' THEN RETURN QUERY SELECT (to_jsonb(r)||jsonb_build_object('created_at',r.created_at::text,'completed_at',r.completed_at::text))::json FROM public.deletion_requests r
      WHERE resource_type=p_query->>'resource_type' AND resource_id=(p_query->>'resource_id')::uuid
      AND request_type=p_query->>'request_type' AND status IN ('pending','approved','held') ORDER BY created_at DESC LIMIT 1 FOR UPDATE;
    WHEN 'ErasureJob' THEN RETURN QUERY SELECT (to_jsonb(r)||jsonb_build_object('scheduled_at',r.scheduled_at::text,'completed_at',r.completed_at::text))::json FROM public.erasure_jobs r
      WHERE deletion_request_id=(p_query->>'deletion_request_id')::uuid ORDER BY scheduled_at DESC LIMIT 1;
    WHEN 'RetentionHold' THEN RETURN QUERY SELECT (to_jsonb(r)||jsonb_build_object('starts_at',r.starts_at::text,'ends_at',r.ends_at::text,'created_at',r.created_at::text))::json FROM public.retention_holds r
      WHERE resource_type=p_query->>'resource_type' AND resource_id=(p_query->>'resource_id')::uuid AND ends_at IS NULL ORDER BY created_at DESC LIMIT 1;
    WHEN 'DeletionAction' THEN RETURN QUERY SELECT (to_jsonb(r)||jsonb_build_object('created_at',r.created_at::text))::json FROM public.deletion_actions r
      WHERE deletion_request_id=(p_query->>'deletion_request_id')::uuid AND action_type=p_query->>'action_type' ORDER BY created_at DESC LIMIT 1;
    WHEN 'ExportRequest' THEN RETURN QUERY SELECT (to_jsonb(r)||jsonb_build_object('created_at',r.created_at::text,'finished_at',r.finished_at::text))::json FROM public.export_requests r
      WHERE export_type=p_query->>'export_type' AND format=p_query->>'format' AND requester_user_id=(p_query->>'requester_user_id')::uuid
      AND subject_user_id=(p_query->>'subject_user_id')::uuid AND status='pending' ORDER BY created_at DESC LIMIT 1;
    ELSE RAISE EXCEPTION 'unsupported privacy source %', p_source USING ERRCODE='22023';
    END CASE;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.privacy_latest_v1(text, jsonb) FROM PUBLIC;

-- Whether a member, held FOR SHARE, may be exported: not deleted.
CREATE FUNCTION api.privacy_may_export_v1(p_user_id uuid)
RETURNS TABLE (allowed boolean)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
#variable_conflict use_variable
DECLARE held public.users%ROWTYPE;
BEGIN
 SELECT * INTO held FROM public.users WHERE id=p_user_id FOR SHARE;
 RETURN QUERY SELECT FOUND AND held.deleted_at IS NULL;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.privacy_may_export_v1(uuid) FROM PUBLIC;

-- The data-rights records of one kind that match the query, as documents,
-- oldest or newest first.
CREATE FUNCTION api.privacy_review_v1(
    p_source text,
    p_query jsonb,
    p_row_limit integer,
    p_oldest boolean
)
RETURNS TABLE (document json)
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
#variable_conflict use_variable
BEGIN
    CASE p_source
    WHEN 'DeletionRequest' THEN RETURN QUERY SELECT (to_jsonb(r)||jsonb_build_object('created_at',r.created_at::text,'completed_at',r.completed_at::text))::json FROM public.deletion_requests r
      WHERE (NOT p_query ? 'status' OR status=p_query->>'status')
      AND (NOT p_query ? 'requester_user_id' OR requester_user_id=(p_query->>'requester_user_id')::uuid)
      AND (NOT p_query ? 'resource_type' OR resource_type=p_query->>'resource_type')
      AND (NOT p_query ? 'resource_id' OR resource_id=(p_query->>'resource_id')::uuid)
      ORDER BY CASE WHEN p_oldest THEN created_at END ASC, CASE WHEN NOT p_oldest THEN created_at END DESC LIMIT p_row_limit;
    WHEN 'ExportRequest' THEN RETURN QUERY SELECT (to_jsonb(r)||jsonb_build_object('created_at',r.created_at::text,'finished_at',r.finished_at::text))::json FROM public.export_requests r
      WHERE (NOT p_query ? 'status' OR status=p_query->>'status')
      AND (NOT p_query ? 'requester_user_id' OR requester_user_id=(p_query->>'requester_user_id')::uuid)
      AND (NOT p_query ? 'subject_user_id' OR subject_user_id=(p_query->>'subject_user_id')::uuid)
      AND (NOT p_query ? 'export_request_id' OR export_request_id=(p_query->>'export_request_id')::uuid)
      ORDER BY CASE WHEN p_oldest THEN created_at END ASC, CASE WHEN NOT p_oldest THEN created_at END DESC LIMIT p_row_limit;
    WHEN 'RetentionHold' THEN RETURN QUERY SELECT (to_jsonb(r)||jsonb_build_object('starts_at',r.starts_at::text,'ends_at',r.ends_at::text,'created_at',r.created_at::text))::json FROM public.retention_holds r
      WHERE ends_at IS NULL AND (NOT p_query ? 'resource_type' OR resource_type=p_query->>'resource_type')
      AND (NOT p_query ? 'resource_id' OR resource_id=(p_query->>'resource_id')::uuid) ORDER BY created_at DESC LIMIT p_row_limit;
    WHEN 'ErasureJob' THEN RETURN QUERY SELECT (to_jsonb(r)||jsonb_build_object('scheduled_at',r.scheduled_at::text,'completed_at',r.completed_at::text))::json FROM public.erasure_jobs r
      WHERE status=p_query->>'status' ORDER BY scheduled_at ASC LIMIT p_row_limit;
    ELSE RAISE EXCEPTION 'unsupported privacy source %', p_source USING ERRCODE='22023';
    END CASE;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.privacy_review_v1(text, jsonb, integer, boolean)
    FROM PUBLIC;

-- Revokes or deletes the rows of one kind a member leaves behind when erased.
-- Answers how many.
CREATE FUNCTION api.privacy_revoke_user_v1(
    p_source text,
    p_user_id uuid,
    p_at text
)
RETURNS TABLE (revoked bigint)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
#variable_conflict use_variable
DECLARE amount bigint;
BEGIN
 IF p_source='Credential' THEN UPDATE public.credentials r SET revoked_at=GREATEST(p_at::timestamptz,r.created_at) WHERE r.user_id=p_user_id AND revoked_at IS NULL;
 ELSIF p_source='Session' THEN UPDATE public.sessions r SET revoked_at=GREATEST(p_at::timestamptz,r.created_at) WHERE r.user_id=p_user_id AND revoked_at IS NULL;
 ELSE RAISE EXCEPTION 'unsupported revocation source %',p_source USING ERRCODE='22023'; END IF;
 GET DIAGNOSTICS amount=ROW_COUNT;
 RETURN QUERY SELECT amount;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.privacy_revoke_user_v1(text, uuid, text)
    FROM PUBLIC;

-- What privacy_revoke_user_v1 revokes, and the member's drafts.
CREATE FUNCTION api.privacy_revoke_user_v3(
    p_source text,
    p_user_id uuid,
    p_at text
)
RETURNS TABLE (revoked bigint)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE amount bigint;
BEGIN
    IF p_source='ForumDraft' THEN
        DELETE FROM public.forum_drafts d WHERE d.owner_user_id=p_user_id;
        GET DIAGNOSTICS amount=ROW_COUNT;
        RETURN QUERY SELECT amount;
    ELSE RETURN QUERY SELECT * FROM api.privacy_revoke_user_v1(p_source,p_user_id,p_at);
    END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.privacy_revoke_user_v3(text, uuid, text)
    FROM PUBLIC;

-- Erasing an account takes its likes with it (source PostLike); every other
-- source is as it was.
CREATE FUNCTION api.privacy_revoke_user_v5(
    p_source text,
    p_user_id uuid,
    p_at text
)
RETURNS TABLE (revoked bigint)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE
    amount bigint;
BEGIN
    IF p_source = 'PostLike' THEN
        DELETE FROM public.post_likes l WHERE l.user_id = p_user_id;
        GET DIAGNOSTICS amount = ROW_COUNT;
        RETURN QUERY SELECT amount;
    ELSE
        RETURN QUERY SELECT * FROM api.privacy_revoke_user_v3(p_source,
            p_user_id, p_at);
    END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.privacy_revoke_user_v5(text, uuid, text)
    FROM PUBLIC;

-- Erasure: the erased member leaves every list, theirs and others'.
CREATE FUNCTION api.privacy_revoke_user_v7(
    p_source text,
    p_user_id uuid,
    p_at text
)
RETURNS TABLE (revoked bigint)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE amount bigint;
BEGIN
    IF p_source = 'MemberRelation' THEN
        DELETE FROM public.member_relations r
            WHERE r.owner_user_id = p_user_id OR r.other_user_id = p_user_id;
        GET DIAGNOSTICS amount = ROW_COUNT;
        RETURN QUERY SELECT amount;
    ELSE
        RETURN QUERY SELECT * FROM api.privacy_revoke_user_v5(p_source,
            p_user_id, p_at);
    END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.privacy_revoke_user_v7(text, uuid, text)
    FROM PUBLIC;

-- An erased member's held posts go with them.
CREATE FUNCTION api.privacy_revoke_user_v9(
    p_source text,
    p_user_id uuid,
    p_at text
)
RETURNS TABLE (revoked bigint)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE amount bigint;
BEGIN
    IF p_source = 'HeldPost' THEN
        DELETE FROM public.held_posts h WHERE h.author_user_id = p_user_id;
        GET DIAGNOSTICS amount = ROW_COUNT;
        RETURN QUERY SELECT amount;
    ELSE
        RETURN QUERY SELECT * FROM api.privacy_revoke_user_v7(p_source,
            p_user_id, p_at);
    END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.privacy_revoke_user_v9(text, uuid, text)
    FROM PUBLIC;

-- An erased member's notes go with them; notes an erased staff member
-- wrote about others stay, under the anonymized account.
CREATE FUNCTION api.privacy_revoke_user_v11(
    p_source text,
    p_user_id uuid,
    p_at text
)
RETURNS TABLE (revoked bigint)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE amount bigint;
BEGIN
    IF p_source = 'MemberNote' THEN
        DELETE FROM public.member_notes n WHERE n.subject_user_id = p_user_id;
        GET DIAGNOSTICS amount = ROW_COUNT;
        RETURN QUERY SELECT amount;
    ELSE
        RETURN QUERY SELECT * FROM api.privacy_revoke_user_v9(p_source,
            p_user_id, p_at);
    END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.privacy_revoke_user_v11(text, uuid, text)
    FROM PUBLIC;

-- An erased member's messages go, with their side of every conversation;
-- the other member keeps their own messages, and a conversation nobody is
-- left in goes too.
CREATE FUNCTION api.privacy_revoke_user_v13(
    p_source text,
    p_user_id uuid,
    p_at text
)
RETURNS TABLE (revoked bigint)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE amount bigint;
BEGIN
    IF p_source = 'DirectMessage' THEN
        DELETE FROM public.direct_messages d WHERE d.author_user_id = p_user_id;
        GET DIAGNOSTICS amount = ROW_COUNT;
        UPDATE public.direct_conversation_members m
            SET unread_count = (SELECT count(*)
                FROM public.direct_messages d
                WHERE d.conversation_id = m.conversation_id
                    AND d.author_user_id <> m.user_id
                    AND (m.last_read_at IS NULL
                        OR d.created_at > m.last_read_at))
            WHERE m.other_user_id = p_user_id;
        DELETE FROM public.direct_conversation_members m
            WHERE m.user_id = p_user_id;
        DELETE FROM public.direct_conversations c
            WHERE (c.first_user_id = p_user_id OR c.second_user_id = p_user_id)
                AND NOT EXISTS (SELECT 1
                    FROM public.direct_conversation_members m
                    WHERE m.conversation_id = c.conversation_id);
        UPDATE public.direct_conversations c SET started_by_user_id = NULL
            WHERE c.started_by_user_id = p_user_id;
        RETURN QUERY SELECT amount;
    ELSE
        RETURN QUERY SELECT * FROM api.privacy_revoke_user_v11(p_source,
            p_user_id, p_at);
    END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.privacy_revoke_user_v13(text, uuid, text)
    FROM PUBLIC;

-- Erasure: the member's secret, recovery codes and challenges go.
CREATE FUNCTION api.privacy_revoke_user_v15(
    p_source text,
    p_user_id uuid,
    p_at text
)
RETURNS TABLE (revoked bigint)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE amount bigint;
BEGIN
    IF p_source = 'SecondFactor' THEN
        DELETE FROM public.second_factor_recovery_codes c
            WHERE c.user_id = p_user_id;
        DELETE FROM public.second_factor_challenges c
            WHERE c.user_id = p_user_id;
        DELETE FROM public.second_factors f WHERE f.user_id = p_user_id;
        GET DIAGNOSTICS amount = ROW_COUNT;
        RETURN QUERY SELECT amount;
    ELSE
        RETURN QUERY SELECT * FROM api.privacy_revoke_user_v13(p_source,
            p_user_id, p_at);
    END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.privacy_revoke_user_v15(text, uuid, text)
    FROM PUBLIC;

-- Erasure: the member's picture row goes, and every upload they linked to
-- their profile is marked deleted. Their stored objects were deleted
-- before (Service::Community::Avatars::erase_files).
CREATE FUNCTION api.privacy_revoke_user_v17(
    p_source text,
    p_user_id uuid,
    p_at text
)
RETURNS TABLE (revoked bigint)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE rows_gone bigint; uploads_gone bigint;
BEGIN
    IF p_source = 'Avatar' THEN
        DELETE FROM public.member_avatars m WHERE m.user_id = p_user_id;
        GET DIAGNOSTICS rows_gone = ROW_COUNT;
        UPDATE public.attachments a
            SET state = 'deleted',
                deleted_at = coalesce(a.deleted_at, p_at::timestamptz)
            WHERE a.owner_user_id = p_user_id AND a.state <> 'deleted'
                AND EXISTS (SELECT 1 FROM public.attachment_links l
                    WHERE l.attachment_id = a.attachment_id
                        AND l.target_type = 'profile'
                        AND l.target_id = p_user_id);
        GET DIAGNOSTICS uploads_gone = ROW_COUNT;
        RETURN QUERY SELECT rows_gone + uploads_gone;
    ELSE
        RETURN QUERY SELECT * FROM api.privacy_revoke_user_v15(p_source,
            p_user_id, p_at);
    END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.privacy_revoke_user_v17(text, uuid, text)
    FROM PUBLIC;

-- Erasure deletes a member's reactions (source PostReaction); every other
-- source goes on to the version before.
CREATE FUNCTION api.privacy_revoke_user_v19(
    p_source text,
    p_user_id uuid,
    p_at text
)
RETURNS TABLE (revoked bigint)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE
    amount bigint;
BEGIN
    IF p_source = 'PostReaction' THEN
        DELETE FROM public.post_reactions r WHERE r.user_id = p_user_id;
        GET DIAGNOSTICS amount = ROW_COUNT;
        RETURN QUERY SELECT amount;
    ELSE
        RETURN QUERY SELECT * FROM api.privacy_revoke_user_v17(p_source,
            p_user_id, p_at);
    END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.privacy_revoke_user_v19(text, uuid, text)
    FROM PUBLIC;

-- An erased staff member's name leaves the bans they placed, edited or
-- lifted; the bans stay, since they are about an address, not about them.
CREATE FUNCTION api.privacy_revoke_user_v21(
    p_source text,
    p_user_id uuid,
    p_at text
)
RETURNS TABLE (revoked bigint)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE amount bigint;
BEGIN
    IF p_source = 'AddressBan' THEN
        UPDATE public.address_bans b
            SET created_by_user_id = nullif(b.created_by_user_id, p_user_id),
                updated_by_user_id = nullif(b.updated_by_user_id, p_user_id),
                lifted_by_user_id = nullif(b.lifted_by_user_id, p_user_id)
            WHERE p_user_id IN (b.created_by_user_id, b.updated_by_user_id,
                b.lifted_by_user_id);
        GET DIAGNOSTICS amount = ROW_COUNT;
        RETURN QUERY SELECT amount;
    ELSE
        RETURN QUERY SELECT * FROM api.privacy_revoke_user_v19(p_source,
            p_user_id, p_at);
    END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.privacy_revoke_user_v21(text, uuid, text)
    FROM PUBLIC;

-- Writes the given fields of a data-rights record, as a document.
CREATE FUNCTION api.privacy_update_v1(
    p_source text,
    p_id uuid,
    p_changes jsonb
)
RETURNS TABLE (document json)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
#variable_conflict use_variable
BEGIN
 CASE p_source
 WHEN 'DeletionRequest' THEN RETURN QUERY UPDATE public.deletion_requests r SET status=CASE WHEN p_changes ? 'status' THEN (p_changes->>'status')::text ELSE r.status END, completed_at=CASE WHEN p_changes ? 'completed_at' THEN (p_changes->>'completed_at')::timestamptz ELSE r.completed_at END WHERE deletion_request_id=p_id RETURNING to_json(r);
 WHEN 'ErasureJob' THEN RETURN QUERY UPDATE public.erasure_jobs r SET status=CASE WHEN p_changes ? 'status' THEN (p_changes->>'status')::text ELSE r.status END, completed_at=CASE WHEN p_changes ? 'completed_at' THEN (p_changes->>'completed_at')::timestamptz ELSE r.completed_at END, last_error=CASE WHEN p_changes ? 'last_error' THEN (p_changes->>'last_error')::text ELSE r.last_error END WHERE erasure_job_id=p_id RETURNING to_json(r);
 WHEN 'ExportRequest' THEN RETURN QUERY UPDATE public.export_requests r SET status=CASE WHEN p_changes ? 'status' THEN (p_changes->>'status')::text ELSE r.status END, finished_at=CASE WHEN p_changes ? 'finished_at' THEN (p_changes->>'finished_at')::timestamptz ELSE r.finished_at END, manifest=CASE WHEN p_changes ? 'manifest' THEN p_changes->'manifest' ELSE r.manifest END WHERE export_request_id=p_id RETURNING to_json(r);
 WHEN 'User' THEN RETURN QUERY UPDATE public.users r SET deleted_at=CASE WHEN p_changes ? 'deleted_at' THEN (p_changes->>'deleted_at')::timestamptz ELSE r.deleted_at END, display_name=CASE WHEN p_changes ? 'display_name' THEN (p_changes->>'display_name')::text ELSE r.display_name END, email_normalized=CASE WHEN p_changes ? 'email_normalized' THEN (p_changes->>'email_normalized')::text ELSE r.email_normalized END, email_verified_at=CASE WHEN p_changes ? 'email_verified_at' THEN (p_changes->>'email_verified_at')::timestamptz ELSE r.email_verified_at END, password_hash=CASE WHEN p_changes ? 'password_hash' THEN (p_changes->>'password_hash')::text ELSE r.password_hash END, status=CASE WHEN p_changes ? 'status' THEN (p_changes->>'status')::text ELSE r.status END, trust_level=CASE WHEN p_changes ? 'trust_level' THEN (p_changes->>'trust_level')::integer ELSE r.trust_level END, updated_at=CASE WHEN p_changes ? 'updated_at' THEN (p_changes->>'updated_at')::timestamptz ELSE r.updated_at END, username=CASE WHEN p_changes ? 'username' THEN (p_changes->>'username')::text ELSE r.username END WHERE id=p_id RETURNING to_json(r);
 ELSE RAISE EXCEPTION 'unsupported privacy source %', p_source USING ERRCODE='22023';
 END CASE;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.privacy_update_v1(text, uuid, jsonb)
    FROM PUBLIC;

-- Erasure writes the account's bio away with the rest of its words: the
-- shipped update ignores a column it does not know, so this one writes
-- the bio first and hands the other changes on.
CREATE FUNCTION api.privacy_update_v3(
    p_source text,
    p_id uuid,
    p_changes jsonb
)
RETURNS TABLE (document json)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    IF p_source = 'User' AND p_changes ? 'bio' THEN
        UPDATE public.users u SET bio = (p_changes ->> 'bio')::text
        WHERE u.id = p_id;
    END IF;
    RETURN QUERY SELECT * FROM api.privacy_update_v1(p_source, p_id,
        p_changes - 'bio');
END;
$$;
REVOKE EXECUTE ON FUNCTION api.privacy_update_v3(text, uuid, jsonb)
    FROM PUBLIC;

COMMIT;
