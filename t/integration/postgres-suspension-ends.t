# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Infrastructure::Id;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Service::Moderation::SuspensionStore;
use GPForum::Service::Operations::ScheduledJobs;
use GPForum::Service::Outbox::Dispatcher;
use GPForum::Service::Outbox::DomainEventTransport;
use GPForum::Test::FixedClock;
use GPForum::Test::PgDatabase;
use GPForum::Worker::Handler::SuspensionEnd;

our $VERSION = '0.001';

const my $NOW       => '2026-10-01T09:00:00Z';
const my $ENDS      => '2026-10-01T10:00:00Z';
const my $DUE       => '2026-10-01T10:00:01Z';
const my $AFTER     => '2026-10-01T10:00:02Z';
const my $RETRIED   => '2026-10-01T10:01:30Z';
const my $FAR_AHEAD => '2099-01-01T00:00:00Z';
const my $BATCH     => 100;
const my $AN_HOUR   => 3_600;
const my $ENDED     => 'user.suspension_ended';

const my $USER_SQL => join q{ },
  'INSERT INTO users (id, username, display_name, email_normalized,',
q{password_hash, status, updated_at) VALUES (?, ?, ?, ?, 'x', 'active', now())};
const my $OPEN_ENDED_SQL => join q{ },
  'INSERT INTO suspensions (suspension_id, user_id, actor_user_id, reason,',
  q{valid_from) VALUES (?, ?, ?, 'held', ?::timestamptz)};
const my $TIMER_SQL => join q{ },
  q{SELECT status, payload->>'event_type' AS event_type,},
  q{to_char(next_attempt_at AT TIME ZONE 'UTC',},
  q{'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS due FROM outbox_messages},
  q{WHERE idempotency_key = 'suspension-end:' || ?};
const my $DROP_TIMER_SQL =>
  q{DELETE FROM outbox_messages WHERE idempotency_key = 'suspension-end:' || ?};
const my $AGE_TIMER_SQL => join q{ },
  q{UPDATE outbox_messages SET created_at = now() - interval '7 days'},
  q{WHERE idempotency_key = 'suspension-end:' || ?};
const my $STATUS_SQL => 'SELECT status FROM users WHERE id = ?';
const my $ENDED_SQL => join q{ },
  'SELECT count(*) FROM audit_log WHERE action = ? AND target_id = ?',
  'AND actor_id IS NULL';
const my $ENDED_EVENTS_SQL =>
  'SELECT count(*) FROM event_log WHERE event_type = ? AND aggregate_id = ?';

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'set GPFORUM_DATABASE_DSN to run the suspension end test';
}

my $database = GPForum::Test::PgDatabase->fresh;
my $dbh      = $database->dbh;
my $schema   = $database->schema;
my $ids      = GPForum::Infrastructure::Id->new;
my $staff    = _user('staff');

# v5.0.0-2.3.2: a timed suspension ends at its valid_to. It set the member's
# status to suspended and only a revocation set it back, so a member whose
# suspension had ended still read the forum as a visitor and could not post.
_ends_on_time();
_ends_once_the_clock_agrees();
_open_ended_queues_nothing();
_revoked_ends_nothing();
_another_suspension_holds_the_member();
_sweep_queues_a_missing_end();
_search_lag_skips_an_end_not_due();

done_testing();

sub _ends_on_time {
    my $member = _user('on_time');
    my $id     = _suspend( $member, $ENDS );
    is_deeply(
        $dbh->selectrow_hashref( $TIMER_SQL, undef, $id ),
        {
            due        => $DUE,
            event_type => 'user.suspension_end_due',
            status     => 'pending'
        },
        'a timed suspension queues its end, due a second after valid_to'
    );

    _dispatch($ENDS);
    is( _status($member), 'suspended',
        'the member stays suspended until then' );

    _dispatch($AFTER);
    is( _status($member), 'active', 'and is active once the end is delivered' );
    is( _ended($member),  1,        'the end is audited once, with no actor' );
    is(
        scalar $dbh->selectrow_array( $ENDED_EVENTS_SQL, undef, $ENDED,
            $member ),
        1,
        'and recorded as an event'
    );
    is( $dbh->selectrow_hashref( $TIMER_SQL, undef, $id )->{status},
        'done', 'its message is done' );

    _dispatch($AFTER);
    is( _ended($member), 1, 'delivering again ends nothing more' );

    return;
}

# The worker's clock behind the database's: the suspension is still in force
# by it, so the end fails and the outbox delivers it again.
sub _ends_once_the_clock_agrees {
    my $member = _user('skewed');
    my $id     = _suspend( $member, $ENDS );

    my $early = _dispatch( $AFTER, $ENDS );
    is( $early->{failed}, 1,           'an end read as early fails' );
    is( _status($member), 'suspended', 'and leaves the member suspended' );

    _dispatch($RETRIED);
    is( _status($member), 'active', 'the retry ends the suspension' );
    is( _ended($member),  1,        'once' );

    return;
}

sub _open_ended_queues_nothing {
    my $member = _user('open_ended');
    my $id     = _suspend( $member, undef );
    ok(
        !$dbh->selectrow_hashref( $TIMER_SQL, undef, $id ),
        'an open-ended suspension queues no end'
    );

    return;
}

sub _revoked_ends_nothing {
    my $member = _user('revoked');
    my $id     = _suspend( $member, $ENDS );
    _store($NOW)->revoke_suspension( $id, $staff, 'appeal' );

    _dispatch($AFTER);
    is( _status($member), 'active', 'a revoked suspension leaves its member' );
    is( _ended($member),  0,        'and its end audits nothing' );

    return;
}

sub _another_suspension_holds_the_member {
    my $member = _user('held');
    my $id     = _suspend( $member, $ENDS );
    $dbh->do( $OPEN_ENDED_SQL, undef, $ids->uuid, $member, $staff, $NOW );

    _dispatch($AFTER);
    is( _status($member), 'suspended',
        'a member another suspension holds stays suspended' );
    is( _ended($member), 0, 'and nothing is audited' );

    return;
}

# A suspension stored before migration 1055 has no end queued; the hourly
# sweep queues it, and an end already past is delivered at once.
sub _sweep_queues_a_missing_end {
    my $member = _user('swept');
    my $id     = _suspend( $member, $ENDS );
    $dbh->do( $DROP_TIMER_SQL, undef, $id );

    my $jobs = GPForum::Service::Operations::ScheduledJobs->new(
        clock  => GPForum::Test::FixedClock->new( iso8601 => $AFTER ),
        schema => $schema,
    );
    is_deeply(
        $jobs->run_job( 'suspension_ends', { limit => $BATCH } ),
        { ok => 1, queued => 1 },
        'the sweep queues the end the suspension lacks'
    );
    is_deeply(
        $jobs->run_job( 'suspension_ends', { limit => $BATCH } ),
        { ok => 1, queued => 0 },
        'and only once'
    );

    _dispatch($AFTER);
    is( _status($member), 'active', 'which ends the suspension' );

    return;
}

# An end due next century, queued a week ago: counted from when it was
# queued, search read as a week behind.
sub _search_lag_skips_an_end_not_due {
    my $member = _user('far_ahead');
    my $id     = _suspend( $member, $FAR_AHEAD );
    $dbh->do( $AGE_TIMER_SQL, undef, $id );

    my $lag = GPForum::Infrastructure::SqlFunction->for_schema($schema)
      ->row( 'search_observe_lag', {} );
    cmp_ok( $lag->{lag_seconds}, q{<}, $AN_HOUR,
        'an end not yet due is no search lag' );

    return;
}

sub _suspend {
    my ( $member, $valid_to ) = @_;

    my $suspended = _store($NOW)->create_suspension(
        {
            actor_user_id => $staff,
            reason        => 'abuse',
            user_id       => $member,
            ( defined $valid_to ? ( valid_to => $valid_to ) : () ),
        }
    );

    return $suspended->{suspension}{suspension_id};
}

# The outbox as the worker runs it at $at, its handler's clock at $handler_at
# (the same unless given).
sub _dispatch {
    my ( $at, $handler_at ) = @_;

    my $handler = GPForum::Worker::Handler::SuspensionEnd->new(
        store => _store( $handler_at // $at ) );

    return GPForum::Service::Outbox::Dispatcher->new(
        clock      => GPForum::Test::FixedClock->new( iso8601 => $at ),
        id_service => $ids,
        schema     => $schema,
        transport  => GPForum::Service::Outbox::DomainEventTransport->new(
            handlers => [$handler],
        ),
    )->dispatch_pending($BATCH);
}

sub _store {
    my ($now) = @_;

    return GPForum::Service::Moderation::SuspensionStore->new(
        clock  => GPForum::Test::FixedClock->new( iso8601 => $now ),
        schema => $schema,
    );
}

sub _user {
    my ($name) = @_;

    my $id = $ids->uuid;
    $dbh->do( $USER_SQL, undef, $id, "end_$name", $name,
        "end_$name\@example.test" );

    return $id;
}

sub _status {
    my ($member) = @_;

    return scalar $dbh->selectrow_array( $STATUS_SQL, undef, $member );
}

sub _ended {
    my ($member) = @_;

    return scalar $dbh->selectrow_array( $ENDED_SQL, undef, $ENDED, $member );
}

1;
