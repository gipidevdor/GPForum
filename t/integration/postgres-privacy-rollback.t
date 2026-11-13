# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Infrastructure::Id;
use GPForum::Service::Privacy::DeletionWorkflow;
use GPForum::Test::AuditCallFailure;
use GPForum::Test::FixedClock;
use GPForum::Test::PgDatabase;

our $VERSION = '0.001';

const my $NOW       => '2026-05-23T12:00:00Z';
const my $SIGNED_IN => '2026-05-23T08:00:00Z';

const my $USER_SQL => join q{ },
  'INSERT INTO users (id, username, display_name, email_normalized,',
  'password_hash, status, trust_level, email_verified_at)',
  q{VALUES (?, ?, 'Forum member', ?, 'hashed', 'active', 1, ?)};
const my $CREDENTIAL_SQL => join q{ },
  'INSERT INTO credentials (id, user_id, type, secret_hash, created_at)',
  q{VALUES (?, ?, 'password', 'hashed', ?)};
const my $SESSION_SQL => join q{ },
  'INSERT INTO sessions (session_id, user_id, session_hash, created_at,',
  q{last_seen_at, expires_at)},
  q{VALUES (?, ?, ?, ?, ?, now() + interval '1 day')};
const my $MEMBER_SQL => join q{ },
  q{SELECT deleted_at IS NOT NULL AS erased, email_normalized},
  'FROM users WHERE id = ?';
const my $CREDENTIAL_REVOKED_SQL =>
  'SELECT revoked_at IS NOT NULL FROM credentials WHERE id = ?';
const my $SESSION_REVOKED_SQL =>
  'SELECT revoked_at IS NOT NULL FROM sessions WHERE session_id = ?';
const my $REQUEST_STATUS_SQL =>
  'SELECT status FROM deletion_requests WHERE deletion_request_id = ?';
const my $JOB_STATUS_SQL =>
  'SELECT status FROM erasure_jobs WHERE erasure_job_id = ?';
const my $JOBS_SQL =>
  'SELECT count(*) FROM erasure_jobs WHERE deletion_request_id = ?';
const my @TOTAL_SQLS => map { "SELECT count(*) FROM $_" }
  qw(deletion_actions erasure_jobs event_log outbox_messages audit_log);

# A sessions table the erasure cannot revoke: every update of it fails, as
# a relation the role may not write, or one that is gone, would.
const my $REFUSING_FUNCTION_SQL => <<'SQL';
CREATE FUNCTION pg_temp.refuse_session_update() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'relation "sessions" cannot be revoked';
END
$$
SQL
const my $REFUSING_TRIGGER_SQL => <<'SQL';
CREATE TRIGGER refuse_session_update BEFORE UPDATE ON sessions
FOR EACH STATEMENT EXECUTE FUNCTION pg_temp.refuse_session_update()
SQL
const my $DROP_TRIGGER_SQL => 'DROP TRIGGER refuse_session_update ON sessions';

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'set GPFORUM_TEST_DSN to run against PostgreSQL';
}

# A deletion step writes its rows, its event and its audit entry in one
# transaction: a step that fails part way leaves nothing, and runs again.
# These held on a fake ORM in t/86 and t/339 until the privacy stores wrote
# each step once, on the function layer (ADR 0177).
my $database = GPForum::Test::PgDatabase->fresh;
my $ctx      = {
    clock  => GPForum::Test::FixedClock->new,
    dbh    => $database->dbh,
    ids    => GPForum::Infrastructure::Id->new,
    schema => $database->schema,
};
$ctx->{staff} = _member( $ctx, 'staff' );

_approval_rolls_back($ctx);
_erasure_rolls_back_on_audit($ctx);
_erasure_rolls_back_on_sessions($ctx);

$ctx->{schema}->storage->disconnect;

done_testing();

# An approval whose audit entry fails leaves the request pending, with no
# job, action, event, outbox message or audit entry.
sub _approval_rolls_back ($ctx) {
    my $member  = _member( $ctx, 'approved' );
    my $request = _deletion($ctx)->request_deletion( _erase($member) );
    my $id      = $request->{deletion_request_id};
    my $before  = _totals($ctx);

    my $error = _error_of(
        sub {
            _deletion( $ctx, failing => 1 )
              ->approve_request( $id, $ctx->{staff}, 'verified' );
        }
    );
    like(
        $error,
        qr/audit [ ] write [ ] failed/msx,
        'an approval whose audit fails fails'
    );
    is( _value( $ctx, $REQUEST_STATUS_SQL, $id ),
        'pending', 'and leaves the request pending' );
    is( _value( $ctx, $JOBS_SQL, $id ), 0, 'with no erasure job' );
    is_deeply( _totals($ctx), $before,
        'nor an action, an event, an outbox message or an audit entry' );

    my $approved =
      _deletion($ctx)->approve_request( $id, $ctx->{staff}, 'verified' );
    ok( $approved->{ok}, 'the approval runs again' );
    is( _value( $ctx, $JOBS_SQL, $id ), 1, 'and schedules one job' );

    return;
}

# An erasure whose audit entry fails, after it revoked the credentials and
# sessions and anonymized the account, leaves all of them as they were.
sub _erasure_rolls_back_on_audit ($ctx) {
    my $erasure = _approved_erasure( $ctx, 'audited' );
    my $before  = _totals($ctx);

    my $error = _error_of(
        sub {
            _deletion( $ctx, failing => 1 )
              ->complete_job( $erasure->{job}, $ctx->{staff} );
        }
    );
    like(
        $error,
        qr/audit [ ] write [ ] failed/msx,
        'an erasure whose audit fails fails'
    );
    _assert_intact( $ctx, $erasure, 'after a failed audit' );
    is_deeply( _totals($ctx), $before,
        'and records no action, event, outbox message or audit entry' );

    _assert_erased_on_retry( $ctx, $erasure );

    return;
}

# An erasure that cannot revoke the member's sessions fails, and rolls back:
# the account is not anonymized behind sessions still signed in, and the job
# runs again. The workflow skipped such a source once, and completed the
# erasure without revoking its rows.
sub _erasure_rolls_back_on_sessions ($ctx) {
    my $erasure = _approved_erasure( $ctx, 'signedin' );

    $ctx->{dbh}->do($REFUSING_FUNCTION_SQL);
    $ctx->{dbh}->do($REFUSING_TRIGGER_SQL);
    my $error = _error_of(
        sub {
            _deletion($ctx)->complete_job( $erasure->{job}, $ctx->{staff} );
        }
    );
    $ctx->{dbh}->do($DROP_TRIGGER_SQL);

    like(
        $error,
        qr/"sessions" [ ] cannot [ ] be [ ] revoked/msx,
        'an erasure that cannot revoke the sessions fails'
    );
    _assert_intact( $ctx, $erasure, 'when the sessions cannot be revoked' );

    _assert_erased_on_retry( $ctx, $erasure );

    return;
}

sub _assert_intact ( $ctx, $erasure, $when ) {
    is_deeply(
        _row( $ctx, $MEMBER_SQL, $erasure->{member} ),
        { erased => 0, email_normalized => "$erasure->{name}\@example.test" },
        "the account is not anonymized $when"
    );
    ok( !_value( $ctx, $CREDENTIAL_REVOKED_SQL, $erasure->{credential} ),
        'its credential is not revoked' );
    ok( !_value( $ctx, $SESSION_REVOKED_SQL, $erasure->{session} ),
        'its session is still signed in' );
    is( _value( $ctx, $JOB_STATUS_SQL, $erasure->{job} ),
        'pending', 'the job is left to run again' );
    is( _value( $ctx, $REQUEST_STATUS_SQL, $erasure->{request} ),
        'approved', 'and the request stays approved' );

    return;
}

sub _assert_erased_on_retry ( $ctx, $erasure ) {
    my $retried =
      _deletion($ctx)->complete_job( $erasure->{job}, $ctx->{staff} );
    ok( $retried && $retried->{ok}, 'the job completes when it runs again' );
    ok( _row( $ctx, $MEMBER_SQL, $erasure->{member} )->{erased},
        'anonymizing the account' );
    ok( _value( $ctx, $CREDENTIAL_REVOKED_SQL, $erasure->{credential} ),
        'revoking the credential' );
    ok( _value( $ctx, $SESSION_REVOKED_SQL, $erasure->{session} ),
        'and the session' );
    is( _value( $ctx, $JOB_STATUS_SQL, $erasure->{job} ),
        'done', 'the job is done' );

    return;
}

# A member with a credential and a session, whose erasure is approved.
sub _approved_erasure ( $ctx, $name ) {
    my $member     = _member( $ctx, $name );
    my $credential = $ctx->{ids}->uuid;
    $ctx->{dbh}->do( $CREDENTIAL_SQL, undef, $credential, $member, $SIGNED_IN );
    my $session = $ctx->{ids}->uuid;
    $ctx->{dbh}->do( $SESSION_SQL, undef, $session, $member, $session,
        $SIGNED_IN, $SIGNED_IN );

    my $deletion = _deletion($ctx);
    my $request  = $deletion->request_deletion( _erase($member) );
    my $approved = $deletion->approve_request( $request->{deletion_request_id},
        $ctx->{staff}, 'verified' );

    return {
        credential => $credential,
        job        => $approved->{job}{erasure_job_id},
        member     => $member,
        name       => $name,
        request    => $request->{deletion_request_id},
        session    => $session,
    };
}

sub _deletion ( $ctx, %options ) {
    my %recorder =
      $options{failing}
      ? (
        recorder => GPForum::Test::AuditCallFailure->new(
            id_service => $ctx->{ids},
            schema     => $ctx->{schema},
        )
      )
      : ();

    return GPForum::Service::Privacy::DeletionWorkflow->new(
        clock      => $ctx->{clock},
        id_service => $ctx->{ids},
        schema     => $ctx->{schema},
        %recorder,
    );
}

sub _erase ($member) {
    return {
        reason            => 'leaving the forum',
        request_type      => 'anonymize',
        requester_user_id => $member,
        resource_id       => $member,
        resource_type     => 'user',
    };
}

sub _member ( $ctx, $name ) {
    my $id = $ctx->{ids}->uuid;
    $ctx->{dbh}
      ->do( $USER_SQL, undef, $id, $name, "$name\@example.test", $NOW );

    return $id;
}

sub _error_of ($code) {
    my $error;
    try { $code->(); }
    catch ($caught) { $error = $caught; };

    return $error // q{};
}

sub _totals ($ctx) {
    return [ map { _value( $ctx, $_ ) } @TOTAL_SQLS ];
}

sub _row ( $ctx, $sql, @bind ) {
    return $ctx->{dbh}->selectrow_hashref( $sql, undef, @bind ) // {};
}

sub _value ( $ctx, $sql, @bind ) {
    return scalar $ctx->{dbh}->selectrow_array( $sql, undef, @bind );
}

1;
