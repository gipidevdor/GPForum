# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Attachment::PostgresStorage;

use Mojo::Base 'GPForum::Base', -signatures;
use v5.40;

use Carp qw(croak);
use Const::Fast;
use Digest::SHA;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Service::Attachment::PostgresAsset;
use GPForum::Service::Attachment::Source;
use Mojo::Asset::File;

our $VERSION = '0.001';
const my $SHA_BITS => 256;
__PACKAGE__->requires('schema');
has legacy => undef;   # optional filesystem read compatibility during migration
has functions => sub ($self) {
    return GPForum::Infrastructure::SqlFunction->for_schema( $self->schema );
};

sub transactional ($self) { return 1; }

sub write_object ( $self, $key, $bytes ) {
    my $source =
      GPForum::Service::Attachment::Source->from_input( { content => $bytes } );
    return $self->write_source( $key, $source, $source->checksum );
}

sub write_source ( $self, $key, $source, $checksum ) {
    return $self->schema->txn_do(
        sub {
            my $created = $self->functions->row(
                'attachment_object_create',
                {
                    object_key => $key,
                    byte_size  => $source->size,
                    checksum   => $checksum,
                }
            );
            if ( $created->{created} ) {
                my $number = 0;
                my $digest = Digest::SHA->new($SHA_BITS);
                $source->each_chunk(
                    sub ($chunk) {
                        $digest->add($chunk);
                        $self->functions->row(
                            'attachment_object_chunk_insert',
                            {
                                object_key   => $key,
                                chunk_number => $number++,
                                data         => $chunk,
                            }
                        );
                    }
                );
                croak 'upload changed while being stored'
                  if $digest->hexdigest ne $checksum;
                $self->functions->row( 'attachment_object_finish',
                    { object_key => $key } );
            }
            return { ok => 1, object_key => $key, byte_size => $source->size };
        }
    );
}

sub object_info ( $self, $key ) {
    return $self->functions->row( 'attachment_object_info',
        { object_key => $key } );
}

sub exists_object ( $self, $key ) {
    return 1 if $self->object_info($key);
    return $self->legacy ? $self->legacy->exists_object($key) : 0;
}

sub asset_for ( $self, $key ) {
    if ( my $info = $self->object_info($key) ) {
        return GPForum::Service::Attachment::PostgresAsset->new(
            storage     => $self,
            object_key  => $key,
            byte_size   => $info->{byte_size},
            modified_at => $info->{modified_at},
        );
    }
    return Mojo::Asset::File->new( path => $self->legacy->path_for($key) )
      if $self->legacy && $self->legacy->exists_object($key);
    croak "attachment object $key is missing from storage";
}

sub read_chunk ( $self, $key, $number ) {
    my $row = $self->functions->row(
        'attachment_object_chunk',
        {
            object_key   => $key,
            chunk_number => $number,
        }
    );
    croak "attachment object $key has a missing chunk" if !$row;
    return $row->{data};
}

sub read_object ( $self, $key ) { return $self->asset_for($key)->slurp; }

sub delete_object ( $self, $key ) {
    my $result = $self->functions->row( 'attachment_object_delete',
        { object_key => $key } );

    # Explicit deletion/erasure also removes a retained legacy copy. Import
    # itself never deletes files; a user deletion must not resurrect one.
    if ( $self->legacy ) { $self->legacy->delete_object($key); }
    return { ok => 1, object_key => $key, deleted => $result->{deleted} };
}

1;

__END__

=head1 NAME

GPForum::Service::Attachment::PostgresStorage - Transactional binary storage.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $storage = GPForum::Service::Attachment::PostgresStorage->new(schema => $schema);

=head1 DESCRIPTION

Stores immutable objects in logged PostgreSQL tables as one MiB bytea chunks.
Writes, completeness validation and publication share the caller's connection
and transaction. Reads use the narrow versioned SQL API. Legacy filesystem
objects stay readable until imported; new writes always go to PostgreSQL.

=head1 SUBROUTINES/METHODS

=head2 transactional

Returns true: an enclosing rollback removes new objects without compensating deletes.


=head2 write_object

Stores scalar bytes as a complete immutable object in a transaction.


=head2 write_source

Stores a source in bounded chunks and verifies its digest and completeness before publication.


=head2 object_info

Returns size, SHA-256 and creation time for a complete database object.


=head2 exists_object

Checks the database first, then the configured legacy filesystem.


=head2 asset_for

Returns a seekable database asset or a legacy file asset; fails when the object is missing.


=head2 read_chunk

Reads one complete database chunk by the composite primary key.


=head2 read_object

Returns all bytes for existing small-image consumers.


=head2 delete_object

Deletes the database object and cascades its chunks in the current transaction. An explicit deletion also removes a retained legacy copy.

=head1 DIAGNOSTICS

Propagates database failures; rejects changed source bytes and conflicting object keys.

=head1 CONFIGURATION AND ENVIRONMENT

The composition layer supplies the schema, storage and source policy.

=head1 DEPENDENCIES

L<Mojo::Base> and the composed Good Phorum services.

=head1 INCOMPATIBILITIES

Requires applied binary-storage migrations; legacy files remain outside PostgreSQL until imported.

=head1 BUGS AND LIMITATIONS

Requires applied binary-storage migrations; legacy files remain outside PostgreSQL until imported.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. BSD-3-Clause.

=cut
