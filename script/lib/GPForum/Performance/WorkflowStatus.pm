# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause
package GPForum::Performance::WorkflowStatus;
use v5.40;
use Exporter qw(import);
use File::Spec;
use Getopt::Long                   qw(GetOptionsFromArray);
use GPForum::Performance::Support  qw(read_json write_json);
use GPForum::Performance::Evidence qw(initial);

our $VERSION   = '0.001';
our @EXPORT_OK = qw(statuses main);

sub statuses ($environment) {
    my %names = (
        contracts         => 'PERF_CONTRACTS',
        setup             => 'PERF_SETUP',
        tools             => 'PERF_TOOLS',
        databases         => 'PERF_DATABASES',
        migrations        => 'PERF_MIGRATIONS',
        http_workflow     => 'PERF_HTTP',
        hotpaths_workflow => 'PERF_HOTPATHS',
    );
    if ( ( $environment->{GITHUB_EVENT_NAME} // q{} ) eq 'pull_request' ) {
        @names{qw(baseline_setup baseline_http baseline_hotpaths)} =
          qw(PERF_BASE_SETUP PERF_BASE_HTTP PERF_BASE_HOTPATHS);
        if ( $environment->{PERF_BASE_REPORT} ) {
            $names{baseline_report} = 'PERF_BASE_REPORT';
        }
    }
    my %result;
    for my $name ( keys %names ) {
        my $outcome = $environment->{ $names{$name} } || 'skipped';
        my $state =
            $outcome eq 'success' ? 'ok'
          : $outcome eq 'failure' ? 'failed'
          :                         'skipped';
        $result{$name} = {
            status => $state,
            reason => "GitHub Actions step outcome: $outcome"
        };
        if ( $state eq 'failed' ) {
            my %infrastructure =
              map { $_ => 1 } qw(contracts setup tools databases);
            $result{$name}{failure_kind} =
              $infrastructure{$name}
              ? 'infrastructure_or_harness'
              : 'deterministic_or_infrastructure';
        }
    }
    $result{pr_comment} = {
        status => 'skipped',
        reason =>
'Job Summary and artifacts provide PR results with a read-only token; no privileged fork artifact/comment workflow is enabled.'
    };
    return \%result;
}

sub main (@arguments) {
    my %options;
    GetOptionsFromArray( \@arguments, \%options, qw(output=s check) )
      or die "Invalid workflow-status arguments\n";
    die "--output required\n" if !$options{output} || @arguments;
    if ( $options{check} ) {
        try {
            my $summary = read_json(
                File::Spec->catfile( $options{output}, 'summary.json' ) );
            my %known = map { $_ => 1 } qw(ok partial failed skipped);
            die "Invalid summary status\n"
              if !$known{ $summary->{status} // q{} };
            if (   $summary->{status} eq 'failed'
                || $summary->{status} eq 'skipped' )
            {
                print {*STDERR}
"Performance collection: $summary->{status}; see Job Summary and artifacts.\n"
                  or die "Cannot write collection diagnostic\n";
                return 1;
            }
            return 0;
        }
        catch ($error) {
            print {*STDERR}
              "Performance report was not generated; collection did not pass.\n"
              or die "Cannot write collection diagnostic\n";
            return 1;
        };
    }
    my $metadata = File::Spec->catfile( $options{output}, 'metadata.json' );
    if ( !-e $metadata ) {
        write_json(
            $metadata,
            initial(
                $ENV{PERF_MODE}   // 'pr',
                $ENV{PERF_COMMIT} // $ENV{GITHUB_SHA}
            )
        );
    }
    write_json( File::Spec->catfile( $options{output}, 'workflow-status.json' ),
        statuses( \%ENV ) );
    return 0;
}
1;
