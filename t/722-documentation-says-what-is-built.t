# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Mojo::File qw(path);
use Test::More;

our $VERSION = '0.001';

# The documents a reader starts from describe the code as it is. A review of
# main on 2026-10-15 found them describing an earlier tree: services reaching
# PostgreSQL through DBIx::Class after ADR 0126 moved the statements into
# functions. Each subtest pins one such statement to what is built.

subtest 'the architecture says statements are calls to api functions' => sub {
    my $architecture = path('ARCHITECTURE.md')->slurp;
    like(
        $architecture,
        qr/GPForum::Infrastructure::SqlFunction/msx,
        'the map names the call layer'
    );
    like( $architecture, qr/ADR [ ] 0126/msx, 'and the decision behind it' );
    unlike(
        $architecture,
        qr/services [ ] read [ ] and [ ] write [ ] through \s+ DBIx::Class/msx,
        'and no longer routes the services through DBIx::Class'
    );
    unlike(
        $architecture,
        qr/Queries [ ] --> [ ] DBIx/msx,
        'nor draws the readers on it'
    );

    my $database = _status('docs/adr/0051-database-architecture.md');
    like(
        $database,
        qr/ADR [ ] 0126/msx,
        'ADR 0051 says ADR 0126 amends its mandatory ORM'
    );

    my $layers =
      path('docs/adr/0107-layers-are-the-namespaces-that-exist.md')->slurp;
    unlike(
        $layers,
        qr/Services [ ] read [ ] and \s+ write [ ] through [ ] DBIx::Class/msx,
        'ADR 0107 does not route the services through DBIx::Class'
    );
};

subtest 'an accepted decision says which of its capabilities are unbuilt' =>
  sub {
    for my $number (
        qw(0049 0050 0053 0058 0060 0068 0075 0077 0078 0085 0091 0093 0095 0097)
      )
    {
        my ($file) = glob "docs/adr/$number-*.md";
        like(
            _status($file),
            qr/a \s+ target, \s+ not \s+ current \s+ state/msx,
            "ADR $number marks its unbuilt capabilities as a target"
        );
    }
  };

subtest 'no guide states a count that the next migration makes wrong' => sub {
    unlike(
        path('README.md')->slurp,
        qr/\d+ \s+ versioned \s+ PostgreSQL \s+ functions/msx,
        'the README does not count the functions'
    );
    unlike(
        path('docs/DEPLOYMENT.md')->slurp,
        qr/Applied \s+ \d+ \s+ migrations/msx,
        'the deployment guide does not count the migrations'
    );
    unlike(
        path('docs/QUALITY_PROGRAM.md')->slurp,
        qr/all \s+ [\d,]+ \s+ (?:Perl \s+ )? (?:modules|files)/msx,
        'the quality program does not count the modules'
    );
};

subtest 'the quality program states what is open, not a score' => sub {
    my $program = path('docs/QUALITY_PROGRAM.md')->slurp;
    unlike(
        $program,
        qr{Now: \s+ [*]{2} [\d.]+ \s+ / \s+ 10}msx,
        'it keeps no current self-score'
    );
    like(
        $program,
        qr/review \s+ of \s+ .main. \s+ on \s+ 2026-10-15/msx,
        'and points at the review that found the open defects'
    );
};

subtest 'the operator actions name what the tree has' => sub {
    my ( undef, $unreleased ) = split /^[#]{2} [ ] Unreleased \n/msx,
      path('CHANGELOG.md')->slurp, 2;
    my ( $summary, $actions ) =
      split /^[#]{3} [ ] Operator [ ] action [ ] required \n/msx,
      $unreleased // q{}, 2;
    ($actions) = split /^[#]{3} [ ]/msx, $actions // q{}, 2;
    like( $summary, qr/\S/msx, 'Unreleased opens with a summary' );

    my %gone = (
        'old environment names that start' => qr/until \s+ v0[.]3[.]0/msx,
        'the old bootstrap command'      => qr/bin\/gpforum-admin-bootstrap/msx,
        'script/antivirus-check'         => qr/script\/antivirus-check/msx,
        'the old scheduled-jobs command' => qr/bin\/gpforum-scheduled-jobs/msx,
        'the unix-socket unit to re-copy' =>
          qr/Re-copy \s+ `deploy\/systemd\/gpforum-unix-socket/msx,
        'MacPorts clamav'                    => qr/MacPorts \s+ `clamav`/msx,
        'a GlifiStore that production needs' =>
          qr/GlifiStore \s+ the \s+ required/msx,
        'script/os-preflight' => qr/`script\/os-preflight`/msx,
    );
    for my $name ( sort keys %gone ) {
        unlike( $actions // q{}, $gone{$name}, "no $name" );
    }
};

subtest 'every relative link in the documents resolves' => sub {
    my @documents =
      grep { -e }
      map  { path($_) }
      qw(README.md ARCHITECTURE.md CHANGELOG.md CONTRIBUTING.md SECURITY.md);
    push @documents,
      path('docs')->list_tree->grep( sub { $_->basename =~ /[.]md\z/msx } )
      ->each;
    my @broken;
    for my $document (@documents) {
        my $text = $document->slurp;
        $text =~ s/^```.*?^```//gmsx;
        $text =~ s/`[^`\n]*`//gmsx;
        for my $target ( $text =~ /[]][(]([^)\s]+)[^)]*[)]/gmsx ) {
            next if $target =~ /\A (?:[[:alpha:]][\w+.-]*: | [#]) /msx;
            ( my $file = $target ) =~ s/[#?].*\z//msx;
            next if $file eq q{};
            next if -e $document->dirname->child($file);
            push @broken, "$document -> $target";
        }
    }
    is_deeply( \@broken, [], 'no link names a file that is not there' );
};

done_testing();

sub _status ($file) {
    my ( undef, $status ) = split /^[#]{2} [ ] Status \n/msx,
      path($file)->slurp, 2;
    ($status) = split /^[#]{2} [ ]/msx, $status // q{}, 2;
    return $status // q{};
}

1;
