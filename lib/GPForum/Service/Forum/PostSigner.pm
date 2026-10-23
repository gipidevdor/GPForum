# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Forum::PostSigner;

use Mojo::Base 'GPForum::Base', -signatures;
use v5.40;
use Const::Fast;
use Carp qw(croak);
use Crypt::PK::Ed25519;
use Digest::SHA qw(sha256_hex);
use JSON::MaybeXS;
use MIME::Base64 qw(encode_base64url decode_base64url);
use Mojo::File   qw(path);

our $VERSION = '0.001';

const my $PUBLIC_KEY_BYTES => 32;
__PACKAGE__->requires('key_file');
my $JSON = JSON::MaybeXS->new( canonical => 1, utf8 => 1 );
has key => sub ($self) { return $self->_load_key; };

has public_key => sub ($self) { return $self->_archive_public_key; };

# The trust anchor is the filesystem, never a key supplied by the database
# alongside the content it purports to authenticate.
has trusted_keys => sub ($self) { return $self->_read_trusted_keys; };

sub _load_key ($self) {
    my $file = path( $self->key_file )->to_abs;
    if ( !-e $file ) {
        $file->dirname->make_path( { mode => oct '700' } );
        my $key = Crypt::PK::Ed25519->new->generate_key;

        # Write a complete private file before publishing it. link is atomic
        # and never replaces another worker's winning key.
        require File::Temp;
        my ( $fh, $temporary ) = File::Temp::tempfile(
            '.post-key-XXXXXX',
            DIR    => $file->dirname->to_string,
            UNLINK => 1
        );
        chmod oct '600', $temporary or croak 'cannot protect signing key';
        print {$fh} $key->export_key_pem('private')
          or croak 'cannot write signing key';
        close $fh or croak 'cannot close signing key';
        if ( !link $temporary, $file ) {
            croak 'cannot publish signing key' if !-e $file;
        }
    }
    croak 'signing key must be a private regular file'
      if -l $file || !-f $file || ( ( stat $file )[2] & oct '077' );
    my $key = Crypt::PK::Ed25519->new( $file->to_string );
    croak 'signing key has no private key' if !$key->is_private;
    return $key;
}

sub _archive_public_key ($self) {
    my $raw = $self->key->export_key_raw('public');
    my $key = {
        kty => 'OKP',
        crv => 'Ed25519',
        x   => encode_base64url($raw),
        kid => sha256_hex($raw),
        use => 'sig',
        alg => 'EdDSA'
    };
    my $file = path( $self->key_file . ".$key->{kid}.pub.json" )->to_abs;
    if ( !-e $file ) {
        require File::Temp;
        my ( $fh, $temporary ) = File::Temp::tempfile(
            '.post-public-XXXXXX',
            DIR    => $file->dirname->to_string,
            UNLINK => 1
        );
        print {$fh} $JSON->encode($key)
          or croak 'cannot archive public signing key';
        close $fh or croak 'cannot close public signing key';
        if ( !link $temporary, $file ) {
            croak 'cannot publish public signing key' if !-e $file;
        }
    }
    return $key;
}

sub _read_trusted_keys ($self) {
    my $current = $self->public_key;
    my $file    = path( $self->key_file )->to_abs;
    my $prefix  = $file->basename;
    my %keys    = ( $current->{kid} => $current );
    for my $entry ( @{ $file->dirname->list } ) {
        next
          if $entry->basename !~
          /\A \Q$prefix\E [.] [[:xdigit:]]{64} [.]pub[.]json \z/msx;
        croak 'public signing key must be a regular file'
          if -l $entry || !-f $entry;
        my $key = $JSON->decode( $entry->slurp );
        my $raw = decode_base64url( $key->{x} // q{} );
        croak 'invalid archived public signing key'
          if length($raw) != $PUBLIC_KEY_BYTES
          || sha256_hex($raw) ne ( $key->{kid} // q{} );
        $keys{ $key->{kid} } = $key;
    }
    return \%keys;
}

sub payload ( $, $body ) {
    my $source = ( $body->{body_source} // q{} ) =~ s/\r\n?/\n/grmsx;
    return $JSON->encode(
        {
            type        => 'GPForum.post.v1',
            post_id     => $body->{post_id},
            body_format => $body->{body_format},
            body_source => $source
        }
    );
}

sub sign ( $self, $body ) {
    my $payload = $self->payload($body);
    return {
        key            => $self->public_key,
        payload_sha256 => sha256_hex($payload),
        signature      => encode_base64url( $self->key->sign_message($payload) )
    };
}

sub verify ( $self, $body, $envelope ) {
    return 0 if ref $envelope ne 'HASH' || ref $envelope->{key} ne 'HASH';
    my $valid = 0;
    try {
        my $key     = $envelope->{key};
        my $trusted = $self->trusted_keys->{ $key->{kid} // q{} };
        return 0 if !$trusted || $trusted->{x} ne ( $key->{x} // q{} );
        my $raw = decode_base64url( $key->{x} // q{} );
        return 0 if $key->{kid} ne sha256_hex($raw);
        my $payload = $self->payload($body);
        return 0
          if ( $envelope->{payload_sha256} // q{} ) ne sha256_hex($payload);
        $valid =
          Crypt::PK::Ed25519->new->import_key_raw( $raw, 'public' )
          ->verify_message( decode_base64url( $envelope->{signature} // q{} ),
            $payload );
    }
    catch ($error) { return 0; };
    return $valid ? 1 : 0;
}

1;

__END__

=head1 NAME

GPForum::Service::Forum::PostSigner - Persisted Ed25519 attestations of post revisions.

=head1 DESCRIPTION

C<sign($body)> signs canonical UTF-8 JSON containing the type
C<GPForum.post.v1>, post UUID, Markdown format and exact source. The detached
envelope includes the payload SHA-256, base64url signature and public JWK with a SHA-256
key id. Public keys are archived alongside the private PEM, independently
of database content. The database stores the attestation with the revision; export verifies it before
delivery. This attests the server's copy, not the human author's identity.
Creation time, placement and moderation are outside this signature.

C<key_file> is a stable PEM path shared by all workers. A missing key is
created atomically with mode 0600; existing keys with group/other access are
refused. Preserve it separately from database backups. Pin or archive the
public well-known key set when verifying exports independently.

=head1 SUBROUTINES/METHODS

=head2 payload

Returns canonical UTF-8 JSON for the versioned post attestation.

=head2 sign

Returns a detached Ed25519 envelope for an exact post body.

=head2 verify

True only for exact matching content, a cryptographically valid signature and a filesystem-trusted public key.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $envelope = $signer->sign($body);

=head1 DIAGNOSTICS

Throws for inaccessible or unsafe key files. Verification returns false for untrusted or invalid signatures.

=head1 CONFIGURATION AND ENVIRONMENT

key_file names a persistent private PEM shared by workers. Public key archives live beside it.

=head1 DEPENDENCIES

Crypt::PK::Ed25519, JSON::MaybeXS, Digest::SHA and MIME::Base64.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Attests post UUID, format and source. It does not authenticate the human author or metadata.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause license.

=cut
