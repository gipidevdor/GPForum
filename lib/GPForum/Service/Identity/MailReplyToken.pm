# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Identity::MailReplyToken;

use Mojo::Base 'GPForum::Base', -signatures;
use v5.40;
use Const::Fast;
use Digest::SHA    qw(hmac_sha256_hex sha256_hex);
use Crypt::URandom qw(urandom);
use Mojo::Util     qw(secure_compare);
use GPForum::Infrastructure::Id;
use GPForum::Service::Clock;

our $VERSION = '0.001';

const my $NONCE_LENGTH    => 16;
const my $TOKEN_PARTS     => 5;
const my $SECONDS_PER_DAY => 86_400;

# A clock a day behind the issuer's still accepts what it issued today.
const my $OLDEST_FUTURE_DAY => -1;
const my $NONCE             => qr/\A [[:xdigit:]]{16} \z/amsx;
const my $DAY               => qr/\A [[:digit:]]{1,9} \z/amsx;
const my $MAC               => qr/\A [[:xdigit:]]{64} \z/amsx;
__PACKAGE__->requires(qw(secrets domain));
has clock        => sub { return GPForum::Service::Clock->new; };
has max_age_days => 30;

sub issue ( $self, $thread, $user, $message_key = undef ) {
    return undef
      if !GPForum::Infrastructure::Id->is_uuid($thread)
      || !GPForum::Infrastructure::Id->is_uuid($user);
    my $nonce = substr sha256_hex( $message_key // urandom($NONCE_LENGTH) ), 0,
      $NONCE_LENGTH;
    my $value = "$thread.$user.$nonce." . $self->_today;
    return
        '<gpforum-reply.'
      . $value . q{.}
      . hmac_sha256_hex( "gpforum-mail-reply-v1:$value", $self->secrets->[0] )
      . q{@}
      . $self->domain . '>';
}

# The UTC day the capability was issued: retries of one notification on one
# day keep one Message-ID, and a reply after max_age_days is refused.
sub _today ($self) {
    return int( $self->clock->now_epoch / $SECONDS_PER_DAY );
}

sub verify ( $self, $value ) {
    my ( $thread, $user, $nonce, $day, $mac ) = $self->_parts($value)
      or return undef;
    my $age = $self->_today - $day;
    return undef if $age < $OLDEST_FUTURE_DAY || $age > $self->max_age_days;

    for my $secret ( @{ $self->secrets } ) {
        return { thread_id => $thread, user_id => $user }
          if secure_compare(
            $mac,
            hmac_sha256_hex(
                "gpforum-mail-reply-v1:$thread.$user.$nonce.$day", $secret
            )
          );
    }
    return undef;
}

# The thread, recipient, nonce, day and MAC of a well-formed capability for
# this domain, or nothing.
sub _parts ( $self, $value ) {
    my ( $payload, $domain ) = ( $value // q{} ) =~
      /\A <gpforum-reply[.]([^<>\s\@]+)\@([^<>\s]+)> \z/msx;
    return if !defined $domain || $domain ne $self->domain;
    my @parts = split /[.]/msx, $payload;
    return if @parts != $TOKEN_PARTS;
    my ( $thread, $user, $nonce, $day, $mac ) = @parts;
    return
         if $nonce !~ $NONCE
      || $day      !~ $DAY
      || $mac      !~ $MAC
      || !GPForum::Infrastructure::Id->is_uuid($thread)
      || !GPForum::Infrastructure::Id->is_uuid($user);
    return @parts;
}

1;

__END__

=head1 NAME

GPForum::Service::Identity::MailReplyToken - Recipient-scoped email reply capabilities.

=head1 DESCRIPTION

The Message-ID contains a thread UUID, recipient UUID, the UTC day it was
issued and HMAC-SHA256 using
the session signing secrets with a separate protocol context. In-Reply-To
must echo this entire id. A public mbox Message-ID cannot authorize posting.
The sender must still match a currently verified active account. Secrets
can rotate using the configured previous session secrets. Forwarded mail
contains a capability and should be treated like a signed action link.
A reply more than C<max_age_days> (30) after the notification is refused.

=head1 SUBROUTINES/METHODS

=head2 issue

Returns a recipient-bound notification Message-ID with an HMAC, a per-message
nonce and the day of issue; one message key on one UTC day gives one id.

=head2 verify

Authenticates a complete In-Reply-To value no older than C<max_age_days> and
returns its thread and user UUIDs, or undef.

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

A forwarded capability remains a bearer token until it expires; MailIn also
requires the sender to be the recipient's current verified address.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause license.

=cut
