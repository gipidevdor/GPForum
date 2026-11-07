# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Identity::OpenID;

use Mojo::Base 'GPForum::Base', -signatures;
use v5.40;
use Const::Fast;
use Crypt::JWT     qw(decode_jwt);
use Crypt::URandom qw(urandom);
use Digest::SHA    qw(sha256 sha256_hex);
use MIME::Base64   qw(encode_base64url);
use Mojo::JSON     qw(encode_json);
use Mojo::Promise;
use GPForum::Infrastructure::AsyncWork;
use GPForum::Infrastructure::Row qw(column_of);
use GPForum::Infrastructure::ResultRow;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Infrastructure::EventRecorder;
use GPForum::Service::Integration::HttpClient;
use GPForum::Service::Integration::Readiness;
use GPForum::Service::Identity::CredentialStore;
use GPForum::Service::Identity::LocalProof;
use GPForum::Service::Identity::SessionStore;
use GPForum::Service::Password;
use GPForum::X::Argument;
use GPForum::X::Config;
use GPForum::X::Unavailable;
our $VERSION = '0.001';
const my $CLOCK_SKEW_SECONDS     => 30;
const my $MAX_AUTHORIZATION_CODE => 4096;
const my $MAX_SIGNING_KEYS       => 64;
const my $TOKEN_BYTES            => 32;
const my $MAX_ID_TOKEN           => 16_384;
const my $LINK_AUTH_SECONDS      => 300;
has policy_available => 0;
has query_context    => undef;  # optional: CLI calls have no HTTP query context
has async_work => sub { return GPForum::Infrastructure::AsyncWork->shared; };
__PACKAGE__->requires(qw(schema config second_factor));
has client => sub { return GPForum::Service::Integration::HttpClient->shared; };
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

sub enabled ($self) {
    return 0 if !$self->policy_available;
    return
      @{ GPForum::Service::Integration::Readiness->missing( 'openid',
            $self->config )
      } ? 0 : 1;
}

sub callback_url ($self) {
    my $base = $self->client->https_url( $self->config->public_base_url );
    my $path = $base->path->to_string;
    $path =~ s{/$}{}msx;
    $base->path( $path . '/auth/oidc/callback' )->query(undef);
    return "$base";
}

sub _context ($self) {
    if ( !$self->enabled ) {
        GPForum::X::Config->throw( message => 'external login is disabled' );
    }

    my @values;
    for my $field (
        qw(oidc_issuer oidc_authorization_endpoint oidc_token_endpoint oidc_jwks_uri)
      )
    {
        my $value = $self->config->$field;
        $self->client->https_url($value);
        push @values, $value;
    }

    push @values, $self->config->oidc_client_id,
      $self->config->oidc_client_secret, $self->config->oidc_signing_algorithm,
      $self->callback_url;
    if (   !length( $self->config->oidc_client_id )
        || !length( $self->config->oidc_client_secret ) )
    {
        GPForum::X::Config->throw( message =>
              'external login needs a registered confidential client' );
    }
    return sha256_hex( encode_json( \@values ) );
}

sub verify_local ( $self, @arguments ) {
    return GPForum::Service::Identity::LocalProof->new(
        credentials   => $self->credentials,
        password      => $self->password,
        second_factor => $self->second_factor
    )->verify_local(@arguments);
}

sub begin ( $self, $input = {} ) {
    my $context = $self->_context;
    my $actor   = $input->{actor_user_id};
    my $credential;
    if ( defined $actor ) {
        $credential =
          $self->verify_local( $actor, $input->{password}, $input->{code} );
        return { status => 'refused' } if !$credential;
    }
    my %flow = map { $_ => encode_base64url( urandom($TOKEN_BYTES) ) }
      qw(state nonce binding verifier);
    my $stored = $self->functions->row(
        'identity_oidc_begin',
        {
            state_hash   => sha256_hex( $flow{state} ),
            binding_hash => sha256_hex( $flow{binding} ),
            context_hash => $context,
            nonce        => $flow{nonce},
            actor        => $actor,
            credential   => $credential
        }
    );
    return { status => 'refused' } if !$stored;
    my $url =
      $self->client->https_url( $self->config->oidc_authorization_endpoint );
    $url->query(
        response_type         => 'code',
        client_id             => $self->config->oidc_client_id,
        redirect_uri          => $self->callback_url,
        scope                 => 'openid',
        state                 => $flow{state},
        nonce                 => $flow{nonce},
        code_challenge        => encode_base64url( sha256( $flow{verifier} ) ),
        code_challenge_method => 'S256'
    );

    if ( defined $actor ) {
        $url->query->append( prompt => 'login', max_age => $LINK_AUTH_SECONDS );
    }
    return { status => 'redirect', url => "$url", flow => \%flow };
}

sub complete ( $self, $input ) {
    my $state = $self->_consume_flow($input);
    return { status => 'refused' } if !$state;
    my $claims = $self->_exchange_code( $input, $state );
    return { status => 'refused' } if !$claims;
    return $self->schema->txn_do(
        sub { return $self->_accept_identity( $input, $state, $claims ); } );
}

sub complete_p ( $self, $input, $context = undef ) {
    $input =
      { %{$input}, query_context => $input->{query_context} // $context };
    return Mojo::Promise->resolve->then(
        sub {
            my $parameters = $self->_flow_parameters($input);
            return undef if !$parameters;
            return $self->functions->row_p( 'identity_oidc_consume',
                $parameters, $self->query_context );
        }
    )->then(
        sub ($row) {
            my $state = $row && $row->{result};
            return { status => 'refused' }
              if !$state
              || ( $state->{user_id} // q{} ) ne
              ( $input->{actor_user_id} // q{} );
            return $self->client->request_p(
                'POST',
                $self->config->oidc_token_endpoint,
                { form => $self->_token_form($input) }
            )->then(
                sub ($tokens) {
                    return { status => 'refused' } if !$tokens->is_success;
                    my $token = $tokens->json;
                    return { status => 'refused' } if ref $token ne 'HASH';
                    return $self->client->request_p(
                        'GET',
                        $self->config->oidc_jwks_uri,
                        { headers => { Accept => 'application/json' } }
                    )->then(
                        sub ($keys) {
                            if ( !$keys->is_success ) {
                                GPForum::X::Unavailable->throw( message =>
                                      'external signing keys unavailable' );
                            }
                            return $self->async_work->service_p(
                                $self,
                                'complete_verified',
                                {
                                    input    => $input,
                                    state    => $state,
                                    id_token => $token->{id_token},
                                    keys     => $keys->json
                                },
                                $self->query_context
                            );
                        }
                    );
                }
            );
        }
    );
}

sub complete_verified ( $self, $prepared ) {
    my $claims;
    my $state = $prepared->{state};
    try {
        $claims = $self->verify_id_token(
            $prepared->{id_token}, $prepared->{keys},
            $state->{nonce},       defined $state->{user_id}
        );
    }
    catch ($error) { return { status => 'refused' }; };
    return $self->schema->txn_do(
        sub {
            return $self->_accept_identity( $prepared->{input}, $state,
                $claims );
        }
    );
}

sub _token_form ( $self, $input ) {
    return {
        grant_type    => 'authorization_code',
        code          => $input->{code},
        redirect_uri  => $self->callback_url,
        client_id     => $self->config->oidc_client_id,
        client_secret => $self->config->oidc_client_secret,
        code_verifier => $input->{flow}{verifier}
    };
}

sub _consume_flow ( $self, $input ) {
    my $parameters = $self->_flow_parameters($input);
    return undef if !$parameters;
    my $row = $self->functions->row( 'identity_oidc_consume', $parameters );
    return undef if !$row;
    my $state = $row->{result};
    return undef
      if ( $state->{user_id} // q{} ) ne ( $input->{actor_user_id} // q{} );
    return $state;
}

sub _flow_parameters ( $self, $input ) {
    my $flow = $input->{flow};
    return undef
      if ref $flow ne 'HASH'
      || !defined $input->{state}
      || ( $flow->{state} // q{} ) ne $input->{state}
      || !defined $input->{code}
      || length( $input->{code} ) > $MAX_AUTHORIZATION_CODE;
    for my $name (qw(state binding verifier nonce)) {
        return undef
          if ( $flow->{$name} // q{} ) !~ /\A [[:alnum:]_-]{43} \z/amsx;
    }
    return {
        state_hash   => sha256_hex( $flow->{state} ),
        binding_hash => sha256_hex( $flow->{binding} ),
        context_hash => $self->_context
    };
}

sub _exchange_code ( $self, $input, $state ) {
    my $tokens = $self->client->request(
        'POST',
        $self->config->oidc_token_endpoint,
        {
            form => {
                grant_type    => 'authorization_code',
                code          => $input->{code},
                redirect_uri  => $self->callback_url,
                client_id     => $self->config->oidc_client_id,
                client_secret => $self->config->oidc_client_secret,
                code_verifier => $input->{flow}{verifier},
            }
        }
    );
    return undef if !$tokens->is_success;
    my $token = $tokens->json;
    return undef if ref $token ne 'HASH';
    my $keys = $self->client->request(
        'GET',
        $self->config->oidc_jwks_uri,
        { headers => { Accept => 'application/json' } }
    );
    if ( !$keys->is_success ) {
        GPForum::X::Unavailable->throw(
            message => 'external signing keys unavailable' );
    }
    my $claims;
    try {
        $claims = $self->verify_id_token( $token->{id_token}, $keys->json,
            $state->{nonce}, defined $state->{user_id} );
    }
    catch ($error) { return undef; };
    return $claims;
}

sub _accept_identity ( $self, $input, $state, $claims ) {
    if ( defined $state->{user_id} ) {
        my $answer = $self->functions->row(
            'identity_oidc_link',
            {
                actor      => $state->{user_id},
                credential => $state->{credential_id},
                issuer     => $self->config->oidc_issuer,
                subject    => $claims->{sub}
            }
        )->{result};
        if ( $answer->{status} eq 'linked' ) {
            $self->_audit( 'identity.oidc.linked', $state->{user_id} );
        }
        return $answer;
    }
    my $row = $self->functions->row( 'identity_oidc_resolve',
        { issuer => $self->config->oidc_issuer, subject => $claims->{sub} } );
    return { status => 'unlinked' } if !$row;
    my $member    = $row->{result};
    my $challenge = $self->second_factor->open_challenge( $member->{id},
        $member->{credential_id} );
    if ( $challenge->{status} eq 'open' ) {
        return {
            status          => 'second_factor',
            challenge_token => $challenge->{token},
            user_id         => $member->{id}
        };
    }
    return { status => 'refused' } if $challenge->{status} ne 'none';
    my $user    = GPForum::Infrastructure::ResultRow->from($member);
    my $session = $self->sessions->create_session( $user, $input );
    return { status => 'refused' } if !$session;
    $self->_audit( 'identity.oidc.login', $member->{id} );
    return {
        status        => 'ok',
        ok            => 1,
        user_id       => $member->{id},
        user          => $user,
        session_token => $session->{session_token},
        session_id    => column_of( $session->{session}, 'session_id' ),
        map { $_ => $member->{$_} }
          qw(preferred_locale preferred_theme preferred_timezone)
    };
}

sub verify_id_token ( $self, $token, $keys, $nonce, $link = 0 ) {
    if (  !defined $token
        || length($token) > $MAX_ID_TOKEN
        || $token !~
        /\A [[:alnum:]_-]+[.][[:alnum:]_-]+[.][[:alnum:]_-]+ \z/amsx
        || ref $keys ne 'HASH'
        || ref $keys->{keys} ne 'ARRAY'
        || @{ $keys->{keys} } > $MAX_SIGNING_KEYS )
    {
        GPForum::X::Argument->throw(
            message => 'invalid external identity token' );
    }
    my $claims = decode_jwt(
        token               => $token,
        kid_keys            => $keys,
        accepted_alg        => $self->config->oidc_signing_algorithm,
        verify_iss          => $self->config->oidc_issuer,
        verify_aud          => $self->config->oidc_client_id,
        verify_exp          => 1,
        verify_iat          => 1,
        allow_none          => 0,
        ignore_signature    => 0,
        key_from_jwk_header => 0,
        leeway              => $CLOCK_SKEW_SECONDS
    );
    _check_claim_shape( $claims, $nonce );
    $self->_check_authorized_party($claims);
    if (
        $link
        && (  !defined $claims->{auth_time}
            || ref $claims->{auth_time}
            || $claims->{auth_time} < time - $LINK_AUTH_SECONDS
            || $claims->{auth_time} > time + $CLOCK_SKEW_SECONDS )
      )
    {
        GPForum::X::Argument->throw( message =>
              'external link requires recent provider authentication' );
    }
    return $claims;
}

sub _check_claim_shape ( $claims, $nonce ) {
    if (   ref $claims ne 'HASH'
        || !defined $claims->{nonce}
        || ref $claims->{nonce}
        || $claims->{nonce} ne $nonce
        || !defined $claims->{sub}
        || ref $claims->{sub}
        || $claims->{sub} !~ /\A [\x20-\x7e]{1,255} \z/msx )
    {
        GPForum::X::Argument->throw(
            message => 'external identity claims refused' );
    }
    return;
}

sub _check_authorized_party ( $self, $claims ) {
    my $aud = $claims->{aud};
    if (
        ( ( ref $aud eq 'ARRAY' && @{$aud} > 1 ) || exists $claims->{azp} )
        && ( ref $claims->{azp}
            || ( $claims->{azp} // q{} ) ne $self->config->oidc_client_id )
      )
    {
        GPForum::X::Argument->throw(
            message => 'external authorized party refused' );
    }
    return;
}

sub remove_link ( $self, $input ) {
    if ( !$self->policy_available ) {
        GPForum::X::Unavailable->throw(
            message => 'integration policy unavailable' );
    }
    my $credential = $self->verify_local( $input->{actor_user_id},
        $input->{password}, $input->{code} );
    return { status => 'refused' } if !$credential;
    return $self->schema->txn_do(
        sub {
            my $answer = $self->functions->row(
                'identity_oidc_unlink',
                {
                    actor      => $input->{actor_user_id},
                    credential => $credential,
                    issuer     => $self->config->oidc_issuer,
                    session    => $input->{session_id}
                }
            )->{result};
            if ( $answer->{status} eq 'unlinked' ) {
                $self->_audit( 'identity.oidc.unlinked',
                    $input->{actor_user_id} );
            }
            return $answer;
        }
    );
}

sub _audit ( $self, $action, $actor ) {
    $self->recorder->record_audit(
        action      => $action,
        actor_id    => $actor,
        target_type => 'user',
        target_id   => $actor,
        metadata    => { issuer => $self->config->oidc_issuer }
    );
    return;
}

1;

__END__

=head1 NAME

GPForum::Service::Identity::OpenID - Authenticate explicitly linked existing accounts with pinned OpenID Connect.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $service = GPForum::Service::Identity::OpenID->new;

=head1 DESCRIPTION

Authenticate explicitly linked existing accounts with pinned OpenID Connect. Core owns configuration, authorization and presentation.

=head1 SUBROUTINES/METHODS

=head2 enabled

True when an operator configured an exact issuer; external login is otherwise disabled.

=head2 callback_url

Constructs the single callback from the configured public address, preserving its mount path.

=head2 verify_local

Requires the current local password and, when enabled, a fresh second-factor proof.

=head2 begin

Creates a five-minute single-use browser-bound authorization-code flow with S256 PKCE and nonce.

=head2 complete

Consumes state before exchanging a code, verifies signed claims and either links explicitly or opens the ordinary local MFA/session path.

=head2 verify_id_token

Pins signature algorithm, keys, issuer, audience, authorized party, nonce and time claims; no email-based matching is allowed.

=head2 remove_link

Checks local password/MFA, removes the binding and revokes other sessions and outstanding challenges while preserving the current local session.

=head2 complete_p

Consumes the login flow and performs token and key HTTP exchanges through promises; signature verification and the final transaction run in the bounded subprocess executor.

=head2 complete_verified

Completes the verified token workflow inside one subprocess transaction. Takes the token reply, signing keys and consumed flow as plain data.

=head1 DIAGNOSTICS

Invalid configuration and transport failures raise typed exceptions.

=head1 CONFIGURATION AND ENVIRONMENT

The composition layer supplies validated settings and dependencies.

=head1 DEPENDENCIES

The Good Phorum runtime and the modules named above.

=head1 INCOMPATIBILITIES

Network capabilities are independent of the frozen local Plugin API v1.

=head1 BUGS AND LIMITATIONS

External operations depend on the configured provider and its availability.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. BSD-3-Clause.

=cut
