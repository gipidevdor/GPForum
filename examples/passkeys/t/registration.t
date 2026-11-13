# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;
use FindBin qw($Bin);
use lib "$Bin/../local/lib/perl5", "$Bin/../lib";
use CBOR::XS;
use Const::Fast;
use Crypt::PK::ECC;
use Crypt::URandom qw(urandom);
use Digest::SHA    qw(sha256);
use MIME::Base64   qw(decode_base64url encode_base64url);
use Mojo::Cookie::Response;
use Mojo::Home;
use Mojo::JSON qw(decode_json encode_json false true);
use Test::Mojo;
use Test::More;
use GPForum::Example::Passkeys::App;

our $VERSION = '0.001';
const my $ORIGIN            => 'http://localhost:3000';
const my $CHALLENGE_PATH    => '/api/passkey/register/challenge';
const my $VERIFY_PATH       => '/api/passkey/register/verify';
const my $RANDOM_BYTES      => 32;
const my $AAGUID_BYTES      => 16;
const my $COSE_ALGORITHM    => 3;
const my $COSE_CURVE        => -1;
const my $COSE_X            => -2;
const my $COSE_Y            => -3;
const my $UNEXPECTED_TAG    => 42;
const my $HTTP_NOT_FOUND    => 404;
const my $ES256             => -7;
const my $VALID_FLAGS       => 0x45;
const my $SYNCED_FLAGS      => 0x5d;
const my $HTTP_OK           => 200;
const my $HTTP_BAD_REQUEST  => 400;
const my $HTTP_UNAUTHORIZED => 401;
const my $HTTP_FORBIDDEN    => 403;
const my $HTTP_CONFLICT     => 409;
const my $EXPIRED_SECONDS   => 301;

local $ENV{GPFORUM_PASSKEY_DEMO_ORIGIN} = $ORIGIN;
local $ENV{MOJO_LOG_LEVEL}              = 'fatal';
local $ENV{GPFORUM_PASSKEY_DEMO_SECRET} =
  'test-secret-for-the-isolated-passkey-example';

my $private = Crypt::PK::ECC->new;
$private->generate_key('prime256v1');
my $jwk = decode_json( $private->export_key_jwk('public') );

subtest 'session, exact origin, CSRF and JSON are required' => sub {
    my $t = _client();
    $t->post_ok( $CHALLENGE_PATH => { Origin => $ORIGIN } => json => {} )
      ->status_is($HTTP_UNAUTHORIZED);
    my $headers = _session($t);
    $t->post_ok(
        $CHALLENGE_PATH => { %{$headers}, Origin => 'https://evil.test' } =>
          json => {} )
      ->status_is($HTTP_FORBIDDEN)
      ->json_is( '/error' => 'origin_invalid' );
    $t->post_ok( $CHALLENGE_PATH => { Origin => $ORIGIN } => json => {} )
      ->status_is($HTTP_FORBIDDEN)
      ->json_is( '/error' => 'csrf_invalid' );
    $t->post_ok( $CHALLENGE_PATH => $headers => form => {} )
      ->status_is($HTTP_BAD_REQUEST)
      ->json_is( '/error' => 'json_required' );
    $t->get_ok($CHALLENGE_PATH)->status_is($HTTP_NOT_FOUND);
    $t->get_ok('/passkeys.mjs')
      ->status_is($HTTP_OK)
      ->content_type_like(qr{javascript}msx);
};

subtest
'real Authen::WebAuthn accepts a valid P-256 registration and consumes its cookie nonce'
  => sub {
    my $t       = _client();
    my $headers = _session($t);
    my $options = _begin( $t, $headers );
    is( length decode_base64url( $options->{challenge} ),
        $RANDOM_BYTES, '32 cryptographically random bytes' );
    is( $options->{rp}{id},
        'localhost', 'RP ID is configured, without scheme or port' );
    is( $options->{authenticatorSelection}{userVerification},
        'required', 'verification is mandatory' );
    is( $options->{authenticatorSelection}{residentKey},
        'required', 'a discoverable credential is requested' );
    my $jar = $t->ua->cookie_jar;
    my @old_cookies =
      map { Mojo::Cookie::Response->new( { %{$_} } ) } @{ $jar->all };
    my $payload = _credential( $options->{challenge} );
    $t->post_ok( $VERIFY_PATH => $headers => json => $payload )
      ->status_is($HTTP_OK);
    my $reply = $t->tx->res->json;
    is( encode_json( $reply->{verified} ),
        'true', 'the response confirms verification' );
    is( encode_json( $reply->{persisted} ),
        'false', 'the verified key is explicitly not persisted' );
    $jar->empty->add(@old_cookies);
    $t->post_ok( $VERIFY_PATH => $headers => json => $payload )
      ->status_is($HTTP_CONFLICT)
      ->json_is( '/error' => 'challenge_expired_or_used' );
  };

subtest
'server binding, verification and binary input are enforced by the real verifier'
  => sub {
    my @bad = (
        [ origin             => 'https://evil.test' ],
        [ rp                 => 'evil.test' ],
        [ challenge          => 'different-challenge' ],
        [ type               => 'webauthn.get' ],
        [ flags              => 0x41 ],
        [ flags              => 0x44 ],
        [ flags              => 0x55 ],
        [ flags              => 0xc5 ],
        [ algorithm          => -257 ],
        [ crossOrigin        => true ],
        [ topOrigin          => 'https://parent.test' ],
        [ nonempty_statement => 1 ],
        [ tagged_key         => 1 ],
        [ invalid_point      => 1 ],
    );
    for my $case (@bad) {
        my $t       = _client();
        my $headers = _session($t);
        my $options = _begin( $t, $headers );
        my $payload = _credential( $options->{challenge}, @{$case} );
        $t->post_ok( $VERIFY_PATH => $headers => json => $payload )
          ->status_is($HTTP_BAD_REQUEST)
          ->json_is( '/error' => 'registration_invalid' );
        unlike(
            $t->tx->res->body,
            qr/\Q$options->{challenge}\E/msx,
            'no challenge or CPAN exception leaked'
        );
        $t->post_ok( $VERIFY_PATH => $headers => json => $payload )
          ->status_is($HTTP_CONFLICT);
    }
    for my $bad ( '***', 'A', 'AA==', 'AB' ) {
        my $t       = _client();
        my $headers = _session($t);
        my $options = _begin( $t, $headers );
        my $payload = _credential( $options->{challenge} );
        $payload->{response}{clientDataJSON} = $bad;
        $t->post_ok( $VERIFY_PATH => $headers => json => $payload )
          ->status_is($HTTP_BAD_REQUEST)
          ->json_is( '/error' => 'registration_invalid' );
    }
  };

subtest 'expiration, replacement and synchronization flags' => sub {
    my $t           = _client();
    my $headers     = _session($t);
    my $first       = _begin( $t, $headers );
    my $replacement = _begin( $t, $headers );
    isnt(
        $first->{challenge},
        $replacement->{challenge},
        'each request gets a fresh challenge'
    );
    ok(
        !$t->app->challenges->consume(
            $replacement->{user}{id},
            $first->{challenge}
        ),
        'replacement invalidates old cookie nonce'
    );
    $t->post_ok( $VERIFY_PATH => $headers => json =>
          _credential( $replacement->{challenge}, flags => $SYNCED_FLAGS ) )
      ->status_is($HTTP_OK);
    my $now = time;
    $t->app->challenges->clock( sub { return $now; } );
    my $expires = _begin( $t, $headers );
    $now += $EXPIRED_SECONDS;
    $t->post_ok( $VERIFY_PATH => $headers => json =>
          _credential( $expires->{challenge} ) )->status_is($HTTP_CONFLICT);
};

done_testing();

sub _client {
    return Test::Mojo->new(
        GPForum::Example::Passkeys::App->new(
            home => Mojo::Home->new("$Bin/..")
        )
    );
}

sub _session ($t) {
    $t->get_ok(q{/})->status_is($HTTP_OK);
    my $dom = $t->tx->res->dom;
    return {
        Origin         => $ORIGIN,
        'X-CSRF-Token' => $dom->at('meta[name="csrf-token"]')->attr('content')
    };
}

sub _begin ( $t, $headers ) {
    $t->post_ok( $CHALLENGE_PATH => $headers => json => {} )
      ->status_is($HTTP_OK)
      ->header_is( 'Cache-Control' => 'private, no-store' );
    return $t->tx->res->json->{publicKey};
}

sub _credential ( $challenge, %change ) {
    my $id  = urandom($RANDOM_BYTES);
    my $key = CBOR::XS::as_map(
        [
            1               => 2,
            $COSE_ALGORITHM => ( $change{algorithm} // $ES256 ),
            $COSE_CURVE     => 1,
            $COSE_X => $change{invalid_point} ? pack( 'C', 0 ) x $RANDOM_BYTES
            : decode_base64url( $jwk->{x} ),
            $COSE_Y => $change{invalid_point} ? pack( 'C', 0 ) x $RANDOM_BYTES
            : decode_base64url( $jwk->{y} ),
        ]
    );
    if ( $change{tagged_key} ) {
        $key = CBOR::XS::tag( $UNEXPECTED_TAG, $key );
    }
    my $auth =
        sha256( $change{rp} // 'localhost' )
      . pack( 'C N', $change{flags} // $VALID_FLAGS, 0 )
      . ( pack( 'C', 0 ) x $AAGUID_BYTES )
      . pack( 'n', length $id )
      . $id
      . CBOR::XS::encode_cbor($key);
    my $client_data = {
        type        => $change{type}        // 'webauthn.create',
        challenge   => $change{challenge}   // $challenge,
        origin      => $change{origin}      // $ORIGIN,
        crossOrigin => $change{crossOrigin} // false,
    };
    if ( exists $change{topOrigin} ) {
        $client_data->{topOrigin} = $change{topOrigin};
    }
    return {
        id       => encode_base64url($id),
        rawId    => encode_base64url($id),
        type     => 'public-key',
        response => {
            clientDataJSON    => encode_base64url( encode_json($client_data) ),
            attestationObject => encode_base64url(
                CBOR::XS->new->text_keys->encode(
                    {
                        fmt      => CBOR::XS::as_text('none'),
                        authData => $auth,
                        attStmt  => $change{nonempty_statement}
                        ? { unexpected => 1 }
                        : {},
                    }
                )
            ),
        },
    };
}

1;
