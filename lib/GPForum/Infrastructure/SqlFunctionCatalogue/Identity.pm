# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Infrastructure::SqlFunctionCatalogue::Identity;

use Const::Fast;
use Mojo::Base -base, -signatures;
use v5.40;

our $VERSION = '0.001';

const my %FUNCTION => (
    identity_passkey_begin =>
      { version => 2, parameters => [ input => 'jsonb' ], json => ['result'] },
    identity_passkey_consume =>
      { version => 2, parameters => [ input => 'jsonb' ], json => ['result'] },
    identity_passkey_list => {
        version    => 2,
        parameters => [ user_id => 'uuid', rp_id => 'text' ],
        json       => ['result']
    },
    identity_passkey_register =>
      { version => 2, parameters => [ input => 'jsonb' ], json => ['result'] },
    identity_passkey_resolve => {
        version    => 2,
        parameters => [ credential_id_b64 => 'text', rp_id => 'text' ],
        json       => ['result']
    },
    identity_passkey_advance => {
        version    => 2,
        parameters =>
          [ id => 'uuid', password_id => 'uuid', sign_count => 'bigint' ],
        json => ['result']
    },
    identity_passkey_revoke => {
        version    => 2,
        parameters => [
            user_id     => 'uuid',
            id          => 'uuid',
            password_id => 'uuid',
            session_id  => 'uuid'
        ],
        json => ['result']
    },
    identity_oidc_begin => {
        version    => 2,
        parameters => [
            state_hash   => 'text',
            binding_hash => 'text',
            context_hash => 'text',
            nonce        => 'text',
            actor        => 'uuid',
            credential   => 'uuid'
        ],
        json => ['result']
    },
    identity_oidc_consume => {
        version    => 2,
        parameters => [
            state_hash   => 'text',
            binding_hash => 'text',
            context_hash => 'text'
        ],
        json => ['result']
    },
    identity_oidc_link => {
        version    => 2,
        parameters => [
            actor      => 'uuid',
            credential => 'uuid',
            issuer     => 'text',
            subject    => 'text'
        ],
        json => ['result']
    },
    identity_oidc_resolve => {
        version    => 2,
        parameters => [ issuer => 'text', subject => 'text' ],
        json       => ['result']
    },
    identity_oidc_unlink => {
        version    => 2,
        parameters => [
            actor      => 'uuid',
            credential => 'uuid',
            issuer     => 'text',
            session    => 'uuid'
        ],
        json => ['result']
    },
    identity_oidc_status => {
        version    => 2,
        parameters => [ actor => 'uuid', issuer => 'text' ],
        json       => ['result']
    },

    identity_user_by_id => {
        version    => 2,
        parameters => [ user_id => 'uuid' ],
    },
    identity_user_by_identifier => {
        version    => 2,
        parameters => [ identifier => 'text', by_email => 'boolean' ],
    },

    # ADR 0142: two-step sign-in.
    identity_second_factor_status =>
      { version => 2, parameters => [ user_id => 'uuid' ] },
    identity_second_factor_begin => {
        version    => 2,
        parameters => [
            user_id       => 'uuid',
            secret_sealed => 'text',
            key_id        => 'text',
            now           => 'timestamptz',
        ],
    },
    identity_second_factor_cancel =>
      { version => 2, parameters => [ user_id => 'uuid' ] },
    identity_second_factor_confirm => {
        version    => 2,
        parameters => [
            user_id         => 'uuid',
            step            => 'bigint',
            code_hashes     => 'text[]',
            now             => 'timestamptz',
            keep_session_id => 'uuid',
            audit           => 'jsonb',
            mail            => 'jsonb',
        ],
    },
    identity_second_factor_disable => {
        version    => 2,
        parameters => [
            user_id       => 'uuid',
            step          => 'bigint',
            recovery_hash => 'text',
            now           => 'timestamptz',
            audit         => 'jsonb',
            mail          => 'jsonb',
        ],
    },
    identity_second_factor_renew => {
        version    => 2,
        parameters => [
            user_id     => 'uuid',
            step        => 'bigint',
            code_hashes => 'text[]',
            now         => 'timestamptz',
            audit       => 'jsonb',
        ],
    },
    identity_second_factor_challenge_open =>
      { version => 2, parameters => [ row => 'jsonb' ] },
    identity_second_factor_challenge => {
        version    => 2,
        parameters => [ token_hash => 'text', now => 'timestamptz' ],
    },
    identity_second_factor_challenge_answer => {
        version    => 4,
        parameters => [
            token_hash    => 'text',
            step          => 'bigint',
            recovery_hash => 'text',
            resealed      => 'text',
            key_id        => 'text',
            now           => 'timestamptz',
            audit         => 'jsonb',
            mail          => 'jsonb',
        ],
    },
    identity_registration_duplicates => {
        version    => 2,
        parameters => [ username => 'text', email => 'text' ],
    },
    identity_insert_user => {
        version    => 2,
        parameters => [ values => 'jsonb' ],
    },
    identity_update_user => {
        version    => 6,
        parameters => [ user_id => 'uuid', changes => 'jsonb' ],
    },
    identity_update_profile => {
        version    => 2,
        parameters =>
          [ user_id => 'uuid', display_name => 'text', bio => 'text' ],
    },
    identity_insert_credential => {
        version    => 2,
        parameters => [ values => 'jsonb' ],
    },
    identity_credential_by_id => {
        version    => 2,
        parameters => [ credential_id => 'uuid' ],
    },
    identity_active_password => {
        version    => 2,
        parameters => [ user_id => 'uuid' ],
    },
    identity_hold_password => {
        version    => 2,
        parameters => [ user_id => 'uuid', credential_id => 'uuid' ],
    },

    # A registration as one call (ADR 0126, section 5): the command log, the
    # duplicates, the user, the credential, the registration's event and
    # audit, the verification token with its audit and mail.
    identity_register_command => {
        version    => 4,
        parameters => [
            log                => 'jsonb',
            answer             => 'jsonb',
            accepted           => 'jsonb',
            refused            => 'jsonb',
            user               => 'jsonb',
            credential         => 'jsonb',
            event              => 'jsonb',
            event_outbox_id    => 'text',
            audit              => 'jsonb',
            token              => 'jsonb',
            token_audit        => 'jsonb',
            mail_event         => 'jsonb',
            mail_outbox_id     => 'text',
            mail_outbox_extras => 'jsonb',
            invitation_hash    => 'text',
        ],
        json => [ 'response', 'stored_user' ],
    },
    identity_lock_passwords => {
        version    => 2,
        parameters => [ user_id => 'uuid' ],
    },
    identity_revoke_passwords => {
        version    => 2,
        parameters => [ ids => 'jsonb', revoked_at => 'timestamptz' ],
    },
    identity_insert_token => {
        version    => 2,
        parameters => [ values => 'jsonb' ],
    },
    identity_token_by_id => {
        version    => 2,
        parameters => [ token_id => 'uuid' ],
    },
    identity_unused_token => {
        version    => 2,
        parameters => [ user_id => 'uuid', token_type => 'text' ],
    },
    identity_rotate_token => {
        version    => 2,
        parameters => [ token_id => 'uuid', values => 'jsonb' ],
    },
    identity_consume_token => {
        version    => 2,
        parameters => [
            token_hash => 'text',
            token_type => 'text',
            now        => 'timestamptz',
            now_epoch  => 'bigint'
        ],
        json => ['token_row'],
    },
    identity_token_user => {
        version    => 2,
        parameters => [ token_hash => 'text', token_type => 'text' ],
    },
    identity_profile_trust => {
        version    => 2,
        parameters => [ user_id => 'uuid' ],
    },
    identity_profile_counts => {
        version    => 2,
        parameters => [ user_id => 'uuid' ],
    },
    identity_profile_threads => {
        version    => 2,
        parameters => [
            user_id   => 'uuid',
            after_at  => 'timestamptz',
            after_id  => 'uuid',
            row_limit => 'integer'
        ],
    },
    identity_profile_replies => {
        version    => 2,
        parameters => [
            user_id   => 'uuid',
            after_at  => 'timestamptz',
            after_id  => 'uuid',
            row_limit => 'integer'
        ],
    },

    session_lookup => {
        version    => 2,
        parameters => [
            session_id => 'uuid',
            user_id    => 'uuid',
        ],
    },
    session_create => {
        version    => 2,
        parameters => [
            session_id      => 'uuid',
            user_id         => 'uuid',
            session_hash    => 'text',
            created_at      => 'timestamptz',
            last_seen_at    => 'timestamptz',
            expires_at      => 'timestamptz',
            revoked_at      => 'timestamptz',
            ip_hash         => 'text',
            user_agent_hash => 'text',
            retry           => 'boolean',
        ],
    },
    session_validate => {
        version    => 2,
        parameters => [
            session_id             => 'uuid',
            user_id                => 'uuid',
            token_hash             => 'text',
            now                    => 'timestamptz',
            touch_interval_seconds => 'integer',
        ],
    },
    session_revoke => {
        version    => 2,
        parameters => [
            session_id => 'uuid',
            user_id    => 'uuid',
            revoked_at => 'timestamptz',
        ],
    },
    session_live => {
        version    => 2,
        parameters => [
            session_ids => 'uuid[]',
            now         => 'timestamptz',
        ],
    },
    session_revoke_user => {
        version    => 2,
        parameters => [
            user_id         => 'uuid',
            revoked_at      => 'timestamptz',
            keep_session_id => 'uuid',
        ],
    },
);

sub entries ($class) {
    return \%FUNCTION;
}

1;

__END__

=head1 NAME

GPForum::Infrastructure::SqlFunctionCatalogue::Identity - The PostgreSQL functions of identity: accounts, sessions, passkeys, second factors and tokens.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $entries = GPForum::Infrastructure::SqlFunctionCatalogue::Identity->entries;

=head1 DESCRIPTION

A part of the table L<GPForum::Infrastructure::SqlFunctionCatalogue> reads:
the entries for the functions of identity: accounts, sessions, passkeys, second factors and tokens. See that module for what an
entry holds and for ADR 0126.

=head1 SUBROUTINES/METHODS

=head2 entries

The hash reference of entries, by name, read-only.

=head1 DIAGNOSTICS

None of its own.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

Const::Fast.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

None known.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
