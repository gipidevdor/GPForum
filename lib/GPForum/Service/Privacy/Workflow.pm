# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Privacy::Workflow;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -signatures, -async_await;
use v5.40;

use GPForum::Infrastructure::Text qw(trimmed);
use GPForum::Service::Privacy::ErasedExports;
use GPForum::Service::WorkflowResult qw(log_error workflow_result);
use GPForum::Infrastructure::Row     qw(column_of);

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

sub request_export ( $self, $input ) {
    my $invalid = $self->_missing_field( $input, 'command_id' );
    if ($invalid) {
        return $invalid;
    }

    my $run = sub {
        return $self->_run_store( $EXPORT_NOT_FOUND,
            sub { return $self->_complete_export( $input->{user_id} ); } );
    };
    if ( !$self->command_idempotency ) {
        return $run->();
    }

    my $result;
    try {
        $result =
          $self->command_idempotency->result_of(
            _export_command( $input, run => $run ) );
    }
    catch ($error) {
        return $self->_command_log_failed($error);
    };

    return $result;
}

# request_export on the worker's pooled asynchronous connections: with the
# command log, its row, the account's share lock, the export request and
# its completed bundle commit in one transaction; without it, the export
# runs in one of its own. An export store without the function layer
# answers through the blocking write.
async sub request_export_p ( $self, $input, $context = undef ) {
    my $invalid = $self->_missing_field( $input, 'command_id' );
    return $invalid if $invalid;
    my $functions = _functions_of( $self->export_builder );
    return $self->request_export($input) if !$functions;

    my $run_p = async sub ($scope) {
        return await $self->_run_store_p(
            $EXPORT_NOT_FOUND,
            async sub {
                return await $self->_complete_export_p( $scope,
                    $input->{user_id}, $context );
            }
        );
    };
    if ( !$self->command_idempotency ) {
        return await $self->_run_store_p(
            $EXPORT_NOT_FOUND,
            async sub {
                return await $functions->transaction_p(
                    async sub ($scope) {
                        return await $self->_complete_export_p( $scope,
                            $input->{user_id}, $context );
                    },
                    $context
                );
            }
        );
    }

    my $result;
    try {
        $result =
          await $self->command_idempotency->result_of_p(
            _export_command( $input, run_p => $run_p ), $context );
    }
    catch ($error) {
        $result = $self->_command_log_failed($error);
    };

    return $result;
}

sub _export_command ( $input, $key, $run ) {
    return {
        actor_id     => $input->{user_id},
        command_id   => $input->{command_id},
        command_type => 'privacy.export',
        request      => { user_id => $input->{user_id} },
        $key         => $run,
    };
}

sub _command_log_failed ( $self, $error ) {
    log_error( $self->logger, "privacy command log failed: $error" );
    return workflow_result(
        error  => 'privacy store failed',
        status => 'failed',
    );
}

sub request_deletion ( $self, $input ) {
    my $command = _deletion_command($input);
    my $invalid = $self->_missing_field( $command, 'reason' );
    if ($invalid) {
        return $invalid;
    }

    return $self->_commanded_store( $input, $DELETION_NOT_FOUND,
        sub { return $self->deletion_workflow->request_deletion($command); },
    );
}

# request_deletion in one transaction on the worker's pooled asynchronous
# connections.
async sub request_deletion_p ( $self, $input, $context = undef ) {
    return $self->request_deletion($input) if !$self->_native_deletion;
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

sub approve_deletion ( $self, $input ) {
    my $command = _review_command($input);
    my $invalid = $self->_missing_field( $command, 'reason' );
    if ($invalid) {
        return $invalid;
    }

    return $self->_commanded_store(
        $input,
        $DELETION_NOT_FOUND,
        sub {
            return $self->deletion_workflow->approve_request(
                @{$command}{qw(request_id actor_user_id reason)} );
        },
    );
}

# approve_deletion in one transaction on the worker's pooled asynchronous
# connections.
async sub approve_deletion_p ( $self, $input, $context = undef ) {
    return $self->approve_deletion($input) if !$self->_native_deletion;
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

# A hold on the request's resource, then the request held under it.
sub hold_deletion ( $self, $input ) {
    my $command = _review_command($input);
    my $invalid = $self->_missing_field( $command, 'reason' );
    if ($invalid) {
        return $invalid;
    }

    return $self->_commanded_store(
        $input,
        $DELETION_NOT_FOUND,
        sub {
            return $self->deletion_workflow->hold_request(
                @{$command}{qw(request_id actor_user_id reason)},
                sub ($request) {
                    return $self->hold_store->create_hold(
                        _hold_input( $command, $request ) );
                },
            );
        },
    );
}

# hold_deletion in one transaction on the worker's pooled asynchronous
# connections: the hold is made in a savepoint of the request's own.
async sub hold_deletion_p ( $self, $input, $context = undef ) {
    return $self->hold_deletion($input)
      if !$self->_native_deletion || !$self->hold_store->can('create_hold_p');
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
sub release_hold ( $self, $input ) {
    my $command = _release_command($input);
    my $invalid = $self->_missing_field( $command, 'reason' );
    if ($invalid) {
        return $invalid;
    }

    return $self->_commanded_store(
        $input,
        $HOLD_NOT_FOUND,
        sub {
            return $self->deletion_workflow->release_hold(
                @{$command}{qw(hold_id actor_user_id reason)} );
        },
    );
}

# release_hold in one transaction on the worker's pooled asynchronous
# connections.
async sub release_hold_p ( $self, $input, $context = undef ) {
    return $self->release_hold($input) if !$self->_native_deletion;
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

sub run_erasure_job ( $self, $input ) {
    return $self->_commanded_store(
        $input,
        $JOB_NOT_FOUND,
        sub {
            return $self->deletion_workflow->complete_job(
                @{$input}{qw(job_id actor_user_id)} );
        },
    );
}

# run_erasure_job in one transaction on the worker's pooled asynchronous
# connections: the erasure is a staff request, not a background job.
async sub run_erasure_job_p ( $self, $input, $context = undef ) {
    return $self->run_erasure_job($input) if !$self->_native_deletion;

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
sub _complete_export ( $self, $user_id ) {
    my $guard = $self->erased_exports;
    if ( !$guard ) {
        return $self->_build_export($user_id);
    }

    return $guard->schema->txn_do(
        sub {
            if ( !$guard->may_export($user_id) ) {
                return undef;
            }

            return $self->_build_export($user_id);
        }
    );
}

# _complete_export on the call layer of the export's transaction.
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

sub _build_export ( $self, $user_id ) {
    my $request = $self->export_builder->request_user_export($user_id);

    return _export_answer(
        $request,
        $self->export_builder->complete_user_export(
            $request->{export_request_id}
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

sub _commanded_store ( $self, $input, $not_found, $code ) {
    my $invalid = $self->_missing_field( $input, 'command_id' );
    if ($invalid) {
        return $invalid;
    }

    return $self->_run_store( $not_found, $code );
}

async sub _commanded_store_p ( $self, $input, $not_found, $code ) {
    my $invalid = $self->_missing_field( $input, 'command_id' );
    return $invalid if $invalid;

    return await $self->_run_store_p( $not_found, $code );
}

# Whether the deletion store writes on the function layer, and so has its
# promise twins; the in-memory doubles answer through the blocking writes.
sub _native_deletion ($self) {
    return _functions_of( $self->deletion_workflow ) ? 1 : 0;
}

sub _functions_of ($store) {
    return undef if !$store || !$store->can('functions');
    return $store->functions;
}

# A store that dies fails the write and is logged; one that answers nothing
# is not found; one that answers ok => 0 was blocked, a conflict.
sub _run_store ( $self, $not_found, $code ) {
    my $value;
    try {
        $value = $code->();
    }
    catch ($error) {
        return $self->_store_failed($error);
    };

    return _stored( $not_found, $value );
}

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

=head2 request_export

Creates and completes a user export bundle when a command id is present.
When the export store has a schema, the export first holds the member's
account row through L<GPForum::Service::Privacy::ErasedExports/may_export>
for the rest of its transaction, so an erasure running at the same time
either waits for it and discards the bundle or has committed already; an
erased or unknown member gets C<not_found> and no export.

=head2 request_export_p

L</request_export> as a promise, with an optional query context last: the
command log's row, the account's share lock, the export request and its
completed bundle commit in one transaction on the worker's pooled
asynchronous connections, no child process. An export store without the
function layer answers through the blocking write.

=head2 request_deletion

Creates an anonymize deletion request when a command id and reason are present.
An open request for the same resource is reused.

=head2 request_deletion_p

L</request_deletion> as a promise, with an optional query context last, in
one transaction on the worker's pooled asynchronous connections. A deletion
store without the function layer answers through the blocking write, as do
the other promise twins below.

=head2 approve_deletion

Approves a pending deletion request or reports an active hold as conflict when
a command id and reason are present.

=head2 approve_deletion_p

L</approve_deletion> as a promise, with an optional query context last, in
one transaction on the worker's pooled asynchronous connections.

=head2 hold_deletion

Creates a retention hold and marks the deletion request held when a command id
and reason are present. C<hold_request> stays four arguments besides the
invocant.

=head2 hold_deletion_p

L</hold_deletion> as a promise, with an optional query context last: the
hold is made in a savepoint of the transaction that locks and holds the
request, on the worker's pooled asynchronous connections.

=head2 release_hold

Ends a retention hold and gives the deletion request it held back to
C<approved> or C<pending>, when a command id and a reason are present
(L<GPForum::Service::Privacy::DeletionWorkflow/release_hold>). A hold not in
force answers C<not_found>.

=head2 release_hold_p

L</release_hold> as a promise, with an optional query context last, in one
transaction on the worker's pooled asynchronous connections.

=head2 run_erasure_job

Completes an erasure job or reports an active hold as conflict when a command
id is present.

=head2 run_erasure_job_p

L</run_erasure_job> as a promise, with an optional query context last: the
whole erasure, the profile pictures' stored objects included, in one
transaction on the worker's pooled asynchronous connections.

=head1 DIAGNOSTICS

Returns C<invalid>, C<not_found>, C<conflict>, or C<failed> statuses instead of
throwing for expected write outcomes. Unexpected store or command-log
exceptions are logged and mapped to C<failed>.

=head1 CONFIGURATION AND ENVIRONMENT

Uses deletion, export, hold, and review services supplied by the composition
root. C<erased_exports> defaults to one over the export store's schema, and
to none when the store has no schema.

=head1 DEPENDENCIES

Uses L<GPForum::Base> and L<GPForum::Service::Privacy::ErasedExports>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Command-id is required for export, deletion, approval, hold, and erasure
writes. Open deletion requests, pending exports, and active holds replay on
retry. The same export C<command_id> replays from C<command_log> after the
bundle is already completed. C<hold_request> stays four arguments besides
the invocant.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
