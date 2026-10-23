# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::OS::Filesystem;

use Carp qw(croak);
use Const::Fast;
use English        qw(-no_match_vars);
use File::Basename qw(dirname);
use IO::Handle;
use Mojo::File qw(tempfile);
use Mojo::Base -base, -signatures;
use v5.40;

use GPForum::X::Argument;

our $VERSION = '0.001';
const my $FILE_MODE => oct '666';

has durable => 0;

sub write_atomic ( $self, $path, $content ) {
    if ( !defined $path || !length $path ) {
        GPForum::X::Argument->throw( message => 'path is required' );
    }
    if ( !defined $content ) {
        GPForum::X::Argument->throw( message => 'content is required' );
    }

    my $temporary;
    try {
        $temporary = tempfile( '.gpforum-XXXXXXXX', DIR => dirname($path) );
    }
    catch ($error) {
        croak "failed to open temporary file beside $path: $error";
    };
    my $temporary_path = $temporary->to_string;
    $self->_write_temporary_file( $temporary_path, $content );
    rename $temporary_path,
      $path
      or _cleanup_and_croak( $temporary_path,
        "failed to rename $temporary_path to $path: $ERRNO" );
    if ( $self->durable ) {
        $self->sync_directory( dirname($path) );
    }

    return {
        ok             => 1,
        path           => $path,
        temporary_path => $temporary_path,
    };
}

sub _write_temporary_file ( $self, $temporary_path, $content ) {
    ## no critic (InputOutput::RequireBriefOpen) -- write, sync and close are one durability boundary
    open my $handle, '>', $temporary_path
      or croak "failed to open temporary file $temporary_path: $ERRNO";
    binmode $handle
      or _cleanup_and_croak( $temporary_path,
        "failed to set binary mode for $temporary_path: $ERRNO" );
    print {$handle} $content
      or _cleanup_and_croak( $temporary_path,
        "failed to write temporary file $temporary_path: $ERRNO" );
    $handle->flush
      or _cleanup_and_croak( $temporary_path,
        "failed to flush temporary file $temporary_path: $ERRNO" );

    # Keep the random temporary file private until all bytes are written,
    # then restore the service's normal permissions (0640 with umask 0027),
    # so the reverse proxy's group can read the published object.
    my $mode = $FILE_MODE & ~umask;
    chmod $mode,
      $handle
      or _cleanup_and_croak( $temporary_path,
        "failed to set permissions for $temporary_path: $ERRNO" );
    if ( $self->durable ) {
        $handle->sync
          or _cleanup_and_croak( $temporary_path,
            "failed to sync temporary file $temporary_path: $ERRNO" );
    }
    close $handle
      or _cleanup_and_croak( $temporary_path,
        "failed to close temporary file $temporary_path: $ERRNO" );
    ## use critic

    return;
}

sub sync_directory ( $, $directory ) {
    open my $handle, '<', $directory
      or croak "failed to open directory $directory: $ERRNO";
    $handle->sync or croak "failed to sync directory $directory: $ERRNO";
    close $handle or croak "failed to close directory $directory: $ERRNO";

    return;
}

sub _cleanup_and_croak ( $temporary_path, $message ) {
    if ( defined $temporary_path && -e $temporary_path ) {
        unlink $temporary_path;
    }
    croak $message;
}

1;
