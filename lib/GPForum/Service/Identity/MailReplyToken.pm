# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Identity::MailReplyToken;

use Mojo::Base 'GPForum::Base', -signatures;
use v5.40;
use Const::Fast;
use Digest::SHA    qw(hmac_sha256_hex sha256_hex);
use Crypt::URandom qw(urandom);
use Mojo::Util     qw(secure_compare);
use GPForum::Infrastructure::Id;

our $VERSION = '0.001';

const my $NONCE_LENGTH => 16;
const my $TOKEN_PARTS  => 4;
const my $NONCE        => qr/\A [[:xdigit:]]{16} \z/amsx;
const my $MAC          => qr/\A [[:xdigit:]]{64} \z/amsx;
__PACKAGE__->requires(qw(secrets domain));

sub issue ( $self, $thread, $user, $message_key = undef ) {
    return undef
      if !GPForum::Infrastructure::Id->is_uuid($thread)
      || !GPForum::Infrastructure::Id->is_uuid($user);
    my $nonce = substr sha256_hex( $message_key // urandom($NONCE_LENGTH) ), 0,
      $NONCE_LENGTH;
    my $value = "$thread.$user.$nonce";
    return
        '<gpforum-reply.'
      . $value . q{.}
      . hmac_sha256_hex( "gpforum-mail-reply-v1:$value", $self->secrets->[0] )
      . q{@}
      . $self->domain . '>';
}

sub verify ( $self, $value ) {
    my ( $payload, $domain ) = ( $value // q{} ) =~
      /\A <gpforum-reply[.]([^<>\s\@]+)\@([^<>\s]+)> \z/msx;
    return undef if !defined $domain || $domain ne $self->domain;
    my @parts = split /[.]/msx, $payload;
    return undef if @parts != $TOKEN_PARTS;
    my ( $thread, $user, $nonce, $mac ) = @parts;
    return undef if $nonce !~ $NONCE || $mac !~ $MAC;
    return undef
      if !GPForum::Infrastructure::Id->is_uuid($thread)
      || !GPForum::Infrastructure::Id->is_uuid($user);
    for my $secret ( @{ $self->secrets } ) {
        return { thread_id => $thread, user_id => $user }
          if secure_compare(
            $mac,
            hmac_sha256_hex(
                "gpforum-mail-reply-v1:$thread.$user.$nonce", $secret
            )
          );
    }
    return undef;
}

1;

__END__

=head1 NAME

GPForum::Service::Identity::MailReplyToken - Recipient-scoped email reply capabilities.

=head1 DESCRIPTION

The Message-ID contains a thread UUID, recipient UUID and HMAC-SHA256 using
the session signing secrets with a separate protocol context. In-Reply-To
must echo this entire id. A public mbox Message-ID cannot authorize posting.
The sender must still match a currently verified active account. Secrets
can rotate using the configured previous session secrets. Forwarded mail
contains a capability and should be treated like a signed action link.

=head1 SUBROUTINES/METHODS

=head2 issue

Returns a recipient-bound notification Message-ID with an HMAC and per-message nonce.

=head2 verify

Authenticates a complete In-Reply-To value and returns its thread and user UUIDs, or undef.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $message_id = $tokens->issue($thread_id, $user_id, $post_id);

=head1 DIAGNOSTICS

Invalid capabilities return undef.

=head1 CONFIGURATION AND ENVIRONMENT

Inject current and previous session signing secrets and the published forum domain.

=head1 DEPENDENCIES

Crypt::URandom, Digest::SHA and Mojo::Util.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

A forwarded capability remains a bearer token; current account checks are owned by MailIn.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause license.

=cut
