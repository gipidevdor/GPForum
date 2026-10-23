-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

SET LOCAL lock_timeout = '5s';

CREATE TABLE public.post_signatures (
    body_id uuid PRIMARY KEY REFERENCES public.post_bodies(body_id) ON DELETE CASCADE,
    envelope jsonb NOT NULL
);
REVOKE ALL ON public.post_signatures FROM PUBLIC;
COMMENT ON TABLE public.post_signatures IS 'Immutable server attestations of post body revisions; trust anchors are archived separately from the database.';
COMMENT ON COLUMN public.post_signatures.body_id IS 'Revision body covered by this attestation; erased with its source body.';
COMMENT ON COLUMN public.post_signatures.envelope IS 'Ed25519 signature, canonical payload digest and public JWK; existing attestations are never overwritten.';

CREATE FUNCTION api.core_forum_attach_signature_v1(p_stored jsonb, p_command jsonb)
RETURNS void LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE body public.post_bodies%ROWTYPE;
BEGIN
    IF p_command #> '{body,post_signature}' IS NULL
       OR p_command #> '{body,post_signature}' = 'null'::jsonb
       OR p_stored #>> '{post,post_id}' IS NULL THEN RETURN; END IF;
    SELECT b.* INTO body FROM public.posts p
        JOIN public.post_bodies b ON b.body_id = p.current_body_id
        WHERE p.post_id = (p_stored #>> '{post,post_id}')::uuid;
    IF NOT FOUND THEN RETURN; END IF;
    IF body.post_id::text <> p_command #>> '{body,post_id}'
       OR body.body_source IS DISTINCT FROM p_command #>> '{body,body_source}' THEN
        RAISE EXCEPTION 'post identity changed while signing; retry the command' USING ERRCODE = '40001';
    END IF;
    INSERT INTO public.post_signatures(body_id, envelope)
    VALUES (body.body_id, p_command #> '{body,post_signature}')
    ON CONFLICT (body_id) DO NOTHING;
END
$$;
REVOKE EXECUTE ON FUNCTION api.core_forum_attach_signature_v1(jsonb, jsonb) FROM PUBLIC;

CREATE FUNCTION api.forum_store_write_v3(
    p_store_type text,
    p_command jsonb,
    p_record jsonb
)
RETURNS TABLE (stored json)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE result record;
BEGIN
    SELECT * INTO result FROM api.forum_store_write_v2(p_store_type, p_command, p_record);
    PERFORM api.core_forum_attach_signature_v1(result.stored::jsonb, p_command);
    RETURN QUERY SELECT result.stored;
END
$$;
REVOKE EXECUTE ON FUNCTION api.forum_store_write_v3(text, jsonb, jsonb) FROM PUBLIC;

CREATE FUNCTION api.forum_store_write_v4(
    p_store_type text,
    p_command jsonb,
    p_record jsonb
)
RETURNS TABLE (stored json)
LANGUAGE sql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_store_write_v3(p_store_type, p_command, p_record);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_store_write_v4(text, jsonb, jsonb) FROM PUBLIC;

CREATE FUNCTION api.forum_write_command_v5(
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
DECLARE result record;
BEGIN
    SELECT * INTO result FROM api.forum_write_command_v4(p_log, p_answer, p_store_type, p_command, p_record, p_draft_id, p_draft_revision);
    PERFORM api.core_forum_attach_signature_v1(result.stored::jsonb, p_command);
    RETURN QUERY SELECT result.outcome, result.response, result.stored;
END
$$;
REVOKE EXECUTE ON FUNCTION api.forum_write_command_v5(jsonb, jsonb, text, jsonb, jsonb, uuid, bigint) FROM PUBLIC;

CREATE FUNCTION api.forum_write_command_v6(
    p_log jsonb,
    p_answer jsonb,
    p_store_type text,
    p_command jsonb,
    p_record jsonb,
    p_draft_id uuid,
    p_draft_revision bigint
)
RETURNS TABLE (outcome text, response json, stored json)
LANGUAGE sql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_write_command_v5(p_log, p_answer, p_store_type, p_command, p_record, p_draft_id, p_draft_revision);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_write_command_v6(jsonb, jsonb, text, jsonb, jsonb, uuid, bigint) FROM PUBLIC;

CREATE FUNCTION api.forum_create_reply_v5(
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
    SELECT * INTO result FROM api.forum_create_reply_v4(p_idempotency_key, p_command_type, p_actor_id, p_request_hash, p_command_id, p_command_correlation_id, p_command_at, p_answer, p_store_refusals, p_post_id, p_thread_id, p_author_user_id, p_current_body_id, p_current_revision_id, p_position, p_visibility, p_moderation_state, p_version, p_visibility_version, p_permission_version, p_hidden_at, p_locked_at, p_deleted_at, p_deleted_by, p_body_id, p_body_post_id, p_body_format, p_body_source, p_body_rendered_safe, p_source_hash, p_revision_id, p_revision_post_id, p_revision_body_id, p_editor_user_id, p_revision_number, p_edit_reason, p_correlation_id, p_event_id, p_outbox_id, p_audit_id, p_recorded_at, p_draft_id, p_draft_revision);
    IF result.post_id IS NOT NULL AND NOT coalesce(result.skipped, false) AND p_post_signature IS NOT NULL THEN
        PERFORM api.core_forum_attach_signature_v1(
            jsonb_build_object('post', jsonb_build_object('post_id', result.post_id)),
            jsonb_build_object('body', jsonb_build_object('post_signature', p_post_signature,
                'post_id', p_body_post_id, 'body_source', p_body_source)));
    END IF;
    RETURN QUERY SELECT result.outcome, result.response, result.skipped, result.post_id, result.thread_id, result.author_user_id, result.current_body_id, result.current_revision_id, result."position", result.visibility, result.moderation_state, result.version, result.visibility_version, result.permission_version, result.hidden_at, result.locked_at, result.deleted_at, result.deleted_by;
END
$$;
REVOKE EXECUTE ON FUNCTION api.forum_create_reply_v5(text, text, text, text, text, text, text, jsonb, jsonb, text, text, text, text, text, bigint, text, text, bigint, bigint, bigint, text, text, text, text, text, text, text, text, text, text, text, text, text, text, integer, text, text, text, text, text, text, uuid, bigint, jsonb) FROM PUBLIC;

CREATE FUNCTION api.forum_create_reply_v6(
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
LANGUAGE sql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_create_reply_v5(p_idempotency_key, p_command_type, p_actor_id, p_request_hash, p_command_id, p_command_correlation_id, p_command_at, p_answer, p_store_refusals, p_post_id, p_thread_id, p_author_user_id, p_current_body_id, p_current_revision_id, p_position, p_visibility, p_moderation_state, p_version, p_visibility_version, p_permission_version, p_hidden_at, p_locked_at, p_deleted_at, p_deleted_by, p_body_id, p_body_post_id, p_body_format, p_body_source, p_body_rendered_safe, p_source_hash, p_revision_id, p_revision_post_id, p_revision_body_id, p_editor_user_id, p_revision_number, p_edit_reason, p_correlation_id, p_event_id, p_outbox_id, p_audit_id, p_recorded_at, p_draft_id, p_draft_revision, p_post_signature);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_create_reply_v6(text, text, text, text, text, text, text, jsonb, jsonb, text, text, text, text, text, bigint, text, text, bigint, bigint, bigint, text, text, text, text, text, text, text, text, text, text, text, text, text, text, integer, text, text, text, text, text, text, uuid, bigint, jsonb) FROM PUBLIC;

CREATE FUNCTION api.forum_protocol_signature_v1(p_body_id uuid)
RETURNS TABLE (envelope json)
LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT s.envelope::json FROM public.post_signatures s WHERE s.body_id = p_body_id;
$$;
REVOKE EXECUTE ON FUNCTION api.forum_protocol_signature_v1(uuid) FROM PUBLIC;

CREATE FUNCTION api.forum_protocol_signature_v2(p_body_id uuid)
RETURNS TABLE (envelope json)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_protocol_signature_v1(p_body_id);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_protocol_signature_v2(uuid) FROM PUBLIC;

CREATE FUNCTION api.forum_protocol_member_v1(p_user_id uuid, p_email text)
RETURNS TABLE (id uuid, email_normalized text, trust_level integer, email_verified_at timestamptz)
LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT u.id,u.email_normalized,u.trust_level,u.email_verified_at FROM public.users u WHERE (u.id=p_user_id OR u.email_normalized=p_email) AND u.status='active' AND u.deleted_at IS NULL;
$$;
REVOKE EXECUTE ON FUNCTION api.forum_protocol_member_v1(uuid, text) FROM PUBLIC;

CREATE FUNCTION api.forum_protocol_member_v2(p_user_id uuid, p_email text)
RETURNS TABLE (id uuid, email_normalized text, trust_level integer, email_verified_at timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_protocol_member_v1(p_user_id, p_email);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_protocol_member_v2(uuid, text) FROM PUBLIC;

CREATE FUNCTION api.forum_protocol_unsigned_bodies_v1(p_after uuid)
RETURNS TABLE (body_id uuid, post_id uuid, body_format text, body_source text)
LANGUAGE sql STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT b.body_id,b.post_id,b.body_format,b.body_source FROM public.post_bodies b
WHERE (p_after IS NULL OR b.body_id > p_after)
AND NOT EXISTS (SELECT 1 FROM public.post_signatures s WHERE s.body_id=b.body_id)
ORDER BY b.body_id LIMIT 100;
$$;
REVOKE EXECUTE ON FUNCTION api.forum_protocol_unsigned_bodies_v1(uuid) FROM PUBLIC;

CREATE FUNCTION api.forum_protocol_unsigned_bodies_v2(p_after uuid)
RETURNS TABLE (body_id uuid, post_id uuid, body_format text, body_source text)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_protocol_unsigned_bodies_v1(p_after);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_protocol_unsigned_bodies_v2(uuid) FROM PUBLIC;

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
REVOKE EXECUTE ON FUNCTION api.forum_protocol_attest_body_v1(uuid, uuid, text, jsonb) FROM PUBLIC;

CREATE FUNCTION api.forum_protocol_attest_body_v2(p_body_id uuid, p_post_id uuid, p_source text, p_envelope jsonb)
RETURNS TABLE (saved boolean)
LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_protocol_attest_body_v1(p_body_id, p_post_id, p_source, p_envelope);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_protocol_attest_body_v2(uuid, uuid, text, jsonb) FROM PUBLIC;
