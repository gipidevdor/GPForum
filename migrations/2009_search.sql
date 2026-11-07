-- SPDX-FileCopyrightText: 2026 GPForum Contributors
-- SPDX-License-Identifier: BSD-3-Clause

-- Fresh-database baseline: search.
-- Final definitions only; see migrations/README.md for the dependency order.

BEGIN;
SET LOCAL lock_timeout = '1s';

CREATE TABLE public.search_documents (
    search_document_id uuid NOT NULL,
    entity_type text NOT NULL,
    entity_id uuid NOT NULL,
    space_id uuid,
    visibility text NOT NULL,
    permission_scope text NOT NULL,
    visibility_version bigint NOT NULL,
    permission_version bigint NOT NULL,
    language text NOT NULL DEFAULT 'public.gpforum_italian',
    title text NOT NULL,
    title_normalized text GENERATED ALWAYS AS (lower(title)) STORED NOT NULL,
    body text NOT NULL,
    search_vector tsvector NOT NULL,
    source_version bigint NOT NULL,
    indexed_at timestamptz NOT NULL DEFAULT now(),
    category_id uuid,
    author_user_id uuid,
    source_created_at timestamptz,
    CONSTRAINT search_documents_permission_version_check CHECK (permission_version > 0),
    CONSTRAINT search_documents_source_version_check CHECK (source_version > 0),
    CONSTRAINT search_documents_visibility_check CHECK (visibility IN ('public', 'members', 'private')),
    CONSTRAINT search_documents_visibility_version_check CHECK (visibility_version > 0),
    CONSTRAINT search_documents_entity_key UNIQUE (entity_type, entity_id),
    CONSTRAINT search_documents_pkey PRIMARY KEY (search_document_id)
);
COMMENT ON TABLE public.search_documents IS 'The searchable projection of threads and posts: the text, its tsvector and what decides who may read it.';

CREATE INDEX idx_search_documents_created ON public.search_documents (source_created_at DESC, entity_id DESC);

CREATE INDEX idx_search_documents_title_trgm ON public.search_documents USING GIN (title_normalized public.gin_trgm_ops);

CREATE INDEX idx_search_documents_vector ON public.search_documents USING GIN (search_vector);

COMMIT;
