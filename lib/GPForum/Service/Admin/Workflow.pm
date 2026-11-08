# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Admin::Workflow;

use Const::Fast;
use Mojo::Base -base, -signatures, -async_await;
use v5.40;
use Scalar::Util qw(blessed);

use GPForum::Infrastructure::Text qw(trimmed);
use GPForum::Service::WorkflowResult
  qw(log_error missing_command_id workflow_result);
our $VERSION = '0.001';

const my %ALLOWED_VISIBILITY => (
    members => 1,
    private => 1,
    public  => 1,
);

# Each collaborator serves its own commands, and a caller wiring only some of
# them -- the dead-letter console, the diagnostics page -- leaves the rest out.
has announcement_store  => undef;    # optional: only announcements read it
has binding_store       => undef;    # optional: only role bindings read it
has category_store      => undef;    # optional: only categories read it
has dead_letter_replay  => undef;    # optional: only replays read it
has diagnostics         => undef;    # optional: only diagnostics read it
has maintenance         => undef;    # optional: only maintenance reads it
has role_catalog        => undef;    # optional: only roles read it
has command_idempotency => undef;    # optional: writes run unlogged without one
has logger              => undef;    # optional: errors are dropped without one

sub create_role ( $self, $input ) {
    return $self->_commanded( $self->_create_role_job($input) );
}

async sub create_role_p ( $self, $input, $context = undef ) {
    return $self->create_role($input)
      if !$self->_async_ready( $self->role_catalog, 'create_role_p' );
    return await $self->_commanded_p( $self->_create_role_job($input),
        $context );
}

sub _create_role_job ( $self, $input ) {
    my $invalid = missing_command_id($input);
    return { answer => $invalid } if $invalid;

    my $command = {
        actor_user_id => $input->{actor_user_id},
        description   => _optional( $input->{description} ),
        name          => trimmed( $input->{name} ),
    };
    $invalid = $self->_missing_fields( $command, ['name'] );
    return { answer => $invalid } if $invalid;

    return {
        kind         => 'store',
        actor_id     => $input->{actor_user_id},
        command_id   => $input->{command_id},
        command_type => 'admin.role_create',
        not_found    => 'role not found',
        request      => {
            actor_user_id => $command->{actor_user_id},
            description   => $command->{description},
            name          => $command->{name},
        },
        run   => sub { return $self->role_catalog->create_role($command); },
        run_p => sub ( $scope, $context ) {
            return $self->role_catalog->create_role_p( $command, $context,
                $scope );
        },
    };
}

sub create_permission ( $self, $input ) {
    return $self->_commanded( $self->_create_permission_job($input) );
}

async sub create_permission_p ( $self, $input, $context = undef ) {
    return $self->create_permission($input)
      if !$self->_async_ready( $self->role_catalog, 'create_permission_p' );
    return await $self->_commanded_p( $self->_create_permission_job($input),
        $context );
}

sub _create_permission_job ( $self, $input ) {
    my $invalid = missing_command_id($input);
    return { answer => $invalid } if $invalid;

    my $command = {
        action        => trimmed( $input->{action} ),
        actor_user_id => $input->{actor_user_id},
        name          => trimmed( $input->{name} ),
        resource_type => trimmed( $input->{resource_type} ),
    };
    $invalid =
      $self->_missing_fields( $command, [qw(name resource_type action)] );
    return { answer => $invalid } if $invalid;

    return {
        kind         => 'store',
        actor_id     => $input->{actor_user_id},
        command_id   => $input->{command_id},
        command_type => 'admin.permission_create',
        not_found    => 'permission not found',
        request      => {
            action        => $command->{action},
            actor_user_id => $command->{actor_user_id},
            name          => $command->{name},
            resource_type => $command->{resource_type},
        },
        run => sub { return $self->role_catalog->create_permission($command); },
        run_p => sub ( $scope, $context ) {
            return $self->role_catalog->create_permission_p( $command,
                $context, $scope );
        },
    };
}

sub attach_permission ( $self, $input ) {
    return $self->_commanded( $self->_attach_permission_job($input) );
}

async sub attach_permission_p ( $self, $input, $context = undef ) {
    return $self->attach_permission($input)
      if !$self->_async_ready( $self->role_catalog, 'attach_permission_p' );
    return await $self->_commanded_p( $self->_attach_permission_job($input),
        $context );
}

sub _attach_permission_job ( $self, $input ) {
    my $invalid = missing_command_id($input);
    return { answer => $invalid } if $invalid;

    my $command = {
        actor_user_id => $input->{actor_user_id},
        permission_id => trimmed( $input->{permission_id} ),
        role_id       => trimmed( $input->{role_id} ),
    };
    $invalid = $self->_missing_fields( $command, [qw(role_id permission_id)] );
    return { answer => $invalid } if $invalid;

    return {
        kind         => 'store',
        actor_id     => $input->{actor_user_id},
        command_id   => $input->{command_id},
        command_type => 'admin.permission_attach',
        not_found    => 'role permission not found',
        request      => {
            actor_user_id => $command->{actor_user_id},
            permission_id => $command->{permission_id},
            role_id       => $command->{role_id},
        },
        run => sub { return $self->role_catalog->attach_permission($command); },
        run_p => sub ( $scope, $context ) {
            return $self->role_catalog->attach_permission_p( $command,
                $context, $scope );
        },
    };
}

sub bind_role ( $self, $input ) {
    return $self->_commanded( $self->_bind_role_job($input) );
}

async sub bind_role_p ( $self, $input, $context = undef ) {
    return $self->bind_role($input)
      if !$self->_async_ready( $self->binding_store, 'bind_role_p' );
    return await $self->_commanded_p( $self->_bind_role_job($input), $context );
}

sub _bind_role_job ( $self, $input ) {
    my $invalid = missing_command_id($input);
    return { answer => $invalid } if $invalid;

    my $command = {
        actor_user_id => $input->{actor_user_id},
        resource_id   => _optional( $input->{resource_id} ),
        resource_type => trimmed( $input->{resource_type} ),
        role_id       => trimmed( $input->{role_id} ),
        space_id      => _optional( $input->{space_id} ),
        user_id       => trimmed( $input->{user_id} ),
    };
    $invalid =
      $self->_missing_fields( $command, [qw(user_id role_id resource_type)] );
    return { answer => $invalid } if $invalid;

    return {
        kind         => 'store',
        actor_id     => $input->{actor_user_id},
        command_id   => $input->{command_id},
        command_type => 'admin.role_bind',
        not_found    => 'role binding not found',
        request      => {
            actor_user_id => $command->{actor_user_id},
            resource_id   => $command->{resource_id},
            resource_type => $command->{resource_type},
            role_id       => $command->{role_id},
            space_id      => $command->{space_id},
            user_id       => $command->{user_id},
        },
        run   => sub { return $self->binding_store->bind_role($command); },
        run_p => sub ( $scope, $context ) {
            return $self->binding_store->bind_role_p( $command, $context,
                $scope );
        },
    };
}

sub revoke_binding ( $self, $input ) {
    return $self->_commanded( $self->_revoke_binding_job($input) );
}

async sub revoke_binding_p ( $self, $input, $context = undef ) {
    return $self->revoke_binding($input)
      if !$self->_async_ready( $self->binding_store, 'revoke_binding_p' );
    return await $self->_commanded_p( $self->_revoke_binding_job($input),
        $context );
}

sub _revoke_binding_job ( $self, $input ) {
    my $invalid = missing_command_id($input);
    return { answer => $invalid } if $invalid;

    return {
        kind         => 'store',
        actor_id     => $input->{actor_user_id},
        command_id   => $input->{command_id},
        command_type => 'admin.binding_revoke',
        not_found    => 'role binding not found',
        request      => {
            actor_user_id => $input->{actor_user_id},
            binding_id    => trimmed( $input->{binding_id} ),
        },
        run => sub {
            return $self->binding_store->revoke_binding( $input->{binding_id},
                $input->{actor_user_id} );
        },
        run_p => sub ( $scope, $context ) {
            return $self->binding_store->revoke_binding_p( $input->{binding_id},
                $input->{actor_user_id},
                $context, $scope );
        },
    };
}

sub create_category ( $self, $input ) {
    return $self->_commanded( $self->_create_category_job($input) );
}

async sub create_category_p ( $self, $input, $context = undef ) {
    return $self->create_category($input)
      if !$self->_async_ready( $self->category_store, 'create_category_p' );
    return await $self->_commanded_p( $self->_create_category_job($input),
        $context );
}

sub _create_category_job ( $self, $input ) {
    my $invalid = missing_command_id($input);
    return { answer => $invalid } if $invalid;

    my $command = $self->_category_command($input);
    $invalid = $self->_invalid_category( $command, ['title'] );
    return { answer => $invalid } if $invalid;

    return {
        kind         => 'store',
        actor_id     => $input->{actor_user_id},
        command_id   => $input->{command_id},
        command_type => 'admin.category_create',
        not_found    => 'space not found',
        request      => _category_request($command),
        run => sub { return $self->category_store->create_category($command); },
        run_p => sub ( $scope, $context ) {
            return $self->category_store->create_category_p( $command,
                $context, $scope );
        },
    };
}

sub update_category ( $self, $input ) {
    return $self->_commanded( $self->_update_category_job($input) );
}

async sub update_category_p ( $self, $input, $context = undef ) {
    return $self->update_category($input)
      if !$self->_async_ready( $self->category_store, 'update_category_p' );
    return await $self->_commanded_p( $self->_update_category_job($input),
        $context );
}

sub _update_category_job ( $self, $input ) {
    my $invalid = missing_command_id($input);
    return { answer => $invalid } if $invalid;

    my $command = $self->_category_command($input);
    $invalid = $self->_invalid_category( $command, ['category_id'] );
    return { answer => $invalid } if $invalid;

    return {
        kind         => 'store',
        actor_id     => $input->{actor_user_id},
        command_id   => $input->{command_id},
        command_type => 'admin.category_update',
        not_found    => 'category not found',
        request      => _category_request($command),
        run => sub { return $self->category_store->update_category($command); },
        run_p => sub ( $scope, $context ) {
            return $self->category_store->update_category_p( $command,
                $context, $scope );
        },
    };
}

# An announcement published or retired is on every page at once: the
# public page cache is purged with the write, under the same actor.
sub create_announcement ( $self, $input ) {
    return $self->_purging( $input,
        $self->_commanded( $self->_create_announcement_job($input) ) );
}

async sub create_announcement_p ( $self, $input, $context = undef ) {
    return $self->create_announcement($input)
      if !$self->_async_ready( $self->announcement_store,
        'create_announcement_p' );
    return await $self->_purging_p(
        $input,
        await $self->_commanded_p(
            $self->_create_announcement_job($input), $context
        ),
        $context
    );
}

sub _create_announcement_job ( $self, $input ) {
    my $invalid = missing_command_id($input);
    return { answer => $invalid } if $invalid;
    my $command = {
        actor_user_id => $input->{actor_user_id},
        message       => trimmed( $input->{message} ),
        tone          => trimmed( $input->{tone} ) || 'notice',
    };
    $invalid = $self->_missing_fields( $command, ['message'] );
    return { answer => $invalid } if $invalid;

    return {
        kind         => 'store',
        actor_id     => $input->{actor_user_id},
        command_id   => $input->{command_id},
        command_type => 'admin.announcement_publish',
        not_found    => 'announcement not found',
        request      => $command,
        run          => sub {
            return $self->announcement_store->create_announcement($command);
        },
        run_p => sub ( $scope, $context ) {
            return $self->announcement_store->create_announcement_p( $command,
                $context, $scope );
        },
    };
}

sub retire_announcement ( $self, $input ) {
    return $self->_purging( $input,
        $self->_commanded( $self->_retire_announcement_job($input) ) );
}

async sub retire_announcement_p ( $self, $input, $context = undef ) {
    return $self->retire_announcement($input)
      if !$self->_async_ready( $self->announcement_store,
        'retire_announcement_p' );
    return await $self->_purging_p(
        $input,
        await $self->_commanded_p(
            $self->_retire_announcement_job($input), $context
        ),
        $context
    );
}

sub _retire_announcement_job ( $self, $input ) {
    my $invalid = missing_command_id($input);
    return { answer => $invalid } if $invalid;
    my $command = {
        actor_user_id   => $input->{actor_user_id},
        announcement_id => trimmed( $input->{announcement_id} ),
    };
    $invalid = $self->_missing_fields( $command, ['announcement_id'] );
    return { answer => $invalid } if $invalid;

    return {
        kind         => 'store',
        actor_id     => $input->{actor_user_id},
        command_id   => $input->{command_id},
        command_type => 'admin.announcement_retire',
        not_found    => 'announcement not found',
        request      => $command,
        run          => sub {
            return $self->announcement_store->retire_announcement($command);
        },
        run_p => sub ( $scope, $context ) {
            return $self->announcement_store->retire_announcement_p( $command,
                $context, $scope );
        },
    };
}

# A write that changed what every page shows takes the public cache's
# copies down with it; a write that did not (a refusal, a replay) leaves
# them. Without a maintenance service nothing is purged.
sub _purging ( $self, $input, $result ) {
    return $result if !_purges( $self, $result );
    try {
        $self->maintenance->purge_public_cache(
            { actor_user_id => $input->{actor_user_id} } );
    }
    catch ($error) {
        log_error( $self->logger, "announcement cache purge failed: $error" );
    };
    return $result;
}

async sub _purging_p ( $self, $input, $result, $context ) {
    return $result if !_purges( $self, $result );
    return $self->_purging( $input, $result )
      if !$self->maintenance->can('purge_public_cache_p');
    try {
        await $self->maintenance->purge_public_cache_p(
            { actor_user_id => $input->{actor_user_id} }, $context );
    }
    catch ($error) {
        log_error( $self->logger, "announcement cache purge failed: $error" );
    };
    return $result;
}

sub _purges ( $self, $result ) {
    return 0 if !$result->{ok} || $result->{replayed};
    return $self->maintenance ? 1 : 0;
}

# Replays a dead letter under the command's idempotency, so a lost response
# retried with the same command id gets the first answer back instead of a
# conflict from the replay the first attempt already made.
sub replay_dead_letter ( $self, $input ) {
    return $self->_commanded( $self->_replay_job($input) );
}

async sub replay_dead_letter_p ( $self, $input, $context = undef ) {
    return $self->replay_dead_letter($input)
      if !$self->_async_ready( $self->dead_letter_replay, 'replay_p' );
    return await $self->_commanded_p( $self->_replay_job($input), $context );
}

sub _replay_job ( $self, $input ) {
    my $invalid = missing_command_id($input);
    return { answer => $invalid } if $invalid;

    my $dead_letter_id = trimmed( $input->{dead_letter_id} );
    my $replay         = {
        actor_user_id  => $input->{actor_user_id},
        dead_letter_id => $dead_letter_id,
        via            => 'web',
    };
    return {
        kind         => 'write',
        actor_id     => $input->{actor_user_id},
        command_id   => $input->{command_id},
        command_type => 'admin.dead_letter_replay',
        request      => {
            actor_user_id  => $input->{actor_user_id},
            dead_letter_id => $dead_letter_id,
        },
        run => sub {
            return _replayed(
                $self->_try_store(
                    sub { return $self->dead_letter_replay->replay($replay); }
                )
            );
        },
        run_p => async sub ( $scope, $context ) {
            return _replayed(
                await $self->_try_store_p(
                    sub {
                        return $self->dead_letter_replay->replay_p( $replay,
                            $context, $scope );
                    }
                )
            );
        },
    };
}

sub _replayed ($stored) {
    return _failed_result() if $stored->{failed};
    my $outcome = $stored->{value};
    if ( $outcome->{status} ne 'replayed' ) {
        return workflow_result(
            error  => $outcome->{error},
            status => $outcome->{status},
        );
    }
    return workflow_result(
        status => 'ok',
        stored => $outcome->{replayed},
    );
}

# 6.5: a search rebuild through the outbox, and a purge of the public page
# cache, each under a command id and audited (Admin::Maintenance).
sub request_search_rebuild ( $self, $input ) {
    return $self->_commanded(
        $self->_maintenance_job(
            $input, 'admin.search_rebuild',
            maintenance => 'request_search_rebuild'
        )
    );
}

async sub request_search_rebuild_p ( $self, $input, $context = undef ) {
    return $self->request_search_rebuild($input)
      if !$self->_async_ready( $self->maintenance, 'request_search_rebuild_p' );
    return await $self->_commanded_p(
        $self->_maintenance_job(
            $input, 'admin.search_rebuild',
            maintenance => 'request_search_rebuild'
        ),
        $context
    );
}

sub purge_public_cache ( $self, $input ) {
    return $self->_commanded(
        $self->_maintenance_job(
            $input, 'admin.cache_purge',
            maintenance => 'purge_public_cache'
        )
    );
}

async sub purge_public_cache_p ( $self, $input, $context = undef ) {
    return $self->purge_public_cache($input)
      if !$self->_async_ready( $self->maintenance, 'purge_public_cache_p' );
    return await $self->_commanded_p(
        $self->_maintenance_job(
            $input, 'admin.cache_purge',
            maintenance => 'purge_public_cache'
        ),
        $context
    );
}

# 6.5: a test message to the administrator's own address, and the antivirus
# check, each under a command id -- a resubmitted form sends no second
# message -- and audited with its outcome (Admin::Diagnostics).
sub send_test_mail ( $self, $input ) {
    return $self->_commanded(
        $self->_maintenance_job(
            $input, 'admin.mail_test', diagnostics => 'send_test_mail'
        )
    );
}

async sub send_test_mail_p ( $self, $input, $context = undef ) {
    return $self->send_test_mail($input)
      if !$self->_async_ready( $self->diagnostics, 'send_test_mail_p' );
    return await $self->_commanded_p(
        $self->_maintenance_job(
            $input, 'admin.mail_test', diagnostics => 'send_test_mail'
        ),
        $context
    );
}

sub check_antivirus ( $self, $input ) {
    return $self->_commanded(
        $self->_maintenance_job(
            $input, 'admin.antivirus_check',
            diagnostics => 'check_antivirus'
        )
    );
}

async sub check_antivirus_p ( $self, $input, $context = undef ) {
    return $self->check_antivirus($input)
      if !$self->_async_ready( $self->diagnostics, 'check_antivirus_p' );
    return await $self->_commanded_p(
        $self->_maintenance_job(
            $input, 'admin.antivirus_check',
            diagnostics => 'check_antivirus'
        ),
        $context
    );
}

# A maintenance or diagnostics command: the collaborator's method under the
# command id, its answer stored.
sub _maintenance_job ( $self, $input, $command_type, $collaborator, $method ) {
    my $invalid = missing_command_id($input);
    return { answer => $invalid } if $invalid;
    my $async = $method . '_p';

    return {
        kind         => 'write',
        actor_id     => $input->{actor_user_id},
        command_id   => $input->{command_id},
        command_type => $command_type,
        request      => { actor_user_id => $input->{actor_user_id} },
        run          => sub {
            return _stored(
                $self->_try_store(
                    sub { return $self->$collaborator->$method($input); }
                )
            );
        },
        run_p => async sub ( $scope, $context ) {
            return _stored(
                await $self->_try_store_p(
                    sub {
                        return $self->$collaborator->$async( $input, $context,
                            $scope );
                    }
                )
            );
        },
    };
}

sub _stored ($stored) {
    return _failed_result() if $stored->{failed};

    return workflow_result(
        status => 'ok',
        stored => $stored->{value}
    );
}

sub _category_request ($command) {
    return {
        actor_user_id => $command->{actor_user_id},
        category_id   => $command->{category_id},
        description   => $command->{description},
        position      => $command->{position},
        slug          => $command->{slug},
        space_id      => $command->{space_id},
        title         => $command->{title},
        visibility    => $command->{visibility},
    };
}

sub _category_command ( $, $input ) {
    return {
        actor_user_id => $input->{actor_user_id},
        category_id   => trimmed( $input->{category_id} ),
        description   => _optional( $input->{description} ),
        position      => _optional( $input->{position} ),
        slug          => _optional( $input->{slug} ),
        space_id      => _optional( $input->{space_id} ),
        title         => trimmed( $input->{title} ),
        visibility    => _optional( $input->{visibility} ),
    };
}

sub _invalid_category ( $self, $command, $required ) {
    my $missing = $self->_missing_fields( $command, $required );
    if ($missing) {
        return $missing;
    }

    my $visibility = trimmed( $command->{visibility} );
    if ( !length $visibility || exists $ALLOWED_VISIBILITY{$visibility} ) {
        return undef;
    }

    return workflow_result(
        status => 'invalid',
        errors => { visibility => 'visibility is invalid' },
    );
}

# A command's answer: its refusal, or the store's or the write's result
# under the command id.
sub _commanded ( $self, $job ) {
    return $job->{answer} if $job->{answer};
    return $job->{kind} eq 'store'
      ? $self->_commanded_store($job)
      : $self->_commanded_write($job);
}

# Whether a command runs on pooled asynchronous connections: its
# collaborator has the asynchronous twin, and the command log (when there
# is one) runs on the call layer. In-memory doubles keep the blocking path.
sub _async_ready ( $self, $collaborator, $method ) {
    return 0 if !blessed $collaborator || !$collaborator->can($method);
    my $log = $self->command_idempotency;
    return 1 if !$log;
    return
         blessed $log
      && $log->can('result_of_p')
      && $log->can('functions')
      && $log->functions ? 1 : 0;
}

# _commanded on pooled asynchronous connections: the command log's steps
# and the collaborator's writes commit in one transaction
# (CommandIdempotency->result_of_p), whose call layer the collaborator
# writes through. Without a command log the collaborator runs on its own.
async sub _commanded_p ( $self, $job, $context ) {
    return $job->{answer} if $job->{answer};
    my $run_p = $job->{kind} eq 'store'
      ? async sub ( $scope = undef ) {
        return _store_result(
            $job->{not_found},
            await $self->_try_store_p(
                sub { return $job->{run_p}->( $scope, $context ); }
            )
        );
      }
      : sub ( $scope = undef ) { return $job->{run_p}->( $scope, $context ); };
    my $log = $self->command_idempotency;
    return await $run_p->() if !$log;

    my $result;
    try {
        $result = await $log->result_of_p(
            {
                actor_id     => $job->{actor_id},
                command_id   => $job->{command_id},
                command_type => $job->{command_type},
                request      => $job->{request} || {},
                run_p        => $run_p,
            },
            $context
        );
    }
    catch ($error) {
        log_error( $self->logger, "admin write failed: $error" );
        return _failed_result();
    };

    return $result;
}

sub _commanded_store ( $self, $job ) {
    return $self->_commanded_write(
        {
            actor_id     => $job->{actor_id},
            command_id   => $job->{command_id},
            command_type => $job->{command_type},
            request      => $job->{request} || {},
            run          => sub {
                return $self->_run_store( $job->{not_found}, $job->{run} );
            },
        }
    );
}

sub _commanded_write ( $self, $job ) {
    if ( !$self->command_idempotency ) {
        return $job->{run}->();
    }

    my $result;
    try {
        $result = $self->command_idempotency->result_of($job);
    }
    catch ($error) {
        log_error( $self->logger, "admin write failed: $error" );
        return _failed_result();
    };

    return $result;
}

sub _failed_result {
    return workflow_result(
        error  => 'admin store failed',
        status => 'failed',
    );
}

sub _missing_fields ( $, $input, $names ) {
    my %errors;
    for my $name ( @{$names} ) {
        if ( !length trimmed( $input->{$name} ) ) {
            $errors{$name} = "$name is required";
        }
    }
    if (%errors) {
        return workflow_result(
            status => 'invalid',
            errors => \%errors,
        );
    }

    return undef;
}

sub _run_store ( $self, $not_found, $code ) {
    return _store_result( $not_found, $self->_try_store($code) );
}

sub _store_result ( $not_found, $stored ) {
    if ( $stored->{failed} ) {
        return _failed_result();
    }
    if ( !$stored->{value} ) {
        return workflow_result(
            status => 'not_found',
            error  => $not_found,
        );
    }

    # A store that refuses the write on its own terms (a slug taken by a
    # soft-deleted category, which PostgreSQL's key still holds) answers its
    # errors instead of a row: invalid, not a write that happened.
    if ( ref $stored->{value} eq 'HASH' && $stored->{value}{errors} ) {
        return workflow_result(
            errors => $stored->{value}{errors},
            status => 'invalid',
        );
    }

    return workflow_result(
        status => 'ok',
        stored => $stored->{value},
    );
}

# Under a command id the store runs inside the command's transaction, and its
# exception has to reach that transaction: caught here, the transaction went
# on to commit whatever the store wrote before it failed -- a replay's outbox
# message without its audit row -- and stored "failed" as the command's
# answer, so retrying the same command could never succeed.
# _commanded_write catches it instead, after the rollback.
sub _try_store ( $self, $code ) {
    return { value => $code->() } if $self->command_idempotency;

    my $value;
    try {
        $value = $code->();
    }
    catch ($error) {
        log_error( $self->logger, "admin write failed: $error" );
        return { failed => 1 };
    };

    return { value => $value };
}

async sub _try_store_p ( $self, $code ) {
    return { value => await $code->() } if $self->command_idempotency;

    my $value;
    try {
        $value = await $code->();
    }
    catch ($error) {
        log_error( $self->logger, "admin write failed: $error" );
        return { failed => 1 };
    };

    return { value => $value };
}

sub _optional ($value) {
    my $trimmed = trimmed($value);
    return length $trimmed ? $trimmed : undef;
}

1;

__END__

=head1 NAME

GPForum::Service::Admin::Workflow - Admin authorization write commands.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $result = $workflow->create_role(
        {
            actor_user_id => $user_id,
            command_id    => $command_id,
            name          => $name,
        }
    );

=head1 DESCRIPTION

Application boundary for admin catalog, role-binding, and category writes.
Validates required command fields, requires HTTP C<command_id>, delegates
persistence to C<RoleCatalog>, C<RoleBindingStore>, and C<CategoryStore>,
and returns a normalized result hash. Replays from C<command_log> when the
helper is present. Command hashes include actor and target fields only.
Stores keep transaction, event, audit, and outbox ownership.

=head1 SUBROUTINES/METHODS

=head2 create_role

Creates a role when a name is present.

=head2 create_role_p

Answers what L</create_role> answers, on pooled asynchronous connections:
the command log's steps and the collaborator's writes commit in one
transaction, with no child process.

=head2 create_permission

Creates a permission when name, resource type, and action are present.

=head2 create_permission_p

Answers what L</create_permission> answers, on pooled asynchronous connections:
the command log's steps and the collaborator's writes commit in one
transaction, with no child process.

=head2 attach_permission

Attaches a permission to a role.

=head2 attach_permission_p

Answers what L</attach_permission> answers, on pooled asynchronous connections:
the command log's steps and the collaborator's writes commit in one
transaction, with no child process.

=head2 bind_role

Binds a role to a user for a resource type.

=head2 bind_role_p

Answers what L</bind_role> answers, on pooled asynchronous connections:
the command log's steps and the collaborator's writes commit in one
transaction, with no child process.

=head2 revoke_binding

Revokes an existing role binding.

=head2 revoke_binding_p

Answers what L</revoke_binding> answers, on pooled asynchronous connections:
the command log's steps and the collaborator's writes commit in one
transaction, with no child process.

=head2 create_category

Creates a category when a title is present.

=head2 create_category_p

Answers what L</create_category> answers, on pooled asynchronous connections:
the command log's steps and the collaborator's writes commit in one
transaction, with no child process.

=head2 update_category

Updates a category when a category id is present.

=head2 update_category_p

Answers what L</update_category> answers, on pooled asynchronous connections:
the command log's steps and the collaborator's writes commit in one
transaction, with no child process.

=head2 create_announcement

Publishes a site announcement (ADR 0131) from C<message> and C<tone>,
under C<command_id>, and purges the public page cache.

=head2 create_announcement_p

Answers what L</create_announcement> answers, on pooled asynchronous connections:
the command log's steps and the collaborator's writes commit in one
transaction, with no child process.

=head2 retire_announcement

Retires the announcement C<announcement_id>, under C<command_id>, and
purges the public page cache.

=head2 retire_announcement_p

Answers what L</retire_announcement> answers, on pooled asynchronous connections:
the command log's steps and the collaborator's writes commit in one
transaction, with no child process.

=head2 request_search_rebuild

Starts a search rebuild through L<GPForum::Service::Admin::Maintenance>,
under the command id.

=head2 request_search_rebuild_p

Answers what L</request_search_rebuild> answers, on pooled asynchronous connections:
the command log's steps and the collaborator's writes commit in one
transaction, with no child process.

=head2 purge_public_cache

Purges the public page cache, under the command id.

=head2 purge_public_cache_p

Answers what L</purge_public_cache> answers, on pooled asynchronous connections:
the command log's steps and the collaborator's writes commit in one
transaction, with no child process.

=head2 send_test_mail

Sends a test message to the actor's own address through
L<GPForum::Service::Admin::Diagnostics>, under the command id; C<ok> whether
the transport accepted it or not, with the outcome in C<stored>.

=head2 send_test_mail_p

Answers what L</send_test_mail> answers, on pooled asynchronous connections:
the command log's steps and the collaborator's writes commit in one
transaction, with no child process.

=head2 check_antivirus

Runs the antivirus check, under the command id, with its report in
C<stored>.

=head2 check_antivirus_p

Answers what L</check_antivirus> answers, on pooled asynchronous connections:
the command log's steps and the collaborator's writes commit in one
transaction, with no child process.

=head2 replay_dead_letter

Replays a dead letter through L<GPForum::Service::Outbox::DeadLetterReplay>,
under the command id. C<not_found> when there is no such dead letter,
C<conflict> when it cannot be replayed.

=head2 replay_dead_letter_p

Answers what L</replay_dead_letter> answers, on pooled asynchronous connections:
the command log's steps and the collaborator's writes commit in one
transaction, with no child process.

=head1 DIAGNOSTICS

Returns C<invalid>, C<not_found>, C<conflict>, or C<failed> statuses instead of
throwing for expected write outcomes. Unexpected store exceptions are logged
and mapped to C<failed>.

=head1 CONFIGURATION AND ENVIRONMENT

Uses role catalog, binding, and category stores plus the command-idempotency
helper supplied by the composition root.

=head1 DEPENDENCIES

Uses L<Const::Fast> and L<Mojo::Base>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Stores keep name/scope uniqueness. HTTP retries with the same C<command_id>
replay from C<command_log>.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
