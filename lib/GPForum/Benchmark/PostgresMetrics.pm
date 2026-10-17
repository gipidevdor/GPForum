# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Benchmark::PostgresMetrics;
use v5.40;
use Const::Fast;
use Exporter qw(import);
our $VERSION   = '0.001';
our @EXPORT_OK = qw(snapshot process_snapshot local_backend_pid);
const my $SECONDS_PER_MINUTE => 60;

sub local_backend_pid ($dbh) {
    return $dbh->selectrow_array(
q{SELECT CASE WHEN inet_server_addr() IS NULL THEN pg_backend_pid() ELSE NULL END}
    );
}

sub snapshot ($dbh) {
    $dbh->do('SELECT pg_stat_clear_snapshot()');
    return {
        database => $dbh->selectrow_hashref(
q{SELECT blks_read, blks_hit, temp_bytes, tup_inserted, tup_updated, xact_commit FROM pg_stat_database WHERE datname = current_database()}
        ),
        wal => $dbh->selectrow_hashref(
            'SELECT wal_records, wal_fpi, wal_bytes FROM pg_stat_wal'),
        io => $dbh->selectall_arrayref(
            'SELECT * FROM pg_stat_io',
            { Slice => {} }
        ),
        lsn =>
          $dbh->selectrow_array('SELECT pg_current_wal_insert_lsn()::text'),
    };
}

# Local Unix-socket benchmarks only. RSS contains shared mappings and is
# never summed across PostgreSQL processes. ps CPU has centisecond precision.
sub process_snapshot ($pid) {
    return undef if !defined $pid;
    open my $fh, q{-|}, 'ps', '-p', $pid, '-o', 'time=,rss=' or return undef;
    my $line = <$fh> // q{};
    close $fh or return undef;
    my ( $minutes, $seconds, $rss ) =
      $line =~ /([[:digit:]]+):([[:digit:].]+)\s+([[:digit:]]+)/msx;
    return defined $rss
      ? {
        cpu_seconds => $SECONDS_PER_MINUTE * $minutes + $seconds,
        rss_kib     => 0 + $rss
      }
      : undef;
}

1;
