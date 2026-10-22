-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

-- The records every write leaves: the command log that makes a command
-- idempotent, the event log, the outbox the workers deliver from, the dead
-- letters they give up on, and the hash-chained audit log. The two logs are
-- partitioned by month on created_at (ADR 0113); this file makes their DEFAULT
-- partitions, and gpforum migrate makes the window of months.

BEGIN;
SET LOCAL lock_timeout = '1s';

-- Each command a member sent, by its idempotency key: a replay answers what
-- the first run answered, from response_hash and the stored response.
CREATE TABLE public.command_log (
    command_id uuid NOT NULL,
    command_type text NOT NULL,
    actor_id uuid,
    correlation_id uuid NOT NULL,
    idempotency_key text NOT NULL,
    payload jsonb NOT NULL DEFAULT '{}'::jsonb,
    response_hash text,
    status text NOT NULL DEFAULT 'accepted',
    created_at timestamptz NOT NULL DEFAULT now(),
    handled_at timestamptz,
    CONSTRAINT command_log_pkey PRIMARY KEY (command_id),
    CONSTRAINT command_log_idempotency_key_key UNIQUE (idempotency_key),
    CONSTRAINT command_log_status_check CHECK (status IN ('accepted', 'rejected', 'handled', 'failed'))
);
CREATE INDEX idx_command_log_actor_created_at
    ON public.command_log (actor_id, created_at DESC);
CREATE INDEX idx_command_log_correlation
    ON public.command_log (correlation_id);
COMMENT ON TABLE public.command_log IS 'Each command a member sent, by its idempotency key: a replay answers what the first run answered, from response_hash and the stored response.';

-- The domain events, append-only, partitioned by month on created_at (ADR
-- 0113). The primary key carries created_at because a unique key on a
-- partitioned table must hold the partition key.
CREATE TABLE public.event_log (
    event_id uuid NOT NULL,
    event_type text NOT NULL,
    schema_version integer NOT NULL,
    aggregate_type text NOT NULL,
    aggregate_id uuid,
    aggregate_version bigint NOT NULL DEFAULT 1,
    actor_id uuid,
    correlation_id uuid NOT NULL,
    causation_id uuid,
    idempotency_key text NOT NULL,
    payload jsonb NOT NULL DEFAULT '{}'::jsonb,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT event_log_pkey PRIMARY KEY (event_id, created_at),
    CONSTRAINT event_log_aggregate_version_check CHECK (aggregate_version > 0),
    CONSTRAINT event_log_schema_version_check CHECK (schema_version > 0)
)
PARTITION BY RANGE (created_at);
CREATE TABLE public.event_log_default PARTITION OF public.event_log DEFAULT;
CREATE INDEX idx_event_log_aggregate_created_at
    ON public.event_log (aggregate_type, aggregate_id, created_at);
CREATE INDEX idx_event_log_aggregate_version
    ON public.event_log (aggregate_type, aggregate_id, aggregate_version);
CREATE INDEX idx_event_log_correlation
    ON public.event_log (correlation_id);
CREATE INDEX idx_event_log_created_at_brin
    ON public.event_log USING BRIN (created_at);
CREATE INDEX idx_event_log_idempotency_key
    ON public.event_log (idempotency_key);
CREATE INDEX idx_event_log_type_created_at
    ON public.event_log (event_type, created_at);
COMMENT ON TABLE public.event_log IS 'The domain events, append-only, partitioned by month on created_at (ADR 0113).';

-- The events a worker has claimed or handled: the claim, taken before the side
-- effect, is what keeps two workers from running it twice.
CREATE TABLE public.event_idempotency_keys (
    idempotency_key text NOT NULL,
    event_id uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    completed_at timestamptz,
    CONSTRAINT event_idempotency_keys_pkey PRIMARY KEY (idempotency_key)
);
CREATE INDEX idx_event_idempotency_keys_unclaimed
    ON public.event_idempotency_keys (created_at)
    WHERE completed_at IS NULL;
COMMENT ON TABLE public.event_idempotency_keys IS 'The events a worker has claimed or handled: the claim, taken before the side effect, is what keeps two workers from running it twice.';

-- The jobs and notifications an event queues, delivered at least once by the
-- workers. Partial indexes serve the claim (pending and failed, by
-- next_attempt_at), the reclaim of expired leases and the realtime poll.
CREATE TABLE public.outbox_messages (
    outbox_id uuid NOT NULL,
    event_id uuid NOT NULL,
    queue text NOT NULL,
    job_type text NOT NULL,
    idempotency_key text NOT NULL,
    payload jsonb NOT NULL DEFAULT '{}'::jsonb,
    available_at timestamptz NOT NULL DEFAULT now(),
    created_at timestamptz NOT NULL DEFAULT now(),
    locked_at timestamptz,
    attempts integer NOT NULL DEFAULT 0,
    status text NOT NULL DEFAULT 'pending',
    last_error text,
    next_attempt_at timestamptz NOT NULL DEFAULT now(),
    locked_by text,
    locked_until timestamptz,
    attempt_count integer NOT NULL DEFAULT 0,
    last_error_class text,
    failure_type text,
    CONSTRAINT outbox_messages_pkey PRIMARY KEY (outbox_id),
    CONSTRAINT outbox_messages_idempotency_key_key UNIQUE (idempotency_key),
    CONSTRAINT outbox_messages_attempt_count_check CHECK (attempt_count >= 0),
    CONSTRAINT outbox_messages_attempts_check CHECK (attempts >= 0),
    CONSTRAINT outbox_messages_status_check CHECK (status IN ('pending', 'running', 'done', 'failed', 'cancelled'))
);
CREATE INDEX idx_outbox_messages_claim_ready
    ON public.outbox_messages (next_attempt_at, created_at, outbox_id)
    WHERE status IN ('pending', 'failed');
CREATE INDEX idx_outbox_messages_realtime_poll
    ON public.outbox_messages (status, next_attempt_at, created_at, outbox_id)
    WHERE status = 'done';
CREATE INDEX idx_outbox_messages_retry_backlog
    ON public.outbox_messages (failure_type, next_attempt_at, created_at)
    WHERE status = 'failed';
CREATE INDEX idx_outbox_messages_stale_locks
    ON public.outbox_messages (locked_until, next_attempt_at, created_at, outbox_id)
    WHERE status = 'running';
CREATE INDEX idx_outbox_messages_status_created
    ON public.outbox_messages (status, created_at);
COMMENT ON TABLE public.outbox_messages IS 'The jobs and notifications an event queues, delivered at least once by the workers.';

-- Outbox messages that failed for good, one row per source, kept for an
-- operator to replay.
CREATE TABLE public.dead_letters (
    dead_letter_id uuid NOT NULL,
    source_table text NOT NULL,
    source_id uuid NOT NULL,
    payload jsonb NOT NULL DEFAULT '{}'::jsonb,
    error_class text NOT NULL,
    error_message text NOT NULL,
    retry_count integer NOT NULL DEFAULT 0,
    first_failed_at timestamptz NOT NULL DEFAULT now(),
    last_failed_at timestamptz NOT NULL DEFAULT now(),
    failure_type text NOT NULL DEFAULT 'transient',
    CONSTRAINT dead_letters_pkey PRIMARY KEY (dead_letter_id),
    CONSTRAINT dead_letters_retry_count_check CHECK (retry_count >= 0)
);
CREATE INDEX idx_dead_letters_failure_type
    ON public.dead_letters (failure_type, last_failed_at);
CREATE UNIQUE INDEX idx_dead_letters_source_unique
    ON public.dead_letters (source_table, source_id);
COMMENT ON TABLE public.dead_letters IS 'Outbox messages that failed for good, one row per source, kept for an operator to replay.';

-- The audit trail, hash-chained and append-only, partitioned by month on
-- created_at. idx_audit_log_chain_tip finds the chain's head without reading
-- the table.
CREATE TABLE public.audit_log (
    audit_id uuid NOT NULL,
    action text NOT NULL,
    schema_version integer NOT NULL,
    actor_id uuid,
    target_type text,
    target_id uuid,
    correlation_id uuid NOT NULL,
    previous_hash text,
    record_hash text NOT NULL DEFAULT '',
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT audit_log_pkey PRIMARY KEY (audit_id, created_at),
    CONSTRAINT audit_log_schema_version_check CHECK (schema_version > 0)
)
PARTITION BY RANGE (created_at);
CREATE TABLE public.audit_log_default PARTITION OF public.audit_log DEFAULT;
CREATE INDEX idx_audit_log_action_created_at
    ON public.audit_log (action, created_at);
CREATE INDEX idx_audit_log_actor_created_at
    ON public.audit_log (actor_id, created_at DESC);
CREATE INDEX idx_audit_log_chain_tip
    ON public.audit_log (created_at DESC, audit_id DESC);
CREATE INDEX idx_audit_log_correlation
    ON public.audit_log (correlation_id);
CREATE INDEX idx_audit_log_created_at_brin
    ON public.audit_log USING BRIN (created_at);
CREATE INDEX idx_audit_log_target_created_at
    ON public.audit_log (target_type, target_id, created_at);
COMMENT ON TABLE public.audit_log IS 'The audit trail, hash-chained and append-only, partitioned by month on created_at.';

-- The builds of a projection: at most one active per projection, and one per
-- source event.
CREATE TABLE public.projection_generations (
    generation_id uuid NOT NULL,
    projection_name text NOT NULL,
    built_from_event_id uuid,
    built_from_event_created_at timestamptz,
    is_active boolean NOT NULL DEFAULT false,
    status text NOT NULL DEFAULT 'building',
    created_at timestamptz NOT NULL DEFAULT now(),
    activated_at timestamptz,
    CONSTRAINT projection_generations_pkey PRIMARY KEY (generation_id),
    CONSTRAINT projection_generations_status_check CHECK (status IN ('building', 'ready', 'active', 'failed', 'retired'))
);
CREATE UNIQUE INDEX idx_projection_generations_one_active
    ON public.projection_generations (projection_name)
    WHERE is_active;
CREATE UNIQUE INDEX idx_projection_generations_source_unique
    ON public.projection_generations (projection_name, built_from_event_id)
    WHERE built_from_event_id IS NOT NULL;
COMMENT ON TABLE public.projection_generations IS 'The builds of a projection: at most one active per projection, and one per source event.';

COMMIT;
