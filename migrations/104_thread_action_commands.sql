-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

-- ADR 0126, section 5: a command is one call. The three actions a signed-in
-- reader takes on a thread most -- marking it read, bookmarking it,
-- subscribing to it -- each ran their work as one function while Perl kept
-- the command log around it: a transaction, a lookup, a savepoint, an insert,
-- the work, an update and a commit, eight round trips for one call. Each is
-- one call now: the command log's steps, which the three share as
-- api.core_command_open_v1 and api.core_command_close_v1, around the work
-- function the action already had. The answer recorded is the one the Perl
-- path recorded, key for key, so a response stored before this migration
-- replays as it did and the same request hashes the same.

BEGIN;
SET LOCAL lock_timeout = '1s';

-- The command log's opening, as api.forum_create_reply_v1 does it inline:
-- a key already logged replays its response, conflicts on another request
-- hash or is in progress; a new row is inserted, a taken command id is
-- drawn again, and a row of the same key without a response is reused.
-- 'opened' hands back the row's id and payload for the close.
CREATE FUNCTION api.core_command_open_v1(p_log jsonb)
RETURNS TABLE (outcome text, response jsonb, command_id text, payload jsonb)
LANGUAGE plpgsql
VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
#variable_conflict use_column
DECLARE
    existing public.command_log;
    held record;
    row_command_id text := p_log ->> 'command_id';
    held_payload jsonb :=
        jsonb_build_object('request_hash', p_log ->> 'request_hash');
    reported text;
BEGIN
    SELECT me.* INTO existing FROM public.command_log me
    WHERE me.idempotency_key = p_log ->> 'idempotency_key'
    LIMIT 1;
    IF FOUND THEN
        SELECT * INTO held FROM api.core_command_existing_v1(
            existing.payload, p_log ->> 'request_hash');
        RETURN QUERY SELECT held.outcome, held.response, NULL::text,
            NULL::jsonb;
        RETURN;
    END IF;
    BEGIN
        INSERT INTO public.command_log (actor_id, command_id, command_type,
            correlation_id, created_at, handled_at, idempotency_key, payload,
            response_hash, status)
        VALUES ((p_log ->> 'actor_id')::uuid, row_command_id::uuid,
            p_log ->> 'command_type',
            (p_log ->> 'command_correlation_id')::uuid,
            (p_log ->> 'command_at')::timestamptz, NULL,
            p_log ->> 'idempotency_key', held_payload, NULL, 'accepted');
    EXCEPTION WHEN unique_violation THEN
        GET STACKED DIAGNOSTICS reported = CONSTRAINT_NAME;
        IF api.core_unique_on_v1(reported, 'command_log_pkey') THEN
            SELECT me.* INTO existing FROM public.command_log me
            WHERE me.command_id = row_command_id::uuid;
            IF NOT FOUND OR existing.idempotency_key IS NULL
                OR existing.idempotency_key <> p_log ->> 'idempotency_key'
            THEN
                row_command_id := api.core_uuid_v7_v1()::text;
                INSERT INTO public.command_log (actor_id, command_id,
                    command_type, correlation_id, created_at, handled_at,
                    idempotency_key, payload, response_hash, status)
                VALUES ((p_log ->> 'actor_id')::uuid, row_command_id::uuid,
                    p_log ->> 'command_type',
                    (p_log ->> 'command_correlation_id')::uuid,
                    (p_log ->> 'command_at')::timestamptz, NULL,
                    p_log ->> 'idempotency_key', held_payload, NULL,
                    'accepted');
            ELSIF jsonb_typeof(existing.payload) = 'object'
                AND existing.payload ? 'response'
            THEN
                SELECT * INTO held FROM api.core_command_existing_v1(
                    existing.payload, p_log ->> 'request_hash');
                RETURN QUERY SELECT held.outcome, held.response, NULL::text,
                    NULL::jsonb;
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
            WHERE me.idempotency_key = p_log ->> 'idempotency_key'
            LIMIT 1;
            IF NOT FOUND THEN
                RAISE;
            END IF;
            SELECT * INTO held FROM api.core_command_existing_v1(
                existing.payload, p_log ->> 'request_hash');
            RETURN QUERY SELECT held.outcome, held.response, NULL::text,
                NULL::jsonb;
            RETURN;
        ELSE
            RAISE;
        END IF;
    END;
    RETURN QUERY SELECT 'opened'::text, NULL::jsonb, row_command_id,
        held_payload;
END
$$;
REVOKE EXECUTE ON FUNCTION api.core_command_open_v1(jsonb) FROM PUBLIC;

-- The command log's close: the answer, its canonical hash and the status
-- the Perl path stored (handled for an answer that says ok, rejected
-- otherwise), handled at the command's own time.
CREATE FUNCTION api.core_command_close_v1(p_command_id text,
    p_command_at text, p_payload jsonb, p_answer jsonb)
RETURNS TABLE (closed boolean)
LANGUAGE sql
VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
WITH changed AS (
    UPDATE public.command_log me
    SET handled_at = p_command_at::timestamptz,
        payload = p_payload || jsonb_build_object('response', p_answer),
        response_hash = encode(sha256(convert_to(
            api.core_canonical_json_v1(p_answer), 'UTF8')), 'hex'),
        status = CASE WHEN api.core_perl_true_v1(p_answer ->> 'ok')
            THEN 'handled' ELSE 'rejected' END
    WHERE me.command_id = p_command_id::uuid
    RETURNING 1
)
SELECT EXISTS (SELECT 1 FROM changed)
$$;
REVOKE EXECUTE ON FUNCTION api.core_command_close_v1(text, text, jsonb,
    jsonb) FROM PUBLIC;

-- Marking a thread read: the command log around api.forum_mark_read_v1, and
-- the answer ReadWorkflow records: whether the marker advanced, and the
-- state's four columns. p_answer, when given, is the store's refusal of the
-- request, recorded without running the mark.
CREATE FUNCTION api.forum_read_marker_command_v1(p_log jsonb,
    p_answer jsonb, p_row jsonb)
RETURNS TABLE (outcome text, response json)
LANGUAGE plpgsql
VOLATILE
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
REVOKE EXECUTE ON FUNCTION api.forum_read_marker_command_v1(jsonb, jsonb,
    jsonb) FROM PUBLIC;

-- Bookmarking a thread: the command log around
-- api.community_save_bookmark_v1, an id a collision took drawn again once,
-- and the answer Community::Workflow records: the bookmark's public fields.
CREATE FUNCTION api.community_bookmark_command_v1(p_log jsonb,
    p_answer jsonb, p_row jsonb)
RETURNS TABLE (outcome text, response json)
LANGUAGE plpgsql
VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE
    opened record;
    answer jsonb := p_answer;
    saved jsonb;
    row_in jsonb := p_row;
BEGIN
    SELECT * INTO opened FROM api.core_command_open_v1(p_log);
    IF opened.outcome <> 'opened' THEN
        RETURN QUERY SELECT opened.outcome, opened.response::json;
        RETURN;
    END IF;
    IF answer IS NULL THEN
        SELECT result INTO saved
        FROM api.community_save_bookmark_v1(row_in, true);
        IF api.core_perl_true_v1(saved ->> 'retry_id') THEN
            row_in := row_in || jsonb_build_object('bookmark_id',
                api.core_uuid_v7_v1()::text);
            SELECT result INTO saved
            FROM api.community_save_bookmark_v1(row_in, true);
            IF api.core_perl_true_v1(saved ->> 'retry_id') THEN
                RAISE EXCEPTION USING ERRCODE = 'unique_violation',
                    MESSAGE = 'the replacement id is already stored';
            END IF;
        END IF;
        answer := jsonb_build_object(
            'error', NULL, 'errors', NULL, 'ok', 1, 'status', 'ok',
            'stored', jsonb_build_object(
                'bookmark_id', saved -> 'bookmark_id',
                'created_at', saved -> 'created_at',
                'deleted_at', saved -> 'deleted_at',
                'note', saved -> 'note',
                'ok', saved -> 'ok',
                'target_id', saved -> 'target_id',
                'target_type', saved -> 'target_type',
                'user_id', saved -> 'user_id'));
    END IF;
    PERFORM api.core_command_close_v1(opened.command_id,
        p_log ->> 'command_at', opened.payload, answer);
    RETURN QUERY SELECT 'recorded'::text, answer::json;
END
$$;
REVOKE EXECUTE ON FUNCTION api.community_bookmark_command_v1(jsonb, jsonb,
    jsonb) FROM PUBLIC;

-- Subscribing to a thread: the same around
-- api.notification_save_subscription_v1.
CREATE FUNCTION api.community_subscribe_command_v1(p_log jsonb,
    p_answer jsonb, p_row jsonb)
RETURNS TABLE (outcome text, response json)
LANGUAGE plpgsql
VOLATILE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE
    opened record;
    answer jsonb := p_answer;
    saved jsonb;
    row_in jsonb := p_row;
BEGIN
    SELECT * INTO opened FROM api.core_command_open_v1(p_log);
    IF opened.outcome <> 'opened' THEN
        RETURN QUERY SELECT opened.outcome, opened.response::json;
        RETURN;
    END IF;
    IF answer IS NULL THEN
        SELECT result INTO saved
        FROM api.notification_save_subscription_v1(row_in, true);
        IF api.core_perl_true_v1(saved ->> 'retry_id') THEN
            row_in := row_in || jsonb_build_object('subscription_id',
                api.core_uuid_v7_v1()::text);
            SELECT result INTO saved
            FROM api.notification_save_subscription_v1(row_in, true);
            IF api.core_perl_true_v1(saved ->> 'retry_id') THEN
                RAISE EXCEPTION USING ERRCODE = 'unique_violation',
                    MESSAGE = 'the replacement id is already stored';
            END IF;
        END IF;
        answer := jsonb_build_object(
            'error', NULL, 'errors', NULL, 'ok', 1, 'status', 'ok',
            'stored', jsonb_build_object(
                'created_at', saved -> 'created_at',
                'muted_at', saved -> 'muted_at',
                'ok', saved -> 'ok',
                'preference', saved -> 'preference',
                'revoked_at', saved -> 'revoked_at',
                'subscription_id', saved -> 'subscription_id',
                'target_id', saved -> 'target_id',
                'target_type', saved -> 'target_type',
                'user_id', saved -> 'user_id'));
    END IF;
    PERFORM api.core_command_close_v1(opened.command_id,
        p_log ->> 'command_at', opened.payload, answer);
    RETURN QUERY SELECT 'recorded'::text, answer::json;
END
$$;
REVOKE EXECUTE ON FUNCTION api.community_subscribe_command_v1(jsonb, jsonb,
    jsonb) FROM PUBLIC;

-- ADR 0127: the typed boundaries the runtime role may call, each forwarding
-- its arguments to its own implementation.
CREATE FUNCTION api.forum_read_marker_command_v2(
p_log jsonb, p_answer jsonb, p_row jsonb
)
RETURNS TABLE (outcome text, response json)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.forum_read_marker_command_v1(p_log, p_answer, p_row);
$$;
REVOKE EXECUTE ON FUNCTION api.forum_read_marker_command_v2(jsonb, jsonb,
    jsonb) FROM PUBLIC;

CREATE FUNCTION api.community_bookmark_command_v2(
p_log jsonb, p_answer jsonb, p_row jsonb
)
RETURNS TABLE (outcome text, response json)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_bookmark_command_v1(p_log, p_answer, p_row);
$$;
REVOKE EXECUTE ON FUNCTION api.community_bookmark_command_v2(jsonb, jsonb,
    jsonb) FROM PUBLIC;

CREATE FUNCTION api.community_subscribe_command_v2(
p_log jsonb, p_answer jsonb, p_row jsonb
)
RETURNS TABLE (outcome text, response json)
LANGUAGE sql VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.community_subscribe_command_v1(p_log, p_answer, p_row);
$$;
REVOKE EXECUTE ON FUNCTION api.community_subscribe_command_v2(jsonb, jsonb,
    jsonb) FROM PUBLIC;

COMMIT;
