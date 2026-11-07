# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package main;
use v5.40;
use Test::More;
use Const::Fast;
use Test::Mojo;
use CBOR::XS;
use Crypt::PK::ECC;
use Crypt::URandom qw(urandom);
use Digest::SHA    qw(sha256 sha256_hex);
use MIME::Base64   qw(encode_base64url decode_base64url);
use Mojo::JSON     qw(encode_json decode_json false);
use Mojo::Cookie::Response;
use lib 'lib', 't/lib';
use GPForum::Infrastructure::Id;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Service::Portability::ExportBundleBuilder;
use GPForum::Service::Identity::Passkeys;
use GPForum::Test::PgDatabase;
use GPForum::Test::GuiForm;
our $VERSION = '0.001';
const my $HTTP_OK                  => 200;
const my $HTTP_BAD                 => 400;
const my $HTTP_FORBIDDEN           => 403;
const my $HTTP_ACCEPTED            => 202;
const my $HTTP_FOUND               => 302;
const my $RANDOM_BYTES             => 32;
const my $VALID_FLAGS              => 0x45;
const my $SYNCED_REGISTER_FLAGS    => 0x4d;
const my $SYNCED_ASSERTION_FLAGS   => 0x1d;
const my $VERIFIED_ASSERTION_FLAGS => 5;
const my $AAGUID_BYTES             => 16;
const my $NEXT_COUNT               => 3;
const my $MEMBER_IDS               => 4;
const my $COSE_ALGORITHM           => 3;
const my $COSE_CURVE               => -1;
const my $COSE_X                   => -2;
const my $COSE_Y                   => -3;
const my $ES256                    => -7;
const my $SYNCED_COUNT             => 5;

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'requires PostgreSQL';
}
local $ENV{GPFORUM_MINION_ENABLED}            = 0;
local $ENV{GPFORUM_REALTIME_LISTENER_ENABLED} = 0;
local $ENV{GPFORUM_PUBLIC_BASE_URL}           = 'http://localhost:3000';
my $origin = $ENV{GPFORUM_PUBLIC_BASE_URL};
my $db     = GPForum::Test::PgDatabase->fresh( seed => 1 );
local $ENV{GPFORUM_DATABASE_DSN} = $db->dsn;
my $dbh        = $db->dbh;
my $id         = GPForum::Infrastructure::Id->new;
my $password   = 'Passkey integration correct horse 2026!';
my $app        = Test::Mojo->new('GPForum')->app;
my $controller = $app->build_controller;
my $hash       = $controller->gp_password->hash_password($password);
my ( $user, $session, $token, $password_id ) = _member('passkey_member');
my ( $other, $other_session, $other_token ) = _member('passkey_other');
my $browser = _browser( $user, $session, $token );
my $private = Crypt::PK::ECC->new;
$private->generate_key('prime256v1');
my $jwk = decode_json( $private->export_key_jwk('public') );
my ( $key, $handle, $credential_id, $registered );

subtest 'GUI registration persists a real verified credential' => sub {
    $browser->get_ok('/menu')
      ->status_is($HTTP_OK)
      ->element_exists('a[href="/settings/passkeys"]');
    $browser->get_ok('/settings')
      ->status_is($HTTP_OK)
      ->element_exists('a[href="/settings/passkeys"]');
    $browser->get_ok('/settings/passkeys')->status_is($HTTP_OK);
    my $form = _dom($browser)->at('form[data-passkey="register"]');
    ok( $form, 'registration is available in the real settings GUI' );
    my $request = GPForum::Test::GuiForm->request( $form,
        { password => $password, label => 'Laptop <key>' } );
    my $headers =
      { Origin => $origin, 'X-CSRF-Token' => $request->{fields}{csrf_token} };
    $browser->post_ok( $request->{action} => $headers => form =>
          { %{ $request->{fields} }, password => 'wrong' } )
      ->status_is($HTTP_BAD);
    $browser->post_ok(
        $request->{action} => $headers => form => $request->{fields} )
      ->status_is($HTTP_OK);
    my $options = _json($browser)->{publicKey};
    is( $options->{rp}{id}, 'localhost', 'configured RP is used' );
    $handle        = $options->{user}{id};
    $credential_id = encode_base64url( urandom($RANDOM_BYTES) );
    my $payload = _registration( $options->{challenge}, $credential_id );
    my @old     = map { Mojo::Cookie::Response->new( { %{$_} } ) }
      @{ $browser->ua->cookie_jar->all };
    $browser->post_ok(
        $form->attr('data-finish') => $headers => json => $payload )
      ->status_is($HTTP_OK)
      ->json_is( '/persisted', 1 );
    ($key) = $dbh->selectrow_array( 'SELECT id FROM passkeys WHERE user_id=?',
        undef, $user );
    ok( $key, 'GUI passkey registration persists its verified public key' );
    is(
        $dbh->selectrow_array(
            q{SELECT type FROM credentials WHERE id=?},
            undef, $key
        ),
        'webauthn',
        'canonical credential type is connected'
    );
    my $jar = $browser->ua->cookie_jar;
    $jar->empty->add(@old);
    $browser->post_ok(
        $form->attr('data-finish') => $headers => json => $payload )
      ->status_is($HTTP_BAD);
    is(
        $dbh->selectrow_array(
            'SELECT count(*) FROM passkeys WHERE user_id=?',
            undef, $user
        ),
        1,
        'replayed cookie cannot register again'
    );
    $browser->get_ok('/settings/passkeys')
      ->status_is($HTTP_OK)
      ->content_like(qr/Laptop[ ]&lt;key&gt;/msx);
    $registered = $options;
};

subtest 'discoverable passkey login creates a normal server session' => sub {
    my $login = _browser();
    my ( $headers, $options, $finish ) = _login_begin($login);
    my $payload = _assertion( $options->{challenge}, 1 );
    $login->post_ok( $finish => $headers => json => $payload )
      ->status_is($HTTP_OK)
      ->json_is( '/ok', 1 );
    $login->get_ok('/settings')->status_is($HTTP_OK);
    is(
        $dbh->selectrow_array(
            'SELECT sign_count FROM passkeys WHERE id=?',
            undef, $key
        ),
        1,
        'GUI passkey login advances the saved counter'
    );
    is(
        $dbh->selectrow_array(
q{SELECT count(*) FROM audit_log WHERE actor_id=? AND action='identity.passkey.login'},
            undef,
            $user
        ),
        1,
        'passkey login writes the canonical security audit'
    );
};

subtest 'a credential cannot be assigned to a different account' => sub {
    my $foreign = _browser( $other, $other_session, $other_token );
    $foreign->get_ok('/settings/passkeys')->status_is($HTTP_OK);
    my $form = _dom($foreign)->at('form[data-passkey="register"]');
    my $req  = GPForum::Test::GuiForm->request( $form,
        { password => $password, label => 'Duplicate key' } );
    $foreign->post_ok(
        $req->{action} => { Origin => $origin } => form => $req->{fields} )
      ->status_is($HTTP_OK);
    my $options = _json($foreign)->{publicKey};
    $foreign->post_ok(
        $form->attr('data-finish') => {
            Origin         => $origin,
            'X-CSRF-Token' => $req->{fields}{csrf_token}
        } => json => _registration( $options->{challenge}, $credential_id )
    )->status_is($HTTP_BAD);
    is(
        $dbh->selectrow_array(
            'SELECT user_id FROM passkeys WHERE id=?',
            undef, $key
        ),
        $user,
        'duplicate registration preserves credential ownership'
    );
};

subtest
'wrong origin, CSRF, signatures, counters, handles and expired ceremonies fail'
  => sub {
    my $login = _browser();
    my ( $headers, $options, $finish ) = _login_begin($login);
    $login->post_ok(
        $finish => { %{$headers}, Origin => 'https://evil.test' } => json =>
          _assertion( $options->{challenge}, 2 ) )->status_is($HTTP_FORBIDDEN);
    $login->post_ok(
        $finish => { %{$headers}, 'X-CSRF-Token' => 'wrong' } => json =>
          _assertion( $options->{challenge}, 2 ) )->status_is($HTTP_FORBIDDEN);
    my $payload = _assertion( $options->{challenge}, 2 );
    $payload->{response}{signature} = encode_base64url('invalid');
    $login->post_ok( $finish => $headers => json => $payload )
      ->status_is($HTTP_BAD);
    $login->post_ok(
        $finish => $headers => json => _assertion( $options->{challenge}, 2 ) )
      ->status_is($HTTP_BAD);

    for my $case ( 'counter', 'handle', 'rp', 'uv', 'origin', 'crossOrigin' ) {
        my $b = _browser();
        my ( $h, $o, $f ) = _login_begin($b);
        $b->post_ok( $f => $h => json =>
              _assertion( $o->{challenge}, $case eq 'counter' ? 1 : 2, $case ) )
          ->status_is($HTTP_BAD);
    }
    my $expired = _browser();
    my ( $h, $o, $f ) = _login_begin($expired);
    $dbh->do(
        q{UPDATE passkey_challenges SET expires_at=now()-interval '1 second'});
    $expired->post_ok( $f => $h => json => _assertion( $o->{challenge}, 2 ) )
      ->status_is($HTTP_BAD);
    is(
        $dbh->selectrow_array(
            'SELECT sign_count FROM passkeys WHERE id=?',
            undef, $key
        ),
        1,
        'invalid assertions leave the credential unchanged'
    );
  };

subtest 'synced credentials work with zero and nonmonotonic counters' => sub {
    $browser->get_ok('/settings/passkeys')->status_is($HTTP_OK);
    my $form = _dom($browser)->at('form[data-passkey="register"]');
    my $req  = GPForum::Test::GuiForm->request( $form,
        { password => $password, label => 'Synced device' } );
    $browser->post_ok(
        $req->{action} => { Origin => $origin } => form => $req->{fields} )
      ->status_is($HTTP_OK);
    my $options = _json($browser)->{publicKey};
    my $cid     = encode_base64url( urandom($RANDOM_BYTES) );
    $browser->post_ok(
        $form->attr('data-finish') => {
            Origin         => $origin,
            'X-CSRF-Token' => $req->{fields}{csrf_token}
          } => json =>
          _registration( $options->{challenge}, $cid, $SYNCED_REGISTER_FLAGS )
    )->status_is($HTTP_OK);
    for my $count ( 0, $SYNCED_COUNT, 0 ) {
        my $login = _browser();
        my ( $h, $o, $f ) = _login_begin($login);
        $login->post_ok( $f => $h => json =>
              _assertion( $o->{challenge}, $count, 'synced', $cid ) )
          ->status_is($HTTP_OK);
    }
    is(
        $dbh->selectrow_array(
            'SELECT sign_count FROM passkeys WHERE credential_id_b64=?',
            undef, $cid
        ),
        $SYNCED_COUNT,
        'synchronized passkeys accept zero and nonmonotonic counters'
    );
    my $functions =
      GPForum::Infrastructure::SqlFunction->new( schema => $db->schema );
    my $parts =
      $functions->row( 'portability_export_parts', { user_id => $user } )
      ->{document};
    my $bundle = GPForum::Service::Portability::ExportBundleBuilder->new(
        schema => $db->schema )->build_user_bundle( $user, $parts );
    is( scalar @{ $bundle->{passkeys} },
        2, 'account export includes passkey metadata' );
    unlike(
        encode_json( $bundle->{passkeys} ),
        qr/credential_public_key|user_handle|credential_id_b64/msx,
        'export excludes cryptographic material and handles'
    );
};

subtest 'passkeys preserve the existing second-factor and recovery policy' =>
  sub {
    my $two_step = $controller->gp_second_factor;
    ok( $two_step->begin( $user, $password )->{ok},
        'begin existing TOTP enrollment' );
    my $status = $two_step->status($user);
    my $secret = $two_step->box->unseal( $status->{secret_sealed}, $user );
    my $step   = $two_step->codes->step_at(time);
    my $confirmed =
      $two_step->confirm( $user, $two_step->codes->code_at( $secret, $step ),
        $session );
    ok( $confirmed->{ok}, 'confirm existing TOTP enrollment' );
    my $login = _browser();
    my ( $h, $o, $f ) = _login_begin($login);
    $login->post_ok( $f => $h => json => _assertion( $o->{challenge}, 2 ) )
      ->status_is($HTTP_ACCEPTED)
      ->json_is( '/status', 'second_factor' );
    $login->get_ok('/settings')->status_is($HTTP_FOUND);
    $login->get_ok('/login/second-factor')->status_is($HTTP_OK);
    my $form = _dom($login)->at('form[action="/login/second-factor"]');
    my $req  = GPForum::Test::GuiForm->request( $form,
        { code => $confirmed->{recovery_codes}[0] } );
    $login->post_ok( $req->{action} => form => $req->{fields} )
      ->status_is($HTTP_FOUND);
    $login->get_ok('/settings')->status_is($HTTP_OK);
    ok( _dom($login)->at('a[href="/settings/passkeys"]'),
'GUI passkey login requires the configured second factor before opening a session'
    );

    # Disable through a fresh unused step so subsequent revocation tests exercise
    # the native password-proof form without waiting for the wall clock.
    my $code = $two_step->codes->code_at( $secret, $step + 1 );
    ok( $two_step->disable( $user, $password, $code )->{ok},
        'restore member TOTP state' );
  };

subtest 'native revocation owns the key and closes other devices' => sub {
    my $foreign = _browser( $other, $other_session, $other_token );
    $foreign->get_ok('/settings/passkeys')->status_is($HTTP_OK);
    my $csrf = _csrf($foreign);
    $foreign->post_ok(
        "/settings/passkeys/$key/revoke" => { Origin => $origin } => form =>
          { csrf_token => $csrf, password => $password } )
      ->status_is($HTTP_BAD);
    is(
        $dbh->selectrow_array(
            'SELECT revoked_at IS NULL FROM credentials WHERE id=?',
            undef, $key
        ),
        1,
        'a foreign member cannot revoke the passkey'
    );
    $browser->get_ok('/settings/passkeys')->status_is($HTTP_OK);
    my $form = _dom($browser)->at('form[action$="/revoke"]');
    my $req =
      GPForum::Test::GuiForm->request( $form, { password => $password } );
    $browser->post_ok(
        $req->{action} => { Origin => $origin } => form => $req->{fields} )
      ->status_is($HTTP_FOUND);
    ok(
        $dbh->selectrow_array(
            'SELECT revoked_at IS NOT NULL FROM credentials WHERE id=?',
            undef, $key
        ),
        'GUI revocation disables the saved passkey'
    );
    is(
        $dbh->selectrow_array(
'SELECT count(*) FROM sessions WHERE user_id=? AND revoked_at IS NULL',
            undef,
            $user
        ),
        1,
        'passkey revocation closes all other server sessions'
    );
    my $login = _browser();
    my ( $h, $o, $f ) = _login_begin($login);
    $login->post_ok(
        $f => $h => json => _assertion( $o->{challenge}, $NEXT_COUNT ) )
      ->status_is($HTTP_BAD);
};

subtest
  'password recovery revokes passkeys through the existing credential lifecycle'
  => sub {
    $browser->get_ok('/settings/passkeys')->status_is($HTTP_OK);
    my $form = _dom($browser)->at('form[data-passkey="register"]');
    my $req  = GPForum::Test::GuiForm->request( $form,
        { password => $password, label => 'Recovery test' } );
    $browser->post_ok(
        $req->{action} => { Origin => $origin } => form => $req->{fields} )
      ->status_is($HTTP_OK);
    my $o = _json($browser)->{publicKey};
    is( $o->{user}{id}, $handle, 'user handle stays stable across ceremonies' );
    $browser->post_ok(
        $form->attr('data-finish') => {
            Origin         => $origin,
            'X-CSRF-Token' => $req->{fields}{csrf_token}
        } => json => _registration(
            $o->{challenge}, encode_base64url( urandom($RANDOM_BYTES) )
        )
    )->status_is($HTTP_OK);
    $dbh->do(
'UPDATE credentials SET revoked_at=greatest(now(),created_at) WHERE id=?',
        undef, $password_id
    );
    is(
        $dbh->selectrow_array(
q{SELECT count(*) FROM credentials WHERE user_id=? AND type='webauthn' AND revoked_at IS NULL},
            undef,
            $user
        ),
        0,
        'password recovery revokes every passkey'
    );
    is(
        $dbh->selectrow_array(
            'SELECT count(*) FROM passkey_challenges WHERE user_id=?',
            undef, $user
        ),
        0,
        'password recovery invalidates pending registrations'
    );
  };
subtest 'account erasure removes passkey metadata and opaque handles' => sub {
    $dbh->do( q{UPDATE users SET status='deleted',deleted_at=now() WHERE id=?},
        undef, $user );
    is(
        $dbh->selectrow_array(
            'SELECT count(*) FROM passkeys WHERE user_id=?',
            undef, $user
        ),
        0,
        'erasure removes passkey public keys and labels'
    );
    is(
        $dbh->selectrow_array(
            'SELECT count(*) FROM passkey_accounts WHERE user_id=?',
            undef, $user
        ),
        0,
        'erasure removes opaque account handles'
    );
};

done_testing();

sub _member ($name) {
    my ( $u, $s, $t, $p ) = map { $id->uuid } 1 .. $MEMBER_IDS;
    $dbh->do(
q{INSERT INTO users(id,username,display_name,email_normalized,password_hash,status,email_verified_at) VALUES(?,?,?,?,?,'active',now())},
        undef, $u, $name, $name, "$name\@example.test", $hash
    );
    $dbh->do(
q{INSERT INTO credentials(id,user_id,type,secret_hash) VALUES(?,?,'password',?)},
        undef, $p, $u, $hash
    );
    $dbh->do(
q{INSERT INTO sessions(session_id,user_id,session_hash,expires_at) VALUES(?,?,?,now()+interval '1 day')},
        undef, $s, $u, sha256_hex($t)
    );
    return ( $u, $s, $t, $p );
}

sub _browser ( $u = undef, $s = undef, $t = undef ) {
    $dbh->do('DELETE FROM rate_limit_buckets');
    my $b      = Test::Mojo->new('GPForum');
    my $routes = $b->app->routes;
    $routes->get('/__passkeys/session')->to(
        cb => sub ($c) {
            if ($u) {
                $c->session(
                    user_id       => $u,
                    session_id    => $s,
                    session_token => $t
                );
            }
            $c->render( text => 'ready' );
        }
    );
    $b->get_ok('/__passkeys/session')->status_is($HTTP_OK);
    return $b;
}

sub _csrf ($b) {
    return _dom($b)->at('input[name="csrf_token"]')->attr('value');
}

sub _login_begin ($b) {
    $b->get_ok('/login')->status_is($HTTP_OK);
    my $form    = _dom($b)->at('form[data-passkey="login"]');
    my $request = GPForum::Test::GuiForm->request($form);
    my $headers = {
        Origin         => $origin,
        Accept         => 'application/json',
        'X-CSRF-Token' => $request->{fields}{csrf_token} // q{}
    };
    $b->post_ok( $request->{action} => $headers => form => $request->{fields} )
      ->status_is($HTTP_OK);
    return ( $headers, _json($b)->{publicKey}, $form->attr('data-finish') );
}

sub _registration ( $challenge, $cid, $flags = $VALID_FLAGS ) {
    my $raw  = decode_base64url($cid);
    my $cose = CBOR::XS::as_map(
        [
            1               => 2,
            $COSE_ALGORITHM => $ES256,
            $COSE_CURVE     => 1,
            $COSE_X         => decode_base64url( $jwk->{x} ),
            $COSE_Y         => decode_base64url( $jwk->{y} )
        ]
    );
    my $auth =
        sha256('localhost')
      . pack( 'C N', $flags, 0 )
      . ( "\0" x $AAGUID_BYTES )
      . pack( 'n', length $raw )
      . $raw
      . CBOR::XS::encode_cbor($cose);
    return {
        id       => $cid,
        rawId    => $cid,
        type     => 'public-key',
        response => {
            clientDataJSON => encode_base64url(
                encode_json(
                    {
                        type        => 'webauthn.create',
                        challenge   => $challenge,
                        origin      => $origin,
                        crossOrigin => false
                    }
                )
            ),
            attestationObject => encode_base64url(
                CBOR::XS->new->text_keys->encode(
                    {
                        fmt      => CBOR::XS::as_text('none'),
                        authData => $auth,
                        attStmt  => {}
                    }
                )
            )
        }
    };
}

sub _assertion ( $challenge, $count, $change = q{}, $cid = $credential_id ) {
    my $flags =
        $change eq 'uv'     ? 1
      : $change eq 'synced' ? $SYNCED_ASSERTION_FLAGS
      :                       $VERIFIED_ASSERTION_FLAGS;
    my $auth = sha256( $change eq 'rp' ? 'evil.test' : 'localhost' );
    $auth .= pack 'C N', $flags, $count;
    my $data = encode_json(
        {
            type        => 'webauthn.get',
            challenge   => $challenge,
            origin      => $change eq 'origin' ? 'https://evil.test' : $origin,
            crossOrigin => $change eq 'crossOrigin' ? \1             : false
        }
    );
    return {
        id       => $cid,
        rawId    => $cid,
        type     => 'public-key',
        response => {
            clientDataJSON    => encode_base64url($data),
            authenticatorData => encode_base64url($auth),
            signature         => encode_base64url(
                $private->sign_message( $auth . sha256($data), 'SHA256' )
            ),
            userHandle => $change eq 'handle'
            ? encode_base64url('wrong')
            : $handle
        }
    };
}

sub _dom  ($b) { my $response = $b->tx->res; return $response->dom; }
sub _json ($b) { my $response = $b->tx->res; return $response->json; }
1;
