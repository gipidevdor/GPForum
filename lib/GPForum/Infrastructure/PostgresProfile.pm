# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Infrastructure::PostgresProfile;

use Mojo::Base 'GPForum::Base', -signatures;
use v5.40;
use List::Util qw(min max);
use Const::Fast;
use GPForum::OS;
use GPForum::OS::Memory;
use GPForum::Runtime;

our $VERSION = '0.001';
__PACKAGE__->requires('config');

const my $MIB                      => 1_048_576;
const my $MINIMUM_BUDGET_MB        => 512;
const my $OS_RESERVE_DIVISOR       => 16;
const my $MAX_CONNECTIONS          => 100;
const my $MIN_CONNECTIONS          => 20;
const my $CONNECTIONS_PER_CPU      => 16;
const my $READINESS_HEADROOM       => 16;
const my $CONNECTION_HEADROOM      => 20;
const my $BUFFER_DIVISOR           => 4;
const my $DEDICATED_MAINTENANCE_MB => 512;
const my $SHARED_MAINTENANCE_MB    => 128;
const my $MAINTENANCE_DIVISOR      => 32;
const my $DEDICATED_WORK_MB        => 8;
const my $SHARED_WORK_MB           => 4;
const my $MAINTENANCE_ALLOCATIONS  => 4;
const my $BACKEND_MB               => 10;
const my $WORK_ALLOCATIONS         => 8;
const my $CACHE_NUMERATOR          => 3;

sub _hardware ($self) {
    my $c      = $self->config;
    my $local  = $c->postgres_topology eq 'local';
    my $os     = GPForum::OS->detect;
    my $memory = $c->postgres_memory_mb;
    my $source = 'operator';
    if ( !$memory && $local ) {
        my $detected = GPForum::OS::Memory->new->detect( $os->name );
        $memory = int( ( $detected->{bytes} // 0 ) / $MIB );
        $source = $detected->{source};
    }
    return ( $memory, $source,
        $c->postgres_cpu_count || ( $local ? $os->cpu_count : 0 ) );
}

sub _memory_budget ( $c, $memory ) {
    my $dedicated = $c->postgres_profile eq 'dedicated';
    my $reserve   = $c->postgres_reserve_mb
      || (
        $dedicated
        ? max( $MINIMUM_BUDGET_MB, int( $memory / $OS_RESERVE_DIVISOR ) )
        : int( $memory / 2 )
      );
    my $budget  = max( 0, $memory - $reserve );
    my $buffers = int( ( $dedicated ? $memory : $budget ) / $BUFFER_DIVISOR );
    my $maintenance = min(
        $dedicated ? $DEDICATED_MAINTENANCE_MB : $SHARED_MAINTENANCE_MB,
        int( ( $dedicated ? $memory : $budget ) / $MAINTENANCE_DIVISOR )
    );
    return {
        dedicated   => $dedicated,
        reserve     => $reserve,
        budget      => $budget,
        buffers     => $buffers,
        maintenance => $maintenance
    };
}

sub _allocations ( $c, $memory, $cores ) {
    my $a = _memory_budget( $c, $memory );
    my ( $dedicated, $budget, $buffers, $maintenance ) =
      @{$a}{qw(dedicated budget buffers maintenance)};
    my $web_workers =
      GPForum::Runtime->from_config($c)->effective_web_processes;
    my $connections = min(
        $MAX_CONNECTIONS,
        max(
            $MIN_CONNECTIONS,
            $cores * $CONNECTIONS_PER_CPU,
            2 * $web_workers + $CONNECTION_HEADROOM
        )
    );
    my $work = min(
        $dedicated ? $DEDICATED_WORK_MB : $SHARED_WORK_MB,
        int(
            (
                $budget - $buffers -
                  $MAINTENANCE_ALLOCATIONS * $maintenance -
                  $BACKEND_MB * $connections
            ) / ( $WORK_ALLOCATIONS * $connections )
        )
    );
    my $sufficient = $budget >= $MINIMUM_BUDGET_MB && $work >= 1;
    my $valid = $memory && $cores && $sufficient;
    return {
        %{$a},
        work                 => $work,
        connections          => $connections,
        valid                => $valid,
        required_connections => 2 * $web_workers + $READINESS_HEADROOM,
        sufficient_memory    => $sufficient ? 1 : 0,
    };
}

sub _settings ( $c, $memory, $a ) {
    my ( $dedicated, $budget, $buffers, $maintenance, $work, $connections,
        $valid )
      = @{$a}{qw(dedicated budget buffers maintenance work connections valid)};
    my $ssd = $c->postgres_storage eq 'ssd' || $c->postgres_storage eq 'nvme';
    my %settings =
      $valid
      ? (
        shared_buffers       => "${buffers}MB",
        effective_cache_size => int(
            ( $dedicated ? $memory : $budget ) *
              $CACHE_NUMERATOR /
              $BUFFER_DIVISOR
          )
          . 'MB',
        work_mem                 => "${work}MB",
        maintenance_work_mem     => "${maintenance}MB",
        random_page_cost         => $ssd ? '1.1' : '4',
        effective_io_concurrency => $ssd ? '100' : '2',
        jit                      => 'off',
        max_connections          => "$connections",
        track_io_timing          => 'on',
      )
      : ();
    return \%settings;
}

# Admission estimate, not a PostgreSQL memory limit. Multiple sort/hash nodes,
# parallel workers and three autovacuum workers have explicit allowances.
sub recommendation ($self) {
    my $c = $self->config;
    my ( $memory, $source, $cores ) = $self->_hardware;
    my @issues;
    if ( !$memory || !$cores ) {
        push @issues,
'Declare database RAM and CPU cores; application host resources are not database resources';
    }
    if ( $c->postgres_storage eq 'unknown' ) {
        push @issues,
          'Declare database storage class before applying a profile';
    }
    my $a = _allocations( $c, $memory, $cores );
    my ( $valid, $reserve, $budget, $buffers, $maintenance, $connections,
        $work )
      = @{$a}{qw(valid reserve budget buffers maintenance connections work)};
    if ( $memory && !$a->{sufficient_memory} ) {
        push @issues,
'Insufficient memory after reserves and concurrent query/maintenance allowances';
    }
    return {
        name                 => $c->postgres_profile,
        version              => 1,
        valid                => $valid ? 1 : 0,
        memory_mb            => $memory,
        memory_source        => $source,
        reserve_mb           => $reserve,
        budget_mb            => $budget,
        required_connections => $a->{required_connections},
        sufficient_memory    => $a->{sufficient_memory},
        cpu_count            => $cores,
        storage              => $c->postgres_storage,
        estimated_memory_mb  => $valid
        ? $buffers + $MAINTENANCE_ALLOCATIONS * $maintenance +
          $connections * ( $BACKEND_MB + $WORK_ALLOCATIONS * $work )
        : undef,
        settings    => _settings( $c, $memory, $a ),
        issues      => \@issues,
        assumptions =>
'8 work_mem allocations and 10 MiB backend overhead per connection; 4 maintenance allocations. Measure real concurrency, parallelism and RSS.',
    };
}

1;

__END__

=head1 NAME

GPForum::Infrastructure::PostgresProfile - Size an explicit PostgreSQL profile.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $profile = GPForum::Infrastructure::PostgresProfile->new(config => $config)->recommendation;

=head1 DESCRIPTION

Uses declared database hardware or explicitly local OS/cgroup probes. Reserves memory for other processes and budgets concurrent work and maintenance allocations. Never connects to or modifies PostgreSQL.

=head1 SUBROUTINES/METHODS

recommendation returns settings, memory budget, resource provenance and sizing issues.

=head1 DIAGNOSTICS

Failures name missing evidence, nonconforming settings or refused authorization.

=head1 CONFIGURATION AND ENVIRONMENT

Receives PostgreSQL settings through L<GPForum::Config>.

=head1 DEPENDENCIES

Uses the existing GPForum configuration, OS and database infrastructure.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Resource estimates require an operator budget; measurements remain necessary.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. BSD-3-Clause.

=cut
