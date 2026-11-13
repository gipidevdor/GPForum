# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Privacy::DataRightsReview;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -async_await;
use v5.40;

use GPForum::Infrastructure::SqlFunction;
use GPForum::Infrastructure::ResultRow;
use GPForum::X::Unavailable;

has functions => \&GPForum::Infrastructure::SqlFunction::for_service;

our $VERSION = '0.001';

const my $DEFAULT_LIMIT => 50;

__PACKAGE__->requires(qw(schema));

# Each read is written once, as its promise method (ADR 0177), on the
# worker's pooled asynchronous connections or the blocking layer.
GPForum::Infrastructure::SqlFunction->blocking_twins(
    qw(pending_deletion_requests deletion_request deletion_requests_for_user
      export_requests_for_user completed_export_for_user
      pending_export_requests active_holds_for_user active_holds
      erasure_jobs_by_status)
);

async sub pending_deletion_requests_p ( $self, $options, $context = undef ) {
    return await $self->_search_p( _pending_deletions($options), $context );
}

sub _pending_deletions ($options) {
    return (
        'DeletionRequest',
        { status => 'pending' },
        {
            order_by => [ { -asc => 'created_at' } ],
            rows     => $options->{limit} || $DEFAULT_LIMIT,
        }
    );
}

async sub deletion_request_p ( $self, $request_id, $context = undef ) {
    my $row =
      await $self->_functions->row_p( 'privacy_find',
        { source => 'DeletionRequest', id => $request_id, lock_row => 0 },
        $context );
    return GPForum::Infrastructure::ResultRow->from(
        $row ? $row->{document} : undef );
}

async sub deletion_requests_for_user_p ( $self, $user_id, $options,
    $context = undef )
{
    return await $self->_search_p( _deletions_of( $user_id, $options ),
        $context );
}

sub _deletions_of ( $user_id, $options ) {
    return (
        'DeletionRequest',
        {
            requester_user_id => $user_id,
            resource_type     => 'user',
            resource_id       => $user_id,
        },
        {
            order_by => [ { -desc => 'created_at' } ],
            rows     => $options->{limit} || $DEFAULT_LIMIT,
        }
    );
}

async sub export_requests_for_user_p ( $self, $user_id, $options,
    $context = undef )
{
    return await $self->_search_p( _exports_of( $user_id, $options ),
        $context );
}

sub _exports_of ( $user_id, $options ) {
    return (
        'ExportRequest',
        {
            requester_user_id => $user_id,
            subject_user_id   => $user_id,
        },
        {
            order_by => [ { -desc => 'created_at' } ],
            rows     => $options->{limit} || $DEFAULT_LIMIT,
        }
    );
}

async sub completed_export_for_user_p ( $self, $user_id, $export_request_id,
    $context = undef )
{
    my $rows =
      await $self->_search_p( _completed_export( $user_id, $export_request_id ),
        $context );

    return $rows->[0];
}

sub _completed_export ( $user_id, $export_request_id ) {
    return (
        'ExportRequest',
        {
            export_request_id => $export_request_id,
            requester_user_id => $user_id,
            status            => 'completed',
            subject_user_id   => $user_id,
        },
        { rows => 1 },
    );
}

async sub pending_export_requests_p ( $self, $options, $context = undef ) {
    return await $self->_search_p( _pending_exports($options), $context );
}

sub _pending_exports ($options) {
    return (
        'ExportRequest',
        { status => 'pending' },
        {
            order_by => [ { -asc => 'created_at' } ],
            rows     => $options->{limit} || $DEFAULT_LIMIT,
        }
    );
}

async sub active_holds_for_user_p ( $self, $user_id, $options,
    $context = undef )
{
    return await $self->_search_p( _holds_of( $user_id, $options ), $context );
}

sub _holds_of ( $user_id, $options ) {
    return (
        'RetentionHold',
        {
            resource_type => 'user',
            resource_id   => $user_id,
            ends_at       => undef,
        },
        {
            order_by => [ { -desc => 'created_at' } ],
            rows     => $options->{limit} || $DEFAULT_LIMIT,
        }
    );
}

async sub active_holds_p ( $self, $options, $context = undef ) {
    return await $self->_search_p( _holds($options), $context );
}

sub _holds ($options) {
    return (
        'RetentionHold',
        { ends_at => undef },
        {
            order_by => [ { -desc => 'created_at' } ],
            rows     => $options->{limit} || $DEFAULT_LIMIT,
        }
    );
}

async sub erasure_jobs_by_status_p ( $self, $status, $options,
    $context = undef )
{
    return await $self->_search_p( _erasure_jobs( $status, $options ),
        $context );
}

sub _erasure_jobs ( $status, $options ) {
    return (
        'ErasureJob',
        { status => $status },
        {
            order_by => [ { -asc => 'scheduled_at' } ],
            rows     => $options->{limit} || $DEFAULT_LIMIT,
        }
    );
}

async sub _search_p ( $self, $source, $query, $attrs, $context ) {
    return _documents(
        await $self->_functions->rows_p(
            _review_values( $source, $query, $attrs ), $context
        )
    );
}

sub _review_values ( $source, $query, $attrs ) {
    my $order = $attrs->{order_by} || [];
    my $oldest =
         ref $order eq 'ARRAY'
      && ref $order->[0] eq 'HASH'
      && exists $order->[0]{'-asc'};

    return (
        'privacy_review',
        {
            source    => $source,
            query     => $query,
            row_limit => $attrs->{rows},
            oldest    => $oldest
        }
    );
}

sub _documents ($rows) {
    return [ map { GPForum::Infrastructure::ResultRow->from( $_->{document} ) }
          @{$rows} ];
}

sub _functions ($self) {
    return $self->functions // GPForum::X::Unavailable->throw(
        message => 'privacy reviews need the PostgreSQL database' );
}

1;

__END__

=head1 NAME

GPForum::Service::Privacy::DataRightsReview - Read-only queries over deletion and export requests, retention holds and erasure jobs.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $review =
      GPForum::Service::Privacy::DataRightsReview->new( schema => $schema );

    my $pending = $review->pending_deletion_requests( { limit => 20 } );
    my $exports = $review->export_requests_for_user( $user_id, {} );
    my $export =
      $review->completed_export_for_user( $user_id, $export_request_id );

=head1 DESCRIPTION

The read side of the privacy screens: the queues an administrator works
through (pending deletion and export requests, active retention holds,
erasure jobs by status) and a member's own requests. Every list is bounded,
by the C<limit> option or 50, and holds rows rather than hashes. A member's
lists are restricted to requests the member made about themselves, and
C<completed_export_for_user> checks the same, so one member cannot fetch
another's export by its id.

Each list method takes a hash reference of options of which only C<limit>
is read, and returns an array reference of rows.

=head1 SUBROUTINES/METHODS

Each read takes an optional query context last and answers a promise.

=head2 pending_deletion_requests_p

Takes the options. Answers the pending deletion requests, oldest first.

=head2 deletion_request_p

Takes a deletion request id. Answers its row, or undef.

=head2 deletion_requests_for_user_p

Takes a user id and the options. Answers the deletion requests the user
made for their own account, newest first.

=head2 export_requests_for_user_p

Takes a user id and the options. Answers the export requests the user made
about themselves, newest first.

=head2 completed_export_for_user_p

Takes a user id and an export request id. Answers that export request's row
when it is completed and the user both made it and is its subject; undef
otherwise.

=head2 pending_export_requests_p

Takes the options. Answers the pending export requests, oldest first.

=head2 active_holds_for_user_p

Takes a user id and the options. Answers the retention holds on the user's
account that have no C<ends_at>, newest first.

=head2 active_holds_p

Takes the options. Answers every retention hold with no C<ends_at>, newest
first.

=head2 erasure_jobs_by_status_p

Takes a status and the options. Answers the erasure jobs in that status,
earliest C<scheduled_at> first.

=head2 pending_deletion_requests, deletion_request, deletion_requests_for_user, export_requests_for_user, completed_export_for_user, pending_export_requests, active_holds_for_user, active_holds, erasure_jobs_by_status

The blocking twins of the promise methods above (ADR 0177): each runs its
promise method on the blocking layer, the process's own connection, and
returns its answer.

=head1 DIAGNOSTICS

Without the SQL function layer every read throws
L<GPForum::X::Unavailable>; database errors propagate.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Base>, L<Const::Fast>, L<GPForum::Infrastructure::SqlFunction>
and L<GPForum::Infrastructure::ResultRow>.

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
