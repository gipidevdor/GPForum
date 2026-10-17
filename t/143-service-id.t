# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use lib 'lib';
use lib 't/lib';

use GPForum::Infrastructure::Id;
use GPForum::Test::Id;
use Carp qw(croak);
use Const::Fast;
use English qw(-no_match_vars);
use Test::More;

our $VERSION = '0.001';

# The fullwidth digit one, which [[:xdigit:]] matches without the /a flag.
const my $FULLWIDTH_ONE    => chr 0xFF_11;
const my $UUID_DIGIT_COUNT => 32;
const my $MILLISECONDS     => 1_000;
const my $MANY             => 5_000;
const my $FEW              => 50;

ok( !exists $INC{'Crypt/URandom.pm'},
    'Crypt::URandom stays unloaded when Id compiles' );

ok(
    GPForum::Infrastructure::Id->new,
    'Id constructs without generating a UUID'
);
is( GPForum::Test::Id->new->uuid,
    'generated-1', 'injected Test::Id still supplies identifiers' );

ok( !exists $INC{'Crypt/URandom.pm'},
    'Crypt::URandom stays unloaded after construct and Test::Id' );

# is_uuid guards uuid columns: what passes it, PostgreSQL must accept.
ok(
    GPForum::Infrastructure::Id->is_uuid(
        GPForum::Infrastructure::Id->new->uuid
    ),
    'a generated uuid is a uuid'
);
ok(
    GPForum::Infrastructure::Id->is_uuid(
        '018F1000-0000-7000-8000-0000000000FF'),
    'in either case'
);
ok( !GPForum::Infrastructure::Id->is_uuid(undef),           'undef is not' );
ok( !GPForum::Infrastructure::Id->is_uuid('dead-letter-1'), 'a word is not' );
ok(
    !GPForum::Infrastructure::Id->is_uuid(
        "018f1000-0000-7000-8000-0000000000ff\n"),
    'nor a uuid with a trailing newline'
);

# [[:xdigit:]] matches the fullwidth digits and letters too, and Mojolicious
# decodes a percent-encoded path, so this reached the uuid column and came
# back as a database error instead of a 404.
ok(
    !GPForum::Infrastructure::Id->is_uuid(
        "\N{FULLWIDTH DIGIT ZERO}18f1000-0000-7000-8000-0000000000ff"),
    'fullwidth hex digits are not ASCII hex'
);

# What PostgreSQL reads as a uuid, for a value about to be bound for a uuid
# column: either case, braces, hyphens after any group of four or none.
for my $spelling (
    '018f1000-0000-7000-8000-0000000000ff',
    '018F1000-0000-7000-8000-0000000000FF',
    '{018f1000-0000-7000-8000-0000000000ff}',
    '018f100000007000800000000000000ff' =~ s/f\z//msxr,
    '018f-1000-0000-7000-8000-0000-0000-00ff',
  )
{
    ok(
        GPForum::Infrastructure::Id->is_uuid_spelling($spelling),
        "$spelling is a uuid as PostgreSQL reads one"
    );
}
for my $other (
    'new', undef, q{},
    '{018f1000-0000-7000-8000-0000000000ff',
    '018f1000-0000-7000-8000-0000000000ff-',
    $FULLWIDTH_ONE x $UUID_DIGIT_COUNT
  )
{
    ok( !GPForum::Infrastructure::Id->is_uuid_spelling($other),
        ( $other // 'undef' ) . ' is not' );
}

# Version 7: the time in milliseconds in the first twelve digits, then the
# version digit 7 and the variant 8 to b; never the same id twice, the
# random bytes read a page at a time.
my $ids    = GPForum::Infrastructure::Id->new;
my $before = sprintf '%012x', int( time * $MILLISECONDS );
my %minted = map { $ids->uuid => 1 } 1 .. $MANY;
my $after  = sprintf '%012x', int( time * $MILLISECONDS );
is( scalar keys %minted, $MANY, 'every id minted is new' );
my @shaped = grep {
         /\A [[:xdigit:]]{8} - [[:xdigit:]]{4} - 7 [[:xdigit:]]{3} - [89ab]/msx
      && join( q{}, ( split /-/msx )[ 0, 1 ] ) ge $before
      && join( q{}, ( split /-/msx )[ 0, 1 ] ) le $after
} keys %minted;
is( scalar @shaped, $MANY, 'each with the time, the version and the variant' );

# A process forked from one that read its page of random bytes reads its
# own: the two never hand out the same id.
my ( $reader, $writer );
pipe $reader, $writer or croak "pipe: $OS_ERROR";
my $child = fork // croak "fork: $OS_ERROR";
if ( !$child ) {
    close $reader                                                     or exit 1;
    print {$writer} join( "\n", map { $ids->uuid } 1 .. $FEW ) . "\n" or exit 1;
    close $writer                                                     or exit 1;
    exit 0;
}
close $writer or croak "close: $OS_ERROR";
my @theirs = <$reader>;
close $reader or croak "close: $OS_ERROR";
waitpid $child, 0;
chomp @theirs;
my %ours = map { $ids->uuid => 1 } 1 .. $FEW;
is( scalar @theirs, $FEW, 'the forked process minted its ids' );
is( scalar( grep { $ours{$_} } @theirs ),
    0, 'and none of them is one of this process' );

done_testing();

1;
