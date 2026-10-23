# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause
package GPForum::Performance::HTTPReport;
use v5.40;
use utf8;
use Exporter   qw(import);
use Mojo::File qw(path);
use Mojo::Util qw(xml_escape encode);
our $VERSION   = '0.001';
our @EXPORT_OK = qw(write_report);

sub _value ($value) {
    return defined $value ? sprintf( '%.2f', $value ) : '—';
}

sub _metrics ($metrics) {
    return join q{},
      map { '<td>' . _value($_) . '</td>' } $metrics->{requests},
      $metrics->{latency}{p50_ms},   $metrics->{latency}{p95_ms},
      $metrics->{latency}{p99_ms},   $metrics->{server_app}{p50_ms},
      $metrics->{server_db}{p50_ms}, $metrics->{outside_app}{p50_ms},
      $metrics->{invalid_responses};
}

sub _table ($rows) {
    return
'<div class="scroll"><table><thead><tr><th>Operation / cell</th><th>N</th><th>p50 ms</th><th>p95 ms</th><th>p99 ms</th><th>App p50</th><th>DB p50</th><th>Outside app p50</th><th>Invalid</th></tr></thead><tbody>'
      . join( q{}, @{$rows} )
      . '</tbody></table></div>';
}

sub write_report ( $directory, $report ) {
    my $coverage   = $report->{coverage};
    my @operations = map {
        '<tr><th>' . xml_escape( $_->{name} ) . '</th>' . _metrics($_) . '</tr>'
      }
      reverse
      sort { ( $a->{latency}{p95_ms} // 0 ) <=> ( $b->{latency}{p95_ms} // 0 ) }
      @{ $report->{operations} };
    my @cells = map {
        '<tr><th>'
          . xml_escape(
            "$_->{scenario} · c=$_->{clients} · rep=$_->{repetition}")
          . '<br><small>'
          . _value( $_->{metrics}{requests_per_second} )
          . ' req/s · '
          . xml_escape( $_->{status} )
          . '</small></th>'
          . _metrics( $_->{metrics} ) . '</tr>'
    } @{ $report->{cells} };
    my $html =
'<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>GPForum full HTTP benchmark</title><style>body{font:15px system-ui,sans-serif;margin:32px;color:#203041;background:#f6f8fa}main{max-width:1500px;margin:auto}h1{font-size:30px}p{max-width:1050px;line-height:1.6}table{border-collapse:collapse;background:white;width:100%}th,td{padding:9px 12px;border-bottom:1px solid #dce3e8;text-align:right;white-space:nowrap}th:first-child{text-align:left}thead{background:#173e56;color:white}.scroll{overflow:auto}small{font-weight:normal;color:#526879}summary{cursor:pointer}li{line-height:1.6}</style><main><h1>GPForum · complete HTTP benchmark</h1><p>Status: <b>'
      . xml_escape( $report->{status} )
      . '</b> · '
      . scalar( @{ $report->{cells} } )
      . ' cells · '
      . "$coverage->{observed}/$coverage->{total}"
      . ' named routes observed · '
      . _value( $report->{duration_seconds} )
      . ' s including setup.</p><p>'
      . xml_escape( $report->{generator} )
      . '</p><p>'
      . xml_escape( $report->{policy} )
      . '</p><p>Percentiles use individual requests. Operation rows combine concurrency levels and repetitions; use the cell table for capacity comparisons. Fewer than 20 samples are flagged in JSON; short samples cannot establish tail latency. App/DB come from Server-Timing; outside app includes client, transport and waiting. Percentiles of components do not add up to the percentile of total latency.</p><p><a href="http-complete.json">Raw JSON, configuration, database settings and correctness checks</a></p><h2>Operations sorted by p95</h2>'
      . _table( \@operations )
      . '<h2>Cells</h2>'
      . _table( \@cells )
      . '<details><summary>Unmeasured named routes ('
      . scalar( @{ $coverage->{missing} } )
      . ')</summary><ul>'
      . join( q{},
        map { '<li>' . xml_escape($_) . '</li>' } @{ $coverage->{missing} } )
      . '</ul></details><h2>Failures</h2><ul>'
      . join( q{},
        map { '<li>' . xml_escape($_) . '</li>' } @{ $report->{failures} } )
      . '</ul></main></html>';
    path("$directory/report.html")->spurt( encode( 'UTF-8', $html ) );
    return undef;
}
1;
