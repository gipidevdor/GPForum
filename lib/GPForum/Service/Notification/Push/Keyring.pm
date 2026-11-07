# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Notification::Push::Keyring;

use Mojo::Base -base, -signatures;
use v5.40;
use English qw(-no_match_vars);
use Carp    qw(croak);
use Const::Fast;
use Crypt::PK::ECC;
use Crypt::URandom qw(urandom);
use Digest::SHA    qw(sha256_hex);
use Fcntl
  qw(O_CREAT O_EXCL O_WRONLY S_ISDIR O_RDONLY O_RDWR O_NOFOLLOW O_DIRECTORY LOCK_EX);
use IO::Handle;
use File::Path   qw(make_path);
use File::Temp   qw(tempfile);
use MIME::Base64 qw(encode_base64url);
use Mojo::JSON   qw(encode_json);
use GPForum::Service::Notification::Push::Secrets;

our $VERSION = '0.001';
const my $DIRECTORY_MODE => oct '0700';
const my $FILE_MODE      => oct '0600';
const my $OTHER_ACCESS   => oct '0077';
const my $STAT_MODE      => 2;
const my $STAT_OWNER     => 4;
const my $KEY_BYTES      => 32;
const my $KEY_ID_DIGITS  => 16;
has 'directory';

sub generate ( $self, $rotate = 0 ) {
    my $directory = $self->_directory;
    my $lock      = $self->_rotation_lock($directory);
    my $secrets   = GPForum::Service::Notification::Push::Secrets->new(
        directory => $directory );
    my $exists = -e "$directory/private.json";
    if ( $exists && !$rotate ) {
        croak
'Push keys already exist; use --rotate to preserve existing subscriptions';
    }
    my $private = $exists ? $secrets->private : { keys => {} };
    my $public  = $exists ? $secrets->public  : { keys => {} };
    $self->_ensure_storage( $secrets, $exists );
    my $key     = Crypt::PK::ECC->new->generate_key('prime256v1');
    my $encoded = encode_base64url( $key->export_key_raw('public') );
    my $id      = substr sha256_hex($encoded), 0, $KEY_ID_DIGITS;
    $private->{keys}{$id} = encode_base64url( $key->export_key_raw('private') );
    $public->{keys}{$id}  = $encoded;
    $private->{active}    = $id;
    $public->{active}     = $id;

    # Publish the new public key only after the worker can read its private
    # key. Both rings retain the previous keys; storage.key never rotates here.
    $self->_publish( 'private.json', $private );
    $self->_publish( 'public.json',  $public );
    return { key_id => $id, directory => $directory };
}

sub _rotation_lock ( $self, $directory ) {
    sysopen my $lock, "$directory/.rotation.lock",
      O_RDWR | O_CREAT | O_NOFOLLOW, $FILE_MODE
      or croak 'cannot open Push rotation lock';
    flock $lock, LOCK_EX or croak 'cannot lock Push key ring';
    return $lock;
}

sub _directory ($self) {
    my $directory = $self->directory;
    if ( !-d $directory ) {
        make_path( $directory, { mode => $DIRECTORY_MODE } );
    }
    my @directory_stat = lstat $directory;
    croak 'unsafe Push key directory'
      if !@directory_stat
      || !S_ISDIR( $directory_stat[$STAT_MODE] )
      || $directory_stat[$STAT_OWNER] != $EFFECTIVE_USER_ID
      || ( $directory_stat[$STAT_MODE] & $OTHER_ACCESS );
    return $directory;
}

sub _ensure_storage ( $self, $secrets, $exists ) {
    my $directory = $self->directory;
    if ( !-e "$directory/storage.key" ) {
        if ($exists) {
            croak 'Push storage key missing; restore it before rotating';
        }
        sysopen my $output, "$directory/storage.key",
          O_WRONLY | O_CREAT | O_EXCL, $FILE_MODE
          or croak 'cannot create Push storage key';
        print {$output} encode_base64url( urandom($KEY_BYTES) )
          or croak 'cannot write Push storage key';
        $output->sync or croak 'cannot sync Push storage key';
        close $output or croak 'cannot close Push storage key';
    }
    $secrets->storage;
    return;
}

sub _publish ( $self, $name, $document ) {
    my ( $output, $temporary ) =
      tempfile( '.push-XXXXXX', DIR => $self->directory, UNLINK => 1 );
    chmod $FILE_MODE, $temporary or croak 'cannot protect Push key file';
    print {$output} encode_json($document)
      or croak 'cannot write Push key file';
    $output->sync or croak 'cannot sync Push key file';
    close $output or croak 'cannot close Push key file';
    rename $temporary, $self->directory . q{/} . $name
      or croak 'cannot publish Push key file';
    sysopen my $directory_handle, $self->directory,
      O_RDONLY | O_DIRECTORY | O_NOFOLLOW
      or croak 'cannot open Push key directory for sync';
    $directory_handle->sync or croak 'cannot sync Push key directory';
    close $directory_handle or croak 'cannot close Push key directory';
    return;
}

1;

__END__

=head1 NAME

GPForum::Service::Notification::Push::Keyring - Create and rotate persistent Web Push signing identities.

=head1 DESCRIPTION

Create and rotate persistent Web Push signing identities. See docs/ops/web-push.md for deployment and lifecycle guarantees.

=head1 SUBROUTINES/METHODS

=head2 generate

Create storage.key and both signing rings. An existing ring requires explicit rotation, which preserves its previous keys and the storage key.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $service = GPForum::Service::Notification::Push::Keyring->new(directory => $directory);

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
