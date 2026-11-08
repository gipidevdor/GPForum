# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

# The account flows and the mbox export as the web worker runs them. Their
# controllers reached the fork fallback: each password reset, change of
# password or address and verification ran in a forked child that opened a
# PostgreSQL connection of its own, one child at a time per worker, and so
# did every archive download. Each promise here must answer what its
# blocking write answers and leave the same rows behind, on a member of its
# own, without reaching a fork fallback; Argon2 alone runs in a child, on
# the CPU lane. The archive spooled natively must be the archive spooled
# by the blocking path, byte for byte.
package main;
use v5.40;
use Const::Fast;
use Mojo::File qw(path);
use Test::More;
use Test::Mojo;
use lib 'lib';
use lib 't/lib';
use GPForum::Benchmark::SeedDataset qw(seed_id);
use GPForum::Infrastructure::AsyncWork;
use GPForum::Service::Forum::Viewer;
use GPForum::Service::Password;
use GPForum::Test::PgDatabase;
use GPForum::Test::Promise qw(await_result);
use GPForum::Test::Forks   qw(children_during);

our $VERSION = '0.001';
const my $PASSWORD      => 'account-write-promise-password';
const my $NEW_PASSWORD  => 'account-write-promise-renewed';
const my $DAY_SECONDS   => 86_400;
const my $HTTP_ACCEPTED => 202;

# The columns a write draws for itself.
const my %DRAWN => map { $_ => 1 } qw(id session_id token_id raw_token);

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'set GPFORUM_TEST_DSN to compare account write promises';
}
my $database = GPForum::Test::PgDatabase->fresh( seed => 1 );
local $ENV{GPFORUM_DATABASE_DSN}              = $database->dsn;
local $ENV{GPFORUM_MINION_ENABLED}            = 0;
local $ENV{GPFORUM_REALTIME_LISTENER_ENABLED} = 0;
local $ENV{GPFORUM_WARMUP_ENABLED}            = 0;
my $dbh      = $database->dbh;
my $hash     = GPForum::Service::Password->new->hash_password($PASSWORD);
my $t        = Test::Mojo->new('GPForum');
my $c        = $t->app->build_controller;
my $workflow = $c->gp_identity_workflow;
my $tokens   = $workflow->store->token_store;

# Every child a write starts, recorded instead of trusted.
my $children = children_during( \&flows );
is_deeply( $children->{other}, [], 'no write reached a fork fallback' );

done_testing;

sub flows {
    subtest 'password reset'     => \&password_reset;
    subtest 'password change'    => \&password_change;
    subtest 'email change'       => \&email_change;
    subtest 'email verification' => \&email_verification;
    subtest 'controllers'        => \&controllers;
    subtest 'mbox archive'       => \&mbox_archive;
    return;
}

sub password_reset {
    my ( $a, $b ) = ( member('acw-reset-a'), member('acw-reset-b') );
    for my $identifier (
        [ username => sub ($user) { name_of($user) } ],
        [ unknown  => sub ($user) { 'nobody-' . name_of($user) } ]
      )
    {
        same_effect(
            'request_password_reset',
            sub ($user) {
                return {
                    command_id      => $c->gp_id->uuid,
                    identifier      => $identifier->[1]->($user),
                    request_address => '198.51.100.7',
                };
            },
            $a,
            $b,
            "request_password_reset ($identifier->[0])"
        );
    }

    my %session = map { $_ => session($_) } $a, $b;
    for my $case (
        [ 'a new password',    $NEW_PASSWORD ],
        [ 'the same password', $NEW_PASSWORD ],
        [ 'a short password',  'short' ],
      )
    {
        same_effect(
            'reset_password',
            sub ($user) {
                return {
                    command_id => $c->gp_id->uuid,
                    password   => $case->[1],
                    token      => issued( $user, 'password_reset' ),
                };
            },
            $a,
            $b,
            "reset_password ($case->[0])"
        );
    }
    same_effect(
        'reset_password',
        sub ($user) {
            return {
                command_id => $c->gp_id->uuid,
                password   => $NEW_PASSWORD,
                token      => 'not-a-token-' . name_of($user),
            };
        },
        $a,
        $b,
        'reset_password (an unknown token)'
    );
    ok( !live( $session{$b} ), 'the reset revoked the member\'s sessions' );
    is_deeply(
        [ map { $_->{action} } @{ account($b)->{audit} } ],
        [
            ('identity.password_reset.requested') x 1,
            ('identity.password_reset.completed') x 2,
        ],
        'the request and both completed resets are audited'
    );
    return;
}

sub password_change {
    my ( $a, $b ) = ( member('acw-change-a'), member('acw-change-b') );
    my %keep  = map { $_ => session($_) } $a, $b;
    my %other = map { $_ => session($_) } $a, $b;
    my %token = map { $_ => issued( $_, 'email_change' ) } $a, $b;
    for my $case (
        [
            'a wrong current password', 'not-the-current-password',
            $NEW_PASSWORD
        ],
        [ 'a short new password', $PASSWORD, 'short' ],
        [ 'the same password',    $PASSWORD, $PASSWORD ],
        [ 'a new password',       $PASSWORD, $NEW_PASSWORD ],
      )
    {
        same_effect(
            'change_password',
            sub ($user) {
                return {
                    command_id       => $c->gp_id->uuid,
                    current_password => $case->[1],
                    new_password     => $case->[2],
                    keep_session_id  => $keep{$user},
                    user_id          => $user,
                };
            },
            $a,
            $b,
            "change_password ($case->[0])"
        );
    }
    ok( live( $keep{$b} ) && !live( $other{$b} ),
        'the change kept the session it named and revoked the other' );
    ok(
        GPForum::Service::Password->new->verify_password(
            $NEW_PASSWORD, active_secret($b)
        ),
        'the new password is the active credential'
    );
    is_deeply(
        await_result(
            $workflow->confirm_email_change_p(
                { command_id => $c->gp_id->uuid, token => $token{$b} }
            )
        )->{status},
        'invalid',
        'the change withdrew the pending email change'
    );
    return;
}

sub email_change {
    my ( $a, $b ) = ( member('acw-email-a'), member('acw-email-b') );
    my $taken = member('acw-email-taken');
    for my $case (
        [ 'a wrong password',   'not-the-current-password', 'next' ],
        [ 'an invalid address', $PASSWORD,                  undef ],
        [ 'an address taken',   $PASSWORD,                  name_of($taken) ],
        [ 'the address held',   $PASSWORD,                  q{} ],
        [ 'a new address',      $PASSWORD,                  'next' ],
      )
    {
        same_effect(
            'request_email_change',
            sub ($user) {
                return {
                    command_id       => $c->gp_id->uuid,
                    current_password => $case->[1],
                    email            => address( $user, $case->[2] ),
                    request_address  => '198.51.100.8',
                    user_id          => $user,
                };
            },
            $a,
            $b,
            "request_email_change ($case->[0])"
        );
    }
    is_deeply(
        [ map { $_->{kind} } @{ account($b)->{mail} } ],
        [qw(email_change email_change_notice)],
        'the new address is sent its token and the one held is told'
    );

    for my $case (
        [ 'a new address',    'confirmed' ],
        [ 'an address taken', undef ],
        [ 'a used token',     'confirmed', 'used' ],
      )
    {
        my %token;
        same_effect(
            'confirm_email_change',
            sub ($user) {
                my $to =
                  defined $case->[1]
                  ? address( $user, $case->[1] )
                  : name_of($taken) . '@example.test';
                $token{$user} //= issued( $user, 'email_change', $to );
                return {
                    command_id => $c->gp_id->uuid,
                    token      => $token{$user}
                };
            },
            $a,
            $b,
            "confirm_email_change ($case->[0])"
        );
        next if !$case->[2];
        same_effect(
            'confirm_email_change',
            sub ($user) {
                return {
                    command_id => $c->gp_id->uuid,
                    token      => $token{$user}
                };
            },
            $a,
            $b,
            "confirm_email_change ($case->[2])"
        );
    }
    is(
        scalar $dbh->selectrow_array(
            'SELECT email_normalized FROM users WHERE id = ?',
            undef, $b
        ),
        address( $b, 'confirmed' ),
        'the confirmed address is the member\'s'
    );
    return;
}

sub email_verification {
    my ( $a, $b ) = (
        member( 'acw-verify-a', 'pending' ),
        member( 'acw-verify-b', 'pending' )
    );
    for my $case (
        [ 'by username', sub ($user) { { identifier => name_of($user) } } ],
        [ 'by member',   sub ($user) { { user_id    => $user } } ],
        [
            'an unknown member',
            sub ($user) { { identifier => 'nobody-' . name_of($user) } }
        ],
      )
    {
        same_effect(
            'request_email_verification',
            sub ($user) {
                return {
                    command_id      => $c->gp_id->uuid,
                    request_address => '198.51.100.9',
                    %{ $case->[1]->($user) },
                };
            },
            $a,
            $b,
            "request_email_verification ($case->[0])"
        );
    }
    for my $case ( 'a pending member', 'an active member' ) {
        same_effect(
            'verify_email',
            sub ($user) {
                return {
                    command_id => $c->gp_id->uuid,
                    token      => issued( $user, 'email_verification' ),
                };
            },
            $a,
            $b,
            "verify_email ($case)"
        );
    }
    is(
        scalar $dbh->selectrow_array(
            'SELECT status FROM users WHERE id = ?',
            undef, $b
        ),
        'active',
        'the verified member is active'
    );

    # A command sent again is answered as the log recorded it, either way.
    my %replayed;
    for my $way (qw(blocking promise)) {
        my $command = {
            command_id      => $c->gp_id->uuid,
            identifier      => 'acw-verify-replay',
            request_address => '198.51.100.9',
        };
        my $send =
          $way eq 'blocking'
          ? sub { return $workflow->request_email_verification($command) }
          : sub {
            return await_result(
                $workflow->request_email_verification_p($command) );
          };
        $send->();
        $replayed{$way} = $send->();
    }
    is_deeply( $replayed{promise}, $replayed{blocking},
        'the same command is replayed as the log recorded it' );
    return;
}

# The pages reach the native writes through call_p.
sub controllers {
    my $user = member('acw-controller');
    my $page = Test::Mojo->new( $t->app );
    my $form = $page->get_ok('/password/reset')->tx->res;
    $form = $form->dom;
    $page->post_ok(
        '/password/reset',
        form => {
            command_id => $form->at('input[name=command_id]')->attr('value'),
            csrf_token => $form->at('input[name=csrf_token]')->attr('value'),
            identifier => 'acw-controller',
        }
    )->status_is($HTTP_ACCEPTED);
    is( tokens_of($user)->[0]{token_type},
        'password_reset', 'the reset request page issues the token' );
    return;
}

sub mbox_archive {
    my $archive = $c->gp_archive;
    my $viewer  = GPForum::Service::Forum::Viewer->anonymous;
    for my $case (
        [ thread   => seed_id( thread   => 1 ) ],
        [ category => seed_id( category => 1 ) ],
      )
    {
        my ( $kind, $id ) = @{$case};
        my $blocking = $archive->spool( $kind, $id, $viewer );
        my $descriptor =
          await_result( $archive->spool_p( $kind, $id, $viewer ) );
        my $file = path( $descriptor->{path} );
        ok( -s $file, "the $kind archive is not empty" );
        is(
            $file->slurp,
            path( $blocking->filename )->slurp,
            "the $kind archive spooled natively is the blocking one"
        );
        is( $descriptor->{size}, -s $file, 'its descriptor gives its size' );
        $file->remove;
    }
    is(
        await_result( $archive->spool_p( 'thread', $c->gp_id->uuid, $viewer ) ),
        undef,
        'an unknown thread has no archive'
    );
    return;
}

# The blocking write on member $a, its promise on member $b: the same
# answer and the same rows.
sub same_effect ( $method, $input, $a, $b, $name ) {
    my $async    = $method . '_p';
    my $blocking = $workflow->$method( $input->($a) );
    my $promised = await_result( $workflow->$async( $input->($b), undef ) );
    is_deeply(
        plain( $promised, $a, $b ),
        plain( $blocking, $a, $b ),
        "$name: promise = blocking"
    );
    is_deeply(
        plain( account($b), $a, $b ),
        plain( account($a), $a, $b ),
        "$name: the same rows"
    );
    return $promised;
}

# Rows are objects of the same classes either way; compare their columns,
# with member $b's id and name read as $a's and the values each write
# draws (times, ids, hashes) left out.
sub plain ( $value, $a, $b ) {
    my $type = ref $value;
    if ( !$type ) {
        return $value if !defined $value;
        my ( $from, $to ) = map { name_of($_) } $b, $a;
        return $value =~ s/\Q$b\E/$a/grmsx =~ s/\Q$from\E/$to/grmsx =~
          s/[[:xdigit:]]{64}/<hash>/grmsx;
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

sub _drawn ($key) {
    return 1 if $key =~ /_at\z/msx || $key =~ /_hash\z/msx;
    return exists $DRAWN{$key} ? 1 : 0;
}

# What an account flow leaves behind for a member.
sub account ($user) {
    return {
        user => $dbh->selectrow_hashref( <<'SQL', undef, $user ),
SELECT status, email_normalized, email_verified_at IS NOT NULL AS verified,
       password_hash IS NOT NULL AS hashed
FROM users WHERE id = ?
SQL
        credentials => $dbh->selectall_arrayref( <<'SQL', undef, $user ),
SELECT count(*) FILTER (WHERE revoked_at IS NULL), count(*)
FROM credentials WHERE user_id = ?
SQL
        sessions => $dbh->selectall_arrayref( <<'SQL', undef, $user ),
SELECT count(*) FILTER (WHERE revoked_at IS NULL), count(*)
FROM sessions WHERE user_id = ?
SQL
        tokens => tokens_of($user),
        audit  => $dbh->selectall_arrayref( <<'SQL', { Slice => {} }, $user ),
SELECT action, metadata->>'outcome' AS outcome,
       (SELECT string_agg(k, ',' ORDER BY k) FROM jsonb_object_keys(metadata) k)
         AS keys,
       metadata->>'email_change_withdrawn' AS withdrawn,
       metadata->>'revoked_sessions' AS revoked
FROM audit_log WHERE target_id = ? ORDER BY chain_position
SQL
        mail => $dbh->selectall_arrayref( <<'SQL', { Slice => {} }, $user ),
SELECT e.payload->>'kind' AS kind, o.payload->>'to' AS recipient,
       o.payload->>'locale' AS locale, o.payload->>'sealed_token' IS NOT NULL AS sealed
FROM event_log e JOIN outbox_messages o ON o.event_id = e.event_id
WHERE e.aggregate_id = ? AND e.event_type = 'identity.mail.requested'
ORDER BY e.created_at, o.payload->>'kind'
SQL
    };
}

sub tokens_of ($user) {
    return $dbh->selectall_arrayref( <<'SQL', { Slice => {} }, $user );
SELECT token_type, email_normalized, used_at IS NOT NULL AS used,
       metadata->>'withdrawn' IS NOT NULL AS withdrawn,
       (SELECT string_agg(k, ',' ORDER BY k) FROM jsonb_object_keys(metadata) k)
         AS keys
FROM identity_tokens WHERE user_id = ? ORDER BY token_type
SQL
}

# A token issued to the member as the store issues it, its raw text
# returned: the answers never carry it.
sub issued ( $user, $type, $email = undef ) {
    return $tokens->create_token(
        {
            email_normalized => $email // name_of($user) . '@example.test',
            metadata         => {},
            token_type       => $type,
            ttl_seconds      => $DAY_SECONDS,
            user_id          => $user,
        }
    )->{raw_token};
}

# The member's address for a case: undef is invalid, empty the one held.
sub address ( $user, $suffix ) {
    return 'not-an-address'                 if !defined $suffix;
    return name_of($user) . '@example.test' if !length $suffix;
    return $suffix =~ /\A acw-/msx
      ? "$suffix\@example.test"
      : name_of($user) . "-$suffix\@example.test";
}

my %NAME;

sub name_of ($user) { return $NAME{$user}; }

sub member ( $name, $status = 'active' ) {
    my ($id) = $dbh->selectrow_array(
        <<'SQL', undef, $name, $name, "$name\@example.test", $hash, $status, $status );
INSERT INTO users (id, username, display_name, email_normalized,
    password_hash, status, email_verified_at)
VALUES (gen_random_uuid(), ?, ?, ?, ?, ?,
    CASE WHEN ? = 'active' THEN now() END) RETURNING id
SQL
    $dbh->do( <<'SQL', undef, $id, $hash );
INSERT INTO credentials (id, user_id, type, secret_hash)
VALUES (gen_random_uuid(), ?, 'password', ?)
SQL
    $NAME{$id} = $name;
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

sub live ($session) {
    return
      scalar $dbh->selectrow_array(
        'SELECT revoked_at IS NULL FROM sessions WHERE session_id = ?',
        undef, $session );
}

sub active_secret ($user) {
    return scalar $dbh->selectrow_array( <<'SQL', undef, $user );
SELECT secret_hash FROM credentials
WHERE user_id = ? AND type = 'password' AND revoked_at IS NULL
SQL
}

1;
