# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Identity::SecondFactorCodes;

use Const::Fast;
use Digest::SHA qw(hmac_sha1 sha256_hex);
use Mojo::Base -base, -signatures;
use v5.40;

use Mojo::Util qw(url_escape);

our $VERSION = '0.001';

# ADR 0142: RFC 6238 as every authenticator app reads it by default --
# HMAC-SHA-1, six digits, thirty seconds -- with a 160-bit secret (RFC 4226
# section 4), and one step of drift either way.
const my $SECRET_BYTES  => 20;
const my $DIGITS        => 6;
const my $PERIOD        => 30;
const my $DRIFT_STEPS   => 1;
const my $MODULUS       => 10**$DIGITS;
const my $OFFSET_MASK   => 0x0F;
const my $CODE_MASK     => 0x7FFF_FFFF;
const my $LAST_BYTE     => 19;
const my $COUNTER_SHIFT => 32;
const my $WORD_MASK     => 0xFFFF_FFFF;
const my $WORD_BYTES    => 4;

# Ten recovery codes of 16 base32 characters (80 bits) each, written in
# four groups of four.
const my $RECOVERY_CODES => 10;
const my $RECOVERY_BYTES => 10;
const my $RECOVERY_GROUP => 4;
const my $RECOVERY_CHARS => 16;
const my $RECOVERY_HASH  => 'gpforum.second-factor.recovery.v1';

const my @BASE32       => ( 'A' .. 'Z', 2 .. 7 );
const my $BASE32_BITS  => 5;
const my $BYTE_BITS    => 8;
const my $MAXIMUM_CODE => 64;

has random_bytes => sub {
    return sub ($count) {
        require Crypt::URandom;
        return Crypt::URandom::urandom($count);
    };
};

sub digits ($self) { return $DIGITS; }
sub period ($self) { return $PERIOD; }

# A new secret: 20 random bytes.
sub new_secret ($self) {
    return $self->random_bytes->($SECRET_BYTES);
}

# RFC 4648 base32, upper case, without padding: what an authenticator app
# is given to type in when it cannot scan.
sub base32 ( $self, $bytes ) {
    my $bits = unpack 'B*', $bytes;
    $bits .=
      '0' x ( ( $BASE32_BITS - length($bits) % $BASE32_BITS ) % $BASE32_BITS );

    return join q{},
      map { $BASE32[ oct "0b$_" ] } unpack "(A$BASE32_BITS)*", $bits;
}

# The base32 secret in groups of four, easier to copy by hand.
sub grouped ( $self, $text ) {
    return join q{ }, unpack '(A4)*', $text;
}

# The step a moment falls in.
sub step_at ( $self, $epoch ) {
    return int( $epoch / $PERIOD );
}

# RFC 4226: the code of a counter.
sub code_at ( $self, $secret, $step ) {
    my $counter = pack 'NN', ( $step >> $COUNTER_SHIFT ) & $WORD_MASK,
      $step & $WORD_MASK;
    my $digest = hmac_sha1( $counter, $secret );
    my $offset = ord( substr $digest, $LAST_BYTE, 1 ) & $OFFSET_MASK;
    my $binary =
      unpack( 'N', substr $digest, $offset, $WORD_BYTES ) & $CODE_MASK;

    return sprintf '%0*d', $DIGITS, $binary % $MODULUS;
}

# Whether the text is shaped as a code: six digits, spaces allowed.
sub totp_shaped ( $self, $text ) {
    return _digits($text) =~ /\A [[:digit:]]{$DIGITS} \z/msx ? 1 : 0;
}

# The step the code was made for, within one step of the moment either
# way, or undef. Every candidate is computed and compared in full, so the
# answer takes as long whichever matched, or none.
sub matching_step ( $self, $secret, $text, $epoch ) {
    my $code = _digits($text);
    return undef if $code !~ /\A [[:digit:]]{$DIGITS} \z/msx;

    my $now = $self->step_at($epoch);
    my $matched;
    for my $step ( $now - $DRIFT_STEPS .. $now + $DRIFT_STEPS ) {
        if ( _same( $self->code_at( $secret, $step ), $code ) ) {
            $matched = $step;
        }
    }

    return $matched;
}

# The link an authenticator app reads (Google's Key Uri Format): the issuer
# and the account as the label, the secret, and the defaults written out.
sub otpauth_uri ( $self, $secret, $issuer, $account ) {
    my $label = url_escape($issuer) . q{:} . url_escape($account);

    return
        "otpauth://totp/$label?secret="
      . $self->base32($secret)
      . '&issuer='
      . url_escape($issuer)
      . "&algorithm=SHA1&digits=$DIGITS&period=$PERIOD";
}

# Ten new recovery codes, as the member is shown them.
sub new_recovery_codes ($self) {
    return [
        map {
            lc join q{-}, unpack "(A$RECOVERY_GROUP)*",
              substr $self->base32( $self->random_bytes->($RECOVERY_BYTES) ),
              0, $RECOVERY_CHARS
        } 1 .. $RECOVERY_CODES
    ];
}

# A recovery code as typed -- any case, with or without its dashes and
# spaces -- in the one spelling that is hashed, or undef when it cannot be
# one.
sub normalize_recovery_code ( $self, $text ) {
    return undef if !defined $text || length $text > $MAXIMUM_CODE;
    ( my $code = lc $text ) =~ s/[\s-]+//gmsx;

    return $code =~ /\A [[:lower:]2-7]{$RECOVERY_CHARS} \z/msx ? $code : undef;
}

# The hash a recovery code is kept as, bound to its member: the codes have
# 80 bits each, so SHA-256 alone keeps them out of reach.
sub recovery_hash ( $self, $user_id, $code ) {
    return sha256_hex( join "\n", $RECOVERY_HASH, lc $user_id, $code );
}

sub _digits ($text) {
    ( my $digits = $text // q{} ) =~ s/\s+//gmsx;

    return length $digits > $MAXIMUM_CODE ? q{} : $digits;
}

# Compared in time independent of where the first difference is.
sub _same ( $left, $right ) {
    return 0 if length $left != length $right;
    my $difference = 0;
    for my $index ( 0 .. length($left) - 1 ) {
        $difference |=
          ord( substr $left, $index, 1 ) ^ ord( substr $right, $index, 1 );
    }

    return $difference == 0 ? 1 : 0;
}

1;

__END__

=head1 NAME

GPForum::Service::Identity::SecondFactorCodes - TOTP codes and recovery codes.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $codes  = GPForum::Service::Identity::SecondFactorCodes->new;
    my $secret = $codes->new_secret;
    my $uri    = $codes->otpauth_uri( $secret, 'GPForum', 'ada' );
    my $step   = $codes->matching_step( $secret, '123 456', time );

=head1 DESCRIPTION

ADR 0142. Time-based one-time passwords as RFC 6238 defines them with the
parameters every authenticator app assumes (HMAC-SHA-1, six digits, thirty
seconds), checked one step either side of now, in constant time per
candidate. Recovery codes are 80 random bits, shown as four groups of four
base32 characters and kept as a SHA-256 hash bound to the member.

=head1 SUBROUTINES/METHODS

=head2 digits

Six.

=head2 period

Thirty seconds.

=head2 new_secret

Twenty random bytes.

=head2 base32

RFC 4648 base32 of the bytes, upper case, unpadded.

=head2 grouped

The text in space-separated groups of four.

=head2 step_at

The thirty-second step an epoch second falls in.

=head2 code_at

The six-digit code of a secret at a step (RFC 4226 dynamic truncation).

=head2 totp_shaped

True when the text is six digits once spaces are taken out.

=head2 matching_step

The step, from one before now to one after, whose code the text is; undef
when none.

=head2 otpauth_uri

The C<otpauth://totp/> link for an issuer and an account.

=head2 new_recovery_codes

Ten new recovery codes, such as C<abcd-efgh-ijkl-mnop>.

=head2 normalize_recovery_code

The code as typed, lower case, dashes and spaces taken out; undef when it
is not sixteen base32 characters.

=head2 recovery_hash

The SHA-256 hash, hex, of a normalized code for a member.

=head1 DIAGNOSTICS

None: a text that is no code matches nothing.

=head1 CONFIGURATION AND ENVIRONMENT

C<random_bytes> is a code reference returning that many random bytes,
L<Crypt::URandom> by default; a test gives its own.

=head1 DEPENDENCIES

L<Digest::SHA>, L<Mojo::Util>, L<Crypt::URandom>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Only the parameters authenticator apps assume are offered: no SHA-256
secrets, eight digits or other periods.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause
license.

=cut
