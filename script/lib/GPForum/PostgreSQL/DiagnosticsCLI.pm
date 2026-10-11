# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::PostgreSQL::DiagnosticsCLI;
use v5.40;
use Exporter     qw(import);
use Getopt::Long qw(GetOptionsFromArray);
use JSON::PP;
use GPForum::Performance::Support    qw(root_dir read_json run_bounded);
use GPForum::Performance::Schema     qw(schema_validate secrets);
use GPForum::PostgreSQL::Diagnostics qw(collect failure_report);

our $VERSION   = '0.001';
our @EXPORT_OK = qw(main validate_evidence);
use constant {    ## no critic (ValuesAndExpressions::ProhibitConstantPragma)
    COMMAND_TIMEOUT => 5,
    VERSION_DIVISOR => 10_000,
    MIN_MAJOR       => 16,
    MAX_MAJOR       => 18,
};

sub main (@arguments) {
    my $options = _options( \@arguments );
    return _help() if $options->{help};
    if ( defined $options->{validate} ) {
        validate_evidence( read_json( $options->{validate} ) );
        print "Validated PostgreSQL diagnostic evidence\n"
          or die "Cannot write validation\n";
        return 0;
    }
    my $report = _collect($options);
    $report->{commit}       = _commit();
    $report->{source_dirty} = _source_dirty();
    validate_evidence($report);
    _write( $report, $options->{json} );
    return $report->{status} eq 'fail'
      || $options->{require_statements}
      && ( $report->{sections}{statements}{status} // q{} ) ne 'ok' ? 1 : 0;
}

sub _options ($arguments) {
    my %options;
    my $valid = GetOptionsFromArray(
        $arguments,
        'help'               => \$options{help},
        'json'               => \$options{json},
        'validate=s'         => \$options{validate},
        'require-statements' => \$options{require_statements},
        'limit=i'            => \$options{limit}
    );
    die "Use script/postgres-diagnostics --help\n" if !$valid || @{$arguments};
    return \%options;
}

sub _help {
    print <<'USAGE' or die "Cannot write usage\n";
Usage: script/gpforum-carton exec script/postgres-diagnostics [--json] [--limit 1..100] [--require-statements]
       script/postgres-diagnostics --validate FILE

Read-only operator diagnostics for PostgreSQL 16–18. Uses GPFORUM_DATABASE_DSN,
GPFORUM_DATABASE_USER and GPFORUM_DATABASE_PASSWORD from the operator's shell.
Never grants permissions or installs extensions. SQL text and binds are never
retrieved or published. No web/worker process loads this tool.

Exit: 0 completed (optional unavailable sections remain degraded), 1 failed
or required statement statistics unavailable. Validation needs only core Perl.
USAGE
    return 0;
}

sub _collect ($options) {
    local $SIG{__WARN__} = sub { return; };
    my $report;
    try {
        my $dsn = $ENV{GPFORUM_DATABASE_DSN} // q{};
        die "Missing operator PostgreSQL DSN\n" if $dsn !~ /\A dbi:Pg:/msx;
        require DBI;
        my $dbh = DBI->connect(
            $dsn . ';connect_timeout=5;application_name=gpforum_diagnostics',
            $ENV{GPFORUM_DATABASE_USER}     // q{},
            $ENV{GPFORUM_DATABASE_PASSWORD} // q{},
            {
                AutoCommit     => 1,
                RaiseError     => 1,
                PrintError     => 0,
                PrintWarn      => 0,
                pg_enable_utf8 => 1
            }
        );
        $report = collect( $dbh,
            defined $options->{limit} ? { limit => $options->{limit} } : {} );
        $dbh->disconnect;
    }
    catch ($error) {
        $report = failure_report('operator-connection-or-options-failed');
    };
    return $report;
}

sub _commit {
    my $commit = $ENV{GITHUB_SHA};
    if ( !defined $commit ) {
        try {
            my $result =
              run_bounded( [ 'git', '-C', root_dir(), 'rev-parse', 'HEAD' ],
                { timeout => COMMAND_TIMEOUT } );
            ($commit) = $result =~ /\A ([a-f[:digit:]]{40}) \s* \z/msx;
        }
        catch ($error) { $commit = undef; };
    }
    return defined $commit
      && $commit =~ /\A [a-f[:digit:]]{40} \z/msx ? $commit : undef;
}

sub _source_dirty {
    my $dirty;
    try {
        my $status =
          run_bounded( [ 'git', '-C', root_dir(), 'status', '--porcelain' ],
            { timeout => COMMAND_TIMEOUT } );
        $dirty = length($status) ? JSON::PP::true : JSON::PP::false;
    }
    catch ($error) { $dirty = undef; };
    return $dirty;
}

sub validate_evidence ($data) {
    my $schema =
      read_json( root_dir() . '/docs/ops/postgres-diagnostics-schema-v1.json' );
    schema_validate( $data, $schema );
    secrets($data);
    return 1 if $data->{status} eq 'fail';
    my $major =
      int( ( $data->{environment}{version_number} // 0 ) / VERSION_DIVISOR );
    die "Successful report has no supported PostgreSQL environment\n"
      if $major < MIN_MAJOR || $major > MAX_MAJOR;
    for my $section (
        qw(database settings tables indexes activity wal archive checkpoints statements)
      )
    {
        my $entry = $data->{sections}{$section};
        die "Successful report has an unmeasured section\n" if !defined $entry;
        die "Unavailable section has no reason or includes observations\n"
          if $entry->{status} eq 'unavailable'
          && ( !defined $entry->{reason} || @{ $entry->{rows} } );
        die "Incomplete section cannot be labelled ok\n"
          if $data->{status} eq 'ok' && $entry->{status} ne 'ok';
    }
    if ( $data->{status} eq 'ok' ) { _complete_ok($data); }
    return 1;
}

sub _complete_ok ($data) {
    die "Unobserved statement statistics cannot be labelled ok\n"
      if !@{ $data->{sections}{statements}{rows} };
    die "Findings or limited visibility cannot be labelled ok\n"
      if @{ $data->{findings} // [] }
      || !$data->{environment}{all_statistics_visible};
    return;
}

sub _write ( $report, $json ) {
    if ($json) {
        my $encoder = JSON::PP->new->canonical->pretty;
        print $encoder->encode($report) or die "Cannot write report\n";
        return;
    }
    print "PostgreSQL diagnostics: $report->{status}\n"
      or die "Cannot write report\n";
    for my $name ( sort keys %{ $report->{sections} } ) {
        my $section = $report->{sections}{$name};
        printf "%s: %s (%d rows)%s\n", $name, $section->{status},
          scalar @{ $section->{rows} },
          defined $section->{reason} ? " - $section->{reason}" : q{}
          or die "Cannot write section\n";
    }
    print "Use --json for metrics; see docs/ops/postgres-diagnostics.md.\n"
      or die "Cannot write guidance\n";
    return;
}

1;

__END__

=head1 NAME

GPForum::PostgreSQL::DiagnosticsCLI - PostgreSQL operator diagnostic entry point.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    exit main(@ARGV);

=head1 DESCRIPTION

Runs bounded catalog diagnostics or validates their versioned JSON without
loading the application. Validation uses the existing core schema validator.

=head1 SUBROUTINES/METHODS

=head2 main

Parses arguments, collects or validates evidence, and returns an exit code.

=head2 validate_evidence

Validates the schema, public field allowlist and completeness of successful
reports. Failed and unavailable results never become successful measurements.

=head1 DIAGNOSTICS

Connection failures return constant, secret-free failed evidence.

=head1 CONFIGURATION AND ENVIRONMENT

Uses the operator shell's GPFORUM_DATABASE_DSN, GPFORUM_DATABASE_USER and
GPFORUM_DATABASE_PASSWORD. Credentials are never copied into evidence.

=head1 DEPENDENCIES

Core Perl for validation; the locked DBI/DBD::Pg installation for collection.

=head1 INCOMPATIBILITIES

PostgreSQL versions outside 16 through 18.

=head1 BUGS AND LIMITATIONS

Optional absent extensions and restricted statistics visibility remain explicit.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. BSD-3-Clause.

=cut
