# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Benchmark::PostgresMetrics;
use v5.40;
use Const::Fast;
use Exporter qw(import);
use POSIX    ();
our $VERSION   = '0.001';
our @EXPORT_OK = qw(snapshot process_snapshot ps_cpu_seconds local_backend_pid);
const my $SECONDS_PER_MINUTE => 60;
const my $MINUTES_PER_HOUR   => 60;
const my $HOURS_PER_DAY      => 24;
const my $DIGITS             => qr{[[:digit:]]+}msx;
const my $CLOCK              => qr{($DIGITS) : ($DIGITS (?: [.] $DIGITS )?)}msx;
const my $PS_TIME => qr{\A (?: ($DIGITS) - )? (?: ($DIGITS) : )? $CLOCK \z}msx;

# utime and stime, fields 14 and 15 of /proc/PID/stat, counted from the
# third, the first after the command name.
const my $UTIME_FIELD => 11;
const my $STIME_FIELD => 12;

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
# never summed across PostgreSQL processes. CPU is ps's, read in any of the
# forms its time column takes, or Linux's own count when /proc has it: ps
# there prints whole seconds.
sub process_snapshot ($pid) {
    return undef if !defined $pid || $pid !~ /\A [[:digit:]]+ \z/msx;

    # One -o a column: FreeBSD reads all after the first = of one argument
    # as that column's header.
    open my $fh, q{-|}, 'ps', '-p', $pid, '-o', 'time=', '-o', 'rss='
      or return undef;
    my $line = <$fh> // q{};
    close $fh or return undef;
    my ( $time, $rss ) = split q{ }, $line;
    my $cpu = ps_cpu_seconds($time);
    return undef if !defined $cpu || ( $rss // q{} ) !~ /\A [[:digit:]]+ \z/msx;

    return {
        cpu_seconds => _proc_cpu_seconds($pid) // $cpu,
        rss_kib     => 0 + $rss
    };
}

# A ps time column in seconds: MM:SS.ss (macOS and FreeBSD), [DD-]HH:MM:SS
# (Linux), HH:MM:SS.ss; undef for anything else.
sub ps_cpu_seconds ($text) {
    my ( $days, $hours, $minutes, $seconds ) = ( $text // q{} ) =~ $PS_TIME
      or return undef;

    return ( ( ( $days // 0 ) * $HOURS_PER_DAY + ( $hours // 0 ) ) *
          $MINUTES_PER_HOUR + $minutes ) * $SECONDS_PER_MINUTE + $seconds;
}

# User and system CPU from /proc/PID/stat, in clock ticks; undef where there
# is none. The command name, in parentheses, may hold spaces.
sub _proc_cpu_seconds ($pid) {
    open my $fh, '<', "/proc/$pid/stat" or return undef;
    my $stat = <$fh> // q{};
    close $fh or return undef;
    my ($after) = $stat =~ /[)] \s+ (.*) \z/msx;
    return undef if !defined $after;
    my @fields = split q{ }, $after;
    my $ticks  = POSIX::sysconf( POSIX::_SC_CLK_TCK() );
    return undef if !$ticks || !defined $fields[$STIME_FIELD];

    return ( $fields[$UTIME_FIELD] + $fields[$STIME_FIELD] ) / $ticks;
}

1;
