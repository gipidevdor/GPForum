# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use JSON::MaybeXS qw(encode_json);
use Test::More;
use Time::HiRes qw(time);

use lib 'lib';
use lib 't/lib';

use GPForum::Infrastructure::AuditRecord;
use GPForum::Infrastructure::EventRecorder;
use GPForum::Infrastructure::Id;
use GPForum::Test::PgDatabase;
use GPForum::Test::PostgresHarness;

our $VERSION = '0.001';

const my $LOCK_NOT_AVAILABLE => '55P03';
const my $THREE              => 3;
const my $FOUR               => 4;
const my $LOCK_KEY_BITS      => 32;
const my $QUICK_SECONDS      => 1;
const my $CHAIN_CLASS        => 2_026_102_401;
const my $OLD_CHAIN_KEY      => 2_026_060_210;
const my $RECORD_SQL => 'SELECT (api.ops_record_audit_v2(?::jsonb, ?))::text';
const my $ROWS_SQL =>
  'SELECT * FROM audit_log WHERE chain_key = ? ORDER BY chain_position';

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'set GPFORUM_TEST_DSN to prove the audit chain';
}

# ADR 0156: the audit chain is one chain per aggregate, linked at commit
# under a lock on that aggregate alone, in insertion order, and a row as the
# table holds it verifies.
my $database = GPForum::Test::PgDatabase->fresh;
my $schema   = $database->schema;
my $dbh      = $database->dbh;
my $ids      = GPForum::Infrastructure::Id->new;
my $records  = GPForum::Infrastructure::AuditRecord->new;
my $recorder = GPForum::Infrastructure::EventRecorder->new(
    id_service => $ids,
    schema     => $schema
);
my $thread = $ids->uuid;
my $post   = $ids->uuid;
my $actor  = $ids->uuid;

# Order is insertion order, not the caller's time: a row stamped earlier
# than the one before it takes the next position and links to it.
my @stamps = (
    '2026-06-01T10:00:00Z', '2026-01-01T10:00:00+02:00',
    '2026-03-01T10:00:00.250Z',
);
my @written;
for my $stamp (@stamps) {
    push @written, $schema->txn_do(
        sub {
            return $recorder->record_audit(
                action         => 'thread.audited',
                actor_id       => $actor,
                correlation_id => $ids->uuid,
                created_at     => $stamp,
                metadata       => { stamp => $stamp },
                target_id      => $thread,
                target_type    => 'thread',
            );
        }
    );
}
is_deeply(
    [ map { $_->{chain_position} } @written ],
    [ 1, 2, $THREE ],
    'three audits of one thread take positions 1, 2, 3 in insertion order'
);
is( $written[0]{previous_hash}, undef, 'the first links to nothing' );
is(
    $written[1]{previous_hash},
    $written[0]{record_hash},
    'the second links to the first'
);
is(
    $written[2]{previous_hash},
    $written[1]{record_hash},
    'the third to the second, whatever its time'
);
is( $written[1]{created_at},
    '2026-01-01T08:00:00.000000Z',
    'the record reports its time in UTC with microseconds' );
is( scalar( grep { $recorder->verify_audit_record($_) } @written ),
    scalar(@written), 'every record verifies as returned' );

my $rows = $dbh->selectall_arrayref(
    $ROWS_SQL,
    { Slice => {} },
    $records->chain_key( 'thread', $thread )
);
is( scalar @{$rows}, $THREE, 'the three rows are in the thread\'s chain' );
is(
    scalar( grep { $records->verify($_) } @{$rows} ),
    scalar( @{$rows} ),
    'and every row verifies as the table holds it'
);
is_deeply( $recorder->verify_audit_chain( 'thread', $thread ),
    [], 'the chain has no flaw' );

# Another aggregate's chain is its own, from position 1, and a row with no
# target is in the chain of those.
my $on_post = $schema->txn_do(
    sub {
        return $recorder->record_audit(
            action         => 'post.audited',
            actor_id       => $actor,
            correlation_id => $ids->uuid,
            created_at     => '2026-02-01T10:00:00Z',
            metadata       => {},
            target_id      => $post,
            target_type    => 'post',
        );
    }
);
is( $on_post->{chain_position}, 1, 'a post\'s first audit is position 1' );
is( $on_post->{chain_key},      "post:$post", 'in the post\'s own chain' );
my $untargeted = $schema->txn_do(
    sub {
        return $recorder->record_audit(
            action         => 'system.audited',
            actor_id       => undef,
            correlation_id => $ids->uuid,
            created_at     => '2026-02-01T10:00:00Z',
            metadata       => {},
            target_id      => undef,
            target_type    => undef,
        );
    }
);
is( $untargeted->{chain_key}, q{:}, 'a row with no target is in chain ":"' );

# Writers of different aggregates do not wait for each other; writers of
# one aggregate do, on its lock alone, and no one takes the old forum-wide
# lock.
my $holder = GPForum::Test::PostgresHarness::connect_dbi( $database->dsn );
my $other  = GPForum::Test::PostgresHarness::connect_dbi( $database->dsn );
$holder->begin_work;
$holder->do( $RECORD_SQL, undef, _document( thread => $thread ), 0 );
my ($old_lock) = $holder->selectrow_array(
    'SELECT count(*) FROM pg_locks WHERE locktype = ? AND objid = ?',
    undef, 'advisory', $OLD_CHAIN_KEY % ( 2**$LOCK_KEY_BITS ) );
my ($chain_locks) = $holder->selectrow_array(
    'SELECT count(*) FROM pg_locks WHERE locktype = ? AND classid = ?',
    undef, 'advisory', $CHAIN_CLASS );
is( $old_lock,    0, 'the forum-wide audit lock is not taken' );
is( $chain_locks, 1, 'the thread\'s chain lock is' );

$other->do(q{SET lock_timeout = '300ms'});
my $started = time;
$other->do( $RECORD_SQL, undef, _document( post => $post ), 0 );
cmp_ok( time - $started,
    q{<}, $QUICK_SECONDS,
    'an audit of another aggregate does not wait for the open one' );
my $blocked;
try {
    $other->do( $RECORD_SQL, undef, _document( thread => $thread ), 0 );
}
catch ($error) {
    $blocked = $other->state;
};
is( $blocked, $LOCK_NOT_AVAILABLE,
    'an audit of the same aggregate waits on its lock' );
$holder->commit;
$other->do( $RECORD_SQL, undef, _document( thread => $thread ), 0 );
my ($positions) = $dbh->selectrow_array(
    q{SELECT string_agg(chain_position::text, ',' ORDER BY chain_position)}
      . q{ FROM audit_log WHERE chain_key = ?},
    undef,
    $records->chain_key( 'thread', $thread )
);
is( $positions, '1,2,3,4,5', 'the two late writers took positions 4 and 5' );
is_deeply( $recorder->verify_audit_chain( 'thread', $thread ),
    [], 'and the chain is whole' );

# A caller's audit id is locked on its own: a second writer of the same id
# waits, and an id already stored is written under a new one.
my $explicit = $ids->uuid;
$holder->begin_work;
$holder->do( $RECORD_SQL, undef,
    _document( post => $post, audit_id => $explicit ), 1 );
my $id_blocked;
try {
    $other->do( $RECORD_SQL, undef,
        _document( thread => $thread, audit_id => $explicit ), 1 );
}
catch ($error) {
    $id_blocked = $other->state;
};
is( $id_blocked, $LOCK_NOT_AVAILABLE,
    'a second writer of one explicit audit id waits for the first' );
$holder->commit;
my ($again) = $other->selectrow_array( $RECORD_SQL, undef,
    _document( thread => $thread, audit_id => $explicit ), 1 );
isnt( JSON::MaybeXS->new->decode($again)->{audit_id},
    $explicit, 'an explicit id already stored is written under a new one' );
$holder->disconnect;
$other->disconnect;

# The verifier sees a changed row, a missing row and a broken link.
$dbh->do(
    q{UPDATE audit_log SET metadata = '{"changed": true}'::jsonb}
      . q{ WHERE chain_key = ? AND chain_position = 1},
    undef,
    $records->chain_key( 'thread', $thread )
);
is_deeply(
    [
        map { $_->{problem} }
          @{ $recorder->verify_audit_chain( 'thread', $thread ) }
    ],
    ['record_hash is not the hash of the row'],
    'a changed row is reported at its position'
);
$dbh->do( q{DELETE FROM audit_log WHERE chain_key = ? AND chain_position = 3},
    undef, $records->chain_key( 'thread', $thread ) );
is_deeply(
    [
        map { [ $_->{chain_position}, $_->{problem} ] }
          @{ $recorder->verify_audit_chain( 'thread', $thread ) }
    ],
    [
        [ 1,     'record_hash is not the hash of the row' ],
        [ $FOUR, 'position 4 follows 2' ],
        [ $FOUR, 'previous_hash is not the hash of the row before' ],
    ],
    'a missing row is a gap and a broken link at the row after it'
);
is_deeply( $recorder->verify_audit_chain( 'post', $post ),
    [], 'another chain is untouched' );

# A row written before the chains were per aggregate has no chain and is
# left as it is; the aggregate's chain starts after it.
my $legacy_target = $ids->uuid;
$dbh->do(
    q{INSERT INTO audit_log (audit_id, action, schema_version, actor_id,}
      . q{ target_type, target_id, correlation_id, previous_hash, record_hash,}
      . q{ metadata, created_at) VALUES (?, 'legacy.audited', 1, NULL,}
      . q{ 'thread', ?, ?, NULL, 'legacy', '{}', '2026-01-01T00:00:00Z')},
    undef, $ids->uuid, $legacy_target, $ids->uuid
);
my $after_legacy = $schema->txn_do(
    sub {
        return $recorder->record_audit(
            action         => 'thread.audited',
            actor_id       => $actor,
            correlation_id => $ids->uuid,
            created_at     => '2026-10-24T10:00:00Z',
            metadata       => {},
            target_id      => $legacy_target,
            target_type    => 'thread',
        );
    }
);
is( $after_legacy->{chain_position},
    1, 'the first row after a legacy row starts the aggregate\'s chain' );
is( $after_legacy->{previous_hash}, undef, 'linked to no legacy row' );
my ($legacy_chain) = $dbh->selectrow_array(
    q{SELECT chain_key FROM audit_log WHERE record_hash = 'legacy'});
is( $legacy_chain, undef, 'and the legacy row stays outside every chain' );

# The tip is read by index, in every partition.
my $plan = join "\n",
  map { $_->[0] } @{
    $dbh->selectall_arrayref(
            q{EXPLAIN SELECT record_hash, chain_position FROM audit_log}
          . q{ WHERE chain_key = 'thread:x' ORDER BY chain_position DESC LIMIT 1}
    )
  };
unlike( $plan, qr/Seq [ ] Scan/msx, 'the tip read scans no partition' );
like( $plan, qr/chain_key_chain_position/msx, 'it uses the chain index' );

done_testing();

# An audit document as the recorder sends one, for one target.
sub _document ( $type, $id, %over ) {
    return encode_json(
        {
            action         => "$type.audited",
            actor_id       => $actor,
            audit_id       => $over{audit_id} // $ids->uuid,
            correlation_id => $ids->uuid,
            created_at     => '2026-10-24T10:00:00Z',
            metadata       => {},
            schema_version => 1,
            target_id      => $id,
            target_type    => $type,
        }
    );
}

1;
