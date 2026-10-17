# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause
package GPForum::Performance::Publish;
use v5.40;
use English        qw(-no_match_vars);
use Cwd            qw(abs_path);
use Encode         qw(encode);
use Exporter       qw(import);
use File::Basename qw(dirname);
use File::Path     qw(make_path);
use File::Spec;
use File::Temp;
use Getopt::Long qw(GetOptionsFromArray);
use MIME::Base64 qw(encode_base64);
use List::Util   qw(any);

# The publisher runs without installing or executing artifact dependencies.
use constant {    ## no critic (ValuesAndExpressions::ProhibitConstantPragma)
    MAX_FILE_BYTES        => 8_000_000,
    MAX_PUBLICATION_BYTES => 30_000_000,
    GIT_TIMEOUT           => 45,
    MAX_STATUS            => 255,
    PUSH_ATTEMPTS         => 5
};
use GPForum::Performance::Support  qw(root_dir read_json run_bounded);
use GPForum::Performance::Evidence qw(validate report);

our $VERSION   = '0.001';
our @EXPORT_OK = qw(manifest append_result publish git_command main);
my @FILES =
  qw(metadata.json summary.json http.json database.json outbox.json reactor.json workers.json report.md);

# The history lives on a branch of its own: committed to main it grew by
# megabytes a day and raced every push. Main holds the harness, not the data.
my $BRANCH = 'performance-data';

sub _bytes ($path) {
    open my $file, '<:raw', $path or die "Cannot read publication data\n";
    my $raw = do { local $INPUT_RECORD_SEPARATOR = undef; <$file> };
    close $file or die "Cannot close raw input\n";
    return $raw;
}

sub _write_bytes ( $path, $bytes ) {
    open my $file, '>:raw', $path or die "Cannot write publication data\n";
    print {$file} $bytes or die "Cannot write publication data\n";
    close $file          or die "Cannot close publication data\n";
    return 1;
}

sub _provenance ( $metadata, $options ) {
    my %patterns = (
        commit      => qr/\A[[:xdigit:]]{40}\z/amsx,
        date        => qr/\A\d{4}-\d{2}-\d{2}\z/amsx,
        run_id      => qr/\A[[:alnum:]_-]{1,100}\z/amsx,
        run_attempt => qr/\A[1-9]\d{0,5}\z/amsx,
    );
    for my $field ( keys %patterns ) {
        die "Unsafe publication $field\n"
          if "$metadata->{$field}" !~ $patterns{$field};
    }
    for my $field (qw(commit run_id run_attempt)) {
        my $expected = $options->{$field};
        die "Artifact $field does not match the triggering run\n"
          if defined $expected && $metadata->{$field} ne $expected;
    }
    die "Only main/deep evidence can enter persistent history\n"
      if $metadata->{mode} ne 'main' && $metadata->{mode} ne 'deep';
    return 1;
}

sub _measurement_provenance ( $path, $metadata ) {
    my $provenance = read_json($path)->{provenance} // {};
    for my $field (qw(commit date)) {
        die "Measurement provenance differs from metadata\n"
          if !defined $provenance->{$field}
          || $provenance->{$field} ne $metadata->{$field};
    }
    for my $field (qw(run_id run_attempt)) {
        die "Measurement run differs from metadata\n"
          if exists $provenance->{$field}
          && $provenance->{$field} ne $metadata->{$field};
    }
    return 1;
}

sub _payload_files ( $source, $metadata, $summary ) {
    my %payload;
    my $total = 0;
    for my $name (@FILES) {
        my $path = File::Spec->catfile( $source, $name );
        next if !-e $path;
        die "Unsafe or excessive artifact file\n"
          if -l $path || !-f $path || -s $path > MAX_FILE_BYTES;
        if (   $name ne 'metadata.json'
            && $name ne 'summary.json'
            && $name ne 'report.md' )
        {
            _measurement_provenance( $path, $metadata );
        }
        my $data =
          $name eq 'report.md'
          ? encode( 'UTF-8', report( $metadata, $summary ) )
          : _bytes($path);
        $total += length $data;
        $payload{$name} = $data;
    }
    die "Evidence publication exceeds 30 MB\n"
      if $total > MAX_PUBLICATION_BYTES;
    $payload{'report.md'} = encode( 'UTF-8', report( $metadata, $summary ) );
    return \%payload;
}

sub manifest ( $source, $options = {} ) {
    die "Artifact directory is a symlink\n" if -l $source;
    validate($source);
    my $metadata = read_json( File::Spec->catfile( $source, 'metadata.json' ) );
    _provenance( $metadata, $options );
    my $summary = read_json( File::Spec->catfile( $source, 'summary.json' ) );
    for my $field (qw(commit date run_id run_attempt mode)) {
        die "Metadata and summary provenance differ\n"
          if $summary->{$field} ne $metadata->{$field};
    }
    my $relative = join q{/}, 'benchmarks/results', $metadata->{date},
      $metadata->{commit}, "$metadata->{run_id}-$metadata->{run_attempt}";
    return ( $relative, _payload_files( $source, $metadata, $summary ) );
}

sub _safe_destination ( $root, $relative ) {
    die "Unsafe destination path\n"
      if File::Spec->file_name_is_absolute($relative)
      || any { $_ eq q{..} } File::Spec->splitdir($relative);
    my $destination = File::Spec->catdir( $root, $relative );
    my $path        = $destination;
    while (1) {
        die "Results branch contains a symlink in the canonical path\n"
          if -l $path;
        last if $path eq $root || dirname($path) eq $path;
        $path = dirname($path);
    }
    return $destination;
}

sub _existing ( $destination, $payload ) {
    opendir my $directory, $destination
      or die "Cannot inspect historical result\n";
    my @files = grep {
        -f File::Spec->catfile( $destination, $_ )
          && !-l File::Spec->catfile( $destination, $_ )
    } readdir $directory;
    closedir $directory or die "Cannot close historical result\n";
    die
"Historical run already exists with different contents; refusing overwrite\n"
      if @files != keys %{$payload};
    for my $file (@files) {
        die
"Historical run already exists with different contents; refusing overwrite\n"
          if !exists $payload->{$file}
          || _bytes( File::Spec->catfile( $destination, $file ) ) ne
          $payload->{$file};
    }
    return 0;
}

sub append_result ( $root, $relative, $payload ) {
    $root = File::Spec->rel2abs($root);
    my $destination = _safe_destination( $root, $relative );
    return _existing( $destination, $payload ) if -e $destination;
    make_path($destination);
    for my $name ( keys %{$payload} ) {
        _write_bytes( File::Spec->catfile( $destination, $name ),
            $payload->{$name} );
    }
    validate($destination);
    GPForum::Performance::Evidence::index($root);
    return 1;
}

sub git_command ( $directory, $arguments, $options = {} ) {
    my %result;
    my $output = run_bounded(
        [
            'git', '-C', $directory, '-c', 'core.hooksPath=/dev/null',
            @{$arguments}
        ],
        {
            timeout        => GIT_TIMEOUT,
            env            => $options->{env},
            accepted_codes => [ 0 .. MAX_STATUS ],
            result         => \%result
        }
    );
    die 'Git operation '
      . $arguments->[0]
      . ' failed; inspect repository permissions/rules or network availability.'
      . "\n"
      if ( $options->{check} // 1 ) && $result{returncode};
    return { returncode => $result{returncode} // 0, output => $output };
}

sub _environment ($token) {
    my %environment =
      ( %ENV, GIT_TERMINAL_PROMPT => '0', GIT_LFS_SKIP_SMUDGE => '1' );
    if ( defined $token && length $token ) {
        my $basic = encode_base64( "x-access-token:$token", q{} );
        @environment{qw(GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0)}
          = (
            '1',
            'http.https://github.com/.extraheader',
            "AUTHORIZATION: basic $basic",
          );
    }
    return \%environment;
}

sub _attempt ( $directory, $remote, $relative, $payload, $environment ) {
    git_command( $directory, [ 'init', '--quiet' ], { env => $environment } );
    git_command(
        $directory,
        [ 'remote', 'add', 'origin', $remote ],
        { env => $environment }
    );
    my $exists = git_command(
        $directory,
        [ 'ls-remote', '--exit-code', '--heads', 'origin', $BRANCH ],
        { env => $environment, check => 0 }
    );
    die "Cannot inspect results branch; publication is not confirmed\n"
      if $exists->{returncode} != 0 && $exists->{returncode} != 2;
    die
"The $BRANCH branch is missing; refusing to initialize or replace its history\n"
      if $exists->{returncode} == 2;
    git_command(
        $directory,
        [ 'fetch', '--quiet', '--no-tags', '--depth=1', 'origin', $BRANCH ],
        { env => $environment }
    );
    git_command(
        $directory,
        [ 'checkout', '--quiet', '-b', $BRANCH, 'FETCH_HEAD' ],
        { env => $environment }
    );
    return 1 if !append_result( $directory, $relative, $payload );
    my $target = File::Spec->catdir( $directory, 'benchmarks' );

    for my $name ( 'README.md', 'schema-v1.json' ) {
        my $path   = File::Spec->catfile( $target,    $name );
        my $source = File::Spec->catfile( root_dir(), 'benchmarks', $name );
        if ( !-e $path && -f $source ) {
            _write_bytes( $path, _bytes($source) );
        }
    }
    my @additions =
      ( $relative, 'benchmarks/latest.json', 'benchmarks/history.json' );
    push @additions, map { "benchmarks/$_" }
      grep { -e File::Spec->catfile( $target, $_ ) }
      ( 'README.md', 'schema-v1.json' );
    git_command(
        $directory,
        [ 'add', q{--}, @additions ],
        { env => $environment }
    );
    my ( undef, undef, $run ) = File::Spec->splitpath($relative);
    git_command(
        $directory,
        [
            '-c',
            'user.name=github-actions[bot]',
            '-c',
            'user.email=41898282+github-actions[bot]@users.noreply.github.com',
            'commit',
            '--quiet',
            '-m',
            "Record performance evidence $run [skip ci]"
        ],
        { env => $environment }
    );
    return git_command(
        $directory,
        [ 'push', '--quiet', 'origin', "HEAD:refs/heads/$BRANCH" ],
        { env => $environment, check => 0 }
    )->{returncode} == 0;
}

sub publish ( $source, $remote, $options = {} ) {
    my ( $relative, $payload ) = manifest( $source, $options );
    my $environment = _environment( $options->{token} );
    for ( 1 .. ( $options->{attempts} // PUSH_ATTEMPTS ) ) {
        my $directory = File::Temp->newdir(
            'gpforum-performance-publish-XXXXXX',
            TMPDIR  => 1,
            CLEANUP => 1
        );
        return $relative
          if _attempt( "$directory", $remote, $relative, $payload,
            $environment );
    }
    die
"Publication failed after bounded retries; artifact remains available. Check branch rules and contents:write permission.\n";
}

sub main (@arguments) {
    my %options;
    GetOptionsFromArray( \@arguments, \%options,
        qw(input=s repository=s expected-commit=s expected-run=s expected-attempt=s)
    ) or die "Invalid publication arguments\n";
    die "Unexpected publication arguments\n" if @arguments;
    die "Missing publication argument\n"
      if any { !defined $options{$_} }
      qw(input repository expected-commit expected-run expected-attempt);
    die "Invalid repository name\n"
      if $options{repository} !~ m{\A[[:alnum:]_.-]+/[[:alnum:]_.-]+\z}amsx;
    die "Missing job-scoped GITHUB_TOKEN\n" if !$ENV{GITHUB_TOKEN};
    my $relative = publish(
        $options{input},
        "https://github.com/$options{repository}.git",
        {
            commit      => $options{'expected-commit'},
            run_id      => $options{'expected-run'},
            run_attempt => $options{'expected-attempt'},
            token       => $ENV{GITHUB_TOKEN}
        }
    );
    my $url = "https://github.com/$options{repository}/tree/$BRANCH/$relative";
    say "Published performance evidence: $url"
      or die "Cannot write publication status\n";

    if ( $ENV{GITHUB_STEP_SUMMARY} ) {
        open my $file, '>>:encoding(UTF-8)', $ENV{GITHUB_STEP_SUMMARY}
          or die "Cannot append publication summary\n";
        print {$file} "\n[Published immutable performance evidence]($url)\n"
          or die "Cannot write publication summary\n";
        close $file or die "Cannot close publication summary\n";
    }
    return 0;
}
1;
