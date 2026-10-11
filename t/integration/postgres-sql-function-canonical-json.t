# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package main;

use v5.40;

use Const::Fast;
use Digest::SHA qw(sha256_hex);
use Encode      qw(encode_utf8);
use JSON::MaybeXS;
use Mojo::File qw(path);
use Test::More;

use lib 'lib';
use lib 't/lib';

use GPForum::Test::PgDatabase;

our $VERSION = '0.001';

const my $CANONICAL_SQL =>
  'SELECT api.core_canonical_json_v1(?::jsonb), encode(sha256('
  . q{convert_to(api.core_canonical_json_v1(?::jsonb), 'UTF8')), 'hex')};
const my @GOLDEN => qw(
  t/325-forum-posting-golden.t
  t/329-forum-thread-events-golden.t
);
const my $FIRST_CONTROL => 1;
const my $LAST_CONTROL  => 31;
const my $DELETE        => 127;
const my $MIN_FIXTURES  => 100;
const my $E_GRAVE       => "\N{LATIN SMALL LETTER E WITH GRAVE}";
const my $E_ACUTE       => "\N{LATIN SMALL LETTER E WITH ACUTE}";
const my $LINE_SEP      => "\N{LINE SEPARATOR}";
const my $GRIN          => "\N{GRINNING FACE}";
const my $CHINESE       => "\N{U+4E2D}\N{U+6587}";

if ( !GPForum::Test::PgDatabase->admin_dsn ) {
    plan skip_all => 'set GPFORUM_TEST_DSN to prove the canonical JSON';
}

# ADR 0126, section 5. The command log's response_hash and the audit chain's
# record_hash are SHA-256 of JSON::MaybeXS's canonical encoding; a function
# that records either computes it with api.core_canonical_json_v1. No
# function may use the helper until it writes, byte for byte, what Perl
# writes for the same value: the golden fixtures of t/325 and t/329 (every
# command request, response and replay, and every event and audit row the
# forum's writes hand on), and values made to find the differences.
my $database = GPForum::Test::PgDatabase->fresh;
my $dbh      = $database->dbh;
my $perl     = JSON::MaybeXS->new( canonical => 1, utf8   => 1 );
my $loose    = JSON::MaybeXS->new( canonical => 0, pretty => 1, utf8 => 0 );

my $fixtures = 0;
for my $file (@GOLDEN) {
    my ( undef, $data ) = split /^__DATA__$/msx, path($file)->slurp, 2;
    for my $line ( grep { length } split /\n/msx, $data ) {
        my ( $name, $json ) = split /\t/msx, $line, 2;
        _same( decode_json($json), "$file: $name" );
        $fixtures++;
    }
}
cmp_ok( $fixtures, q{>}, $MIN_FIXTURES, 'every golden fixture was compared' );

# Strings: every control character, the ones JSON escapes short and the rest
# as \u00xx; DEL, the slash and U+2028, which neither side escapes; quotes,
# backslashes, accents, a character outside the BMP.
_same(
    {
        controls => join( q{}, map { chr } $FIRST_CONTROL .. $LAST_CONTROL ),
        delete   => chr $DELETE,
        marks    => q{"quoted" \back\slash/ and / slash},
        text     => join( q{ }, "caff$E_GRAVE", $LINE_SEP, $GRIN, $CHINESE ),
    },
    'strings with control, escaped and non-ASCII characters'
);

# Keys sort by code point, as Perl sorts them: upper before lower case, a
# prefix before what extends it, an accented letter after every ASCII one.
_same(
    {
        'Z'         => 1,
        'a'         => 2,
        'aa'        => 3,
        'b'         => 4,
        $E_ACUTE    => 5,
        "a$E_ACUTE" => 6,
        q{a b}      => 7,
        q{}         => 8,
        $GRIN       => 9,
    },
    'keys in code point order'
);

# Numbers as Perl holds them after a decode: integers of every size it keeps
# exactly, and strings that look like numbers, which stay strings.
_same(
    decode_json(
            '{"zero":0,"negative":-17,"int32":2147483648,'
          . '"int53":9007199254740993,"uint64":18446744073709551615,'
          . '"decimal":1.5,"tenth":0.1,"padded":"007","numeric":"1.50",'
          . '"exponent":"1e3"}'
    ),
    'integers, decimals and numeric strings'
);
_same(
    {
        empty_array  => [],
        empty_object => {},
        false        => JSON::MaybeXS::false,
        nested       => [ { b => [ undef, [ {} ] ], a => q{} }, [] ],
        null         => undef,
        true         => JSON::MaybeXS::true,
    },
    'booleans, nulls, empty and nested containers'
);

# Where the two differ, and why no hashed document reaches it: Perl writes
# a number with an exponent and a negative zero as it holds them, jsonb as
# the numeric they are. Every number the command log and the audit chain
# hash is an integer (an ok, a schema version, a position, a count).
is( _sql( decode_json('[1e20, -0.0]') ),
    '[100000000000000000000,0.0]',
    'jsonb writes an exponent out, where Perl writes 1e+20 and -0.0' );

done_testing();

# Perl's canonical bytes and the function's, for the value and for the same
# value written loosely (keys in hash order, indented), so the function is
# seen sorting and stripping, not echoing its input.
sub _same ( $value, $label ) {
    my $expected = $perl->encode($value);
    my ( $from_canonical, $hash ) =
      _canonical( Encode::decode_utf8($expected) );
    is( encode_utf8($from_canonical), $expected, "$label: the same bytes" );
    is( $hash, sha256_hex($expected),            "$label: the same SHA-256" );
    is( encode_utf8( ( _canonical( $loose->encode($value) ) )[0] ),
        $expected, "$label: from loose JSON too" );

    return;
}

sub _canonical ($json) {
    return $dbh->selectrow_array( $CANONICAL_SQL, undef, $json, $json );
}

sub _sql ($value) {
    return ( _canonical( $loose->encode($value) ) )[0];
}

1;
