-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

-- The 1.0 baseline (ADR 0150): the schema GPForum starts from, in 24 files:
-- the tables by area (1000 to 1010), the functions of api by area (1011 to
-- 1022), and every entry point with the owner's rights (1023). A change after
-- it is a new migration numbered after 1023; these files are never edited, as
-- the runner refuses an applied file that changed.
--
-- What every table here holds to. Ids are uuid, drawn by the application as
-- UUIDv7, so they sort by creation and a write needs no round trip to learn
-- its key. Text is text: a limit a column must keep is a CHECK, which names
-- the rule and changes without rewriting the table, where varchar(n) would do
-- neither. A closed set of values is text with a CHECK listing them, not an
-- enum type, so a new value is one constraint and not a type change every
-- function that names the type depends on. Every instant is timestamptz. Each
-- constraint carries PostgreSQL's conventional name (users_pkey,
-- users_status_check), because the code maps a violation to its constraint by
-- that name. An index is partial where every query that uses it states its
-- predicate, and covering (INCLUDE) where a hot page reads only those columns,
-- so the page can be read from the index alone, in keyset order. fillfactor is
-- lowered only on the tables whose rows are updated in place on the hot paths
-- (a session on each request, a thread and its counter on each reply, a rate
-- bucket on each limited action), so an update that changes no indexed column
-- finds room on its page and stays HOT.
--
-- This file holds what the rest stand on: the trigram extension the search
-- indexes use, schema api with no right for PUBLIC on it or on any function
-- its owner creates (ADR 0126, 0127), and the ledger of migrations.

BEGIN;
SET LOCAL lock_timeout = '1s';

CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA public;

CREATE SCHEMA api;
REVOKE ALL ON SCHEMA api FROM PUBLIC;
ALTER DEFAULT PRIVILEGES REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;

-- The migrations applied to this database, one row each. The runner writes the
-- row in the migration's own transaction, with the file's SHA-256, who applied
-- it and how long it took; a recorded file that changes later is refused, and
-- so is a database that records a migration the code does not have.
CREATE TABLE public.schema_versions (
    version text NOT NULL,
    description text NOT NULL,
    checksum text NOT NULL,
    applied_at timestamptz NOT NULL DEFAULT now(),
    applied_by text NOT NULL DEFAULT current_user,
    execution_ms integer,
    CONSTRAINT schema_versions_pkey PRIMARY KEY (version),
    CONSTRAINT schema_versions_execution_ms_check CHECK (execution_ms >= 0)
);
COMMENT ON TABLE public.schema_versions IS 'The migrations applied to this database, one row each.';

-- The monthly partitions of the append-only logs, as the partition window made
-- them. gpforum migrate and the daily maintenance timer keep the current month
-- and the next two (ADR 0113); a partition is detached or dropped only as the
-- owner decides.
CREATE TABLE public.partition_registry (
    table_name text NOT NULL,
    partition_name text NOT NULL,
    range_start timestamptz NOT NULL,
    range_end timestamptz NOT NULL,
    state text NOT NULL DEFAULT 'planned',
    created_at timestamptz NOT NULL DEFAULT now(),
    detached_at timestamptz,
    archived_at timestamptz,
    CONSTRAINT partition_registry_pkey PRIMARY KEY (table_name, partition_name),
    CONSTRAINT partition_registry_range_check CHECK (range_end > range_start),
    CONSTRAINT partition_registry_state_check CHECK (state IN ('planned', 'created', 'detached', 'archived', 'dropped'))
);
COMMENT ON TABLE public.partition_registry IS 'The monthly partitions of the append-only logs, as the partition window made them.';

-- The most statements and transactions each endpoint may send per request.
-- gpforum migrate syncs them from the code; the readiness check and the budget
-- tests compare a request's counts with them.
CREATE TABLE public.endpoint_query_budgets (
    endpoint_name text NOT NULL,
    max_queries integer NOT NULL,
    max_transactions integer NOT NULL DEFAULT 1,
    notes text NOT NULL DEFAULT '',
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT endpoint_query_budgets_pkey PRIMARY KEY (endpoint_name),
    CONSTRAINT endpoint_query_budgets_queries_check CHECK (max_queries > 0),
    CONSTRAINT endpoint_query_budgets_transactions_check CHECK (max_transactions > 0)
);
COMMENT ON TABLE public.endpoint_query_budgets IS 'The most statements and transactions each endpoint may send per request.';

COMMIT;
