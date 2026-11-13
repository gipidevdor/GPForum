# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Privacy::DeletionWorkflow;

use GPForum::Infrastructure::EventRecorder;
use GPForum::Service::Clock;
use GPForum::Service::Privacy::Completion;
use GPForum::Service::Privacy::ErasedExports;
use GPForum::Service::Privacy::Erasure;
use GPForum::Service::Privacy::Event;
use GPForum::Service::Privacy::Record;
use Mojo::Base 'GPForum::Service::Privacy::Deletion::Erasure', -signatures;
use v5.40;

use GPForum::Infrastructure::SqlFunction;

has functions => \&GPForum::Infrastructure::SqlFunction::for_service;

our $VERSION = '0.001';

has clock      => sub { return GPForum::Service::Clock->new; };
has id_service => sub {
    require GPForum::Infrastructure::Id;
    return GPForum::Infrastructure::Id->new;
};

# Prepares the event and audit calls each step sends on its transaction.
has recorder => \&GPForum::Infrastructure::EventRecorder::for_service;
__PACKAGE__->requires(qw(schema));

# ADR 0144: the profile pictures (Service::Community::Avatars), whose stored
# files erasure deletes before the rows.
has avatars    => undef;    # optional: without it only the rows go
has record     => sub { return GPForum::Service::Privacy::Record->new; };
has completion => sub {
    my ($self) = @_;

    return GPForum::Service::Privacy::Completion->new( record => $self->record,
    );
};
has erasure => sub {
    my ($self) = @_;

    return GPForum::Service::Privacy::Erasure->new( record => $self->record );
};
has events => sub {
    my ($self) = @_;

    return GPForum::Service::Privacy::Event->new( record => $self->record );
};
has erased_exports => sub {
    my ($self) = @_;

    return GPForum::Service::Privacy::ErasedExports->new(
        schema    => $self->schema,
        functions => $self->functions,
    );
};

1;

__END__

=head1 NAME

GPForum::Service::Privacy::DeletionWorkflow - Deletion requests, their approval, legal holds and the erasure job that anonymizes a member.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $deletion = GPForum::Service::Privacy::DeletionWorkflow->new(
        clock      => $clock,
        id_service => $id_service,
        schema     => $schema,
    );
    my $request = $deletion->request_deletion(
        {
            reason            => 'leaving the forum',
            request_type      => 'anonymize',
            requester_user_id => $user_id,
            resource_id       => $user_id,
            resource_type     => 'user',
        }
    );
    my $approved = $deletion->approve_request(
        $request->{deletion_request_id}, $admin_id, 'verified' );
    if ( $approved && $approved->{ok} ) {
        $deletion->complete_job( $approved->{job}{erasure_job_id}, $admin_id );
    }

=head1 DESCRIPTION

Owns the writes behind a member's deletion: it writes C<deletion_requests>,
C<erasure_jobs> and C<deletion_actions>, anonymizes the member when the job
runs, and records a privacy event and audit entry for each step, built by
L<GPForum::Service::Privacy::Event> and written by
L<GPForum::Infrastructure::EventRecorder>. L<GPForum::Service::Privacy::Workflow>
validates the commands and calls it. Each public method runs in one
transaction, and every step can be repeated: a step already taken is
answered from what is stored rather than done twice, and one found
half-recorded -- a request without its event, a job without its approval
action -- is finished.

A request is C<pending> until approved. A resource has at most one open
(C<pending>, C<approved> or C<held>) request of a type: asking again returns
that request, and concurrent requests settle on one by the unique index
C<idx_deletion_requests_open_resource_unique>: the request that lost the
index rereads and answers the winner's.
Approving locks the request, then schedules one C<pending> erasure job for
it -- unless the resource is under an active retention hold (one with no
C<ends_at>), in which case the request is put on hold instead. Running the
job checks the hold again: under a hold it marks the request C<held> and the
job's C<last_error>, and erases nothing; otherwise it anonymizes the member
(when the resource is a C<user> that exists), revokes their credentials and
sessions, discards the export bundles that copy their data, and marks the
job C<done> and the request C<completed>. The credentials are revoked before
the account is anonymized, the order a login takes its locks in, so an
erasure waits for a login opening a session instead of deadlocking with it;
each credential and session is revoked at the erasure's time, or at its own
C<created_at> when that is later.

Inserts run inside savepoints. A lost race on a unique index reuses the row
the other writer inserted; a collision on a generated id is retried once
with a fresh id.

=head1 SUBROUTINES/METHODS

This class adds no methods of its own. It inherits them from the parts it is
built from, each documented in its own file:

=over 4

=item L<GPForum::Service::Privacy::Deletion::Requests>

C<request_deletion_p>, C<approve_request_p> and their blocking twins.

=item L<GPForum::Service::Privacy::Deletion::Holds>

C<hold_request_p>, C<release_hold_p> and their blocking twins.

=item L<GPForum::Service::Privacy::Deletion::Erasure>

C<complete_job_p> and its blocking twin.

=item L<GPForum::Service::Privacy::Deletion::Core>

The privacy rows and records the others share.

=back

=head1 DIAGNOSTICS

Croaks with the database error when an insert fails for any reason other
than a unique conflict it knows, when a conflict leaves no row to reuse,
and when the retry after an id collision fails too. Every public method
runs in one transaction (C<transaction_p>, on the pooled connections or, for
a blocking caller, on the blocking layer), so any failure, including one recording the event or
the audit entry, rolls the whole step back and propagates. A retention hold
is not a failure: it is reported as C<< ok => 0 >> with
C<< error => 'retention_hold_active' >>. Without the SQL function layer
every step throws L<GPForum::X::Unavailable> (ADR 0177).

=head1 CONFIGURATION AND ENVIRONMENT

None. C<clock>, C<id_service>, C<recorder>, C<record>, C<completion>,
C<erasure>, C<erased_exports> and C<events> have defaults; the application
passes its clock and id service.

=head1 DEPENDENCIES

L<GPForum::Infrastructure::EventRecorder>, L<GPForum::Infrastructure::Id>,
L<GPForum::Infrastructure::SqlFunction>,
L<GPForum::Infrastructure::UniqueConflict>, L<GPForum::X::Conflict>,
L<GPForum::X::Unavailable>,
L<GPForum::Service::Clock>, L<GPForum::Service::Privacy::Completion>,
L<GPForum::Service::Privacy::ErasedExports>,
L<GPForum::Service::Privacy::Erasure>, L<GPForum::Service::Privacy::Event>,
L<GPForum::Service::Privacy::Record>.

Extends L<GPForum::Base>: built without C<schema> it throws
L<GPForum::X::Argument>. C<avatars>, a L<GPForum::Service::Community::Avatars>, is
optional: given one, erasure deletes the stored files of the member's
profile pictures before their rows (ADR 0144).

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
