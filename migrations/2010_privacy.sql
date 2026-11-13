-- SPDX-FileCopyrightText: 2026 GPForum Contributors
-- SPDX-License-Identifier: BSD-3-Clause

-- Fresh-database baseline: privacy.
-- Final definitions only; see migrations/README.md for the dependency order.

BEGIN;
SET LOCAL lock_timeout = '1s';

CREATE TABLE public.deletion_requests (
    deletion_request_id uuid NOT NULL,
    requester_user_id uuid,
    resource_type text NOT NULL,
    resource_id uuid NOT NULL,
    request_type text NOT NULL,
    reason text NOT NULL DEFAULT '',
    status text NOT NULL DEFAULT 'pending',
    created_at timestamptz NOT NULL DEFAULT now(),
    completed_at timestamptz,
    CONSTRAINT deletion_requests_status_check CHECK (status IN ('pending', 'approved', 'rejected', 'completed', 'held')),
    CONSTRAINT deletion_requests_type_check CHECK (request_type IN ('soft_delete', 'anonymize', 'hard_purge')),
    CONSTRAINT deletion_requests_pkey PRIMARY KEY (deletion_request_id)
);
COMMENT ON TABLE public.deletion_requests IS 'A request to delete, anonymize or purge a resource, and its outcome.';

CREATE UNIQUE INDEX idx_deletion_requests_open_resource_unique ON public.deletion_requests (resource_type, resource_id, request_type) WHERE status IN ('pending', 'approved', 'held');

CREATE INDEX idx_deletion_requests_requester_created ON public.deletion_requests (requester_user_id, created_at DESC);

CREATE TABLE public.deletion_actions (
    deletion_action_id uuid NOT NULL,
    deletion_request_id uuid NOT NULL,
    actor_id uuid,
    action_type text NOT NULL,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT deletion_actions_type_check CHECK (action_type IN ('soft_deleted', 'anonymized', 'purged', 'held', 'released', 'hold_ended')),
    CONSTRAINT deletion_actions_pkey PRIMARY KEY (deletion_action_id)
);
COMMENT ON TABLE public.deletion_actions IS 'What was done for a deletion request, step by step.';

CREATE TABLE public.erasure_jobs (
    erasure_job_id uuid NOT NULL,
    deletion_request_id uuid NOT NULL,
    status text NOT NULL DEFAULT 'pending',
    scheduled_at timestamptz NOT NULL DEFAULT now(),
    completed_at timestamptz,
    last_error text,
    CONSTRAINT erasure_jobs_status_check CHECK (status IN ('pending', 'running', 'done', 'failed', 'cancelled')),
    CONSTRAINT erasure_jobs_pkey PRIMARY KEY (erasure_job_id)
);
COMMENT ON TABLE public.erasure_jobs IS 'The job that carries out a deletion request, one per request.';

CREATE UNIQUE INDEX idx_erasure_jobs_request_unique ON public.erasure_jobs (deletion_request_id);

CREATE TABLE public.export_requests (
    export_request_id uuid NOT NULL,
    requester_user_id uuid NOT NULL,
    subject_user_id uuid NOT NULL,
    export_type text NOT NULL,
    format text NOT NULL DEFAULT 'json',
    status text NOT NULL DEFAULT 'pending',
    created_at timestamptz NOT NULL DEFAULT now(),
    finished_at timestamptz,
    manifest jsonb NOT NULL DEFAULT '{}'::jsonb,
    CONSTRAINT export_requests_finished_after_created_check CHECK ((finished_at IS NULL) OR (finished_at >= created_at)),
    CONSTRAINT export_requests_format_check CHECK (format = 'json'),
    CONSTRAINT export_requests_status_check CHECK (status IN ('pending', 'running', 'completed', 'failed')),
    CONSTRAINT export_requests_type_check CHECK (export_type IN ('user_data', 'admin_content', 'moderation_audit')),
    CONSTRAINT export_requests_pkey PRIMARY KEY (export_request_id)
);
COMMENT ON TABLE public.export_requests IS 'A request to export a member''s data.';

CREATE UNIQUE INDEX idx_export_requests_pending_unique ON public.export_requests (requester_user_id, subject_user_id, export_type, format) WHERE status = 'pending';

CREATE INDEX idx_export_requests_subject_created ON public.export_requests (subject_user_id, created_at DESC);

CREATE TABLE public.retention_holds (
    retention_hold_id uuid NOT NULL,
    resource_type text NOT NULL,
    resource_id uuid NOT NULL,
    reason text NOT NULL,
    starts_at timestamptz NOT NULL DEFAULT now(),
    ends_at timestamptz,
    created_by uuid,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT retention_holds_window_check CHECK ((ends_at IS NULL) OR (ends_at > starts_at)),
    CONSTRAINT retention_holds_pkey PRIMARY KEY (retention_hold_id)
);
COMMENT ON TABLE public.retention_holds IS 'A hold that keeps a resource from deletion while it lasts, one active per resource.';

CREATE UNIQUE INDEX idx_retention_holds_active_resource_unique ON public.retention_holds (resource_type, resource_id) WHERE ends_at IS NULL;

COMMIT;
