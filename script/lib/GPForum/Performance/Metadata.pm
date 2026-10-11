# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause
package GPForum::Performance::Metadata;
use v5.40;
use English     qw(-no_match_vars);
use Digest::SHA qw(sha256_hex);
use Exporter    qw(import);
use File::Find  qw(find);
use File::Spec;
use JSON::PP;
use POSIX                         qw(uname strftime);
use Time::HiRes                   qw(time);
use GPForum::Performance::Support qw(root_dir run_bounded);

# Metadata collection precedes the locked CPAN setup.
use constant {    ## no critic (ValuesAndExpressions::ProhibitConstantPragma)
    COMMAND_TIMEOUT => 10,
    KIB             => 1024,
    GIB             => 1_073_741_824,
    MICROSECONDS    => 1_000_000,
    ID_LENGTH       => 32,
    COMMIT_LENGTH   => 40,
    ROUND_HALF      => 0.5,
};

our $VERSION   = '0.001';
our @EXPORT_OK = qw(initial compatible_signature command);

sub command ($arguments) {
    my $value;
    try { $value = run_bounded( $arguments, { timeout => COMMAND_TIMEOUT } ); }
    catch ($error) { return undef; };
    $value =~ s/\s+\z//msx;
    return $value;
}

sub _bytes ($path) {
    open my $file, '<:raw', $path or die "Cannot read harness file\n";
    my $raw = do { local $INPUT_RECORD_SEPARATOR = undef; <$file> };
    close $file or die "Cannot close raw input\n";
    return $raw;
}

sub _runner {
    my ( $os, undef, $kernel, undef, $arch ) = uname();
    my $model = $arch;
    my ( $memory, $cpus );
    if ( -f '/proc/cpuinfo' ) {
        my $raw = _bytes('/proc/cpuinfo');
        if ( $raw =~ /model\x20name\s*:\s*([^\n]+)/msx ) { $model = $1; }
        $cpus = scalar( () = $raw =~ /^processor\s*:/mgsx );
        my $mem = _bytes('/proc/meminfo');
        if ( $mem =~ /MemTotal:\s*(\d+)/msx ) { $memory = $1 * KIB; }
    }
    elsif ( $os eq 'Darwin' ) {
        $model = command( [ 'sysctl', '-n', 'machdep.cpu.brand_string' ] )
          // $arch;
        $memory = command( [ 'sysctl', '-n', 'hw.memsize' ] );
        $memory =
          defined $memory && $memory =~ /\A\d+\z/msx ? 0 + $memory : undef;
        $cpus = command( [ 'sysctl', '-n', 'hw.ncpu' ] );
    }
    $cpus //= command( [ 'getconf', '_NPROCESSORS_ONLN' ] );
    $cpus = defined $cpus && $cpus =~ /\A\d+\z/msx ? 0 + $cpus : undef;
    return {
        os            => $os,
        arch          => $arch,
        cpu_count     => $cpus,
        cpu_model     => $model,
        memory_bytes  => $memory,
        kernel        => $kernel,
        name          => $ENV{RUNNER_NAME}         // 'local',
        label         => $ENV{GPFORUM_PERF_RUNNER} // 'local',
        image         => $ENV{ImageOS}             // $os,
        image_version => $ENV{ImageVersion}
    };
}

sub _fingerprints {
    my $root = root_dir();
    my @paths =
      qw(script/performance-evidence script/performance-http script/performance-hotpaths script/performance-outbox.pl benchmarks/hypnotoad-app.pl benchmarks/wrk-metrics.lua t/lib/GPForum/Test/PostgresHarness.pm t/lib/GPForum/Test/OutboxTransport.pm);
    my $modules = File::Spec->catdir( $root, 'script/lib/GPForum/Performance' );
    if ( -d $modules ) {
        find(
            {
                no_chdir => 1,
                wanted   => sub {
                    if ( -f $File::Find::name
                        && $File::Find::name =~ /[.]pm\z/msx )
                    {
                        push @paths,
                          File::Spec->abs2rel( $File::Find::name, $root );
                    }
                }
            },
            $modules
        );
    }
    return {
        map  { $_ => sha256_hex( _bytes( File::Spec->catfile( $root, $_ ) ) ) }
        grep { -f File::Spec->catfile( $root, $_ ) } @paths
    };
}

sub initial ( $mode, $commit = undef ) {
    my $now        = time;
    my $whole      = int $now;
    my $micros     = ( $now - $whole ) * MICROSECONDS;
    my $date       = strftime( '%Y-%m-%d', gmtime $now );
    my $fraction   = sprintf '.%06d+00:00', $micros;
    my $timestamp  = strftime( '%Y-%m-%dT%H:%M:%S', gmtime $now ) . $fraction;
    my $repository = $ENV{GITHUB_REPOSITORY} // 'gpicchiarelli/GPForum';
    my $entropy    = join q{-}, $now, $PROCESS_ID, rand;
    my $digest     = sha256_hex($entropy);
    my $local_id   = 'local-' . substr $digest, 0, ID_LENGTH;
    return {
        schema_version => 1,
        kind           => 'metadata',
        commit         => $commit // command( [ 'git', 'rev-parse', 'HEAD' ] )
          // ( '0' x COMMIT_LENGTH ),
        date        => $date,
        timestamp   => $timestamp,
        mode        => $mode,
        run_id      => $ENV{GITHUB_RUN_ID}      // $local_id,
        run_attempt => $ENV{GITHUB_RUN_ATTEMPT} // '1',
        dirty       =>
          command( [ 'git', 'status', '--porcelain', '--untracked-files=no' ] )
        ? JSON::PP::true
        : JSON::PP::false,
        working_tree_diff_sha256 => sha256_hex(
            command(
                [
                    'git',
                    'diff',
                    'HEAD',
                    q{--},
                    qw(lib templates assets migrations cpanfile cpanfile.snapshot deploy)
                ]
            ) // q{}
        ),
        runner        => _runner(),
        versions      => {},
        dataset       => {},
        configuration => { harness_sha256 => _fingerprints() },
        artifact_url  => $ENV{GPFORUM_PERF_ARTIFACT_URL} // q{},
        history_url   =>
          "https://github.com/$repository/tree/main/benchmarks/results",
        run_url => $ENV{GITHUB_RUN_ID}
        ? ( $ENV{GITHUB_SERVER_URL} // 'https://github.com' )
          . "/$repository/actions/runs/$ENV{GITHUB_RUN_ID}"
        : q{},
        limitations => [
'Shared runners and a colocated load generator give comparative CI evidence, not production capacity.'
        ]
    };
}

sub compatible_signature ($metadata) {
    my $runner = $metadata->{runner} // {};
    my $gib    = ( $runner->{memory_bytes} // 0 ) / GIB;

    # Same nearest-integer memory class as the original harness.
    my $memory = int( $gib + ROUND_HALF );
    my $value  = {
        runner => {
            map { $_ => $runner->{$_} }
              qw(os arch label image cpu_count cpu_model)
        },
        memory_gib     => $memory,
        versions       => $metadata->{versions}      // {},
        dataset        => $metadata->{dataset}       // {},
        configuration  => $metadata->{configuration} // {},
        mode           => $metadata->{mode},
        schema_version => 1
    };
    my $json = JSON::PP->new->canonical->ascii;
    return sha256_hex( $json->encode($value) );
}
1;
