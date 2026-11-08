# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Moderation::ActionStore;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -signatures, -async_await;
use v5.40;

use GPForum::Infrastructure::Row qw(column_of);
use GPForum::Infrastructure::Storage;
use GPForum::Infrastructure::EventRecorder;
use GPForum::Infrastructure::UniqueConflict;
use GPForum::Service::Clock;
use GPForum::Service::Moderation::Event;
use GPForum::X::Conflict;

use GPForum::Infrastructure::SqlFunction;
use GPForum::Infrastructure::ResultRow;

our $VERSION = '0.001';

const my $COMMAND_CONSTRAINT => 'idx_moderation_actions_command_id';
const my $ID_CONSTRAINT      => 'moderation_actions_pkey';
const my $STATE_VISIBLE      => 'visible';
const my $STATE_HIDDEN       => 'hidden';
const my $STATE_LOCKED       => 'locked';
const my $TARGET_POST        => 'post';
const my $TARGET_THREAD      => 'thread';
const my %LOCK_SQL_FOR => (
    post   => 'SELECT post_id FROM posts WHERE post_id = ? FOR UPDATE',
    thread => 'SELECT thread_id FROM threads WHERE thread_id = ? FOR UPDATE',
);

has clock      => sub { return GPForum::Service::Clock->new; };
has id_service => sub {
    require GPForum::Infrastructure::Id;
    return GPForum::Infrastructure::Id->new;
};
has recorder => \&GPForum::Infrastructure::EventRecorder::for_service;
__PACKAGE__->requires(qw(schema));
has functions => \&GPForum::Infrastructure::SqlFunction::for_service;
has events    => sub { return GPForum::Service::Moderation::Event->new; };

sub hide_post ( $self, $input ) {
    return $self->_apply_action( $self->_hide_post_spec($input) );
}

async sub hide_post_p ( $self, $input, $context = undef ) {
    return await $self->_apply_action_p( $self->_hide_post_spec($input),
        $context );
}

sub _hide_post_spec ( $self, $input ) {
    my $timestamp = $self->clock->now_iso8601;

    return {
        %{$input},
        action_type => 'post.hidden',
        applied     => \&_is_hidden,
        created_at  => $timestamp,
        lock_kind   => $TARGET_POST,
        resultset   => 'Post',
        target_id   => $input->{post_id},
        target_type => $TARGET_POST,
        updates     => {
            hidden_at        => $timestamp,
            moderation_state => $STATE_HIDDEN,
        },
    };
}

sub restore_post ( $self, $input ) {
    return $self->_apply_action( $self->_restore_post_spec($input) );
}

async sub restore_post_p ( $self, $input, $context = undef ) {
    return await $self->_apply_action_p( $self->_restore_post_spec($input),
        $context );
}

sub _restore_post_spec ( $self, $input ) {
    return {
        %{$input},
        action_type => 'post.restored',
        applied     => sub ($post) {
            return _state($post) eq $STATE_VISIBLE ? 1 : 0;
        },
        created_at  => $self->clock->now_iso8601,
        lock_kind   => $TARGET_POST,
        resultset   => 'Post',
        target_id   => $input->{post_id},
        target_type => $TARGET_POST,
        updates     => {
            hidden_at        => undef,
            moderation_state => $STATE_VISIBLE,
        },
    };
}

# A thread keeps two facts in one moderation_state: hidden, and locked. The
# lock has its own column, locked_at, which is what refuses replies; hidden
# has none on a thread, so the state is all there is of it. Hiding wins the
# shared column: locking or unlocking a hidden thread leaves it hidden
# (overwriting the state would publish it), and showing it again puts
# back whichever of locked and visible locked_at says.
sub lock_thread ( $self, $input ) {
    return $self->_apply_action( $self->_lock_thread_spec($input) );
}

async sub lock_thread_p ( $self, $input, $context = undef ) {
    return await $self->_apply_action_p( $self->_lock_thread_spec($input),
        $context );
}

sub _lock_thread_spec ( $self, $input ) {
    my $timestamp = $self->clock->now_iso8601;

    return {
        %{$input},
        action_type => 'thread.locked',
        applied     => \&_is_locked,
        created_at  => $timestamp,
        lock_kind   => $TARGET_THREAD,
        resultset   => 'Thread',
        target_id   => $input->{thread_id},
        target_type => $TARGET_THREAD,
        updates     => sub ($thread) {
            return {
                locked_at        => $timestamp,
                moderation_state => _unless_hidden( $thread, $STATE_LOCKED ),
            };
        },
    };
}

# A thread is unlocked once neither locked_at nor its state says locked, so
# unlocking such a thread still puts its state right.
sub unlock_thread ( $self, $input ) {
    return $self->_apply_action( $self->_unlock_thread_spec($input) );
}

async sub unlock_thread_p ( $self, $input, $context = undef ) {
    return await $self->_apply_action_p( $self->_unlock_thread_spec($input),
        $context );
}

sub _unlock_thread_spec ( $self, $input ) {
    return {
        %{$input},
        action_type => 'thread.unlocked',
        applied     => sub ($thread) {
            return !_is_locked($thread)
              && _state($thread) ne $STATE_LOCKED ? 1 : 0;
        },
        created_at  => $self->clock->now_iso8601,
        lock_kind   => $TARGET_THREAD,
        resultset   => 'Thread',
        target_id   => $input->{thread_id},
        target_type => $TARGET_THREAD,
        updates     => sub ($thread) {
            return {
                locked_at        => undef,
                moderation_state => _unless_hidden( $thread, $STATE_VISIBLE ),
            };
        },
    };
}

# The pin is a flag of its own beside the state: pinning or unpinning a
# hidden or locked thread changes nothing else about it.
sub pin_thread ( $self, $input ) {
    return $self->_apply_action( $self->_pin_thread_spec($input) );
}

async sub pin_thread_p ( $self, $input, $context = undef ) {
    return await $self->_apply_action_p( $self->_pin_thread_spec($input),
        $context );
}

sub _pin_thread_spec ( $self, $input ) {
    return {
        %{$input},
        action_type => 'thread.pinned',
        applied     => \&_is_pinned,
        created_at  => $self->clock->now_iso8601,
        lock_kind   => $TARGET_THREAD,
        resultset   => 'Thread',
        target_id   => $input->{thread_id},
        target_type => $TARGET_THREAD,
        updates     => { pinned => 1 },
    };
}

sub unpin_thread ( $self, $input ) {
    return $self->_apply_action( $self->_unpin_thread_spec($input) );
}

async sub unpin_thread_p ( $self, $input, $context = undef ) {
    return await $self->_apply_action_p( $self->_unpin_thread_spec($input),
        $context );
}

sub _unpin_thread_spec ( $self, $input ) {
    return {
        %{$input},
        action_type => 'thread.unpinned',
        applied     => sub ($thread) {
            return _is_pinned($thread) ? 0 : 1;
        },
        created_at  => $self->clock->now_iso8601,
        lock_kind   => $TARGET_THREAD,
        resultset   => 'Thread',
        target_id   => $input->{thread_id},
        target_type => $TARGET_THREAD,
        updates     => { pinned => 0 },
    };
}

# Threads have no hidden_at, unlike posts: writing one died on PostgreSQL
# ("No such column"), so no thread could be hidden or shown again. When it
# was hidden is the created_at of the action row recorded with it.
sub hide_thread ( $self, $input ) {
    return $self->_apply_action( $self->_hide_thread_spec($input) );
}

async sub hide_thread_p ( $self, $input, $context = undef ) {
    return await $self->_apply_action_p( $self->_hide_thread_spec($input),
        $context );
}

sub _hide_thread_spec ( $self, $input ) {
    return {
        %{$input},
        action_type => 'thread.hidden',
        applied     => \&_is_hidden,
        created_at  => $self->clock->now_iso8601,
        lock_kind   => $TARGET_THREAD,
        resultset   => 'Thread',
        target_id   => $input->{thread_id},
        target_type => $TARGET_THREAD,
        updates     => { moderation_state => $STATE_HIDDEN },
    };
}

sub restore_thread ( $self, $input ) {
    return $self->_apply_action( $self->_restore_thread_spec($input) );
}

async sub restore_thread_p ( $self, $input, $context = undef ) {
    return await $self->_apply_action_p( $self->_restore_thread_spec($input),
        $context );
}

sub _restore_thread_spec ( $self, $input ) {
    return {
        %{$input},
        action_type => 'thread.restored',
        applied     => sub ($thread) {
            return _is_hidden($thread) ? 0 : 1;
        },
        created_at  => $self->clock->now_iso8601,
        lock_kind   => $TARGET_THREAD,
        resultset   => 'Thread',
        target_id   => $input->{thread_id},
        target_type => $TARGET_THREAD,
        updates     => sub ($thread) {
            my $shown = _is_locked($thread) ? $STATE_LOCKED : $STATE_VISIBLE;

            return { moderation_state => $shown };
        },
    };
}

sub reverse_action ( $self, $action_id, $reversed_by_user_id, $reason ) {
    return $self->schema->txn_do(
        sub {
            my $timestamp = $self->clock->now_iso8601;
            my $action    = $self->_action_row( { action_id => $action_id } );
            return if !$action;

            return _reversal($action)
              if defined column_of( $action, 'reversed_at' );

            my $changes = _reversal_changes( $reversed_by_user_id, $timestamp );

            # A reversal committed meanwhile changed the action first: the
            # update leaves it as that one made it, and this answers that
            # reversal, with no second event or audit entry.
            return _reversal(
                $self->_action_row( { action_id => $action_id } ) )
              if !$self->_update_action( $action, $changes );
            my ( $event, $audit ) =
              $self->_reversal_records( $action, $action_id,
                $reversed_by_user_id, $reason, $timestamp );
            $self->recorder->record_event( %{$event} );
            $self->recorder->record_audit( %{$audit} );

            return { moderation_action_id => $action_id, %{$changes} };
        }
    );
}

# The same reversal in one transaction on the worker's pooled asynchronous
# connections, not a forked child with a connection of its own.
async sub reverse_action_p ( $self, $action_id, $reversed_by_user_id,
    $reason, $context = undef )
{
    return $self->reverse_action( $action_id, $reversed_by_user_id, $reason )
      if !$self->functions;
    return await $self->functions->transaction_p(
        async sub ($scope) {
            my $timestamp = $self->clock->now_iso8601;
            my $action =
              await _action_row_p( $scope, { action_id => $action_id } );
            return undef if !$action;

            return _reversal($action)
              if defined column_of( $action, 'reversed_at' );

            my $changes = _reversal_changes( $reversed_by_user_id, $timestamp );
            my $updated = await $scope->row_p( 'moderation_action_update',
                _action_update_values( $action, $changes ) );
            return _reversal(
                await _action_row_p( $scope, { action_id => $action_id } ) )
              if !$updated;
            %{$action} = ( %{$action}, %{$changes} );
            await $self->_record_p(
                $scope,
                $self->_reversal_records(
                    $action, $action_id, $reversed_by_user_id,
                    $reason, $timestamp
                )
            );

            return { moderation_action_id => $action_id, %{$changes} };
        },
        $context
    );
}

sub _reversal_changes ( $reversed_by_user_id, $timestamp ) {
    return {
        reversed_at         => $timestamp,
        reversed_by_user_id => $reversed_by_user_id,
    };
}

# The event and the audit entry of a reversal.
sub _reversal_records ( $self, $action, $action_id, $reversed_by_user_id,
    $reason, $timestamp )
{
    my $correlation_id = $self->id_service->uuid;
    return (
        $self->events->reversal_envelope(
            {
                action              => $action,
                action_id           => $action_id,
                correlation_id      => $correlation_id,
                reason              => $reason,
                reversed_by_user_id => $reversed_by_user_id,
                reversed_at         => $timestamp,
            }
        ),
        $self->events->reversal_audit(
            {
                action         => $action,
                correlation_id => $correlation_id,
                reason         => $reason,
                reversed_at    => $timestamp,
                reversed_by    => $reversed_by_user_id,
            }
        ),
    );
}

# Under a lock on the target, a command already recorded is replayed. A
# target already in the state the action sets answers with the action that
# set it; with none on record, the action is recorded as idempotent and the
# target left as it is.
sub _apply_action ( $self, $input ) {
    return $self->schema->txn_do(
        sub {
            my $dbh = GPForum::Infrastructure::Storage->dbh_of( $self->schema );
            if ( $dbh && !$self->functions ) {
                $dbh->selectrow_array( $LOCK_SQL_FOR{ $input->{lock_kind} },
                    undef, $input->{target_id} );
            }
            my $replayed = $self->_find_command_action( $input->{command_id} );
            if ($replayed) {
                return $self->_finish_leftover_action( $replayed, $input );
            }
            my $target = $self->_target($input);
            if ( !$target ) {
                return undef;
            }

            my $idempotent = $input->{applied}->($target) ? 1 : 0;
            if ($idempotent) {
                my $existing = $self->_latest_action($input);
                return _idempotent_answer($existing) if $existing;
            }

            my $previous_state = column_of( $target, 'moderation_state' );
            if ( !$idempotent ) {
                $self->_update_target( $target, $input,
                    _target_changes( $input, $target ) );
            }

            return $self->_record_action(
                _action_input( $input, $idempotent, $previous_state ) );
        }
    );
}

# _apply_action on the worker's pooled asynchronous connections: the
# moderation_target read holds the target's row, as the blocking path's
# does.
async sub _apply_action_p ( $self, $input, $context ) {
    return $self->_apply_action($input) if !$self->functions;
    return await $self->functions->transaction_p(
        async sub ($scope) {
            my $replayed =
              await _find_command_action_p( $scope, $input->{command_id} );
            if ($replayed) {
                return await $self->_finish_leftover_action_p( $scope,
                    $replayed, $input );
            }
            my $target = GPForum::Infrastructure::ResultRow->from(
                await $scope->row_p( 'moderation_target',
                    _target_values($input) ) );
            return undef if !$target;

            my $idempotent = $input->{applied}->($target) ? 1 : 0;
            if ($idempotent) {
                my $existing =
                  await _action_row_p( $scope, _latest_values($input) );
                return _idempotent_answer($existing) if $existing;
            }

            my $previous_state = column_of( $target, 'moderation_state' );
            if ( !$idempotent ) {
                my $changes = _target_changes( $input, $target );
                await $scope->row_p( 'moderation_target_update',
                    _target_update_values( $input, $changes ) );
                %{$target} = ( %{$target}, %{$changes} );
            }

            return await $self->_record_action_p( $scope,
                _action_input( $input, $idempotent, $previous_state ) );
        },
        $context
    );
}

sub _idempotent_answer ($existing) {
    return {
        action     => _action_hash($existing),
        idempotent => 1,
        ok         => 1,
        skipped    => 1,
    };
}

sub _target_changes ( $input, $target ) {
    my $updates = $input->{updates};
    return ref $updates eq 'CODE' ? $updates->($target) : $updates;
}

# What _record_action records for an applied (or idempotent) action.
sub _action_input ( $input, $idempotent, $previous_state ) {
    return {
        actor_user_id  => $input->{actor_user_id},
        action_type    => $input->{action_type},
        command_id     => $input->{command_id},
        correlation_id => $input->{correlation_id},
        created_at     => $input->{created_at},
        metadata       => {
            command_id     => $input->{command_id},
            idempotent     => $idempotent,
            previous_state => $previous_state,
        },
        reason      => $input->{reason},
        target_id   => $input->{target_id},
        target_type => $input->{target_type},
    };
}

sub _target ( $self, $input ) {
    return $self->schema->resultset( $input->{resultset} )
      ->find( $input->{target_id} )
      if !$self->functions;
    return GPForum::Infrastructure::ResultRow->from(
        $self->functions->row( 'moderation_target', _target_values($input) ) );
}

sub _target_values ($input) {
    return {
        kind      => $input->{lock_kind},
        target_id => $input->{target_id},
        hold      => 1
    };
}

sub _update_target ( $self, $row, $input, $changes ) {
    return $row->update($changes) if !$self->functions;
    $self->functions->row( 'moderation_target_update',
        _target_update_values( $input, $changes ) );
    %{$row} = ( %{$row}, %{$changes} );
    return $row;
}

sub _target_update_values ( $input, $changes ) {
    return {
        kind      => $input->{lock_kind},
        target_id => $input->{target_id},
        changes   => $changes
    };
}

sub _action_row ( $self, $input ) {
    return $self->schema->resultset('ModerationAction')
      ->find( $input->{action_id} )
      if !$self->functions;
    return GPForum::Infrastructure::ResultRow->from(
        $self->functions->row(
            'moderation_action_find', _action_find_values($input)
        )
    );
}

async sub _action_row_p ( $scope, $input ) {
    return GPForum::Infrastructure::ResultRow->from(
        await $scope->row_p(
            'moderation_action_find', _action_find_values($input)
        )
    );
}

sub _action_find_values ($input) {
    return {
        action_id   => undef,
        command_id  => undef,
        action_type => undef,
        target_type => undef,
        target_id   => undef,
        %{$input}
    };
}

sub _latest_action ( $self, $input ) {
    return $self->_action_row( _latest_values($input) )
      if $self->functions;
    return $self->schema->resultset('ModerationAction')->search_rs(
        {
            %{ _latest_values($input) }, reversed_at => undef
        },
        { order_by => { -desc => 'created_at' }, rows => 1 }
    )->single;
}

sub _latest_values ($input) {
    return { map { $_ => $input->{$_} } qw(action_type target_type target_id) };
}

sub _update_action ( $self, $row, $changes ) {
    return $row->update($changes) if !$self->functions;
    my $updated = $self->functions->row( 'moderation_action_update',
        _action_update_values( $row, $changes ) );
    return undef if !$updated;
    %{$row} = ( %{$row}, %{$changes} );
    return $row;
}

sub _action_update_values ( $row, $changes ) {
    return {
        action_id => column_of( $row, 'moderation_action_id' ),
        changes   => $changes
    };
}

# What a reversal answers: the action's id, and when and by whom it was
# reversed.
sub _reversal ($action) {
    return { map { $_ => column_of( $action, $_ ) }
          qw(moderation_action_id reversed_at reversed_by_user_id) };
}

sub _state ($target) {
    return column_of( $target, 'moderation_state' ) || q{};
}

sub _is_hidden ($target) {
    return _state($target) eq $STATE_HIDDEN ? 1 : 0;
}

# locked_at is the lock: it is what refuses a reply and what the page shows,
# and hidden, the state no longer says locked at all. A state saying locked
# without it does not count as locked: else locking that thread would be a
# repeat and replies would stay open.
sub _is_locked ($thread) {
    return defined column_of( $thread, 'locked_at' ) ? 1 : 0;
}

sub _is_pinned ($thread) {
    return column_of( $thread, 'pinned' ) ? 1 : 0;
}

sub _unless_hidden ( $thread, $state ) {
    return _is_hidden($thread) ? $STATE_HIDDEN : $state;
}

sub _find_command_action ( $self, $command_id ) {
    if ( !defined $command_id || !length $command_id ) {
        return undef;
    }

    return $self->_action_row( { command_id => $command_id } )
      if $self->functions;
    return $self->schema->resultset('ModerationAction')
      ->search_rs( { command_id => $command_id }, { rows => 1 }, )
      ->single;
}

async sub _find_command_action_p ( $scope, $command_id ) {
    return undef if !defined $command_id || !length $command_id;
    return await _action_row_p( $scope, { command_id => $command_id } );
}

# A concurrent request that recorded this command, or a minted id already
# stored under it, is answered by the action the command recorded; a minted
# id with none is minted once more.
sub _record_action ( $self, $input ) {
    my $insert = sub {
        my $action = $self->_new_action($input);
        if ( $self->functions ) {
            $self->functions->row( 'moderation_action_insert',
                { values => $action } );
        }
        else {
            $self->schema->resultset('ModerationAction')->create($action);
        }

        return $action;
    };
    my ( $created, $error ) =
      GPForum::Infrastructure::UniqueConflict->attempt( $self->schema,
        $insert );
    if ( !$created ) {
        my $conflict = GPForum::X::Conflict->caught($error);
        if ( _command_recorded($conflict) ) {
            my $existing = $self->_find_command_action( $input->{command_id} );
            if ($existing) {
                return $self->_finish_leftover_action( $existing, $input );
            }
        }
        if ( !_id_taken($conflict) ) {
            GPForum::Infrastructure::UniqueConflict->rethrow($error);
        }
        ( $created, $error ) =
          GPForum::Infrastructure::UniqueConflict->attempt( $self->schema,
            $insert );
        if ( !$created ) {
            GPForum::Infrastructure::UniqueConflict->rethrow($error);
        }
    }

    $self->_record_event_and_audit(
        {
            action         => $created,
            correlation_id => $input->{correlation_id},
        }
    );

    return { action => $created, ok => 1 };
}

# _record_action inside a pooled asynchronous transaction: each insert
# attempt runs in a savepoint of it.
async sub _record_action_p ( $self, $scope, $input ) {
    my $insert = async sub ($savepoint) {
        my $action = $self->_new_action($input);
        await $savepoint->row_p( 'moderation_action_insert',
            { values => $action } );
        return $action;
    };
    my ( $created, $error ) =
      await GPForum::Infrastructure::UniqueConflict->attempt_p( $scope,
        $insert );
    if ( !$created ) {
        my $conflict = GPForum::X::Conflict->caught($error);
        if ( _command_recorded($conflict) ) {
            my $existing =
              await _find_command_action_p( $scope, $input->{command_id} );
            if ($existing) {
                return await $self->_finish_leftover_action_p( $scope,
                    $existing, $input );
            }
        }
        if ( !_id_taken($conflict) ) {
            GPForum::Infrastructure::UniqueConflict->rethrow($error);
        }
        ( $created, $error ) =
          await GPForum::Infrastructure::UniqueConflict->attempt_p( $scope,
            $insert );
        if ( !$created ) {
            GPForum::Infrastructure::UniqueConflict->rethrow($error);
        }
    }

    await $self->_record_p(
        $scope,
        $self->_action_records(
            {
                action         => $created,
                correlation_id => $input->{correlation_id},
            }
        )
    );

    return { action => $created, ok => 1 };
}

sub _new_action ( $self, $input ) {
    return {
        actor_user_id        => $input->{actor_user_id},
        action_type          => $input->{action_type},
        command_id           => $input->{command_id},
        created_at           => $input->{created_at},
        metadata             => $input->{metadata} || {},
        moderation_action_id => $self->id_service->uuid,
        reason               => $input->{reason},
        reversed_at          => undef,
        reversed_by_user_id  => undef,
        target_id            => $input->{target_id},
        target_type          => $input->{target_type},
    };
}

sub _id_taken ($conflict) {
    return $conflict && $conflict->on($ID_CONSTRAINT) ? 1 : 0;
}

# The insert met an action already stored: under its id, or under the
# command's.
sub _command_recorded ($conflict) {
    return _id_taken($conflict)
      || ( $conflict && $conflict->on($COMMAND_CONSTRAINT) ) ? 1 : 0;
}

# An earlier attempt may have committed the action without its event.
sub _finish_leftover_action ( $self, $existing, $input ) {
    if ( !$self->recorder->event_recorded( _event_key($existing) ) ) {
        $self->_record_event_and_audit(
            {
                action         => $existing,
                correlation_id => $input->{correlation_id},
            }
        );
    }

    return _leftover_answer($existing);
}

async sub _finish_leftover_action_p ( $self, $scope, $existing, $input ) {
    my $recorded = await $scope->row_p( 'ops_event_recorded',
        { key => _event_key($existing) } );
    if ( !$recorded->{recorded} ) {
        await $self->_record_p(
            $scope,
            $self->_action_records(
                {
                    action         => $existing,
                    correlation_id => $input->{correlation_id},
                }
            )
        );
    }

    return _leftover_answer($existing);
}

sub _event_key ($action) {
    return join q{:},
      map { column_of( $action, $_ ) }
      qw(action_type target_type target_id moderation_action_id);
}

sub _leftover_answer ($existing) {
    return {
        action   => _action_hash($existing),
        ok       => 1,
        replayed => 1,
    };
}

sub _action_hash ($row) {
    if ( ref $row eq 'HASH' ) {
        return { %{$row} };
    }
    if ( $row && $row->can('data') ) {
        return { %{ $row->data } };
    }

    return {
        action_type          => column_of( $row, 'action_type' ),
        actor_user_id        => column_of( $row, 'actor_user_id' ),
        command_id           => column_of( $row, 'command_id' ),
        created_at           => column_of( $row, 'created_at' ),
        metadata             => column_of( $row, 'metadata' ),
        moderation_action_id => column_of( $row, 'moderation_action_id' ),
        reason               => column_of( $row, 'reason' ),
        target_id            => column_of( $row, 'target_id' ),
        target_type          => column_of( $row, 'target_type' ),
    };
}

sub _record_event_and_audit ( $self, $input ) {
    my ( $event, $audit ) = $self->_action_records($input);
    $self->recorder->record_event( %{$event} );
    $self->recorder->record_audit( %{$audit} );

    return;
}

# The event and the audit entry of an action.
sub _action_records ( $self, $input ) {
    my $recorded = {
        action         => $input->{action},
        correlation_id => $input->{correlation_id} || $self->id_service->uuid,
    };
    return (
        $self->events->action_envelope($recorded),
        $self->events->action_audit($recorded),
    );
}

# An event and its audit entry, written as record_event and record_audit
# write them, on the transaction's call layer.
async sub _record_p ( $self, $scope, $event, $audit ) {
    await $scope->row_p( 'ops_record_event',
        $self->recorder->event_call( %{$event} ) );
    await $scope->row_p( 'ops_record_audit',
        $self->recorder->audit_call( %{$audit} ) );
    return;
}

1;

__END__

=head1 NAME

GPForum::Service::Moderation::ActionStore - Hide, restore, lock, unlock, pin and unpin content and record each moderation action once.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $actions = GPForum::Service::Moderation::ActionStore->new(
        schema => $schema,
    );
    my $result = $actions->hide_post(
        {
            actor_user_id  => $moderator_id,
            command_id     => $command_id,
            correlation_id => $correlation_id,
            post_id        => $post_id,
            reason         => 'spam',
        }
    );
    # { ok => 1, action => {...} }, with replayed or skipped on a repeat,
    # or undef when the post does not exist

    $actions->lock_thread(
        {
            actor_user_id => $moderator_id,
            command_id    => $other_command_id,
            reason        => 'off topic',
            thread_id     => $thread_id,
        }
    );
    $actions->reverse_action( $action_id, $moderator_id, 'appeal upheld' );

=head1 DESCRIPTION

The write side of moderation for L<GPForum::Service::Moderation::Workflow>.
Each action changes the target's C<moderation_state> (and a post's
C<hidden_at> or a thread's C<locked_at>), inserts a C<moderation_actions> row
and records the matching event, its outbox message and the audit entry
through L<GPForum::Infrastructure::EventRecorder>, with shapes from
L<GPForum::Service::Moderation::Event>; all of it in one transaction, after
the target row has been locked with C<SELECT ... FOR UPDATE> so two
moderators acting on the same post or thread take turns.

A thread has no C<hidden_at>: hidden is its C<moderation_state> alone, and
when it was hidden is the action row's C<created_at>. The same column also
says C<locked>, so hidden takes precedence there: locking or unlocking a
hidden thread changes C<locked_at> and leaves it C<hidden>, and showing it
again sets C<locked> or C<visible> by C<locked_at>.

Every action is safe to repeat:

=over 4

=item * A command id that already has an action row is a replay: nothing
changes, the stored action comes back with C<< replayed => 1 >>, and the
action's event and audit are written first if an earlier attempt left the
row without them.

=item * A target where the action is already done is not updated: a post
or thread already hidden, a post already visible, a thread already not
hidden, locked (C<locked_at> set, whatever the state says) or unlocked (no
C<locked_at> and a state other than C<locked>). When an unreversed action
of the same type exists for it, that action comes back with
C<< skipped => 1 >> and C<< idempotent => 1 >>; otherwise a new action is
recorded with C<< idempotent => 1 >> in its metadata.

=item * A unique conflict on the command id (a concurrent request with the
same command) replays the row that won; a conflict on the generated action
id is retried once with a fresh id. Inserts run under savepoints through
L<GPForum::Infrastructure::UniqueConflict>.

=back

=head1 SUBROUTINES/METHODS

=head2 new

Mojo::Base constructor. C<schema> is required; C<clock>, C<id_service>,
C<recorder> and C<events> have defaults.

=head2 hide_post

Takes a hash reference with C<post_id>, C<actor_user_id>, C<reason> and the
optional C<command_id> and C<correlation_id> (a fresh one for the event
when absent). Sets the post's state to C<hidden> and stamps C<hidden_at>,
and records a C<post.hidden> action. Returns C<< { ok => 1, action => \%action } >>,
the replay or skip results described above, or C<undef> when the post does
not exist. The action hash holds C<moderation_action_id>, C<action_type>,
C<target_type>, C<target_id>, C<actor_user_id>, C<command_id>, C<reason>,
C<created_at> and C<metadata> (C<command_id>, C<idempotent>,
C<previous_state>).

=head2 hide_post_p

L</hide_post> as a promise, with an optional query context last, in one
transaction on the worker's pooled asynchronous connections.

=head2 restore_post

As L</hide_post>, setting the post's state to C<visible>, clearing
C<hidden_at> and recording C<post.restored>.

=head2 restore_post_p

L</restore_post> as a promise, with an optional query context last, in one
transaction on the worker's pooled asynchronous connections.

=head2 hide_thread

As L</hide_post> for a thread, keyed by C<thread_id>: state C<hidden>,
action C<thread.hidden>. Nothing else on the thread changes; a locked
thread keeps its C<locked_at>.

=head2 hide_thread_p

L</hide_thread> as a promise, with an optional query context last, in one
transaction on the worker's pooled asynchronous connections.

=head2 restore_thread

As L</hide_thread>, setting the state back to C<locked> when C<locked_at>
is set and to C<visible> otherwise, and recording C<thread.restored>. A
thread that is not hidden is left as it is.

=head2 restore_thread_p

L</restore_thread> as a promise, with an optional query context last, in one
transaction on the worker's pooled asynchronous connections.

=head2 lock_thread

As L</hide_thread>, stamping C<locked_at>, setting the state to C<locked>
unless the thread is hidden, which it stays, and recording
C<thread.locked>.

=head2 lock_thread_p

L</lock_thread> as a promise, with an optional query context last, in one
transaction on the worker's pooled asynchronous connections.

=head2 unlock_thread

As L</hide_thread>, clearing C<locked_at>, setting the state to C<visible>
unless the thread is hidden, which it stays, and recording
C<thread.unlocked>.

=head2 unlock_thread_p

L</unlock_thread> as a promise, with an optional query context last, in one
transaction on the worker's pooled asynchronous connections.

=head2 pin_thread

As L</hide_thread>, setting C<pinned> and recording C<thread.pinned>; the
state, hidden or locked, is left as it is. A pinned thread is a repeat.

=head2 pin_thread_p

L</pin_thread> as a promise, with an optional query context last, in one
transaction on the worker's pooled asynchronous connections.

=head2 unpin_thread

As L</pin_thread>, clearing C<pinned> and recording C<thread.unpinned>.

=head2 unpin_thread_p

L</unpin_thread> as a promise, with an optional query context last, in one
transaction on the worker's pooled asynchronous connections.

=head2 reverse_action

Takes an action id, the id of the user reversing it and a reason. In a
transaction, stamps the action's C<reversed_at> and C<reversed_by_user_id>
and records a C<moderation_action.reversed> event and its audit entry.
Returns C<< { moderation_action_id, reversed_at, reversed_by_user_id } >>.
An action already reversed, before or by a reversal that committed while
this one ran, returns that reversal and writes nothing; an unknown action
id returns nothing. The target's state is not changed here.

=head2 reverse_action_p

L</reverse_action> as a promise, with an optional query context last, in one
transaction on the worker's pooled asynchronous connections.

=head1 DIAGNOSTICS

A missing target returns C<undef> and a missing action an empty return;
neither is thrown. Database errors other than the handled unique conflicts
are rethrown and the transaction rolls back.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Infrastructure::EventRecorder>,
L<GPForum::Infrastructure::Storage>,
L<GPForum::Infrastructure::UniqueConflict>, L<GPForum::X::Conflict>,
L<GPForum::Infrastructure::Row>, L<GPForum::Infrastructure::Id>,
L<GPForum::Service::Clock>, L<GPForum::Service::Moderation::Event>.

Extends L<GPForum::Base>: built without C<schema> it throws
L<GPForum::X::Argument>.

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
