# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Infrastructure::Id;

use Mojo::Base -base, -signatures;
use v5.40;

use Const::Fast;
use English qw(-no_match_vars);

our $VERSION = '0.001';

const my $UUID_RANDOM_BYTES  => 10;
const my $MILLISECONDS       => 1_000;
const my $BITS               => 8;
const my $VERSION_MASK       => 0x0f;
const my $VERSION_SEVEN      => 0x70;
const my $VARIANT_MASK       => 0x3f;
const my $VARIANT_RFC4122    => 0x80;
const my $VERSION_BYTE_INDEX => 6;
const my $VARIANT_BYTE_INDEX => 8;
const my $TIMESTAMP_SKIP     => 2;
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

# Version 7: the time in milliseconds in the first six bytes, big-endian,
# then ten random bytes under the version and variant bits, written as the
# five groups of hex digits. The time is the low six bytes of a 64-bit
# big-endian integer; the bytes are set in place rather than as a list of
# numbers, which made an id twice as dear.
sub uuid ($self) {
    my $bytes =
      substr( pack( 'Q>', int( time * $MILLISECONDS ) ), $TIMESTAMP_SKIP )
      . _random_bytes($UUID_RANDOM_BYTES);
    vec( $bytes, $VERSION_BYTE_INDEX, $BITS ) =
      ( vec( $bytes, $VERSION_BYTE_INDEX, $BITS ) & $VERSION_MASK ) |
      $VERSION_SEVEN;
    vec( $bytes, $VARIANT_BYTE_INDEX, $BITS ) =
      ( vec( $bytes, $VARIANT_BYTE_INDEX, $BITS ) & $VARIANT_MASK ) |
      $VARIANT_RFC4122;

    return join q{-}, unpack $UUID_GROUPS, unpack 'H*', $bytes;
}

# The system's random bytes, read a page at a time: each id read ten bytes
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

Returns a version-seven UUID string.

=head1 DIAGNOSTICS

Random byte generation errors are surfaced by L<Crypt::URandom>.

=head1 CONFIGURATION AND ENVIRONMENT

No environment variables are read.

=head1 DEPENDENCIES

Uses L<Crypt::URandom>.

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
