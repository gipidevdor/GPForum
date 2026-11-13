# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Infrastructure::EventRecorder;
use GPForum::Test::Id;
use GPForum::Test::RecorderFunctions;
use GPForum::Test::Schema;

our $VERSION = '0.001';

const my $EARLIER => '2026-05-23T11:00:00Z';

# ADR 0116. event_log, audit_log and notifications are partitioned by
# created_at, and keyed on the id and that time: an id already stored at
# another time is no conflict. api.ops_record_event locks a caller's event
# id and looks it up in every partition; api.ops_record_audit locks a
# caller's audit id, looks it up, and writes a new id for one taken. Those
# are the database's, in t/integration/postgres-partition-conflicts.t (an
# event raced at another time, an audit id taken at another time) and
# t/integration/postgres-audit-chain.t (a second writer of one audit id
# waits); a notification stored at another time is api.notification_deliver's
# (ADR 0177), in t/integration/postgres-notifications.t. These pin what the
# recorder sends for it, and that an id it mints itself costs nothing more.
_caller_event_id_is_locked();
_minted_event_id_is_not_locked();
_caller_audit_id_is_looked_up();
_minted_audit_id_is_not_looked_up();

done_testing();

sub _caller_event_id_is_locked {
    my $log = GPForum::Test::RecorderFunctions->new;
    _recorder($log)->record_event( _event( event_id => 'event-1' ) );
    my $sent = $log->sent('ops_record_event');

    is( scalar @{$sent}, 1, q{a caller's event is recorded in one call} );
    ok( $sent->[0]{explicit}, 'which is asked to lock and look up its id' );
    is( $sent->[0]{event}{event_id}, 'event-1', 'under that id' );

    return;
}

sub _minted_event_id_is_not_locked {
    my $log = GPForum::Test::RecorderFunctions->new;
    _recorder($log)->record_event( _event() );

    ok( !$log->sent('ops_record_event')->[0]{explicit},
        'an event id the recorder mints is neither locked nor looked up' );
    is( scalar @{ $log->events }, 1, 'and the event is written' );

    return;
}

sub _caller_audit_id_is_looked_up {
    my $log = GPForum::Test::RecorderFunctions->new;
    _recorder($log)->record_audit( _audit( audit_id => 'audit-1' ) );
    my $sent = $log->sent('ops_record_audit');

    ok( $sent->[0]{explicit},
        q{a caller's audit id is sent to be locked and looked up} );
    is( $sent->[0]{audit}{audit_id}, 'audit-1', 'as it was given' );

    return;
}

sub _minted_audit_id_is_not_looked_up {
    my $log      = GPForum::Test::RecorderFunctions->new;
    my $recorder = _recorder($log);
    my $audit    = $recorder->record_audit( _audit() );

    ok( !$log->sent('ops_record_audit')->[0]{explicit},
        'an audit id the recorder mints is neither locked nor looked up' );
    ok( $recorder->verify_audit_record($audit), 'and its record verifies' );

    return;
}

sub _recorder {
    my ($log) = @_;

    return GPForum::Infrastructure::EventRecorder->new(
        functions  => $log,
        id_service => GPForum::Test::Id->new,
        schema     => GPForum::Test::Schema->new,
    );
}

sub _event {
    my (%extra) = @_;

    return (
        actor_id          => 'user-1',
        aggregate_id      => 'thread-1',
        aggregate_type    => 'thread',
        aggregate_version => 1,
        event_type        => 'thread.created',
        idempotency_key   => 'thread.created:thread-1',
        payload           => { thread_id => 'thread-1' },
        %extra,
    );
}

sub _audit {
    my (%extra) = @_;

    return (
        action         => 'thread.created',
        actor_id       => 'user-1',
        correlation_id => 'correlation-1',
        created_at     => $EARLIER,
        target_id      => 'thread-1',
        target_type    => 'thread',
        %extra,
    );
}

1;
