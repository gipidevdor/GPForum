# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package GPForum::Service::Identity::LocalProof;
use Mojo::Base 'GPForum::Base', -signatures, -async_await;
use v5.40;
use GPForum::Infrastructure::Row qw(column_of);
our $VERSION = '0.001';
__PACKAGE__->requires(qw(credentials password second_factor));

# The member's current password, checked against their active credential
# (a member without one costs the same work, against the decoy), and, when
# two-step sign-in is on, a code spent. The credential's id, or undef.
async sub verify_local_p ( $self, $actor, $password, $code = q{},
    $context = undef )
{
    my $credential =
      await $self->credentials->active_password_credential_p( $actor,
        $context );
    my $hash =
      $credential
      ? column_of( $credential, 'secret_hash' )
      : await $self->_decoy_hash_p;
    my $verified = await $self->_verified_p( $password // q{}, $hash );
    return undef if !$verified || !$credential;
    my $id = column_of( $credential, 'id' );
    my $challenge =
      await $self->second_factor->open_challenge_p( $actor, $id, $context );
    return $id   if $challenge->{status} eq 'none';
    return undef if $challenge->{status} ne 'open';
    my $answer =
      await $self->second_factor->prepare_answer_p( $challenge->{token},
        $code, $context );
    return undef if !$answer;

    return ( await $self->second_factor->answer_p( $answer, $context ) )->{ok}
      ? $id
      : undef;
}

# Argon2 in a child of the CPU lane on the asynchronous layer, in the
# process on the blocking one, whose settled promise a child would leave
# pending (ADR 0177).
async sub _verified_p ( $self, $password, $hash ) {
    return $self->password->verify_password( $password, $hash )
      if $self->_in_process;

    return await $self->password->verify_password_p( $password, $hash );
}

async sub _decoy_hash_p ($self) {
    return $self->password->decoy_hash if $self->_in_process;

    return await $self->password->decoy_hash_p;
}

sub _in_process ($self) {
    my $functions = $self->credentials->functions;
    return !$functions || $functions->blocking ? 1 : 0;
}

1;
__END__
=head1 NAME

GPForum::Service::Identity::LocalProof - Fresh password and configured second-factor proof for account changes.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $credential_id = await $proof->verify_local_p( $actor, $password, $code );

=head1 DESCRIPTION

Shared by external identity linking and passkey management. Verification returns the current password credential ID for the transactional write to hold again.

=head1 SUBROUTINES/METHODS

=head2 verify_local_p

Checks the current password and, when enabled, consumes a TOTP or recovery
code, with an optional query context after the code. Resolves with the
password credential's id, or undef on refusal. The reads and the challenge
run on the call layer of the credential store and the second factor;
Argon2 runs in a child of the CPU lane, or in the process when that layer
blocks (ADR 0177), so a blocking caller's settled copy runs it too.

=head1 DIAGNOSTICS

Wrong passwords and rejected second-factor answers return undef. Store errors propagate.

=head1 CONFIGURATION AND ENVIRONMENT

Inject credentials, password and second_factor services.

=head1 DEPENDENCIES

Uses the identity and infrastructure modules named above.

=head1 INCOMPATIBILITIES

External identity and TOTP retain their existing account policies.

=head1 BUGS AND LIMITATIONS

Proof alone does not authorize a write: callers hold the returned active credential in their write transaction.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. BSD-3-Clause.

=cut
