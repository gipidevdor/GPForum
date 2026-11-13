# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Moderation::Workflow;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -signatures, -async_await;
use v5.40;

use Mojo::Util   qw(monkey_patch);
use Scalar::Util qw(blessed);

use GPForum::Infrastructure::SqlFunction;
use GPForum::Infrastructure::Text qw(trimmed);
use GPForum::Log;
use GPForum::Service::WorkflowResult qw(log_error workflow_result);
our $VERSION = '0.001';

__PACKAGE__->requires(
    qw(action_store command_idempotency report_store suspension_store));
has logger => undef;    # optional: errors are dropped without one

# The command log's call layer: blocking_copy makes the workflow's parts
# block only when the workflow has one.
has functions => sub ($self) {
    my $log = $self->command_idempotency;
    return blessed $log && $log->can('functions') ? $log->functions : undef;
};

# The actions on a post or a thread, each answered not found by its target.
# Why a suspension, or its revocation, was refused (SuspensionStore): the
# member is the actor, or staff and the actor does not manage the admin
# console.
const my %REFUSALS => (
    self  => 'you cannot suspend yourself or lift your own suspension',
    staff => 'only an administrator can suspend a staff member or lift theirs',
);
const my %ACTION_NOT_FOUND => (
    hide_post      => 'post not found',
    restore_post   => 'post not found',
    lock_thread    => 'thread not found',
    unlock_thread  => 'thread not found',
    pin_thread     => 'thread not found',
    unpin_thread   => 'thread not found',
    hide_thread    => 'thread not found',
    restore_thread => 'thread not found',
);

# Every command but the actions: the job it is, built from its input.
const my %JOB => (
    reverse_action    => \&_reverse_job,
    assign_report     => \&_assign_job,
    release_report    => \&_release_job,
    resolve_report    => \&_resolve_job,
    suspend_user      => \&_suspend_job,
    revoke_suspension => \&_revoke_job,
);

# Each command is written once, as its promise method (ADR 0177): the
# command log's steps and the store's writes in one transaction. The
# blocking methods are its twins, the stores and the log blocking with it.
monkey_patch __PACKAGE__,
  map { ( "${_}_p" => _commanded($_) ) } keys %ACTION_NOT_FOUND, keys %JOB;
GPForum::Infrastructure::SqlFunction->blocking_twins( keys %ACTION_NOT_FOUND,
    keys %JOB );
GPForum::Infrastructure::SqlFunction->blocking_parts(
    qw(action_store command_idempotency report_store suspension_store));

sub _commanded ($name) {
    return sub ( $self, $input, $context = undef ) {
        return $self->_write_p( _job( $name => $input ), $context );
    };
}

# The command's job: which store method writes it with which arguments,
# its kind, its request as the command log fingerprints it and what it
# answers when nothing is found; or { invalid } when a required field is
# missing, checked in the order the command names them.
sub _job ( $name, $input ) {
    return $JOB{$name}->($input) if !exists $ACTION_NOT_FOUND{$name};
    my $not_found = $ACTION_NOT_FOUND{$name};

    return _checked(
        $input,
        [qw(reason command_id)],
        {
            command_type => "moderation.$name",
            kind         => 'action',
            not_found    => $not_found,
            request      => _action_request($input),
            store        => 'action_store',
            method       => $name,
            arguments    => [$input],
        }
    );
}

sub _reverse_job ($input) {
    return _checked(
        $input,
        [qw(command_id reason)],
        {
            command_type => 'moderation.reverse',
            kind         => 'reverse',
            not_found    => 'moderation action not found',
            request      => {
                action_id     => $input->{action_id},
                actor_user_id => $input->{actor_user_id},
                reason        => trimmed( $input->{reason} ),
            },
            store     => 'action_store',
            method    => 'reverse_action',
            arguments => [
                $input->{action_id}, $input->{actor_user_id},
                $input->{reason},
            ],
        }
    );
}

sub _assign_job ($input) {
    return _report_job( $input, 'moderation.assign', 'assign_report' );
}

sub _release_job ($input) {
    return _report_job( $input, 'moderation.release', 'release_report' );
}

sub _report_job ( $input, $command_type, $method ) {
    return _checked(
        $input,
        [qw(command_id)],
        {
            command_type => $command_type,
            kind         => 'report',
            not_found    => 'report not found',
            request      => _assign_request($input),
            store        => 'report_store',
            method       => $method,
            arguments    => [ $input->{report_id}, $input->{actor_user_id} ],
        }
    );
}

sub _resolve_job ($input) {
    return _checked(
        $input,
        [qw(resolution command_id)],
        {
            command_type => 'moderation.resolve',
            kind         => 'report',
            not_found    => 'report not found',
            request      => {
                %{ _assign_request($input) },
                resolution => trimmed( $input->{resolution} ),
            },
            store     => 'report_store',
            method    => 'resolve_report',
            arguments => [
                $input->{report_id}, $input->{resolution},
                $input->{actor_user_id},
            ],
        }
    );
}

sub _suspend_job ($input) {
    my $request = {
        actor_user_id => $input->{actor_user_id},
        reason        => trimmed( $input->{reason} ),
        user_id       => $input->{user_id},
    };
    if ( defined $input->{valid_to} && length $input->{valid_to} ) {
        $request->{valid_to} = $input->{valid_to};
    }

    return _checked(
        $input,
        [qw(reason command_id)],
        {
            command_type => 'moderation.suspend',
            kind         => 'suspend',
            not_found    => 'user not found',
            request      => $request,
            store        => 'suspension_store',
            method       => 'create_suspension',
            arguments    => [$input],
        }
    );
}

sub _revoke_job ($input) {
    return _checked(
        $input,
        [qw(reason command_id)],
        {
            command_type => 'moderation.suspension_revoke',
            kind         => 'revoke',
            not_found    => 'suspension not found',
            request      => {
                actor_user_id => $input->{actor_user_id},
                reason        => trimmed( $input->{reason} ),
                suspension_id => $input->{suspension_id},
            },
            store     => 'suspension_store',
            method    => 'revoke_suspension',
            arguments => [
                $input->{suspension_id}, $input->{actor_user_id},
                $input->{reason},
            ],
        }
    );
}

# The job, keyed by the input's actor and command id, once every field it
# requires is present.
sub _checked ( $input, $fields, $job ) {
    for my $field ( @{$fields} ) {
        my $invalid = _missing_field( $input, $field );
        return { invalid => $invalid } if $invalid;
    }

    return {
        %{$job},
        actor_id   => $input->{actor_user_id},
        command_id => $input->{command_id},
    };
}

# The store's answer under the command id: a store that fails fails the
# command and is logged, one that finds nothing is not found, and any other
# answer is reduced to the public fields of its kind. The store works on
# the command log's transaction.
async sub _write_p ( $self, $job, $context ) {
    return $job->{invalid} if $job->{invalid};
    my $accessor    = $job->{store};
    my $store       = $self->$accessor;
    my $method      = $job->{method} . '_p';
    my $log_context = GPForum::Log->request_context;
    my $run_p       = async sub ( $scope = undef ) {
        my $writer =
          $scope
          ? GPForum::Infrastructure::SqlFunction->joined( $store, $scope )
          : $store;
        my $value;
        try {
            $value = await $writer->$method( @{ $job->{arguments} }, $context );
        }
        catch ($error) {
            $self->_log_in( $log_context, "moderation write failed: $error" );
            return _store_failed();
        };
        return _stored_result( $job, $value );
    };

    my $result;
    try {
        $result =
          await $self->command_idempotency->result_of_p(
            { %{ _logged($job) }, run_p => $run_p }, $context );
    }
    catch ($error) {
        $self->_log_in( $log_context, "moderation command log failed: $error" );
        return _store_failed();
    };

    return $result;
}

sub _logged ($job) {
    return {
        actor_id     => $job->{actor_id},
        command_id   => $job->{command_id},
        command_type => $job->{command_type},
        request      => $job->{request} || {},
    };
}

sub _stored_result ( $job, $value ) {
    if ( !$value ) {
        return workflow_result(
            status => 'not_found',
            error  => $job->{not_found},
        );
    }
    if ( ref $value eq 'HASH' && $value->{refused} ) {
        return workflow_result(
            status => 'forbidden',
            error  => $REFUSALS{ $value->{refused} } || 'permission denied',
        );
    }

    return workflow_result(
        status => 'ok',
        stored => _public_stored( $job->{kind}, $value ),
    );
}

sub _store_failed {
    return workflow_result(
        status => 'failed',
        error  => 'moderation store failed',
    );
}

sub _log_in ( $self, $log_context, $message ) {
    GPForum::Log->in_context( $log_context,
        sub { log_error( $self->logger, $message ); return; } );
    return;
}

# The fields of a stored row that the answer, and the command log, carry.
sub _public_stored ( $kind, $stored ) {
    $stored ||= {};
    if ( $kind eq 'suspend' ) {
        return {
            ok         => 1,
            suspension => _fields(
                $stored->{suspension} || $stored,
                qw(actor_user_id reason revoked_at suspension_id user_id
                  valid_from valid_to)
            ),
        };
    }
    if ( $kind eq 'revoke' ) {
        return _fields( $stored,
            qw(actor_user_id reason revoked_at suspension_id) );
    }
    if ( $kind eq 'reverse' ) {
        return _fields( $stored->{action} || $stored,
            qw(moderation_action_id reason reversed_at reversed_by_user_id) );
    }
    if ( $kind eq 'action' ) {
        return {
            ok     => 1,
            action => _fields(
                $stored->{action} || $stored,
                qw(action_type actor_user_id command_id created_at metadata
                  moderation_action_id reason reversed_at reversed_by_user_id
                  target_id target_type)
            ),
        };
    }

    return _fields(
        $stored,
        qw(actor_user_id assigned_moderator_user_id report_id resolution
          resolved_at status)
    );
}

sub _fields ( $row, @names ) {
    return { map { $_ => $row->{$_} } @names };
}

sub _assign_request ($input) {
    return {
        actor_user_id => $input->{actor_user_id},
        report_id     => $input->{report_id},
    };
}

# The post or thread acted on, whichever the request names.
sub _action_request ($input) {
    my $request = {
        actor_user_id => $input->{actor_user_id},
        reason        => trimmed( $input->{reason} ),
    };
    for my $field (qw(post_id thread_id)) {
        if ( defined $input->{$field} && length $input->{$field} ) {
            $request->{$field} = $input->{$field};
        }
    }

    return $request;
}

sub _missing_field ( $input, $field ) {
    if ( !length trimmed( $input->{$field} ) ) {
        return workflow_result(
            status => 'invalid',
            errors => { $field => "$field is required" },
        );
    }

    return undef;
}

1;

__END__

=head1 NAME

GPForum::Service::Moderation::Workflow - Moderation write commands.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $result = await $workflow->hide_post_p(
        {
            actor_user_id => $user_id,
            post_id       => $post_id,
            reason        => $reason,
        }
    );

=head1 DESCRIPTION

Application boundary for moderation writes. Validates required command fields,
delegates persistence to report, action, and suspension stores, and returns a
normalized result hash. Stores keep transaction, event, audit, and outbox
ownership.

Each command is written once, as its promise method (ADR 0177): the command
log's steps (L<GPForum::Service::Operations::CommandIdempotency/result_of_p>)
and the store's writes commit in one transaction, the store joined to the
log's. Each takes an optional query context last. The blocking methods are
its twins, settled on the blocking layer with the stores and the log.

=head1 SUBROUTINES/METHODS

=head2 hide_post_p

Hides a post when a reason is present. C<hide_post> is its blocking twin.

=head2 restore_post_p

Restores a hidden post when a reason is present. C<restore_post> is its blocking twin.

=head2 lock_thread_p

Locks a thread when a reason is present. C<lock_thread> is its blocking twin.

=head2 unlock_thread_p

Unlocks a thread when a reason is present. C<unlock_thread> is its blocking twin.

=head2 pin_thread_p

Pins a thread to the top of its category when a reason is present. C<pin_thread> is its blocking twin.

=head2 unpin_thread_p

Unpins a thread when a reason is present. C<unpin_thread> is its blocking twin.

=head2 hide_thread_p

Hides a thread when a reason is present. C<hide_thread> is its blocking twin.

=head2 restore_thread_p

Restores a hidden thread when a reason is present. C<restore_thread> is its blocking twin.

=head2 reverse_action_p

Records reversal of a prior moderation action when a command id and reason
are present. C<reverse_action> is its blocking twin.

=head2 assign_report_p

Assigns an open report to the acting moderator when a command id is present. C<assign_report> is its blocking twin.

=head2 release_report_p

Releases a report assignment when a command id is present. C<release_report> is its blocking twin.

=head2 resolve_report_p

Resolves a report when a command id and resolution are present. C<resolve_report> is its blocking twin.

=head2 suspend_user_p

Creates a user suspension when a command id and reason are present. C<suspend_user> is its blocking twin.

=head2 revoke_suspension_p

Revokes a suspension when a command id and reason are present. C<revoke_suspension> is its blocking twin.

=head1 DIAGNOSTICS

Returns C<invalid>, C<not_found>, or C<failed> statuses instead of throwing for
expected write outcomes. Unexpected store exceptions are logged and mapped to
C<failed>.

=head1 CONFIGURATION AND ENVIRONMENT

Uses action, report, and suspension stores plus the command-idempotency
helper supplied by the composition root.

=head1 DEPENDENCIES

Uses L<GPForum::Base>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Command-id is required for assign, release, resolve, reverse, hide, restore,
lock, unlock, suspend, and revoke. Those writes replay from C<command_log>
under the same request. Hide, restore, lock, and unlock also keep
store-level unique C<command_id>. Reverse store arity stays four arguments.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
