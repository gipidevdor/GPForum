# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Privacy::Record;

use Mojo::Base -base, -signatures;
use v5.40;

use GPForum::Infrastructure::Row qw(column_of);

our $VERSION = '0.001';

sub column ( $, $row, $name ) {
    if ( ref $row eq 'HASH' ) {
        return $row->{$name};
    }

    return column_of( $row, $name );
}

sub request_payload ( $self, $request ) {
    return {
        deletion_request_id => $self->column( $request, 'deletion_request_id' ),
        request_type        => $self->column( $request, 'request_type' ),
        resource_id         => $self->column( $request, 'resource_id' ),
        resource_type       => $self->column( $request, 'resource_type' ),
        status              => $self->column( $request, 'status' ),
    };
}

sub job_hash ( $self, $job ) {
    if ( !$job ) {
        return undef;
    }

    return {
        completed_at        => $self->column( $job, 'completed_at' ),
        deletion_request_id => $self->column( $job, 'deletion_request_id' ),
        erasure_job_id      => $self->column( $job, 'erasure_job_id' ),
        last_error          => $self->column( $job, 'last_error' ),
        scheduled_at        => $self->column( $job, 'scheduled_at' ),
        status              => $self->column( $job, 'status' ),
    };
}

sub request_hash ( $self, $request ) {
    if ( !$request ) {
        return undef;
    }

    return {
        completed_at        => $self->column( $request, 'completed_at' ),
        created_at          => $self->column( $request, 'created_at' ),
        deletion_request_id => $self->column( $request, 'deletion_request_id' ),
        reason              => $self->column( $request, 'reason' ),
        request_type        => $self->column( $request, 'request_type' ),
        requester_user_id   => $self->column( $request, 'requester_user_id' ),
        resource_id         => $self->column( $request, 'resource_id' ),
        resource_type       => $self->column( $request, 'resource_type' ),
        status              => $self->column( $request, 'status' ),
    };
}

1;

__END__

=head1 NAME

GPForum::Service::Privacy::Record - Privacy row accessors.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $status = $records->column( $request, 'status' );

=head1 DESCRIPTION

Reads deletion-request and erasure-job hashes or DBIx::Class-like rows. It
does not persist privacy state. L<GPForum::Service::Privacy::DeletionWorkflow>
keeps transactions and locks. Event and audit hashes live in
L<GPForum::Service::Privacy::Event>.

=head1 SUBROUTINES/METHODS

=head2 column

Reads a named field from a hash or row.

=head2 request_payload

Returns the canonical deletion-request event payload.

=head2 job_hash

Copies erasure-job fields into a plain hash.

=head2 request_hash

Copies deletion-request fields into a plain hash.

=head1 DIAGNOSTICS

Missing rows yield undef columns. Missing jobs yield undef hashes.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

Uses L<Mojo::Base>.

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
