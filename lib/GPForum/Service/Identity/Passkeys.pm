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

sub _proof ( $self, @arguments ) {
    return GPForum::Service::Identity::LocalProof->new(
        credentials   => $self->credentials,
        password      => $self->password,
        second_factor => $self->second_factor
    )->verify_local(@arguments);
}

sub _audit ( $self, $action, $actor ) {
    $self->recorder->record_audit(
        action      => $action,
        actor_id    => $actor,
        target_type => 'user',
        target_id   => $actor
    );
    return;
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

sub enabled ($self) { return defined $self->origin ? 1 : 0; }
sub rp_id   ($self) { return Mojo::URL->new( $self->origin )->host; }

sub verifier ($self) {
    die "passkeys unavailable\n" if !$self->enabled;
    return GPForum::Service::Identity::PasskeyVerifier->new(
        origin => $self->origin,
        rp_id  => $self->rp_id
    );
}

sub listed ( $self, $actor ) {
    return [] if !$self->enabled;
    return [ map { $_->{result} }
          @{ $self->functions->rows( $self->_listed_values($actor) ) } ];
}

# The settings page's list on the worker's pooled asynchronous connections.
async sub listed_p ( $self, $actor, $context = undef ) {
    return $self->listed($actor) if !$self->enabled || !$self->functions;
    return [
        map { $_->{result} }
          @{ await $self->functions->rows_p( $self->_listed_values($actor),
                $context )
          }
    ];
}

sub _listed_values ( $self, $actor ) {
    return ( 'identity_passkey_list',
        { user_id => $actor, rp_id => $self->rp_id } );
}

sub begin ( $self, $input ) {
    return undef if !$self->enabled;
    my $purpose = $input->{purpose};
    return undef
      if !defined $purpose || ( $purpose ne 'register' && $purpose ne 'login' );
    my ( $password, $label );
    if ( $purpose eq 'register' ) {
        my $proof = $self->_registration_proof($input) or return undef;
        ( $password, $label ) = @{$proof};
    }
    my $challenge = encode_base64url( urandom($RANDOM_BYTES) );
    my $row       = $self->functions->row(
        'identity_passkey_begin',
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
    return undef if !$row;
    return {
        challenge        => $challenge,
        rpId             => $self->rp_id,
        userVerification => 'required',
        timeout          => $TIMEOUT_MS
      }
      if $purpose eq 'login';
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
          @{ $self->listed( $input->{user_id} ) } ];
    return $options;
}

sub _registration_proof ( $self, $input ) {
    return undef if !$input->{user_id} || !$input->{session_id};
    my $password =
      $self->_proof( $input->{user_id}, $input->{password}, $input->{code} );
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

sub complete ( $self, $input ) {
    return undef if !$self->enabled;
    my $challenge = $input->{challenge};
    return undef if ( $challenge // q{} ) !~ /\A [[:alnum:]_-]{43} \z/amsx;

    # Commit consumption before crypto: a refused response also spends it, and
    # replaying a previous signed cookie cannot restore the database challenge.
    my $row = $self->functions->row(
        'identity_passkey_consume',
        {
            input => {
                %{ $self->_context_input($input) },
                challenge_hash => sha256_hex($challenge)
            }
        }
    );
    return undef if !$row;
    return $self->_register( $input, $row->{result} )
      if $input->{purpose} eq 'register';
    return $self->_login($input);
}

sub _register ( $self, $input, $state ) {
    my $verified =
      $self->verifier->verify( $input->{credential}, $input->{challenge} );
    return $self->schema->txn_do(
        sub {
            my $id  = GPForum::Infrastructure::Id->new->uuid;
            my $row = $self->functions->row(
                'identity_passkey_register',
                {
                    input => {
                        %{$state}, %{$verified}, id => $id
                    }
                }
            );
            return undef if !$row;
            $self->_audit( 'identity.passkey.registered', $state->{user_id} );
            return { ok => 1, persisted => 1, status => 'registered' };
        }
    );
}

sub _login ( $self, $input ) {
    my $credential = $input->{credential};
    return undef
      if ref $credential ne 'HASH'
      || ref $credential->{rawId}
      || length( $credential->{rawId} // q{} ) > $CREDENTIAL_TEXT_LIMIT;
    my $row = $self->functions->row(
        'identity_passkey_resolve',
        {
            credential_id_b64 => $credential->{rawId} // q{},
            rp_id             => $self->rp_id
        }
    );
    return undef if !$row;
    my $key = $row->{result};
    my $verified =
      $self->verifier->verify_assertion( $credential, $input->{challenge},
        $key );
    return $self->schema->txn_do(
        sub {
            my $held = $self->functions->row(
                'identity_passkey_advance',
                {
                    id          => $key->{id},
                    password_id => $key->{password_id},
                    sign_count  => $verified->{sign_count}
                }
            );
            return undef if !$held;
            my $member    = $held->{result};
            my $challenge = $self->second_factor->open_challenge( $member->{id},
                $key->{password_id} );
            if ( $challenge->{status} eq 'open' ) {
                return {
                    status          => 'second_factor',
                    challenge_token => $challenge->{token},
                    user_id         => $member->{id}
                };
            }
            return undef if $challenge->{status} ne 'none';
            my $user    = GPForum::Infrastructure::ResultRow->from($member);
            my $session = $self->sessions->create_session( $user, $input );
            return undef if !$session;
            $self->_audit( 'identity.passkey.login', $member->{id} );
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
    );
}

sub revoke ( $self, $input ) {
    return undef if !GPForum::Infrastructure::Id->is_uuid( $input->{id} );
    my $password =
      $self->_proof( $input->{user_id}, $input->{password}, $input->{code} );
    return undef if !$password;
    return $self->schema->txn_do(
        sub {
            my $row = $self->functions->row(
                'identity_passkey_revoke',
                {
                    user_id     => $input->{user_id},
                    id          => $input->{id},
                    password_id => $password,
                    session_id  => $input->{session_id}
                }
            );
            return undef if !$row;
            $self->_audit( 'identity.passkey.revoked', $input->{user_id} );
            return { ok => 1, status => 'revoked' };
        }
    );
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

=head2 enabled

Reports whether the configured public address supports passkeys.

=head2 rp_id

Derives the relying-party hostname from configuration.

=head2 verifier

Builds the bounded WebAuthn verifier for that origin and RP.

=head2 listed

Lists at most ten active keys belonging to the member for this RP.

=head2 listed_p

L</listed> as a promise, with an optional query context last, read on the
worker's pooled asynchronous connections. Without passkeys or SQL functions
it answers the blocking list.

=head2 begin

Issues a five-minute registration or discoverable login ceremony. Registration requires fresh local proof and a valid server session.

=head2 complete

Atomically spends the browser-bound challenge before verification. Persists a verified registration or starts the existing TOTP/session flow after a verified assertion.

=head2 revoke

Requires fresh local proof, revokes the owned key, other sessions and pending TOTP challenges, and records an audit entry in one transaction. Password rotation and account recovery revoke all passkeys.

=head1 DIAGNOSTICS

Refusals return undef. Verifier and persistence errors propagate to the controller without exposing request payloads.

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
