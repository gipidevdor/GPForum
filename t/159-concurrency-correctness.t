# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Test::Exception;
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Infrastructure::EventRecorder;
use GPForum::Infrastructure::UniqueConflict;
use GPForum::Service::Community::BookmarkStore;
use GPForum::Service::Notification::SubscriptionStore;
use GPForum::Test::AuditChainSchema;
use GPForum::Test::BrokenAuditSchema;
use GPForum::Test::CommunityResultSet;
use GPForum::Test::CommunitySchema;
use GPForum::Test::FixedClock;
use GPForum::Test::Id;
use GPForum::Test::NotificationResultSet;
use GPForum::Test::NotificationSchema;
use GPForum::Test::PostStoreLockDbh;
use GPForum::Test::PostStoreLockStorage;
use GPForum::Test::Schema;

our $VERSION = '0.001';

ok(
    GPForum::Infrastructure::UniqueConflict->is_conflict(
        'duplicate key value violates unique constraint "x" (23505)'),
    'PostgreSQL unique violations are recognized'
);
ok( !GPForum::Infrastructure::UniqueConflict->is_conflict('connection reset'),
    'non-unique errors are not treated as conflicts' );

_assert_bookmark_unique_replay();
_assert_subscription_unique_replay();
_assert_audit_chain_lock();
_assert_audit_chain_transaction();
_assert_audit_chain_joins_open_transaction();
_assert_audit_lookup_errors_propagate();

done_testing();

sub _assert_bookmark_unique_replay {
    my $bookmarks = GPForum::Test::CommunityResultSet->new;
    my $store     = GPForum::Service::Community::BookmarkStore->new(
        clock      => GPForum::Test::FixedClock->new,
        id_service => GPForum::Test::Id->new,
        schema     => GPForum::Test::CommunitySchema->new(
            resultsets => { Bookmark => $bookmarks },
        ),
    );
    my $input = {
        note        => 'rileggi',
        target_id   => 'thread-1',
        target_type => 'thread',
        user_id     => 'user-1',
    };
    my $first = $store->save_bookmark($input);
    $bookmarks->find_misses(1);
    my $replay = $store->save_bookmark( { %{$input}, note => 'aggiornato' } );

    is(
        $first->{bookmark_id},
        $replay->{bookmark_id},
        'bookmark unique race returns the existing bookmark'
    );
    is( scalar @{ $bookmarks->created },
        1, 'bookmark unique race does not insert a second row' );
    is( $replay->{note}, 'aggiornato',
        'bookmark unique race restores the winning row' );

    return;
}

sub _assert_subscription_unique_replay {
    my $subscriptions = GPForum::Test::NotificationResultSet->new;
    my $store         = GPForum::Service::Notification::SubscriptionStore->new(
        clock      => GPForum::Test::FixedClock->new,
        id_service => GPForum::Test::Id->new,
        schema     => GPForum::Test::NotificationSchema->new(
            resultsets => { Subscription => $subscriptions },
        ),
    );
    my $input = {
        preference  => 'all',
        target_id   => 'thread-1',
        target_type => 'thread',
        user_id     => 'user-1',
    };
    my $first = $store->save_subscription($input);
    $subscriptions->find_misses(1);
    my $replay =
      $store->save_subscription( { %{$input}, preference => 'mentions' } );

    is(
        $first->{subscription_id},
        $replay->{subscription_id},
        'subscription unique race returns the existing subscription'
    );
    is( scalar @{ $subscriptions->created },
        1, 'subscription unique race does not insert a second row' );
    is( $replay->{preference}, 'mentions',
        'subscription unique race restores the winning row' );

    return;
}

sub _assert_audit_chain_lock {
    my $lock_dbh = GPForum::Test::PostStoreLockDbh->new;
    my $schema   = GPForum::Test::Schema->new(
        storage => GPForum::Test::PostStoreLockStorage->new( dbh => $lock_dbh ),
    );
    my $recorder = GPForum::Infrastructure::EventRecorder->new(
        id_service => GPForum::Test::Id->new,
        schema     => $schema,
    );
    my $first = $recorder->record_audit(
        action         => 'thread.created',
        actor_id       => 'user-1',
        correlation_id => 'correlation-1',
        target_id      => 'thread-1',
        target_type    => 'thread',
    );
    my $replay = $recorder->record_audit(
        action         => 'thread.updated',
        actor_id       => 'user-1',
        correlation_id => 'correlation-1',
        target_id      => 'thread-1',
        target_type    => 'thread',
    );

    is( scalar @{ $lock_dbh->calls },
        2, 'each audit append takes the chain lock' );
    like( $lock_dbh->calls->[0]{sql},
        qr/pg_advisory_xact_lock/msx,
        'audit chain lock uses a transaction advisory lock' );
    is( $replay->{previous_hash},
        $first->{record_hash},
        'advisory lock does not change audit record hashing' );
    ok( $recorder->verify_audit_record($replay),
        'chained audit still verifies after lock serialization' );

    return;
}

# pg_advisory_xact_lock only lives for the transaction that took it, so an
# autocommit caller used to release it at statement end and let the
# previous_hash/record_hash chain fork under concurrency.
sub _assert_audit_chain_transaction {
    my $schema   = GPForum::Test::AuditChainSchema->new;
    my $recorder = GPForum::Infrastructure::EventRecorder->new(
        id_service => GPForum::Test::Id->new,
        schema     => $schema,
    );
    $recorder->record_audit( _audit_input('thread.created') );
    my $journal = $schema->journal;

    is( $schema->transaction_count,
        1, 'an autocommit audit append opens its own transaction' );
    is_deeply( [ map { $_->{step} } @{$journal} ],
        [qw(begin lock commit)],
        'the chain lock is taken inside that transaction' );
    like( $journal->[1]{sql},
        qr/pg_advisory_xact_lock/msx,
        'the locked statement is still the transaction advisory lock' );
    is( $journal->[1]{depth}, 1, 'the lock runs at transaction depth one' );
    is( $journal->[0]{audits},
        0, 'no audit row exists when the transaction opens' );
    is( $journal->[2]{audits},
        1, 'the audit row is inserted before the transaction commits' );

    return;
}

sub _assert_audit_chain_joins_open_transaction {
    my $schema = GPForum::Test::AuditChainSchema->new;
    $schema->storage->transaction_depth(1);
    my $recorder = GPForum::Infrastructure::EventRecorder->new(
        id_service => GPForum::Test::Id->new,
        schema     => $schema,
    );
    $recorder->record_audit( _audit_input('thread.updated') );

    is( $schema->transaction_count,
        0, 'an audit append inside txn_do reuses the caller transaction' );
    is_deeply( [ map { $_->{step} } @{ $schema->journal } ],
        ['lock'], 'the chain lock still runs on the caller transaction' );
    is( scalar @{ $schema->created_for('AuditLog') },
        1, 'the audit row is still inserted' );

    return;
}

sub _audit_input {
    my ($action) = @_;

    return (
        action         => $action,
        actor_id       => 'user-1',
        correlation_id => 'correlation-1',
        target_id      => 'thread-1',
        target_type    => 'thread',
    );
}

sub _assert_audit_lookup_errors_propagate {
    my $recorder = GPForum::Infrastructure::EventRecorder->new(
        id_service => GPForum::Test::Id->new,
        schema     => GPForum::Test::BrokenAuditSchema->new,
    );

    throws_ok(
        sub {
            $recorder->record_audit(
                action         => 'thread.created',
                actor_id       => 'user-1',
                correlation_id => 'correlation-1',
                target_id      => 'thread-1',
                target_type    => 'thread',
            );
        },
        qr/audit [ ] lookup [ ] failed/msx,
        'audit lookup errors are not swallowed'
    );

    return;
}

1;
