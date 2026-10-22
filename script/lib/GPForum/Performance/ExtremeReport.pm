# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Performance::ExtremeReport;

use v5.40;
use utf8;
use Carp    qw(croak);
use English qw(-no_match_vars);
use File::Spec;
use JSON::PP;

# The artifact renderer loads before CPAN setup as well.
use constant MEBIBYTE => 1_048_576;    ## no critic (ValuesAndExpressions::ProhibitConstantPragma)

our $VERSION = '0.001';

sub _cell ($value) {
    $value //= 'unknown';
    $value =~ s/[|]/\\|/gmsx;
    $value =~ s/\n/ /gmsx;
    return $value;
}

sub _number ($value) {
    return defined $value ? sprintf( '%.2f', $value ) : 'unknown';
}

sub _json ($value) {
    return _cell( JSON::PP->new->canonical->encode($value) );
}

sub _row ($row) {
    my $metric = $row->{metrics};
    my $rss    = $metric->{rss_peak_bytes} // $metric->{rss_bytes};
    my @values = (
        "$row->{phase}/$row->{scenario} #$row->{repetition} ($row->{status})",
        "$row->{concurrency} / " . _number( $metric->{concurrency_effective} ),
        _number( $metric->{requests_per_second} ),
        join(
            ' / ', map { _number( $metric->{$_} ) } qw(p50_ms p95_ms p99_ms)
        ),
        join( ' / ',
            map { _number( $metric->{$_} ) }
              qw(http_errors transport_errors timeouts) ),
        _number( $metric->{cpu_percent} ) . ' / '
          . _number( defined $rss ? $rss / MEBIBYTE : undef ),
        _number( $metric->{generator_cpu_percent} ),
        $row->{classification},
    );
    return '| ' . join( ' | ', map { _cell($_) } @values ) . ' |';
}

sub write_report ( $output, $state ) {
    my $details =
      $state->{run_url}
      ? "[artifact and job details]($state->{run_url})"
      : 'local diagnostics beside this report';
    my @lines = (
        '# GPForum weekly extreme performance',
        q{},
"Commit: `$state->{commit}` · profile: **$state->{profile}** · status: **$state->{status}**",
        "Run $state->{run_id}, attempt $state->{run_attempt} · $details",
        q{},
        'Runner: ' . _json( $state->{runner} ),
        q{},
        'Versions: ' . _json( $state->{versions} ),
        q{},
        'Dataset: ' . _json( $state->{dataset} ),
        q{},
        'Configuration: ' . _json( $state->{configuration} ),
        q{},
        sprintf(
'Elapsed job clock %.1fs; maximum 1800s, report/cleanup reserve 240s; source %s.',
            $state->{budget}{elapsed_seconds},
            $state->{budget}{clock_source}
        ),
        q{},
        '| Phase | State | Reason |',
        '| --- | --- | --- |',
    );
    for my $phase (qw(setup progressive mixed soak spike recovery cleanup)) {
        my $value = $state->{phases}{$phase};
        push @lines,
          "| $phase | $value->{status} | " . _cell( $value->{reason} ) . ' |';
    }
    push @lines, q{},
'| Phase/scenario | Connections requested/effective | RPS | p50/p95/p99 ms | HTTP/transport/timeout errors | Server CPU/peak RSS MiB | Generator CPU | Classification |',
      '| --- | --- | --- | --- | --- | --- | --- | --- |';
    push @lines, map { _row($_) } @{ $state->{measurements} };
    push @lines, q{}, 'Observed stops: ' . _json( $state->{saturation} // [] ),
      q{},
      'Soak trend: ' . _json( $state->{soak_trend} ), q{},
      'Recovery: ' . _json( $state->{phases}{recovery} ), q{},
      'Skipped coverage and cells:', q{};
    push @lines, map { '- ' . _json($_) } @{ $state->{skipped} };
    push @lines, q{}, 'Limitations:', q{},
      map { '- ' . _cell($_) } @{ $state->{limitations} };
    push @lines, q{}, 'Conclusion: ' . $state->{conclusion}, q{};
    my $path = File::Spec->catfile( $output, 'report.md' );
    open my $handle, '>:encoding(UTF-8)', $path
      or croak "Cannot write report: $OS_ERROR";
    print {$handle} join "\n", @lines
      or croak "Cannot write report: $OS_ERROR";
    close $handle or croak "Cannot close report: $OS_ERROR";
    return $path;
}

1;
