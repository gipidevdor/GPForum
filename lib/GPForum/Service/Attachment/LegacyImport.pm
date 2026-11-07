# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Attachment::LegacyImport;

use Mojo::Base 'GPForum::Base', -signatures;
use v5.40;
use Carp qw(croak);
use Mojo::Asset::File;
use GPForum::Service::Attachment::Source;

our $VERSION = '0.001';
__PACKAGE__->requires(qw(storage filesystem));

sub run ( $self, $apply = 0 ) {
    my ( $after, $count ) = ( q{}, 0 );
    while (1) {
        my $rows = $self->storage->functions->rows(
            'attachment_object_import_candidates',
            {
                after_key => $after,
                row_limit => 100,
            }
        );
        last if !@{$rows};
        for my $row ( @{$rows} ) {
            $count += $self->storage->schema->txn_do(
                sub { return $self->_one( $row, $apply ); } );
            $after = $row->{object_key};
        }
    }
    return { checked => $count, imported => $apply ? $count : 0 };
}

sub _one ( $self, $row, $apply ) {

    # Serialize with erasure: deleting metadata after this transaction also
    # cascades the newly imported bytes, including an already-open file.
    my $owner = $self->storage->functions->row(
        'attachment_find',
        {
            attachment_id => $row->{attachment_id},
            object_key    => undef,
            hold          => 1,
        }
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
        $self->storage->write_source( $row->{object_key}, $source, $checksum );
    }
    return 1;
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

=head2 run

Takes a boolean apply flag, false for validation only. Returns checked and
imported counts; fails on a missing, changed or unreadable legacy file.

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
