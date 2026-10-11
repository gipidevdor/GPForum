# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::PostgreSQL::Queries;

use v5.40;
use Exporter qw(import);

our $VERSION   = '0.001';
our @EXPORT_OK = qw(queries statements_sql row_types);
use constant CHECKPOINTER_MAJOR => 17;    ## no critic (ValuesAndExpressions::ProhibitConstantPragma)

# Explicit field types serve both normalization and the versioned schema;
# future server columns are never automatically included in public evidence.
sub row_types {
    my %fields = (
        database => {
            number => [
                qw(bytes xid_age xact_commit xact_rollback blks_read blks_hit temp_files temp_bytes deadlocks conflicts freeze_max_age)
            ],
            string => [qw(stats_reset track_counts)],
        },
        settings =>
          { string => [qw(name setting unit)], boolean => ['pending_restart'] },
        tables => {
            string => [
                qw(table_name last_vacuum last_autovacuum last_analyze last_autoanalyze)
            ],
            boolean => ['is_partition'],
            array   => ['vacuum_options'],
            number  => [
                qw(n_live_tup n_dead_tup n_mod_since_analyze seq_scan idx_scan n_tup_ins n_tup_upd n_tup_del vacuum_count autovacuum_count analyze_count autoanalyze_count xid_age total_bytes index_bytes dead_tuple_estimate_pct)
            ],
        },
        indexes => {
            string  => [qw(table_name index_name)],
            number  => [qw(idx_scan idx_tup_read idx_tup_fetch bytes)],
            boolean => [
                qw(valid ready is_unique is_primary is_partial backs_constraint)
            ],
        },
        activity => {
            number => [
                qw(connections active idle_in_transaction lock_waiters blocked hidden_sessions oldest_transaction_seconds)
            ]
        },
        wal => {
            number => [qw(wal_records wal_fpi wal_bytes wal_buffers_full)],
            string => ['stats_reset']
        },
        archive => {
            number => [qw(archived_count failed_count)],
            string => [qw(last_archived_time last_failed_time stats_reset)]
        },
        checkpoints => {
            number => [qw(timed requested write_ms sync_ms buffers_written)],
            string => ['stats_reset']
        },
        statements => {
            string  => ['query_id'],
            boolean => [qw(toplevel planning_measured)],
            number  => [
                qw(role_oid calls plans total_execution_ms mean_execution_ms stddev_execution_ms total_planning_ms mean_planning_ms stddev_planning_ms buffer_hits buffer_reads buffer_dirtied buffer_written temp_reads temp_written wal_records wal_fpi wal_bytes)
            ],
        },
    );
    my %types;
    for my $section ( keys %fields ) {
        for my $type ( keys %{ $fields{$section} } ) {
            for my $key ( @{ $fields{$section}{$type} } ) {
                $types{$section}{$key} = $type;
            }
        }
    }
    return \%types;
}

# Operator diagnostics read PostgreSQL's catalogs, never forum rows. This
# module is repository tooling and is never loaded by web or worker processes.
sub queries ($major) {
    return {
        database => <<'SQL',
SELECT pg_database_size(datid) AS bytes, age(d.datfrozenxid) AS xid_age,
       xact_commit, xact_rollback, blks_read, blks_hit, temp_files, temp_bytes,
       deadlocks, conflicts, stats_reset::text,
       current_setting('autovacuum_freeze_max_age')::bigint AS freeze_max_age,
       current_setting('track_counts') AS track_counts
FROM pg_catalog.pg_stat_database s
JOIN pg_catalog.pg_database d ON d.oid = s.datid
WHERE s.datname = current_database()
SQL
        settings => <<'SQL',
SELECT name, setting, unit, pending_restart
FROM pg_catalog.pg_settings
WHERE name IN ('autovacuum', 'autovacuum_analyze_threshold',
 'autovacuum_analyze_scale_factor', 'autovacuum_vacuum_threshold',
 'autovacuum_vacuum_scale_factor', 'autovacuum_freeze_max_age',
 'autovacuum_max_workers', 'autovacuum_vacuum_cost_limit',
 'autovacuum_vacuum_cost_delay', 'track_counts', 'track_activities',
 'track_io_timing', 'track_wal_io_timing', 'max_connections',
 'shared_buffers', 'work_mem', 'effective_cache_size', 'checkpoint_timeout',
 'max_wal_size', 'archive_mode', 'archive_timeout', 'compute_query_id',
 'pg_stat_statements.track', 'pg_stat_statements.track_planning',
 'auto_explain.log_min_duration', 'auto_explain.sample_rate',
 'auto_explain.log_analyze', 'auto_explain.log_timing',
 'auto_explain.log_parameter_max_length')
ORDER BY name
SQL
        tables => <<'SQL',
SELECT s.relname AS table_name, c.relispartition AS is_partition,
       s.n_live_tup, s.n_dead_tup, s.n_mod_since_analyze,
       s.seq_scan, s.idx_scan, s.n_tup_ins, s.n_tup_upd, s.n_tup_del,
       s.last_vacuum::text, s.last_autovacuum::text,
       s.last_analyze::text, s.last_autoanalyze::text,
       s.vacuum_count, s.autovacuum_count, s.analyze_count, s.autoanalyze_count,
       age(c.relfrozenxid) AS xid_age,
       pg_total_relation_size(c.oid) AS total_bytes,
       pg_indexes_size(c.oid) AS index_bytes,
       ARRAY(SELECT option FROM unnest(c.reloptions) option
             WHERE option LIKE 'autovacuum_%' ORDER BY option) AS vacuum_options
FROM pg_catalog.pg_stat_user_tables s
JOIN pg_catalog.pg_class c ON c.oid = s.relid
WHERE s.schemaname = 'public' AND c.relkind IN ('r', 'm')
ORDER BY s.n_dead_tup DESC, age(c.relfrozenxid) DESC, s.relname
LIMIT ?
SQL
        indexes => <<'SQL',
SELECT s.relname AS table_name, s.indexrelname AS index_name,
       s.idx_scan, s.idx_tup_read, s.idx_tup_fetch,
       pg_relation_size(s.indexrelid) AS bytes,
       i.indisvalid AS valid, i.indisready AS ready,
       i.indisunique AS is_unique, i.indisprimary AS is_primary,
       (i.indpred IS NOT NULL) AS is_partial,
       EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c
               WHERE c.conindid = s.indexrelid) AS backs_constraint
FROM pg_catalog.pg_stat_user_indexes s
JOIN pg_catalog.pg_index i ON i.indexrelid = s.indexrelid
WHERE s.schemaname = 'public'
ORDER BY pg_relation_size(s.indexrelid) DESC, s.indexrelname
LIMIT ?
SQL
        activity => <<'SQL',
SELECT count(*) AS connections,
       count(*) FILTER (WHERE state = 'active') AS active,
       count(*) FILTER (WHERE state = 'idle in transaction') AS idle_in_transaction,
       count(*) FILTER (WHERE wait_event_type = 'Lock') AS lock_waiters,
       count(*) FILTER (WHERE cardinality(pg_blocking_pids(pid)) > 0) AS blocked,
       count(*) FILTER (WHERE state IS NULL) AS hidden_sessions,
       max(extract(epoch FROM clock_timestamp() - xact_start)) AS oldest_transaction_seconds
FROM pg_catalog.pg_stat_activity
WHERE datname = current_database() AND backend_type = 'client backend'
  AND pid <> pg_backend_pid()
SQL
        wal => <<'SQL',
SELECT wal_records, wal_fpi, wal_bytes, wal_buffers_full, stats_reset::text
FROM pg_catalog.pg_stat_wal
SQL
        archive => <<'SQL',
SELECT archived_count, failed_count, last_archived_time::text,
       last_failed_time::text, stats_reset::text
FROM pg_catalog.pg_stat_archiver
SQL
        checkpoints => $major >= CHECKPOINTER_MAJOR ? <<'NEW_SQL' : <<'OLD_SQL',
SELECT num_timed AS timed, num_requested AS requested,
       write_time AS write_ms, sync_time AS sync_ms,
       buffers_written, stats_reset::text
FROM pg_catalog.pg_stat_checkpointer
NEW_SQL
SELECT checkpoints_timed AS timed, checkpoints_req AS requested,
       checkpoint_write_time AS write_ms, checkpoint_sync_time AS sync_ms,
       buffers_checkpoint AS buffers_written, stats_reset::text
FROM pg_catalog.pg_stat_bgwriter
OLD_SQL
    };
}

sub statements_sql ( $dbh, $namespace ) {
    my $function = $dbh->quote_identifier($namespace) . '.pg_stat_statements';
    return <<"SQL";
SELECT queryid::text AS query_id, userid AS role_oid, toplevel, calls, plans,
       total_exec_time AS total_execution_ms, mean_exec_time AS mean_execution_ms,
       stddev_exec_time AS stddev_execution_ms,
       total_plan_time AS total_planning_ms, mean_plan_time AS mean_planning_ms,
       stddev_plan_time AS stddev_planning_ms,
       shared_blks_hit AS buffer_hits, shared_blks_read AS buffer_reads,
       shared_blks_dirtied AS buffer_dirtied, shared_blks_written AS buffer_written,
       temp_blks_read AS temp_reads, temp_blks_written AS temp_written,
       wal_records, wal_fpi, wal_bytes
FROM $function(false)
WHERE dbid = (SELECT oid FROM pg_catalog.pg_database
              WHERE datname = current_database()) AND calls > 0
ORDER BY total_exec_time DESC, queryid NULLS LAST, userid, toplevel
LIMIT ?
SQL
}

1;

__END__

=head1 NAME

GPForum::PostgreSQL::Queries - Allowlisted operator catalog queries.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $sql = queries(18)->{database};

=head1 DESCRIPTION

Read-only repository diagnostics for PostgreSQL 16 through 18. Statement
statistics use C<pg_stat_statements(false)> and never retrieve SQL text.

=head1 SUBROUTINES/METHODS

=head2 queries

Returns named catalog queries for the supplied PostgreSQL major version.

=head2 statements_sql

Returns a bounded query against the extension namespace, quoted by DBI.

=head2 row_types

Returns each section's public field allowlist and JSON types.

=head1 DIAGNOSTICS

Errors are handled by the diagnostic collector.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

Core Perl and a supplied PostgreSQL DBI connection.

=head1 INCOMPATIBILITIES

Server versions outside 16 through 18 are unsupported.

=head1 BUGS AND LIMITATIONS

Statistics are cumulative estimates, not a measurement of physical bloat.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. BSD-3-Clause.

=cut
