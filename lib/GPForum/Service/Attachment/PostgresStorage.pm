# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Attachment::PostgresStorage;

use Mojo::Base 'GPForum::Base', -signatures, -async_await;
use v5.40;
use GPForum::Infrastructure::FileAsset;

use Carp qw(croak);
use Const::Fast;
use Digest::SHA;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Service::Attachment::PostgresAsset;
use GPForum::Service::Attachment::Source;
use Mojo::Asset::File;
use Mojo::Promise;
use GPForum::Infrastructure::AsyncWork;

our $VERSION = '0.001';
const my $SHA_BITS => 256;
__PACKAGE__->requires('schema');
has legacy => undef;   # optional filesystem read compatibility during migration
has functions => \&GPForum::Infrastructure::SqlFunction::for_service;

sub transactional ($self) { return 1; }

sub write_object ( $self, $key, $bytes ) {
    my $source =
      GPForum::Service::Attachment::Source->from_input( { content => $bytes } );
    return $self->write_source( $key, $source, $source->checksum );
}

sub write_source ( $self, $key, $source, $checksum ) {
    return $self->schema->txn_do(
        sub {
            my $created = $self->functions->row( 'attachment_object_create',
                _object_values( $key, $source, $checksum ) );
            if ( $created->{created} ) {
                my $number = 0;
                my $digest = Digest::SHA->new($SHA_BITS);
                $source->each_chunk(
                    sub ($chunk) {
                        $digest->add($chunk);
                        $self->functions->row(
                            'attachment_object_chunk_insert',
                            _chunk_values( $key, $number++, $chunk )
                        );
                    }
                );
                _same_digest( $digest, $checksum );
                $self->functions->row( 'attachment_object_finish',
                    { object_key => $key } );
            }
            return _written( $key, $source );
        }
    );
}

# write_object on the worker's pooled asynchronous connections.
async sub write_object_p (
    $self, $key, $bytes,
    $context = undef,
    $functions = undef
  )
{
    my $source =
      GPForum::Service::Attachment::Source->from_input( { content => $bytes } );
    return await $self->write_source_p( $key, $source, $source->checksum,
        $context, $functions );
}

# write_source on the worker's pooled asynchronous connections: in the
# transaction $functions belongs to when one is given, else in one of its
# own. The chunks are read one at a time between the inserts.
async sub write_source_p (
    $self, $key, $source, $checksum,
    $context = undef,
    $functions = undef
  )
{
    return await $self->_transaction_p(
        $functions,
        $context,
        async sub ($scope) {
            my $created =
              await $scope->row_p( 'attachment_object_create',
                _object_values( $key, $source, $checksum ), $context );
            if ( $created->{created} ) {
                my ( $number, $offset ) = ( 0, 0 );
                my $digest = Digest::SHA->new($SHA_BITS);
                while ( $offset < $source->size ) {
                    my $chunk = $source->chunk($offset);
                    $digest->add($chunk);
                    await $scope->row_p( 'attachment_object_chunk_insert',
                        _chunk_values( $key, $number++, $chunk ), $context );
                    $offset += length $chunk;
                }
                _same_digest( $digest, $checksum );
                await $scope->row_p( 'attachment_object_finish',
                    { object_key => $key }, $context );
            }
            return _written( $key, $source );
        }
    );
}

sub _transaction_p ( $self, $functions, $context, $work ) {
    return $work->($functions) if $functions;
    return $self->functions->transaction_p( $work, $context );
}

sub _object_values ( $key, $source, $checksum ) {
    return {
        object_key => $key,
        byte_size  => $source->size,
        checksum   => $checksum,
    };
}

sub _chunk_values ( $key, $number, $chunk ) {
    return {
        object_key   => $key,
        chunk_number => $number,
        data         => $chunk,
    };
}

sub _same_digest ( $digest, $checksum ) {
    croak 'upload changed while being stored'
      if $digest->hexdigest ne $checksum;
    return;
}

sub _written ( $key, $source ) {
    return { ok => 1, object_key => $key, byte_size => $source->size };
}

sub object_info ( $self, $key ) {
    return $self->functions->row( 'attachment_object_info',
        { object_key => $key } );
}

sub exists_object ( $self, $key ) {
    return 1 if $self->object_info($key);
    return $self->legacy ? $self->legacy->exists_object($key) : 0;
}

# exists_object on the worker's pooled asynchronous connections, or on the
# transaction $functions belongs to.
async sub exists_object_p ( $self, $key, $context = undef, $functions = undef )
{
    $functions //= $self->functions;
    return 1
      if await $functions->row_p( 'attachment_object_info',
        { object_key => $key }, $context );
    return $self->legacy ? $self->legacy->exists_object($key) : 0;
}

sub asset_for_p ( $self, $key, $context = undef ) {
    return $self->functions->row_p( 'attachment_object_info',
        { object_key => $key }, $context )->then(
        sub ($info) {
            if ($info) {
                return GPForum::Service::Attachment::PostgresAsset->new(
                    storage       => $self,
                    object_key    => $key,
                    byte_size     => $info->{byte_size},
                    modified_at   => $info->{modified_at},
                    query_context => $context
                );
            }
            croak 'attachment object is missing from storage' if !$self->legacy;
            my $path = $self->legacy->path_for($key);
            return GPForum::Infrastructure::FileAsset->from_path_p($path);
        }
        );
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

sub read_object_p ( $self, $key, $maximum, $context = undef ) {
    return $self->functions->row_p( 'attachment_object_info',
        { object_key => $key }, $context )->then(
        sub ($info) {
            if ( !$info ) {
                return GPForum::Infrastructure::AsyncWork->shared->cpu_p(
                    sub {
                        my $bytes =
                            $self->legacy
                          ? $self->legacy->read_object($key)
                          : undef;
                        croak 'legacy image unavailable or too large'
                          if !defined $bytes || length($bytes) > $maximum;
                        return $bytes;
                    }
                );
            }
            croak 'image exceeds its read limit'
              if $info->{byte_size} > $maximum;
            my $asset = GPForum::Service::Attachment::PostgresAsset->new(
                storage       => $self,
                object_key    => $key,
                byte_size     => $info->{byte_size},
                query_context => $context,
            );
            my $bytes = q{};
            my $next;
            $next = sub {
                return Mojo::Promise->resolve($bytes)
                  if length($bytes) >= $info->{byte_size};
                return $asset->get_chunk_p( length $bytes )->then(
                    sub ($chunk) {
                        croak 'image read ended early' if !length $chunk;
                        $bytes .= $chunk;
                        return $next->();
                    }
                );
            };
            return $next->()->finally( sub { undef $next; return; } );
        }
        );
}

sub read_chunk_p ( $self, $key, $number, $context = undef ) {
    return $self->functions->row_p(
        'attachment_object_chunk',
        {
            object_key   => $key,
            chunk_number => $number,
        },
        $context
    )->then(
        sub ($row) {
            croak "attachment object $key has a missing chunk" if !$row;
            return $row->{data};
        }
    );
}

sub delete_object ( $self, $key ) {
    my $result = $self->functions->row( 'attachment_object_delete',
        { object_key => $key } );
    return $self->_deleted( $key, $result );
}

# delete_object on the worker's pooled asynchronous connections, or on the
# transaction $functions belongs to.
async sub delete_object_p ( $self, $key, $context = undef, $functions = undef )
{
    $functions //= $self->functions;
    return $self->_deleted(
        $key,
        await $functions->row_p(
            'attachment_object_delete', { object_key => $key }, $context
        )
    );
}

# Explicit deletion/erasure also removes a retained legacy copy. Import
# itself never deletes files; a user deletion must not resurrect one.
sub _deleted ( $self, $key, $result ) {
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

=head2 read_object_p

Reads a size-limited object through sequential asynchronous database chunks. Legacy filesystem reads run in a bounded subprocess.

=head2 read_chunk_p

Returns a promise for one immutable database chunk on a separately leased connection.

=head2 asset_for_p

Loads object metadata with native SQL and constructs the streaming asset in the caller. A legacy filesystem object uses asynchronous bounded file reads.

=head2 write_object_p

L</write_object> as a promise, with an optional query context and an
optional transaction call layer last: the object's rows are written on the
worker's pooled asynchronous connections, in that transaction when one is
given.

=head2 write_source_p

L</write_source> as a promise, with an optional query context and an
optional transaction call layer last. The source is read one chunk at a time
between the inserts, and its digest is checked before the object is
finished.

=head2 exists_object_p

L</exists_object> as a promise, with an optional query context and an
optional transaction call layer last.

=head2 delete_object_p

L</delete_object> as a promise, with an optional query context and an
optional transaction call layer last. A retained legacy copy is removed as
well.

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
