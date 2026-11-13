# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package GPForum::Service::Identity::Passkeys;
use Mojo::Base 'GPForum::Base', -async_await;
use v5.40;
use Const::Fast;
use Crypt::URandom qw(urandom);
use Digest::SHA    qw(sha256_hex);
use MIME::Base64   qw(encode_base64url);
use Mojo::URL;
use GPForum::Infrastructure::Id;
use GPForum::Infrastructure::ResultRow;
use GPForum::Infrastructure::Row qw(column_of);
use GPForum::Service::Identity::PasskeyVerifier;
use GPForum::Service::Identity::LocalProof;
use GPForum::Service::Identity::CredentialStore;
use GPForum::Service::Identity::SessionStore;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Infrastructure::EventRecorder;
use GPForum::Service::Password;
use GPForum::X::Unavailable;
our $VERSION = '0.001';
const my $RANDOM_BYTES          => 32;
const my $LABEL_LIMIT           => 100;
const my $CREDENTIAL_TEXT_LIMIT => 1364;
const my $TIMEOUT_MS            => 60_000;
__PACKAGE__->requires(qw(schema config second_factor));
has password => sub ($self) {
    return GPForum::Service::Password->from_config( $self->config );
};
has credentials => sub ($self) {
    return GPForum::Service::Identity::CredentialStore->new(
        schema => $self->schema );
};
has sessions => sub ($self) {
    return GPForum::Service::Identity::SessionStore->new(
        schema => $self->schema );
};
has functions => \&GPForum::Infrastructure::SqlFunction::for_service;
has recorder  => sub ($self) {
    return GPForum::Infrastructure::EventRecorder->new(
        schema => $self->schema );
};

GPForum::Infrastructure::SqlFunction->blocking_twins(
    qw(listed begin complete revoke));
GPForum::Infrastructure::SqlFunction->blocking_parts(
    qw(credentials sessions second_factor));

async sub _proof_p ( $self, $user_id, $password, $code, $context ) {
    return await GPForum::Service::Identity::LocalProof->new(
        credentials   => $self->credentials,
        password      => $self->password,
        second_factor => $self->second_factor
    )->verify_local_p( $user_id, $password, $code, $context );
}

# The audit on $scope, the transaction of the write it records, as
# EventRecorder's record_audit writes it through the call layer.
async sub _audit_p ( $self, $action, $actor, $context, $scope ) {
    await $scope->row_p( 'ops_record_audit',
        $self->recorder->audit_call( _audit_input( $action, $actor ) ),
        $context );
    return;
}

sub _audit_input ( $action, $actor ) {
    return (
        action      => $action,
        actor_id    => $actor,
        target_type => 'user',
        target_id   => $actor,
    );
}

# The public address is trusted configuration, never a request's Host header.
sub origin ($self) {
    my $url = Mojo::URL->new( $self->config->public_base_url );
    return undef
      if $url->userinfo
      || $url->query->to_string
      || $url->fragment
      || ( $url->path->to_string // q{} ) !~ m{\A /? \z}msx;
    my $host = $url->host // q{};
    return undef
      if !$host
      || $host =~ /[:]/msx
      || $host =~ /\A (?:[[:digit:]]+[.]){3}[[:digit:]]+ \z/amsx;
    return undef
      if ( $url->scheme // q{} ) ne 'https'
      && !( ( $url->scheme // q{} ) eq 'http' && $host eq 'localhost' );
    return $url->to_string =~ s{/\z}{}rmsx;
}

# The origin is read from the configuration alone: answered in the worker.
async sub origin_p ( $self, $context = undef ) { return $self->origin; }

sub enabled ($self) { return defined $self->origin ? 1 : 0; }
sub rp_id   ($self) { return Mojo::URL->new( $self->origin )->host; }

sub verifier ($self) {
    die "passkeys unavailable\n" if !$self->enabled;
    return GPForum::Service::Identity::PasskeyVerifier->new(
        origin => $self->origin,
        rp_id  => $self->rp_id
    );
}

# The member's active keys for this relying party, on the worker's pooled
# asynchronous connections.
async sub listed_p ( $self, $actor, $context = undef ) {
    return [] if !$self->enabled;
    my $rows = await $self->_functions->rows_p( 'identity_passkey_list',
        { user_id => $actor, rp_id => $self->rp_id }, $context );
    return [ map { $_->{result} } @{$rows} ];
}

# A registration or a discoverable login ceremony; a registration asks for
# the password again, Argon2 in a child of the CPU lane.
async sub begin_p ( $self, $input, $context = undef ) {
    return undef if !$self->enabled;
    my $purpose = $input->{purpose};
    return undef if !_purpose($purpose);
    my $proof = [];
    if ( $purpose eq 'register' ) {
        return undef if !_registration_shaped($input);
        my $password =
          await $self->_proof_p( $input->{user_id}, $input->{password},
            $input->{code}, $context );
        $proof = _registration_proof( $input, $password ) or return undef;
    }
    my ( $challenge, $values ) = $self->_begin_values( $input, $proof );
    my $row =
      await $self->_functions->row_p( 'identity_passkey_begin', $values,
        $context );
    return undef                             if !$row;
    return $self->_login_options($challenge) if $purpose eq 'login';

    return $self->_registration_options( $row, $challenge,
        await $self->listed_p( $input->{user_id}, $context ) );
}

sub _purpose ($purpose) {
    return
      defined $purpose && ( $purpose eq 'register' || $purpose eq 'login' );
}

sub _begin_values ( $self, $input, $proof ) {
    my ( $password, $label ) = @{$proof};
    my $challenge = encode_base64url( urandom($RANDOM_BYTES) );
    return (
        $challenge,
        {
            input => {
                %{ $self->_context_input($input) },
                password_id    => $password,
                label          => $label,
                user_handle    => encode_base64url( urandom($RANDOM_BYTES) ),
                challenge_hash => sha256_hex($challenge),
            }
        }
    );
}

sub _login_options ( $self, $challenge ) {
    return {
        challenge        => $challenge,
        rpId             => $self->rp_id,
        userVerification => 'required',
        timeout          => $TIMEOUT_MS,
    };
}

sub _registration_options ( $self, $row, $challenge, $listed ) {
    my $account = $row->{result};
    my $options = $self->verifier->options(
        {
            id           => $account->{user_handle},
            name         => $account->{name},
            display_name => $account->{display_name}
        },
        $challenge
    );
    $options->{excludeCredentials} =
      [ map { { type => 'public-key', id => $_->{credential_id_b64} } }
          @{$listed} ];
    return $options;
}

sub _registration_shaped ($input) {
    return $input->{user_id} && $input->{session_id} ? 1 : 0;
}

# The password credential that proved, with the label: or undef for no
# proof or a label that is empty, too long or holds control characters.
sub _registration_proof ( $input, $password ) {
    return undef if !$password;
    my $label = $input->{label} // q{};
    return undef
      if ref $label
      || $label !~ /\S/msx
      || length($label) > $LABEL_LIMIT
      || $label =~ /[[:cntrl:]]/msx;
    return [ $password, $label ];
}

sub _context_input ( $self, $input ) {
    die "invalid browser binding\n"
      if ( $input->{binding} // q{} ) !~ /\A [[:alnum:]_-]{43} \z/amsx;
    return {
        purpose      => $input->{purpose},
        rp_id        => $self->rp_id,
        origin       => $self->origin,
        binding_hash => sha256_hex( $input->{binding} ),
        user_id => $input->{purpose} eq 'register' ? $input->{user_id} : undef,
        session_id => $input->{purpose} eq 'register'
        ? $input->{session_id}
        : undef
    };
}

# The challenge spent on its own, before the signature is checked: a
# refused response spends it too, and replaying a signed cookie cannot
# restore it. Then the registration or the sign-in (with its second factor,
# session and audit) in one transaction. The signature checks are one
# public-key verification each and run in the worker.
async sub complete_p ( $self, $input, $context = undef ) {
    return undef if !$self->enabled;
    my $challenge = _challenge($input) // return undef;
    my $row       = await $self->_functions->row_p( 'identity_passkey_consume',
        $self->_consume_values( $input, $challenge ), $context );
    return undef if !$row;
    return await $self->_register_p( $input, $row->{result}, $context )
      if $input->{purpose} eq 'register';
    return await $self->_login_p( $input, $context );
}

sub _challenge ($input) {
    my $challenge = $input->{challenge};
    return undef if ( $challenge // q{} ) !~ /\A [[:alnum:]_-]{43} \z/amsx;
    return $challenge;
}

sub _consume_values ( $self, $input, $challenge ) {
    return {
        input => {
            %{ $self->_context_input($input) },
            challenge_hash => sha256_hex($challenge)
        }
    };
}

async sub _register_p ( $self, $input, $state, $context ) {
    my $verified =
      $self->verifier->verify( $input->{credential}, $input->{challenge} );
    return await $self->_functions->transaction_p(
        async sub ($scope) {
            my $row = await $scope->row_p( 'identity_passkey_register',
                _register_values( $state, $verified ), $context );
            return undef if !$row;
            await $self->_audit_p( 'identity.passkey.registered',
                $state->{user_id}, $context, $scope );
            return _registered();
        },
        $context
    );
}

sub _register_values ( $state, $verified ) {
    return {
        input => {
            %{$state}, %{$verified},
            id => GPForum::Infrastructure::Id->new->uuid
        }
    };
}

sub _registered {
    return { ok => 1, persisted => 1, status => 'registered' };
}

async sub _login_p ( $self, $input, $context ) {
    my $credential = _assertion($input) // return undef;
    my $row        = await $self->_functions->row_p( 'identity_passkey_resolve',
        $self->_resolve_values($credential), $context );
    return undef if !$row;
    my $key = $row->{result};
    my $verified =
      $self->verifier->verify_assertion( $credential, $input->{challenge},
        $key );
    return await $self->_functions->transaction_p(
        async sub ($scope) {
            my $held = await $scope->row_p( 'identity_passkey_advance',
                _advance_values( $key, $verified ), $context );
            return undef if !$held;
            my $member = $held->{result};
            my $challenge =
              await $self->second_factor->open_challenge_p( $member->{id},
                $key->{password_id}, $context, $scope );
            return _second_factor( $member, $challenge )
              if $challenge->{status} ne 'none';
            my $user = GPForum::Infrastructure::ResultRow->from($member);
            my $session =
              await $self->sessions->create_session_p( $user, $input, $context,
                $scope );
            return undef if !$session;
            await $self->_audit_p( 'identity.passkey.login', $member->{id},
                $context, $scope );
            return _signed_in( $member, $user, $session );
        },
        $context
    );
}

sub _assertion ($input) {
    my $credential = $input->{credential};
    return undef
      if ref $credential ne 'HASH'
      || ref $credential->{rawId}
      || length( $credential->{rawId} // q{} ) > $CREDENTIAL_TEXT_LIMIT;
    return $credential;
}

sub _resolve_values ( $self, $credential ) {
    return {
        credential_id_b64 => $credential->{rawId} // q{},
        rp_id             => $self->rp_id
    };
}

sub _advance_values ( $key, $verified ) {
    return {
        id          => $key->{id},
        password_id => $key->{password_id},
        sign_count  => $verified->{sign_count}
    };
}

# An open second-factor challenge answers its token; any status but open
# or none refuses the sign-in.
sub _second_factor ( $member, $challenge ) {
    return undef if $challenge->{status} ne 'open';
    return {
        status          => 'second_factor',
        challenge_token => $challenge->{token},
        user_id         => $member->{id}
    };
}

sub _signed_in ( $member, $user, $session ) {
    return {
        ok            => 1,
        status        => 'ok',
        user_id       => $member->{id},
        user          => $user,
        session_token => $session->{session_token},
        session_id    => column_of( $session->{session}, 'session_id' ),
        map { $_ => $member->{$_} }
          qw(preferred_locale preferred_theme preferred_timezone)
    };
}

# The password checked first, Argon2 in a child of the CPU lane, then the
# revocation and its audit in one transaction.
async sub revoke_p ( $self, $input, $context = undef ) {
    return undef if !GPForum::Infrastructure::Id->is_uuid( $input->{id} );
    my $password =
      await $self->_proof_p( $input->{user_id}, $input->{password},
        $input->{code}, $context );
    return undef if !$password;
    return await $self->_functions->transaction_p(
        async sub ($scope) {
            my $row = await $scope->row_p( 'identity_passkey_revoke',
                _revoke_values( $input, $password ), $context );
            return undef if !$row;
            await $self->_audit_p( 'identity.passkey.revoked',
                $input->{user_id}, $context, $scope );
            return _revoked();
        },
        $context
    );
}

sub _revoke_values ( $input, $password ) {
    return {
        user_id     => $input->{user_id},
        id          => $input->{id},
        password_id => $password,
        session_id  => $input->{session_id},
    };
}

sub _revoked {
    return { ok => 1, status => 'revoked' };
}

sub _functions ($self) {
    return $self->functions // GPForum::X::Unavailable->throw(
        message => 'passkeys need the PostgreSQL function layer' );
}
1;

__END__
=head1 NAME

GPForum::Service::Identity::Passkeys - Persist and authenticate member passkeys.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $options = $passkeys->begin($input);

=head1 DESCRIPTION

Shares local proof, server sessions, TOTP policy and audit infrastructure with normal identity workflows. PostgreSQL owns single-use challenges, key uniqueness, counter updates and revocation locks.

=head1 SUBROUTINES/METHODS

=head2 origin

Returns the configured trusted origin when HTTPS or loopback development is available.

=head2 origin_p

L</origin> as a promise, with an optional query context last; it reads the
configuration alone, so it is answered in the worker itself.

=head2 enabled

Reports whether the configured public address supports passkeys.

=head2 rp_id

Derives the relying-party hostname from configuration.

=head2 verifier

Builds the bounded WebAuthn verifier for that origin and RP.

=head2 functions

The call layer (L<GPForum::Infrastructure::SqlFunction>). Each operation
below is written once, as its promise method on it; its blocking name is
its twin, the same body settled on the blocking layer (ADR 0177), with the
credential store, the session store and the second factor as blocking
parts. The local proof's Argon2 runs in a child of the CPU lane on the
asynchronous layer and in the process on the blocking one.

=head2 listed_p

Lists at most ten active keys belonging to the member for this RP, with an
optional query context last; none without passkeys. C<listed> is its
blocking twin.

=head2 begin_p

Issues a five-minute registration or discoverable login ceremony, with an
optional query context last. Registration requires fresh local proof and a
valid server session. C<begin> is its blocking twin.

=head2 complete_p

Atomically spends the browser-bound challenge before verification, then
persists a verified registration or starts the existing TOTP/session flow
after a verified assertion, with its second factor, session and audit in
one transaction. Takes an optional query context last. C<complete> is its
blocking twin.

=head2 revoke_p

Requires fresh local proof, then revokes the owned key, other sessions and
pending TOTP challenges, and records an audit entry, in one transaction;
an optional query context last. Password rotation and account recovery
revoke all passkeys. C<revoke> is its blocking twin.

=head1 DIAGNOSTICS

Refusals return undef. Verifier and persistence errors propagate to the controller without exposing request payloads; without the function layer the operations throw L<GPForum::X::Unavailable>.

=head1 CONFIGURATION AND ENVIRONMENT

Uses public_base_url from validated forum configuration and injected schema, password and second-factor services.

=head1 DEPENDENCIES

Uses the identity and infrastructure modules named above.

=head1 INCOMPATIBILITIES

External identity and TOTP retain their existing account policies.

=head1 BUGS AND LIMITATIONS

Requires a local recovery password. Changing that password revokes all passkeys. Physical authenticator behavior requires a compatible browser.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. BSD-3-Clause.

=cut
