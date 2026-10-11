#!/usr/bin/env perl
# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;
use Carp qw(croak);
use Const::Fast;
use English       qw(-no_match_vars);
use File::Temp    qw(tempdir);
use Getopt::Long  qw(GetOptionsFromArray);
use JSON::MaybeXS qw(decode_json encode_json);
use POSIX         qw(_exit);
use Time::HiRes   qw(time);

use lib 'lib';
use lib 't/lib';

use GPForum::Command::Migrate;
use GPForum::Service::Outbox::Dispatcher;
use GPForum::Test::OutboxTransport;
use GPForum::Test::PostgresHarness;

our $VERSION = '0.001';
const my $MAX_MESSAGES    => 100_000;
const my $MAX_REPETITIONS => 5;
const my $BATCH_SIZE      => 100;
const my $MILLISECONDS    => 1_000;
const my $MIN_DURATION    => 0.000_001;
const my $P50             => 0.50;
const my $P95             => 0.95;
const my $P99             => 0.99;
const my $ROUND_HALF      => 0.5;

# The fixture benchmark remains script/bench-outbox-dispatcher. This adds
# the PostgreSQL costs it cannot measure, using the same real Dispatcher
# and recording transport, and real worker processes on independent DBI
# connections. CREATE DATABASE and migrations are outside the timed span.
exit main(@ARGV);

sub main (@arguments) {
    my $options = _options(@arguments);
    return _usage( $options->{usage} ) if defined $options->{usage};
    my %options = %{$options};
    return _benchmark( \%options );
}

sub _options (@arguments) {
    my %options = ( messages => 1_000, workers => '1,2', repetitions => 3 );
    GetOptionsFromArray( \@arguments, \%options,
        'messages=i', 'workers=s', 'repetitions=i', 'json', 'help' )
      or return { usage => 2 };
    return { usage => 0 } if $options{help};
    return { usage => 2 }
      if @arguments
      || $options{messages} < 1
      || $options{messages} > $MAX_MESSAGES
      || $options{repetitions} < 1
      || $options{repetitions} > $MAX_REPETITIONS
      || $options{workers} !~ /\A[1248](?:,[1248])*\z/msx;
    return \%options;
}

sub _benchmark ($option) {
    my %options   = %{$option};
    my $admin_dsn = $ENV{GPFORUM_DATABASE_DSN} // croak
      'GPFORUM_DATABASE_DSN is required for an owned benchmark database';
    my @workers = split /,/msx, $options{workers};
    my @children;
    my $database;
    my @results;
    my $failure;
    local $SIG{TERM} = sub { die "outbox benchmark interrupted\n"; };
    local $SIG{INT}  = sub { die "outbox benchmark interrupted\n"; };
    try {
        $database = GPForum::Test::PostgresHarness::create_database($admin_dsn);
        local $ENV{GPFORUM_DATABASE_DSN} = $database->{dsn};
        croak 'owned benchmark database migrations failed'
          if GPForum::Test::PostgresHarness::quietly(
            sub { return GPForum::Command::Migrate->new->run('--apply'); } );
        @results = _collect( $database, \%options, \@workers, \@children );
    }
    catch ($error) {
        $failure = "$error";
    };
    for my $pid (@children) {
        kill 'TERM', $pid;
        waitpid $pid, 0;
    }
    if ($database) {
        try {
            GPForum::Test::PostgresHarness::drop_database($database);
        }
        catch ($error) {
            $failure = ( $failure // q{} ) . " cleanup failed: $error";
        };
    }
    my @failed = grep { $_->{status} ne 'ok' } @results;
    my $status = $failure || @failed ? 'fail' : 'ok';
    my $report = {
        mode    => 'postgresql',
        status  => $status,
        results => \@results,
        dataset =>
          { messages => $options{messages}, batch_size => $BATCH_SIZE },
        limitations => [
            'No-op transport excludes real handlers and external delivery.',
'Batch percentiles include claim, renewal, dispatch and acknowledgement.',
'Timed wall span includes worker connection startup; migrations and seeding excluded.',
        ],
        ( $failure ? ( error => $failure ) : () ),
    };
    print encode_json($report), "\n" or croak 'cannot write outbox evidence';
    return $status eq 'ok' ? 0 : 1;
}

sub _collect ( $database, $options, $workers, $children ) {
    my @results;
    for my $repetition ( 1 .. $options->{repetitions} ) {

        # Alternating order reduces monotonic host/cache bias.
        my @order = $repetition % 2 ? @{$workers} : reverse @{$workers};
        for my $count (@order) {
            push @results,
              _run( $database, $options->{messages},
                $count, $repetition, $children );
        }
    }
    return @results;
}

sub _run ( $database, $messages, $workers, $repetition, $children ) {
    my $dbh = $database->{dbh};
    $dbh->do('TRUNCATE outbox_messages');
    $dbh->do(
        q{INSERT INTO outbox_messages (outbox_id, event_id, queue, job_type,}
          . q{ idempotency_key, payload, available_at, created_at, next_attempt_at)}
          . q{ SELECT md5('message-' || n)::uuid, md5('event-' || n)::uuid,}
          . q{ 'domain', 'benchmark.noop', 'performance-' || n, '{}'::jsonb,}
          . q{ timestamptz '2026-01-01', timestamptz '2026-01-01',}
          . q{ timestamptz '2026-01-01' FROM generate_series(1, ?::integer) n},
        undef, $messages
    );
    $dbh->do('ANALYZE outbox_messages');
    my $directory = tempdir( CLEANUP => 1 );
    pipe my $barrier_read, my $barrier_write or croak "pipe: $OS_ERROR";
    @{$children} = ();
    for my $worker ( 1 .. $workers ) {
        my $pid = _spawn( $database, $worker, $directory,
            $barrier_read, $barrier_write );
        push @{$children}, $pid;
    }
    close $barrier_read or croak "close barrier: $OS_ERROR";
    my $started = time;
    print {$barrier_write} 'x' x $workers or croak "release barrier: $OS_ERROR";
    close $barrier_write                  or croak "close barrier: $OS_ERROR";
    my $failed = 0;
    for my $pid ( @{$children} ) {
        waitpid $pid, 0;
        $failed ||= $CHILD_ERROR != 0;
    }
    @{$children} = ();
    my $elapsed = time - $started;
    return _summary( $dbh, $messages, $workers, $repetition,
        $directory, $elapsed, $failed );
}

sub _spawn ( $database, $worker, $directory, $barrier_read, $barrier_write ) {
    my $pid = fork;
    croak "fork: $OS_ERROR" if !defined $pid;
    return $pid             if $pid;

    # Only the parent owns database cleanup. A group timeout must not unwind
    # an inherited parent stack in children and race DROP DATABASE.
    local $SIG{TERM} = 'DEFAULT';
    local $SIG{INT}  = 'DEFAULT';
    close $barrier_write or _exit(1);

    # Never destruct an inherited parent DBI socket after a fork.
    $database->{dbh}{InactiveDestroy}       = 1;
    $database->{admin_dbh}{InactiveDestroy} = 1;
    my $token;

    # Unbuffered: read() can prefetch several tokens into one child's
    # PerlIO buffer, leaving other workers at EOF despite a complete release.
    sysread $barrier_read, $token, 1 or _exit(1);
    close $barrier_read or _exit(1);
    my $report;
    try {
        $report = _worker($worker);
    }
    catch ($error) {
        $report = { status => 'fail', error => "$error" };
    };
    open my $output, '>', "$directory/$worker.json" or _exit(1);
    print {$output} encode_json($report) or _exit(1);
    close $output                        or _exit(1);
    _exit( $report->{status} eq 'ok' ? 0 : 1 );
    return undef;
}

sub _summary ( $dbh, $messages, $workers, $repetition,
    $directory, $elapsed, $failed )
{
    my @delivered;
    my @batch_ms;
    my $acknowledged = 0;
    my @errors;
    for my $worker ( 1 .. $workers ) {
        my $report = _read_report("$directory/$worker.json");
        push @delivered, @{ $report->{delivered} // [] };
        push @batch_ms,  @{ $report->{batch_ms}  // [] };
        $acknowledged += $report->{acknowledged} // 0;
        if ( $report->{error} ) {
            push @errors, $report->{error};
        }
    }
    my %seen;
    my $duplicates = grep { $seen{$_}++ } @delivered;
    my $lost       = $messages - scalar keys %seen;
    my ($done)     = $dbh->selectrow_array(
        q{SELECT count(*) FROM outbox_messages WHERE status = 'done'});
    my $incomplete = $acknowledged != $messages || $done != $messages;
    return {
        status => $failed
          || @errors
          || $duplicates
          || $lost
          || $incomplete ? 'fail' : 'ok',
        workers             => $workers,
        repetition          => $repetition,
        messages            => $messages,
        duration_seconds    => $elapsed,
        messages_per_second => @delivered / ( $elapsed || $MIN_DURATION ),
        delivered           => scalar @delivered,
        acknowledged        => $acknowledged,
        done                => $done,
        lost                => $lost,
        duplicates          => $duplicates,
        p50_batch_ms        => _percentile( \@batch_ms, $P50 ),
        p95_batch_ms        => _percentile( \@batch_ms, $P95 ),
        p99_batch_ms        => _percentile( \@batch_ms, $P99 ),
        errors              => \@errors,
    };
}

sub _read_report ($path) {
    return { error => 'worker did not produce evidence' } if !-f $path;
    open my $input, '<', $path or croak "read worker report: $OS_ERROR";
    my $report =
      decode_json( do { local $INPUT_RECORD_SEPARATOR = undef; <$input> } );
    close $input or croak "close report: $OS_ERROR";
    return $report;
}

sub _worker ($number) {
    my $schema     = GPForum::Test::PostgresHarness::connect_schema();
    my $transport  = GPForum::Test::OutboxTransport->new;
    my $dispatcher = GPForum::Service::Outbox::Dispatcher->new(
        schema    => $schema,
        transport => $transport,
        worker_id => "performance-worker-$number",
    );
    my @batch_ms;
    my $acknowledged = 0;
    while (1) {
        my $started = time;
        my $batch   = $dispatcher->dispatch_pending($BATCH_SIZE);
        last if !$batch->{selected};
        push @batch_ms, ( time - $started ) * $MILLISECONDS;
        $acknowledged += $batch->{acknowledged};
    }
    $schema->storage->disconnect;
    return {
        status       => 'ok',
        delivered    => $transport->delivered,
        batch_ms     => \@batch_ms,
        acknowledged => $acknowledged
    };
}

sub _percentile ( $values, $quantile ) {
    return undef if !@{$values};
    my @sorted = sort { $a <=> $b } @{$values};
    return $sorted[ int( ( @sorted - 1 ) * $quantile + $ROUND_HALF ) ];
}

sub _usage ($code) {
    print 'Usage: script/performance-outbox.pl [--json] [--messages N]'
      . " [--workers 1,2,4] [--repetitions 1..5]\n"
      or croak 'cannot write usage';
    return $code;
}
