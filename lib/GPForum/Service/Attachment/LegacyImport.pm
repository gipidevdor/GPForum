# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Attachment::LegacyImport;

use Mojo::Base 'GPForum::Base', -signatures, -async_await;
use v5.40;
use Carp qw(croak);
use Const::Fast;
use Mojo::Asset::File;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Service::Attachment::Source;
use GPForum::X::Unavailable;

our $VERSION = '0.001';
const my $IMPORT_BATCH => 100;
__PACKAGE__->requires(qw(storage filesystem));
has functions => sub ($self) { return $self->storage->functions; };

# Written once, as its promise method (ADR 0177).
GPForum::Infrastructure::SqlFunction->blocking_twins('run');

# Each object in a transaction of its own, so a failure rolls back that
# object alone and the next run resumes with the rest.
async sub run_p ( $self, $apply = 0, $context = undef ) {
    my ( $after, $count ) = ( q{}, 0 );
    while (1) {
        my $rows = await $self->_functions->rows_p(
            'attachment_object_import_candidates',
            {
                after_key => $after,
                row_limit => $IMPORT_BATCH,
            },
            $context
        );
        last if !@{$rows};
        for my $row ( @{$rows} ) {
            $count += await $self->_functions->transaction_p(
                async sub ($scope) {
                    return await $self->_one_p( $row, $apply, $scope,
                        $context );
                },
                $context
            );
            $after = $row->{object_key};
        }
    }
    return { checked => $count, imported => $apply ? $count : 0 };
}

async sub _one_p ( $self, $row, $apply, $scope, $context ) {

    # Serialize with erasure: deleting metadata after this transaction also
    # cascades the newly imported bytes, including an already-open file.
    my $owner = await $scope->row_p(
        'attachment_find',
        {
            attachment_id => $row->{attachment_id},
            object_key    => undef,
            hold          => 1,
        },
        $context
    );
    return 0 if !$owner || defined $owner->{deleted_at};
    my $source = GPForum::Service::Attachment::Source->new(
        asset => Mojo::Asset::File->new(
            path => $self->filesystem->path_for( $row->{object_key} )
        )
    );
    croak "legacy object $row->{object_key} has the wrong size"
      if !-f $source->asset->path || $source->size != $row->{byte_size};
    my $checksum = $source->checksum;
    croak "legacy object $row->{object_key} has the wrong checksum"
      if defined $row->{checksum} && $checksum ne $row->{checksum};
    if ($apply) {
        await $self->storage->write_source_p( $row->{object_key}, $source,
            $checksum, $context, $scope );
    }
    return 1;
}

sub _functions ($self) {
    return $self->functions // GPForum::X::Unavailable->throw(
        message => 'the attachment import needs the PostgreSQL database' );
}

1;

__END__

=head1 NAME

GPForum::Service::Attachment::LegacyImport - Resumable filesystem import.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $result = $import->run(1);

=head1 DESCRIPTION

Checks metadata, SHA-256 and file size before copying each object in bounded
chunks. Existing complete objects are skipped using keyset pagination. A
failure rolls back that object; the next run resumes with remaining objects.
Never removes a legacy file or changes its content review status.

=head1 SUBROUTINES/METHODS

=head2 new

Mojo::Base constructor. C<storage> (a
L<GPForum::Service::Attachment::PostgresStorage>) and C<filesystem> (the
legacy L<GPForum::Service::Attachment::FilesystemStorage>) are required.
C<functions> defaults to the storage's call layer.

=head2 run_p

Takes a boolean apply flag, false for validation only, and an optional
query context. Answers checked and imported counts; fails on a missing,
changed or unreadable legacy file.

=head2 run

The blocking twin of L</run_p> (ADR 0177): the import on the blocking layer,
the process's own connection, for the command line.

=head1 DIAGNOSTICS

Stops on a missing file, size mismatch, changed digest or database failure.

=head1 CONFIGURATION AND ENVIRONMENT

The composition layer supplies the schema, storage and source policy.

=head1 DEPENDENCIES

L<Mojo::Base> and the composed Good Phorum services.

=head1 INCOMPATIBILITIES

Retains filesystem copies and preserves existing review status.

=head1 BUGS AND LIMITATIONS

Retains filesystem copies and preserves existing review status.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. BSD-3-Clause.

=cut
