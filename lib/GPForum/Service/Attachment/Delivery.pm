# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Attachment::Delivery;

use Carp                         qw(croak);
use Digest::SHA                  qw(sha256_hex);
use GPForum::Infrastructure::Row qw(column_of);
use GPForum::Service::Attachment::ImagePreview;
use Mojo::Base 'GPForum::Base', -signatures, -async_await;
use v5.40;

our $VERSION = '0.001';

__PACKAGE__->requires(qw(storage store));

# An authorized download never comes back as the whole object in a scalar
# for render(): a 25 MiB attachment (the validator's limit) would be pinned
# in a worker for the life of the request, once in the scalar and again in
# the response buffer, and concurrency multiplies it.
#
# A backend that can name a path returns the path and nothing else: the caller
# streams it. Only a backend that cannot is read into memory, and none of the
# shipped ones take that branch.
sub download ( $self, $input ) {
    my $decision = $self->store->download_for($input);
    return $decision if !$decision->{ok};

    if ( ( $input->{preview} // q{} ) eq '1280' ) {
        $decision = $self->_preview($decision);
    }
    return { %{$decision}, %{ $self->_body( $decision->{object_key} ) } };
}

# The same download on the worker's pooled asynchronous connections: the
# decision, the preview and a PostgreSQL object's size are read there.
async sub download_p ( $self, $input, $context = undef ) {
    my $store = $self->store;
    return $self->download($input) if !$store->can('download_for_p');
    my $decision = await $store->download_for_p( $input, $context );
    return $decision if !$decision->{ok};

    if ( ( $input->{preview} // q{} ) eq '1280' && _previewable($decision) ) {
        $decision = _with_variant( $decision,
            await $store->find_variant_p( _variant_query($decision), $context )
        );
    }
    my $storage = $self->storage;
    return { %{$decision},
        object_asset =>
          await $storage->asset_for_p( $decision->{object_key}, $context ) }
      if $storage->can('asset_for_p');
    return { %{$decision}, %{ $self->_body( $decision->{object_key} ) } };
}

# The original's complete access decision precedes the indexed variant lookup.
# A missing preview uses the original, including for uploads made before this
# feature. No transformation or source-sized allocation happens on a GET.
sub _preview ( $self, $decision ) {
    return $decision if !_previewable($decision);
    return _with_variant( $decision,
        $self->store->find_variant( _variant_query($decision) ) );
}

sub _previewable ($decision) {
    return ( $decision->{media_type} // q{} ) =~ m{\Aimage/(?:jpeg|png)\z}msx
      ? 1
      : 0;
}

sub _variant_query ($decision) {
    return {
        attachment_id => $decision->{attachment_id},
        variant_type  =>
          GPForum::Service::Attachment::ImagePreview->variant_type,
    };
}

sub _with_variant ( $decision, $variant ) {
    if ( !$variant ) { return $decision; }
    my $column = sub ($name) {
        return column_of( $variant, $name );
    };
    if ( ( $column->('media_type') // q{} ) ne 'image/png' ) {
        return $decision;
    }
    my $key = $column->('object_key');
    return {
        %{$decision},
        object_key => $key,
        media_type => 'image/png',
        byte_size  => $column->('byte_size'),
        checksum   => sha256_hex(
            join q{:}, $decision->{attachment}{checksum} // q{}, $key
        ),
    };
}

# A path whose file is gone -- a restore without the attachments, a lost
# disk -- is a failure, not an empty file: streamed, it answered 200 with no
# body and the member's file name, and logged nothing.
sub _body ( $self, $object_key ) {
    return { object_asset => $self->storage->asset_for($object_key) }
      if $self->storage->can('asset_for');
    my $path = $self->_object_path($object_key);
    if ( defined $path ) {
        croak "attachment object $object_key is missing from storage"
          if !-e $path;
        return { object_path => $path };
    }

    return { content => $self->storage->read_object($object_key) };
}

# UNIVERSAL::can by name, not $storage->can(...): a storage double is free to
# define its own can(), and the search permission engine already proved that
# hazard is not theoretical here.
sub _object_path ( $self, $object_key ) {
    my $storage = $self->storage;
    ## no critic (BuiltinFunctions::ProhibitUniversalCan)
    # Deliberate: the point is to bypass an overridden can(). The search
    # permission engine defines its own can($actor, $action, ...), and
    # $object->can('method') called that instead of asking about methods.
    return undef if !UNIVERSAL::can( $storage, 'path_for' );
    ## use critic

    return $storage->path_for($object_key);
}

1;

__END__

=head1 NAME

GPForum::Service::Attachment::Delivery - Authorize an attachment download and hand back a path to stream.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $delivery = GPForum::Service::Attachment::Delivery->new(
        storage => GPForum::Service::Attachment::FilesystemStorage->new,
        store   => $attachment_store,
    );

    my $download = $delivery->download(
        {
            attachment_id  => $attachment_id,
            viewer         => $viewer,
            viewer_user_id => $user_id,
        }
    );
    # $download->{object_path} to stream, or $download->{error} when !ok

=head1 DESCRIPTION

Authorized downloads used to come back with the whole object in a scalar,
which kept a 25 MiB attachment in a worker for the whole request, once in the
scalar and again in the response buffer. Now the access decision comes from
L<GPForum::Service::Attachment::Store> and, when it allows the download, the
storage backend is asked for a path that the caller streams. Only a backend
without C<path_for> has its object read into memory, and none of the shipped
backends takes that branch.

The C<path_for> check uses C<UNIVERSAL::can> by name rather than
C<< $storage->can >>, so a storage double that defines its own C<can> is not
asked the wrong question.

=head1 SUBROUTINES/METHODS

=head2 download

An optional C<< preview => 1280 >> selects the stored aspect-preserving PNG
preview after authorizing the original. Missing previews fall back to the
original. Preview ETags are separate from original download ETags.

Takes the hash reference that
L<GPForum::Service::Attachment::Store/download_for> takes (C<attachment_id>,
C<viewer>, C<viewer_user_id>). When the store refuses, returns its decision
unchanged (C<< ok => 0 >> with C<error> set to C<not_found> or
C<forbidden>). When it allows, returns the decision with C<object_path> added
when the storage can name a path, or C<content> (the object's bytes)
otherwise.

=head2 download_p

L</download> as a promise, with an optional query context last: the
decision, the preview and the object are looked up on the worker's pooled
asynchronous connections.

=head1 DIAGNOSTICS

Refusals are returned, not thrown. A path whose file is missing croaks
("attachment object KEY is missing from storage"), which the workflow logs
and answers as unavailable. Errors from the store or from the storage's
C<path_for> or C<read_object> propagate.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Service::Attachment::Store>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

None known.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
