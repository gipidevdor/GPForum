# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use Mojo::File qw(path);
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Domain::EventEnvelope;

our $VERSION = '0.001';

# The forum's thread and post writes are PostgreSQL's (api.forum_write_command,
# api.forum_create_reply, ADR 0177): their transaction, event, audit and
# outbox boundaries are the functions', which t/integration holds. So are
# the privacy writes': their rollback on a failing record is
# t/integration/postgres-privacy-rollback.t's.
const my @CANONICAL_WRITE_STORES => (
    'lib/GPForum/Service/Moderation/ActionStore.pm',
    'lib/GPForum/Service/Moderation/ReportStore.pm',
    'lib/GPForum/Service/Moderation/SuspensionStore.pm',
    'lib/GPForum/Service/Privacy/DeletionWorkflow.pm',
    'lib/GPForum/Service/Privacy/RetentionHoldStore.pm',
);
const my @CONTROLLER_WRITE_METHODS => qw(create update update_or_create delete);
const my @INVARIANT_TEST_FILES => (
    't/11-forum-thread.t',
    't/12-forum-post.t',
    't/25-moderation-review.t',
    't/integration/postgres-privacy.t',
    't/41-thread-read-state.t',
    't/integration/postgres-sql-function-thread-actions.t',
    't/84-outbox-concurrent-dispatcher.t',
    't/85-realtime-outbox-multiprocess.t',
);

# The invariants the schema holds, as the fresh baseline writes them: keys and
# checks that make a write idempotent, ordered or valid, and the partial
# unique indexes that make two concurrent requests settle on one row.
const my @MIGRATION_CONSTRAINTS => (
    [ q{migrations/2004_records.sql}, qr/event_idempotency_keys_pkey/msx ],
    [
        q{migrations/2004_records.sql},
        qr/outbox_messages_idempotency_key_key/msx,
    ],
    [ q{migrations/2004_records.sql}, qr/outbox_messages_status_check/msx ],
    [ q{migrations/2003_forum.sql},   qr/posts_thread_position_key/msx ],
    [ q{migrations/2003_forum.sql}, qr/thread_counters_reply_count_check/msx ],
    [ q{migrations/2003_forum.sql}, qr/thread_read_state_pkey/msx ],
    [ q{migrations/2003_forum.sql}, qr/user_read_marker_deltas_pkey/msx ],
    [ q{migrations/2007_moderation.sql}, qr/reports_status_check/msx ],
    [
        q{migrations/2007_moderation.sql},
        qr/moderation_actions_target_type_check/msx,
    ],
    [ q{migrations/2004_records.sql}, qr/idx_outbox_messages_claim_ready/msx ],
    [ q{migrations/2004_records.sql}, qr/idx_outbox_messages_stale_locks/msx ],
    [ q{migrations/2010_privacy.sql}, qr/idx_erasure_jobs_request_unique/msx ],
    [
        q{migrations/2010_privacy.sql},
        qr/idx_deletion_requests_open_resource_unique/msx,
    ],
    [
        q{migrations/2010_privacy.sql},
        qr/idx_export_requests_pending_unique/msx,
    ],
    [
        q{migrations/2010_privacy.sql},
        qr/idx_retention_holds_active_resource_unique/msx,
    ],
    [
        q{migrations/2005_community.sql},
        qr/idx_reputation_events_source_unique/msx,
    ],
    [
        q{migrations/2005_community.sql},
qr/reputation_event_id [ ] uuid .*? source_id [ ] uuid [ ] NOT [ ] NULL/msx,
    ],
    [
        q{migrations/2001_identity.sql},
        qr/idx_identity_tokens_open_user_type/msx,
    ],
    [ q{migrations/2001_identity.sql}, qr/email_verification/msx ],
    [ q{migrations/2002_access.sql},   qr/idx_role_bindings_active_unique/msx ],
    [ q{migrations/2002_access.sql},   qr/NULLS [ ] NOT [ ] DISTINCT/msx ],
    [ q{migrations/2004_records.sql},  qr/idx_dead_letters_source_unique/msx ],
    [ q{migrations/2004_records.sql},  qr/source_table, [ ] source_id/msx ],
    [
        q{migrations/2001_identity.sql},
        qr/idx_credentials_active_password_unique/msx,
    ],
    [
        q{migrations/2001_identity.sql},
        qr/revoked_at [ ] IS [ ] NULL \s+ AND [ ] type [ ] = [ ] 'password'/msx,
    ],
);
const my $AT_SIGN_CODEPOINT => 64;

# The migration that creates the claim and the owned write the dispatcher calls.
const my $CLAIM_MIGRATION => q{migrations/2015_api_operations.sql};

# What the PostgreSQL outbox reclaim test names its two reclaim cases.
const my $RECLAIMS_EXPIRED_LOCK =>
  qr/reclaims [ ] the [ ] expired [ ] running [ ] lock/msx;
const my $RECLAIMS_AFTER_EXPIRY =>
  qr/reclaims [ ] after [ ] locked_until [ ] expires/msx;

_assert_canonical_boundaries();
_assert_event_envelope_contract();
_assert_outbox_claim_contract();
_assert_architectural_fitness();
_assert_hot_path_and_cache();
_assert_invariant_test_fixtures();
_assert_migration_constraints();
_assert_engineering_correctness_documentation();

done_testing();

sub _assert_canonical_boundaries {
    subtest
      'canonical writes keep transaction/event/audit/outbox boundaries' => sub {
        _assert_write_store_boundaries();
        _assert_event_recorder_boundary();
      };

    return;
}

sub _assert_write_store_boundaries {
    for my $file (@CANONICAL_WRITE_STORES) {
        my $source = _slurp($file) . _parts_source($file);

        # A store written once, as its promise method (ADR 0177), opens its
        # transaction with transaction_p and records through the calls.
        like(
            $source,
            qr/->(?:txn_do|transaction_p)[(]/msx,
            "$file uses transaction boundary"
        );
        like(
            $source,
            qr/record_event[(] | 'ops_record_event'/msx,
            "$file records domain event"
        );
        like(
            $source,
            qr/record_audit[(] | 'ops_record_audit'/msx,
            "$file records audit event"
        );
        like(
            $source . _event_module_source($file),
            qr/idempotency_key/msx,
            "$file provides event idempotency"
        );
    }

    return;
}

# Event envelopes, including idempotency keys, live in the sibling
# *::Event module since the event-extraction ADRs.
sub _event_module_source {
    my ($file) = @_;

    my $event_module = path($file)->sibling('Event.pm');

    return -f $event_module ? $event_module->slurp : q{};
}

# The recorder writes through api.ops_record_event and api.ops_record_audit
# (ADR 0126, ADR 0177), and those append the rows: the event, its outbox
# row and the audit record.
sub _assert_event_recorder_boundary {
    my $recorder = _slurp('lib/GPForum/Infrastructure/EventRecorder.pm');
    my $core     = _slurp('migrations/2012_api_core.sql');
    like(
        $recorder,
        qr/row_p[(][ ]'ops_record_event'/msx,
        'event recorder records the event through its function'
    );
    like(
        $recorder,
        qr/row_p[(][ ]'ops_record_audit'/msx,
        'event recorder records the audit through its function'
    );
    for my $writes (
        [ core_shared_record_event_v1  => 'event_log',       'EventLog' ],
        [ core_shared_ensure_outbox_v1 => 'outbox_messages', 'OutboxMessage' ],
        [ core_shared_append_audit_v1  => 'audit_log',       'AuditLog' ],
      )
    {
        my ( $function, $table, $source ) = @{$writes};
        my ($body) =
          $core =~ m{FUNCTION [ ] api[.]\Q$function\E (.*?) [\$][\$];}msx;
        like(
            $body // q{},
            qr{INSERT [ ] INTO [ ] public[.]\Q$table\E}msx,
            "event recorder appends $source row"
        );
    }

    return;
}

sub _assert_event_envelope_contract {
    subtest
      'event envelope exposes contract, version, correlation and idempotency'
      => sub {
        _assert_event_envelope_payload();
      };

    return;
}

sub _assert_event_envelope_payload {
    my $envelope = GPForum::Domain::EventEnvelope->new;
    my $event    = $envelope->record(
        actor_id          => 'user-1',
        aggregate_id      => 'thread-1',
        aggregate_type    => 'thread',
        aggregate_version => 1,
        correlation_id    => 'correlation-1',
        event_id          => 'event-1',
        event_type        => 'thread.created',
        payload           => { title => 'Welcome' },
        schema_version    => 1,
    );
    my $transport = $envelope->transport_payload($event);

    is( $transport->{contract},
        'gpforum.domain_event', 'transport contract is explicit' );
    is( $transport->{contract_version},
        1, 'transport contract version is explicit' );
    is( $transport->{correlation_id},
        'correlation-1', 'correlation id is durable' );
    is( $transport->{idempotency_key},
        'thread.created:thread-1', 'idempotency key is durable' );
    is( $transport->{schema_version}, 1, 'schema version is durable' );

    return;
}

sub _assert_outbox_claim_contract {
    subtest 'outbox dispatcher claim is concurrent and stale-lock safe' => sub {
        _assert_outbox_dispatcher_source();
        _assert_outbox_concurrency_fixture();
    };

    return;
}

sub _assert_outbox_dispatcher_source {

    # The dispatcher claims and writes through api.outbox_claim_ready and
    # api.outbox_owned_write (migration 1052), whose bodies hold the SQL
    # ADR 0025 once kept in ClaimQuery.
    my $dispatcher = _slurp('lib/GPForum/Service/Outbox/Dispatcher.pm');
    my $claim = _function_body( $CLAIM_MIGRATION, 'api.outbox_claim_ready_v5' );
    my $owned_write =
      _function_body( $CLAIM_MIGRATION, 'api.outbox_owned_write_v3' );

    like(
        $dispatcher,
        qr/sub [ ] claim_ready_batch/msx,
        'dispatcher exposes claim_ready_batch'
    );
    like(
        $dispatcher,
        qr/\x27outbox_claim_ready\x27/msx,
        'which claims through the claim function'
    );
    like( $dispatcher, qr/ClaimedMessage/msx,
        'PostgreSQL outbox hot path avoids DBIx row reloads' );
    for my $part (
        [ 'FOR UPDATE OF me SKIP LOCKED', 'claim uses FOR UPDATE SKIP LOCKED' ],
        [
            q{status IN ('pending', 'failed')},
            'claim includes pending and failed rows'
        ],
        [ q{status = 'running'}, 'claim includes running stale-lock rows' ],
        [
            'locked_until <= p_now::timestamptz',
            'claim recovers expired locks'
        ],
        [
            'ORDER BY ready.next_attempt_at, ready.created_at, ready.outbox_id',
            'claim uses deterministic next-at created-at id ordering'
        ],
        [ 'RETURNING', 'claim returns rows from the atomic update' ],
      )
    {
        my ( $text, $name ) = @{$part};
        ok( index( $claim, $text ) >= 0, $name );
    }
    ok(
        index( $owned_write,
            q{me.locked_by = p_worker_id AND me.status = 'running'} ) >= 0,
        'every outbox write after the claim is conditional on still owning it'
    );

    return;
}

# A function's body as its migration creates it, up to its closing $$.
sub _function_body ( $file, $name ) {
    my $migration = _slurp($file);
    my $start     = index $migration, "CREATE FUNCTION $name(";
    return q{} if $start < 0;

    return substr $migration, $start,
      index( $migration, "\n\$\$;", $start ) - $start;
}

sub _assert_outbox_concurrency_fixture {
    my $test       = _slurp('t/84-outbox-concurrent-dispatcher.t');
    my $pg_pool    = _slurp('t/integration/postgres-outbox-dispatcher.t');
    my $pg_reclaim = _slurp('t/integration/postgres-outbox-reclaim.t');
    my $worker_counts_line = 'const my ' . chr $AT_SIGN_CODEPOINT;
    $worker_counts_line .= 'WORKER_COUNTS => ( 2, 4, 8 );';

    # Which rows a claim takes is api.outbox_claim_ready's, so the pool of
    # workers and the stale and crashed claims run on PostgreSQL (ADR 0177).
    ok(
        index( $pg_pool, $worker_counts_line ) >= 0,
        'outbox concurrency test covers 2, 4, and 8 workers'
    );
    like(
        $pg_pool,
        qr/zero [ ] duplicate [ ] deliveries/msx,
        'outbox concurrency test verifies duplicate delivery count'
    );
    like(
        $pg_reclaim,
        qr/stale [ ] running [ ] reclaim [ ] delivers/msx,
        'outbox concurrency test verifies stale-lock recovery'
    );
    like(
        $pg_reclaim,
        qr/crash [ ] after [ ] claim [ ] leaves [ ] the [ ] row [ ] running/msx,
        'outbox concurrency test verifies crash between claim and dispatch'
    );
    like(
        $test,
        qr/retryable [ ] row [ ] schedules [ ] backoff/msx,
        'outbox concurrency test verifies retry/backoff'
    );
    like(
        $pg_reclaim,
        qr/exactly [ ] one [ ] worker [ ] $RECLAIMS_EXPIRED_LOCK/msx,
        'PostgreSQL outbox reclaim test covers concurrent stale-lock reclaim'
    );
    like(
        $pg_reclaim,
        qr/second [ ] connection [ ] $RECLAIMS_AFTER_EXPIRY/msx,
        'PostgreSQL outbox reclaim test covers claim-crash then reclaim'
    );

    return;
}

sub _assert_architectural_fitness {
    subtest 'architectural fitness gates keep writes behind services' => sub {
        _assert_controller_boundaries();
        _assert_template_boundaries();
    };

    return;
}

sub _assert_controller_boundaries {
    for my $file ( _perl_files('lib/GPForum/Controller') ) {
        my $source = _code_without_pod( $file->slurp );
        unlike(
            $source,
            qr/->resultset[[:space:]]*[(]/msx,
            "$file does not access DBIx::Class resultsets"
        );
        unlike(
            $source,
            qr/DBIx::Class|GPForum::Schema/msx,
            "$file does not depend on persistence classes"
        );
        _assert_no_controller_writes( $file, $source );
    }

    return;
}

sub _assert_no_controller_writes {
    my ( $file, $source ) = @_;

    for my $method (@CONTROLLER_WRITE_METHODS) {
        unlike(
            $source,
            qr/->$method[[:space:]]*[(]/msx,
            "$file does not perform direct $method writes"
        );
    }

    return;
}

sub _assert_template_boundaries {
    for my $file ( _template_files() ) {
        my $source = $file->slurp;
        unlike(
            $source,
            qr/resultset|DBIx::Class|GPForum::Schema/msx,
            "$file renders without persistence access"
        );
        unlike(
            $source,
            qr/->(?:create|update|delete|search)[[:space:]]*[(]/msx,
            "$file renders without business writes or searches"
        );
    }

    return;
}

sub _assert_hot_path_and_cache {
    subtest 'hot path rejects OFFSET and treats cache as disposable' => sub {
        _assert_no_offset_in_hot_path();
        _assert_cache_is_disposable();
    };

    return;
}

sub _assert_no_offset_in_hot_path {
    for my $file ( _perl_files('lib'), _template_files() ) {
        my $source = $file->slurp;
        unlike(
            $source,
            qr/\b OFFSET \b|-> [[:space:]]* search .* offset/msx,
            "$file does not use OFFSET in application hot path"
        );
    }

    return;
}

sub _assert_cache_is_disposable {
    my $cache = _slurp('lib/GPForum/Service/Operations/LocalCache.pm');
    unlike(
        $cache,
        qr/resultset|GPForum::Schema|txn_do/msx,
        'local cache cannot become a persistence authority'
    );
    like( $cache, qr/ttl_seconds/msx, 'local cache has TTL expiry' );
    like( $cache, qr/max_entries/msx, 'local cache has bounded size' );
    like( $cache, qr/invalidate/msx,  'local cache exposes invalidation' );

    my $shared = _slurp('lib/GPForum/Service/Operations/SharedCache.pm');
    unlike(
        $shared,
        qr/resultset|GPForum::Schema|txn_do/msx,
        'shared cache cannot become a persistence authority'
    );
    like( $shared, qr/ttl_seconds/msx, 'shared cache has TTL expiry' );
    like( $shared, qr/try_connect/msx,
        'shared cache degrades when the remote store is absent' );
    like( $shared, qr/connect_required/msx,
        'shared cache exposes a required connect path' );
    like( $shared, qr/invalidate/msx, 'shared cache exposes invalidation' );

    my $factory = _slurp('lib/GPForum/Service/Operations/CacheFactory.pm');
    unlike(
        $factory,
        qr/resultset|GPForum::Schema|txn_do/msx,
        'cache factory cannot become a persistence authority'
    );
    like( $factory, qr/TieredCache/msx,
        'cache factory wires shared L2 when GlifiStore is configured' );

    my $tiered = _slurp('lib/GPForum/Service/Operations/TieredCache.pm');
    unlike(
        $tiered,
        qr/resultset|GPForum::Schema|txn_do/msx,
        'tiered cache cannot become a persistence authority'
    );
    like( $tiered, qr/invalidate/msx, 'tiered cache exposes invalidation' );

    return;
}

sub _assert_invariant_test_fixtures {
    subtest 'domain invariant tests are executable release fixtures' => sub {
        _assert_invariant_files_exist();
        _assert_invariant_files_cover_expected_rules();
    };

    return;
}

sub _assert_invariant_files_exist {
    for my $file (@INVARIANT_TEST_FILES) {
        ok( -f $file, "$file exists" );
    }

    return;
}

sub _assert_invariant_files_cover_expected_rules {
    like( _slurp('t/25-moderation-review.t'),
        qr/idempotent/msx, 'moderation tests verify idempotent transitions' );
    like( _slurp('t/integration/postgres-privacy.t'),
        qr/idempotent/msx, 'privacy tests verify idempotent erasure/retry' );
    like(
        _slurp('t/integration/postgres-sql-function-thread-actions.t'),
        qr/never [ ] regresses/msx,
        'read-state tests verify monotonicity'
    );
    like(
        _slurp('t/85-realtime-outbox-multiprocess.t'),
        qr/polling [ ] fallback/msx,
        'realtime tests verify outbox fallback polling'
    );

    return;
}

sub _assert_migration_constraints {
    subtest 'migration constraints encode correctness invariants' => sub {
        _assert_migration_patterns();
    };

    return;
}

sub _assert_migration_patterns {
    for my $constraint (@MIGRATION_CONSTRAINTS) {
        my ( $file, $pattern ) = @{$constraint};
        like( _slurp($file), $pattern, "$file contains $pattern" );
    }

    return;
}

sub _assert_engineering_correctness_documentation {
    subtest 'engineering correctness documentation is present' => sub {
        _assert_engineering_doc_sections();
    };

    return;
}

sub _assert_engineering_doc_sections {
    my $doc = _slurp('docs/ENGINEERING_CORRECTNESS.md');

    like(
        $doc,
        qr/Engineering [ ] Correctness [ ] Freeze/msx,
        'document names the freeze'
    );
    like( $doc, qr{thread/post}msx, 'document covers thread/post invariants' );
    like( $doc, qr/read-state/msx,  'document covers read-state invariants' );
    like( $doc, qr/moderation/msx,  'document covers moderation invariants' );
    like( $doc, qr/outbox/msx,      'document covers outbox invariants' );
    like( $doc, qr/privacy/msx,     'document covers privacy invariants' );
    like(
        $doc,
        qr/failure [ ] injection/imsx,
        'document covers failure injection'
    );

    return;
}

sub _slurp {
    my ($file) = @_;

    return path($file)->slurp;
}

# A class split into parts that it inherits (DeletionWorkflow, whose parts are
# under Deletion/) is one store: the boundary is checked over all of them.
sub _parts_source {
    my ($file) = @_;

    my $directory = path( $file =~ s/Workflow[.]pm\z//rmsx );
    return q{} if !-d $directory;

    return join q{}, map { $_->slurp } @{ $directory->list };
}

# Boundary checks look at code only; POD may describe forbidden layers.
sub _code_without_pod {
    my ($source) = @_;

    $source =~ s/^=[[:alpha:]].*?(?:^=cut[^\n]*\n|\z)//gmsx;

    return $source;
}

sub _perl_files {
    my ($root) = @_;

    return grep { "$_" =~ /[.]pm\z/msx } path($root)->list_tree->each;
}

sub _template_files {
    return if !-d 'templates';

    return grep { "$_" =~ /[.]ep\z/msx } path('templates')->list_tree->each;
}

1;
