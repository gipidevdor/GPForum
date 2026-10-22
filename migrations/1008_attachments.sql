-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

-- Uploaded files, their derived variants, what they are attached to, and
-- members' pictures.

BEGIN;
SET LOCAL lock_timeout = '1s';

-- An uploaded file: its object in storage, its media type and its scan. The
-- partial indexes serve the rescan of pending files and the backfill of files
-- only format-checked.
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
    CONSTRAINT attachments_pkey PRIMARY KEY (attachment_id),
    CONSTRAINT attachments_object_key_key UNIQUE (object_key),
    CONSTRAINT attachments_owner_user_id_fkey FOREIGN KEY (owner_user_id) REFERENCES public.users (id),
    CONSTRAINT attachments_byte_size_check CHECK (byte_size > 0),
    CONSTRAINT attachments_scan_status_check CHECK (scan_status IN ('pending', 'clean', 'infected', 'failed')),
    CONSTRAINT attachments_state_check CHECK (state IN ('intent', 'uploaded', 'available', 'quarantined', 'deleted'))
);
CREATE INDEX idx_attachments_format_checked
    ON public.attachments (scan_attempts, created_at, attachment_id)
    WHERE scan_status = 'clean'
      AND deleted_at IS NULL
      AND (scan_engine IS NULL OR scan_engine = 'format-check');
CREATE INDEX idx_attachments_owner_state
    ON public.attachments (owner_user_id, state, created_at DESC)
    WHERE deleted_at IS NULL;
CREATE INDEX idx_attachments_pending_scan
    ON public.attachments (scan_attempts, uploaded_at, attachment_id)
    WHERE scan_status = 'pending';
COMMENT ON TABLE public.attachments IS 'An uploaded file: its object in storage, its media type and its scan.';

-- The derived files of an attachment (a resized image), one per kind.
CREATE TABLE public.attachment_variants (
    attachment_variant_id uuid NOT NULL,
    attachment_id uuid NOT NULL,
    variant_type text NOT NULL,
    object_key text NOT NULL,
    media_type text NOT NULL,
    byte_size bigint NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT attachment_variants_pkey PRIMARY KEY (attachment_variant_id),
    CONSTRAINT attachment_variants_object_key_key UNIQUE (object_key),
    CONSTRAINT attachment_variants_variant_key UNIQUE (attachment_id, variant_type),
    CONSTRAINT attachment_variants_attachment_id_fkey FOREIGN KEY (attachment_id) REFERENCES public.attachments (attachment_id),
    CONSTRAINT attachment_variants_byte_size_check CHECK (byte_size > 0)
);
COMMENT ON TABLE public.attachment_variants IS 'The derived files of an attachment (a resized image), one per kind.';

-- What an attachment is attached to: a post, a thread or a profile.
CREATE TABLE public.attachment_links (
    attachment_link_id uuid NOT NULL,
    attachment_id uuid NOT NULL,
    target_type text NOT NULL,
    target_id uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT attachment_links_pkey PRIMARY KEY (attachment_link_id),
    CONSTRAINT attachment_links_target_key UNIQUE (attachment_id, target_type, target_id),
    CONSTRAINT attachment_links_attachment_id_fkey FOREIGN KEY (attachment_id) REFERENCES public.attachments (attachment_id),
    CONSTRAINT attachment_links_target_type_check CHECK (target_type IN ('post', 'thread', 'profile'))
);
CREATE INDEX idx_attachment_links_target
    ON public.attachment_links (target_type, target_id, attachment_id);
COMMENT ON TABLE public.attachment_links IS 'What an attachment is attached to: a post, a thread or a profile.';

-- The picture a member shows and the one waiting to replace it.
CREATE TABLE public.member_avatars (
    user_id uuid NOT NULL,
    attachment_id uuid,
    shown_at timestamptz,
    pending_attachment_id uuid,
    pending_state text,
    pending_at timestamptz,
    CONSTRAINT member_avatars_pkey PRIMARY KEY (user_id),
    CONSTRAINT member_avatars_attachment_id_fkey FOREIGN KEY (attachment_id) REFERENCES public.attachments (attachment_id),
    CONSTRAINT member_avatars_pending_attachment_id_fkey FOREIGN KEY (pending_attachment_id) REFERENCES public.attachments (attachment_id),
    CONSTRAINT member_avatars_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users (id) ON DELETE CASCADE,
    CONSTRAINT member_avatars_pending_check CHECK ((pending_attachment_id IS NULL) = (pending_state IS NULL)),
    CONSTRAINT member_avatars_pending_state_check CHECK (pending_state IN ('checking', 'unreadable')),
    CONSTRAINT member_avatars_shown_check CHECK ((attachment_id IS NULL) = (shown_at IS NULL))
);
CREATE INDEX idx_member_avatars_attachment
    ON public.member_avatars (attachment_id)
    WHERE attachment_id IS NOT NULL;
CREATE INDEX idx_member_avatars_pending_attachment
    ON public.member_avatars (pending_attachment_id)
    WHERE pending_attachment_id IS NOT NULL;
COMMENT ON TABLE public.member_avatars IS 'The picture a member shows and the one waiting to replace it.';

COMMIT;
