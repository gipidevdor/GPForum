# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use Mojo::JSON qw(decode_json);
use Test::Mojo;
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Command::AdminBootstrap;
use GPForum::Infrastructure::Id;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Service::Password;
use GPForum::Test::PgDatabase;
use GPForum::Test::PostgresHarness;
use GPForum::Web::CookieSession;

our $VERSION = '0.001';

const my $HTTP_OK           => 200;
const my $HTTP_ACCEPTED     => 202;
const my $HTTP_FOUND        => 302;
const my $HTTP_INVALID      => 400;
const my $HTTP_UNAUTHORIZED => 401;
const my $HTTP_FORBIDDEN    => 403;
const my $HTTP_CONFLICT     => 409;
const my $HTTP_TOO_MANY     => 429;
const my $PASSWORD          => 'correct horse battery staple';
const my $CODES             => 10;
const my $TRIES             => 5;
const my $LOCK              => 10;
const my $NEXT              => 1;
const my $LATER             => 1_000;
const my $SECRET_BYTES      => 20;
const my $HOUR              => 3_600;
const my $JSON              => { Accept => 'application/json' };
const my $NOW               => '2026-10-17T10:00:00Z';

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'set GPFORUM_TEST_DSN for two-step sign-in';
}

# ADR 0142 on a migrated, seeded PostgreSQL: a member sets up two-step
# sign-in with the password and a first code, signs in with a code or a
# recovery code once each, is locked after ten wrong codes, turns it off
# with the password and a code; staff see whether it is on and never the
# secret, an administrator resets it and requires it of staff; erasure
# deletes it and the export says only whether it was on.
local $ENV{GPFORUM_MINION_ENABLED}            = 0;
local $ENV{GPFORUM_REALTIME_LISTENER_ENABLED} = 0;
my $database = GPForum::Test::PgDatabase->fresh( seed => 1 );
local $ENV{GPFORUM_DATABASE_DSN} = $database->dsn;
my $schema    = $database->schema;
my $dbh       = $database->dbh;
my $functions = GPForum::Infrastructure::SqlFunction->new( schema => $schema );
my $hash      = GPForum::Service::Password->new->hash_password($PASSWORD);
my $app       = Test::Mojo->new('GPForum')->app;
my $two_step  = $app->build_controller->gp_second_factor;
my $codes     = $two_step->codes;

my $member    = _user( 'tsf_member',    0 );
my $admin     = _user( 'tsf_admin',     1 );
my $moderator = _user( 'tsf_moderator', 0 );
my $suspended = _user( 'tsf_suspended', 0 );
_grant_queue($moderator);
$dbh->do(
    q{INSERT INTO suspensions (suspension_id, user_id, actor_user_id, reason)}
      . q{ VALUES (gen_random_uuid(), ?, ?, 'second factor test')},
    undef, $suspended, $admin
);

my ( $browser, $secret, @recovery );

subtest 'a member sets it up with the password and a first code' => sub {
    $browser = _signed_in('tsf_member');
    $browser->get_ok('/settings')
      ->status_is($HTTP_OK)
      ->element_exists('a[href="/settings/security"]');
    $browser->get_ok('/settings/security')
      ->status_is($HTTP_OK)
      ->header_like( 'Cache-Control' => qr/no-store/msx );
    $browser->element_exists('form[action="/settings/security/begin"]');
    my $csrf = _csrf($browser);

    $browser->post_ok( '/settings/security/begin' => form =>
          { csrf_token => $csrf, password => 'not it' } )
      ->status_is($HTTP_FOUND);
    is( _state($member), 'off', 'a wrong password begins nothing' );
    $browser->post_ok(
        '/settings/security/begin' => form => { password => $PASSWORD } )
      ->status_is( $HTTP_FORBIDDEN,
        'a write without the CSRF token is refused' );
    is( _state($member), 'off', 'and begins nothing' );

    $browser->post_ok( '/settings/security/begin' => form =>
          { csrf_token => $csrf, password => $PASSWORD } )
      ->status_is($HTTP_FOUND);
    is( _state($member), 'pending', 'the password begins it' );
    $secret = _secret($member);
    is( length $secret, $SECRET_BYTES, 'a 160-bit secret' );
    my $stored = _row( 'second_factors', $member );
    unlike(
        $stored->{secret_sealed},
        qr/\Q${\ $codes->base32($secret)}\E/msx,
        'the database holds it sealed, never in base32'
    );

    $browser->get_ok('/settings/security')
      ->status_is($HTTP_OK)
      ->element_exists( 'svg[role="img"] path', 'the QR code is drawn here' );
    $browser->content_like(
        qr/\Q${\ $codes->grouped( $codes->base32($secret) )}\E/msx,
        'and the key is there to type' );
    $browser->content_unlike( qr{https?://[^"]*(?:chart|qr)}msx,
        'no third-party image service' );

    $browser->post_ok( '/settings/security/confirm' => form =>
          { csrf_token => $csrf, code => _wrong_code() } )
      ->status_is($HTTP_FOUND);
    is( _state($member), 'pending', 'a wrong first code turns nothing on' );

    my $other = _signed_in('tsf_member');
    $browser->post_ok( '/settings/security/confirm' => form =>
          { csrf_token => $csrf, code => _code( $secret, 0 ) } )
      ->status_is($HTTP_OK)
      ->header_like( 'Cache-Control' => qr/no-store/msx );
    @recovery = _codes_shown($browser);
    is( scalar @recovery, $CODES,   'ten recovery codes are shown once' );
    is( _state($member),  'active', 'the first right code turns it on' );
    is(
        scalar $dbh->selectrow_array(
            q{SELECT count(*) FROM second_factor_recovery_codes}
              . q{ WHERE user_id = ? AND code_hash ~ '^[0-9a-f]{64}$'},
            undef,
            $member
        ),
        $CODES,
        'kept as hashes'
    );

    for my $code (@recovery) {
        is( _containing( 'second_factor_recovery_codes', $code ),
            0, 'never in the clear' );
    }
    $browser->get_ok('/settings')->status_is( $HTTP_OK, 'this session stays' );
    $other->get_ok('/settings')
      ->status_is( $HTTP_FOUND, 'the member\'s other sessions end' );
    is( _audits('identity.second_factor.enabled'), 1, 'audited' );
    is( _mails('second_factor_enabled'), 1, 'and the member is mailed' );
    $browser->get_ok('/settings/security')
      ->status_is($HTTP_OK)
      ->element_exists('form[action="/settings/security/disable"]');
    $browser->element_exists_not( 'svg', 'no QR code once it is on' );
};

subtest 'a sign-in asks for a code, and takes each once' => sub {
    my $client = _login('tsf_member');
    is( $client->tx->res->code, $HTTP_FOUND, 'the password is accepted' );
    is( _location($client), '/login/second-factor',
        'and the second step asked for' );
    $client->get_ok('/settings')->status_is( $HTTP_FOUND, 'not signed in yet' );
    $client->get_ok('/login/second-factor')
      ->status_is($HTTP_OK)
      ->element_exists('input[name=code][autocomplete="one-time-code"]');
    my $csrf = _csrf_of($client);

    $client->post_ok(
        '/login/second-factor' => form => { code => _code( $secret, $NEXT ) } )
      ->status_is( $HTTP_FORBIDDEN, 'no CSRF token, no answer' );
    $client->post_ok( '/login/second-factor' => form =>
          { csrf_token => $csrf, code => _wrong_code() } )
      ->status_is($HTTP_UNAUTHORIZED)
      ->content_like( qr/4/msx, 'a wrong code says the tries left' );
    $client->post_ok( '/login/second-factor' => form =>
          { csrf_token => $csrf, code => _spent_code() } )
      ->status_is( $HTTP_UNAUTHORIZED, 'the code that turned it on is spent' );
    $client->post_ok( '/login/second-factor' => form =>
          { csrf_token => $csrf, code => _code( $secret, $NEXT ) } )
      ->status_is($HTTP_FOUND);
    $client->get_ok('/settings')->status_is( $HTTP_OK, 'signed in' );
    is( _audits('identity.second_factor.passed'), 1, 'the pass is audited' );

    my $again = _login('tsf_member');
    _answer( $again, _spent_code() )
      ->status_is( $HTTP_UNAUTHORIZED, 'a code is never taken twice' );

    my $recovered = _login('tsf_member');
    _answer( $recovered, uc $recovery[0] )->status_is($HTTP_FOUND);
    $recovered->get_ok('/settings')
      ->status_is( $HTTP_OK, 'a recovery code, any case, signs in' )
      ->content_like( qr/9/msx, 'and says how many are left' );
    my $replay = _login('tsf_member');
    _answer( $replay, $recovery[0] )->status_is( $HTTP_UNAUTHORIZED, 'once' );

    my $json = _login( 'tsf_member', $JSON );
    is( $json->tx->res->code, $HTTP_ACCEPTED, 'JSON is told to answer' );
    is( $json->tx->res->json('/status'), 'second_factor', 'the second step' );
};

subtest 'a challenge ends after five minutes or five wrong codes' => sub {
    _clear_failures();
    my $client = _login('tsf_member');
    $dbh->do(
        q{UPDATE second_factor_challenges SET created_at = now() - interval}
          . q{ '10 minutes', expires_at = now() - interval '5 minutes'}
          . q{ WHERE user_id = ? AND closed_at IS NULL},
        undef, $member
    );
    _answer( $client, _code( $secret, $NEXT ) )->status_is($HTTP_FOUND);
    is( _location($client), '/login', 'expired: back to login' );
    $client->get_ok('/settings')->status_is($HTTP_FOUND);

    my $tries = _login('tsf_member');
    $tries->get_ok('/login/second-factor');
    my $csrf = _csrf_of($tries);
    for ( 1 .. $TRIES - 1 ) {
        $tries->post_ok( '/login/second-factor' => form =>
              { csrf_token => $csrf, code => _wrong_code() } )
          ->status_is($HTTP_UNAUTHORIZED);
    }
    $tries->post_ok( '/login/second-factor' => form =>
          { csrf_token => $csrf, code => _wrong_code() } )
      ->status_is( $HTTP_FOUND, 'the fifth closes it' );
    _clear_failures();
};

subtest 'ten wrong codes in an hour lock sign-in and tell the member' => sub {
    my $credential = _credential($member);
    my $status;
    for my $try ( 1 .. $LOCK ) {
        my $opened = $two_step->open_challenge( $member, $credential );
        is( $opened->{status}, 'open', "challenge $try opens" );
        my $answer = $schema->txn_do(
            sub {
                return $two_step->answer(
                    $two_step->prepare_answer( $opened->{token}, '000000' ) );
            }
        );
        $status = $answer->{status};
    }
    is( $status, 'locked', 'the tenth wrong code locks' );
    is( $two_step->open_challenge( $member, $credential )->{status},
        'locked', 'no new challenge for the hour' );
    is( _mails('second_factor_locked'), 1, 'the member is mailed once' );
    is( _audits('identity.second_factor.locked'), 1, 'audited' );
    my $client = _login('tsf_member');
    is( $client->tx->res->code, $HTTP_TOO_MANY, 'the login form says so' );
    _clear_failures();
};

subtest 'the recovery codes are renewed with a fresh code' => sub {
    my $csrf = _csrf($browser);
    $browser->post_ok( '/settings/security/renew' => form =>
          { csrf_token => $csrf, code => _spent_code() } )
      ->status_is( $HTTP_FOUND, 'a spent code renews nothing' );
    _rewind($member);
    $browser->post_ok( '/settings/security/renew' => form =>
          { csrf_token => $csrf, code => _code( $secret, 0 ) } )
      ->status_is($HTTP_OK);
    my @renewed = _codes_shown($browser);
    is( scalar @renewed,         $CODES, 'ten new codes' );
    is( _recovery_left($member), $CODES, 'the old ones are gone' );
    @recovery = @renewed;
};

subtest 'staff see whether it is on, never the secret' => sub {
    my $staff = _signed_in('tsf_admin');
    $staff->get_ok( "/admin/users/$member/roles" => $JSON )
      ->status_is($HTTP_OK)
      ->json_is( '/second_factor/state' => 'active' );
    my $body = $staff->tx->res->body;
    my $row  = _row( 'second_factors', $member );
    unlike( $body, qr/\Q$row->{secret_sealed}\E/msx, 'not even sealed' );
    $staff->get_ok("/admin/users/$member/roles")
      ->status_is($HTTP_OK)
      ->element_exists(
        "form[action=\"/admin/users/$member/second-factor/reset\"]");
    $staff->get_ok('/admin/security')
      ->status_is($HTTP_OK)
      ->content_like( qr/tsf_moderator/msx, 'the staff are listed' );
    $staff->get_ok( '/admin/security' => $JSON )->status_is($HTTP_OK);
    is(
        (
            grep { $_->{username} eq 'tsf_moderator' }
              @{ $staff->tx->res->json('/staff') }
        )[0]{enabled},
        0,
        'with whether they have it'
    );
    unlike( $staff->tx->res->body, qr/secret/msx, 'and nothing of a secret' );

    _signed_in('tsf_member')
      ->get_ok('/admin/security')
      ->status_is( $HTTP_FORBIDDEN, 'members do not see it' );
    for my $table (qw(event_log outbox_messages audit_log search_documents)) {
        is( _containing( $table, $row->{secret_sealed} ),
            0, "no sealed secret in $table" );
        is( _containing( $table, $codes->base32($secret) ),
            0, "nor the secret in $table" );
    }
};

subtest 'an administrator requires it of staff' => sub {
    my $staff = _signed_in('tsf_admin');
    my $csrf  = _csrf($staff);
    $staff->post_ok( '/admin/security/policy' => $JSON => form =>
          { csrf_token => $csrf, staff_required => 1 } )
      ->status_is($HTTP_CONFLICT)
      ->json_is( '/status' => 'unenrolled', 'not without it themselves' );

    _enroll( $staff, $admin );
    $staff->post_ok(
        '/admin/security/policy' => form => { staff_required => 1 } )
      ->status_is( $HTTP_FORBIDDEN, 'no CSRF token, no change' );
    $staff->post_ok( '/admin/security/policy' => $JSON => form =>
          { csrf_token => $csrf, staff_required => 1 } )->status_is($HTTP_OK);
    is( _audits('identity.second_factor.policy_set'), 1, 'audited' );
    $staff->get_ok('/admin')
      ->status_is( $HTTP_OK, 'an enrolled admin goes on' );

    my $queue = _signed_in('tsf_moderator');
    $queue->get_ok('/moderation/reports')
      ->status_is( $HTTP_FORBIDDEN, 'staff without it are refused' );
    my $login = _login('tsf_moderator');
    is( _location($login), '/settings/security',
        'and sent to set it up when they sign in' );
    _signed_in('tsf_member')
      ->get_ok(q{/})
      ->status_is( $HTTP_OK, 'members are not affected' );
    is(
        $functions->row(
            'admin_permission_allowed',
            {
                user_id       => $moderator,
                resource_type => 'category',
                action        => 'read',
                resource_id   => undef,
                space_id      => undef,
            }
        )->{allowed} // 0,
        $functions->row(
            'admin_permission_allowed',
            {
                user_id       => $member,
                resource_type => 'category',
                action        => 'read',
                resource_id   => undef,
                space_id      => undef,
            }
        )->{allowed} // 0,
        'reading a category is not a staff console'
    );

    $staff->post_ok(
        '/admin/security/policy' => $JSON => form => { csrf_token => $csrf } )
      ->status_is($HTTP_OK);
    $queue->get_ok('/moderation/reports')
      ->status_is( $HTTP_OK, 'lifted, the queue opens again' );
};

subtest 'an administrator resets a member\'s' => sub {
    my $staff = _signed_in('tsf_admin');
    my $csrf  = _csrf($staff);
    $staff->post_ok(
        "/admin/users/$admin/second-factor/reset" => $JSON => form =>
          { csrf_token => $csrf, confirm => 1 } )
      ->status_is($HTTP_CONFLICT)
      ->json_is( '/status' => 'self', 'not their own' );
    _signed_in('tsf_moderator')
      ->post_ok( "/admin/users/$member/second-factor/reset" => form =>
          { csrf_token => $csrf, confirm => 1 } )
      ->status_is( $HTTP_FORBIDDEN, 'only administrators reset' );
    is( _state($member), 'active', 'still on' );
    $staff->post_ok(
        "/admin/users/$admin/second-factor/reset" => $JSON => form =>
          { confirm => 1 } )->status_is($HTTP_FORBIDDEN);
    $staff->post_ok(
        "/admin/users/$member/second-factor/reset" => $JSON => form =>
          { csrf_token => $csrf, confirm => 1 } )->status_is($HTTP_OK);
    is( _state($member),         'off',             'the member\'s is off' );
    is( _recovery_left($member), 0,                 'with the recovery codes' );
    is( _audits('identity.second_factor.reset'), 1, 'audited' );
    is( _mails('second_factor_reset'),           1, 'and the member mailed' );
    my $client = _login('tsf_member');
    is( _location($client), q{/}, 'the password signs in' );
};

subtest 'the member turns it off with the password and a code' => sub {
    $browser = _signed_in('tsf_member');
    _enroll( $browser, $member );
    my $csrf = _csrf($browser);
    _rewind($member);
    $browser->post_ok(
        '/settings/security/disable' => $JSON => form => {
            csrf_token => $csrf,
            password   => 'not it',
            code       => _code( $secret, 0 )
        }
    )->status_is($HTTP_INVALID)->json_is( '/status' => 'password' );
    $browser->post_ok( '/settings/security/disable' => $JSON => form =>
          { csrf_token => $csrf, password => $PASSWORD, code => _wrong_code() }
    )->status_is($HTTP_INVALID)->json_is( '/status' => 'wrong' );
    is( _state($member), 'active', 'still on' );
    $browser->post_ok( '/settings/security/disable' => $JSON => form =>
          { csrf_token => $csrf, password => $PASSWORD, code => $recovery[1] } )
      ->status_is($HTTP_OK);
    is( _state($member), 'off', 'a recovery code turns it off as well' );
    is( _mails('second_factor_disabled'),           1, 'the member is mailed' );
    is( _audits('identity.second_factor.disabled'), 1, 'audited' );
};

subtest 'a suspended member still secures the account' => sub {
    my $away = _signed_in('tsf_suspended');
    $away->get_ok('/settings/security')->status_is($HTTP_OK);
    $away->post_ok( '/settings/security/begin' => form =>
          { csrf_token => _csrf($away), password => $PASSWORD } )
      ->status_is($HTTP_FOUND);
    is( _state($suspended), 'pending', 'begun' );
    $away->post_ok(
        '/settings/security/cancel' => form => { csrf_token => _csrf($away) } )
      ->status_is($HTTP_FOUND);
    is( _state($suspended), 'off', 'and cancelled' );
    Test::Mojo->new('GPForum')
      ->get_ok( '/settings/security' => $JSON )
      ->status_is( $HTTP_UNAUTHORIZED, 'a visitor has no such page' );
    Test::Mojo->new('GPForum')
      ->get_ok('/login/second-factor')
      ->status_is( $HTTP_FOUND, 'nor a second step to answer' );
};

subtest 'the export says whether it is on; erasure deletes it' => sub {
    $browser = _signed_in('tsf_member');
    _enroll( $browser, $member );
    my $document =
      $functions->row( 'portability_export_parts', { user_id => $member } )
      ->{document};
    if ( !ref $document ) {
        $document = decode_json($document);
    }
    is( $document->{second_factor}{state},
        'active', 'the export says it is on' );
    is( $document->{second_factor}{recovery_codes_left},
        $CODES, 'with the codes left' );
    my $exported = Mojo::JSON::encode_json($document);
    my $row      = _row( 'second_factors', $member );
    unlike( $exported, qr/\Q$row->{secret_sealed}\E/msx, 'never the secret' );
    unlike( $exported, qr/[[:xdigit:]]{64}/msx, 'nor the codes\' hashes' );

    $functions->row( 'privacy_revoke_user',
        { source => 'SecondFactor', user_id => $member, at => $NOW } );
    is( _state($member),         'off', 'erasure deletes the secret' );
    is( _recovery_left($member), 0,     'the recovery codes' );
    is(
        scalar $dbh->selectrow_array(
            q{SELECT count(*) FROM second_factor_challenges WHERE user_id = ?},
            undef,
            $member
        ),
        0,
        'and the challenges'
    );
};

done_testing();

# A code from the secret, $offset steps from now.
sub _code ( $key, $offset ) {
    return $codes->code_at( $key, $codes->step_at(time) + $offset );
}

# Replay the step actually consumed, even when the runner crossed a 30-second
# boundary since it was used. A newly generated code would test a fresh step.
sub _spent_code {
    return $codes->code_at( $secret,
        _row( 'second_factors', $member )->{last_step} );
}

# A code that is none of the three a check takes now.
sub _wrong_code {
    my %taken = map { _code( $secret, $_ ) => 1 } -1 .. 2;
    my $code  = 0;
    while ( $taken{ sprintf '%06d', $code } ) {
        $code++;
    }

    return sprintf '%06d', $code;
}

sub _secret ($user_id) {
    my $row = _row( 'second_factors', $user_id );

    return $two_step->box->unseal( $row->{secret_sealed}, $user_id );
}

sub _state ($user_id) {
    my $row = _row( 'second_factors', $user_id );

    return $row ? $row->{state} : 'off';
}

sub _row ( $table, $user_id ) {
    return $dbh->selectrow_hashref( qq{SELECT * FROM $table WHERE user_id = ?},
        undef, $user_id );
}

sub _recovery_left ($user_id) {
    return scalar $dbh->selectrow_array(
        q{SELECT count(*) FROM second_factor_recovery_codes}
          . q{ WHERE user_id = ? AND used_at IS NULL},
        undef, $user_id
    );
}

# The last step taken, set back so the next code of the test is fresh.
sub _rewind ($user_id) {
    $dbh->do( q{UPDATE second_factors SET last_step = 1 WHERE user_id = ?},
        undef, $user_id );

    return;
}

# The wrong answers counted so far, and the per-address limits the test's
# many sign-ins from one address used up.
sub _clear_failures {
    $dbh->do(q{DELETE FROM second_factor_challenges});
    $dbh->do(q{DELETE FROM rate_limit_buckets});

    return;
}

sub _credential ($user_id) {
    return scalar $dbh->selectrow_array(
        q{SELECT id FROM credentials WHERE user_id = ? AND type = 'password'}
          . q{ AND revoked_at IS NULL},
        undef, $user_id
    );
}

# Turns it on for the member signed in on the browser, with its secret in
# $secret and its codes in @recovery.
sub _enroll ( $client, $user_id ) {
    my $csrf = _csrf($client);
    $client->post_ok( '/settings/security/begin' => form =>
          { csrf_token => $csrf, password => $PASSWORD } )
      ->status_is($HTTP_FOUND);
    $secret = _secret($user_id);
    $client->post_ok( '/settings/security/confirm' => form =>
          { csrf_token => $csrf, code => _code( $secret, 0 ) } )
      ->status_is($HTTP_OK);
    @recovery = _codes_shown($client);

    return;
}

sub _audits ($action) {
    return
      scalar $dbh->selectrow_array(
        q{SELECT count(*) FROM audit_log WHERE action = ?},
        undef, $action );
}

# The notice mails of a kind in the outbox, each with an address and a
# language.
sub _mails ($kind) {
    return scalar $dbh->selectrow_array(
        q{SELECT count(*) FROM outbox_messages}
          . q{ WHERE payload -> 'mail' ->> 'kind' = ?}
          . q{ AND payload -> 'mail' ->> 'to' LIKE '%@example.test'},
        undef, $kind
    );
}

sub _containing ( $table, $text ) {
    return
      scalar $dbh->selectrow_array(
        qq{SELECT count(*) FROM $table t WHERE row_to_json(t)::text LIKE ?},
        undef, "%$text%" );
}

# Where the last answer sent the browser.
sub _location ($client) {
    my $response = $client->tx->res;

    return $response->headers->location;
}

# The recovery codes the last page showed.
sub _codes_shown ($client) {
    my $dom = $client->tx->res->dom;

    return map { $_->text } $dom->find('ol code')->each;
}

sub _csrf ($test) {
    $test->get_ok('/settings');

    return _csrf_of($test);
}

sub _csrf_of ($test) {
    my $dom   = $test->tx->res->dom;
    my $input = $dom->at('input[name=csrf_token]');

    return $input ? $input->attr('value') : q{};
}

# A fresh browser that gave the password; it is answered with the second
# step when the member has it on.
sub _login ( $username, $headers = {} ) {
    my $client = Test::Mojo->new('GPForum');
    $client->get_ok('/login');
    my $csrf = _csrf_of($client);
    $client->post_ok(
        '/login' => $headers => form => {
            command_id => GPForum::Infrastructure::Id->new->uuid,
            csrf_token => $csrf,
            identifier => $username,
            password   => $PASSWORD,
        }
    );

    return $client;
}

sub _answer ( $client, $code ) {
    $client->get_ok('/login/second-factor');

    return $client->post_ok( '/login/second-factor' => form =>
          { csrf_token => _csrf_of($client), code => $code } );
}

# A browser signed in with the password, before two-step sign-in is on.
sub _signed_in ($username) {
    my $client = Test::Mojo->new('GPForum');
    my $routes = $client->app->routes;
    my ($user_id) =
      $dbh->selectrow_array( q{SELECT id FROM users WHERE username = ?},
        undef, $username );
    $routes->get('/__test/second-factor-session')->to(
        cb => sub ($c) {
            my $session =
              $c->gp_identity_store->session_store->create_session(
                { id              => $user_id },
                { request_address => '127.0.0.1', user_agent => 'test' } );
            GPForum::Web::CookieSession->new->replace_login(
                $c,
                {
                    expires_at => time + $HOUR,
                    rotation   => 'test',
                    session_id => $c->gp_identity_store->support->column(
                        $session->{session}, 'session_id'
                    ),
                    session_token => $session->{session_token},
                    user_id       => $user_id,
                }
            );
            return $c->render( json => { ok => 1 } );
        }
    );
    $client->get_ok('/__test/second-factor-session')->status_is($HTTP_OK);

    return $client;
}

# report.view_queue, for a staff member who is not an administrator.
sub _grant_queue ($user_id) {
    my ($permission) = $dbh->selectrow_array(
q{SELECT permission_id FROM permissions WHERE name = 'report.view_queue'}
    );
    my ($role) = $dbh->selectrow_array(
            q{INSERT INTO roles (role_id, name) VALUES (gen_random_uuid(),}
          . q{ 'tsf_queue_reader') RETURNING role_id} );
    $dbh->do(
        q{INSERT INTO role_permissions (role_id, permission_id) VALUES (?, ?)},
        undef, $role, $permission
    );
    $dbh->do(
        q{INSERT INTO role_bindings (binding_id, user_id, role_id,}
          . q{ resource_type) VALUES (gen_random_uuid(), ?, ?, 'global')},
        undef, $user_id, $role
    );

    return;
}

# A new active member with a password, given the bootstrap administration
# role when asked.
sub _user ( $name, $administrator ) {
    my ($id) = $dbh->selectrow_array(
        q{INSERT INTO users (id, username, display_name, email_normalized,}
          . q{ password_hash, status, email_verified_at) VALUES}
          . q{ (gen_random_uuid(), ?, ?, ?, ?, 'active', now()) RETURNING id},
        undef, $name, $name, "$name\@example.test", $hash
    );
    $dbh->do(
        q{INSERT INTO credentials (id, user_id, type, secret_hash)}
          . q{ VALUES (gen_random_uuid(), ?, 'password', ?)},
        undef, $id, $hash
    );
    if ($administrator) {
        GPForum::Test::PostgresHarness::quietly(
            sub {
                return GPForum::Command::AdminBootstrap->new->run( 'grant',
                    '--user-id', $id );
            }
        );
    }

    return $id;
}

1;
