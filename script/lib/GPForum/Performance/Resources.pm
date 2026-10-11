# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause
package GPForum::Performance::Resources;
use v5.40;
use Carp    qw(croak);
use English qw(-no_match_vars);
our $VERSION = '0.001';
use List::Util                    qw(min max sum);
use POSIX                         qw(sysconf _SC_CLK_TCK);
use GPForum::Performance::Support qw(redact);
use GPForum::Performance::HTTP    qw(process_snapshot cpu_count nofile_soft);

# Core constants keep metrics available before application dependencies load.
use constant {    ## no critic (ValuesAndExpressions::ProhibitConstantPragma)
    USER_TICKS     =>  11,
    SYSTEM_TICKS   =>  12,
    KIBIBYTE       => 1_024,
    CPU_LAST_FIELD =>  7,
    IDLE_FIELD     =>  3,
    IOWAIT_FIELD   =>  4,
    STEAL_FIELD    =>  7,
    LAST_SAMPLE    => -1,
    PERCENT        =>  100,
};

sub _read ($path) {
    open my $fh, '<', $path or croak "Cannot read process observation: $ERRNO";
    local $INPUT_RECORD_SEPARATOR = undef;
    my $text = <$fh>;
    close $fh or croak "Cannot close process observation: $ERRNO";
    return $text;
}

sub process ($pid) {
    my $value;
    try {
        my $directory = "/proc/$pid";
        my $text      = _read("$directory/stat");
        $text =~ s/\A.*[)]\s*//smx;
        my @fields = split /\s+/msx, $text;
        my $status = _read("$directory/status");
        my ($rss)  = $status =~ /^VmRSS:\s+(\d+)[ ]kB/msx;
        opendir my $fds, "$directory/fd"
          or croak 'Cannot read process descriptors';
        my @fds = grep { $_ ne q{.} && $_ ne q{..} } readdir $fds;
        closedir $fds or croak 'Cannot close process descriptors';
        $value = {
            ticks     => $fields[USER_TICKS] + $fields[SYSTEM_TICKS],
            rss_bytes => defined($rss) ? $rss * KIBIBYTE : undef,
            fds       => scalar @fds
        }
    }
    catch ($error) { $value = undef };
    return $value;
}

sub host {
    my $value;
    try {
        my ($line) = split /\n/msx, _read('/proc/stat');
        my @cpu = split /\s+/msx, $line;
        shift @cpu;
        @cpu = @cpu[ 0 .. CPU_LAST_FIELD ];
        my $memory      = _read('/proc/meminfo');
        my ($total)     = $memory =~ /^MemTotal:\s+(\d+)/msx;
        my ($available) = $memory =~ /^MemAvailable:\s+(\d+)/msx;
        if ( !( $total && defined $available ) ) {
            croak 'Missing host memory observation';
        }
        $value = {
            cpu_ticks                 => sum(@cpu),
            idle_ticks                => $cpu[IDLE_FIELD] + $cpu[IOWAIT_FIELD],
            steal_ticks               => $cpu[STEAL_FIELD],
            memory_bytes              => $total * KIBIBYTE,
            memory_available_fraction => $available / $total
        }
    }
    catch ($error) { $value = undef };
    return $value;
}

sub new ( $class, $args ) {
    return bless { $args->%*, samples => [], last_pg => -1e99 }, $class;
}

sub sample ( $self, $pid, $elapsed ) {
    my $snapshot = process_snapshot( $self->{server}{master} );
    my %members;
    for my $member ( $self->{server}{master}, @{ $snapshot->{worker_pids} } ) {
        my $data = process($member);
        if ($data) { $members{$member} = $data; }
    }
    my $row = {
        elapsed_seconds => $elapsed,
        generator       => process($pid),
        server          => \%members,
        host            => host()
    };
    if ( $self->{pg_sampler} && $elapsed - $self->{last_pg} >= 2 ) {
        $self->{last_pg} = $elapsed;
        try { $row->{postgres} = $self->{pg_sampler}->() } catch ($error) {
            $row->{postgres_error} = redact($error)
        };
    }
    push @{ $self->{samples} }, $row;
    return undef;
}

sub _cpu ( $samples, $component ) {
    my @valid = grep {
        $_->{$component}
          && ( $component ne 'server' || keys %{ $_->{$component} } )
    } $samples->@*;
    if ( !( @valid >= 2 ) ) { return ( undef, undef ); }
    my ( $first, $final ) = @valid[ 0, LAST_SAMPLE ];
    my $span = $final->{elapsed_seconds} - $first->{elapsed_seconds};
    if ( !( $span > 0 ) ) { return ( undef, undef ); }
    my $ticks;
    if ( $component eq 'server' ) {
        my $initial_members = join q{,}, sort keys %{ $first->{$component} };
        my $final_members   = join q{,}, sort keys %{ $final->{$component} };
        if ( $initial_members ne $final_members ) {
            return ( undef, undef );
        }
        $ticks = sum(
            map {
                $final->{$component}{$_}{ticks} -
                  $first->{$component}{$_}{ticks}
            } keys %{ $first->{$component} }
        );
    }
    else { $ticks = $final->{$component}{ticks} - $first->{$component}{ticks} }
    return ( max( 0, PERCENT * $ticks / sysconf(_SC_CLK_TCK) / $span ), $span );
}

sub summary ($self) {
    my ( $generator_cpu, $generator_span ) =
      _cpu( $self->{samples}, 'generator' );
    my ( $server_cpu, $server_span ) = _cpu( $self->{samples}, 'server' );
    my @generators =
      map { $_->{generator} } grep { $_->{generator} } @{ $self->{samples} };
    my @hosts = map { $_->{host} } grep { $_->{host} } @{ $self->{samples} };
    my @server_rss = map {
        sum( map { $_->{rss_bytes} // 0 } values %{ $_->{server} } )
          // 0
    } grep { keys %{ $_->{server} } } @{ $self->{samples} };
    my ( $busy, $steal );
    if ( @hosts >= 2 ) {
        my $span = $hosts[LAST_SAMPLE]{cpu_ticks} - $hosts[0]{cpu_ticks};
        if ( $span > 0 ) {
            $busy =
              PERCENT *
              ( 1 -
                  ( $hosts[LAST_SAMPLE]{idle_ticks} - $hosts[0]{idle_ticks} ) /
                  $span );
            $steal =
              PERCENT *
              ( $hosts[LAST_SAMPLE]{steal_ticks} - $hosts[0]{steal_ticks} ) /
              $span;
        }
    }
    return {
        generator_cpu_percent      => $generator_cpu,
        generator_cpu_span_seconds => $generator_span,
        server_cpu_percent         => $server_cpu,
        server_cpu_span_seconds    => $server_span,
        generator_rss_peak_bytes   => @generators
        ? max( map { $_->{rss_bytes} // 0 } @generators )
        : undef,
        generator_fd_peak => @generators ? max( map { $_->{fds} } @generators )
        : undef,
        server_rss_peak_bytes      => @server_rss ? max(@server_rss) : undef,
        server_fd_peak_per_process => max(
            map {
                map { $_->{fds} }
                  values %{ $_->{server} }
            } @{ $self->{samples} }
        ),
        host_busy_percent         => $busy,
        host_steal_percent        => $steal,
        memory_available_fraction => @hosts
        ? min( map { $_->{memory_available_fraction} } @hosts )
        : undef,
        memory_bytes      => @hosts ? $hosts[LAST_SAMPLE]{memory_bytes} : undef,
        cpu_count         => cpu_count(),
        nofile_soft       => nofile_soft(),
        generator_threads => $self->{threads},
        source            =>
'Linux /proc alive samples; CPU excludes unsampled final tail; RSS/FD observed sample peaks'
    };
}
1;
