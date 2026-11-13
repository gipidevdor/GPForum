# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Password;

use Const::Fast;
use Crypt::Argon2 qw(argon2id_pass argon2id_verify);
use Encode        qw(encode FB_CROAK LEAVE_SRC);
use GPForum::Infrastructure::AsyncWork;
use GPForum::X::Argument;
use Mojo::Base -base, -signatures, -async_await;
use v5.40;

our $VERSION = '0.001';
const my $MINIMUM_ARGON_MEMORY_MIB => 19;
const my $MAXIMUM_ARGON_MEMORY_MIB => 256;
const my $MAXIMUM_ARGON_ITERATIONS => 10;

const my $SALT_BYTES     => 16;
const my $PARALLELISM    => 1;
const my $TAG_BYTES      => 32;
const my $MINIMUM_LENGTH => 12;

# The decoy hash of each cost, made once per process (decoy_hash).
my %DECOY;

has memory_mib => 32;
has iterations => 3;

sub from_config ( $class, $config ) {
    return $class->new if !defined $config;
    return $class->new(
        memory_mib => $config->password_memory_mib,
        iterations => $config->password_iterations,
    );
}

sub hash_password ( $self, $password ) {
    $self->_require_hashable($password);

    return $self->_hashed($password);
}

# hash_password in a child of the CPU lane: Argon2 never holds the event
# loop. The password and the costs are checked here first, so a refusal is
# the same exception hash_password throws.
async sub hash_password_p ( $self, $password ) {
    $self->_require_hashable($password);

    return await GPForum::Infrastructure::AsyncWork->shared->cpu_p(
        sub { return $self->_hashed($password); } );
}

# verify_password in a child of the CPU lane.
async sub verify_password_p ( $self, $password, $encoded_hash ) {
    return 0 if !_verifiable( $password, $encoded_hash );

    return await GPForum::Infrastructure::AsyncWork->shared->cpu_p(
        sub { return $self->verify_password( $password, $encoded_hash ); } );
}

sub _require_hashable ( $self, $password ) {
    _require_password($password);
    if (   $self->memory_mib !~ /\A\d+\z/msx
        || $self->memory_mib < $MINIMUM_ARGON_MEMORY_MIB
        || $self->memory_mib > $MAXIMUM_ARGON_MEMORY_MIB
        || $self->iterations !~ /\A\d+\z/msx
        || $self->iterations < 2
        || $self->iterations > $MAXIMUM_ARGON_ITERATIONS )
    {
        GPForum::X::Argument->throw(
            message => 'Argon2 requires 19..256 MiB and 2..10 iterations' );
    }

    return;
}

sub _hashed ( $self, $password ) {
    return argon2id_pass(
        _octets( $password, 'UTF-8' ),
        _random_bytes($SALT_BYTES),
        $self->iterations, $self->memory_mib . 'M',
        $PARALLELISM,      $TAG_BYTES
    );
}

sub verify_password ( $self, $password, $encoded_hash ) {
    return 0 if !_verifiable( $password, $encoded_hash );

    # A password is hashed as its UTF-8 octets, and verified so: nothing
    # released ever hashed one otherwise.
    return argon2id_verify( $encoded_hash, _octets( $password, 'UTF-8' ) )
      ? 1
      : 0;
}

sub _octets ( $password, $encoding ) {
    return encode( $encoding, $password, FB_CROAK | LEAVE_SRC );
}

# A hash nobody knows the password of, made once per process. A login for
# an unknown account verifies against it, so that it costs what a wrong
# password costs: answering at once told anyone timing the reply which
# usernames and addresses have an account.
sub decoy_hash ($self) {
    return $DECOY{ $self->_cost } //=
      $self->hash_password( unpack 'H*', _random_bytes($SALT_BYTES) );
}

# decoy_hash made in a child of the CPU lane the first time, and kept in
# this process as decoy_hash keeps it.
async sub decoy_hash_p ($self) {
    my $cost = $self->_cost;
    return $DECOY{$cost} //=
      await $self->hash_password_p( unpack 'H*', _random_bytes($SALT_BYTES) );
}

sub _cost ($self) {
    return join q{:}, $self->memory_mib, $self->iterations;
}

sub _verifiable ( $password, $encoded_hash ) {
    return
         defined $password
      && defined $encoded_hash
      && $encoded_hash =~ /\A \x{24} argon2id \x{24} /msx ? 1 : 0;
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
The salt is 128 random bits.

=head2 verify_password

Verifies a password, as its UTF-8 octets, against a standard encoded Argon2id
hash. There is no fallback to another encoding, so distinct passwords stay
distinct.
No trimming, normalization, case folding or truncation is performed.


=head2 decoy_hash

An Argon2id hash of a random password, made once per process, to verify
against when there is no account: an unknown login then takes as long as a
wrong password.

=head2 hash_password_p

L</hash_password> as a promise: the password and the costs are checked in
this process, and Argon2 runs in a child of the CPU lane
(L<GPForum::Infrastructure::AsyncWork/cpu_p>), so it never holds the event
loop.

=head2 verify_password_p

L</verify_password> as a promise, Argon2 run in a child of the CPU lane.

=head2 decoy_hash_p

L</decoy_hash> as a promise: made in a child of the CPU lane the first
time, then kept in this process.

=head2 from_config

Builds the hasher with the validated memory and iteration costs; without configuration uses defaults.

=head1 DIAGNOSTICS

Throws exceptions for missing or too-short passwords.

=head1 CONFIGURATION AND ENVIRONMENT

No environment variables are read.

=head1 DEPENDENCIES

Uses L<Const::Fast>, L<Crypt::Argon2>, L<Crypt::URandom>, L<Encode> and
L<Mojo::Base>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

New hashes use the configured memory and iteration costs. Verification reads
the costs from each existing hash, so changing the settings preserves logins.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
