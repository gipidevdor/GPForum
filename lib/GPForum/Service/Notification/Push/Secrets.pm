# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Notification::Push::Secrets;

use Mojo::Base -base, -signatures;
use v5.40;
use Carp qw(croak);
use Const::Fast;
use Fcntl        qw(O_RDONLY O_NOFOLLOW S_ISREG);
use English      qw(-no_match_vars);
use MIME::Base64 qw(decode_base64url encode_base64url);
use Mojo::JSON   qw(decode_json);

our $VERSION = '0.001';
const my $STAT_MODE    => 2;
const my $STAT_OWNER   => 4;
const my $STAT_BYTES   => 7;
const my $MAX_BYTES    => 65_536;
const my $PRIVATE_MODE => oct '0077';
const my $KEY_BYTES    => 32;
has 'directory';

sub storage ($self) {
    my $encoded = $self->_read( 'storage.key', 1 );
    $encoded =~ s/\n\z//msx;
    my $key = decode_base64url($encoded);
    croak 'invalid push storage key'
      if length($key) != $KEY_BYTES || encode_base64url($key) ne $encoded;
    return $key;
}

sub public ($self) {
    my $keys = decode_json( $self->_read( 'public.json', 0 ) );
    if (   ref $keys ne 'HASH'
        || !defined $keys->{active}
        || ref $keys->{keys} ne 'HASH'
        || !exists $keys->{keys}{ $keys->{active} } )
    {
        croak 'invalid push public key ring';
    }
    return $keys;
}

sub private ($self) {
    my $keys = decode_json( $self->_read( 'private.json', 1 ) );
    croak 'invalid Push private key ring'
      if ref $keys ne 'HASH' || ref $keys->{keys} ne 'HASH';
    return $keys;
}

sub _read ( $self, $name, $private ) {
    my $file = $self->directory . q{/} . $name;
    sysopen my $input, $file, O_RDONLY | O_NOFOLLOW
      or croak 'cannot open push key material';
    my @stat = stat $input;
    if (
           !@stat
        || !S_ISREG( $stat[$STAT_MODE] )
        || $stat[$STAT_BYTES] > $MAX_BYTES
        || (
            $private
            && ( $stat[$STAT_OWNER] != $EFFECTIVE_USER_ID
                || ( $stat[$STAT_MODE] & $PRIVATE_MODE ) )
        )
      )
    {
        croak 'unsafe push key material';
    }
    my $bytes = do { local $INPUT_RECORD_SEPARATOR = undef; <$input> };
    close $input or croak 'cannot close push key material';
    return $bytes;
}

1;

__END__

=head1 NAME

GPForum::Service::Notification::Push::Secrets - Read bounded, protected Push key files without following final-component symlinks.

=head1 DESCRIPTION

Read bounded, protected Push key files without following final-component symlinks. See docs/ops/web-push.md for deployment and lifecycle guarantees.

=head1 SUBROUTINES/METHODS

=head2 storage

Read the separate 32-byte storage encryption key from storage.key.

=head2 public

Read public.json, which contains the active signing identity and public keys only.

=head2 private

Read private.json. Private files must be regular, owned by the effective user, with no group or other access.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $service = GPForum::Service::Notification::Push::Secrets->new(directory => $directory);

=head1 DIAGNOSTICS

Invalid input fails closed. Transport failures are bounded and reported without receiver capability URLs or key material.

=head1 CONFIGURATION AND ENVIRONMENT

Dependencies and validated settings are supplied by the composition layer. See docs/ops/web-push.md.

=head1 DEPENDENCIES

CryptX supplies cryptographic primitives; Mojolicious supplies asynchronous HTTPS; versioned PostgreSQL API functions own persistence.

=head1 INCOMPATIBILITIES

Private key files require a persistent service account and restrictive filesystem permissions.

=head1 BUGS AND LIMITATIONS

A provider acceptance does not guarantee display. An already accepted notification cannot be recalled.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. BSD-3-Clause.

=cut
