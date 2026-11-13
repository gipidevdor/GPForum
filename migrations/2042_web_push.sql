-- SPDX-FileCopyrightText: 2026 GPForum Contributors
-- SPDX-License-Identifier: BSD-3-Clause

BEGIN;
SET LOCAL lock_timeout = '1s';

CREATE TABLE public.notification_push_subscriptions (
    subscription_id uuid PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    session_id uuid NOT NULL REFERENCES public.sessions(session_id) ON DELETE CASCADE,
    endpoint_hash text NOT NULL UNIQUE CHECK (endpoint_hash ~ '^[a-f0-9]{64}$'),
    envelope text NOT NULL CHECK (length(envelope) BETWEEN 32 AND 8192),
    provider text NOT NULL CHECK (length(provider) BETWEEN 3 AND 253),
    key_id text NOT NULL CHECK (key_id ~ '^[a-f0-9]{16}$'),
    kinds text[] NOT NULL CHECK (cardinality(kinds) BETWEEN 1 AND 4
        AND kinds <@ ARRAY['reply','mention','moderation','message']::text[]),
    active boolean NOT NULL DEFAULT false,
    challenge_hash text,
    challenge_expires_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    CHECK (active OR (challenge_hash IS NOT NULL AND challenge_expires_at IS NOT NULL))
);
CREATE INDEX notification_push_owner ON public.notification_push_subscriptions(user_id, subscription_id);
CREATE INDEX notification_push_session ON public.notification_push_subscriptions(session_id);
COMMENT ON TABLE public.notification_push_subscriptions IS 'Explicit device consent, bound to one live account session; capability URL and receiver keys are AEAD encrypted.';

CREATE TABLE public.notification_push_deliveries (
    delivery_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    subscription_id uuid NOT NULL REFERENCES public.notification_push_subscriptions(subscription_id) ON DELETE CASCADE,
    notification_id uuid NOT NULL,
    kind text NOT NULL CHECK (kind IN ('activation','alert')),
    event_type text,
    source_type text,
    source_id uuid,
    actor_id uuid,
    activation text,
    state text NOT NULL DEFAULT 'pending' CHECK (state IN ('pending','leased','accepted','cancelled','failed')),
    available_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz NOT NULL,
    lease_id uuid,
    lease_until timestamptz,
    attempts integer NOT NULL DEFAULT 0 CHECK (attempts BETWEEN 0 AND 8),
    created_at timestamptz NOT NULL DEFAULT now(),
    finished_at timestamptz,
    UNIQUE(subscription_id, notification_id)
);
CREATE INDEX notification_push_ready ON public.notification_push_deliveries(available_at, delivery_id)
    WHERE state IN ('pending','leased');
CREATE INDEX notification_push_device ON public.notification_push_deliveries(subscription_id, state);
CREATE INDEX notification_push_expiry ON public.notification_push_deliveries(expires_at) WHERE state IN ('pending','leased');
CREATE INDEX notification_push_retention ON public.notification_push_deliveries(finished_at) WHERE finished_at IS NOT NULL;
COMMENT ON TABLE public.notification_push_deliveries IS 'Independent transactional push outbox; accepted is provider acceptance, never proof of display or reading.';

CREATE FUNCTION api.core_notification_push_enabled_v1(p_user_id uuid,p_type text)
RETURNS boolean
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT EXISTS (
    SELECT 1 FROM public.notification_push_subscriptions d
    JOIN public.sessions s ON s.session_id=d.session_id AND s.user_id=d.user_id
    JOIN public.users u ON u.id=d.user_id
    WHERE d.user_id=p_user_id AND d.active
      AND api.core_notification_event_type_v2(p_type)=ANY(d.kinds)
      AND s.revoked_at IS NULL AND s.expires_at>now()
      AND u.status='active' AND u.deleted_at IS NULL
);
$$;
REVOKE EXECUTE ON FUNCTION api.core_notification_push_enabled_v1(p_user_id uuid,p_type text) FROM PUBLIC;

CREATE FUNCTION api.notification_push_register_v1(p_user_id uuid,p_session_id uuid,p_subscription_id uuid,
p_endpoint_hash text,p_envelope text,p_provider text,p_key_id text,p_kinds text[],
p_challenge_hash text,p_activation text)
RETURNS TABLE(result jsonb)
LANGUAGE plpgsql VOLATILE SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE owner uuid; device_count integer;
BEGIN
    PERFORM 1 FROM public.users u WHERE u.id=p_user_id AND u.status='active'
        AND u.deleted_at IS NULL FOR UPDATE;
    IF NOT FOUND THEN
        RETURN QUERY SELECT jsonb_build_object('status','unauthorized'); RETURN;
    END IF;
    -- Serialize binding creation with revocation. A mere EXISTS snapshot
    -- could insert a new generation after logout's deletion had scanned it.
    PERFORM 1 FROM public.sessions s
        WHERE s.session_id=p_session_id AND s.user_id=p_user_id
        AND s.revoked_at IS NULL AND s.expires_at>now() FOR SHARE;
    IF NOT FOUND THEN
        RETURN QUERY SELECT jsonb_build_object('status','unauthorized'); RETURN;
    END IF;
    SELECT d.user_id INTO owner FROM public.notification_push_subscriptions d
        WHERE d.endpoint_hash=p_endpoint_hash FOR UPDATE;
    IF owner IS NOT NULL AND owner<>p_user_id THEN
        RETURN QUERY SELECT jsonb_build_object('status','conflict'); RETURN;
    END IF;
    SELECT count(*) INTO device_count FROM public.notification_push_subscriptions d
        WHERE d.user_id=p_user_id AND d.endpoint_hash<>p_endpoint_hash;
    IF device_count>=10 THEN
        RETURN QUERY SELECT jsonb_build_object('status','limit'); RETURN;
    END IF;
    DELETE FROM public.notification_push_subscriptions d WHERE d.endpoint_hash=p_endpoint_hash;
    INSERT INTO public.notification_push_subscriptions(subscription_id,user_id,session_id,
        endpoint_hash,envelope,provider,key_id,kinds,challenge_hash,challenge_expires_at)
    VALUES(p_subscription_id,p_user_id,p_session_id,p_endpoint_hash,p_envelope,p_provider,
        p_key_id,p_kinds,p_challenge_hash,now()+interval '2 minutes');
    INSERT INTO public.notification_push_deliveries(subscription_id,notification_id,kind,activation,expires_at)
    VALUES(p_subscription_id,p_subscription_id,'activation',p_activation,now()+interval '2 minutes');
    RETURN QUERY SELECT jsonb_build_object('status','pending','subscription_id',p_subscription_id);
EXCEPTION WHEN unique_violation THEN
    RETURN QUERY SELECT jsonb_build_object('status','conflict');
END;
$$;
REVOKE EXECUTE ON FUNCTION api.notification_push_register_v1(p_user_id uuid,p_session_id uuid,p_subscription_id uuid,
p_endpoint_hash text,p_envelope text,p_provider text,p_key_id text,p_kinds text[],
p_challenge_hash text,p_activation text) FROM PUBLIC;

CREATE FUNCTION api.notification_push_register_v2(p_user_id uuid,p_session_id uuid,p_subscription_id uuid,
p_endpoint_hash text,p_envelope text,p_provider text,p_key_id text,p_kinds text[],
p_challenge_hash text,p_activation text)
RETURNS TABLE(result jsonb)
LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.notification_push_register_v1(p_user_id,p_session_id,p_subscription_id,p_endpoint_hash,p_envelope,p_provider,p_key_id,p_kinds,p_challenge_hash,p_activation);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_push_register_v2(p_user_id uuid,p_session_id uuid,p_subscription_id uuid,
p_endpoint_hash text,p_envelope text,p_provider text,p_key_id text,p_kinds text[],
p_challenge_hash text,p_activation text) FROM PUBLIC;

CREATE FUNCTION api.notification_push_confirm_v1(p_user_id uuid,p_session_id uuid,p_subscription_id uuid,p_challenge_hash text)
RETURNS TABLE(result jsonb)
LANGUAGE plpgsql VOLATILE SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    UPDATE public.notification_push_subscriptions d SET active=true,challenge_hash=NULL,
        challenge_expires_at=NULL
    WHERE d.subscription_id=p_subscription_id AND d.user_id=p_user_id
      AND d.session_id=p_session_id AND NOT d.active AND d.challenge_hash=p_challenge_hash
      AND d.challenge_expires_at>now()
      AND EXISTS(SELECT 1 FROM public.sessions s WHERE s.session_id=d.session_id
          AND s.user_id=p_user_id AND s.revoked_at IS NULL AND s.expires_at>now())
      AND EXISTS(SELECT 1 FROM public.users u WHERE u.id=p_user_id
          AND u.status='active' AND u.deleted_at IS NULL);
    IF NOT FOUND THEN RETURN QUERY SELECT jsonb_build_object('status','invalid'); RETURN; END IF;
    RETURN QUERY SELECT jsonb_build_object('status','active');
END;
$$;
REVOKE EXECUTE ON FUNCTION api.notification_push_confirm_v1(p_user_id uuid,p_session_id uuid,p_subscription_id uuid,p_challenge_hash text) FROM PUBLIC;

CREATE FUNCTION api.notification_push_confirm_v2(p_user_id uuid,p_session_id uuid,p_subscription_id uuid,p_challenge_hash text)
RETURNS TABLE(result jsonb)
LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.notification_push_confirm_v1(p_user_id,p_session_id,p_subscription_id,p_challenge_hash);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_push_confirm_v2(p_user_id uuid,p_session_id uuid,p_subscription_id uuid,p_challenge_hash text) FROM PUBLIC;

CREATE FUNCTION api.notification_push_devices_v1(p_user_id uuid)
RETURNS TABLE(subscription_id uuid,active boolean,kinds text[],key_id text)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT d.subscription_id,d.active,d.kinds,d.key_id FROM public.notification_push_subscriptions d
JOIN public.sessions s ON s.session_id=d.session_id
WHERE d.user_id=p_user_id AND s.revoked_at IS NULL AND s.expires_at>now()
ORDER BY d.created_at DESC,d.subscription_id LIMIT 10;
$$;
REVOKE EXECUTE ON FUNCTION api.notification_push_devices_v1(p_user_id uuid) FROM PUBLIC;

CREATE FUNCTION api.notification_push_devices_v2(p_user_id uuid)
RETURNS TABLE(subscription_id uuid,active boolean,kinds text[],key_id text)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.notification_push_devices_v1(p_user_id);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_push_devices_v2(p_user_id uuid) FROM PUBLIC;

CREATE FUNCTION api.notification_push_revoke_v1(p_user_id uuid,p_subscription_id uuid)
RETURNS TABLE(result jsonb)
LANGUAGE plpgsql VOLATILE SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    DELETE FROM public.notification_push_subscriptions d
    WHERE d.user_id=p_user_id AND d.subscription_id=p_subscription_id;
    RETURN QUERY SELECT jsonb_build_object('status','revoked');
END;
$$;
REVOKE EXECUTE ON FUNCTION api.notification_push_revoke_v1(p_user_id uuid,p_subscription_id uuid) FROM PUBLIC;

CREATE FUNCTION api.notification_push_revoke_v2(p_user_id uuid,p_subscription_id uuid)
RETURNS TABLE(result jsonb)
LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.notification_push_revoke_v1(p_user_id,p_subscription_id);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_push_revoke_v2(p_user_id uuid,p_subscription_id uuid) FROM PUBLIC;

CREATE FUNCTION api.notification_push_enqueue_v1(p_notification jsonb)
RETURNS TABLE(queued integer)
LANGUAGE plpgsql VOLATILE SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE device record; v_count integer:=0; v_kind text;
BEGIN
    v_kind:=api.core_notification_event_type_v2(p_notification->>'notification_type');
    IF v_kind IS NULL THEN RETURN QUERY SELECT 0; RETURN; END IF;
    FOR device IN SELECT d.subscription_id FROM public.notification_push_subscriptions d
        JOIN public.sessions s ON s.session_id=d.session_id
        JOIN public.users u ON u.id=d.user_id
        WHERE d.user_id=(p_notification->>'recipient_user_id')::uuid AND d.active
        AND v_kind=ANY(d.kinds) AND s.revoked_at IS NULL AND s.expires_at>now()
        AND u.status='active' AND u.deleted_at IS NULL
        ORDER BY d.subscription_id FOR UPDATE OF d LOOP
        IF EXISTS(SELECT 1 FROM public.notification_push_deliveries j
            WHERE j.subscription_id=device.subscription_id
            AND j.notification_id=(p_notification->>'notification_id')::uuid) THEN CONTINUE; END IF;
        -- Keep one waiting alert per device. Retain superseded ids for
        -- bounded replay protection; cleanup removes receipts after a day.
        UPDATE public.notification_push_deliveries j SET state='cancelled',finished_at=now()
        WHERE j.subscription_id=device.subscription_id AND j.kind='alert' AND j.state='pending';
        INSERT INTO public.notification_push_deliveries(subscription_id,notification_id,kind,
            event_type,source_type,source_id,actor_id,expires_at)
        VALUES(device.subscription_id,(p_notification->>'notification_id')::uuid,'alert',v_kind,
            p_notification->>'source_type',(p_notification->>'source_id')::uuid,
            (p_notification->'payload'->>'actor_id')::uuid,now()+interval '15 minutes')
        ON CONFLICT(subscription_id,notification_id) DO NOTHING;
        IF FOUND THEN v_count:=v_count+1; END IF;
    END LOOP;
    RETURN QUERY SELECT v_count;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.notification_push_enqueue_v1(p_notification jsonb) FROM PUBLIC;

CREATE FUNCTION api.notification_push_enqueue_v2(p_notification jsonb)
RETURNS TABLE(queued integer)
LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.notification_push_enqueue_v1(p_notification);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_push_enqueue_v2(p_notification jsonb) FROM PUBLIC;

CREATE FUNCTION api.notification_push_refresh_v1(p_lease_id uuid)
RETURNS TABLE(delivery_id bigint,subscription_id uuid,user_id uuid,endpoint_hash text,envelope text,
key_id text,kind text,activation text,remaining integer,attempts integer,viewer jsonb,placement jsonb,allowed boolean,source_type text)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT j.delivery_id,d.subscription_id,d.user_id,d.endpoint_hash,d.envelope,
        d.key_id,j.kind,j.activation,floor(extract(epoch FROM j.expires_at-now()))::integer,j.attempts,
        to_jsonb(v),CASE j.source_type
          WHEN 'post' THEN (SELECT to_jsonb(x) FROM api.forum_post_placement_v1(j.source_id) x)
          WHEN 'thread' THEN (SELECT to_jsonb(x) FROM api.forum_thread_placement_v1(j.source_id) x)
          ELSE NULL::jsonb END,
        (j.event_type NOT IN ('reply','mention') OR NOT EXISTS(SELECT 1 FROM api.community_relation_between_v1(d.user_id,j.actor_id)))
        AND NOT EXISTS(SELECT 1 FROM public.notification_inbox i WHERE i.notification_id=j.notification_id
            AND i.recipient_user_id=d.user_id AND i.read_at IS NOT NULL)
        AND (j.source_type<>'message' OR coalesce((SELECT x.participant
            FROM api.community_message_participant_v1(j.source_id,d.user_id) x),false)),j.source_type
    FROM public.notification_push_deliveries j
    JOIN public.notification_push_subscriptions d ON d.subscription_id=j.subscription_id
    LEFT JOIN LATERAL api.forum_resolve_viewer_v9(d.user_id) v ON true
    WHERE j.lease_id=p_lease_id AND j.state='leased' AND j.lease_until>now()
      AND j.expires_at>now()
      AND EXISTS(SELECT 1 FROM public.sessions a WHERE a.session_id=d.session_id
          AND a.user_id=d.user_id AND a.revoked_at IS NULL AND a.expires_at>now())
      AND EXISTS(SELECT 1 FROM public.users u WHERE u.id=d.user_id AND u.status='active' AND u.deleted_at IS NULL)
      AND ((j.kind='activation' AND NOT d.active AND d.challenge_expires_at>now())
        OR (j.kind='alert' AND d.active AND j.event_type=ANY(d.kinds)))
    ORDER BY j.delivery_id LIMIT 64;
$$;
REVOKE EXECUTE ON FUNCTION api.notification_push_refresh_v1(uuid) FROM PUBLIC;

CREATE FUNCTION api.notification_push_refresh_v2(p_lease_id uuid)
RETURNS TABLE(delivery_id bigint,subscription_id uuid,user_id uuid,endpoint_hash text,envelope text,
key_id text,kind text,activation text,remaining integer,attempts integer,viewer jsonb,placement jsonb,allowed boolean,source_type text)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.notification_push_refresh_v1(p_lease_id);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_push_refresh_v2(uuid) FROM PUBLIC;

CREATE FUNCTION api.notification_push_claim_v1(p_lease_id uuid,p_limit integer,p_per_provider integer)
RETURNS TABLE(delivery_id bigint,subscription_id uuid,user_id uuid,endpoint_hash text,envelope text,
key_id text,kind text,activation text,remaining integer,attempts integer,viewer jsonb,placement jsonb,allowed boolean,source_type text)
LANGUAGE plpgsql VOLATILE SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    WITH candidates AS MATERIALIZED (
        SELECT j.delivery_id,d.provider FROM public.notification_push_deliveries j
        JOIN public.notification_push_subscriptions d ON d.subscription_id=j.subscription_id
        JOIN public.sessions s ON s.session_id=d.session_id
        JOIN public.users u ON u.id=d.user_id
        WHERE j.state IN ('pending','leased') AND j.available_at<=now()
        AND (j.state='pending' OR j.lease_until<=now()) AND j.expires_at>now()
        AND j.attempts<8 AND s.revoked_at IS NULL AND s.expires_at>now()
        AND u.status='active' AND u.deleted_at IS NULL
        AND ((j.kind='activation' AND NOT d.active) OR
            (j.kind='alert' AND d.active AND j.event_type=ANY(d.kinds)))
        ORDER BY j.available_at,j.delivery_id LIMIT 256
    ), ranked AS (
        SELECT c.delivery_id,row_number() OVER(PARTITION BY c.provider ORDER BY c.delivery_id) AS n
        FROM candidates c
    ), picked AS (
        SELECT j.delivery_id FROM public.notification_push_deliveries j
        JOIN ranked r ON r.delivery_id=j.delivery_id
        WHERE r.n<=greatest(1,least(p_per_provider,16))
        ORDER BY j.delivery_id LIMIT greatest(1,least(p_limit,64))
        FOR UPDATE OF j SKIP LOCKED
    )
    UPDATE public.notification_push_deliveries j SET state='leased',lease_id=p_lease_id,
        lease_until=now()+interval '30 seconds',available_at=now()+interval '30 seconds',attempts=j.attempts+1
    FROM picked p WHERE j.delivery_id=p.delivery_id;
    RETURN QUERY SELECT j.delivery_id,d.subscription_id,d.user_id,d.endpoint_hash,d.envelope,
        d.key_id,j.kind,j.activation,floor(extract(epoch FROM j.expires_at-now()))::integer,j.attempts,
        NULL::jsonb,NULL::jsonb,true,j.source_type
    FROM public.notification_push_deliveries j
    JOIN public.notification_push_subscriptions d ON d.subscription_id=j.subscription_id
    WHERE j.lease_id=p_lease_id AND j.state='leased' ORDER BY j.delivery_id;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.notification_push_claim_v1(p_lease_id uuid,p_limit integer,p_per_provider integer) FROM PUBLIC;

CREATE FUNCTION api.notification_push_claim_v2(p_lease_id uuid,p_limit integer,p_per_provider integer)
RETURNS TABLE(delivery_id bigint,subscription_id uuid,user_id uuid,endpoint_hash text,envelope text,
key_id text,kind text,activation text,remaining integer,attempts integer,viewer jsonb,placement jsonb,allowed boolean,source_type text)
LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.notification_push_claim_v1(p_lease_id,p_limit,p_per_provider);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_push_claim_v2(p_lease_id uuid,p_limit integer,p_per_provider integer) FROM PUBLIC;

CREATE FUNCTION api.notification_push_finish_v1(p_delivery_id bigint,p_lease_id uuid,p_outcome text,p_retry_after integer)
RETURNS TABLE(changed boolean,outcome text)
LANGUAGE plpgsql VOLATILE SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE v_subscription uuid; v_outcome text;
BEGIN
    IF p_outcome NOT IN ('accepted','expired','retry','failed','cancelled') THEN
        RAISE EXCEPTION 'invalid push outcome' USING ERRCODE='22023';
    END IF;
    SELECT j.subscription_id INTO v_subscription FROM public.notification_push_deliveries j
    WHERE j.delivery_id=p_delivery_id AND j.lease_id=p_lease_id
        AND j.state='leased' AND j.lease_until>now() FOR UPDATE;
    IF NOT FOUND THEN RETURN QUERY SELECT false,NULL::text; RETURN; END IF;
    IF p_outcome='expired' THEN
        DELETE FROM public.notification_push_subscriptions d WHERE d.subscription_id=v_subscription;
        v_outcome:='expired';
    ELSE
        UPDATE public.notification_push_deliveries j SET
            state=CASE WHEN p_outcome='retry' AND j.attempts<8
                AND now()+make_interval(secs=>greatest(1,least(p_retry_after,86400)))<j.expires_at
                THEN 'pending' WHEN p_outcome='retry' THEN 'failed' ELSE p_outcome END,
            available_at=now()+make_interval(secs=>greatest(1,least(p_retry_after,86400))),
            finished_at=CASE WHEN p_outcome='retry' AND j.attempts<8
                AND now()+make_interval(secs=>greatest(1,least(p_retry_after,86400)))<j.expires_at
                THEN NULL ELSE now() END,lease_id=NULL,lease_until=NULL
        WHERE j.delivery_id=p_delivery_id RETURNING j.state INTO v_outcome;
    END IF;
    RETURN QUERY SELECT true,CASE WHEN v_outcome='pending' THEN 'retry' ELSE v_outcome END;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.notification_push_finish_v1(p_delivery_id bigint,p_lease_id uuid,p_outcome text,p_retry_after integer) FROM PUBLIC;

CREATE FUNCTION api.notification_push_finish_v2(p_delivery_id bigint,p_lease_id uuid,p_outcome text,p_retry_after integer)
RETURNS TABLE(changed boolean,outcome text)
LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.notification_push_finish_v1(p_delivery_id,p_lease_id,p_outcome,p_retry_after);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_push_finish_v2(p_delivery_id bigint,p_lease_id uuid,p_outcome text,p_retry_after integer) FROM PUBLIC;

CREATE FUNCTION api.notification_push_finish_batch_v1(p_outcomes jsonb)
RETURNS TABLE(delivery_id bigint,outcome text,changed boolean)
LANGUAGE plpgsql VOLATILE SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE item jsonb;
BEGIN
    IF jsonb_typeof(p_outcomes)<>'array' OR jsonb_array_length(p_outcomes)>64 THEN
        RAISE EXCEPTION 'invalid Push result batch' USING ERRCODE='22023';
    END IF;
    FOR item IN SELECT * FROM jsonb_array_elements(p_outcomes) LOOP
        RETURN QUERY SELECT (item->>'delivery_id')::bigint,f.outcome,f.changed
        FROM api.notification_push_finish_v1((item->>'delivery_id')::bigint,
            (item->>'lease_id')::uuid,item->>'outcome',(item->>'retry_after')::integer) f;
    END LOOP;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.notification_push_finish_batch_v1(jsonb) FROM PUBLIC;

CREATE FUNCTION api.notification_push_finish_batch_v2(p_outcomes jsonb)
RETURNS TABLE(delivery_id bigint,outcome text,changed boolean)
LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.notification_push_finish_batch_v1(p_outcomes);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_push_finish_batch_v2(jsonb) FROM PUBLIC;

CREATE FUNCTION api.notification_push_cleanup_v1()
RETURNS TABLE(removed integer)
LANGUAGE plpgsql VOLATILE SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE v_removed integer; v_expired integer;
BEGIN
    DELETE FROM public.notification_push_subscriptions d WHERE d.subscription_id IN (
        SELECT s.subscription_id FROM public.notification_push_subscriptions s
        JOIN public.sessions a ON a.session_id=s.session_id
        WHERE a.revoked_at IS NOT NULL OR a.expires_at<=now()
          OR (NOT s.active AND s.challenge_expires_at<=now())
        ORDER BY s.created_at LIMIT 100);
    DELETE FROM public.notification_push_deliveries j WHERE j.delivery_id IN (
        SELECT q.delivery_id FROM public.notification_push_deliveries q
        WHERE q.finished_at<now()-interval '1 day'
        ORDER BY q.finished_at LIMIT 500);
    GET DIAGNOSTICS v_removed=ROW_COUNT;
    DELETE FROM public.notification_push_deliveries j WHERE j.delivery_id IN (
        SELECT q.delivery_id FROM public.notification_push_deliveries q
        WHERE q.state IN ('pending','leased') AND q.expires_at<=now()
            AND (q.lease_until IS NULL OR q.lease_until<=now())
        ORDER BY q.expires_at LIMIT 500);
    GET DIAGNOSTICS v_expired=ROW_COUNT;
    RETURN QUERY SELECT v_removed+v_expired;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.notification_push_cleanup_v1() FROM PUBLIC;

CREATE FUNCTION api.notification_push_cleanup_v2()
RETURNS TABLE(removed integer)
LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.notification_push_cleanup_v1();
$$;
REVOKE EXECUTE ON FUNCTION api.notification_push_cleanup_v2() FROM PUBLIC;

CREATE FUNCTION api.core_notification_push_revoke_v1()
RETURNS trigger
LANGUAGE plpgsql VOLATILE SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
BEGIN
    IF TG_TABLE_NAME='sessions' THEN
        IF NEW.revoked_at IS NOT NULL THEN
            DELETE FROM public.notification_push_subscriptions d WHERE d.session_id=NEW.session_id;
        END IF;
    ELSE
        IF NEW.status<>'active' OR NEW.deleted_at IS NOT NULL THEN
            DELETE FROM public.notification_push_subscriptions d WHERE d.user_id=NEW.id;
        END IF;
    END IF;
    RETURN NEW;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.core_notification_push_revoke_v1() FROM PUBLIC;

CREATE TRIGGER notification_push_session_revoke AFTER UPDATE OF revoked_at ON public.sessions
FOR EACH ROW WHEN (NEW.revoked_at IS NOT NULL) EXECUTE FUNCTION api.core_notification_push_revoke_v1();
CREATE TRIGGER notification_push_account_revoke AFTER UPDATE OF status,deleted_at ON public.users
FOR EACH ROW EXECUTE FUNCTION api.core_notification_push_revoke_v1();

CREATE FUNCTION api.notification_delivery_plan_v5(p_user_id uuid,p_notification_type text)
RETURNS TABLE(event_type text,in_app boolean,email boolean,email_address text,locale text,web_push boolean)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT p.*,api.core_notification_push_enabled_v1(p_user_id,p_notification_type)
FROM api.notification_delivery_plan_v3(p_user_id,p_notification_type) p;
$$;
REVOKE EXECUTE ON FUNCTION api.notification_delivery_plan_v5(p_user_id uuid,p_notification_type text) FROM PUBLIC;

CREATE FUNCTION api.notification_delivery_plan_v6(p_user_id uuid,p_notification_type text)
RETURNS TABLE(event_type text,in_app boolean,email boolean,email_address text,locale text,web_push boolean)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.notification_delivery_plan_v5(p_user_id,p_notification_type);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_delivery_plan_v6(p_user_id uuid,p_notification_type text) FROM PUBLIC;

CREATE FUNCTION api.notification_fanout_candidates_v5(p_target_type text,
    p_target_id uuid,
    p_notification_type text,
    p_actor_id uuid,
    p_excluded_user_id uuid)
RETURNS TABLE(
    user_id uuid,
    in_app boolean,
    email boolean,
    email_address text,
    locale text,
    event_type text,
    silenced boolean,
    status text,
    suspended boolean,
    grants json,
    moderates boolean,
    listed uuid[],
    trust_level integer,
    web_push boolean
)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT s.user_id,
    coalesce(plan.in_app, true),
    coalesce(plan.email, false),
    plan.email_address,
    plan.locale,
    plan.event_type,
    p_actor_id IS NOT NULL AND s.user_id <> p_actor_id AND EXISTS (
        SELECT 1 FROM api.community_relation_between_v1(s.user_id, p_actor_id)),
    viewer.status,
    viewer.suspended,
    viewer.grants,
    viewer.moderates,
    viewer.listed,
    viewer.trust_level,
    api.core_notification_push_enabled_v1(s.user_id,p_notification_type)
FROM api.notification_subscribers_v5(p_target_type, p_target_id, p_notification_type) s
LEFT JOIN LATERAL api.notification_delivery_plan_v3(s.user_id, p_notification_type) plan
    ON true
LEFT JOIN LATERAL api.forum_resolve_viewer_v9(s.user_id) viewer ON true
WHERE p_excluded_user_id IS NULL OR s.user_id <> p_excluded_user_id
ORDER BY s.user_id
$$;
REVOKE EXECUTE ON FUNCTION api.notification_fanout_candidates_v5(p_target_type text,
    p_target_id uuid,
    p_notification_type text,
    p_actor_id uuid,
    p_excluded_user_id uuid) FROM PUBLIC;

CREATE FUNCTION api.notification_fanout_candidates_v6(p_target_type text,
    p_target_id uuid,
    p_notification_type text,
    p_actor_id uuid,
    p_excluded_user_id uuid)
RETURNS TABLE(
    user_id uuid,
    in_app boolean,
    email boolean,
    email_address text,
    locale text,
    event_type text,
    silenced boolean,
    status text,
    suspended boolean,
    grants json,
    moderates boolean,
    listed uuid[],
    trust_level integer,
    web_push boolean
)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.notification_fanout_candidates_v5(p_target_type,p_target_id,p_notification_type,p_actor_id,p_excluded_user_id);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_fanout_candidates_v6(p_target_type text,
    p_target_id uuid,
    p_notification_type text,
    p_actor_id uuid,
    p_excluded_user_id uuid) FROM PUBLIC;

CREATE FUNCTION api.notification_fanout_deliver_v3(p_recipients jsonb)
RETURNS TABLE(
    recipient_user_id uuid,
    outcome text,
    result jsonb,
    unread_count bigint,
    email_queued boolean,
    error text
)
LANGUAGE plpgsql VOLATILE SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE
    recipient jsonb;
    v_user uuid;
    v_outcome text;
    v_result jsonb;
    v_count bigint;
    v_uncounted text;
    v_mailed boolean;
BEGIN
    FOR recipient IN SELECT * FROM jsonb_array_elements(p_recipients) LOOP
        v_user := (recipient ->> 'recipient_user_id')::uuid;
        v_result := NULL;
        v_count := NULL;
        v_uncounted := NULL;
        v_mailed := false;
        BEGIN
            IF coalesce((recipient ->> 'in_app')::boolean, false) THEN
                SELECT d.result INTO v_result
                FROM api.notification_deliver_v1(recipient -> 'notification',
                    recipient -> 'inbox', recipient ->> 'idempotency_key') d;
                v_outcome := CASE WHEN (v_result ->> 'duplicate')::integer = 1
                    THEN 'duplicate' ELSE 'created' END;
            ELSE
                v_outcome := 'skipped';
            END IF;
            IF coalesce((recipient ->> 'web_push')::boolean, false) THEN
                PERFORM api.notification_push_enqueue_v1(recipient -> 'notification');
            END IF;
            IF coalesce((recipient ->> 'email')::boolean, false) THEN
                PERFORM api.ops_record_event_v1(recipient -> 'email_event',
                    recipient ->> 'email_outbox_id',
                    CASE WHEN jsonb_typeof(recipient -> 'email_outbox_extras') = 'object'
                        THEN recipient -> 'email_outbox_extras' END,
                    coalesce((recipient ->> 'email_explicit')::boolean, false));
                v_mailed := true;
            END IF;
            -- The count after the rows, in a savepoint of its own: a count
            -- that fails (a lock it waited for) leaves the delivery made, as
            -- it did when the count was a statement after the commit, and is
            -- answered as the badge's failure, not the recipient's.
            IF v_outcome <> 'skipped' THEN
                BEGIN
                    SELECT c.unread_count INTO v_count
                    FROM api.notification_unread_count_v7(v_user,
                        coalesce((recipient ->> 'filter_sources')::boolean, false),
                        coalesce((recipient ->> 'member')::boolean, false),
                        coalesce((recipient ->> 'global_read')::boolean, false),
                        (recipient ->> 'viewer_user_id')::uuid,
                        ARRAY(SELECT jsonb_array_elements_text(
                            coalesce(recipient -> 'category_ids', '[]'::jsonb)))::uuid[],
                        ARRAY(SELECT jsonb_array_elements_text(
                            coalesce(recipient -> 'space_ids', '[]'::jsonb)))::uuid[]) c;
                EXCEPTION WHEN OTHERS THEN
                    v_count := NULL;
                    v_uncounted := SQLERRM;
                END;
            END IF;
            RETURN QUERY SELECT v_user, v_outcome, v_result, v_count, v_mailed, v_uncounted;
        EXCEPTION WHEN OTHERS THEN
            RETURN QUERY SELECT v_user, 'failed'::text, NULL::jsonb, NULL::bigint, false, SQLERRM;
        END;
    END LOOP;
    RETURN;
END;
$$;
REVOKE EXECUTE ON FUNCTION api.notification_fanout_deliver_v3(p_recipients jsonb) FROM PUBLIC;

CREATE FUNCTION api.notification_fanout_deliver_v4(p_recipients jsonb)
RETURNS TABLE(
    recipient_user_id uuid,
    outcome text,
    result jsonb,
    unread_count bigint,
    email_queued boolean,
    error text
)
LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.notification_fanout_deliver_v3(p_recipients);
$$;
REVOKE EXECUTE ON FUNCTION api.notification_fanout_deliver_v4(p_recipients jsonb) FROM PUBLIC;

ALTER TABLE public.notification_push_deliveries SET (
    autovacuum_vacuum_scale_factor=0.02,autovacuum_analyze_scale_factor=0.01);

CREATE FUNCTION api.portability_export_parts_v31(p_user_id uuid)
RETURNS TABLE(document json) LANGUAGE sql STABLE SECURITY INVOKER
SET search_path=pg_catalog,pg_temp
SET plan_cache_mode=force_generic_plan
AS $$
SELECT (previous.document::jsonb || jsonb_build_object('push_devices',coalesce((
    SELECT jsonb_agg(jsonb_build_object('subscription_id',d.subscription_id,'active',d.active,
        'kinds',d.kinds,'created_at',d.created_at))
    FROM public.notification_push_subscriptions d WHERE d.user_id=p_user_id),'[]'::jsonb)))::json
FROM api.portability_export_parts_v29(p_user_id) previous;
$$;
REVOKE EXECUTE ON FUNCTION api.portability_export_parts_v31(uuid) FROM PUBLIC;
CREATE FUNCTION api.portability_export_parts_v32(p_user_id uuid)
RETURNS TABLE(document json) LANGUAGE sql STABLE SECURITY DEFINER
SET search_path=pg_catalog,pg_temp
SET plan_cache_mode=force_generic_plan
AS $$
SELECT * FROM api.portability_export_parts_v31(p_user_id);
$$;
REVOKE EXECUTE ON FUNCTION api.portability_export_parts_v32(uuid) FROM PUBLIC;

COMMIT;
