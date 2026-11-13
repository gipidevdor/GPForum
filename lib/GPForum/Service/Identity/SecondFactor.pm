# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Identity::SecondFactor;

use Const::Fast;
use Digest::SHA qw(sha256_hex);
use Time::Piece ();
use Mojo::Base 'GPForum::Base', -async_await;
use v5.40;

use GPForum::Infrastructure::EventRecorder;
use GPForum::Infrastructure::Id;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Service::Clock;
use GPForum::Service::Identity::Event;
use GPForum::Service::Identity::SecondFactorCodes;
use GPForum::Service::Identity::SecretBox;
use GPForum::Service::Identity::Support;
use GPForum::Service::Password;
use GPForum::X::Unavailable;

our $VERSION = '0.001';

# ADR 0142: a sign-in waits five minutes for its second step; the staff
# list shows at most 200 members.
const my $CHALLENGE_SECONDS => 300;
const my $STAFF_ROWS        => 200;
const my $TOKEN_BYTES       => 32;
const my $USER              => 'user';
const my %AUDIT => (
    enabled  => 'identity.second_factor.enabled',
    disabled => 'identity.second_factor.disabled',
    renewed  => 'identity.second_factor.recovery_renewed',
    passed   => 'identity.second_factor.passed',
    reset    => 'identity.second_factor.reset',
    policy   => 'identity.second_factor.policy_set',
);
const my %MAIL => (
    enabled  => 'second_factor_enabled',
    disabled => 'second_factor_disabled',
    reset    => 'second_factor_reset',
    locked   => 'second_factor_locked',
);

__PACKAGE__->requires(qw(schema));

has clock      => sub { return GPForum::Service::Clock->new; };
has id_service => sub { return GPForum::Infrastructure::Id->new; };
has codes => sub { return GPForum::Service::Identity::SecondFactorCodes->new; };
has box   => sub { return GPForum::Service::Identity::SecretBox->new; };
has password => sub { return GPForum::Service::Password->new; };
has events   => sub ($self) {
    return GPForum::Service::Identity::Event->new( clock => $self->clock );
};
has recorder => \&GPForum::Infrastructure::EventRecorder::for_service;

# The member's active password credential, for the checks that ask for the
# password again (Service::Identity::CredentialStore).
has credential_store => undef;    # optional: without it no password matches

# The call layer every read and write goes through (ADR 0126). There is no
# other path (ADR 0177): without it they raise Unavailable.
has functions => \&GPForum::Infrastructure::SqlFunction::for_service;

GPForum::Infrastructure::SqlFunction->blocking_twins(
    qw(status enrollment begin cancel confirm disable renew open_challenge
      prepare_answer answer member_summary reset_member policy staff
      set_policy)
);
GPForum::Infrastructure::SqlFunction->blocking_parts('credential_store');

# Whether this forum can seal secrets: without a key nobody can turn
# two-step sign-in on.
sub available ($self) {
    return $self->box->available && $self->functions ? 1 : 0;
}

# The member's state: off, pending or active, since when, the recovery
# codes left, whether they are staff and whether the policy requires it of
# them. An id that is no member's is off without a read.
async sub status_p ( $self, $user_id, $context = undef ) {
    return _status(undef) if !_uuid($user_id);

    return _status(
        await $self->_functions->row_p(
            'identity_second_factor_status', { user_id => $user_id },
            $context
        )
    );
}

# What an authenticator app is given while enrollment is pending: the
# secret in base32 (grouped for typing) and the otpauth link, which names
# the forum and the member's username, or undef.
async sub enrollment_p ( $self, $user_id, $issuer, $context = undef ) {
    my $status = await $self->status_p( $user_id, $context );
    return undef if $status->{state} ne 'pending';
    my $secret = $self->box->unseal( $status->{secret_sealed}, $user_id );
    return undef if !defined $secret;

    my $user = await $self->_functions->row_p( 'identity_user_by_id',
        { user_id => $user_id }, $context );
    my $account = ( $user && $user->{username} ) || $user_id;
    return {
        secret => $self->codes->grouped( $self->codes->base32($secret) ),
        uri    => $self->codes->otpauth_uri( $secret, $issuer, $account ),
    };
}

# Begins enrollment once the password checks: a new secret, sealed.
# Answers ok, or a refusal: password, unavailable, active, forbidden.
async sub begin_p ( $self, $user_id, $password, $context = undef ) {
    return _refused('unavailable') if !$self->available;
    return _refused('password')
      if !await $self->_password_ok_p( $user_id, $password, $context );

    my ( $sealed, $key_id ) =
      $self->box->seal( $self->codes->new_secret, $user_id );
    return _answer(
        await $self->_functions->row_p(
            'identity_second_factor_begin',
            {
                user_id       => $user_id,
                secret_sealed => $sealed,
                key_id        => $key_id,
                now           => $self->clock->now_iso8601,
            },
            $context
        )
    );
}

# Drops a pending enrollment.
async sub cancel_p ( $self, $user_id, $context = undef ) {
    return _answer(
        await $self->_functions->row_p(
            'identity_second_factor_cancel', { user_id => $user_id },
            $context
        )
    );
}

# Turns a pending enrollment on with the first code the app gives: answers
# ok with the ten recovery codes (shown once), or wrong, not_found, active.
async sub confirm_p (
    $self, $user_id, $code,
    $keep_session_id = undef,
    $context = undef
  )
{
    my $status = await $self->status_p( $user_id, $context );
    return _refused('not_found') if $status->{state} ne 'pending';
    my $step = $self->_step( $user_id, $status, $code );
    return _refused('wrong') if !defined $step;

    my $recovery = $self->codes->new_recovery_codes;
    my $row      = await $self->_functions->row_p(
        'identity_second_factor_confirm',
        {
            user_id         => $user_id,
            step            => $step,
            code_hashes     => $self->_hashes( $user_id, $recovery ),
            now             => $self->clock->now_iso8601,
            keep_session_id => _uuid($keep_session_id),
            audit           => $self->_audit( $AUDIT{enabled}, $user_id ),
            mail            => $self->_mail( $MAIL{enabled}, $user_id ),
        },
        $context
    );
    my $answer = _answer($row);
    return $answer if !$answer->{ok};

    return {
        %{$answer},
        recovery_codes   => $recovery,
        sessions_revoked => 0 + ( $row->{sessions_revoked} // 0 ),
    };
}

# Turns two-step sign-in off, given the password and a code or an unused
# recovery code: ok, or password, wrong, replayed, not_found.
async sub disable_p ( $self, $user_id, $password, $code, $context = undef ) {
    my $status = await $self->status_p( $user_id, $context );
    return _refused('not_found') if $status->{state} ne 'active';
    return _refused('password')
      if !await $self->_password_ok_p( $user_id, $password, $context );
    my $proof = $self->_proof( $user_id, $status, $code );
    return _refused('wrong') if !$proof;

    return _answer(
        await $self->_functions->row_p(
            'identity_second_factor_disable',
            {
                user_id       => $user_id,
                step          => $proof->{step},
                recovery_hash => $proof->{recovery_hash},
                now           => $self->clock->now_iso8601,
                audit         => $self->_audit(
                    $AUDIT{disabled}, $user_id,
                    { method => $proof->{method} }
                ),
                mail => $self->_mail( $MAIL{disabled}, $user_id ),
            },
            $context
        )
    );
}

# Ten new recovery codes for the old ones, given the password and a code
# from the app: ok with the codes, or password, wrong, replayed, not_found.
# The password first: a wrong code here was refused before anything counted
# it, so a session alone could guess codes at the settings rate limit.
async sub renew_p ( $self, $user_id, $password, $code, $context = undef ) {
    my $status = await $self->status_p( $user_id, $context );
    return _refused('not_found') if $status->{state} ne 'active';
    return _refused('password')
      if !await $self->_password_ok_p( $user_id, $password, $context );
    my $step = $self->_step( $user_id, $status, $code );
    return _refused('wrong') if !defined $step;

    my $recovery = $self->codes->new_recovery_codes;
    my $answer   = _answer(
        await $self->_functions->row_p(
            'identity_second_factor_renew',
            {
                user_id     => $user_id,
                step        => $step,
                code_hashes => $self->_hashes( $user_id, $recovery ),
                now         => $self->clock->now_iso8601,
                audit       => $self->_audit( $AUDIT{renewed}, $user_id ),
            },
            $context
        )
    );
    return $answer->{ok}
      ? { %{$answer}, recovery_codes => $recovery }
      : $answer;
}

# A sign-in whose password verified: the challenge's token when the member
# has two-step sign-in on (status open), none when they have not, locked
# after ten wrong answers in the hour. On $scope, the transaction of the
# sign-in that asks for it, when one is given.
async sub open_challenge_p (
    $self, $user_id, $credential_id,
    $context = undef,
    $scope = undef
  )
{
    $scope //= $self->_functions;
    my $token = unpack 'H*', $self->codes->random_bytes->($TOKEN_BYTES);
    my $now   = $self->clock->now_epoch;
    my $row   = await $scope->row_p(
        'identity_second_factor_challenge_open',
        {
            row => {
                challenge_id  => $self->id_service->uuid,
                token_hash    => sha256_hex($token),
                user_id       => $user_id,
                credential_id => $credential_id,
                created_at    => _iso8601($now),
                expires_at    => _iso8601( $now + $CHALLENGE_SECONDS ),
            }
        },
        $context
    );
    my $status = $row ? $row->{status} : 'invalid';

    return $status eq 'open'
      ? { status => 'open', token => $token }
      : { status => $status };
}

# What answering a challenge sends, worked out before the transaction that
# sends it: the code's step, or the recovery code's hash, and the secret
# sealed again when its key is being rotated out. undef for a token that
# names no open challenge.
async sub prepare_answer_p ( $self, $token, $code, $context = undef ) {
    return undef if !_token($token);
    my $hash = sha256_hex($token);
    my $challenge =
      await $self->_functions->row_p( 'identity_second_factor_challenge',
        { token_hash => $hash, now => $self->clock->now_iso8601 }, $context );
    return undef if !$challenge || !$challenge->{open};

    my $user_id = $challenge->{user_id};
    my $proof   = $self->_proof( $user_id, $challenge, $code ) || {};
    my ( $resealed, $key_id ) =
      defined $proof->{step}
      ? $self->_resealed( $challenge, $user_id )
      : ();
    return {
        token_hash    => $hash,
        step          => $proof->{step},
        recovery_hash => $proof->{recovery_hash},
        resealed      => $resealed,
        key_id        => $key_id,
        user_id       => $user_id,
    };
}

# The secret sealed again under the current key when the challenge's key
# is being rotated out; nothing otherwise.
sub _resealed ( $self, $challenge, $user_id ) {
    return () if !$self->box->stale( $challenge->{key_id} );
    my $secret = $self->box->unseal( $challenge->{secret_sealed}, $user_id );
    return () if !defined $secret;

    return $self->box->seal( $secret, $user_id );
}

# Answers the challenge prepared: ok (with user_id, method, recovery_left),
# wrong (attempts_left), locked, expired, not_found. Runs on $scope, the
# caller's transaction, which opens the session on ok.
async sub answer_p ( $self, $prepared, $context = undef, $scope = undef ) {
    $scope //= $self->_functions;
    my $row = (
        await $scope->row_p(
            'identity_second_factor_challenge_answer',
            {
                token_hash    => $prepared->{token_hash},
                step          => $prepared->{step},
                recovery_hash => $prepared->{recovery_hash},
                resealed      => $prepared->{resealed},
                key_id        => $prepared->{key_id},
                now           => $self->clock->now_iso8601,
                audit         => $self->_audit( $AUDIT{passed}, undef ),
                mail => $self->_mail( $MAIL{locked}, $prepared->{user_id} ),
            },
            $context
        )
    ) || { status => 'not_found' };

    return {
        ok            => $row->{status} eq 'ok' ? 1 : 0,
        status        => $row->{status},
        user_id       => $row->{user_id},
        method        => $row->{method},
        recovery_left => 0 + ( $row->{recovery_left} // 0 ),
        attempts_left => 0 + ( $row->{attempts_left} // 0 ),
    };
}

# What staff see of a member's two-step sign-in: state, since when,
# recovery codes left. Never the secret.
async sub member_summary_p ( $self, $user_id, $context = undef ) {
    my $row =
      _uuid($user_id)
      ? await $self->_functions->row_p( 'admin_second_factor_member',
        { user_id => $user_id }, $context )
      : undef;

    return {
        state         => $row->{state} // 'off',
        confirmed_at  => $row->{confirmed_at},
        recovery_left => 0 + ( $row->{recovery_left} // 0 ),
    };
}

# An administrator turns a member's two-step sign-in off: ok, or self,
# not_found, invalid.
async sub reset_member_p ( $self, $user_id, $actor_user_id, $context = undef ) {
    return _refused('not_found') if !_uuid($user_id);

    return _answer(
        await $self->_functions->row_p(
            'admin_second_factor_reset',
            {
                user_id       => $user_id,
                actor_user_id => $actor_user_id,
                now           => $self->clock->now_iso8601,
                audit         => $self->_audit( $AUDIT{reset}, $actor_user_id ),
                mail          => $self->_mail( $MAIL{reset}, $user_id ),
            },
            $context
        )
    );
}

# Whether staff must use two-step sign-in, and who set it when.
async sub policy_p ( $self, $context = undef ) {
    my $row =
      await $self->_functions->row_p( 'admin_second_factor_policy', {},
        $context );

    return {
        staff_required      => $row && $row->{staff_required} ? 1 : 0,
        updated_at          => $row ? $row->{updated_at}          : undef,
        updated_by_username => $row ? $row->{updated_by_username} : undef,
    };
}

# The staff, those without two-step sign-in first.
async sub staff_p ( $self, $context = undef ) {
    return await $self->_functions->rows_p( 'admin_second_factor_staff',
        { row_limit => $STAFF_ROWS }, $context );
}

# Requires two-step sign-in of staff, or stops: ok, unchanged, or
# unenrolled (the administrator has none of their own).
async sub set_policy_p ( $self, $required, $actor_user_id, $context = undef ) {
    return _answer(
        await $self->_functions->row_p(
            'admin_second_factor_policy_set',
            {
                required      => $required ? 1 : 0,
                actor_user_id => $actor_user_id,
                now           => $self->clock->now_iso8601,
                audit         => $self->_audit(
                    $AUDIT{policy}, $actor_user_id,
                    {},             'second_factor_policy'
                ),
            },
            $context
        )
    );
}

# The code's step against the member's secret, or undef.
sub _step ( $self, $user_id, $status, $code ) {
    my $secret = $self->box->unseal( $status->{secret_sealed}, $user_id );
    return undef if !defined $secret;

    return $self->codes->matching_step( $secret, $code,
        $self->clock->now_epoch );
}

# A code from the app (its step) or a recovery code (its hash), or undef
# for neither.
sub _proof ( $self, $user_id, $status, $code ) {
    if ( $self->codes->totp_shaped($code) ) {
        my $step = $self->_step( $user_id, $status, $code );
        return defined $step ? { step => $step, method => 'totp' } : undef;
    }
    my $recovery = $self->codes->normalize_recovery_code($code);
    return undef if !defined $recovery;

    return {
        recovery_hash => $self->codes->recovery_hash( $user_id, $recovery ),
        method        => 'recovery',
    };
}

sub _hashes ( $self, $user_id, $codes ) {
    return [
        map { $self->codes->recovery_hash( $user_id, $_ ) }
        map { $self->codes->normalize_recovery_code($_) } @{$codes}
    ];
}

# The password checks against the member's active credential; a member
# without one costs the same work, verified against the decoy hash.
async sub _password_ok_p ( $self, $user_id, $password, $context ) {
    my $credential =
      $self->credential_store && _uuid($user_id)
      ? await $self->credential_store->active_password_credential_p( $user_id,
        $context )
      : undef;
    my $hash =
      $credential
      ? GPForum::Service::Identity::Support->new->column( $credential,
        q{secret_hash} )
      : await $self->_decoy_hash_p;
    my $verified = await $self->_verified_p( $password // q{}, $hash );

    return $credential && $verified ? 1 : 0;
}

# Argon2 in a child of the CPU lane on the asynchronous layer, in the
# process on the blocking one, whose settled promise a child would leave
# pending (ADR 0177).
async sub _verified_p ( $self, $password, $hash ) {
    return $self->password->verify_password( $password, $hash )
      if $self->_functions->blocking;

    return await $self->password->verify_password_p( $password, $hash );
}

async sub _decoy_hash_p ($self) {
    return $self->password->decoy_hash if $self->_functions->blocking;

    return await $self->password->decoy_hash_p;
}

sub _audit ( $self, $action, $actor_id, $metadata = {}, $target_type = $USER ) {
    return $self->recorder->audit_call(
        action      => $action,
        actor_id    => $actor_id,
        metadata    => $metadata,
        target_id   => undef,
        target_type => $target_type,
    )->{audit};
}

# The notice mail's event and outbox message; the function adds the
# member's address and language.
sub _mail ( $self, $kind, $user_id ) {
    return undef if !_uuid($user_id);
    my $call = $self->recorder->event_call(
        %{
            $self->events->mail_envelope(
                {
                    user_id  => $user_id,
                    kind     => $kind,
                    token_id => $self->id_service->uuid,
                }
            )
        },
        outbox_payload => { mail => { kind => $kind } },
    );

    return {
        event         => $call->{event},
        outbox_id     => $call->{outbox_id},
        outbox_extras => $call->{outbox_extras},
    };
}

sub _functions ($self) {
    return $self->functions // GPForum::X::Unavailable->throw(
        message => 'two-step sign-in needs the PostgreSQL function layer' );
}

sub _status ($row) {
    return {
        state          => $row ? $row->{state}         : 'off',
        secret_sealed  => $row ? $row->{secret_sealed} : undef,
        key_id         => $row ? $row->{key_id}        : undef,
        last_step      => 0 + ( $row ? $row->{last_step} // 0 : 0 ),
        confirmed_at   => $row ? $row->{confirmed_at} : undef,
        recovery_left  => 0 + ( $row ? $row->{recovery_left} // 0 : 0 ),
        staff          => $row && $row->{staff}          ? 1 : 0,
        staff_required => $row && $row->{staff_required} ? 1 : 0,
    };
}

sub _answer ($row) {
    my $status = $row ? $row->{status} // 'failed' : 'failed';

    return {
        ok     => $status eq 'ok' || $status eq 'unchanged' ? 1 : 0,
        status => $status,
    };
}

sub _refused ($status) {
    return { ok => 0, status => $status };
}

sub _uuid ($value) {
    return GPForum::Infrastructure::Id->is_uuid_spelling($value)
      ? $value
      : undef;
}

sub _token ($token) {
    return defined $token && $token =~ /\A [[:xdigit:]]{64} \z/msx ? 1 : 0;
}

sub _iso8601 ($epoch) {
    return Time::Piece->gmtime($epoch)->datetime . q{Z};
}

1;

__END__

=head1 NAME

GPForum::Service::Identity::SecondFactor - Two-step sign-in: enrollment, challenges, recovery and the staff policy.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $second = GPForum::Service::Identity::SecondFactor->new(
        schema           => $schema,
        box              => $secret_box,
        credential_store => $credential_store,
    );
    my $begun     = $second->begin( $user_id, $password );
    my $confirmed = $second->confirm( $user_id, '123456', $session_id );
    my $opened    = $second->open_challenge( $user_id, $credential_id );

=head1 DESCRIPTION

ADR 0142. Every read and write is a function of schema C<api> (ADR 0126);
refusals are result values (ADR 0118). The secret is drawn and sealed here
(L<GPForum::Service::Identity::SecretBox>), and codes are checked here
against it (L<GPForum::Service::Identity::SecondFactorCodes>); the
functions keep the state, the steps already used, the recovery codes'
hashes, the challenges and their wrong answers, and record the audit rows
and the notice mails in the same call.

=head1 SUBROUTINES/METHODS

Each operation is written once, as its promise method on the call layer;
its blocking name is its twin, the same body settled on the blocking layer
(ADR 0177), with the credential store as a blocking part. Every promise
method takes an optional query context last. Argon2 runs in a child of the
CPU lane on the asynchronous layer and in the process on the blocking one.

=head2 available

True when a key is configured and the function layer is there.

=head2 functions

The call layer (L<GPForum::Infrastructure::SqlFunction>).

=head2 status_p

The member's C<state> (C<off>, C<pending>, C<active>), C<confirmed_at>,
C<recovery_left>, C<staff>, C<staff_required>, and the sealed secret; C<off>
without a read for an id that is no member's. C<status> is its blocking
twin.

=head2 enrollment_p

While enrollment is pending, the secret in grouped base32 and the
C<otpauth://> link; undef otherwise. C<enrollment> is its blocking twin.

=head2 begin_p

Takes the member and their password; begins enrollment. Answers C<ok>, or
C<password>, C<unavailable>, C<active>, C<forbidden>, C<invalid>. C<begin>
is its blocking twin.

=head2 cancel_p

Drops a pending enrollment: C<ok> or C<not_found>. C<cancel> is its
blocking twin.

=head2 confirm_p

Takes the member, the first code and the session to keep (the query
context after it); answers C<ok> with C<recovery_codes> and
C<sessions_revoked>, or C<wrong>, C<not_found>, C<active>. C<confirm> is its
blocking twin.

=head2 disable_p

Takes the member, the password and a code or a recovery code; answers
C<ok>, or C<password>, C<wrong>, C<replayed>, C<not_found>. C<disable> is
its blocking twin.

=head2 renew_p

Takes the member, their password and a code; answers C<ok> with new
C<recovery_codes>, or C<password>, C<wrong>, C<replayed>, C<not_found>.
C<renew> is its blocking twin.

=head2 open_challenge_p

Takes the member and the password credential that verified, and an
optional query context and call layer (the transaction of the sign-in)
last; answers C<open> with the C<token> for the cookie, C<none>, or
C<locked>. C<open_challenge> is its blocking twin.

=head2 prepare_answer_p

Takes the token and the code typed; resolves with what L</answer_p> sends,
or undef for a token naming no open challenge. C<prepare_answer> is its
blocking twin.

=head2 answer_p

Sends a prepared answer, with an optional query context and call layer
(the caller's transaction) last; resolves with C<ok> (C<user_id>,
C<method>, C<recovery_left>), C<wrong> (C<attempts_left>), C<locked>,
C<expired> or C<not_found>. C<answer> is its blocking twin.

=head2 member_summary_p

Staff's view of a member: C<state>, C<confirmed_at>, C<recovery_left>.
C<member_summary> is its blocking twin.

=head2 reset_member_p

Takes the member and the administrator; answers C<ok>, C<self>,
C<not_found> or C<invalid>. C<reset_member> is its blocking twin.

=head2 policy_p

C<staff_required>, C<updated_at>, C<updated_by_username>. C<policy> is its
blocking twin.

=head2 staff_p

The staff members with C<enabled>, those without first. C<staff> is its
blocking twin.

=head2 set_policy_p

Takes whether it is required and the administrator; answers C<ok>,
C<unchanged> or C<unenrolled>. C<set_policy> is its blocking twin.

=head1 DIAGNOSTICS

Reads and writes without the function layer throw
L<GPForum::X::Unavailable>; a member's id that is no uuid reads as C<off>
without one.

=head1 CONFIGURATION AND ENVIRONMENT

C<box> holds the keys from C<GPFORUM_SECOND_FACTOR_KEY> and
C<GPFORUM_SECOND_FACTOR_KEYS>.

=head1 DEPENDENCIES

L<GPForum::Infrastructure::SqlFunction>,
L<GPForum::Infrastructure::EventRecorder>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

TOTP only; WebAuthn is another credential type (ADR 0053).

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
