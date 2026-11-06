# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use English     qw(-no_match_vars);
use POSIX       qw(_exit :sys_wait_h);
use Time::HiRes qw(sleep time);
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Config;
use GPForum::Infrastructure::Id;
use GPForum::Schema;
use GPForum::Service::Identity::Store;
use GPForum::Service::Password;
use GPForum::Test::HoldingSessionStore;
use GPForum::Test::InterposingPassword;
use GPForum::Test::PgDatabase;
use GPForum::Test::SkewedClock;

our $VERSION = '0.001';

const my $OLD_PASSWORD    => 'correct horse battery staple';
const my $MEMBER_PASSWORD => 'the member reset the password to this';
const my $OTHER_PASSWORD  => 'whoever knew the old one chose this';
const my $WAIT_SECONDS    => 15;
const my $POLL_SECONDS    => 0.05;
const my $CHILD_FAILURE   => 3;
const my $AHEAD           => 2;
const my $USER_SQL => join q{ },
  'INSERT INTO users (id, username, display_name, email_normalized,',
  q{password_hash, status, email_verified_at)},
  q{VALUES (?, ?, ?, ?, ?, 'active', now())};
const my $CREDENTIAL_SQL => join q{ },
  'INSERT INTO credentials (id, user_id, type, secret_hash, created_at)',
  q{VALUES (?, ?, 'password', ?, now() - interval '1 day')};
const my $SESSION_SQL => join q{ },
  'INSERT INTO sessions (session_id, user_id, session_hash, created_at,',
  q{last_seen_at, expires_at) VALUES (?, ?, ?, now() - interval '1 hour',},
  q{now() - interval '1 hour', now() + interval '1 day')};
const my $ACTIVE_SQL => join q{ },
  'SELECT count(*) FROM credentials',
  q{WHERE user_id = ? AND type = 'password' AND revoked_at IS NULL};
const my $USER_HASH_SQL => 'SELECT password_hash FROM users WHERE id = ?';
const my $LOCK_WAITERS_SQL => join q{ },
  'SELECT count(*) FROM pg_stat_activity',
  q{WHERE datname = current_database() AND wait_event_type = 'Lock'};

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'set GPFORUM_TEST_DSN to run against PostgreSQL';
}

# A password change verifies the current password before its transaction,
# and a reset or a change rotated whatever credential it found once it had
# the lock. Racing each other, the one that came second won or lied: a change
# verified against the old password overwrote the reset that had just taken
# the account back, a reset that waited for a change answered ok and left the
# change's password, and a change that waited for another reported success
# with a password it never stored. Each case runs the two on two
# connections, the second one in the first one's window.
my $database = GPForum::Test::PgDatabase->fresh;
my $ctx      = {
    database => $database,
    hasher   => GPForum::Service::Password->new,
    ids      => GPForum::Infrastructure::Id->new,
    rival    => _connect($database),
    schema   => $database->schema,
};
$ctx->{secret} = $ctx->{hasher}->hash_password($OLD_PASSWORD);

_change_verified_before_a_reset($ctx);
_reset_waiting_for_a_change($ctx);
_change_waiting_for_a_change($ctx);
_email_request_verified_before_a_reset($ctx);
_reset_after_email_replaced($ctx);
_reset_after_email_roundtrip($ctx);
_email_request_waiting_for_a_reset($ctx);
_email_confirmation_waiting_for_a_reset($ctx);
_reset_waiting_for_email_confirmation($ctx);
_reset_request_waiting_for_email_confirmation($ctx);

$ctx->{rival}->storage->disconnect;

done_testing();

# A change of recovery address requires the password that is still current
# when its token is issued, just as an authenticated password change does.
sub _email_request_verified_before_a_reset {
    my ($context) = @_;

    my $user = _member( $context, 'staleemail' );
    my $raw  = _reset_token( $context, 'staleemail' );
    my $reset;
    my $verifier = GPForum::Test::InterposingPassword->new(
        interpose => sub {
            $reset =
              _identity( $context, $context->{rival} )
              ->reset_password(
                { password => $MEMBER_PASSWORD, token => $raw } );
        }
    );
    my $request =
      _identity( $context, $context->{schema}, password => $verifier )
      ->request_email_change(
        {
            current_password => $OLD_PASSWORD,
            email            => 'outsider@example.test',
            user_id          => $user,
        }
      );

    ok( $reset->{ok},
        'reset commits after email request verifies the password' );
    is( $request->{error}, 'invalid_current_password',
        'email request verified against the replaced password is refused' );
    is(
        scalar $context->{schema}->storage->dbh->selectrow_array(
q{SELECT count(*) FROM identity_tokens WHERE user_id = ? AND token_type = 'email_change'},
            undef,
            $user
        ),
        0,
        'stale email request issues no confirmation token'
    );

    return;
}

# A reset belongs to the recovery address it was sent to, while remaining
# usable after an authenticated password change at that same address.
sub _reset_after_email_replaced {
    my ($context) = @_;

    my $user = _member( $context, 'oldmailbox' );
    my $raw  = _reset_token( $context, 'oldmailbox' );
    my $change =
      _identity( $context, $context->{schema} )->request_email_change(
        {
            current_password => $OLD_PASSWORD,
            email            => 'replacement@example.test',
            user_id          => $user,
        }
      );
    ok(
        _identity( $context, $context->{schema} )
          ->confirm_email_change( { token => $change->{token}{raw_token} } )
          ->{ok},
        'the member confirms a replacement recovery address'
    );
    is(
        _identity( $context, $context->{schema} )
          ->reset_password( { password => $OTHER_PASSWORD, token => $raw } )
          ->{error},
        'invalid_token',
        'the reset sent to the replaced address is refused'
    );
    ok(
        _signs_in( $context, 'oldmailbox', $OLD_PASSWORD ),
        'the stale reset leaves the password unchanged'
    );

    my $fresh = _reset_token( $context, 'replacement@example.test' );
    ok(
        _identity( $context, $context->{schema} )->reset_password(
            { password => $MEMBER_PASSWORD, token => "  $fresh\n" }
        )->{ok},
'a reset sent to the current address still accepts surrounding whitespace'
    );

    return;
}

# Returning to a previously used address starts a new recovery lifecycle;
# it must not revive a reset link issued before the address was replaced.
sub _reset_after_email_roundtrip {
    my ($context) = @_;

    my $user = _member( $context, 'roundtrip' );
    my $raw  = _reset_token( $context, 'roundtrip' );
    for my $email ( 'away@example.test', 'roundtrip@example.test' ) {
        my $confirmation = _email_token( $context, $user, $email );
        ok(
            _identity( $context, $context->{schema} )
              ->confirm_email_change( { token => $confirmation } )->{ok},
            "member confirms recovery address $email"
        );
    }
    is(
        _identity( $context, $context->{schema} )
          ->reset_password( { password => $OTHER_PASSWORD, token => $raw } )
          ->{error},
        'invalid_token',
        'returning to the old address does not revive its reset'
    );
    ok(
        _signs_in( $context, 'roundtrip', $OLD_PASSWORD ),
'the reset from the previous address lifecycle leaves the password alone'
    );

    return;
}

# A request can verify the old credential while the reset that revokes it
# is uncommitted. It must wait, then refuse, before it issues a new token.
sub _email_request_waiting_for_a_reset {
    my ($context) = @_;

    my $user     = _member( $context, 'waitingemail' );
    my $raw      = _reset_token( $context, 'waitingemail' );
    my $child    = {};
    my $sessions = _holding_session_store(
        $context,
        sub {
            $child->{pid} = _in_child(
                $context->{database},
                sub ($identity) {
                    my $result = $identity->request_email_change(
                        {
                            current_password => $OLD_PASSWORD,
                            email            => 'late-outsider@example.test',
                            user_id          => $user,
                        }
                    );
                    return { ok => ( $result->{error} // q{} ) eq
                          'invalid_current_password' };
                }
            );
            _await_lock_wait( $context, $child );
        }
    );
    my $reset =
      _identity( $context, $context->{schema}, session_store => $sessions )
      ->reset_password( { password => $MEMBER_PASSWORD, token => $raw } );
    _reap($child);

    ok( $reset->{ok},     'reset commits while an email request waits' );
    ok( $child->{waited}, 'email request waits for the credential lock' );
    is( $child->{status}, 0, 'the request then refuses the replaced password' );

    return;
}

# Reset holds the credential and account before it withdraws an email
# token. Confirmation must wait on that credential before taking the token,
# or each operation can wait on a lock the other holds.
sub _email_confirmation_waiting_for_a_reset {
    my ($context) = @_;

    my $user     = _member( $context, 'waitingconfirm' );
    my $email    = _email_token( $context, $user, 'unconfirmed@example.test' );
    my $raw      = _reset_token( $context, 'waitingconfirm' );
    my $child    = {};
    my $sessions = _holding_session_store(
        $context,
        sub {
            $child->{pid} = _in_child(
                $context->{database},
                sub ($identity) {
                    my $result =
                      $identity->confirm_email_change( { token => $email } );
                    return {
                        ok => ( $result->{error} // q{} ) eq 'invalid_token' };
                }
            );
            _await_lock_wait( $context, $child );
        }
    );
    my $reset =
      _identity( $context, $context->{schema}, session_store => $sessions )
      ->reset_password( { password => $MEMBER_PASSWORD, token => $raw } );
    _reap($child);

    ok( $reset->{ok},
        'reset withdraws the pending email change without deadlock' );
    ok( $child->{waited}, 'confirmation waits for the reset credential lock' );
    is( $child->{status}, 0, 'confirmation then rejects the withdrawn token' );

    return;
}

# Confirmation holds the credential and token just before its account
# update. A reset sent to the address it replaces waits, then sees the new
# address and is refused, without replacing the password.
sub _reset_waiting_for_email_confirmation {
    my ($context) = @_;

    my $user  = _member( $context, 'waitingreset' );
    my $email = _email_token( $context, $user, 'confirmed-first@example.test' );
    my $raw   = _reset_token( $context, 'waitingreset' );
    my $child = {};
    my $storage = $context->{schema}->storage;
    my $pending = 1;
    $storage->debugcb(
        sub {
            my ( undef, $statement ) = @_;
            if (   $pending
                && $statement =~ /api[.]identity_update_user_v[[:digit:]]+/msx )
            {
                $pending = 0;
                $child->{pid} = _in_child(
                    $context->{database},
                    sub ($identity) {
                        my $result = $identity->reset_password(
                            { password => $OTHER_PASSWORD, token => $raw } );
                        return { ok => ( $result->{error} // q{} ) eq
                              'invalid_token' };
                    }
                );
                _await_lock_wait( $context, $child );
            }
            return;
        }
    );
    $storage->debug(1);
    my $confirmed = _identity( $context, $context->{schema} )
      ->confirm_email_change( { token => $email } );
    $storage->debug(0);
    $storage->debugcb(undef);
    _reap($child);

    ok( !$pending, 'reset starts before the confirmation updates the account' );
    ok( $confirmed->{ok}, 'confirmation commits without deadlock' );
    ok( $child->{waited}, 'reset waits for the confirmation credential lock' );
    is( $child->{status}, 0,
        'reset then rejects the replaced recovery address' );
    ok(
        _signs_in( $context, 'waitingreset', $OLD_PASSWORD ),
        'the refused concurrent reset leaves the password unchanged'
    );

    return;
}

# A reset request may have found the old address before confirmation holds
# the credential. It must wait and reload the address before minting a link,
# so the withdrawal cannot be followed by a fresh link to the old mailbox.
sub _reset_request_waiting_for_email_confirmation {
    my ($context) = @_;

    my $user  = _member( $context, 'waitingissue' );
    my $email = _email_token( $context, $user, 'issued-current@example.test' );
    my $child = {};
    my $storage = $context->{schema}->storage;
    my $pending = 1;
    $storage->debugcb(
        sub {
            my ( undef, $statement ) = @_;
            if (   $pending
                && $statement =~ /api[.]identity_update_user_v[[:digit:]]+/msx )
            {
                $pending = 0;
                $child->{pid} = _in_child(
                    $context->{database},
                    sub ($identity) {
                        my $result = $identity->request_password_reset(
                            { identifier => 'waitingissue' } );
                        return { ok => $result->{ok}
                              && ( $result->{email_normalized} // q{} ) eq
                              'issued-current@example.test' };
                    }
                );
                _await_lock_wait( $context, $child );
            }
            return;
        }
    );
    $storage->debug(1);
    my $confirmed = _identity( $context, $context->{schema} )
      ->confirm_email_change( { token => $email } );
    $storage->debug(0);
    $storage->debugcb(undef);
    _reap($child);

    ok( !$pending, 'reset issuance starts before the account address changes' );
    ok( $confirmed->{ok}, 'confirmation commits before reset issuance' );
    ok( $child->{waited}, 'reset issuance waits for the credential lock' );
    is( $child->{status}, 0,
        'reset issuance uses the newly confirmed address' );
    is(
        scalar $context->{schema}->storage->dbh->selectrow_array(
q{SELECT email_normalized FROM identity_tokens WHERE user_id = ? AND token_type = 'password_reset' AND used_at IS NULL},
            undef,
            $user
        ),
        'issued-current@example.test',
        'only the current mailbox gets a fresh reset'
    );

    return;
}

sub _email_token {
    my ( $context, $user, $email ) = @_;

    my $request =
      _identity( $context, $context->{schema} )->request_email_change(
        {
            current_password => $OLD_PASSWORD,
            email            => $email,
            user_id          => $user,
        }
      );

    return $request->{token}{raw_token};
}

# Whoever knew the old password -- the reason for the reset -- asks for a
# change; the member's reset commits after the change verified the old
# password and before its transaction.
sub _change_verified_before_a_reset {
    my ($context) = @_;

    my $user = _member( $context, 'retaken' );
    my $kept = _session( $context, $user );
    my $raw  = _reset_token( $context, 'retaken' );
    my $reset;
    my $verifier = GPForum::Test::InterposingPassword->new(
        interpose => sub {
            $reset =
              _identity( $context, $context->{rival} )
              ->reset_password(
                { password => $MEMBER_PASSWORD, token => $raw } );
        }
    );
    my $change =
      _identity( $context, $context->{schema}, password => $verifier )
      ->change_password(
        {
            current_password => $OLD_PASSWORD,
            keep_session_id  => $kept,
            new_password     => $OTHER_PASSWORD,
            user_id          => $user,
        }
      );

    ok( $reset->{ok}, 'the reset commits in the gap' );
    is( $change->{error}, 'invalid_current_password',
        'the change verified against the replaced password is refused' );
    ok( _signs_in( $context, 'retaken', $MEMBER_PASSWORD ),
        'the password the reset set signs in' );
    ok(
        !_signs_in( $context, 'retaken', $OTHER_PASSWORD ),
        'the one the change asked for does not'
    );

    return;
}

# The change holds the member's credential, stamped two seconds ahead, while
# the reset, in another process on its own connection, waits for it.
sub _reset_waiting_for_a_change {
    my ($context) = @_;

    my $user     = _member( $context, 'waiter' );
    my $raw      = _reset_token( $context, 'waiter' );
    my $child    = {};
    my $sessions = _holding_session_store(
        $context,
        sub {
            $child->{pid} = _in_child(
                $context->{database},
                sub ($identity) {
                    return $identity->reset_password(
                        { password => $MEMBER_PASSWORD, token => $raw } );
                }
            );
            _await_lock_wait( $context, $child );
        }
    );
    my $change = _identity(
        $context, $context->{schema},
        clock         => GPForum::Test::SkewedClock->new( seconds => $AHEAD ),
        session_store => $sessions,
    )->change_password(
        {
            current_password => $OLD_PASSWORD,
            new_password     => $OTHER_PASSWORD,
            user_id          => $user,
        }
    );
    _reap($child);

    ok( $change->{ok},    'the change that held the credential first commits' );
    ok( $child->{waited}, 'the reset waits for it' );
    is( $child->{status}, 0,
        'and then completes, on a clock behind the credential it replaces' );
    ok( _signs_in( $context, 'waiter', $MEMBER_PASSWORD ),
        'the password the reset set signs in' );
    ok(
        !_signs_in( $context, 'waiter', $OTHER_PASSWORD ),
        'the one the change set before it does not'
    );
    is( _active_credentials( $context, $user ),
        1, 'one active password credential' );

    return;
}

# Two changes verified the same current password; the second waits for the
# first's transaction.
sub _change_waiting_for_a_change {
    my ($context) = @_;

    my $user     = _member( $context, 'twice' );
    my $child    = {};
    my $sessions = _holding_session_store(
        $context,
        sub {
            $child->{pid} = _in_child(
                $context->{database},
                sub ($identity) {
                    my $refused = $identity->change_password(
                        {
                            current_password => $OLD_PASSWORD,
                            new_password     => $OTHER_PASSWORD,
                            user_id          => $user,
                        }
                    );
                    return { ok => ( $refused->{error} // q{} ) eq
                          'invalid_current_password' };
                }
            );
            _await_lock_wait( $context, $child );
        }
    );
    my $first =
      _identity( $context, $context->{schema}, session_store => $sessions )
      ->change_password(
        {
            current_password => $OLD_PASSWORD,
            new_password     => $MEMBER_PASSWORD,
            user_id          => $user,
        }
      );
    _reap($child);

    ok( $first->{ok},     'the first change commits' );
    ok( $child->{waited}, 'the second waits for it' );
    is( $child->{status}, 0,
        'and is refused: its current password is no longer current' );
    ok(
        _signs_in( $context, 'twice', $MEMBER_PASSWORD ),
        'the first change\'s password signs in'
    );
    ok(
        $context->{hasher}->verify_password(
            $MEMBER_PASSWORD,
            scalar $context->{schema}
              ->storage->dbh->selectrow_array( $USER_HASH_SQL, undef, $user )
        ),
        'and is the one the account row holds'
    );

    return;
}

# A session store that runs the code once, before it revokes: the rotation
# that precedes the revocation in the same transaction holds the credential
# then.
sub _holding_session_store {
    my ( $context, $code ) = @_;

    return GPForum::Test::HoldingSessionStore->new(
        before_revoke => $code,
        id_service    => $context->{ids},
        schema        => $context->{schema},
    );
}

# The work in a process of its own, on a connection of its own; the child
# exits 0 when the work answers ok.
sub _in_child {
    my ( $database_arg, $work ) = @_;

    my $pid = fork;
    if ( !defined $pid ) {
        BAIL_OUT("fork: $OS_ERROR");
    }
    if ($pid) {
        return $pid;
    }

    my $code = $CHILD_FAILURE;
    try {
        my $schema = _connect($database_arg);
        my $result =
          $work->(
            GPForum::Service::Identity::Store->new( schema => $schema ) );
        $code = $result->{ok} ? 0 : 1;
        $schema->storage->disconnect;
    }
    catch ($error) {
        print {*STDERR} "child: $error\n"
          or $code = $CHILD_FAILURE;
    };
    return _exit($code);
}

# Notes in %{$child} whether some backend came to wait on a lock before the
# child finished, and the child's exit status when it finished first.
sub _await_lock_wait {
    my ( $context, $child ) = @_;

    my $dbh      = $context->{rival}->storage->dbh;
    my $deadline = time + $WAIT_SECONDS;
    $child->{waited} = 0;
    while ( time < $deadline ) {
        my ($waiting) = $dbh->selectrow_array($LOCK_WAITERS_SQL);
        if ($waiting) {
            $child->{waited} = 1;
            return;
        }
        if ( waitpid( $child->{pid}, WNOHANG ) == $child->{pid} ) {
            $child->{status} = WEXITSTATUS($CHILD_ERROR);
            return;
        }
        sleep $POLL_SECONDS;
    }

    return;
}

sub _reap {
    my ($child) = @_;

    if ( !exists $child->{status} ) {
        waitpid $child->{pid}, 0;
        $child->{status} = WEXITSTATUS($CHILD_ERROR);
    }

    return;
}

sub _signs_in {
    my ( $context, $name, $password ) = @_;

    return _identity( $context, $context->{schema} )
      ->authenticate_login( { identifier => $name, password => $password } )
      ->{ok};
}

sub _active_credentials {
    my ( $context, $user ) = @_;

    return
      scalar $context->{schema}
      ->storage->dbh->selectrow_array( $ACTIVE_SQL, undef, $user );
}

sub _identity {
    my ( $context, $schema, %options ) = @_;

    return GPForum::Service::Identity::Store->new(
        id_service => $context->{ids},
        schema     => $schema,
        %options,
    );
}

sub _reset_token {
    my ( $context, $name ) = @_;

    my $request = _identity( $context, $context->{rival} )
      ->request_password_reset( { identifier => $name } );

    return $request->{token}{raw_token};
}

sub _member {
    my ( $context, $name ) = @_;

    my $id  = $context->{ids}->uuid;
    my $dbh = $context->{schema}->storage->dbh;
    $dbh->do( $USER_SQL, undef, $id, $name, ucfirst $name,
        "$name\@example.test", $context->{secret} );
    $dbh->do(
        $CREDENTIAL_SQL, undef, $context->{ids}->uuid,
        $id,             $context->{secret}
    );

    return $id;
}

sub _session {
    my ( $context, $user ) = @_;

    my $id = $context->{ids}->uuid;
    $context->{schema}
      ->storage->dbh->do( $SESSION_SQL, undef, $id, $user, "hash-$id" );

    return $id;
}

sub _connect {
    my ($database_arg) = @_;

    local $ENV{GPFORUM_DATABASE_DSN} = $database_arg->dsn;

    return GPForum::Schema->connect_from_config(
        GPForum::Config->from_environment );
}

1;
