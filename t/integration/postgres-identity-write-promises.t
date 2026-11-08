# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

# The identity and privacy writes as the web worker runs them. Without a
# METHOD_p call_p ran each blocking write in a forked child that opened a
# PostgreSQL connection of its own, one child at a time per worker. Each
# promise here must answer what its blocking write answers and leave the
# same rows behind, on a member of its own, without reaching a fork
# fallback; Argon2 alone runs in a child, on the CPU lane.
package main;
use v5.40;
use Const::Fast;
use Test::More;
use Test::Mojo;
use lib 'lib';
use lib 't/lib';
use GPForum::Infrastructure::AsyncWork;
use GPForum::Service::Community::Follows;
use GPForum::Service::Identity::OpenID;
use GPForum::Service::Password;
use GPForum::Test::PgDatabase;
use GPForum::Test::Promise qw(await_result);
use GPForum::Test::Forks   qw(children_during);

our $VERSION = '0.001';
const my $PASSWORD       => 'identity-write-promise-password';
const my $BIO_TOO_LONG   => 501;
const my $RECOVERY_CODES => 10;
const my $TOKEN_LENGTH   => 64;

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'set GPFORUM_TEST_DSN to compare identity write promises';
}
my $database = GPForum::Test::PgDatabase->fresh( seed => 1 );
local $ENV{GPFORUM_DATABASE_DSN}              = $database->dsn;
local $ENV{GPFORUM_MINION_ENABLED}            = 0;
local $ENV{GPFORUM_REALTIME_LISTENER_ENABLED} = 0;
local $ENV{GPFORUM_WARMUP_ENABLED}            = 0;
my $dbh  = $database->dbh;
my $hash = GPForum::Service::Password->new->hash_password($PASSWORD);
my $t    = Test::Mojo->new('GPForum');
my $c    = $t->app->build_controller;

# Every child a write starts, recorded instead of trusted.
my $children = children_during( \&writes );
is_deeply( $children->{other}, [], 'no write reached a fork fallback' );

done_testing;

sub writes {
    subtest 'relations and follows' => \&relations_and_follows;
    subtest 'notification preferences and unsubscribe' =>
      \&notification_preferences_and_unsubscribe;
    subtest 'two-step sign-in'                           => \&two_step_sign_in;
    subtest 'signing in'                                 => \&signing_in;
    subtest 'identity preferences, profile and sign-out' => \&identity_writes;
    subtest 'registering'                                => \&registering;
    subtest 'passkeys, external links and exports'       => \&local_proofs;
    return;
}

sub identity_writes {
    my ( $a, $b ) = ( member('ipw-pref-a'), member('ipw-pref-b') );
    my $workflow = $c->gp_identity_workflow;
    for my $call (
        [ update_preferred_locale => { preferred_locale => 'it' } ],
        [ update_preferred_locale => { preferred_locale => 'it' } ],
        [ update_preferred_locale => { preferred_locale => q{} } ],
        [ update_preferred_theme  => { preferred_theme  => 'dark' } ],
        [
            update_preferred_timezone => { preferred_timezone => 'Europe/Rome' }
        ],
        [ update_preferred_timezone => { preferred_timezone => 'Mars/Base' } ],
        [ update_preferred_timezone => { preferred_timezone => q{} } ],
        [ update_bio                => { bio => "two\r\nlines" } ],
        [ update_bio                => { bio => q{x} x $BIO_TOO_LONG } ],
        [ update_profile => { display_name => 'New name', bio => 'b' } ],
        [ update_profile => { display_name => 'New name', bio => 'b' } ],
        [ update_profile => { display_name => q{},        bio => 'b' } ],
      )
    {
        my ( $method, $input ) = @{$call};
        same_effect(
            $workflow,
            $method,
            sub ($user) {
                return [
                    {
                        user_id    => $user,
                        command_id => $c->gp_id->uuid,
                        %{$input},
                    }
                ];
            },
            $a,
            $b,
            $method
        );
    }
    is_deeply( user_row($b), user_row($a),
        'both members end with the same settings' );

    my $theme = {
        preferred_theme => 'high_contrast',
        user_id         => $b,
        command_id      => $c->gp_id->uuid,
    };
    my $first = await_result( $workflow->update_preferred_theme_p($theme) );
    is_deeply( await_result( $workflow->update_preferred_theme_p($theme) ),
        _recorded($first),
        'the same command is replayed as the log recorded it' );

    my %sessions = map { $_ => session($_) } $a, $b;
    for my $round ( 1, 2 ) {
        same_effect(
            $workflow,
            'logout',
            sub ($user) {
                return [
                    {
                        command_id => $c->gp_id->uuid,
                        user_id    => $user,
                        session_id => $sessions{$user},
                    }
                ];
            },
            $a,
            $b,
            "logout, round $round"
        );
    }
    same_effect(
        $workflow,
        'logout',
        sub ($user) {
            return [ { command_id => $c->gp_id->uuid, user_id => $user } ];
        },
        $a,
        $b,
        'logout without a session'
    );
    ok(
        $dbh->selectrow_array(
            'SELECT revoked_at IS NOT NULL FROM sessions WHERE session_id=?',
            undef, $sessions{$b}
        ),
        'the promise revoked the session'
    );
    return;
}

# The writes that ask for the password again: refused alike without it,
# and with it both reach the same answer.
sub local_proofs {
    my ( $a, $b ) = ( member('ipw-proof-a'), member('ipw-proof-b') );
    my $passkeys = $c->gp_passkeys;
    my $openid   = GPForum::Service::Identity::OpenID->new(
        schema           => $c->gp_schema,
        policy_available => 1,
        config           => $c->gp_config,
        password         => $c->gp_password,
        second_factor    => $c->gp_second_factor,
    );
    for my $password ( 'not the password at all', $PASSWORD ) {
        same_effect(
            $passkeys,
            'revoke',
            sub ($user) {
                return [
                    {
                        user_id  => $user,
                        id       => $c->gp_id->uuid,
                        password => $password,
                    }
                ];
            },
            $a,
            $b,
            'passkey revoke'
        );
        same_effect(
            $openid,
            'remove_link',
            sub ($user) {
                return [ { actor_user_id => $user, password => $password } ];
            },
            $a,
            $b,
            'external link removal'
        );
    }
    same_effect( $c->gp_data_rights_review, 'completed_export_for_user',
        sub ($user) { return [ $user, $c->gp_id->uuid ] },
        $a, $b, 'no completed export' );
    return;
}

sub registering {
    my $workflow = $c->gp_identity_workflow;
    my $input    = sub ($name) {
        return {
            command_id   => $c->gp_id->uuid,
            display_name => "Display $name",
            email        => "$name\@example.test",
            password     => $PASSWORD,
            username     => $name,
        };
    };
    my $blocking = $workflow->register( $input->('ipw_reg_a') );
    my $command  = $input->('ipw_reg_b');
    my $promised = await_result( $workflow->register_p($command) );
    is( $promised->{status}, 'ok', 'the promise registers the account' );
    is_deeply(
        [ sort keys %{ $promised->{stored} } ],
        [ sort keys %{ $blocking->{stored} } ],
        'register: promise = blocking'
    );
    my ($stored_hash) =
      $dbh->selectrow_array( 'SELECT password_hash FROM users WHERE username=?',
        undef, 'ipw_reg_b' );
    ok(
        GPForum::Service::Password->new->verify_password(
            $PASSWORD, $stored_hash
        ),
        'the password is stored as its Argon2 hash'
    );
    is( await_result( $workflow->register_p($command) )->{status},
        'ok', 'the same command is replayed' );
    is(
        await_result(
            $workflow->register_p(
                { %{ $input->('ipw_reg_b') }, email => 'other@example.test' }
            )
        )->{status},
        'invalid',
        'a taken username is refused'
    );
    is(
        await_result(
            $workflow->register_p(
                { %{ $input->('x') }, password => 'short' }
            )
        )->{status},
        'invalid',
        'a refused form is refused'
    );
    return;
}

sub relations_and_follows {
    my $target = member('ipw-target');
    my ( $a, $b ) = ( member('ipw-rel-a'), member('ipw-rel-b') );
    my $relations = $c->gp_relation_store;
    for my $call (
        [ set_relation    => { username => 'ipw-target',  kind => 'ignore' } ],
        [ set_relation    => { username => 'ipw-target',  kind => 'block' } ],
        [ set_relation    => { username => 'ipw-target',  kind => 'block' } ],
        [ set_relation    => { username => q{},           kind => 'block' } ],
        [ set_relation    => { username => 'nobody-here', kind => 'block' } ],
        [ remove_relation => { username => 'ipw-target' } ],
        [ remove_relation => { username => 'ipw-target' } ],
      )
    {
        my ( $method, $input ) = @{$call};
        same_effect(
            $relations,
            $method,
            sub ($owner) {
                return [ { owner_user_id => $owner, %{$input} } ];
            },
            $a,
            $b,
            "$method " . ( $input->{kind} // 'remove' )
        );
    }
    is_deeply( relation_rows($b), relation_rows($a),
        'both members end with the same list' );

    my $follows =
      GPForum::Service::Community::Follows->new( schema => $c->gp_schema );
    for my $operation (qw(follow follow unfollow)) {
        same_effect(
            $follows, 'change',
            sub ($actor) {
                return [
                    {
                        actor     => $actor,
                        command   => $c->gp_id->uuid,
                        username  => 'ipw-target',
                        operation => $operation,
                    }
                ];
            },
            $a,
            $b,
            "follow change $operation"
        );
    }
    is(
        await_result(
            $follows->change_p( { actor => $a, command => 'not-a-uuid' } )
        )->{status},
        'invalid',
        'a malformed command is refused before the database'
    );
    return;
}

sub notification_preferences_and_unsubscribe {
    my ( $a, $b ) = ( member('ipw-note-a'), member('ipw-note-b') );
    my $store = $c->gp_notification_preference_store;
    for my $scope (qw(reply digest all reply bogus)) {
        same_effect( $store, 'unsubscribe',
            sub ($user) { return [ { user_id => $user, scope => $scope } ] },
            $a, $b, "unsubscribe $scope" );
    }

    my $workflow = $c->gp_notification_workflow;
    my $input    = sub ($user) {
        return {
            user_id     => $user,
            preferences => [
                {
                    channel          => 'email',
                    enabled          => 1,
                    digest_frequency => 'daily'
                },
                { channel => 'in_app', enabled => 0 },
            ],
            type_preferences =>
              [ { event_type => 'reply', channel => 'email', enabled => 0 }, ],
        };
    };
    my $command  = $c->gp_id->uuid;
    my $blocking = $workflow->set_preferences(
        { %{ $input->($a) }, command_id => $c->gp_id->uuid } );
    my $promised = await_result(
        $workflow->set_preferences_p(
            { %{ $input->($b) }, command_id => $command }
        )
    );
    is_deeply(
        plain( $promised, $a, $b ),
        plain( $blocking, $a, $b ),
        'set_preferences: promise = blocking'
    );
    ok( $promised->{ok}, 'the preferences are stored' );
    is_deeply(
        await_result(
            $workflow->set_preferences_p(
                { %{ $input->($b) }, command_id => $command }
            )
        ),
        $promised,
        'the same command is replayed from the log'
    );
    is(
        await_result(
            $workflow->set_preferences_p(
                { %{ $input->($a) }, command_id => $command }
            )
        )->{status},
        'conflict',
        'the command id of another request is a conflict'
    );
    my $refused = await_result(
        $workflow->set_preferences_p(
            {
                user_id     => $b,
                command_id  => $c->gp_id->uuid,
                preferences => [ { channel => 'pigeon', enabled => 1 } ],
            }
        )
    );
    is( $refused->{status}, 'invalid', 'an unknown channel is refused' );
    is_deeply( preference_rows($b), preference_rows($a),
        'both members end with the same preferences' );

    my $tokens = $c->gp_unsubscribe_tokens;
    my $token  = $tokens->issue( $a, 'reply' );
    for my $candidate ( $token, "${token}x", undef ) {
        is_deeply(
            await_result( $tokens->verify_p( $candidate, undef ) ),
            $tokens->verify($candidate),
            'verify: promise = blocking'
        );
    }
    is(
        await_result( $c->gp_passkeys->origin_p(undef) ),
        $c->gp_passkeys->origin,
        'origin: promise = blocking'
    );
    return;
}

sub two_step_sign_in {
    my ( $a, $b ) = ( member('ipw-2fa-a'), member('ipw-2fa-b') );
    my $two_step = $c->gp_second_factor;
    if ( !$two_step->available ) {
        plan skip_all => q{no second factor keys};
    }
    for my $password ( 'wrong password here', $PASSWORD ) {
        same_effect( $two_step, 'begin',
            sub ($user) { return [ $user, $password ] },
            $a, $b, 'begin' );
    }
    my $enrolled = await_result( $two_step->enrollment_p( $b, 'Forum' ) );
    like( $enrolled->{uri}, qr/\Aotpauth:/msx, 'the enrollment link' );
    is_deeply(
        [ sort keys %{$enrolled} ],
        [ sort keys %{ $two_step->enrollment( $a, 'Forum' ) } ],
        'enrollment: promise = blocking'
    );
    same_effect( $two_step, 'confirm',
        sub ($user) { return [ $user, '000000', undef ] },
        $a, $b, 'a wrong first code' );
    same_effect( $two_step, 'renew', sub ($user) { return [ $user, '1' ] },
        $a, $b, 'renew while pending' );
    same_effect( $two_step, 'disable',
        sub ($user) { return [ $user, $PASSWORD, '1' ] },
        $a, $b, 'disable while pending' );
    same_effect( $two_step, 'cancel', sub ($user) { return [$user] },
        $a, $b, 'cancel' );
    is( await_result( $two_step->status_p($b) )->{state},
        'off', 'the enrollment is dropped' );

    my $codes = $two_step->codes;
    await_result( $two_step->begin_p( $b, $PASSWORD ) );
    my $code = sub ($offset) {
        my $secret =
          $two_step->box->unseal( $two_step->status($b)->{secret_sealed}, $b );
        return $codes->code_at( $secret, $codes->step_at(time) + $offset );
    };
    my $confirmed =
      await_result( $two_step->confirm_p( $b, $code->(0), undef ) );
    ok( $confirmed->{ok}, 'the first code turns it on' );
    is( scalar @{ $confirmed->{recovery_codes} },
        $RECOVERY_CODES, 'with the recovery codes' );

    my $workflow = $c->gp_identity_workflow;
    my $login    = await_result(
        $workflow->login_p(
            { identifier => 'ipw-2fa-b', password => $PASSWORD }
        )
    );
    is( $login->{status}, 'second_factor', 'the sign-in asks for a code' );
    my $token = $login->{stored}{challenge_token};
    is(
        await_result(
            $workflow->complete_second_factor_p(
                { challenge_token => $token, code => '000000' }
            )
        )->{status},
        'wrong',
        'a wrong code is counted'
    );
    my $passed = await_result(
        $workflow->complete_second_factor_p(
            {
                challenge_token => $token,
                code            => $code->(1),
                request_address => '192.0.2.1',
                user_agent      => 'promise',
            }
        )
    );
    is( $passed->{status},         'ok',   'the right code opens the session' );
    is( $passed->{stored}{method}, 'totp', 'by the app' );
    ok(
        $dbh->selectrow_array(
            'SELECT 1 FROM sessions WHERE session_id=? AND user_id=?', undef,
            $passed->{stored}{session_id},                             $b
        ),
        'the session is stored'
    );
    is(
        await_result(
            $two_step->disable_p(
                $b, $PASSWORD, $confirmed->{recovery_codes}[0]
            )
        )->{status},
        'ok',
        'a recovery code turns it off'
    );
    return;
}

sub signing_in {
    my ( $a, $b ) = ( member('ipw-login-a'), member('ipw-login-b') );
    my $workflow = $c->gp_identity_workflow;
    for my $case (
        [ 'right password', $PASSWORD,                 'ok' ],
        [ 'wrong password', 'not the password at all', 'rejected' ],
      )
    {
        my ( $name, $password, $status ) = @{$case};
        my $blocking = $workflow->login(
            { identifier => 'ipw-login-a', password => $password } );
        my $promised = await_result(
            $workflow->login_p(
                {
                    identifier      => 'IPW-login-b',
                    password        => $password,
                    request_address => '192.0.2.1',
                    user_agent      => 'promise',
                }
            )
        );
        is( $promised->{status}, $status, "$name: $status" );
        is_deeply(
            [ sort keys %{ $promised->{stored} || {} } ],
            [ sort keys %{ $blocking->{stored} || {} } ],
            "$name: promise = blocking"
        );
        is( $promised->{error}, $blocking->{error}, "$name: same error" );
    }
    is(
        await_result(
            $workflow->login_p(
                { identifier => 'nobody-at-all', password => $PASSWORD }
            )
        )->{status},
        'rejected',
        'an unknown account is refused in the same words'
    );
    is(
        await_result(
            $workflow->complete_second_factor_p(
                { challenge_token => 'f' x $TOKEN_LENGTH, code => '1' }
            )
        )->{status},
        'expired',
        'a challenge nobody opened has expired'
    );
    return;
}

# METHOD on member $a and METHOD_p on member $b, with the arguments each
# member's own; the answers must match once the members' ids are swapped.
sub same_effect ( $service, $method, $arguments, $a, $b, $name ) {
    my $async    = $method . '_p';
    my $blocking = $service->$method( @{ $arguments->($a) } );
    my $promised =
      await_result( $service->$async( @{ $arguments->($b) }, undef ) );
    is_deeply(
        plain( $promised, $a, $b ),
        plain( $blocking, $a, $b ),
        "$name: promise = blocking"
    );
    return $promised;
}

# Rows are objects of the same classes either way; compare their columns,
# with member $b's id read as $a's and the values each write draws (times,
# ids) left out.
sub plain ( $value, $a, $b ) {
    my $type = ref $value;
    if ( !$type ) {
        return $value if !defined $value;
        return $value =~ s/\Q$b\E/$a/grmsx;
    }
    return [ map { plain( $_, $a, $b ) } @{$value} ] if $type eq 'ARRAY';
    return {
        map  { $_ => plain( $value->{$_}, $a, $b ) }
        grep { !_drawn($_) }
          keys %{$value}
      }
      if $type eq 'HASH' || $value->isa('HASH');
    return "$type";
}

# The columns a write draws for itself, or names its member by.
sub _drawn ($key) {
    return 1 if $key =~ /_at\z/msx || $key =~ /_hash\z/msx;
    return $key =~ /\A(?:id|session_id|username|display_name|email\w*)\z/msx
      ? 1
      : 0;
}

# What the command log recorded of a first answer: a replay answers that.
sub _recorded ($answer) {
    return {
        %{$answer},
        stored => {
            ok => $answer->{stored}{ok},
        },
    };
}

sub member ($name) {
    my ($id) = $dbh->selectrow_array(
        <<'SQL', undef, $name, $name, "$name\@example.test", $hash );
INSERT INTO users (id, username, display_name, email_normalized,
    password_hash, status, email_verified_at)
VALUES (gen_random_uuid(), ?, ?, ?, ?, 'active', now()) RETURNING id
SQL
    $dbh->do( <<'SQL', undef, $id, $hash );
INSERT INTO credentials (id, user_id, type, secret_hash)
VALUES (gen_random_uuid(), ?, 'password', ?)
SQL
    return $id;
}

sub session ($user) {
    my ($id) = $dbh->selectrow_array( <<'SQL', undef, $user );
INSERT INTO sessions (session_id, user_id, session_hash, expires_at)
VALUES (gen_random_uuid(), ?, md5(random()::text), now() + interval '1 day')
RETURNING session_id
SQL
    return $id;
}

sub relation_rows ($owner) {
    return $dbh->selectall_arrayref( <<'SQL', { Slice => {} }, $owner );
SELECT r.kind, u.username FROM member_relations r
JOIN users u ON u.id = r.other_user_id WHERE r.owner_user_id = ? ORDER BY 2
SQL
}

sub preference_rows ($user) {
    return [
        @{ $dbh->selectall_arrayref( <<'SQL', { Slice => {} }, $user ) },
SELECT channel, enabled, digest_frequency FROM notification_preferences
WHERE user_id = ? ORDER BY channel
SQL
        @{ $dbh->selectall_arrayref( <<'SQL', { Slice => {} }, $user ) },
SELECT event_type, channel, enabled FROM notification_type_preferences
WHERE user_id = ? ORDER BY event_type, channel
SQL
    ];
}

sub user_row ($user) {
    return $dbh->selectrow_hashref( <<'SQL', undef, $user );
SELECT preferred_locale, preferred_theme, preferred_timezone, bio,
       display_name FROM users WHERE id = ?
SQL
}

1;
