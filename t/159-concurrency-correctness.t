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
use GPForum::Test::Id;
use GPForum::Test::RecorderFunctions;
use GPForum::Test::Schema;

our $VERSION = '0.001';

ok(
    GPForum::Infrastructure::UniqueConflict->is_conflict(
        'duplicate key value violates unique constraint "x" (23505)'),
    'PostgreSQL unique violations are recognized'
);
ok( !GPForum::Infrastructure::UniqueConflict->is_conflict('connection reset'),
    'non-unique errors are not treated as conflicts' );

_assert_audit_chain_calls();
_assert_audit_lookup_errors_propagate();

done_testing();

# Each audit append is one api.ops_record_audit call, which takes the
# chain's lock, reads its tip and writes the row in the caller's
# transaction (ADR 0156): the lock and the transaction are
# t/integration/postgres-audit-chain.t's. Here, the record each append
# answers is linked to the one before and verifies.
sub _assert_audit_chain_calls {
    my $log      = GPForum::Test::RecorderFunctions->new;
    my $recorder = _recorder($log);
    my $first    = $recorder->record_audit( _audit_input('thread.created') );
    my $replay   = $recorder->record_audit( _audit_input('thread.updated') );

    is( scalar @{ $log->sent('ops_record_audit') },
        2, 'each audit append is one call of the audit function' );
    is( $replay->{previous_hash},
        $first->{record_hash}, 'the second record links to the first' );
    ok(
        $recorder->verify_audit_record($replay),
        'and the chained record verifies'
    );

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
    my $recorder = _recorder(
        GPForum::Test::RecorderFunctions->new(
            failure => "audit lookup failed\n"
        )
    );

    throws_ok(
        sub { $recorder->record_audit( _audit_input('thread.created') ); },
        qr/audit [ ] lookup [ ] failed/msx,
        'audit lookup errors are not swallowed'
    );

    return;
}

sub _recorder {
    my ($functions) = @_;

    return GPForum::Infrastructure::EventRecorder->new(
        functions  => $functions,
        id_service => GPForum::Test::Id->new,
        schema     => GPForum::Test::Schema->new,
    );
}

1;
