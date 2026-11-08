# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package GPForum::Service::Identity::LocalProof;
use Mojo::Base 'GPForum::Base', -signatures, -async_await;
use v5.40;
use GPForum::Infrastructure::Row qw(column_of);
our $VERSION = '0.001';
__PACKAGE__->requires(qw(credentials password second_factor));

sub verify_local ( $self, $actor, $password, $code = q{} ) {
    my $credential = $self->credentials->active_password_credential($actor);
    my $hash =
      $credential
      ? column_of( $credential, 'secret_hash' )
      : $self->password->decoy_hash;
    my $verified = $self->password->verify_password( $password // q{}, $hash );
    return undef if !$verified || !$credential;
    my $id        = column_of( $credential, 'id' );
    my $challenge = $self->second_factor->open_challenge( $actor, $id );
    if ( $challenge->{status} ne 'none' ) {
        return undef if $challenge->{status} ne 'open';
        my $answer =
          $self->second_factor->prepare_answer( $challenge->{token}, $code );
        return undef
          if !$answer || !$self->second_factor->answer($answer)->{ok};
    }
    return $id;
}

# verify_local with the reads and the challenge on the worker's pooled
# asynchronous connections and Argon2 in a child of the CPU lane.
async sub verify_local_p ( $self, $actor, $password, $code = q{},
    $context = undef )
{
    my $credential =
      await $self->credentials->active_password_credential_p( $actor,
        $context );
    my $hash =
      $credential
      ? column_of( $credential, 'secret_hash' )
      : await $self->password->decoy_hash_p;
    my $verified =
      await $self->password->verify_password_p( $password // q{}, $hash );
    return undef if !$verified || !$credential;
    my $id = column_of( $credential, 'id' );
    my $challenge =
      await $self->second_factor->open_challenge_p( $actor, $id, $context );
    if ( $challenge->{status} ne 'none' ) {
        return undef if $challenge->{status} ne 'open';
        my $answer =
          await $self->second_factor->prepare_answer_p( $challenge->{token},
            $code, $context );
        return undef
          if !$answer
          || !( await $self->second_factor->answer_p( $answer, $context ) )
          ->{ok};
    }
    return $id;
}

1;
__END__
=head1 NAME

GPForum::Service::Identity::LocalProof - Fresh password and configured second-factor proof for account changes.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $credential_id = $proof->verify_local($actor, $password, $code);

=head1 DESCRIPTION

Shared by external identity linking and passkey management. Verification returns the current password credential ID for the transactional write to hold again.

=head1 SUBROUTINES/METHODS

=head2 verify_local

Checks the current password and, when enabled, consumes a TOTP or recovery code. Returns undef on refusal.

=head2 verify_local_p

L</verify_local> as a promise, with an optional query context after the
code: the reads and the challenge on the worker's pooled asynchronous
connections, Argon2 in a child of the CPU lane.

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
