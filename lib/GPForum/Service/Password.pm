# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Password;

use Const::Fast;
use Crypt::Argon2 qw(argon2id_pass argon2id_verify);
use Encode        qw(encode FB_CROAK LEAVE_SRC);
use MIME::Base64  qw(decode_base64);
use GPForum::X::Argument;
use Mojo::Base -base, -signatures;
use v5.40;

our $VERSION = '0.001';

const my $SALT_BYTES     => 16;
const my $TIME_COST      => 3;
const my $MEMORY_COST    => '32M';
const my $PARALLELISM    => 1;
const my $TAG_BYTES      => 32;
const my $MINIMUM_LENGTH => 12;

# The random suffix retains its 128 bits. This public salt prefix identifies
# UTF-8 password octets without changing the standard Argon2id PHC format.
# Previous GPForum hashes have a 16-byte salt, so cannot carry this marker.
const my $UTF8_SALT_PREFIX    => 'gpforum:utf8:';
const my $SALT_FIELD_FROM_END => 2;

sub hash_password ( $self, $password ) {
    _require_password($password);

    return argon2id_pass(
        _octets( $password, 'UTF-8' ),
        $UTF8_SALT_PREFIX . _random_bytes($SALT_BYTES),
        $TIME_COST, $MEMORY_COST, $PARALLELISM, $TAG_BYTES
    );
}

sub verify_password ( $self, $password, $encoded_hash ) {
    return 0 if !defined $password;
    return 0 if !defined $encoded_hash;
    return 0 if $encoded_hash !~ /\A \x{24} argon2id \x{24} /msx;

    my $utf8        = _uses_utf8($encoded_hash);
    my $legacy_text = $password !~ /[^\x{00}-\x{ff}]/msx;
    my $encoding    = $utf8 || !$legacy_text ? 'UTF-8' : 'ISO-8859-1';
    my $verified =
      argon2id_verify( $encoded_hash, _octets( $password, $encoding ) );

    # An unrepresentable legacy candidate still pays the KDF cost. It must
    # never match a different legacy password whose Latin-1 bytes happen to
    # equal this candidate's UTF-8 bytes.
    return $verified && ( $utf8 || $legacy_text ) ? 1 : 0;
}

sub _octets ( $password, $encoding ) {
    return encode( $encoding, $password, FB_CROAK | LEAVE_SRC );
}

sub _uses_utf8 ($encoded_hash) {
    my @fields = split /\x{24}/msx, $encoded_hash;
    my $salt   = decode_base64( $fields[ -$SALT_FIELD_FROM_END ] // q{} );

    return length $salt == length($UTF8_SALT_PREFIX) + $SALT_BYTES
      && substr( $salt, 0, length $UTF8_SALT_PREFIX ) eq $UTF8_SALT_PREFIX
      ? 1
      : 0;
}

# A hash nobody knows the password of, made once per process. A login for
# an unknown account verifies against it, so that it costs what a wrong
# password costs: answering at once told anyone timing the reply which
# usernames and addresses have an account.
sub decoy_hash ($self) {
    state $decoy =
      $self->hash_password( unpack 'H*', _random_bytes($SALT_BYTES) );

    return $decoy;
}

sub _require_password ($password) {
    if ( !defined $password || !length $password ) {
        GPForum::X::Argument->throw( message => 'password is required' );
    }

    if ( length $password < $MINIMUM_LENGTH ) {
        GPForum::X::Argument->throw(
            message => "password must be at least $MINIMUM_LENGTH characters" );
    }

    return;
}

sub _random_bytes ($bytes) {
    require Crypt::URandom;
    return Crypt::URandom::urandom($bytes);
}

1;

__END__

=head1 NAME

GPForum::Service::Password - Argon2id password hashing boundary.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $hash = GPForum::Service::Password->new->hash_password($password);

=head1 DESCRIPTION

Provides the mandatory Argon2id password hashing and verification boundary for
identity workflows. L<Crypt::URandom> is loaded when hashing so compile-time
tests can inject collaborators without that XS module.

=head1 SUBROUTINES/METHODS

=head2 hash_password

Validates its character length and hashes its exact UTF-8 octets with Argon2id.
The salt contains a public encoding marker followed by 128 random bits.

=head2 verify_password

Verifies a password against a standard encoded Argon2id hash. A marked salt
selects UTF-8. Previous GPForum hashes, whose salts have 16 bytes, retain
their original Latin-1 octets; characters outside that alphabet cannot match them.
There is no fallback between encodings, so distinct passwords stay distinct.
No trimming, normalization, case folding or truncation is performed.


=head2 decoy_hash

An Argon2id hash of a random password, made once per process, to verify
against when there is no account: an unknown login then takes as long as a
wrong password.

=head1 DIAGNOSTICS

Throws exceptions for missing or too-short passwords.

=head1 CONFIGURATION AND ENVIRONMENT

No environment variables are read.

=head1 DEPENDENCIES

Uses L<Const::Fast>, L<Crypt::Argon2>, L<Crypt::URandom>, L<Encode>,
L<MIME::Base64> and L<Mojo::Base>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Argon2 parameters are fixed until calibration tooling is added.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause
license.

=cut
