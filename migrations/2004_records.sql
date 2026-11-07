-- SPDX-FileCopyrightText: 2026 GPForum Contributors
-- SPDX-License-Identifier: BSD-3-Clause

-- Fresh-database baseline: records.
-- Final definitions only; see migrations/README.md for the dependency order.

BEGIN;
SET LOCAL lock_timeout = '1s';

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
    CONSTRAINT command_log_status_check CHECK (status IN ('accepted', 'rejected', 'handled', 'failed')),
    CONSTRAINT command_log_idempotency_key_key UNIQUE (idempotency_key),
    CONSTRAINT command_log_pkey PRIMARY KEY (command_id)
);
COMMENT ON TABLE public.command_log IS 'Each command a member sent, by its idempotency key: a replay answers what the first run answered, from response_hash and the stored response.';

CREATE INDEX idx_command_log_actor_created_at ON public.command_log (actor_id, created_at DESC);

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
    CONSTRAINT event_log_aggregate_version_check CHECK (aggregate_version > 0),
    CONSTRAINT event_log_schema_version_check CHECK (schema_version > 0),
    CONSTRAINT event_log_pkey PRIMARY KEY (event_id, created_at)
)
PARTITION BY RANGE (created_at);
COMMENT ON TABLE public.event_log IS 'The domain events, append-only, partitioned by month on created_at (ADR 0113).';

CREATE INDEX idx_event_log_aggregate_created_at ON public.event_log (aggregate_type, aggregate_id, created_at);

CREATE INDEX idx_event_log_aggregate_version ON public.event_log (aggregate_type, aggregate_id, aggregate_version);

CREATE INDEX idx_event_log_created_at_brin ON public.event_log USING BRIN (created_at);

CREATE INDEX idx_event_log_idempotency_key ON public.event_log (idempotency_key);

CREATE TABLE public.event_idempotency_keys (
    idempotency_key text NOT NULL,
    event_id uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    completed_at timestamptz,
    CONSTRAINT event_idempotency_keys_pkey PRIMARY KEY (idempotency_key)
);
COMMENT ON TABLE public.event_idempotency_keys IS 'The events a worker has claimed or handled: the claim, taken before the side effect, is what keeps two workers from running it twice.';

CREATE INDEX idx_event_idempotency_keys_unclaimed ON public.event_idempotency_keys (created_at) WHERE completed_at IS NULL;

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
    status text NOT NULL DEFAULT 'pending',
    last_error text,
    next_attempt_at timestamptz NOT NULL DEFAULT now(),
    locked_by text,
    locked_until timestamptz,
    attempt_count integer NOT NULL DEFAULT 0,
    last_error_class text,
    failure_type text,
    CONSTRAINT outbox_messages_attempt_count_check CHECK (attempt_count >= 0),
    CONSTRAINT outbox_messages_status_check CHECK (status IN ('pending', 'running', 'done', 'failed', 'cancelled')),
    CONSTRAINT outbox_messages_idempotency_key_key UNIQUE (idempotency_key),
    CONSTRAINT outbox_messages_pkey PRIMARY KEY (outbox_id)
);
COMMENT ON TABLE public.outbox_messages IS 'The jobs and notifications an event queues, delivered at least once by the workers.';

CREATE INDEX idx_outbox_messages_claim_ready ON public.outbox_messages (next_attempt_at, created_at, outbox_id) WHERE status IN ('pending', 'failed');

CREATE INDEX idx_outbox_messages_realtime_poll ON public.outbox_messages (status, next_attempt_at, created_at, outbox_id) WHERE status = 'done';

CREATE INDEX idx_outbox_messages_retry_backlog ON public.outbox_messages (failure_type, next_attempt_at, created_at) WHERE status = 'failed';

CREATE INDEX idx_outbox_messages_stale_locks ON public.outbox_messages (locked_until, next_attempt_at, created_at, outbox_id) WHERE status = 'running';

CREATE INDEX idx_outbox_messages_status_created ON public.outbox_messages (status, created_at);

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
    CONSTRAINT dead_letters_retry_count_check CHECK (retry_count >= 0),
    CONSTRAINT dead_letters_pkey PRIMARY KEY (dead_letter_id)
);
COMMENT ON TABLE public.dead_letters IS 'Outbox messages that failed for good, one row per source, kept for an operator to replay.';

CREATE UNIQUE INDEX idx_dead_letters_source_unique ON public.dead_letters (source_table, source_id);

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
    chain_key text,
    chain_position bigint,
    CONSTRAINT audit_log_schema_version_check CHECK (schema_version > 0),
    CONSTRAINT audit_log_pkey PRIMARY KEY (audit_id, created_at)
)
PARTITION BY RANGE (created_at);
COMMENT ON TABLE public.audit_log IS 'The audit trail, hash-chained and append-only, partitioned by month on created_at.';
COMMENT ON COLUMN public.audit_log.chain_key IS 'The chain the row belongs to: its target as type:id (ADR 0156); NULL for a row written before the chains were per aggregate.';
COMMENT ON COLUMN public.audit_log.chain_position IS 'The row''s place in its chain, dense from 1 (ADR 0156).';

CREATE INDEX idx_audit_log_action_created_at ON public.audit_log (action, created_at);

CREATE INDEX idx_audit_log_actor_created_at ON public.audit_log (actor_id, created_at DESC);

CREATE INDEX idx_audit_log_chain_key_position ON public.audit_log (chain_key, chain_position DESC) WHERE chain_key IS NOT NULL;

CREATE INDEX idx_audit_log_chain_tip ON public.audit_log (created_at DESC, audit_id DESC);

CREATE INDEX idx_audit_log_correlation ON public.audit_log (correlation_id);

CREATE INDEX idx_audit_log_created_at_brin ON public.audit_log USING BRIN (created_at);

CREATE INDEX idx_audit_log_target_created_at ON public.audit_log (target_type, target_id, created_at);

CREATE TABLE public.audit_log_default PARTITION OF public.audit_log DEFAULT;

CREATE TABLE public.event_log_default PARTITION OF public.event_log DEFAULT;

COMMIT;
