-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

-- ADR 0126: every statement the application sends becomes a call to a
-- function in schema api, created by a numbered migration from this one on.
-- This migration makes the schema and the first shared helper; 053 and 054
-- add the pilot's functions.
--
-- The schema holds functions and nothing else. PUBLIC has no right on it,
-- and none on a function in it: each migration revokes EXECUTE from PUBLIC
-- on every function it creates (t/641 holds them to it). The role's default
-- privileges are set to do the same for the functions it creates from here
-- on. ALTER DEFAULT PRIVILEGES IN SCHEMA api would not: a per-schema entry
-- can only add to the role's defaults, never take away the EXECUTE that
-- PostgreSQL grants PUBLIC on every new function, so the REVOKE is the
-- role's, for this database.
--
-- api.core_canonical_json_v1 writes a jsonb value as JSON::MaybeXS writes
-- the same value with canonical => 1, utf8 => 1: keys sorted by code point,
-- no whitespace, strings escaped as Cpanel::JSON::XS escapes them (", \,
-- \b \f \n \r \t, other control characters as \u00xx, everything else as
-- UTF-8). The command log's response_hash and the audit chain's record_hash
-- are SHA-256 of that text, so a function that records either has to write
-- it byte for byte as Perl does; t/integration/
-- postgres-sql-function-canonical-json.t proves it on the golden fixtures of
-- t/325 and t/329 and on generated values before any function uses it.
-- Integers agree; a number written with an exponent does not (Perl writes
-- 1e+20 where jsonb keeps 100000000000000000000), and no hashed document
-- holds one. Called only by other api functions (a core_ helper).
--
-- CREATE FUNCTION takes no lock on a table; lock_timeout is set as every
-- migration sets it.

BEGIN;
SET LOCAL lock_timeout = '1s';

CREATE SCHEMA api;
REVOKE ALL ON SCHEMA api FROM PUBLIC;
ALTER DEFAULT PRIVILEGES REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;

CREATE FUNCTION api.core_canonical_json_v1(p_value jsonb)
RETURNS text
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
SET search_path = pg_catalog, pg_temp
SET plan_cache_mode = force_generic_plan
AS $$
SELECT CASE jsonb_typeof(p_value)
    WHEN 'object' THEN
        '{' || coalesce((
            SELECT string_agg(
                to_jsonb(member.key)::text || ':'
                    || api.core_canonical_json_v1(member.value),
                ',' ORDER BY member.key COLLATE "C")
            FROM jsonb_each(p_value) AS member
        ), '') || '}'
    WHEN 'array' THEN
        '[' || coalesce((
            SELECT string_agg(
                api.core_canonical_json_v1(element.value),
                ',' ORDER BY element.place)
            FROM jsonb_array_elements(p_value)
                WITH ORDINALITY AS element (value, place)
        ), '') || ']'
    ELSE p_value::text
END
$$;
REVOKE EXECUTE ON FUNCTION api.core_canonical_json_v1(jsonb) FROM PUBLIC;

COMMIT;
