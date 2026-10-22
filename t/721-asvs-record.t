# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use Mojo::File qw(path);
use Test::More;

our $VERSION = '0.001';

# The OWASP ASVS 5.0.0 verification record (ADR 0149) says, requirement by
# requirement, what GPForum meets and what shows it. This test does not verify
# the requirements again; that is the review the record writes down. It keeps
# the record checkable: every requirement in scope is there once, under its
# chapter, by its versioned identifier; each row has a level, a state and its
# evidence or reason; every file it names exists, at a line the file has; the
# tallies agree with the rows; and the gap list names every requirement not
# met, and nothing else.

const my $RECORD => 'docs/security/asvs-5.0.md';

# Requirements in scope per chapter: every Level 1 and 2 requirement of ASVS
# 5.0.0, Level 3 in V6, V7 and V8, seven V11 requirements behind
# authentication, and the moderation rows of V2 and V16. V10 and V17 do not
# apply (ADR 0149).
const my %IN_SCOPE => (
    1  => 27,
    2  => 13,
    3  => 19,
    4  => 10,
    5  => 9,
    6  => 47,
    7  => 19,
    8  => 13,
    9  => 7,
    11 => 21,
    12 => 9,
    13 => 13,
    14 => 9,
    15 => 13,
    16 => 17,
);
const my %LEVEL_THREE => map { $_ => 1 } qw(2 6 7 8 11 16);
const my %STATES      => map { $_ => 1 } ( 'met', 'not met', 'n/a' );
const my $HIGHEST     => 3;
const my $CELLS       => 5;

const my $NUMBER   => qr/([[:digit:]]+)/msx;
const my $ID       => qr/\A v5[.]0[.]0- $NUMBER [.] $NUMBER [.] $NUMBER \z/msx;
const my $CITED_ID => qr/v5[.]0[.]0-[[:digit:].]+[[:digit:]]/msx;
const my $TOP_FILES =>
  qr/cpanfile|Makefile|[.]gitleaks[.]toml|[[:upper:]_]+[.]md/msx;
const my $DIRECTORIES => join q{|},
  qw(.github assets bin deploy docs etc lib locale migrations script t templates themes);
const my $NAMES_A_FILE => qr{\A (?: (?:$DIRECTORIES)/ | $TOP_FILES )}msx;
const my $FILE_AND_LINES =>
  qr{\A ([^:\s]+) (?: : $NUMBER (?: - $NUMBER )? )? \z}msx;
const my $TALLY_KEY => qr/V[[:digit:]]+|Level [ ] [123]|All [ ] chapters/msx;
const my $COUNT     => qr/[ ] [|] [ ] ([[:digit:]]+)/msx;

my $text = path($RECORD)->slurp('UTF-8');
my @rows = _rows($text);

subtest
  'every requirement in scope is cited once, in order, under its chapter' =>
  \&_check_identifiers;
subtest 'every row has a level, a state and its evidence or reason' =>
  \&_check_cells;
subtest 'every file the record names exists, at a line it has' =>
  \&_check_files;
subtest 'the tallies agree with the rows' => \&_check_tallies;
subtest 'the gap list names every requirement not met, and only those' =>
  \&_check_gaps;

done_testing();

sub _rows ($markdown) {
    my @found;
    my $section;
    for my $line ( split /\n/msx, $markdown ) {
        if ( $line =~ /\A [#]{2} [ ] /msx ) {
            ($section) = $line =~ /\A [#]{2} [ ] V([[:digit:]]+) [ ]/msx;
            next;
        }
        next if $line !~ /\A [|] [ ] v5[.]0[.]0- /msx;
        my ( undef, @cells ) = split /[ ]* [|] [ ]*/msx, $line;
        my ( $id, $level, undef, $state, $evidence ) = @cells;
        my @numbers = $id =~ $ID;
        push @found,
          {
            line     => $line,
            cells    => \@cells,
            id       => $id,
            numbers  => \@numbers,
            section  => $section,
            level    => $level,
            state    => $state    // q{},
            evidence => $evidence // q{},
          };
    }
    return @found;
}

sub _check_identifiers {
    my @malformed = map { $_->{id} } grep { !@{ $_->{numbers} } } @rows;
    is_deeply( \@malformed, [], 'identifiers read v5.0.0-C.S.R' );

    my %seen;
    my @twice = grep { $seen{$_}++ } map { $_->{id} } @rows;
    is_deeply( \@twice, [], 'no requirement is listed twice' );

    my @cited  = map { $_->{id} } @rows;
    my @sorted = map { $_->{id} }
      sort { _compare_numbers( $a->{numbers}, $b->{numbers} ) } @rows;
    is_deeply( \@cited, \@sorted, 'requirements are in ASVS order' );

    my @misplaced = map { $_->{id} }
      grep { @{ $_->{numbers} } && ( $_->{section} // 0 ) != $_->{numbers}[0] }
      @rows;
    is_deeply( \@misplaced, [], 'each requirement is under its chapter' );

    my %per_chapter;
    for my $row ( grep { @{ $_->{numbers} } } @rows ) {
        $per_chapter{ $row->{numbers}[0] }++;
    }
    is_deeply( \%per_chapter, \%IN_SCOPE,
        'every chapter lists the requirements in scope' );
    return undef;
}

sub _compare_numbers ( $left, $right ) {
    return
         $left->[0] <=> $right->[0]
      || $left->[1] <=> $right->[1]
      || $left->[2] <=> $right->[2];
}

sub _check_cells {
    my @shapeless =
      map { $_->{line} } grep { @{ $_->{cells} } != $CELLS } @rows;
    is_deeply( \@shapeless, [], 'every row has five cells' );

    my @levels = map { $_->{id} } grep { !_level_in_scope($_) } @rows;
    is_deeply( \@levels, [], 'every level is 1, 2, or 3 where ADR 0149 says' );

    my @states = map { $_->{id} } grep { !$STATES{ $_->{state} } } @rows;
    is_deeply( \@states, [], 'every state is met, not met, or n/a' );

    my @unexplained =
      map { $_->{id} } grep { $_->{evidence} !~ /[[:alpha:]]{2}/msx } @rows;
    is_deeply( \@unexplained, [], 'every row gives its evidence or reason' );

    my @unproven = map { $_->{id} }
      grep { $_->{state} eq 'met' && !_files( $_->{evidence} ) } @rows;
    is_deeply( \@unproven, [], 'every met requirement names a file' );
    return undef;
}

sub _level_in_scope ($row) {
    my $level = $row->{level} // q{};
    return 0 if $level !~ /\A [123] \z/msx;
    return 1 if $level < $HIGHEST;
    return @{ $row->{numbers} } && $LEVEL_THREE{ $row->{numbers}[0] };
}

sub _files ($evidence) {
    return grep { $_ =~ $NAMES_A_FILE } $evidence =~ /`([^`]+)`/gmsx;
}

sub _check_files {
    my %lines;
    my @missing;
    for my $row (@rows) {
        for my $cited ( _files( $row->{evidence} ) ) {
            my ( $file, $first, $until ) = $cited =~ $FILE_AND_LINES;
            if ( !defined $file || !-e $file ) {
                push @missing, "$row->{id}: $cited";
                next;
            }
            next if !defined $first;
            $lines{$file} //= scalar( () = path($file)->slurp =~ /\n/gmsx );
            my $line = $until // $first;
            if ( $first < 1 || $line < $first || $line > $lines{$file} ) {
                push @missing, "$row->{id}: $cited";
            }
        }
    }
    is_deeply( \@missing, [], 'cited files exist and have the cited lines' );
    return undef;
}

sub _check_tallies {
    my %counted;
    for my $row (@rows) {
        for my $key ( "V$row->{numbers}[0]", "Level $row->{level}",
            'All chapters' )
        {
            $counted{$key}{scope}++;
            $counted{$key}{ $row->{state} }++;
        }
    }
    my %stated;
    for my $line ( split /\n/msx, $text ) {
        my ( $key, @numbers ) =
          $line =~ m{\A [|] [ ] ($TALLY_KEY) [^|]* $COUNT $COUNT $COUNT $COUNT
            [ ] [|] \z}msx
          or next;
        @{ $stated{$key} }{ 'scope', 'met', 'not met', 'n/a' } = @numbers;
    }
    for my $tally ( values %counted ) {
        for my $state ( keys %STATES ) {
            $tally->{$state} //= 0;
        }
    }
    is_deeply( \%stated, \%counted,
        'each chapter, level and the total add up to their rows' );
    return undef;
}

sub _check_gaps {
    my ($gaps) =
      $text =~ /^ [#]{2} [ ] Gaps [^\n]* \n (.*?) (?: ^[#]{2} [ ] | \z)/msx;
    ok( defined $gaps, 'the record ends with its gap list' );
    my %listed = map { $_ => 1 } ( $gaps // q{} ) =~ /($CITED_ID)/gmsx;
    my %not_met =
      map { $_->{id} => 1 } grep { $_->{state} eq 'not met' } @rows;
    is_deeply(
        [ sort keys %listed ],
        [ sort keys %not_met ],
        'the gap list names exactly the requirements not met'
    );
    return undef;
}

1;
