# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Infrastructure::Id;
use GPForum::Service::Moderation::SuspensionStore;
use GPForum::Test::FixedClock;
use GPForum::Test::PgDatabase;
use GPForum::Test::PostgresHarness;

our $VERSION = '0.001';

const my $LOCK_TIMEOUT_MS => 10_000;
const my $IDLE_TIMEOUT_MS => 30_000;
const my $FIRST_AT        => '2026-10-01T09:00:00Z';
const my $SECOND_AT       => '2026-10-01T09:05:00Z';
const my $MEMBERS         => 3;
const my $SUSPENDED       => 'user.suspended';
const my $REVOKED         => 'user.suspension_revoked';
const my $SEED_USERS_SQL => join q{ },
  q{SELECT id FROM users WHERE status = 'active'},
  'ORDER BY username LIMIT ?';
const my $ACTIVE_SQL => join q{ },
  'SELECT suspension_id FROM suspensions',
  'WHERE user_id = ? AND revoked_at IS NULL';
const my $STATUS_SQL => 'SELECT status FROM users WHERE id = ?';
const my $MANAGE_PERMISSION_SQL => join q{ },
  'INSERT INTO permissions (permission_id, name, resource_type, action)',
  q{VALUES (?, 'admin_console.manage', 'admin_console', 'manage')},
  'RETURNING permission_id';
const my $GRANT_SQL => join q{ },
  'INSERT INTO role_permissions (role_id, permission_id)',
  q{SELECT role_id, ? FROM roles WHERE name = 'administrator'};
const my $GLOBAL_ADMIN_SQL => join q{ },
  'INSERT INTO role_bindings (binding_id, user_id, role_id, resource_type)',
  q{SELECT ?, ?, role_id, 'global' FROM roles WHERE name = 'administrator'};
const my $ROLE_HOLDER_SQL => join q{ },
  'SELECT b.user_id FROM role_bindings b JOIN roles r USING (role_id)',
  'WHERE r.name = ? AND b.revoked_at IS NULL ORDER BY b.user_id LIMIT 1';
const my $AUDITS_SQL =>
  'SELECT count(*) FROM audit_log WHERE action = ? AND target_id = ?';
const my $REVOCATION_AUDITS_SQL => join q{ },
  'SELECT count(*) FROM audit_log WHERE action = ?',
  q{AND metadata->>'suspension_id' = ?};
const my $REVOKED_AT_SQL => join q{ },
  'SELECT count(*) FROM suspensions',
  'WHERE suspension_id = ? AND revoked_at = ?::timestamptz';

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'set GPFORUM_DATABASE_DSN to run the suspension race test';
}

local $ENV{GPFORUM_DATABASE_LOCK_TIMEOUT_MS} = $LOCK_TIMEOUT_MS;

# The first write sits idle in its transaction while the test watches the
# second one wait; the default timeout would end it first.
local $ENV{GPFORUM_DATABASE_IDLE_IN_TRANSACTION_TIMEOUT_MS} = $IDLE_TIMEOUT_MS;
local $ENV{GPFORUM_MINION_ENABLED}                          = 0;
local $ENV{GPFORUM_REALTIME_LISTENER_ENABLED}               = 0;

my $database = GPForum::Test::PgDatabase->fresh( seed => 1 );
local $ENV{GPFORUM_DATABASE_DSN} = $database->dsn;
my $dbh = $database->dbh;

# v5.0.0-2.3.4: every write of a member's suspensions takes the member's row
# first, so two of them on one member run one after the other and the second
# sees what the first committed.
my ( $moderator, $colleague, @members ) =
  @{ $dbh->selectcol_arrayref( $SEED_USERS_SQL, undef, 2 + $MEMBERS ) };
is( scalar @members,
    $MEMBERS, 'the seed provides two moderators and three members' );

_suspensions_serialise( $members[0] );
_revocations_serialise( $members[1] );
_suspension_waits_for_a_revocation( $members[2] );
_staff_are_suspended_by_an_administrator();

done_testing();

# Two moderators suspend one member at once. Checked and inserted without a
# lock, both saw no active suspension and each inserted one: two active
# suspensions and two audit entries for one decision.
sub _suspensions_serialise {
    my ($member) = @_;

    my ( $holding, $waiting ) = _race(
        sub ($schema) {
            return _suspend( $schema, $moderator, $FIRST_AT, $member );
        },
        sub ($schema) {
            return _suspend( $schema, $colleague, $SECOND_AT, $member );
        },
    );
    my $kept = $holding->{result}{suspension}{suspension_id};
    ok( $kept, 'the first suspension is created' );
    is( $waiting->{result}{suspension}{suspension_id},
        $kept, 'the second one finds it and keeps it' );
    is_deeply( $dbh->selectcol_arrayref( $ACTIVE_SQL, undef, $member ),
        [$kept], 'the member has one active suspension' );
    is(
        scalar $dbh->selectrow_array( $AUDITS_SQL, undef, $SUSPENDED, $member ),
        1,
        'and one suspension audit entry'
    );

    return;
}

# Two moderators revoke one suspension at once. Read without a lock, the
# second saw it unrevoked, stamped its own time over the first one's and
# audited a second revocation.
sub _revocations_serialise {
    my ($member) = @_;

    my $suspension_id =
      _suspend( $database->schema, $moderator, $FIRST_AT, $member )
      ->{suspension}{suspension_id};
    my ( $holding, $waiting ) = _race(
        sub ($schema) {
            return _revoke( $schema, $moderator, $FIRST_AT, $suspension_id );
        },
        sub ($schema) {
            return _revoke( $schema, $colleague, $SECOND_AT, $suspension_id );
        },
    );
    is( $waiting->{result}{suspension_id},
        $suspension_id, 'the second revocation answers for the suspension' );
    is(
        scalar $dbh->selectrow_array(
            $REVOKED_AT_SQL, undef, $suspension_id, $FIRST_AT
        ),
        1,
        'which keeps the first revocation time'
    );
    is(
        scalar $dbh->selectrow_array(
            $REVOCATION_AUDITS_SQL, undef, $REVOKED, $suspension_id
        ),
        1,
        'one revocation audit entry is written'
    );
    is( scalar $dbh->selectrow_array( $STATUS_SQL, undef, $member ),
        'active', 'and the member is active again' );

    return;
}

# One moderator revokes a suspension while another suspends the member anew.
# Read without a lock, the suspension still looked active, so the second
# moderator was told the member was suspended, and the revocation then lifted
# it: the member went free against the later decision.
sub _suspension_waits_for_a_revocation {
    my ($member) = @_;

    my $earlier =
      _suspend( $database->schema, $moderator, $FIRST_AT, $member )
      ->{suspension}{suspension_id};
    my ( $holding, $waiting ) = _race(
        sub ($schema) {
            return _revoke( $schema, $moderator, $FIRST_AT, $earlier );
        },
        sub ($schema) {
            return _suspend( $schema, $colleague, $SECOND_AT, $member );
        },
    );
    my $later = $waiting->{result}{suspension}{suspension_id};
    isnt( $later, $earlier,
        'the suspension made during the revocation is a new one' );
    is_deeply( $dbh->selectcol_arrayref( $ACTIVE_SQL, undef, $member ),
        [$later], 'and the only active one' );
    is( scalar $dbh->selectrow_array( $STATUS_SQL, undef, $member ),
        'suspended', 'so the member stays suspended' );

    return;
}

# The holding write runs in a transaction held open; the waiting one must
# queue on a row it holds, and both finish once it commits.
sub _race {
    my ( $hold, $wait ) = @_;

    my $holding = GPForum::Test::PostgresHarness::hold(
        sub {
            my ( $ready, $await_go ) = @_;
            my $schema = GPForum::Test::PostgresHarness::connect_schema();
            my ($pid) =
              $schema->storage->dbh->selectrow_array('SELECT pg_backend_pid()');
            $schema->txn_begin;
            my $result = $hold->($schema);
            $ready->( { pid => $pid } );
            $await_go->();
            $schema->txn_commit;

            return $result;
        }
    );
    my $holder  = GPForum::Test::PostgresHarness::await_ready($holding);
    my $waiting = GPForum::Test::PostgresHarness::hold(
        sub {
            return $wait->( GPForum::Test::PostgresHarness::connect_schema() );
        }
    );
    ok(
        GPForum::Test::PostgresHarness::await_row_wait( $dbh, $holder->{pid} ),
        q{the second write waits on the first one's lock}
    );
    GPForum::Test::PostgresHarness::release($holding);

    my @outcomes = map { GPForum::Test::PostgresHarness::collect($_) } $holding,
      $waiting;
    for my $outcome (@outcomes) {
        ok( $outcome->{ok}, 'the write finishes' )
          or diag( $outcome->{error} // 'missing error' );
    }

    return @outcomes;
}

# A suspended administrator can no longer lift a suspension from the
# consoles: a moderator may not suspend one, nor anyone themselves; an
# administrator may suspend a moderator. Both paths refuse alike.
sub _staff_are_suspended_by_an_administrator {
    my ($admin) =
      $dbh->selectrow_array( $ROLE_HOLDER_SQL, undef, 'administrator' );
    my ($mod) = $dbh->selectrow_array( $ROLE_HOLDER_SQL, undef, 'moderator' );
    ok( $admin && $mod, 'the seed has an administrator and a moderator' );
    my $schema = GPForum::Test::PostgresHarness::connect_schema();

    is_deeply(
        _suspend( $schema, $mod, $FIRST_AT, $admin ),
        { ok => 0, refused => 'staff' },
        'a moderator may not suspend an administrator'
    );
    my $async;
    _store( $schema, $FIRST_AT )
      ->create_suspension_p(
        { actor_user_id => $mod, reason => 'abuse', user_id => $admin } )
      ->then( sub ($answer) { $async = $answer } )
      ->wait;
    is_deeply(
        $async,
        { ok => 0, refused => 'staff' },
        'nor on the pooled connections'
    );
    is_deeply(
        _suspend( $schema, $mod, $FIRST_AT, $mod ),
        { ok => 0, refused => 'self' },
        'nobody suspends themselves'
    );
    is_deeply( $dbh->selectcol_arrayref( $ACTIVE_SQL, undef, $admin ),
        [], 'the administrator stays unsuspended' );

    # The seed's administrator role is bound to one space and has no console
    # management: an administrator of the whole forum has both.
    my ($manage) = $dbh->selectrow_array( $MANAGE_PERMISSION_SQL, undef,
        GPForum::Infrastructure::Id->uuid );
    $dbh->do( $GRANT_SQL, undef, $manage );
    $dbh->do( $GLOBAL_ADMIN_SQL, undef, GPForum::Infrastructure::Id->uuid,
        $admin );
    $dbh->do('UPDATE second_factor_policy SET staff_required = false');
    ok(
        _suspend( $schema, $admin, $FIRST_AT, $mod )
          ->{suspension}{suspension_id},
        'an administrator may suspend a moderator'
    );

    return;
}

sub _suspend {
    my ( $schema, $actor, $now, $member ) = @_;

    return _store( $schema, $now )->create_suspension(
        {
            actor_user_id => $actor,
            reason        => 'abuse',
            user_id       => $member,
        }
    );
}

sub _revoke {
    my ( $schema, $actor, $now, $suspension_id ) = @_;

    return _store( $schema, $now )
      ->revoke_suspension( $suspension_id, $actor, 'appeal' );
}

sub _store {
    my ( $schema, $now ) = @_;

    return GPForum::Service::Moderation::SuspensionStore->new(
        clock  => GPForum::Test::FixedClock->new( iso8601 => $now ),
        schema => $schema,
    );
}

1;
