# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Attachment::ScanQueue;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -signatures, -async_await;
use v5.40;

use GPForum::Service::Attachment::Record;
use GPForum::Service::Clock;
use GPForum::Infrastructure::SqlFunction;
use GPForum::X::Unavailable;

our $VERSION = '0.001';

const my $AGE_PENDING => 'uploaded_at';

has clock  => sub { return GPForum::Service::Clock->new; };
has record => sub { return GPForum::Service::Attachment::Record->new; };
__PACKAGE__->requires(qw(schema));
has functions => \&GPForum::Infrastructure::SqlFunction::for_service;

# Written once, as its promise method (ADR 0177).
GPForum::Infrastructure::SqlFunction->blocking_twins(
    qw(pending_scan_ids unscanned_clean_ids confirm_clean record_scan_failure));

# Uploads no scanner has decided yet, oldest first: what the scheduled rescan
# retries once the antivirus answers again (ADR 0108).
async sub pending_scan_ids_p ( $self, $limit, $context = undef ) {
    return await $self->_ids_by_attempts_p( $AGE_PENDING, $limit, $context );
}

# Files served on a format check alone, oldest first: the backfill's work
# once an antivirus is configured (ADR 0108).
async sub unscanned_clean_ids_p ( $self, $limit, $context = undef ) {
    return await $self->_ids_by_attempts_p( 'created_at', $limit, $context );
}

# Fewest scan attempts first, then oldest by the age column, then id.
async sub _ids_by_attempts_p ( $self, $age_column, $limit, $context ) {
    my $rows = await $self->_functions->rows_p(
        'attachment_scan_queue',
        {
            pending   => $age_column eq $AGE_PENDING ? 1 : 0,
            row_limit => $limit
        },
        $context
    );
    return [ map { $_->{attachment_id} } @{$rows} ];
}

# Records the engine that confirmed a format-checked file clean. Nothing else
# changes -- the file was already served -- and only a row still waiting for
# that confirmation is touched, so a quarantine that won a race stands.
async sub confirm_clean_p ( $self, $input, $context = undef ) {
    my $updated = await $self->_functions->row_p(
        'attachment_confirm_clean',
        {
            attachment_id => $input->{attachment_id},
            scan_engine   => $input->{scan_engine},
            scanned_at    => $self->clock->now_iso8601
        },
        $context
    );

    return {
        attachment_id => $input->{attachment_id},
        confirmed     => ( $updated->{changed_count} + 0 ) ? 1 : 0,
        scan_engine   => $input->{scan_engine},
    };
}

# A scheduled scan that failed on this file: counted, with the error kept for
# the operator. The next runs take files with fewer attempts first.
async sub record_scan_failure_p ( $self, $attachment_id, $error,
    $context = undef )
{
    my $failed = await $self->_functions->row_p( 'attachment_scan_failure',
        { attachment_id => $attachment_id, error => $error }, $context );
    return $failed->{changed_count} ? 1 : 0;
}

sub _functions ($self) {
    return $self->functions // GPForum::X::Unavailable->throw(
        message => 'the attachment scan queue needs the PostgreSQL database' );
}

1;

__END__

=head1 NAME

GPForum::Service::Attachment::ScanQueue - The scheduled rescan's and the antivirus backfill's work on attachment rows.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $queue = GPForum::Service::Attachment::ScanQueue->new(
        schema => $schema );

    for my $attachment_id ( @{ $queue->pending_scan_ids(50) } ) {
        ...;    # scan it again; on failure:
        $queue->record_scan_failure( $attachment_id, $error );
    }
    for my $attachment_id ( @{ $queue->unscanned_clean_ids(50) } ) {
        ...;    # scan it; when the engine finds it clean:
        $queue->confirm_clean(
            { attachment_id => $attachment_id, scan_engine => 'clamd' } );
    }

=head1 DESCRIPTION

The queues of ADR 0108, over the C<attachments> table: the uploads no
scanner has decided yet, which the scheduled rescan retries once the
antivirus answers again, and the files served on a format check alone,
which the backfill scans once an antivirus is configured. Both are taken
fewest scan attempts first, so a file that keeps failing does not hold up
the others. Verdicts themselves, with their events, are written by
L<GPForum::Service::Attachment::Store/record_scan_p>; the store also answers
every method here by delegation, which is how the scanner and the
scheduled jobs reach it.

=head1 SUBROUTINES/METHODS

=head2 new

Mojo::Base constructor. C<schema> is required. C<functions> (the
schema's L<GPForum::Infrastructure::SqlFunction>), C<clock>
(L<GPForum::Service::Clock>) and C<record>
(L<GPForum::Service::Attachment::Record>) have defaults.

=head2 pending_scan_ids_p

Takes a limit and an optional query context. Answers an array reference of the ids of undeleted
C<uploaded> attachments whose scan is still C<pending>, fewest scan
attempts first, then oldest upload, then id.

=head2 unscanned_clean_ids_p

Takes a limit and an optional query context. Answers an array reference of the ids of undeleted
C<available> attachments marked C<clean> on a format check alone (no scan
engine, or C<format-check>), fewest scan attempts first, then oldest, then
id.

=head2 confirm_clean_p

Takes a hash reference with C<attachment_id> and C<scan_engine>, and an
optional query context. Records the
engine that confirmed a format-checked file clean, clears C<scan_error> and
stamps C<scanned_at>; nothing else changes, since the file was already
served. Only a row still waiting for that confirmation is touched, so a
quarantine that won a race stands. Answers
C<< { attachment_id, confirmed => 1 or 0, scan_engine } >>.

=head2 record_scan_failure_p

Takes an attachment id, an error message and an optional query context.
Adds one to C<scan_attempts> and keeps the first 500 characters of the
error in C<scan_error>. Answers 1, or 0 for an unknown id.

=head2 pending_scan_ids, unscanned_clean_ids, confirm_clean, record_scan_failure

The blocking twins of the promise methods above (ADR 0177): each runs its
promise method on the blocking layer and returns its answer.

=head1 DIAGNOSTICS

Database errors propagate; without the function layer every method raises
L<GPForum::X::Unavailable>. An unknown id is answered, not thrown.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<Const::Fast>, L<GPForum::Base>, L<GPForum::Service::Attachment::Record>,
L<GPForum::Infrastructure::SqlFunction>, L<GPForum::Service::Clock>.

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
