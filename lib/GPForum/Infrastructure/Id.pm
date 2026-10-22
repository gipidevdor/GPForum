# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Infrastructure::Id;

use Mojo::Base -base, -signatures;
use v5.40;

use Const::Fast;
use English     qw(-no_match_vars);
use Time::HiRes ();

our $VERSION = '0.001';

const my $UUID_RANDOM_BYTES  => 8;
const my $MICROSECONDS       => 1_000;
const my $FRACTIONS          => 4_096;
const my $TICKS_PER_SECOND   => 4_096_000;
const my $FRACTION_BITS      => 12;
const my $FRACTION_MASK      => 0x0fff;
const my $TIME_SHIFT         => 16;
const my $VERSION_SEVEN      => 0x70_00;
const my $BITS               => 8;
const my $VARIANT_MASK       => 0x3f;
const my $VARIANT_RFC4122    => 0x80;
const my $VARIANT_BYTE_INDEX => 8;
const my $UUID_GROUPS        => 'A8 A4 A4 A4 A12';

# /a: without it [[:xdigit:]] also matches the fullwidth digits and letters
# (U+FF10...), which PostgreSQL's uuid input rejects.
const my $UUID_PATTERN =>
  qr/\A [[:xdigit:]]{8} (?: - [[:xdigit:]]{4} ){3} - [[:xdigit:]]{12} \z/msxa;

# What PostgreSQL reads as a uuid: the digits in either case, a hyphen
# allowed after any group of four, the whole in braces or not. A value
# written otherwise is refused with the statement that binds it.
const my $UUID_DIGITS => qr/(?: [[:xdigit:]]{4} -? ){7} [[:xdigit:]]{4}/msxa;
const my $UUID_SPELLING =>
  qr/\A (?: [{] $UUID_DIGITS [}] | $UUID_DIGITS ) \z/msxa;

# The shape of a uuid. A value from a URL or a form that does not have it must
# be refused before it reaches a uuid column: PostgreSQL rejects the whole
# statement, which surfaces as a 500 instead of a 404 or a 400.
sub uuid_pattern ($class) {
    return $UUID_PATTERN;
}

sub is_uuid ( $class, $value ) {
    return defined $value && $value =~ $UUID_PATTERN ? 1 : 0;
}

sub is_uuid_spelling ( $class, $value ) {
    return defined $value && $value =~ $UUID_SPELLING ? 1 : 0;
}

# Version 7 (RFC 9562): the time in milliseconds in the first six bytes,
# big-endian; the version, then twelve bits counting 4,096ths of that
# millisecond (section 6.2, method 3); then eight random bytes under the
# variant bits, written as the five groups of hex digits. The builtin time
# is whole seconds: it left the milliseconds at zero, so the ids of one
# second sorted at random, and a list ordered by a created_at to the
# second, then by id, showed two posts of one second either way round.
# An id sorts after the one this process minted before it, even in the
# same tick or when the clock steps back. The first eight bytes are one
# 64-bit big-endian integer and the variant is set in place, rather than
# as a list of numbers, which made an id twice as dear.
my $LAST_TICK = 0;

sub uuid ($self) {
    my ( $seconds, $microseconds ) = Time::HiRes::gettimeofday();
    my $tick = $seconds * $TICKS_PER_SECOND +
      int( $microseconds * $FRACTIONS / $MICROSECONDS );
    if ( $tick <= $LAST_TICK ) {
        $tick = $LAST_TICK + 1;
    }
    $LAST_TICK = $tick;
    my $bytes = pack( 'Q>',
        ( ( $tick >> $FRACTION_BITS ) << $TIME_SHIFT ) | $VERSION_SEVEN |
          ( $tick & $FRACTION_MASK ) )
      . _random_bytes($UUID_RANDOM_BYTES);
    vec( $bytes, $VARIANT_BYTE_INDEX, $BITS ) =
      ( vec( $bytes, $VARIANT_BYTE_INDEX, $BITS ) & $VARIANT_MASK ) |
      $VARIANT_RFC4122;

    return join q{-}, unpack $UUID_GROUPS, unpack 'H*', $bytes;
}

# The system's random bytes, read a page at a time: each id read its bytes
# with a read of its own, and a signed-in thread page makes 28 ids. What is
# read is this process's alone -- a worker forked from the manager drops
# what the manager read and reads its own -- so no two processes hand out
# the same bytes, and none is handed out twice.
const my $RANDOM_PAGE => 4_096;
my %RANDOM = ( process => 0, bytes => q{} );

sub _random_bytes ($bytes) {
    if ( $RANDOM{process} != $PROCESS_ID ) {
        %RANDOM = ( process => $PROCESS_ID, bytes => q{} );
    }
    if ( length $RANDOM{bytes} < $bytes ) {
        require Crypt::URandom;
        $RANDOM{bytes} .= Crypt::URandom::urandom($RANDOM_PAGE);
    }

    return substr $RANDOM{bytes}, 0, $bytes, q{};
}

1;

__END__

=head1 NAME

GPForum::Infrastructure::Id - Identifier service.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $id = GPForum::Infrastructure::Id->new->uuid;

=head1 DESCRIPTION

Provides UUID generation behind a replaceable service boundary.
L<Crypt::URandom> is loaded when minting a UUID so compile-time tests can
inject L<GPForum::Test::Id> without that XS module.

=head1 SUBROUTINES/METHODS

=head2 uuid_pattern

The pattern a uuid's text form matches.

=head2 is_uuid

True when a value has the shape of a uuid.

=head2 is_uuid_spelling

True when a value is one PostgreSQL reads as a uuid: hexadecimal digits in
either case, a hyphen allowed after any group of four, in braces or not.
C<is_uuid> is the one shape GPForum writes; this is every shape the
database accepts, for a value that is about to be bound for a uuid column.

=head2 uuid

Returns a version-seven UUID string. Its time is the millisecond and a
4,096th of it, and the ids one process mints sort in the order it minted
them.

=head1 DIAGNOSTICS

Random byte generation errors are surfaced by L<Crypt::URandom>.

=head1 CONFIGURATION AND ENVIRONMENT

No environment variables are read.

=head1 DEPENDENCIES

Uses L<Crypt::URandom> and L<Time::HiRes>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Only UUID version seven generation is exposed.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause
license.

=cut
