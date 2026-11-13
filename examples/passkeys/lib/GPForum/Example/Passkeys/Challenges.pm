# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Example::Passkeys::Challenges;

use Mojo::Base -base, -signatures;
use v5.40;
use Const::Fast;
use Crypt::URandom qw(urandom);
use MIME::Base64   qw(encode_base64url);
use Mojo::Exception;

our $VERSION = '0.001';
const my $CHALLENGE_BYTES => 32;
const my $TTL_SECONDS     => 300;
const my $CAPACITY        => 512;

has pending => sub { return {}; };
has clock   => sub {
    return sub { return time; };
};

sub issue ( $self, $owner, $previous = undef ) {
    my $now     = $self->clock->();
    my $pending = $self->pending;
    for my $key ( keys %{$pending} ) {
        if ( $pending->{$key}{expires_at} <= $now ) {
            delete $pending->{$key};
        }
    }
    if ( defined $previous ) {
        $self->consume( $owner, $previous );
    }
    if ( keys %{$pending} >= $CAPACITY ) {
        Mojo::Exception->throw('challenge_capacity');
    }
    my $challenge = encode_base64url( urandom($CHALLENGE_BYTES) );
    my $entry     = { owner => $owner, expires_at => $now + $TTL_SECONDS };
    $pending->{$challenge} = $entry;
    return { challenge => $challenge, expires_at => $entry->{expires_at} };
}

sub consume ( $self, $owner, $challenge ) {
    return 0 if !defined $challenge || ref $challenge;
    my $entry = $self->pending->{$challenge};
    return 0 if !$entry || $entry->{owner} ne $owner;
    delete $self->pending->{$challenge};
    return $entry->{expires_at} > $self->clock->() ? 1 : 0;
}

1;

__END__

=head1 NAME

GPForum::Example::Passkeys::Challenges - Single-process demonstration nonce ledger.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $pending = $ledger->issue($owner);
    $ledger->consume($owner, $pending->{challenge});

=head1 DESCRIPTION

The session holds the challenge; this bounded, expiring ledger also consumes
it server-side. Deleting a signed cookie field alone cannot reject old-cookie
replay. Production must replace this ledger with an atomic PostgreSQL consume.
Only the single-process daemon is supported by the example.

=head1 SUBROUTINES/METHODS

=head2 issue

Issues 32 random bytes, invalidates this owner's preceding challenge, and
returns its Base64URL representation and absolute expiry (five minutes).

=head2 consume

Checks owner and expiry and removes a nonce before verification. Returns a
boolean. There is no asynchronous yield between lookup and removal.

=head1 DIAGNOSTICS

Capacity exhaustion raises Mojo::Exception; absent, expired or reused nonces return false.

=head1 CONFIGURATION AND ENVIRONMENT

The optional clock callback supports deterministic expiry tests.

=head1 DEPENDENCIES

See the pinned dependencies in examples/passkeys/cpanfile.snapshot.

=head1 INCOMPATIBILITIES

In-memory state is lost at restart and cannot be shared across workers or hosts.

=head1 BUGS AND LIMITATIONS

No credential persistence or assertion/login ceremony is implemented.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. BSD-3-Clause.

=cut
