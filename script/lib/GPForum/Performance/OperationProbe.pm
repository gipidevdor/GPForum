# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Performance::OperationProbe;

use v5.40;
use Carp qw(croak);
use Const::Fast;
use English       qw(-no_match_vars);
use JSON::MaybeXS qw(encode_json);
use Time::HiRes   qw(clock_gettime CLOCK_MONOTONIC);
use GPForum::Infrastructure::SqlFunction;
use GPForum::Service::Operations::DbQueryStats;

our $VERSION = '0.001';
my ( $installed, $stream, $stream_pid );
my %first;
const my $MILLISECONDS => 1_000;

# Loaded only by benchmark-operations, never by the application. Each process
# owns its append-only file, including children that leave through POSIX::_exit.
# No URLs, bind values, request bodies, exception messages or identifiers leave
# the process. Recording follows the measured interval, not the SQL timer.
sub import ($class) {
    return if $installed++;
    croak 'OperationProbe requires GPFORUM_BENCHMARK_TRACE_DIR'
      if !$ENV{GPFORUM_BENCHMARK_TRACE_DIR};
    my $execute = GPForum::Infrastructure::SqlFunction->can('_execute');
    my $start =
      GPForum::Service::Operations::DbQueryStats->can('start_request');
    my $finish =
      GPForum::Service::Operations::DbQueryStats->can('finish_request');
    no warnings 'redefine';    ## no critic (TestingAndDebugging::ProhibitNoWarnings) -- opt-in instrumentation of the production boundary
    ## no critic (Variables::ProtectPrivateVars) -- observe actual executions, not pre-answered page reads
    *GPForum::Infrastructure::SqlFunction::_execute =
      sub ( $self, $entry, $bound ) {
        my $started = clock_gettime(CLOCK_MONOTONIC);
        my ( $rows, $error );
        try { $rows = $execute->( $self, $entry, $bound ); }
        catch ($caught) { $error = $caught; };
        my $elapsed =
          ( clock_gettime(CLOCK_MONOTONIC) - $started ) * $MILLISECONDS;
        _record(
            {
                kind       => 'sql',
                operation  => $entry->{name} // 'uncatalogued',
                outcome    => defined $error ? 'exception' : 'returned',
                elapsed_ms => $elapsed,
                rows       => defined $rows ? scalar @{$rows} : 0,
            }
        );
        die $error if defined $error;    ## no critic (ErrorHandling::RequireCarping) -- preserve the exception object and its stack
        return $rows;
      };
    ## use critic
    *GPForum::Service::Operations::DbQueryStats::start_request =
      sub ( $self, @arguments ) {
        my $token = $start->( $self, @arguments );
        $token->{benchmark_started} = clock_gettime(CLOCK_MONOTONIC);
        return $token;
      };
    *GPForum::Service::Operations::DbQueryStats::finish_request =
      sub ( $self, $token, $metadata ) {
        my $elapsed =
          $token && defined $token->{benchmark_started}
          ? ( clock_gettime(CLOCK_MONOTONIC) - $token->{benchmark_started} ) *
          $MILLISECONDS
          : undef;
        my $request = $finish->( $self, $token, $metadata );
        if ($request) {
            _record(
                {
                    kind                 => 'http',
                    operation            => $request->{route},
                    outcome              => q{} . ( $request->{status} // 0 ),
                    elapsed_ms           => $elapsed // $request->{duration_ms},
                    db_ms                => $request->{db_duration_ms},
                    db_observer_attached => $request->{attached},
                    queries              => $request->{queries},
                    transactions         => $request->{transactions},
                }
            );
        }
        return $request;
      };
    return undef;
}

sub _record ($sample) {
    if ( !$stream_pid || $stream_pid != $PROCESS_ID ) {
        if ($stream) {
            close $stream or croak "Cannot close parent trace: $OS_ERROR";
        }
        ## no critic (InputOutput::RequireBriefOpen) -- one append descriptor per process avoids reopening on every measured SQL call
        open $stream, '>>:raw',
          "$ENV{GPFORUM_BENCHMARK_TRACE_DIR}/samples-$PROCESS_ID.jsonl"
          or croak "Cannot open operation trace: $OS_ERROR";
        ## use critic
        $stream_pid = $PROCESS_ID;
        %first      = ();
    }
    my $key = join q{:}, @{$sample}{qw(kind operation outcome)};
    $sample->{phase} = $first{$key}++ ? 'subsequent' : 'first';
    $sample->{test}  = $PROGRAM_NAME;
    my $line    = encode_json($sample) . "\n";
    my $written = syswrite $stream, $line;
    croak "Cannot write complete operation trace: $OS_ERROR"
      if !defined $written || $written != length $line;
    return undef;
}

1;
