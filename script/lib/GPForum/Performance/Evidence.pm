# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause
package GPForum::Performance::Evidence;
use v5.40;
use English        qw(-no_match_vars);
use Encode         qw(encode);
use Exporter       qw(import);
use File::Basename qw(dirname);
use File::Find     qw(find);
use File::Path     qw(make_path);
use File::Spec;
use Getopt::Long qw(GetOptionsFromArray);
use List::Util   qw(any);

# Core-only validation runs before the dependency setup action.
use constant MAX_FILE_BYTES => 8_000_000;    ## no critic (ValuesAndExpressions::ProhibitConstantPragma)
use GPForum::Performance::Support  qw(root_dir read_json write_json redact);
use GPForum::Performance::Metadata qw(initial compatible_signature command);
use GPForum::Performance::Schema   qw(schema_validate secrets);
use GPForum::Performance::Compare
  qw(key aggregate compare configuration_differences);
use GPForum::Performance::Report qw(report);

our $VERSION = '0.001';
our @EXPORT_OK =
  qw(initial compatible_signature command schema_validate secrets key aggregate compare configuration_differences report finalize validate index read_json write_json main);
my @KINDS = qw(http database outbox reactor workers);
my @PROVENANCE =
  qw(commit date timestamp run_id run_attempt runner versions dataset configuration);

sub _schema ( $path = undef ) {
    return read_json( $path
          // File::Spec->catfile( root_dir(), 'benchmarks/schema-v1.json' ) );
}

sub _path ( $directory, $name ) {
    return File::Spec->catfile( $directory, "$name.json" );
}

sub _text ( $path, $value ) {
    make_path( dirname($path) );
    open my $file, '>:raw', $path or die "Cannot write evidence text\n";
    print {$file} encode( 'UTF-8', $value )
      or die "Cannot write evidence text\n";
    close $file or die "Cannot close evidence text\n";
    return 1;
}

sub _raw ($path) {
    open my $file, '<:raw', $path or die "Cannot read evidence diagnostic\n";
    my $raw = do { local $INPUT_RECORD_SEPARATOR = undef; <$file> };
    close $file or die "Cannot close raw input\n";
    return $raw;
}

sub _http_contract ($value) {
    my @configuration =
      qw(scenario endpoint generator reactor workers concurrency repetition);
    my @metrics =
      qw(requests_per_second completed http_errors transport_errors p50_ms p95_ms p99_ms duration_seconds);
    for my $row ( @{ $value->{measurements} } ) {
        die "HTTP measurement is missing its scenario configuration\n"
          if any { !exists $row->{$_} } @configuration;
        die "HTTP measurement is missing required metrics\n"
          if any { !exists $row->{metrics}{$_} } @metrics;
        die "HTTP measurement duration must be positive\n"
          if !defined $row->{metrics}{duration_seconds}
          || $row->{metrics}{duration_seconds} <= 0;
    }
    return 1;
}

sub _validate_file ( $path, $name, $schema ) {
    die "Unsafe evidence file\n"
      if -l $path || !-f $path || -s $path > MAX_FILE_BYTES;
    my $value = read_json($path);
    schema_validate( $value, $schema );
    secrets($value);
    if ( any { $_ eq $name } @KINDS ) {
        die "Evidence kind does not match filename\n"
          if $value->{kind} ne $name;
        die "Measurement files require real observations\n"
          if !@{ $value->{measurements} // [] };
    }
    if ( $name eq 'http' ) { _http_contract($value); }
    return 1;
}

sub validate ( $output, $schema_path = undef ) {
    my $schema = _schema($schema_path);
    for my $name ( 'metadata', 'summary', @KINDS ) {
        my $path = _path( $output, $name );
        if ( !-e $path ) {
            die "Missing $name.json\n"
              if $name eq 'metadata' || $name eq 'summary';
            next;
        }

        _validate_file( $path, $name, $schema );
    }
    my $metadata = read_json( _path( $output, 'metadata' ) );
    my $summary  = read_json( _path( $output, 'summary' ) );
    for my $name (qw(commit date run_id run_attempt)) {
        die "Summary metadata mismatch: $name\n"
          if $metadata->{$name} ne $summary->{$name};
    }
    return 1;
}

sub _merge_environment ( $metadata, $output ) {
    for my $name ( 'http-environment', 'hotpaths-environment' ) {
        my $path = _path( $output, $name );
        next if !-e $path;
        my $extra = read_json($path);
        for my $field (qw(versions dataset configuration runner)) {
            @{ $metadata->{$field} }{ keys %{ $extra->{$field} // {} } } =
              values %{ $extra->{$field} // {} };
        }
        push @{ $metadata->{limitations} }, @{ $extra->{limitations} // [] };
    }
    $metadata->{comparison_signature} = compatible_signature($metadata);
    return 1;
}

sub _statuses ($output) {
    my %records;
    for my $name ( 'suite-status', 'hotpaths-status', 'workflow-status' ) {
        my $path = _path( $output, $name );
        next if !-e $path;
        my $data = read_json($path);
        if ( ref $data eq 'HASH' ) {
            @records{ keys %{$data} } = values %{$data};
        }
        else {
            for my $row ( @{$data} ) { $records{ $row->{scenario} } = $row; }
        }
    }
    return \%records;
}

sub _summaries ($root) {
    my @paths;
    if ( defined $root && -d $root ) {
        find(
            {
                no_chdir => 1,
                wanted   => sub {
                    if ( -f $File::Find::name
                        && $File::Find::name =~ m{(?:\A|/)summary[.]json\z}msx )
                    {
                        push @paths, $File::Find::name;
                    }
                }
            },
            $root
        );
    }
    return [ sort @paths ];
}

sub _choose_baseline ( $root, $metadata ) {
    my @candidates;
    for my $path ( @{ _summaries($root) } ) {
        try {
            my $summary = read_json($path);
            if (   ( $summary->{status} // q{} ) eq 'ok'
                && ( $summary->{comparison_signature} // q{} ) eq
                $metadata->{comparison_signature}
                && ( $summary->{commit} // q{} ) ne $metadata->{commit} )
            {
                push @candidates, [ $summary->{timestamp}, dirname($path) ];
            }
        }
        catch ($error) { next; };
    }
    @candidates =
      sort { $a->[0] cmp $b->[0] || $a->[1] cmp $b->[1] } @candidates;
    return @candidates ? $candidates[-1][1] : undef;
}

sub _validated_baseline ($directory) {
    my $prior;
    try {
        validate($directory);
        $prior = read_json( _path( $directory, 'summary' ) );
    }
    catch ($error) { $prior = undef; };
    return $prior;
}

sub _baseline ( $directory, $metadata ) {
    return ( undef, 'No baseline available.' ) if !defined $directory;
    my $prior = _validated_baseline($directory);
    return ( undef, 'Baseline invalid or incomplete.' ) if !$prior;
    if ( $prior->{status} eq 'failed' || $prior->{status} eq 'skipped' ) {
        return ( undef, 'Baseline failed or did not execute benchmarks.' );
    }
    if ( $prior->{comparison_signature} ne $metadata->{comparison_signature} ) {
        return ( undef,
            'Runner, dataset, configuration, mode or tool versions differ.' );
    }
    return ( $prior, 'Compatible baseline.' );
}

sub _collect ( $output, $metadata, $suites ) {
    my ( @measurements, @limitations );
    for my $kind (qw(http database outbox)) {
        my $path = _path( $output, $kind );
        if ( !-e $path ) {
            $suites->{$kind} //= {
                status => 'skipped',
                reason => 'No measurement data was produced.'
            };
            next;
        }
        my $payload;
        try {
            $payload = read_json($path);
            schema_validate( $payload, _schema() );
            secrets($payload);
            die "$kind has no valid observations\n"
              if !@{ $payload->{measurements} // [] }
              || $payload->{kind} ne $kind;
        }
        catch ($error) {
            $suites->{$kind} = {
                status       => 'failed',
                failure_kind => 'infrastructure_or_harness',
                reason       => "Invalid measurement payload: $error"
            };
            my $diagnostic = File::Spec->catfile( $output, 'diagnostics',
                "$kind-invalid.log" );
            _text( $diagnostic,
                index( "$error", 'Sensitive' ) >= 0
                ? "Payload rejected by secret screening.\n"
                : redact( _raw($path) ) );
            unlink $path or die "Cannot remove rejected measurement\n";
            next;
        };
        push @measurements, @{ aggregate( $payload->{measurements}, $kind ) };
        $suites->{$kind} //= { status => $payload->{status} };
        push @limitations, @{ $payload->{limitations} // [] };
        $payload->{provenance} = { map { $_ => $metadata->{$_} } @PROVENANCE };
        write_json( $path, $payload );
    }
    return ( \@measurements, \@limitations );
}

sub _views ( $output, $metadata, $measurements ) {
    for my $kind (qw(reactor workers)) {
        my @rows =
          grep { $_->{kind} eq 'http' && exists $_->{$kind} } @{$measurements};
        next if !@rows;
        my $differences = configuration_differences( \@rows, $kind );
        my $status =
            ( any { $_->{status} ne 'ok' } @rows ) ? 'failed'
          : @{$differences}                        ? 'ok'
          :                                          'partial';
        write_json(
            _path( $output, $kind ),
            {
                schema_version => 1,
                kind           => $kind,
                status         => $status,
                measurements   => \@rows,
                differences    => $differences,
                provenance     => { map { $_ => $metadata->{$_} } @PROVENANCE },
                limitations    => @{$differences}
                ? []
                : [
"Only one $kind configuration measured; comparison not executed."
                ]
            }
        );
    }
    return 1;
}

sub finalize ( $output, $options = {} ) {
    my $metadata = read_json( _path( $output, 'metadata' ) );
    _merge_environment( $metadata, $output );
    write_json( _path( $output, 'metadata' ), $metadata );
    my $suites = _statuses($output);
    my ( $measurements, $limits ) = _collect( $output, $metadata, $suites );
    my $baseline = $options->{baseline}
      // _choose_baseline( $options->{baseline_root}, $metadata );
    my ( $prior, $reason ) = _baseline( $baseline, $metadata );
    my %old = map { $_->{kind} . q{:} . key($_) => $_ }
      @{ $prior ? $prior->{measurements} : [] };

    for my $row ( @{$measurements} ) {
        $row->{comparison} =
          compare( $row, $old{ $row->{kind} . q{:} . key($row) } );
        if ( !$prior ) { $row->{comparison}{reason} = $reason; }
    }
    my %failed_status     = map { $_ => 1 } qw(failed fail);
    my %incomplete_status = map { $_ => 1 } qw(partial skipped);
    my $failed =
         ( any { $failed_status{ $_->{status} // q{} } } values %{$suites} )
      || ( any { $_->{status} ne 'ok' } @{$measurements} );
    my $incomplete =
      any { $incomplete_status{ $suites->{$_}{status} // q{} } }
      qw(http database outbox);
    my $status = $failed ? 'failed' : $incomplete
      && @{$measurements} ? 'partial' : @{$measurements} ? 'ok' : 'skipped';
    my %summary = map { $_ => $metadata->{$_} }
      qw(commit date timestamp run_id run_attempt mode comparison_signature runner dataset configuration);
    my %seen;
    @summary{
        qw(schema_version kind status suites measurements baseline limitations)}
      = (
        1,
        'summary',
        $status, $suites,
        $measurements,
        {
            path   => $baseline,
            commit => $prior ? $prior->{commit} : undef,
            reason => $reason
        },
        [ grep { !$seen{$_}++ } ( @{ $metadata->{limitations} }, @{$limits} ) ],
      );
    write_json( _path( $output, 'summary' ), \%summary );
    _views( $output, $metadata, $measurements );
    _text( File::Spec->catfile( $output, 'report.md' ),
        report( $metadata, \%summary ) );
    validate($output);
    return \%summary;
}

# Public CLI operation is named index for parity with the historical evidence API.
sub index ($root) {    ## no critic (Subroutines::ProhibitBuiltinHomonyms)
    my @rows;
    for my $path (
        @{ _summaries( File::Spec->catdir( $root, 'benchmarks/results' ) ) } )
    {
        validate( dirname($path) );
        my $summary = read_json($path);
        my %entry   = map { $_ => $summary->{$_} }
          qw(commit date timestamp run_id run_attempt mode status comparison_signature);
        $entry{path} = File::Spec->abs2rel( dirname($path), $root );
        $entry{metrics} =
          [ map { _history_metrics($_) } @{ $summary->{measurements} } ];
        push @rows, \%entry;
    }
    @rows = sort {
             $a->{timestamp}   cmp $b->{timestamp}
          || $a->{run_id}      cmp $b->{run_id}
          || $a->{run_attempt} cmp $b->{run_attempt}
    } @rows;
    my @valid = grep { $_->{status} eq 'ok' } @rows;
    write_json(
        File::Spec->catfile( $root, 'benchmarks/history.json' ),
        { schema_version => 1, kind => 'history', runs => \@rows }
    );
    write_json(
        File::Spec->catfile( $root, 'benchmarks/latest.json' ),
        {
            schema_version => 1,
            kind           => 'latest',
            run            => @valid ? $valid[-1] : undef
        }
    );
    for my $name (qw(history latest)) {
        schema_validate(
            read_json( File::Spec->catfile( $root, "benchmarks/$name.json" ) ),
            _schema()
        );
    }
    return 1;
}

sub _history_metrics ($row) {
    return { map { $_ => $row->{$_} }
          qw(kind scenario metrics comparison status) };
}

sub _initialize ($options) {
    my %modes = map { $_ => 1 } qw(pr main deep);
    die "--mode pr/main/deep required\n" if !$modes{ $options->{mode} // q{} };
    die "Evidence run already initialized; use a distinct directory\n"
      if -e _path( $options->{output}, 'metadata' );
    my $metadata = initial( $options->{mode}, $options->{commit} );
    schema_validate( $metadata, _schema() );
    write_json( _path( $options->{output}, 'metadata' ), $metadata );
    return 1;
}

sub main (@arguments) {
    my $action = shift @arguments
      // die "Action required: init/finalize/validate/index\n";
    my %options;
    GetOptionsFromArray( \@arguments, \%options,
        qw(output=s mode=s commit=s baseline=s baseline-root=s schema=s root=s)
    ) or die "Invalid evidence arguments\n";
    die "Unexpected evidence arguments\n" if @arguments;
    if ( $action eq 'index' ) {
        die "--root required\n" if !$options{root};
        GPForum::Performance::Evidence::index( $options{root} );
        return 0;
    }
    die "--output required\n" if !$options{output};
    if ( $action eq 'init' ) {
        _initialize( \%options );
    }
    elsif ( $action =~ /\Afinali[sz]e\z/msx ) {
        my $summary = finalize(
            $options{output},
            {
                baseline      => $options{baseline},
                baseline_root => $options{'baseline-root'}
            }
        );
        say "performance evidence: $summary->{status}, "
          . @{ $summary->{measurements} }
          . ' scenarios'
          or die "Cannot write evidence status\n";
    }
    elsif ( $action eq 'validate' ) {
        validate( $options{output}, $options{schema} );
        say 'Performance evidence schema valid'
          or die "Cannot write evidence status\n";
    }
    else { die "Unknown evidence action\n"; }
    return 0;
}
1;
