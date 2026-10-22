#!/usr/bin/env perl
# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause
use v5.40;
our $VERSION = '0.001';
use English qw(-no_match_vars);
use lib 'script/lib';
use Test::More;
use Digest::SHA qw(sha256_hex);
use File::Path  qw(make_path);
use File::Temp  qw(tempdir);
use File::Spec;
use JSON::PP;
use GPForum::Performance::Evidence
  qw(initial finalize validate schema_validate secrets compatible_signature);
use GPForum::Performance::Support qw(read_json write_json root_dir);

my $root = tempdir( CLEANUP => 1 );

# Fixture constants keep this pre-install suite core-only.
use constant {    ## no critic (ValuesAndExpressions::ProhibitConstantPragma)
    SHA_LENGTH          => 40,
    DIGEST_LENGTH       => 64,
    REPEATS             => 3,
    BASE_RPS            => 100,
    HTTP_ERRORS         => 20,
    INCOMPATIBLE_CPUS   => 333,
    SCALED_WORKERS      => 4,
    NEGATIVE_LATENCY    => -1,
    CASE_CLASSIFICATION => 3,
};

sub clone ($value) {
    return JSON::PP->new->decode( JSON::PP->new->encode($value) );
}

sub failed ( $code, $pattern, $label ) {
    my $error;
    try { $code->(); }
    catch ($exception) { $error = "$exception"; };
    like( $error // q{}, $pattern, $label );
    return undef;
}

sub raw ($path) {
    open my $file, '<:raw', $path or die "Cannot read test fixture\n";
    my $raw = do { local $INPUT_RECORD_SEPARATOR = undef; <$file> };
    close $file or die "Cannot close raw input\n";
    return $raw;
}

sub fixture ( $name, $options = {} ) {
    my $output   = "$root/$name";
    my $commit   = $name eq 'base' ? 'a' : 'b';
    my $metadata = initial( 'pr', $commit x SHA_LENGTH );
    $metadata->{run_id}      = '77';
    $metadata->{run_attempt} = '1';
    $metadata->{versions} =
      { perl => '5.40', mojolicious => '9.49', postgres => '16' };
    $metadata->{dataset} = { profile => 'small', threads => 12, posts => 96 };
    $metadata->{configuration} =
      { harness_sha256 => { fixture => 'a' x DIGEST_LENGTH } };
    write_json( "$output/metadata.json", $metadata );
    my @rows;

    for my $repetition ( 1 .. ( $options->{count} // REPEATS ) ) {
        push @rows,
          {
            scenario    => 'health-live',
            endpoint    => '/health/live',
            generator   => 'wrk',
            reactor     => 'Mojo::Reactor::Poll',
            workers     => 2,
            concurrency => 10,
            repetition  => $repetition,
            status      => $options->{status} // 'ok',
            metrics     => {
                requests_per_second => ( $options->{rps} // BASE_RPS ) +
                  $repetition - 1,
                p50_ms      => 1,
                p95_ms      => 5,
                p99_ms      => 9,
                completed   => 200,
                http_errors => ( $options->{status} // 'ok' ) eq 'ok'
                ? 0
                : HTTP_ERRORS,
                transport_errors => 0,
                duration_seconds => 2,
                cpu_percent      => undef,
                rss_bytes        => 12_345_678
            }
          };
    }
    write_json(
        "$output/http.json",
        {
            schema_version => 1,
            kind           => 'http',
            status         => $options->{status} // 'ok',
            measurements   => \@rows,
            limitations    => []
        }
    );
    for my $kind (qw(database outbox)) {
        write_json(
            "$output/$kind.json",
            {
                schema_version => 1,
                kind           => $kind,
                status         => 'ok',
                measurements   => [
                    {
                        scenario => 'check',
                        status   => 'ok',
                        metrics  => { statements => 2 }
                    }
                ],
                limitations => []
            }
        );
    }
    return $output;
}

sub test_success {
    my $output  = fixture('success');
    my $summary = finalize($output);
    is( $summary->{status}, 'ok', 'actual suites ran' );
    is( $summary->{measurements}[0]{comparison}{classification},
        'not-comparable', 'absent baseline is explicit' );
    like( $summary->{measurements}[0]{comparison}{reason},
        qr/No\x20baseline/msx, 'absent reason retained' );
    ok( validate($output), 'schema validates' );
    like( raw("$output/report.md"),
        qr/Mojo::Reactor::Poll/msx, 'rendered actual reactor' );
    is(
        read_json("$output/http.json")->{provenance}{commit},
        'b' x SHA_LENGTH,
        'HTTP envelope has commit'
    );

    for my $path (
        't/lib/GPForum/Test/PostgresHarness.pm',
        't/lib/GPForum/Test/OutboxTransport.pm'
      )
    {
        my $metadata = initial( 'main', 'a' x SHA_LENGTH );
        my $workflow = raw( root_dir() . '/.github/workflows/performance.yml' );
        ok( index( $workflow, "- '$path'" ) >= 0, "$path triggers evidence" );
        is(
            $metadata->{configuration}{harness_sha256}{$path},
            sha256_hex( raw( root_dir() . "/$path" ) ),
            "$path actual digest"
        );
        my $changed = clone($metadata);
        $changed->{configuration}{harness_sha256}{$path} = '0' x DIGEST_LENGTH;
        isnt(
            compatible_signature($metadata),
            compatible_signature($changed),
            'support changes invalidate baseline'
        );
    }
    return undef;
}
subtest 'success, provenance and safe report' => \&test_success;

sub test_failures {
    my $failure = finalize( fixture( 'failure', { status => 'failed' } ) );
    is( $failure->{status}, 'failed', 'failure saved' );
    is_deeply( $failure->{measurements}[0]{metrics},
        {}, 'failed cells do not invent statistics' );
    my $output = "$root/skip";
    write_json( "$output/metadata.json", initial( 'pr', 'b' x SHA_LENGTH ) );
    write_json( "$output/suite-status.json",
        { http => { status => 'skipped', reason => 'wrk unavailable' } } );
    is( finalize($output)->{status}, 'skipped', 'no measurement never passes' );
    ok( !-e "$output/http.json" && !-e "$output/reactor.json",
        'no invented measurement files' );
    like( raw("$output/report.md"),
        qr/wrk\x20unavailable/msx, 'skip reason reported' );
    return undef;
}
subtest 'failed and skipped are never success' => \&test_failures;

sub test_baseline {
    my $base = fixture('base');
    finalize($base);
    for my $case (
        [ confirmed       => 70,  REPEATS, 'confirmed-regression' ],
        [ single          => 40,  1,       'possible-regression' ],
        [ stable          => 103, REPEATS, 'stable' ],
        [ improved        => 140, REPEATS, 'improvement' ],
        [ single_improved => 140, 1,       'not-comparable' ]
      )
    {
        my $summary = finalize(
            fixture( $case->[0], { rps => $case->[1], count => $case->[2] } ),
            { baseline => $base } );
        is(
            $summary->{measurements}[0]{comparison}{classification},
            $case->[CASE_CLASSIFICATION],
            $case->[0]
        );
        is( $summary->{status}, 'ok', 'timing classifications are advisory' );
    }
    my $current  = fixture( 'incompatible', { rps => 40 } );
    my $metadata = read_json("$current/metadata.json");
    $metadata->{runner}{cpu_count} = INCOMPATIBLE_CPUS;
    write_json( "$current/metadata.json", $metadata );
    is(
        finalize( $current, { baseline => $base } )
          ->{measurements}[0]{comparison}{classification},
        'not-comparable',
        'different runner rejected'
    );
    my $failed_base = fixture( 'failed_base', { status => 'failed' } );
    finalize($failed_base);
    like(
        finalize( fixture('after_failed'), { baseline => $failed_base } )
          ->{baseline}{reason},
        qr/Baseline\x20failed/msx,
        'failed baseline rejected'
    );
    return undef;
}
subtest 'robust repeated baseline comparisons' => \&test_baseline;

sub test_configurations {
    my $output  = fixture('workers');
    my $payload = read_json("$output/http.json");
    my $scaled  = clone( $payload->{measurements} );
    for my $row ( @{$scaled} ) {
        $row->{workers} = SCALED_WORKERS;
        $row->{metrics}{requests_per_second} *= 2;
    }
    push @{ $payload->{measurements} }, @{$scaled};
    write_json( "$output/http.json", $payload );
    finalize($output);
    my $workers = read_json("$output/workers.json");
    is( $workers->{status}, 'ok',               'worker comparison measured' );
    is( scalar @{ $workers->{differences} }, 1, 'one scaled configuration' );
    is( $workers->{differences}[0]{comparison}{classification},
        'improvement', 'robust scaled comparison' );
    is( read_json("$output/reactor.json")->{status},
        'partial', 'single reactor is not a comparison' );
    like( raw("$output/report.md"), qr/workers=4/msx, 'comparison rendered' );
    return undef;
}
subtest 'worker and reactor derived views' => \&test_configurations;

sub test_invalid_records {
    my $output = fixture('validation');
    finalize($output);
    my $payload = read_json("$output/http.json");
    for my $kind (qw(negative secret missing metric configuration duration)) {
        my $changed = clone($payload);
        if ( $kind eq 'negative' ) {
            $changed->{measurements}[0]{metrics}{p95_ms} = NEGATIVE_LATENCY;
        }
        if ( $kind eq 'secret' ) { $changed->{password} = 'oops'; }
        if ( $kind eq 'missing' ) {
            delete $changed->{measurements}[0]{status};
        }
        if ( $kind eq 'metric' ) {
            delete $changed->{measurements}[0]{metrics}{completed};
        }
        if ( $kind eq 'configuration' ) {
            delete $changed->{measurements}[0]{generator};
        }
        if ( $kind eq 'duration' ) {
            $changed->{measurements}[0]{metrics}{duration_seconds} = 0;
        }
        write_json( "$output/http.json", $changed );
        failed(
            sub { validate($output) },
            qr/schema\x20variant|Sensitive|HTTP\x20measurement/msx,
            "$kind rejected"
        );
    }
    open my $file, '>', "$output/http.json"
      or die "Cannot prepare test fixture\n";
    print {$file} '{"v": NaN}' or die "Cannot write invalid fixture\n";
    close $file                or die "Cannot close fixture\n";
    failed(
        sub { validate($output) },
        qr/malformed|unexpected|JSON|character/imsx,
        'nonfinite input rejected'
    );
    failed( sub { schema_validate( {}, { unknown_keyword => 1 } ) },
        qr/unsupported\x20schema/msx, 'unknown schema keywords fail closed' );
    failed( sub { secrets( { detail => 'postgres://user:secret@host/db' } ) },
        qr/Sensitive\x20value/msx, 'connection secret rejected' );
    return undef;
}
subtest 'malformed, nonfinite, secret and incomplete records are rejected' =>
  \&test_invalid_records;

sub test_partial_failure {
    my $output = fixture('partial_failure');
    open my $file, '>', "$output/database.json"
      or die "Cannot prepare test fixture\n";
    print {$file} '{"password":"test-value", BROKEN}'
      or die "Cannot write invalid fixture\n";
    close $file or die "Cannot close fixture\n";
    my $summary = finalize($output);
    is( $summary->{status}, 'failed', 'invalid SQL recorded' );
    ok( !-e "$output/database.json" && -e "$output/http.json",
        'valid HTTP retained' );
    unlike( raw("$output/diagnostics/database-invalid.log"),
        qr/test-value/msx, 'diagnostic secret redacted' );
    ok( validate($output), 'partial failure remains valid evidence' );
    return undef;
}
subtest
  'one invalid suite preserves valid measurements and redacts diagnostics' =>
  \&test_partial_failure;

sub test_immutable_indices {
    my @historical;
    for my $attempt ( '1', '2' ) {
        my $source   = fixture("run$attempt");
        my $metadata = read_json("$source/metadata.json");
        $metadata->{run_attempt} = $attempt;
        write_json( "$source/metadata.json", $metadata );
        finalize($source);
        my $destination =
            "$root/benchmarks/results/2026-10-11/"
          . ( 'b' x SHA_LENGTH )
          . "/77-$attempt";
        make_path(
            File::Spec->catdir(
                $root,
                'benchmarks/results/2026-10-11',
                'b' x SHA_LENGTH
            )
        );
        rename $source, $destination or die "Cannot prepare test fixture\n";
        push @historical, "$destination/summary.json";
    }
    my %before = map { $_ => raw($_) } @historical;
    GPForum::Performance::Evidence::index($root);
    is( scalar @{ read_json("$root/benchmarks/history.json")->{runs} },
        2, 'distinct attempts retained' );
    is( read_json("$root/benchmarks/latest.json")->{run}{run_attempt},
        '2', 'latest valid attempt' );
    GPForum::Performance::Evidence::index($root);
    is_deeply( { map { $_ => raw($_) } @historical },
        \%before, 'index never rewrites measurements' );
    my $partial = fixture('partial_history');
    write_json( "$partial/workflow-status.json",
        { http => { status => 'partial', reason => 'suite deadline' } } );
    my $metadata = read_json("$partial/metadata.json");
    $metadata->{run_id} = '78';
    write_json( "$partial/metadata.json", $metadata );
    finalize($partial);
    rename $partial,
      "$root/benchmarks/results/2026-10-11/" . ( 'b' x SHA_LENGTH ) . '/78-1'
      or die "Cannot prepare test fixture\n";
    GPForum::Performance::Evidence::index($root);
    is( read_json("$root/benchmarks/latest.json")->{run}{run_id},
        '77', 'partial never latest' );
    is( scalar @{ read_json("$root/benchmarks/history.json")->{runs} },
        REPEATS, 'partial included in history' );
    return undef;
}
subtest 'append-only indices retain failures and distinct attempts' =>
  \&test_immutable_indices;
done_testing;
