-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause

-- Members and how they sign in: accounts, credentials, sessions, single-use
-- tokens, the second factor, the rate limits and the address bans. Nothing
-- here holds a secret in the clear: passwords are Argon2 hashes, tokens and
-- recovery codes SHA-256 hashes, and the TOTP secret is sealed with a key from
-- the settings file.

BEGIN;
SET LOCAL lock_timeout = '1s';

-- A member: identity, status, preferences and the profile they show. id is a
-- UUIDv7 drawn by the application; username and the normalized email are
-- unique; version and permission_version count changes, so a cached viewer can
-- tell it is stale.
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
    CONSTRAINT users_pkey PRIMARY KEY (id),
    CONSTRAINT users_email_normalized_key UNIQUE (email_normalized),
    CONSTRAINT users_username_key UNIQUE (username),
    CONSTRAINT users_bio_length_check CHECK (char_length(bio) <= 500),
    CONSTRAINT users_permission_version_check CHECK (permission_version > 0),
    CONSTRAINT users_preferred_locale_check CHECK (preferred_locale IN ('en', 'it')),
    CONSTRAINT users_preferred_theme_check CHECK (preferred_theme IN ('auto', 'default', 'dark', 'high_contrast')),
    CONSTRAINT users_preferred_timezone_length_check CHECK (preferred_timezone IS NULL OR (length(preferred_timezone) >= 1 AND length(preferred_timezone) <= 64)),
    CONSTRAINT users_status_check CHECK (status IN ('pending', 'active', 'suspended', 'deleted')),
    CONSTRAINT users_trust_level_check CHECK (trust_level >= 0),
    CONSTRAINT users_version_check CHECK (version > 0)
);
CREATE INDEX idx_users_status_created_at
    ON public.users (status, created_at);
COMMENT ON TABLE public.users IS 'A member: identity, status, preferences and the profile they show.';

-- A member's password hashes, at most one active at a time
-- (idx_credentials_active_password_unique); the type also admits totp and
-- webauthn, which nothing writes yet.
CREATE TABLE public.credentials (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    type text NOT NULL,
    secret_hash text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    revoked_at timestamptz,
    CONSTRAINT credentials_pkey PRIMARY KEY (id),
    CONSTRAINT credentials_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users (id),
    CONSTRAINT credentials_revoked_after_created_check CHECK (revoked_at IS NULL OR revoked_at >= created_at),
    CONSTRAINT credentials_type_check CHECK (type IN ('password', 'totp', 'webauthn'))
);
CREATE UNIQUE INDEX idx_credentials_active_password_unique
    ON public.credentials (user_id)
    WHERE revoked_at IS NULL
      AND type = 'password';
CREATE INDEX idx_credentials_user_type_active
    ON public.credentials (user_id, type)
    WHERE revoked_at IS NULL;
COMMENT ON TABLE public.credentials IS 'A member''s password hashes, at most one active at a time (idx_credentials_active_password_unique); the type also admits totp and webauthn, which nothing writes yet.';

-- A signed-in browser: the SHA-256 of its token, never the token, and when it
-- was last seen. fillfactor 90 leaves room on each page for the last-seen
-- update to stay a HOT update.
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
    CONSTRAINT sessions_pkey PRIMARY KEY (session_id),
    CONSTRAINT sessions_session_hash_key UNIQUE (session_hash),
    CONSTRAINT sessions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users (id),
    CONSTRAINT sessions_expires_after_created_check CHECK (expires_at > created_at),
    CONSTRAINT sessions_revoked_after_created_check CHECK (revoked_at IS NULL OR revoked_at >= created_at)
)
WITH (fillfactor = 90);
CREATE INDEX idx_sessions_active
    ON public.sessions (session_id)
    WHERE revoked_at IS NULL;
CREATE INDEX idx_sessions_lookup
    ON public.sessions (session_id, expires_at, revoked_at);
CREATE INDEX idx_sessions_user_revoked_expires
    ON public.sessions (user_id, revoked_at, expires_at);
COMMENT ON TABLE public.sessions IS 'A signed-in browser: the SHA-256 of its token, never the token, and when it was last seen.';

-- Single-use tokens for password resets, email changes and email verification,
-- kept as hashes. At most one unused token per member and kind.
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
    CONSTRAINT identity_tokens_pkey PRIMARY KEY (token_id),
    CONSTRAINT identity_tokens_hash_key UNIQUE (token_hash),
    CONSTRAINT identity_tokens_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users (id),
    CONSTRAINT identity_tokens_expires_after_created_check CHECK (expires_at > created_at),
    CONSTRAINT identity_tokens_type_check CHECK (token_type IN ('password_reset', 'email_change', 'email_verification')),
    CONSTRAINT identity_tokens_used_after_created_check CHECK (used_at IS NULL OR used_at >= created_at)
);
CREATE INDEX idx_identity_tokens_active_lookup
    ON public.identity_tokens (token_hash, token_type, expires_at)
    WHERE used_at IS NULL;
CREATE UNIQUE INDEX idx_identity_tokens_open_user_type
    ON public.identity_tokens (user_id, token_type)
    WHERE used_at IS NULL
      AND user_id IS NOT NULL;
CREATE INDEX idx_identity_tokens_user_type_created
    ON public.identity_tokens (user_id, token_type, created_at DESC);
COMMENT ON TABLE public.identity_tokens IS 'Single-use tokens for password resets, email changes and email verification, kept as hashes.';

-- A member's time-based one-time password (TOTP, RFC 6238): the secret sealed
-- with a key from the settings file, and the last step a code was accepted
-- for, so no code is accepted twice.
CREATE TABLE public.second_factors (
    user_id uuid NOT NULL,
    state text NOT NULL,
    secret_sealed text NOT NULL,
    key_id text NOT NULL,
    last_step bigint NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL,
    confirmed_at timestamptz,
    updated_at timestamptz NOT NULL,
    CONSTRAINT second_factors_pkey PRIMARY KEY (user_id),
    CONSTRAINT second_factors_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users (id) ON DELETE CASCADE,
    CONSTRAINT second_factors_confirmed_check CHECK ((state = 'active') = (confirmed_at IS NOT NULL)),
    CONSTRAINT second_factors_key_id_check CHECK (length(key_id) >= 1 AND length(key_id) <= 64),
    CONSTRAINT second_factors_last_step_check CHECK (last_step >= 0),
    CONSTRAINT second_factors_secret_sealed_check CHECK (length(secret_sealed) >= 1 AND length(secret_sealed) <= 400),
    CONSTRAINT second_factors_state_check CHECK (state IN ('pending', 'active'))
);
CREATE INDEX idx_second_factors_key_id
    ON public.second_factors (key_id);
COMMENT ON TABLE public.second_factors IS 'A member''s time-based one-time password (TOTP, RFC 6238): the secret sealed with a key from the settings file, and the last step a code was accepted for, so no code is accepted twice.';

-- The second step of a sign-in whose password verified: answered within five
-- minutes and five tries.
CREATE TABLE public.second_factor_challenges (
    challenge_id uuid NOT NULL,
    token_hash text NOT NULL,
    user_id uuid NOT NULL,
    credential_id uuid NOT NULL,
    created_at timestamptz NOT NULL,
    expires_at timestamptz NOT NULL,
    failed_attempts integer NOT NULL DEFAULT 0,
    closed_at timestamptz,
    CONSTRAINT second_factor_challenges_pkey PRIMARY KEY (challenge_id),
    CONSTRAINT second_factor_challenges_token_hash_key UNIQUE (token_hash),
    CONSTRAINT second_factor_challenges_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users (id) ON DELETE CASCADE,
    CONSTRAINT second_factor_challenges_expiry_check CHECK (expires_at > created_at),
    CONSTRAINT second_factor_challenges_failed_attempts_check CHECK (failed_attempts >= 0)
);
CREATE INDEX idx_second_factor_challenges_user
    ON public.second_factor_challenges (user_id, created_at);
COMMENT ON TABLE public.second_factor_challenges IS 'The second step of a sign-in whose password verified: answered within five minutes and five tries.';

-- The ten single-use recovery codes of a member's second factor, as SHA-256
-- hashes.
CREATE TABLE public.second_factor_recovery_codes (
    user_id uuid NOT NULL,
    code_hash text NOT NULL,
    created_at timestamptz NOT NULL,
    used_at timestamptz,
    CONSTRAINT second_factor_recovery_codes_pkey PRIMARY KEY (user_id, code_hash),
    CONSTRAINT second_factor_recovery_codes_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users (id) ON DELETE CASCADE,
    CONSTRAINT second_factor_recovery_codes_code_hash_check CHECK (code_hash ~ '^[0-9a-f]{64}$')
);
COMMENT ON TABLE public.second_factor_recovery_codes IS 'The ten single-use recovery codes of a member''s second factor, as SHA-256 hashes.';

-- Whether staff must sign in with a second factor: one row (singleton).
CREATE TABLE public.second_factor_policy (
    singleton boolean NOT NULL DEFAULT true,
    staff_required boolean NOT NULL,
    updated_by_user_id uuid,
    updated_at timestamptz NOT NULL,
    CONSTRAINT second_factor_policy_pkey PRIMARY KEY (singleton),
    CONSTRAINT second_factor_policy_updated_by_user_id_fkey FOREIGN KEY (updated_by_user_id) REFERENCES public.users (id) ON DELETE SET NULL,
    CONSTRAINT second_factor_policy_singleton_check CHECK (singleton)
);
COMMENT ON TABLE public.second_factor_policy IS 'Whether staff must sign in with a second factor: one row (singleton).';

-- Fixed-window counters of what an actor did, by scope and action. fillfactor
-- 90 keeps the counter updates HOT; expired windows are swept by
-- idx_rate_limit_buckets_expiry.
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
    CONSTRAINT rate_limit_buckets_pkey PRIMARY KEY (scope, actor_hash, action, window_started_at),
    CONSTRAINT rate_limit_buckets_blocked_count_check CHECK (blocked_count >= 0),
    CONSTRAINT rate_limit_buckets_expires_after_window_check CHECK (expires_at > window_started_at),
    CONSTRAINT rate_limit_buckets_observed_count_check CHECK (observed_count >= 0),
    CONSTRAINT rate_limit_buckets_window_seconds_check CHECK (window_seconds > 0)
)
WITH (fillfactor = 90);
CREATE INDEX idx_rate_limit_buckets_expiry
    ON public.rate_limit_buckets (expires_at);
CREATE INDEX idx_rate_limit_buckets_scope_action_window
    ON public.rate_limit_buckets (scope, action, window_started_at DESC);
COMMENT ON TABLE public.rate_limit_buckets IS 'Fixed-window counters of what an actor did, by scope and action.';

-- An address or CIDR range staff ban from registering, signing in or writing,
-- until it expires or is lifted. A request asks which live ban covers its
-- address with one GiST lookup.
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
    CONSTRAINT address_bans_pkey PRIMARY KEY (ban_id),
    CONSTRAINT address_bans_created_by_user_id_fkey FOREIGN KEY (created_by_user_id) REFERENCES public.users (id) ON DELETE SET NULL,
    CONSTRAINT address_bans_lifted_by_user_id_fkey FOREIGN KEY (lifted_by_user_id) REFERENCES public.users (id) ON DELETE SET NULL,
    CONSTRAINT address_bans_updated_by_user_id_fkey FOREIGN KEY (updated_by_user_id) REFERENCES public.users (id) ON DELETE SET NULL,
    CONSTRAINT address_bans_expiry_check CHECK (expires_at > created_at),
    CONSTRAINT address_bans_range_check CHECK (masklen(address_range::inet) >=
CASE family(address_range::inet)
    WHEN 4 THEN 16
    ELSE 32
END),
    CONSTRAINT address_bans_reason_check CHECK (length(reason) >= 1 AND length(reason) <= 500),
    CONSTRAINT address_bans_scope_check CHECK (scope IN ('registration', 'sign_in', 'writes'))
);
CREATE INDEX idx_address_bans_created
    ON public.address_bans (created_at DESC, ban_id DESC);
CREATE INDEX idx_address_bans_created_by
    ON public.address_bans (created_by_user_id);
CREATE INDEX idx_address_bans_lifted_by
    ON public.address_bans (lifted_by_user_id);
CREATE INDEX idx_address_bans_live_range
    ON public.address_bans USING GIST (address_range inet_ops)
    WHERE lifted_at IS NULL;
CREATE INDEX idx_address_bans_updated_by
    ON public.address_bans (updated_by_user_id);
COMMENT ON TABLE public.address_bans IS 'An address or CIDR range staff ban from registering, signing in or writing, until it expires or is lifted.';

COMMIT;
