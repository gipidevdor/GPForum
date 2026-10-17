# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Identity::SecretBox;

use Const::Fast;
use Digest::SHA  qw(hmac_sha256 sha256_hex);
use MIME::Base64 qw(decode_base64url encode_base64url);
use Mojo::Base -base, -signatures;
use v5.40;

use GPForum::X::Unavailable;

our $VERSION = '0.001';

# ADR 0142: a two-step secret is sealed before it is stored, with a key the
# database never sees (GPFORUM_SECOND_FACTOR_KEY). Encrypt-then-MAC from
# HMAC-SHA-256 alone, which Digest::SHA brings with Perl: a keystream of
# HMAC(encryption key, nonce || counter) -- counter mode over a
# pseudorandom function -- XORed with the secret, then HMAC(MAC key) over
# the format, the key id, the member's id, the nonce and the ciphertext.
# The two keys are derived from the configured one under their own labels;
# the member's id binds a sealed secret to its row, so one copied to
# another member's opens for nobody.
const my $FORMAT       => 'v1';
const my $ENCRYPT      => 'gpforum.second-factor.encrypt.v1';
const my $AUTHENTICATE => 'gpforum.second-factor.authenticate.v1';
const my $KEY_ID       => "gpforum.second-factor.key-id.v1\n";
const my $NONCE_BYTES  => 16;
const my $BLOCK_BYTES  => 32;
const my $KEY_ID_CHARS => 12;
const my $PARTS        => 5;
const my $MAXIMUM      => 400;

# The keys, the one that seals first; the others still open what they
# sealed (a key being rotated out).
has keys => sub { return []; };

has random_bytes => sub {
    return sub ($count) {
        require Crypt::URandom;
        return Crypt::URandom::urandom($count);
    };
};

# Whether a key is configured: without one nothing is sealed or opened.
sub available ($self) {
    return scalar $self->_keys ? 1 : 0;
}

# The id of the key that seals: the first 12 hexadecimal characters of a
# labelled SHA-256 of it, which names it without revealing it.
sub current_key_id ($self) {
    my ($key) = $self->_keys;
    return defined $key ? _key_id($key) : undef;
}

# The plaintext sealed for a member: "v1.<key id>.<nonce>.<ciphertext>.<tag>",
# base64url, and the key id.
sub seal ( $self, $plaintext, $context ) {
    my ($key) = $self->_keys;
    if ( !defined $key ) {
        GPForum::X::Unavailable->throw(
            message => 'second factor secrets need GPFORUM_SECOND_FACTOR_KEY' );
    }

    my $key_id = _key_id($key);
    my $nonce  = $self->random_bytes->($NONCE_BYTES);
    my $ciphertext =
      $plaintext ^. _keystream( $key, $nonce, length $plaintext );
    my $tag = _tag( $key, $key_id, $context, $nonce, $ciphertext );

    return (
        join( q{.},
            $FORMAT,     $key_id, map { encode_base64url($_) } $nonce,
            $ciphertext, $tag ),
        $key_id
    );
}

# The plaintext a sealed text holds for the member, or undef: a text of
# another format, sealed under a key no longer held, altered, or sealed
# for another member.
sub unseal ( $self, $sealed, $context ) {
    return undef if !defined $sealed || length $sealed > $MAXIMUM;
    my ( $format, $key_id, @encoded ) = split /[.]/msx, $sealed;
    return undef if ( $format // q{} ) ne $FORMAT || @encoded != $PARTS - 2;
    my ( $nonce, $ciphertext, $tag ) = map { decode_base64url($_) } @encoded;

    for my $key ( $self->_keys ) {
        next if _key_id($key) ne $key_id;
        next
          if !_same( _tag( $key, $key_id, $context, $nonce, $ciphertext ),
            $tag );

        return $ciphertext ^. _keystream( $key, $nonce, length $ciphertext );
    }

    return undef;
}

# Whether a sealed text was sealed with a key other than the current one,
# and is worth sealing again.
sub stale ( $self, $key_id ) {
    my $current = $self->current_key_id;

    return defined $current && defined $key_id && $key_id ne $current ? 1 : 0;
}

sub _keys ($self) {
    my %seen;

    return grep { defined && length && !$seen{$_}++ } @{ $self->keys || [] };
}

sub _key_id ($key) {
    return substr sha256_hex( $KEY_ID . $key ), 0, $KEY_ID_CHARS;
}

sub _keystream ( $key, $nonce, $length ) {
    my $encryption = hmac_sha256( $ENCRYPT, $key );
    my $stream     = q{};
    my $counter    = 0;
    while ( length $stream < $length ) {
        $stream .= hmac_sha256( $nonce . pack( 'N', $counter++ ), $encryption );
    }

    return substr $stream, 0, $length;
}

sub _tag ( $key, $key_id, $context, $nonce, $ciphertext ) {
    return hmac_sha256(
        pack( '(N/a*)*',
            $FORMAT, $key_id, $context // q{},
            $nonce,  $ciphertext ),
        hmac_sha256( $AUTHENTICATE, $key )
    );
}

# Compared in time independent of where the first difference is.
sub _same ( $left, $right ) {
    return 0 if !defined $left                || !defined $right;
    return 0 if length $left != length $right || length $left != $BLOCK_BYTES;
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

GPForum::Service::Identity::SecretBox - Seals two-step secrets with the configured key.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $box = GPForum::Service::Identity::SecretBox->new(
        keys => [ $config->second_factor_keys ] );
    my ( $sealed, $key_id ) = $box->seal( $secret, $user_id );
    my $secret = $box->unseal( $sealed, $user_id );    # undef when it cannot

=head1 DESCRIPTION

ADR 0142. The TOTP secrets are stored sealed: encrypted with a keystream of
HMAC-SHA-256 in counter mode under a key derived from the configured one,
then authenticated with HMAC-SHA-256 under a second derived key over the
format, the key's id, the member's id (the context), the nonce and the
ciphertext. Each sealing draws a 16-byte random nonce. The key's id is
stored beside the sealed text so a rotated key can be found and retired.

=head1 SUBROUTINES/METHODS

=head2 available

True when a key is configured.

=head2 current_key_id

The id of the key that seals now, or undef.

=head2 seal

Takes the plaintext and the context (the member's id) and returns the
sealed text and the key's id.

=head2 unseal

Takes a sealed text and its context and returns the plaintext, or undef
when no configured key opens it as that member's.

=head2 stale

True when the key id given is not the current key's.

=head1 DIAGNOSTICS

L</seal> without a key throws L<GPForum::X::Unavailable>.

=head1 CONFIGURATION AND ENVIRONMENT

C<keys>: the current key first (C<GPFORUM_SECOND_FACTOR_KEY>), then the
previous ones still accepted (C<GPFORUM_SECOND_FACTOR_KEYS>).

=head1 DEPENDENCIES

L<Digest::SHA>, L<MIME::Base64>, L<Crypt::URandom>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

The construction is built from HMAC-SHA-256 because no AEAD cipher ships
with Perl; a later format can move to AES-GCM under a new version prefix.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause
license.

=cut
