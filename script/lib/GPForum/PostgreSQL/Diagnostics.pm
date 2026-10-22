# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::PostgreSQL::Diagnostics;

use v5.40;
use Carp     qw(croak);
use Exporter qw(import);
use JSON::PP;
use POSIX       qw(strftime);
use Time::HiRes qw(clock_gettime CLOCK_MONOTONIC);

use GPForum::PostgreSQL::Queries qw(queries statements_sql row_types);

our $VERSION   = '0.001';
our @EXPORT_OK = qw(collect failure_report);

use constant {    ## no critic (ValuesAndExpressions::ProhibitConstantPragma)
    MIN_MAJOR            => 16,
    MAX_MAJOR            => 18,
    MAX_LIMIT            => 100,
    DEFAULT_LIMIT        => 25,
    STATEMENT_TIMEOUT_MS => 2_000,
    LOCK_TIMEOUT_MS      => 500,
    VERSION_DIVISOR      => 10_000,
    PERCENT              => 100,
};

sub failure_report ($reason) {
    return {
        check                => 'postgres_diagnostics',
        schema_version       => 1,
        status               => 'fail',
        checked_at           => strftime( '%Y-%m-%dT%H:%M:%SZ', gmtime ),
        environment          => {},
        sections             => {},
        error                => $reason,
        secrets_redacted     => JSON::PP::true,
        private_beta_claimed => 0,
        residual_gaps => ['No successful database inspection is claimed.'],
    };
}

sub collect ( $dbh, $options = {} ) {

    # PostgreSQL notices may contain SQL or parameter values too.
    local $SIG{__WARN__} = sub { return; };
    my $limit = $options->{limit} // DEFAULT_LIMIT;
    croak 'limit must be an integer from 1 through 100'
      if $limit !~ /\A [[:digit:]]+ \z/msx || $limit < 1 || $limit > MAX_LIMIT;
    croak 'diagnostics require a dedicated AutoCommit connection'
      if !$dbh->{AutoCommit};

    my $start  = clock_gettime(CLOCK_MONOTONIC);
    my $report = failure_report('inspection-failed');
    delete $report->{error};
    $report->{residual_gaps} = [
'Cumulative counters and estimated tuple counts are not workload benchmarks or physical bloat measurements.',
        'Cluster WAL, archive and checkpoint counters include other databases.',
'Zero index scans since a statistics reset do not justify dropping an index.',
'Query IDs are not comparable across PostgreSQL majors, architectures or independently recreated catalogs.',
    ];
    $report->{configuration} = {
        row_limit            => 0 + $limit,
        statement_timeout_ms => STATEMENT_TIMEOUT_MS,
        lock_timeout_ms      => LOCK_TIMEOUT_MS,
        transaction          => 'read-only-rollback',
        query_text_collected => JSON::PP::false,
    };

    my $started = 0;
    try {
        $dbh->begin_work;
        $started = 1;
        $dbh->do('SET LOCAL transaction_read_only = on');
        $dbh->do('SET LOCAL search_path = pg_catalog, pg_temp');
        $dbh->do( 'SET LOCAL statement_timeout = ' . STATEMENT_TIMEOUT_MS );
        $dbh->do( 'SET LOCAL lock_timeout = ' . LOCK_TIMEOUT_MS );
        my $environment = $dbh->selectrow_hashref(<<'SQL');
SELECT current_setting('server_version') AS postgres_version,
       current_setting('server_version_num')::integer AS version_number,
       pg_is_in_recovery() AS in_recovery,
       r.rolsuper AS superuser, r.rolbypassrls AS bypass_rls,
       pg_has_role(current_user, 'pg_read_all_stats', 'USAGE') AS all_statistics_visible
FROM pg_catalog.pg_roles r WHERE r.rolname = current_user
SQL
        $report->{environment} = _environment($environment);
        my $major = int( $environment->{version_number} / VERSION_DIVISOR );
        croak 'unsupported-server-major'
          if $major < MIN_MAJOR || $major > MAX_MAJOR;
        my $sql = queries($major);

        for my $section (
            qw(database settings tables indexes activity wal archive checkpoints)
          )
        {
            $report->{sections}{$section} = _section(
                $dbh,
                sub {
                    my @bind = $section eq 'tables'
                      || $section eq 'indexes' ? ($limit) : ();
                    return $dbh->selectall_arrayref( $sql->{$section},
                        { Slice => {} }, @bind );
                }
            );
        }
        $report->{sections}{statements} =
          _section( $dbh, sub { return _statements( $dbh, $limit ); } );
        _interpret($report);
    }
    catch ($error) {
        $report->{status} = 'fail';
        $report->{error} =
            "$error" =~ /unsupported-server-major/msx
          ? 'unsupported-server-major'
          : _reason( $dbh->state );
    };
    if ($started) {
        try { $dbh->rollback; }
        catch ($error) {
            $report->{status} = 'fail';
            $report->{error}  = 'rollback-failed';
        };
    }
    $report->{duration_seconds} = clock_gettime(CLOCK_MONOTONIC) - $start;
    _normalise($report);
    return $report;
}

sub _normalise ($report) {
    my $types = row_types();
    for my $section ( keys %{ $report->{sections} } ) {
        for my $row ( @{ $report->{sections}{$section}{rows} } ) {
            for my $key ( keys %{$row} ) {
                my $type = $types->{$section}{$key};
                if ( !defined $type ) { delete $row->{$key}; next; }
                next if !defined $row->{$key};
                if    ( $type eq 'number' ) { $row->{$key} = 0 + $row->{$key}; }
                elsif ( $type eq 'boolean' ) {
                    $row->{$key} =
                      $row->{$key} ? JSON::PP::true : JSON::PP::false;
                }
                elsif ( $type eq 'string' ) { $row->{$key} = "$row->{$key}"; }
            }
        }
    }
    return;
}

sub _environment ($row) {
    return {
        postgres_version => $row->{postgres_version},
        version_number   => 0 + $row->{version_number},
        in_recovery => $row->{in_recovery} ? JSON::PP::true : JSON::PP::false,
        superuser   => $row->{superuser}   ? JSON::PP::true : JSON::PP::false,
        bypass_rls  => $row->{bypass_rls}  ? JSON::PP::true : JSON::PP::false,
        all_statistics_visible => $row->{all_statistics_visible}
        ? JSON::PP::true
        : JSON::PP::false,
    };
}

sub _section ( $dbh, $reader ) {
    $dbh->do('SAVEPOINT diagnostics_section');
    my $section;
    try {
        $section = { status => 'ok', rows => $reader->() };
    }
    catch ($error) {
        my $state = $dbh->state;
        $dbh->do('ROLLBACK TO SAVEPOINT diagnostics_section');
        $section =
          { status => 'unavailable', reason => _reason($state), rows => [] };
    };
    $dbh->do('RELEASE SAVEPOINT diagnostics_section');
    return $section;
}

sub _reason ($state) {
    my %reasons = (
        '42501' => 'permission-denied',
        '55000' => 'extension-not-preloaded',
        '57014' => 'statement-timeout',
        '42P01' => 'catalog-unavailable',
        '42703' => 'catalog-column-unavailable',
    );
    return $reasons{ $state // q{} } // 'inspection-failed';
}

sub _statements ( $dbh, $limit ) {
    my ($namespace) = $dbh->selectrow_array(<<'SQL');
SELECT n.nspname FROM pg_catalog.pg_extension e
JOIN pg_catalog.pg_namespace n ON n.oid = e.extnamespace
WHERE e.extname = 'pg_stat_statements'
SQL
    return [] if !defined $namespace;
    my $rows = $dbh->selectall_arrayref( statements_sql( $dbh, $namespace ),
        { Slice => {} }, $limit );
    my ($planning) = $dbh->selectrow_array(
        q{SELECT current_setting('pg_stat_statements.track_planning', true)});
    for my $row ( @{$rows} ) {
        my $enabled  = defined $planning && $planning eq 'on';
        my $measured = $enabled          && ( $row->{plans} // 0 ) > 0;
        if ( !$enabled ) { $row->{plans} = undef; }
        if ( !$measured ) {
            for my $key (
                qw(total_planning_ms mean_planning_ms stddev_planning_ms))
            {
                $row->{$key} = undef;
            }
        }
        $row->{planning_measured} =
          $measured ? JSON::PP::true : JSON::PP::false;
    }
    return $rows;
}

sub _interpret ($report) {
    my $sections = $report->{sections};
    my @unavailable =
      grep { $sections->{$_}{status} ne 'ok' } sort keys %{$sections};
    if ( $sections->{statements}{status} eq 'ok'
        && !@{ $sections->{statements}{rows} } )
    {
        $sections->{statements}{status} = 'unavailable';
        $sections->{statements}{reason} = 'extension-absent-or-no-observations';
        push @unavailable, 'statements';
    }
    my @findings;
    for my $table ( @{ $sections->{tables}{rows} } ) {
        my $total =
          ( $table->{n_live_tup} // 0 ) + ( $table->{n_dead_tup} // 0 );
        $table->{dead_tuple_estimate_pct} =
          $total ? PERCENT * $table->{n_dead_tup} / $total : undef;
    }
    push @findings, _maintenance_findings($sections);
    if ( !$report->{environment}{all_statistics_visible} ) {
        push @findings, 'statistics-visibility-limited-to-current-role';
    }
    push @{ $report->{residual_gaps} },
      map { "Section $_ is unavailable: $sections->{$_}{reason}." }
      @unavailable;
    $report->{findings} = \@findings;
    $report->{status}   = @unavailable || @findings ? 'degraded' : 'ok';
    return;
}

sub _maintenance_findings ($sections) {
    my @findings;
    for my $index ( @{ $sections->{indexes}{rows} } ) {
        if ( !$index->{valid} || !$index->{ready} ) {
            push @findings, 'invalid-or-unready-index:' . $index->{index_name};
        }
    }
    for my $row ( @{ $sections->{database}{rows} } ) {
        if ( $row->{track_counts} ne 'on' ) {
            push @findings, 'track-counts-disabled';
        }
        if ( $row->{xid_age} >= $row->{freeze_max_age} ) {
            push @findings, 'database-xid-age-near-freeze-limit';
        }
    }
    return @findings;
}

1;

__END__

=head1 NAME

GPForum::PostgreSQL::Diagnostics - Bounded, private PostgreSQL operator evidence.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $report = collect($dedicated_dbh, { limit => 25 });

=head1 DESCRIPTION

Repository tooling, separate from the application function API. Inspects
allowlisted catalogs inside a dedicated read-only transaction and rolls it
back. Each optional section has its own savepoint. No query text, bind value,
connection string, setting source or database row is reported.

=head1 SUBROUTINES/METHODS

=head2 collect

Takes an AutoCommit DBI connection and optional bounded row limit. Returns
versioned evidence with status, metrics and explicit visibility limitations.

=head2 failure_report

Builds failed evidence without claiming a successful inspection.

=head1 DIAGNOSTICS

Public failures have constant reasons derived from SQLSTATE; server error
text, which can contain statements or secrets, is never returned.

=head1 CONFIGURATION AND ENVIRONMENT

Collection does not change server settings, statistics, tables or privileges.

=head1 DEPENDENCIES

Core Perl, PostgreSQL::Queries and a supplied DBI PostgreSQL connection.

=head1 INCOMPATIBILITIES

PostgreSQL outside versions 16 through 18 is rejected.

=head1 BUGS AND LIMITATIONS

Cumulative snapshots cannot prove workload throughput, bloat, an unused
index or production capacity. Unavailable measurements are explicit.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. BSD-3-Clause.

=cut
