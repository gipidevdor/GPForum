-- SPDX-FileCopyrightText: 2026 GPForum Contributors
-- SPDX-License-Identifier: BSD-3-Clause

-- Fresh-database baseline: identity.
-- Final definitions only; see migrations/README.md for the dependency order.

BEGIN;
SET LOCAL lock_timeout = '1s';

CREATE TABLE public.users (
    id uuid NOT NULL,
    username text NOT NULL,
    display_name text NOT NULL,
    email_normalized text NOT NULL,
    password_hash text NOT NULL,
    status text NOT NULL DEFAULT 'pending',
    trust_level integer NOT NULL DEFAULT 0,
    version bigint NOT NULL DEFAULT 1,
    permission_version bigint NOT NULL DEFAULT 1,
    email_verified_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    preferred_locale text NOT NULL DEFAULT 'en',
    preferred_theme text NOT NULL DEFAULT 'auto',
    preferred_timezone text,
    bio text NOT NULL DEFAULT '',
    CONSTRAINT users_bio_length_check CHECK (char_length(bio) <= 500),
    CONSTRAINT users_permission_version_check CHECK (permission_version > 0),
    CONSTRAINT users_preferred_locale_check CHECK (preferred_locale IN ('en', 'it')),
    CONSTRAINT users_preferred_theme_check CHECK (preferred_theme IN ('auto', 'default', 'dark', 'high_contrast')),
    CONSTRAINT users_preferred_timezone_length_check CHECK ((preferred_timezone IS NULL) OR ((length(preferred_timezone) >= 1) AND (length(preferred_timezone) <= 64))),
    CONSTRAINT users_status_check CHECK (status IN ('pending', 'active', 'suspended', 'deleted')),
    CONSTRAINT users_trust_level_check CHECK (trust_level >= 0),
    CONSTRAINT users_version_check CHECK (version > 0),
    CONSTRAINT users_email_normalized_key UNIQUE (email_normalized),
    CONSTRAINT users_pkey PRIMARY KEY (id),
    CONSTRAINT users_username_key UNIQUE (username)
);
COMMENT ON TABLE public.users IS 'A member: identity, status, preferences and the profile they show.';
COMMENT ON COLUMN public.users.version IS 'Counts the changes registration approval makes to the row; nothing reads it.';
COMMENT ON COLUMN public.users.permission_version IS 'Counts the permission changes registration approval makes; nothing reads it.';

CREATE INDEX idx_users_status_created_at ON public.users (status, created_at);

CREATE TABLE public.credentials (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    type text NOT NULL,
    secret_hash text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    revoked_at timestamptz,
    CONSTRAINT credentials_revoked_after_created_check CHECK ((revoked_at IS NULL) OR (revoked_at >= created_at)),
    CONSTRAINT credentials_type_check CHECK (type IN ('password', 'totp', 'webauthn')),
    CONSTRAINT credentials_pkey PRIMARY KEY (id)
);
COMMENT ON TABLE public.credentials IS 'A member''s password hashes, at most one active at a time (idx_credentials_active_password_unique); the type also admits totp and webauthn, which nothing writes yet.';

CREATE UNIQUE INDEX idx_credentials_active_password_unique ON public.credentials (user_id) WHERE revoked_at IS NULL AND type = 'password';

CREATE INDEX idx_credentials_user_type_active ON public.credentials (user_id, type) WHERE revoked_at IS NULL;

CREATE TABLE public.sessions (
    session_id uuid NOT NULL,
    user_id uuid NOT NULL,
    session_hash text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    last_seen_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz NOT NULL,
    revoked_at timestamptz,
    ip_hash text,
    user_agent_hash text,
    CONSTRAINT sessions_expires_after_created_check CHECK (expires_at > created_at),
    CONSTRAINT sessions_revoked_after_created_check CHECK ((revoked_at IS NULL) OR (revoked_at >= created_at)),
    CONSTRAINT sessions_pkey PRIMARY KEY (session_id),
    CONSTRAINT sessions_session_hash_key UNIQUE (session_hash)
)
WITH (fillfactor = 90);
COMMENT ON TABLE public.sessions IS 'A signed-in browser: the SHA-256 of its token, never the token, and when it was last seen.';

CREATE INDEX idx_sessions_user_revoked_expires ON public.sessions (user_id, revoked_at, expires_at);

CREATE TABLE public.identity_tokens (
    token_id uuid NOT NULL,
    user_id uuid,
    token_type text NOT NULL,
    token_hash text NOT NULL,
    email_normalized text,
    created_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz NOT NULL,
    used_at timestamptz,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    CONSTRAINT identity_tokens_expires_after_created_check CHECK (expires_at > created_at),
    CONSTRAINT identity_tokens_type_check CHECK (token_type IN ('password_reset', 'email_change', 'email_verification')),
    CONSTRAINT identity_tokens_used_after_created_check CHECK ((used_at IS NULL) OR (used_at >= created_at)),
    CONSTRAINT identity_tokens_hash_key UNIQUE (token_hash),
    CONSTRAINT identity_tokens_pkey PRIMARY KEY (token_id)
);
COMMENT ON TABLE public.identity_tokens IS 'Single-use tokens for password resets, email changes and email verification, kept as hashes.';

CREATE UNIQUE INDEX idx_identity_tokens_open_user_type ON public.identity_tokens (user_id, token_type) WHERE used_at IS NULL AND (user_id IS NOT NULL);

CREATE INDEX idx_identity_tokens_user_type_created ON public.identity_tokens (user_id, token_type, created_at DESC);

CREATE TABLE public.second_factors (
    user_id uuid NOT NULL,
    state text NOT NULL,
    secret_sealed text NOT NULL,
    key_id text NOT NULL,
    last_step bigint NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL,
    confirmed_at timestamptz,
    updated_at timestamptz NOT NULL,
    CONSTRAINT second_factors_confirmed_check CHECK ((state = 'active') = (confirmed_at IS NOT NULL)),
    CONSTRAINT second_factors_key_id_check CHECK ((length(key_id) >= 1) AND (length(key_id) <= 64)),
    CONSTRAINT second_factors_last_step_check CHECK (last_step >= 0),
    CONSTRAINT second_factors_secret_sealed_check CHECK ((length(secret_sealed) >= 1) AND (length(secret_sealed) <= 400)),
    CONSTRAINT second_factors_state_check CHECK (state IN ('pending', 'active')),
    CONSTRAINT second_factors_pkey PRIMARY KEY (user_id)
);
COMMENT ON TABLE public.second_factors IS 'A member''s time-based one-time password (TOTP, RFC 6238): the secret sealed with a key from the settings file, and the last step a code was accepted for, so no code is accepted twice.';

CREATE TABLE public.second_factor_challenges (
    challenge_id uuid NOT NULL,
    token_hash text NOT NULL,
    user_id uuid NOT NULL,
    credential_id uuid NOT NULL,
    created_at timestamptz NOT NULL,
    expires_at timestamptz NOT NULL,
    failed_attempts integer NOT NULL DEFAULT 0,
    closed_at timestamptz,
    CONSTRAINT second_factor_challenges_expiry_check CHECK (expires_at > created_at),
    CONSTRAINT second_factor_challenges_failed_attempts_check CHECK (failed_attempts >= 0),
    CONSTRAINT second_factor_challenges_pkey PRIMARY KEY (challenge_id),
    CONSTRAINT second_factor_challenges_token_hash_key UNIQUE (token_hash)
);
COMMENT ON TABLE public.second_factor_challenges IS 'The second step of a sign-in whose password verified: answered within five minutes and five tries.';

CREATE INDEX idx_second_factor_challenges_user ON public.second_factor_challenges (user_id, created_at);

CREATE TABLE public.second_factor_recovery_codes (
    user_id uuid NOT NULL,
    code_hash text NOT NULL,
    created_at timestamptz NOT NULL,
    used_at timestamptz,
    CONSTRAINT second_factor_recovery_codes_code_hash_check CHECK (code_hash ~ '^[0-9a-f]{64}$'),
    CONSTRAINT second_factor_recovery_codes_pkey PRIMARY KEY (user_id, code_hash)
);
COMMENT ON TABLE public.second_factor_recovery_codes IS 'The ten single-use recovery codes of a member''s second factor, as SHA-256 hashes.';

CREATE TABLE public.second_factor_policy (
    singleton boolean NOT NULL DEFAULT true,
    staff_required boolean NOT NULL,
    updated_by_user_id uuid,
    updated_at timestamptz NOT NULL,
    CONSTRAINT second_factor_policy_singleton_check CHECK (singleton),
    CONSTRAINT second_factor_policy_pkey PRIMARY KEY (singleton)
);
COMMENT ON TABLE public.second_factor_policy IS 'Whether staff must sign in with a second factor: one row (singleton).';

CREATE TABLE public.rate_limit_buckets (
    scope text NOT NULL,
    actor_hash text NOT NULL,
    action text NOT NULL,
    window_started_at timestamptz NOT NULL,
    window_seconds integer NOT NULL,
    observed_count integer NOT NULL DEFAULT 0,
    blocked_count integer NOT NULL DEFAULT 0,
    first_seen_at timestamptz NOT NULL DEFAULT now(),
    last_seen_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz NOT NULL,
    CONSTRAINT rate_limit_buckets_blocked_count_check CHECK (blocked_count >= 0),
    CONSTRAINT rate_limit_buckets_expires_after_window_check CHECK (expires_at > window_started_at),
    CONSTRAINT rate_limit_buckets_observed_count_check CHECK (observed_count >= 0),
    CONSTRAINT rate_limit_buckets_window_seconds_check CHECK (window_seconds > 0),
    CONSTRAINT rate_limit_buckets_pkey PRIMARY KEY (scope, actor_hash, action, window_started_at)
)
WITH (fillfactor = 90);
COMMENT ON TABLE public.rate_limit_buckets IS 'Fixed-window counters of what an actor did, by scope and action.';

CREATE INDEX idx_rate_limit_buckets_expiry ON public.rate_limit_buckets (expires_at);

CREATE TABLE public.address_bans (
    ban_id uuid NOT NULL,
    address_range cidr NOT NULL,
    scope text NOT NULL,
    reason text NOT NULL,
    created_at timestamptz NOT NULL,
    created_by_user_id uuid,
    expires_at timestamptz NOT NULL,
    updated_at timestamptz,
    updated_by_user_id uuid,
    lifted_at timestamptz,
    lifted_by_user_id uuid,
    CONSTRAINT address_bans_expiry_check CHECK (expires_at > created_at),
    CONSTRAINT address_bans_range_check CHECK (masklen((address_range)::inet) >=
CASE family((address_range)::inet)
    WHEN 4 THEN 16
    ELSE 32
END),
    CONSTRAINT address_bans_reason_check CHECK ((length(reason) >= 1) AND (length(reason) <= 500)),
    CONSTRAINT address_bans_scope_check CHECK (scope IN ('registration', 'sign_in', 'writes')),
    CONSTRAINT address_bans_pkey PRIMARY KEY (ban_id)
);
COMMENT ON TABLE public.address_bans IS 'An address or CIDR range staff ban from registering, signing in or writing, until it expires or is lifted.';

CREATE INDEX idx_address_bans_created_by ON public.address_bans (created_by_user_id);

CREATE INDEX idx_address_bans_lifted_by ON public.address_bans (lifted_by_user_id);

CREATE INDEX idx_address_bans_live_range ON public.address_bans USING gist (address_range inet_ops) WHERE lifted_at IS NULL;

CREATE INDEX idx_address_bans_updated_by ON public.address_bans (updated_by_user_id);

CREATE TABLE public.registration_policy (
    singleton boolean NOT NULL DEFAULT true,
    mode text NOT NULL DEFAULT 'open',
    approval_required boolean NOT NULL DEFAULT false,
    updated_at timestamptz NOT NULL DEFAULT now(),
    updated_by uuid,
    CONSTRAINT registration_policy_mode_check CHECK (mode IN ('open', 'invite', 'closed')),
    CONSTRAINT registration_policy_singleton_check CHECK (singleton),
    CONSTRAINT registration_policy_pkey PRIMARY KEY (singleton)
);
COMMENT ON TABLE public.registration_policy IS 'Registration mode and independent staff approval policy for new accounts.';

INSERT INTO public.registration_policy(singleton) VALUES (true);

CREATE TABLE public.registration_invitations (
    invitation_id uuid NOT NULL,
    token_hash text NOT NULL,
    email_normalized text NOT NULL,
    created_by uuid,
    created_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz NOT NULL,
    used_by uuid,
    used_at timestamptz,
    revoked_at timestamptz,
    CONSTRAINT registration_invitations_check CHECK (expires_at > created_at),
    CONSTRAINT registration_invitations_email_normalized_check CHECK ((length(email_normalized) >= 3) AND (length(email_normalized) <= 254)),
    CONSTRAINT registration_invitations_token_hash_check CHECK (token_hash ~ '^[0-9a-f]{64}$'),
    CONSTRAINT registration_invitations_pkey PRIMARY KEY (invitation_id),
    CONSTRAINT registration_invitations_token_hash_key UNIQUE (token_hash)
);
COMMENT ON TABLE public.registration_invitations IS 'Email-bound single-use invitation hashes; raw invitation secrets are never persisted.';

CREATE INDEX idx_registration_invitations_expiry ON public.registration_invitations (expires_at, invitation_id);

CREATE TABLE public.registration_reviews (
    user_id uuid NOT NULL,
    decision text NOT NULL DEFAULT 'pending',
    created_at timestamptz NOT NULL DEFAULT now(),
    decided_at timestamptz,
    decided_by uuid,
    CONSTRAINT registration_reviews_decision_check CHECK (decision IN ('pending', 'approved', 'rejected')),
    CONSTRAINT registration_reviews_pkey PRIMARY KEY (user_id)
);
COMMENT ON TABLE public.registration_reviews IS 'Independent staff admission decisions; email verification alone cannot approve an account.';

CREATE INDEX idx_registration_reviews_pending ON public.registration_reviews (created_at, user_id) WHERE decision = 'pending';

COMMIT;
