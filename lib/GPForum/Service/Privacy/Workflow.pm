# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Privacy::Workflow;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -signatures, -async_await;
use v5.40;

use GPForum::Infrastructure::SqlFunction;
use GPForum::Infrastructure::Text qw(trimmed);
use GPForum::Service::Privacy::ErasedExports;
use GPForum::Service::WorkflowResult qw(log_error workflow_result);
use GPForum::Infrastructure::Row     qw(column_of);

use Scalar::Util qw(blessed);

our $VERSION = '0.001';

const my $EXPORT_NOT_FOUND   => 'export request not found';
const my $DELETION_NOT_FOUND => 'deletion request not found';
const my $HOLD_NOT_FOUND     => 'retention hold not found';
const my $JOB_NOT_FOUND      => 'erasure job not found';

has command_idempotency => undef;    # optional: writes run unlogged without one
__PACKAGE__->requires(qw(deletion_workflow export_builder hold_store));
has logger => undef;                 # optional: errors are dropped without one

# Orders an export against the member's erasure; none for an export store
# without a schema.
has erased_exports => sub {
    my ($self) = @_;
    my $builder = $self->export_builder;
    if ( !$builder || !$builder->can('schema') || !$builder->schema ) {
        return undef;
    }

    return GPForum::Service::Privacy::ErasedExports->new(
        schema => $builder->schema );
};

# The stores' call layer (Infrastructure::SqlFunction): the deletion
# store's, or the export store's.
has functions => sub ($self) {
    return _functions_of( $self->deletion_workflow )
      // _functions_of( $self->export_builder );
};

# Each command is written once, as its promise method (ADR 0177); the
# stores and the command log it awaits block with its blocking twin.
GPForum::Infrastructure::SqlFunction->blocking_twins(
    qw(request_export request_deletion approve_deletion hold_deletion
      release_hold run_erasure_job)
);
GPForum::Infrastructure::SqlFunction->blocking_parts(
    qw(command_idempotency deletion_workflow erased_exports export_builder
      hold_store)
);

# With the command log, its row, the account's share lock, the export
# request and its completed bundle commit in one transaction; without it,
# the export runs in one of its own.
async sub request_export_p ( $self, $input, $context = undef ) {
    my $invalid = $self->_missing_field( $input, 'command_id' );
    return $invalid if $invalid;

    my $export_p = async sub ( $scope = undef ) {
        return await $self->_complete_export_p( $scope, $input->{user_id},
            $context );
    };
    my $command_log = $self->command_idempotency;
    if ( !$command_log ) {
        return await $self->_run_store_p( $EXPORT_NOT_FOUND,
            async sub { return await $self->_exported_p( $export_p, $context ) }
        );
    }

    my $run_p = async sub ( $scope = undef ) {
        return await $self->_run_store_p( $EXPORT_NOT_FOUND,
            async sub { return await $export_p->($scope) } );
    };
    my $result;
    try {
        $result =
          await $command_log->result_of_p(
            _export_command( $input, run_p => $run_p ), $context );
    }
    catch ($error) {
        $result = $self->_command_log_failed($error);
    };

    return $result;
}

# The export in a transaction of its own; an export store without the
# function layer (a double) runs it as it is.
async sub _exported_p ( $self, $export_p, $context ) {
    my $functions = _functions_of( $self->export_builder );
    return await $export_p->() if !$functions;

    return await $functions->transaction_p( $export_p, $context );
}

sub _export_command ( $input, %runs ) {
    return {
        actor_id     => $input->{user_id},
        command_id   => $input->{command_id},
        command_type => 'privacy.export',
        request      => { user_id => $input->{user_id} },
        %runs,
    };
}

sub _command_log_failed ( $self, $error ) {
    log_error( $self->logger, "privacy command log failed: $error" );
    return workflow_result(
        error  => 'privacy store failed',
        status => 'failed',
    );
}

# An anonymize request for the member, in one transaction.
async sub request_deletion_p ( $self, $input, $context = undef ) {
    my $command = _deletion_command($input);
    my $invalid = $self->_missing_field( $command, 'reason' );
    return $invalid if $invalid;

    return await $self->_commanded_store_p(
        $input,
        $DELETION_NOT_FOUND,
        async sub {
            return await $self->deletion_workflow->request_deletion_p( $command,
                $context );
        },
    );
}

sub _deletion_command ($input) {
    return {
        reason            => trimmed( $input->{reason} ),
        request_type      => 'anonymize',
        requester_user_id => $input->{user_id},
        resource_id       => $input->{user_id},
        resource_type     => 'user',
    };
}

# The request approved, or held under an active hold, in one transaction.
async sub approve_deletion_p ( $self, $input, $context = undef ) {
    my $command = _review_command($input);
    my $invalid = $self->_missing_field( $command, 'reason' );
    return $invalid if $invalid;

    return await $self->_commanded_store_p(
        $input,
        $DELETION_NOT_FOUND,
        async sub {
            return await $self->deletion_workflow->approve_request_p(
                @{$command}{qw(request_id actor_user_id reason)}, $context );
        },
    );
}

sub _review_command ($input) {
    return {
        actor_user_id => $input->{actor_user_id},
        reason        => trimmed( $input->{reason} ),
        request_id    => $input->{request_id},
    };
}

# A hold on the request's resource, then the request held under it: the
# hold is made in a savepoint of the transaction that locks and holds the
# request.
async sub hold_deletion_p ( $self, $input, $context = undef ) {
    my $command = _review_command($input);
    my $invalid = $self->_missing_field( $command, 'reason' );
    return $invalid if $invalid;

    return await $self->_commanded_store_p(
        $input,
        $DELETION_NOT_FOUND,
        async sub {
            return await $self->deletion_workflow->hold_request_p(
                @{$command}{qw(request_id actor_user_id reason)},
                async sub ( $request, $scope ) {
                    return await $self->hold_store->create_hold_p(
                        _hold_input( $command, $request ),
                        $context, $scope );
                },
                $context
            );
        },
    );
}

sub _hold_input ( $command, $request ) {
    return {
        created_by    => $command->{actor_user_id},
        reason        => $command->{reason},
        resource_id   => column_of( $request, 'resource_id' ),
        resource_type => column_of( $request, 'resource_type' ),
    };
}

# A hold ended, and the request it held given back to where it found it.
# A hold already ended, or not in force, is not found: a repeated release
# changes nothing.
async sub release_hold_p ( $self, $input, $context = undef ) {
    my $command = _release_command($input);
    my $invalid = $self->_missing_field( $command, 'reason' );
    return $invalid if $invalid;

    return await $self->_commanded_store_p(
        $input,
        $HOLD_NOT_FOUND,
        async sub {
            return await $self->deletion_workflow->release_hold_p(
                @{$command}{qw(hold_id actor_user_id reason)}, $context );
        },
    );
}

sub _release_command ($input) {
    return {
        actor_user_id => $input->{actor_user_id},
        hold_id       => $input->{hold_id},
        reason        => trimmed( $input->{reason} ),
    };
}

# The erasure is a staff request, not a background job: the whole of it,
# the profile pictures' stored objects included, in one transaction.
async sub run_erasure_job_p ( $self, $input, $context = undef ) {
    return await $self->_commanded_store_p(
        $input,
        $JOB_NOT_FOUND,
        async sub {
            return await $self->deletion_workflow->complete_job_p(
                @{$input}{qw(job_id actor_user_id)}, $context );
        },
    );
}

# The member's account row is held for share from before the request until
# the export commits, so an erasure either waits for the export and then
# discards it, or has committed and the export finds the member erased.
async sub _complete_export_p ( $self, $scope, $user_id, $context ) {
    my $guard = $self->erased_exports;
    return undef
      if $guard && !await $guard->may_export_p( $user_id, $context, $scope );

    my $builder = $self->export_builder;
    my $request =
      await $builder->request_user_export_p( $user_id, $context, $scope );

    return _export_answer(
        $request,
        await $builder->complete_user_export_p(
            $request->{export_request_id},
            undef, $context, $scope
        )
    );
}

sub _export_answer ( $request, $completed ) {
    return $completed || $request;
}

sub _missing_field ( $, $input, $name ) {
    if ( length trimmed( $input->{$name} ) ) {
        return undef;
    }

    return workflow_result(
        errors => { $name => "$name is required" },
        status => 'invalid',
    );
}

async sub _commanded_store_p ( $self, $input, $not_found, $code ) {
    my $invalid = $self->_missing_field( $input, 'command_id' );
    return $invalid if $invalid;

    return await $self->_run_store_p( $not_found, $code );
}

sub _functions_of ($store) {
    return undef if !blessed $store || !$store->can('functions');
    return $store->functions;
}

# A store that dies fails the write and is logged; one that answers nothing
# is not found; one that answers ok => 0 was blocked, a conflict.
async sub _run_store_p ( $self, $not_found, $code ) {
    my ( $value, $failed );
    try {
        $value = await $code->();
    }
    catch ($error) {
        $failed = $self->_store_failed($error);
    };

    return $failed // _stored( $not_found, $value );
}

sub _store_failed ( $self, $error ) {
    log_error( $self->logger, "privacy write failed: $error" );
    return workflow_result(
        error  => 'privacy store failed',
        status => 'failed',
    );
}

sub _stored ( $not_found, $value ) {
    if ( !$value ) {
        return workflow_result(
            error  => $not_found,
            status => 'not_found',
        );
    }
    if ( ref $value eq 'HASH' && exists $value->{ok} && !$value->{ok} ) {
        return workflow_result(
            error  => $value->{error},
            status => 'conflict',
            stored => $value,
        );
    }

    return workflow_result(
        status => 'ok',
        stored => $value,
    );
}

1;

__END__

=head1 NAME

GPForum::Service::Privacy::Workflow - Privacy export, deletion, and hold writes.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $result = $workflow->request_deletion(
        {
            reason  => $reason,
            user_id => $user_id,
        }
    );

=head1 DESCRIPTION

Application boundary for member export/deletion requests and staff approval,
legal-hold, and erasure commands. Validates required fields, orchestrates
existing privacy stores, and returns a normalized result hash. Stores keep
transaction, event, audit, and outbox ownership.

=head1 SUBROUTINES/METHODS

Each command takes its input hash and an optional query context, and
answers a promise of the workflow result.

=head2 request_export_p

Creates and completes a user export bundle when a command id is present:
the command log's row, the account's share lock, the export request and its
completed bundle commit in one transaction; without a command log the
export runs in one of its own. When the export store has a schema, the
export first holds the member's account row through
L<GPForum::Service::Privacy::ErasedExports/may_export_p> for the rest of its
transaction, so an erasure running at the same time either waits for it and
discards the bundle or has committed already; an erased or unknown member
gets C<not_found> and no export.

=head2 request_deletion_p

Creates an anonymize deletion request when a command id and reason are
present, in one transaction. An open request for the same resource is
reused.

=head2 approve_deletion_p

Approves a pending deletion request, or reports an active hold as conflict,
when a command id and reason are present, in one transaction.

=head2 hold_deletion_p

Creates a retention hold and marks the deletion request held when a command
id and reason are present: the hold is made in a savepoint of the
transaction that locks and holds the request.

=head2 release_hold_p

Ends a retention hold and gives the deletion request it held back to
C<approved> or C<pending>, when a command id and a reason are present
(L<GPForum::Service::Privacy::DeletionWorkflow/release_hold_p>). A hold not
in force answers C<not_found>.

=head2 run_erasure_job_p

Completes an erasure job, or reports an active hold as conflict, when a
command id is present: the whole erasure, the profile pictures' stored
objects included, in one transaction.

=head2 request_export, request_deletion, approve_deletion, hold_deletion, release_hold, run_erasure_job

The blocking twins of the promise methods above (ADR 0177): each runs its
promise method on a copy whose stores and command log block, the process's
own connection and the transaction it holds, and returns its answer.

=head1 DIAGNOSTICS

Returns C<invalid>, C<not_found>, C<conflict>, or C<failed> statuses instead of
throwing for expected write outcomes. Unexpected store or command-log
exceptions are logged and mapped to C<failed>.

=head1 CONFIGURATION AND ENVIRONMENT

Uses deletion, export, hold, and review services supplied by the composition
root. C<erased_exports> defaults to one over the export store's schema, and
to none when the store has no schema.

=head1 DEPENDENCIES

Uses L<GPForum::Base>, L<GPForum::Infrastructure::SqlFunction> and
L<GPForum::Service::Privacy::ErasedExports>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Command-id is required for export, deletion, approval, hold, and erasure
writes. Open deletion requests, pending exports, and active holds replay on
retry. The same export C<command_id> replays from C<command_log> after the
bundle is already completed.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
