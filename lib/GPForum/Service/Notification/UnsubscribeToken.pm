# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Notification::UnsubscribeToken;

use Const::Fast;
use Digest::SHA  qw(hmac_sha256);
use MIME::Base64 qw(decode_base64url encode_base64url);
use Mojo::Base -base, -signatures;
use v5.40;

use GPForum::Infrastructure::Id;
use GPForum::X::Argument;

our $VERSION = '0.001';

# ADR 0078: what a token is for, signed into it so that no other signature
# the application makes with the same secret reads as one.
const my $PURPOSE => 'gpforum.notification.unsubscribe.v1';
const my %SCOPES  => map { $_ => 1 } qw(reply mention moderation all digest);

# The longest token verify reads: a uuid and a scope, and the signature.
const my $MAXIMUM_LENGTH => 160;

# The application's signing secrets, newest first: a token is signed with
# the first and read with any, so a rotated secret keeps old links working.
has secrets => sub { return []; };

sub issue ( $self, $user_id, $scope ) {
    if ( !exists $SCOPES{ $scope // q{} } ) {
        GPForum::X::Argument->throw(
            message => 'unsubscribe scope is unknown' );
    }
    if ( !GPForum::Infrastructure::Id->is_uuid_spelling($user_id) ) {
        GPForum::X::Argument->throw(
            message => 'unsubscribe user id is invalid' );
    }
    my ($secret) = $self->_secrets;
    my $claim = lc($user_id) . q{.} . $scope;

    return encode_base64url($claim) . q{.}
      . encode_base64url( _signature( $secret, $claim ) );
}

# The user id and scope a token names, or undef for one that is malformed or
# signed with no secret the application holds.
sub verify ( $self, $token ) {
    return undef if !defined $token || length $token > $MAXIMUM_LENGTH;
    my ( $encoded_claim, $encoded_signature ) =
      $token =~ m{\A ([[:alnum:]_-]+) [.] ([[:alnum:]_-]+) \z}msx;
    return undef if !defined $encoded_signature;
    my $claim = decode_base64url($encoded_claim);
    my ( $user_id, $scope ) =
      $claim =~ m{\A ([[:xdigit:]-]{36}) [.] ([[:lower:]_]+) \z}msx;
    return undef
      if !defined $scope
      || !exists $SCOPES{$scope}
      || !GPForum::Infrastructure::Id->is_uuid_spelling($user_id);
    my $signature = decode_base64url($encoded_signature);

    for my $secret ( $self->_secrets ) {
        return { user_id => $user_id, scope => $scope }
          if _same( _signature( $secret, $claim ), $signature );
    }

    return undef;
}

sub _secrets ($self) {
    my @secrets = grep { defined && length } @{ $self->secrets || [] };
    if ( !@secrets ) {
        GPForum::X::Argument->throw(
            message => 'unsubscribe tokens need a signing secret' );
    }

    return @secrets;
}

sub _signature ( $secret, $claim ) {
    return hmac_sha256( "$PURPOSE\n$claim", $secret );
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

GPForum::Service::Notification::UnsubscribeToken - Signed one-click unsubscribe links.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $tokens = GPForum::Service::Notification::UnsubscribeToken->new(
        secrets => $app->secrets );
    my $token = $tokens->issue( $user_id, 'reply' );
    my $claim = $tokens->verify($token);    # { user_id, scope } or undef

=head1 DESCRIPTION

ADR 0078. The token in an unsubscribe link, and in the mail's
C<List-Unsubscribe> header (RFC 8058): the member's id and the scope it
turns off (C<reply>, C<mention>, C<moderation>, C<all> or C<digest>), base64url, with
an HMAC-SHA-256 signature over them and the token's purpose. It is a
capability: whoever holds the mail may turn that email off, and nothing
else. It does not expire, as a link in an old mail must keep working, and
needs no storage; it is honoured while any of the application's signing
secrets signed it.

=head1 SUBROUTINES/METHODS

=head2 issue

Takes a user id and a scope and returns the token, signed with the first
secret.

=head2 verify

Takes a token and returns C<< { user_id, scope } >>, or undef when it is
malformed, names an unknown scope or is signed by no secret held.

=head1 DIAGNOSTICS

L</issue> throws L<GPForum::X::Argument> for an unknown scope or a user id
that is not a uuid; both methods throw it when no secret is configured.

=head1 CONFIGURATION AND ENVIRONMENT

The secrets are the application's signing secrets
(L<GPForum::Config/signing_secrets>, as L<GPForum::Bootstrap::Core> sets them).

=head1 DEPENDENCIES

L<Digest::SHA>, L<MIME::Base64>, L<GPForum::Infrastructure::Id>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

A link cannot be revoked short of rotating every secret that signed it;
it can only ever turn email off.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause
license.

=cut
