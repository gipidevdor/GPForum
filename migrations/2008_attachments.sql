-- SPDX-FileCopyrightText: 2026 GPForum Contributors
-- SPDX-License-Identifier: BSD-3-Clause

-- Fresh-database baseline: attachments.
-- Final definitions only; see migrations/README.md for the dependency order.

BEGIN;
SET LOCAL lock_timeout = '1s';

CREATE TABLE public.attachments (
    attachment_id uuid NOT NULL,
    owner_user_id uuid NOT NULL,
    object_key text NOT NULL,
    original_filename text NOT NULL,
    media_type text NOT NULL,
    byte_size bigint NOT NULL,
    checksum text NOT NULL,
    state text NOT NULL DEFAULT 'intent',
    scan_status text NOT NULL DEFAULT 'pending',
    created_at timestamptz NOT NULL DEFAULT now(),
    uploaded_at timestamptz,
    scanned_at timestamptz,
    quarantined_at timestamptz,
    deleted_at timestamptz,
    scan_engine text,
    scan_signature text,
    scan_attempts integer NOT NULL DEFAULT 0,
    scan_error text,
    CONSTRAINT attachments_byte_size_check CHECK (byte_size > 0),
    CONSTRAINT attachments_scan_status_check CHECK (scan_status IN ('pending', 'clean', 'infected', 'failed')),
    CONSTRAINT attachments_state_check CHECK (state IN ('intent', 'uploaded', 'available', 'quarantined', 'deleted')),
    CONSTRAINT attachments_object_key_key UNIQUE (object_key),
    CONSTRAINT attachments_pkey PRIMARY KEY (attachment_id)
);
COMMENT ON TABLE public.attachments IS 'An uploaded file: its object in storage, its media type and its scan.';

CREATE INDEX idx_attachments_format_checked ON public.attachments (scan_attempts, created_at, attachment_id) WHERE (scan_status = 'clean') AND (deleted_at IS NULL) AND ((scan_engine IS NULL) OR (scan_engine = 'format-check'));

CREATE INDEX idx_attachments_intent_created ON public.attachments (created_at) WHERE state = 'intent';

CREATE INDEX idx_attachments_live_checksum ON public.attachments (checksum) WHERE deleted_at IS NULL;

CREATE INDEX idx_attachments_owner_state ON public.attachments (owner_user_id, state, created_at DESC) WHERE deleted_at IS NULL;

CREATE INDEX idx_attachments_pending_scan ON public.attachments (scan_attempts, uploaded_at, attachment_id) WHERE scan_status = 'pending';

CREATE TABLE public.attachment_variants (
    attachment_variant_id uuid NOT NULL,
    attachment_id uuid NOT NULL,
    variant_type text NOT NULL,
    object_key text NOT NULL,
    media_type text NOT NULL,
    byte_size bigint NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT attachment_variants_byte_size_check CHECK (byte_size > 0),
    CONSTRAINT attachment_variants_object_key_key UNIQUE (object_key),
    CONSTRAINT attachment_variants_pkey PRIMARY KEY (attachment_variant_id),
    CONSTRAINT attachment_variants_variant_key UNIQUE (attachment_id, variant_type)
);
COMMENT ON TABLE public.attachment_variants IS 'The derived files of an attachment (a resized image), one per kind.';

CREATE TABLE public.attachment_links (
    attachment_link_id uuid NOT NULL,
    attachment_id uuid NOT NULL,
    target_type text NOT NULL,
    target_id uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT attachment_links_target_type_check CHECK (target_type IN ('post', 'thread', 'profile')),
    CONSTRAINT attachment_links_pkey PRIMARY KEY (attachment_link_id),
    CONSTRAINT attachment_links_target_key UNIQUE (attachment_id, target_type, target_id)
);
COMMENT ON TABLE public.attachment_links IS 'What an attachment is attached to: a post, a thread or a profile.';

CREATE INDEX idx_attachment_links_target ON public.attachment_links (target_type, target_id, attachment_id);

CREATE TABLE public.member_avatars (
    user_id uuid NOT NULL,
    attachment_id uuid,
    shown_at timestamptz,
    pending_attachment_id uuid,
    pending_state text,
    pending_at timestamptz,
    CONSTRAINT member_avatars_pending_check CHECK ((pending_attachment_id IS NULL) = (pending_state IS NULL)),
    CONSTRAINT member_avatars_pending_state_check CHECK (pending_state IN ('checking', 'unreadable')),
    CONSTRAINT member_avatars_shown_check CHECK ((attachment_id IS NULL) = (shown_at IS NULL)),
    CONSTRAINT member_avatars_pkey PRIMARY KEY (user_id)
);
COMMENT ON TABLE public.member_avatars IS 'The picture a member shows and the one waiting to replace it.';

CREATE TABLE public.attachment_objects (
    object_key text NOT NULL,
    attachment_id uuid,
    byte_size bigint NOT NULL,
    checksum text NOT NULL,
    complete boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT attachment_objects_byte_size_check CHECK ((byte_size >= 1) AND (byte_size <= 262144000)),
    CONSTRAINT attachment_objects_checksum_check CHECK (checksum ~ '^[0-9a-f]{64}$'),
    CONSTRAINT attachment_objects_object_key_check CHECK ((length(object_key) >= 1) AND (length(object_key) <= 512)),
    CONSTRAINT attachment_objects_pkey PRIMARY KEY (object_key)
);
COMMENT ON TABLE public.attachment_objects IS 'Immutable binary objects, published only after every chunk is present.';

CREATE INDEX attachment_objects_attachment ON public.attachment_objects (attachment_id) WHERE attachment_id IS NOT NULL;

CREATE TABLE public.attachment_object_chunks (
    object_key text NOT NULL,
    chunk_number integer NOT NULL,
    data bytea NOT NULL,
    CONSTRAINT attachment_object_chunks_chunk_number_check CHECK ((chunk_number >= 0) AND (chunk_number <= 249)),
    CONSTRAINT attachment_object_chunks_data_check CHECK ((octet_length(data) >= 1) AND (octet_length(data) <= 1048576)),
    CONSTRAINT attachment_object_chunks_pkey PRIMARY KEY (object_key, chunk_number)
);
ALTER TABLE ONLY public.attachment_object_chunks ALTER COLUMN data SET STORAGE EXTERNAL;
COMMENT ON TABLE public.attachment_object_chunks IS 'One MiB bytea chunks, indexed by object and sequence, cascaded with the object.';

CREATE TABLE public.attachment_content_reviews (
    attachment_id uuid NOT NULL,
    source_kind text NOT NULL,
    source_url text NOT NULL DEFAULT '',
    status text NOT NULL DEFAULT 'pending',
    reason text NOT NULL DEFAULT '',
    reviewed_by uuid,
    reviewed_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT attachment_content_reviews_reason_check CHECK (length(reason) <= 500),
    CONSTRAINT attachment_content_reviews_source_kind_check CHECK (source_kind IN ('original', 'authorized')),
    CONSTRAINT attachment_content_reviews_source_url_check CHECK (length(source_url) <= 2048),
    CONSTRAINT attachment_content_reviews_status_check CHECK (status IN ('pending', 'approved', 'rejected')),
    CONSTRAINT attachment_content_reviews_pkey PRIMARY KEY (attachment_id)
);
COMMENT ON TABLE public.attachment_content_reviews IS 'Provenance attestation and staff content decision, separate from malware scanning.';

CREATE INDEX attachment_content_pending ON public.attachment_content_reviews (created_at, attachment_id) WHERE status = 'pending';

CREATE TABLE public.attachment_content_blocks (
    checksum text NOT NULL,
    reason text NOT NULL,
    blocked_by uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT attachment_content_blocks_checksum_check CHECK (checksum ~ '^[0-9a-f]{64}$'),
    CONSTRAINT attachment_content_blocks_reason_check CHECK ((length(reason) >= 1) AND (length(reason) <= 500)),
    CONSTRAINT attachment_content_blocks_pkey PRIMARY KEY (checksum)
);
COMMENT ON TABLE public.attachment_content_blocks IS 'Exact SHA-256 matches of rejected content; altered files still require independent review.';

COMMIT;
