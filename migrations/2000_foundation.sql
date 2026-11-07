-- SPDX-FileCopyrightText: 2026 GPForum Contributors
-- SPDX-License-Identifier: BSD-3-Clause

-- Fresh-database baseline: foundation.
-- Final definitions only; see migrations/README.md for the dependency order.

BEGIN;
SET LOCAL lock_timeout = '1s';

-- Keep the extension privileges of the established schema; subsequent
-- application functions are private by default.
CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA public;

CREATE SCHEMA api;
REVOKE ALL ON SCHEMA api FROM PUBLIC;
ALTER DEFAULT PRIVILEGES REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;

COMMENT ON EXTENSION pg_trgm IS 'text similarity measurement and index searching based on trigrams';

CREATE EXTENSION IF NOT EXISTS unaccent WITH SCHEMA public;

COMMENT ON EXTENSION unaccent IS 'text search dictionary that removes accents';

-- Italian stemming and stopwords, with accent folding on word tokens.
CREATE TEXT SEARCH CONFIGURATION public.gpforum_italian (COPY = pg_catalog.italian);
ALTER TEXT SEARCH CONFIGURATION public.gpforum_italian
    ALTER MAPPING FOR word, hword, hword_part
    WITH public.unaccent, pg_catalog.italian_stem;
COMMENT ON TEXT SEARCH CONFIGURATION public.gpforum_italian IS 'Search text in Italian: unaccent, then the Italian Snowball stemmer and its stopwords.';

CREATE TABLE public.schema_versions (
    version text NOT NULL,
    description text NOT NULL,
    checksum text NOT NULL,
    applied_at timestamptz NOT NULL DEFAULT now(),
    applied_by text NOT NULL DEFAULT CURRENT_USER,
    execution_ms integer,
    CONSTRAINT schema_versions_execution_ms_check CHECK (execution_ms >= 0),
    CONSTRAINT schema_versions_pkey PRIMARY KEY (version)
);
COMMENT ON TABLE public.schema_versions IS 'The migrations applied to this database, one row each.';

CREATE TABLE public.partition_registry (
    table_name text NOT NULL,
    partition_name text NOT NULL,
    range_start timestamptz NOT NULL,
    range_end timestamptz NOT NULL,
    state text NOT NULL DEFAULT 'planned',
    created_at timestamptz NOT NULL DEFAULT now(),
    detached_at timestamptz,
    archived_at timestamptz,
    CONSTRAINT partition_registry_range_check CHECK (range_end > range_start),
    CONSTRAINT partition_registry_state_check CHECK (state IN ('planned', 'created', 'detached', 'archived', 'dropped')),
    CONSTRAINT partition_registry_pkey PRIMARY KEY (table_name, partition_name)
);
COMMENT ON TABLE public.partition_registry IS 'The monthly partitions of the append-only logs, as the partition window made them.';

CREATE TABLE public.endpoint_query_budgets (
    endpoint_name text NOT NULL,
    max_queries integer NOT NULL,
    max_transactions integer NOT NULL DEFAULT 1,
    notes text NOT NULL DEFAULT '',
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT endpoint_query_budgets_queries_check CHECK (max_queries > 0),
    CONSTRAINT endpoint_query_budgets_transactions_check CHECK (max_transactions > 0),
    CONSTRAINT endpoint_query_budgets_pkey PRIMARY KEY (endpoint_name)
);
COMMENT ON TABLE public.endpoint_query_budgets IS 'The most statements and transactions each endpoint may send per request.';

COMMIT;
