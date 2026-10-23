# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Performance::Operations;

use v5.40;
use Carp qw(croak);
use Const::Fast;
use English  qw(-no_match_vars);
use Exporter qw(import);
use File::Spec;
use JSON::MaybeXS qw(decode_json);
use List::Util    qw(sum0 max any);
use POSIX         qw(ceil);
use GPForum::Bootstrap::Routes;
use GPForum::Infrastructure::SqlFunctionCatalogue;
use Mojolicious;

our $VERSION   = '0.001';
our @EXPORT_OK = qw(summarize inventory);
const my $P50             => .50;
const my $P95             => .95;
const my $P99             => .99;
const my $MINIMUM_SAMPLES => 20;

sub inventory {
    my $app = Mojolicious->new;
    GPForum::Bootstrap::Routes->register( application => $app );
    my @routes;
    my $visit;
    $visit = sub ($parent) {
        for my $route ( @{ $parent->children } ) {
            if ( $route->name ) { push @routes, $route->name; }
            $visit->($route);
        }
        return undef;
    };
    $visit->( $app->routes );
    return {
        http => [ sort @routes ],
        sql  => GPForum::Infrastructure::SqlFunctionCatalogue->new->names,
    };
}

sub _distribution ($values) {
    my @sorted = sort { $a <=> $b } @{$values};
    return undef if !@sorted;
    return {
        count    => scalar @sorted,
        total_ms => sum0(@sorted),
        mean_ms  => sum0(@sorted) / @sorted,
        p50_ms   => $sorted[ ceil( @sorted * $P50 ) - 1 ],
        p95_ms   => $sorted[ ceil( @sorted * $P95 ) - 1 ],
        p99_ms   => $sorted[ ceil( @sorted * $P99 ) - 1 ],
        max_ms   => $sorted[-1],
    };
}

sub summarize ( $directory, $catalogue = undef ) {
    $catalogue //= inventory();
    opendir my $dir, $directory or croak "Cannot read traces: $OS_ERROR";
    my @files =
      sort grep { /\Asamples-[[:digit:]]+[.]jsonl\z/msx } readdir $dir;
    closedir $dir or croak "Cannot close traces: $OS_ERROR";
    my ( %groups, %seen, %successful );
    for my $file (@files) {
        open my $input, '<:raw', File::Spec->catfile( $directory, $file )    ## no critic (InputOutput::RequireBriefOpen) -- stream potentially large traces instead of retaining raw samples twice
          or croak "Cannot read trace: $OS_ERROR";
        while ( my $line = <$input> ) {
            my $row = decode_json($line);
            $row->{operation} //= 'uncatalogued';
            _append( \%groups, $row );
            $seen{ $row->{kind} }{ $row->{operation} } = 1;
            if ( _successful($row) ) {
                $successful{ $row->{kind} }{ $row->{operation} } = 1;
            }
        }
        close $input or croak "Cannot close trace: $OS_ERROR";
    }
    my $measurements = _measurements( \%groups );
    my %coverage;
    for my $kind ( sort keys %{$catalogue} ) {
        my @expected = @{ $catalogue->{$kind} };
        $coverage{$kind} = {
            total      => scalar @expected,
            observed   => scalar( grep { $seen{$kind}{$_} } @expected ),
            successful => scalar( grep { $successful{$kind}{$_} } @expected ),
            missing    => [ grep { !$seen{$kind}{$_} } @expected ],
            without_success => [ grep { !$successful{$kind}{$_} } @expected ],
        };
    }
    return {
        schema_version  => 1,
        measurements    => $measurements,
        coverage        => \%coverage,
        coverage_status => ( any { @{ $_->{missing} } } values %coverage )
        ? 'partial'
        : 'complete',
        trace_files => scalar @files,
        scope       =>
'Integration workflows on isolated PostgreSQL; diagnostic timings, not a load baseline',
        timing =>
'SQL boundary includes DBI and transport; HTTP is application dispatch, excluding client/network. SQL trace writes add diagnostic overhead to HTTP time. First sample is per process, operation and outcome; subsequent does not guarantee a warm cache.',
        outcomes =>
'SQL returned means no exception, not domain success; HTTP redirects and errors have separate distributions. Test assertions determine workflow correctness.',
    };
}

sub _measurements ($groups) {
    my @measurements;
    for my $key ( sort keys %{$groups} ) {
        my $group   = $groups->{$key};
        my $samples = delete $group->{samples};
        my $db      = delete $group->{db};
        my $queries = delete $group->{queries};
        $group->{tests}   = [ sort keys %{ $group->{tests} } ];
        $group->{latency} = _distribution($samples);
        $group->{db}      = _distribution($db);
        $group->{non_db}  = _distribution( delete $group->{non_db} );
        my $counts = _distribution($queries);
        $group->{queries} =
          $counts
          ? { mean => $counts->{mean_ms}, max => $counts->{max_ms} }
          : undef;
        $group->{low_sample_count} = @{$samples} < $MINIMUM_SAMPLES ? 1 : 0;
        push @measurements, $group;
    }
    return \@measurements;
}

sub _append ( $groups, $row ) {
    my $key   = join q{:}, @{$row}{qw(kind operation outcome phase)};
    my $group = $groups->{$key} //= {
        ( map { $_ => $row->{$_} } qw(kind operation outcome phase) ),
        samples => [],
        db      => [],
        non_db  => [],
        queries => [],
        tests   => {},
    };
    push @{ $group->{samples} }, $row->{elapsed_ms};
    if ( defined $row->{db_ms} ) { push @{ $group->{db} }, $row->{db_ms}; }
    if ( defined $row->{db_ms} ) {
        push @{ $group->{non_db} },
          max( 0, $row->{elapsed_ms} - $row->{db_ms} );
    }
    if ( defined $row->{queries} ) {
        push @{ $group->{queries} }, $row->{queries};
    }
    $group->{tests}{ $row->{test} } = 1;
    if (  !$group->{slowest}
        || $row->{elapsed_ms} > $group->{slowest}{elapsed_ms} )
    {
        $group->{slowest} =
          { map { $_ => $row->{$_} } qw(test elapsed_ms db_ms queries rows) };
    }
    return undef;
}

sub _successful ($row) {
    return $row->{kind} eq 'sql'
      ? $row->{outcome} eq 'returned'
      : $row->{outcome} =~ /\A2[[:digit:]]{2}\z/msx;
}

1;
