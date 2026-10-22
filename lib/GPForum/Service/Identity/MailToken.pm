# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Identity::MailToken;

use Const::Fast;
use Digest::SHA qw(hmac_sha256_hex);
use Mojo::Base -base, -signatures;
use v5.40;

use GPForum::Config;
use GPForum::Service::Identity::SecretBox;
use GPForum::X::Unavailable;

our $VERSION = '0.001';

# The key a mail's token is sealed with, derived from a signing secret
# under its own label, so no other use of that secret reads as one.
const my $PURPOSE => 'gpforum.identity-mail.v1';

# The application's signing secrets, newest first: a token is sealed with
# the first and opened with any, so a rotated secret still opens the mail
# queued before it. The configured ones unless given.
has secrets => sub { return GPForum::Config->new->signing_secrets; };

has box => sub ($self) {
    return GPForum::Service::Identity::SecretBox->new(
        keys => [ map { hmac_sha256_hex( $PURPOSE, $_ ) } $self->_secrets ] );
};

sub seal ( $self, $token, $token_id ) {
    my ($sealed) = $self->box->seal( $token, $token_id );

    return $sealed;
}

sub unseal ( $self, $sealed, $token_id ) {
    return $self->box->unseal( $sealed, $token_id );
}

sub _secrets ($self) {
    my @secrets = grep { defined && length } @{ $self->secrets || [] };
    if ( !@secrets ) {
        GPForum::X::Unavailable->throw(
            message => 'identity mail tokens need a signing secret' );
    }

    return @secrets;
}

1;

__END__

=head1 NAME

GPForum::Service::Identity::MailToken - Seals the token of an identity mail while it waits in the outbox.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $mail_token = GPForum::Service::Identity::MailToken->new(
        secrets => $app->secrets );
    my $sealed = $mail_token->seal( $raw_token, $token_id );
    my $raw    = $mail_token->unseal( $sealed, $token_id );

=head1 DESCRIPTION

A password reset, an email change and an email verification carry a token
the member follows, and wait for the outbox worker to mail them. The
outbox payload holds the token sealed, not in clear: encrypt-then-MAC
through L<GPForum::Service::Identity::SecretBox>, with a key derived from
each signing secret under the label C<gpforum.identity-mail.v1>, and bound
to the token's id, so a sealed token copied to another mail opens for
nobody. The database alone, its backups and a dead letter's payload do not
give the token; the worker, which holds the secrets, opens it to send.

=head1 SUBROUTINES/METHODS

=head2 seal

Takes the raw token and its token id; returns the sealed text.

=head2 unseal

Takes the sealed text and the token id; returns the raw token, or undef
for a text sealed under no secret held, for another token, or altered.

=head1 DIAGNOSTICS

Throws L<GPForum::X::Unavailable> when there is no signing secret.

=head1 CONFIGURATION AND ENVIRONMENT

C<GPFORUM_SESSION_SECRET> and C<GPFORUM_SESSION_SECRETS>, through
L<GPForum::Config/signing_secrets>, unless C<secrets> is given.

=head1 DEPENDENCIES

L<Digest::SHA>, L<GPForum::Config>, L<GPForum::Service::Identity::SecretBox>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Whoever holds the database and the signing secrets together can open a
queued token, as they could sign a session cookie.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause
license.

=cut
