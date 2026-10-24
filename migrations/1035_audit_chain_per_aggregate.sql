-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

SET LOCAL lock_timeout = '5s';

-- ADR 0156: the audit chain is one chain per aggregate, linked at commit
-- under a lock on that aggregate alone, in insertion order.
--
-- Until now every audit row linked to "the newest row" of one chain for the
-- whole forum, chosen by created_at and audit_id -- both the caller's -- under
-- pg_advisory_xact_lock(2026060210), held to COMMIT by every audited write.
-- Two writers whose stamps were out of order left a row no later row linked
-- to (the chain forked), and every audited write waited for every other.
--
-- Each row now belongs to the chain of its target (chain_key, "type:id";
-- ":" for a row with no target) and takes the next chain_position in it;
-- previous_hash is the record_hash at the position before, so the order is
-- the stored one and no clock is involved. The lock is per chain key, so
-- writes to different aggregates do not wait for each other. record_hash is
-- the SHA-256 of the row's stored form (created_at in UTC with microseconds,
-- metadata as jsonb, schema_version as a number), which a reader recomputes
-- from the table: api.ops_audit_chain_verify_v2 walks a chain and reports a
-- gap, a broken link or a row whose hash is not its own. Rows written before
-- this migration keep their old links and NULL chain columns.
--
-- The four functions below are replaced in place, by name (ADR 0126, section
-- 2, amended by ADR 0156, and t/641's allowlist): a chain discipline must
-- change for every writer at once, the previous release's workers included,
-- or two disciplines fork the chain; their signatures and result types are
-- unchanged.

ALTER TABLE public.audit_log
    ADD COLUMN chain_key text,
    ADD COLUMN chain_position bigint;
COMMENT ON COLUMN public.audit_log.chain_key IS
    'The chain the row belongs to: its target as type:id (ADR 0156); NULL for a row written before the chains were per aggregate.';
COMMENT ON COLUMN public.audit_log.chain_position IS
    'The row''s place in its chain, dense from 1 (ADR 0156).';

-- gpforum:blocking-index a partitioned parent cannot be built concurrently
-- The index is partial on the key, which every existing row lacks, so the
-- build reads no row of the current partitions.
CREATE INDEX idx_audit_log_chain_key_position
    ON public.audit_log (chain_key, chain_position DESC)
    WHERE chain_key IS NOT NULL;

-- The chain a row belongs to: its target as type:id, ":" without one.
CREATE FUNCTION api.core_audit_chain_key_v1(p_target_type text, p_target_id text)
RETURNS text
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT coalesce(p_target_type, '') || ':' || coalesce(p_target_id, '')
$$;
REVOKE EXECUTE ON FUNCTION api.core_audit_chain_key_v1(text, text) FROM PUBLIC;

-- The stored form of an audit row and its SHA-256: every value as the table
-- holds it, created_at in UTC with microseconds, so the hash recomputes from
-- the row. What GPForum::Infrastructure::AuditRecord hashes for the same row.
CREATE FUNCTION api.core_audit_digest_v1(
    p_action text,
    p_actor_id uuid,
    p_audit_id uuid,
    p_correlation_id uuid,
    p_created_at timestamptz,
    p_metadata jsonb,
    p_previous_hash text,
    p_schema_version integer,
    p_target_id uuid,
    p_target_type text
)
RETURNS text
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT encode(sha256(convert_to(api.core_canonical_json_v1(jsonb_build_object(
    'action', p_action,
    'actor_id', p_actor_id::text,
    'audit_id', p_audit_id::text,
    'correlation_id', p_correlation_id::text,
    'created_at', to_char(p_created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
    'metadata', coalesce(p_metadata, '{}'::jsonb),
    'previous_hash', p_previous_hash,
    'schema_version', p_schema_version,
    'target_id', p_target_id::text,
    'target_type', p_target_type)), 'UTF8')), 'hex')
$$;
REVOKE EXECUTE ON FUNCTION api.core_audit_digest_v1(text, uuid, uuid, uuid, timestamptz, jsonb, text, integer, uuid, text)
    FROM PUBLIC;

-- The one implementation of the chained insert (ADR 0156): the row's chain
-- from its target, the chain's lock, the tip by position, the stored-form
-- hash, the row. A previous_hash the caller sent is not the link; the chain
-- decides it. Returns the hashed document with record_hash, chain_key and
-- chain_position.
CREATE OR REPLACE FUNCTION api.core_shared_append_audit_v1(p_audit jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE
    key text := api.core_audit_chain_key_v1(p_audit->>'target_type', p_audit->>'target_id');
    tip_hash text;
    tip_position bigint;
    stamp timestamptz := (p_audit->>'created_at')::timestamptz;
    document jsonb;
    chain_hash text;
BEGIN
    PERFORM pg_advisory_xact_lock(2026102401, hashtext(key));
    SELECT me.record_hash, me.chain_position INTO tip_hash, tip_position
        FROM public.audit_log me
        WHERE me.chain_key = key
        ORDER BY me.chain_position DESC LIMIT 1;
    tip_position := coalesce(tip_position, 0) + 1;
    chain_hash := api.core_audit_digest_v1(p_audit->>'action',
        (p_audit->>'actor_id')::uuid, (p_audit->>'audit_id')::uuid,
        (p_audit->>'correlation_id')::uuid, stamp,
        coalesce(p_audit->'metadata', '{}'::jsonb), tip_hash,
        (p_audit->>'schema_version')::integer, (p_audit->>'target_id')::uuid,
        p_audit->>'target_type');
    INSERT INTO public.audit_log (action, actor_id, audit_id, correlation_id,
        created_at, metadata, previous_hash, record_hash, schema_version,
        target_id, target_type, chain_key, chain_position)
    VALUES (p_audit->>'action', (p_audit->>'actor_id')::uuid,
        (p_audit->>'audit_id')::uuid, (p_audit->>'correlation_id')::uuid, stamp,
        coalesce(p_audit->'metadata', '{}'::jsonb), tip_hash, chain_hash,
        (p_audit->>'schema_version')::integer, (p_audit->>'target_id')::uuid,
        p_audit->>'target_type', key, tip_position);
    document := jsonb_build_object(
        'action', p_audit->>'action',
        'actor_id', p_audit->>'actor_id',
        'audit_id', p_audit->>'audit_id',
        'correlation_id', p_audit->>'correlation_id',
        'created_at', to_char(stamp AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
        'metadata', coalesce(p_audit->'metadata', '{}'::jsonb),
        'previous_hash', tip_hash,
        'schema_version', (p_audit->>'schema_version')::integer,
        'target_id', p_audit->>'target_id',
        'target_type', p_audit->>'target_type');
    RETURN document || jsonb_build_object('record_hash', chain_hash,
        'chain_key', key, 'chain_position', tip_position);
END $$;
REVOKE EXECUTE ON FUNCTION api.core_shared_append_audit_v1(jsonb) FROM PUBLIC;

-- The typed form of the same insert, for the forum's write steps.
CREATE OR REPLACE FUNCTION api.core_append_audit_v1(
    p_action text,
    p_actor_id text,
    p_audit_id text,
    p_correlation_id text,
    p_created_at text,
    p_metadata jsonb,
    p_schema_version integer,
    p_target_id text,
    p_target_type text
)
RETURNS jsonb
LANGUAGE sql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT api.core_shared_append_audit_v1(jsonb_build_object(
    'action', p_action,
    'actor_id', p_actor_id,
    'audit_id', p_audit_id,
    'correlation_id', p_correlation_id,
    'created_at', p_created_at,
    'metadata', coalesce(p_metadata, '{}'::jsonb),
    'schema_version', p_schema_version,
    'target_id', p_target_id,
    'target_type', p_target_type))
$$;
REVOKE EXECUTE ON FUNCTION api.core_append_audit_v1(text, text, text, text, text, jsonb, integer, text, text)
    FROM PUBLIC;

-- EventRecorder::record_audit for an audit whose id the record drew: the
-- row in its target's chain (no forum-wide lock); an id drawn twice is
-- written once more under a new id.
CREATE OR REPLACE FUNCTION api.core_record_audit_v1(
    p_action text,
    p_actor_id text,
    p_audit_id text,
    p_correlation_id text,
    p_created_at text,
    p_metadata jsonb,
    p_schema_version integer,
    p_target_id text,
    p_target_type text
)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE
    reported text;
BEGIN
    BEGIN
        RETURN api.core_append_audit_v1(p_action, p_actor_id, p_audit_id,
            p_correlation_id, p_created_at, p_metadata, p_schema_version,
            p_target_id, p_target_type);
    EXCEPTION WHEN unique_violation THEN
        GET STACKED DIAGNOSTICS reported = CONSTRAINT_NAME;
        IF NOT api.core_unique_on_v1(reported, 'audit_log_pkey') THEN
            RAISE;
        END IF;
        RETURN api.core_append_audit_v1(p_action, p_actor_id,
            api.core_uuid_v7_v1()::text, p_correlation_id, p_created_at,
            p_metadata, p_schema_version, p_target_id, p_target_type);
    END;
END
$$;
REVOKE EXECUTE ON FUNCTION api.core_record_audit_v1(text, text, text, text, text, jsonb, integer, text, text)
    FROM PUBLIC;

-- Appends a row to its target's chain. A caller's audit id (p_explicit) is
-- locked on its own, class 2026100311 (ADR 0116 as ADR 0156 amends it), so
-- two writers of one id cannot both miss each other across the partitions;
-- an id already stored, or drawn twice, is written under a new one.
CREATE OR REPLACE FUNCTION api.ops_record_audit_v1(p_audit jsonb, p_explicit boolean)
RETURNS TABLE (audit json)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
DECLARE document jsonb := p_audit; reported text;
BEGIN
    IF p_explicit THEN
        PERFORM pg_advisory_xact_lock(2026100311, hashtext(document->>'audit_id'));
        IF EXISTS (SELECT 1 FROM public.audit_log me
            WHERE me.audit_id = (document->>'audit_id')::uuid) THEN
            document := document || jsonb_build_object('audit_id',api.core_uuid_v7_v1()::text);
        END IF;
    END IF;
    BEGIN
        RETURN QUERY SELECT api.core_shared_append_audit_v1(document)::json;
    EXCEPTION WHEN unique_violation THEN
        GET STACKED DIAGNOSTICS reported = CONSTRAINT_NAME;
        IF NOT api.core_unique_on_v1(reported,'audit_log_pkey') THEN RAISE; END IF;
        document := document || jsonb_build_object('audit_id',api.core_uuid_v7_v1()::text);
        RETURN QUERY SELECT api.core_shared_append_audit_v1(document)::json;
    END;
END $$;
REVOKE EXECUTE ON FUNCTION api.ops_record_audit_v1(jsonb, boolean) FROM PUBLIC;

-- Walks one chain by position and answers each flaw, none for a sound
-- chain: a position that does not follow the one before, a previous_hash
-- that is not the hash of the row before, a record_hash that is not the
-- row's own. A month partition that retention dropped reads as a gap.
CREATE FUNCTION api.ops_audit_chain_verify_v1(p_chain_key text)
RETURNS TABLE (chain_position bigint, audit_id uuid, problem text)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
WITH chain AS (
    SELECT me.*,
        lag(me.record_hash) OVER (ORDER BY me.chain_position) AS hash_before,
        lag(me.chain_position) OVER (ORDER BY me.chain_position) AS position_before
    FROM public.audit_log me
    WHERE me.chain_key = p_chain_key
)
SELECT chain.chain_position, chain.audit_id, flaw.problem
FROM chain
CROSS JOIN LATERAL (VALUES
    (CASE WHEN chain.chain_position <> coalesce(chain.position_before, 0) + 1
        THEN 'position ' || chain.chain_position || ' follows '
            || coalesce(chain.position_before, 0) END),
    (CASE WHEN chain.previous_hash IS DISTINCT FROM chain.hash_before
        THEN 'previous_hash is not the hash of the row before' END),
    (CASE WHEN chain.record_hash <> api.core_audit_digest_v1(chain.action,
            chain.actor_id, chain.audit_id, chain.correlation_id,
            chain.created_at, chain.metadata, chain.previous_hash,
            chain.schema_version, chain.target_id, chain.target_type)
        THEN 'record_hash is not the hash of the row' END)
) AS flaw(problem)
WHERE flaw.problem IS NOT NULL
ORDER BY chain.chain_position, flaw.problem
$$;
REVOKE EXECUTE ON FUNCTION api.ops_audit_chain_verify_v1(text) FROM PUBLIC;

-- The entry point the catalogue calls (ADR 0127).
CREATE FUNCTION api.ops_audit_chain_verify_v2(p_chain_key text)
RETURNS TABLE (chain_position bigint, audit_id uuid, problem text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT * FROM api.ops_audit_chain_verify_v1(p_chain_key);
$$;
REVOKE EXECUTE ON FUNCTION api.ops_audit_chain_verify_v2(text) FROM PUBLIC;
