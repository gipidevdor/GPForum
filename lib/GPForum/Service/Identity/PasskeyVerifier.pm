# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Identity::PasskeyVerifier;

use Mojo::Base -base, -signatures;
use v5.40;
use Authen::WebAuthn;
use CBOR::XS;
use Const::Fast;
use Crypt::PK::ECC;
use MIME::Base64 qw(decode_base64url encode_base64url);
use Mojo::Exception;
use Mojo::JSON qw(decode_json encode_json false true);

our $VERSION = '0.001';
const my $CLIENT_LIMIT             => 8_192;
const my $ATTESTATION_LIMIT        => 16_384;
const my $CREDENTIAL_LIMIT         => 1_023;
const my $COSE_LIMIT               => 1_024;
const my $CBOR_DEPTH               => 16;
const my $TIMEOUT_MS               => 60_000;
const my $ASSERTION_BYTES          => 37;
const my $HANDLE_LIMIT             => 64;
const my $ES256                    => -7;
const my $COSE_ALGORITHM           => 3;
const my $COORDINATE_BYTES         => 32;
const my $COSE_CURVE               => -1;
const my $COSE_X                   => -2;
const my $COSE_Y                   => -3;
const my $AUTH_FLAGS_OFFSET        => 32;
const my $CREDENTIAL_LENGTH_OFFSET => 53;
const my $CREDENTIAL_ID_OFFSET     => 55;
const my $ATTESTED_FLAG            => 0x40;
const my $EXTENSIONS_FLAG          => 0x80;
const my $BACKUP_ELIGIBLE_FLAG     => 0x08;
const my $BACKUP_STATE_FLAG        => 0x10;

has [qw(rp_id origin)];
has validator => sub ($self) {
    return Authen::WebAuthn->new(
        rp_id  => $self->rp_id,
        origin => $self->origin
    );
};

sub options ( $self, $account, $challenge ) {
    return {
        challenge => $challenge,
        rp        => { id => $self->rp_id, name => 'Good Phorum' },
        user      => {
            id          => $account->{id},
            name        => $account->{name},
            displayName => $account->{display_name},
        },
        pubKeyCredParams       => [ { type => 'public-key', alg => $ES256 } ],
        timeout                => $TIMEOUT_MS,
        attestation            => 'none',
        authenticatorSelection => {
            authenticatorAttachment => 'platform',
            residentKey             => 'required',
            requireResidentKey      => true,
            userVerification        => 'required',
        },
        excludeCredentials => [],
    };
}

sub verify ( $self, $payload, $challenge ) {
    my $result;
    try { $result = $self->_validated( $payload, $challenge ); }
    catch ($error) { Mojo::Exception->throw('registration_invalid'); };
    return $result;
}

sub _validated ( $self, $payload, $challenge ) {
    _record($payload);
    if ( ( $payload->{type} // q{} ) ne 'public-key' ) { _invalid(); }
    my $id = _binary( $payload->{rawId}, $CREDENTIAL_LIMIT );
    if ( ( $payload->{id} // q{} ) ne encode_base64url($id) ) { _invalid(); }
    my $response = $payload->{response};
    _record($response);
    my $client = _binary( $response->{clientDataJSON}, $CLIENT_LIMIT );
    my $attestation =
      _binary( $response->{attestationObject}, $ATTESTATION_LIMIT );
    my $data = decode_json($client);
    _record($data);

    if ( exists $data->{crossOrigin}
        && encode_json( $data->{crossOrigin} ) ne encode_json(false) )
    {
        _invalid();
    }
    if ( exists $data->{topOrigin} ) { _invalid(); }

    # Keep CBOR nesting bounded before handing the same bytes to the library.
    my $object = _cbor($attestation);
    _record($object);
    _record( $object->{attStmt} );
    if ( ( $object->{fmt} // q{} ) ne 'none' || keys %{ $object->{attStmt} } ) {
        _invalid();
    }

    # Check embedded COSE before it reaches the library's CBOR decoder.
    my $key = _attested_key( $object->{authData}, $id );
    _es256_key($key);
    my $result = $self->validator->validate_registration(
        challenge_b64             => $challenge,
        requested_uv              => 'required',
        client_data_json_b64      => $response->{clientDataJSON},
        attestation_object_b64    => $response->{attestationObject},
        allowed_attestation_types => ['None'],
    );
    if ( $result->{credential_id} ne $payload->{rawId} ) { _invalid(); }
    _binary( $result->{credential_pubkey}, $COSE_LIMIT );
    return {
        credential_id_b64         => $result->{credential_id},
        credential_public_key_b64 => $result->{credential_pubkey},
        sign_count                => $result->{signature_count},
        backup_eligible           => _backup_eligible( $object->{authData} ),
    };
}

sub verify_assertion ( $self, $payload, $challenge, $stored ) {
    my $result;
    try {
        $result = $self->_validated_assertion( $payload, $challenge, $stored );
    }
    catch ($error) { Mojo::Exception->throw('assertion_invalid'); };
    return $result;
}

sub _validated_assertion ( $self, $payload, $challenge, $stored ) {
    my $response = _assertion_response( $payload, $stored );
    my $auth     = _assertion_authenticator( $response, $stored );
    my $result   = $self->validator->validate_assertion(
        challenge_b64          => $challenge,
        credential_pubkey_b64  => $stored->{credential_public_key_b64},
        stored_sign_count      => 0,
        requested_uv           => 'required',
        client_data_json_b64   => $response->{clientDataJSON},
        authenticator_data_b64 => $response->{authenticatorData},
        signature_b64          => $response->{signature},
    );

    # Synced passkeys may keep a zero or nonmonotonic counter. Device-bound
    # keys with a counter must advance; PostgreSQL repeats this under lock.
    if (   !_backup_eligible($auth)
        && ( $stored->{sign_count} || $result->{signature_count} )
        && $result->{signature_count} <= $stored->{sign_count} )
    {
        _invalid();
    }
    return { sign_count => $result->{signature_count} };
}

sub _assertion_response ( $payload, $stored ) {
    _record($payload);
    _record( $payload->{response} );
    _binary( $payload->{rawId}, $CREDENTIAL_LIMIT );
    if (   ( $payload->{type} // q{} ) ne 'public-key'
        || ( $payload->{id} // q{} ) ne $payload->{rawId}
        || $payload->{rawId} ne $stored->{credential_id_b64} )
    {
        _invalid();
    }
    my $response = $payload->{response};
    my $data =
      decode_json( _binary( $response->{clientDataJSON}, $CLIENT_LIMIT ) );
    _record($data);
    if (   exists $data->{topOrigin}
        || exists $data->{crossOrigin}
        && encode_json( $data->{crossOrigin} ) ne encode_json(false) )
    {
        _invalid();
    }
    _binary( $response->{signature}, $COSE_LIMIT );
    if ( !defined $response->{userHandle}
        || _binary( $response->{userHandle}, $HANDLE_LIMIT ) ne
        decode_base64url( $stored->{user_handle} ) )
    {
        _invalid();
    }
    return $response;
}

sub _assertion_authenticator ( $response, $stored ) {
    my $auth = _binary( $response->{authenticatorData}, $CLIENT_LIMIT );
    if ( length($auth) != $ASSERTION_BYTES ) { _invalid(); }
    my $flags  = unpack 'C', substr $auth, $AUTH_FLAGS_OFFSET, 1;
    my $backup = _backup_eligible($auth);
    if (   $backup != $stored->{backup_eligible}
        || ( $flags & $BACKUP_STATE_FLAG ) && !$backup
        || ( $flags & ( $ATTESTED_FLAG | $EXTENSIONS_FLAG ) ) )
    {
        _invalid();
    }
    return $auth;
}

sub _backup_eligible ($auth) {
    my $flags = unpack 'C', substr $auth, $AUTH_FLAGS_OFFSET, 1;
    return ( $flags & $BACKUP_ELIGIBLE_FLAG ) ? 1 : 0;
}

sub _binary ( $text, $limit ) {
    if (  !defined $text
        || ref $text
        || length($text) > 2 * $limit
        || $text !~ /\A [[:alnum:]_-]+ \z/amsx )
    {
        _invalid();
    }
    my $bytes = decode_base64url($text);
    if ( length($bytes) > $limit || encode_base64url($bytes) ne $text ) {
        _invalid();
    }
    return $bytes;
}

sub _cbor ($bytes) {
    my $decoder = CBOR::XS->new_safe;
    $decoder->max_depth($CBOR_DEPTH)->filter( \&_invalid );
    return $decoder->decode($bytes);
}

sub _check_authenticator_data ($bytes) {
    if (  !defined $bytes
        || ref $bytes
        || utf8::is_utf8($bytes)
        || length($bytes) <= $CREDENTIAL_ID_OFFSET )
    {
        _invalid();
    }
    my $flags = unpack 'C', substr $bytes, $AUTH_FLAGS_OFFSET, 1;
    if (  !( $flags & $ATTESTED_FLAG )
        || ( $flags & $EXTENSIONS_FLAG )
        || ( $flags & $BACKUP_STATE_FLAG )
        && !( $flags & $BACKUP_ELIGIBLE_FLAG ) )
    {
        _invalid();
    }
    return;
}

sub _attested_key ( $bytes, $id ) {
    _check_authenticator_data($bytes);
    my $length = unpack 'n', substr $bytes, $CREDENTIAL_LENGTH_OFFSET, 2;
    if (  !$length
        || $length > $CREDENTIAL_LIMIT
        || length($id) != $length
        || substr( $bytes, $CREDENTIAL_ID_OFFSET, $length ) ne $id )
    {
        _invalid();
    }
    my $cose = substr $bytes, $CREDENTIAL_ID_OFFSET + $length;
    if ( !length($cose) || length($cose) > $COSE_LIMIT ) { _invalid(); }
    my $key = _cbor($cose);
    _record($key);
    return $key;
}

sub _es256_key ($cose) {

    # Authen::WebAuthn 0.005 leaves offered-algorithm matching to the caller.
    if (   encode_json( $cose->{$COSE_ALGORITHM} ) ne "$ES256"
        || encode_json( $cose->{1} ) ne '2'
        || encode_json( $cose->{$COSE_CURVE} ) ne '1' )
    {
        _invalid();
    }
    for my $coordinate ( $cose->{$COSE_X}, $cose->{$COSE_Y} ) {
        if (  !defined $coordinate
            || ref $coordinate
            || length($coordinate) != $COORDINATE_BYTES )
        {
            _invalid();
        }
    }

    # Import validates the public point on the advertised P-256 curve.
    Crypt::PK::ECC->new->import_key(
        {
            kty => 'EC',
            crv => 'P-256',
            x   => encode_base64url( $cose->{$COSE_X} ),
            y   => encode_base64url( $cose->{$COSE_Y} ),
        }
    );
    return;
}

sub _record ($value) {
    if ( ref $value ne 'HASH' ) { _invalid(); }
    return;
}

sub _invalid {
    Mojo::Exception->throw('registration_invalid');
}

1;

__END__

=head1 NAME

GPForum::Service::Identity::PasskeyVerifier - WebAuthn registration verification adapter.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $fields = $registration->verify($response, $expected_challenge);

=head1 DESCRIPTION

Verifies a bounded, same-origin ES256 registration using Authen::WebAuthn, returning verified fields for the transactional passkey store. Assertions require user verification and the stored opaque user handle.

=head1 SUBROUTINES/METHODS

=head2 options

Builds creation options from a trusted account and a server-generated challenge.
Requires a resident platform credential and user verification, offers ES256,
and requests no identifying attestation. Binary fields travel as Base64URL.

=head2 verify

Normalizes bounded Base64URL, rejects cross-origin ceremonies, then delegates
challenge, origin, RP hash, user presence and verification checks to
Authen::WebAuthn 0.005. Also checks credential IDs and the offered algorithm.
Returns the verified credential ID, COSE key, initial counter and backup eligibility for the transactional store.
CPAN croaks become a generic Mojo::Exception, without leaking their payloads.

=head2 verify_assertion

Verifies a discoverable ES256 assertion against the saved public key, user
handle, configured origin and RP. Requires presence and verification. Backup
eligibility must match registration; device-bound counters must advance.
PostgreSQL repeats the counter and revocation checks while holding the key.

=head1 DIAGNOSTICS

Malformed or rejected input raises the generic Mojo::Exception registration_invalid.

=head1 CONFIGURATION AND ENVIRONMENT

rp_id and origin are server-controlled attributes. No trust-anchor bypass is enabled.

=head1 DEPENDENCIES

Authen::WebAuthn, CBOR::XS and CryptX, pinned in the main cpanfile.snapshot.

=head1 INCOMPATIBILITIES

Only ES256 P-256, discoverable credentials, required UV and none attestation are offered. Authenticator extensions are not requested or accepted.

=head1 BUGS AND LIMITATIONS

Persistence, one-use challenges, configured second-factor policy and sessions belong to GPForum::Service::Identity::Passkeys.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. BSD-3-Clause.

=cut
