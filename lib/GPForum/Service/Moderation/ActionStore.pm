# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Moderation::ActionStore;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -signatures, -async_await;
use v5.40;

use GPForum::Infrastructure::EventRecorder;
use GPForum::Infrastructure::ResultRow;
use GPForum::Infrastructure::Row qw(column_of);
use GPForum::Infrastructure::SqlFunction;
use GPForum::Infrastructure::UniqueConflict;
use GPForum::Service::Clock;
use GPForum::Service::Moderation::Event;
use GPForum::X::Conflict;
use GPForum::X::Unavailable;
use Mojo::Util qw(monkey_patch);

our $VERSION = '0.001';

const my $COMMAND_CONSTRAINT => 'idx_moderation_actions_command_id';
const my $ID_CONSTRAINT      => 'moderation_actions_pkey';
const my $STATE_VISIBLE      => 'visible';
const my $STATE_HIDDEN       => 'hidden';
const my $STATE_LOCKED       => 'locked';

has clock      => sub { return GPForum::Service::Clock->new; };
has id_service => sub {
    require GPForum::Infrastructure::Id;
    return GPForum::Infrastructure::Id->new;
};
has recorder => \&GPForum::Infrastructure::EventRecorder::for_service;
__PACKAGE__->requires(qw(schema));
has functions => \&GPForum::Infrastructure::SqlFunction::for_service;
has events    => sub { return GPForum::Service::Moderation::Event->new; };

# Each action as data: the event it records, the kind of target it changes
# (whose id the input names as post_id or thread_id), whether the target is
# already where the action takes it, and the changes that take it there,
# given the target and the action's time.
#
# A thread keeps two facts in one moderation_state: hidden, and locked. The
# lock has its own column, locked_at, which is what refuses replies; hidden
# has none on a thread, so the state is all there is of it. Hiding wins the
# shared column: locking or unlocking a hidden thread leaves it hidden
# (overwriting the state would publish it), and showing it again puts back
# whichever of locked and visible locked_at says. A thread is unlocked once
# neither locked_at nor its state says locked, so unlocking such a thread
# still puts its state right. The pin is a flag of its own beside the state.
# Threads have no hidden_at, unlike posts: when one was hidden is the
# created_at of the action recorded with it.
my %ACTIONS = (
    hide_post => {
        event   => 'post.hidden',
        target  => 'post',
        applied => \&_is_hidden,
        changes => sub ( $post, $at ) {
            return { hidden_at => $at, moderation_state => $STATE_HIDDEN };
        },
    },
    restore_post => {
        event   => 'post.restored',
        target  => 'post',
        applied => sub ($post) { return _state($post) eq $STATE_VISIBLE },
        changes => sub ( $post, $at ) {
            return { hidden_at => undef, moderation_state => $STATE_VISIBLE };
        },
    },
    hide_thread => {
        event   => 'thread.hidden',
        target  => 'thread',
        applied => \&_is_hidden,
        changes => sub ( $thread, $at ) {
            return { moderation_state => $STATE_HIDDEN };
        },
    },
    restore_thread => {
        event   => 'thread.restored',
        target  => 'thread',
        applied => sub ($thread) { return !_is_hidden($thread) },
        changes => sub ( $thread, $at ) {
            return {
                moderation_state => _is_locked($thread)
                ? $STATE_LOCKED
                : $STATE_VISIBLE
            };
        },
    },
    lock_thread => {
        event   => 'thread.locked',
        target  => 'thread',
        applied => \&_is_locked,
        changes => sub ( $thread, $at ) {
            return {
                locked_at        => $at,
                moderation_state => _unless_hidden( $thread, $STATE_LOCKED ),
            };
        },
    },
    unlock_thread => {
        event   => 'thread.unlocked',
        target  => 'thread',
        applied => sub ($thread) {
            return !_is_locked($thread) && _state($thread) ne $STATE_LOCKED;
        },
        changes => sub ( $thread, $at ) {
            return {
                locked_at        => undef,
                moderation_state => _unless_hidden( $thread, $STATE_VISIBLE ),
            };
        },
    },
    pin_thread => {
        event   => 'thread.pinned',
        target  => 'thread',
        applied => \&_is_pinned,
        changes => sub ( $thread, $at ) { return { pinned => 1 } },
    },
    unpin_thread => {
        event   => 'thread.unpinned',
        target  => 'thread',
        applied => sub ($thread) { return !_is_pinned($thread) },
        changes => sub ( $thread, $at ) { return { pinned => 0 } },
    },
);

# Each action's promise method is _act_p on its entry; each operation's
# blocking twin is its promise method on the blocking layer (ADR 0177).
for my $name ( keys %ACTIONS ) {
    monkey_patch __PACKAGE__, "${name}_p",
      sub ( $self, $input, $context = undef ) {
        return $self->_act_p( $ACTIONS{$name}, $input, $context );
      };
}
GPForum::Infrastructure::SqlFunction->blocking_twins( keys %ACTIONS,
    'reverse_action' );

# Under a hold on the target, a command already recorded is replayed. A
# target already in the state the action sets answers with the action that
# set it; with none on record, the action is recorded as idempotent and the
# target left as it is.
async sub _act_p ( $self, $action, $input, $context ) {
    my $at   = $self->clock->now_iso8601;
    my $kind = $action->{target};
    my $spec = {
        %{$input},
        action_type => $action->{event},
        created_at  => $at,
        target_id   => $input->{"${kind}_id"},
        target_type => $kind,
    };
    return await $self->_functions->transaction_p(
        async sub ($scope) {
            my $replayed =
              await _find_command_action_p( $scope, $spec->{command_id} );
            return await $self->_finish_leftover_action_p( $scope, $replayed,
                $spec )
              if $replayed;
            my $target = GPForum::Infrastructure::ResultRow->from(
                await $scope->row_p(
                    'moderation_target',
                    {
                        kind      => $kind,
                        target_id => $spec->{target_id},
                        hold      => 1
                    }
                )
            );
            return undef if !$target;

            my $idempotent = $action->{applied}->($target) ? 1 : 0;
            if ($idempotent) {
                my $existing = await _action_row_p(
                    $scope,
                    {
                        map { $_ => $spec->{$_} }
                          qw(action_type target_type target_id)
                    }
                );
                return _idempotent_answer($existing) if $existing;
            }
            else {
                await $scope->row_p(
                    'moderation_target_update',
                    {
                        kind      => $kind,
                        target_id => $spec->{target_id},
                        changes   => $action->{changes}->( $target, $at ),
                    }
                );
            }

            return await $self->_record_action_p(
                $scope,
                _action_input(
                    $spec, $idempotent,
                    column_of( $target, q{moderation_state} )
                )
            );
        },
        $context
    );
}

# Reverses an action once. A reversal committed meanwhile changed the
# action first: the update leaves it as that one made it, and this answers
# that reversal, with no second event or audit entry.
async sub reverse_action_p ( $self, $action_id, $reversed_by_user_id,
    $reason, $context = undef )
{
    return await $self->_functions->transaction_p(
        async sub ($scope) {
            my $timestamp = $self->clock->now_iso8601;
            my $action =
              await _action_row_p( $scope, { action_id => $action_id } );
            return undef if !$action;

            return _reversal($action)
              if defined column_of( $action, 'reversed_at' );

            my $changes = {
                reversed_at         => $timestamp,
                reversed_by_user_id => $reversed_by_user_id,
            };
            my $updated = await $scope->row_p( 'moderation_action_update',
                { action_id => $action_id, changes => $changes } );
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

sub _idempotent_answer ($existing) {
    return {
        action     => _action_hash($existing),
        idempotent => 1,
        ok         => 1,
        skipped    => 1,
    };
}

# What _record_action_p records for an applied (or idempotent) action.
sub _action_input ( $spec, $idempotent, $previous_state ) {
    return {
        actor_user_id  => $spec->{actor_user_id},
        action_type    => $spec->{action_type},
        command_id     => $spec->{command_id},
        correlation_id => $spec->{correlation_id},
        created_at     => $spec->{created_at},
        metadata       => {
            command_id     => $spec->{command_id},
            idempotent     => $idempotent,
            previous_state => $previous_state,
        },
        reason      => $spec->{reason},
        target_id   => $spec->{target_id},
        target_type => $spec->{target_type},
    };
}

async sub _action_row_p ( $scope, $input ) {
    return GPForum::Infrastructure::ResultRow->from(
        await $scope->row_p(
            'moderation_action_find',
            {
                action_id   => undef,
                command_id  => undef,
                action_type => undef,
                target_type => undef,
                target_id   => undef,
                %{$input}
            }
        )
    );
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
    return _state($target) eq $STATE_HIDDEN;
}

# locked_at is the lock: it is what refuses a reply and what the page shows,
# and hidden, the state no longer says locked at all. A state saying locked
# without it does not count as locked: else locking that thread would be a
# repeat and replies would stay open.
sub _is_locked ($thread) {
    return defined column_of( $thread, 'locked_at' );
}

sub _is_pinned ($thread) {
    return column_of( $thread, 'pinned' ) ? 1 : 0;
}

sub _unless_hidden ( $thread, $state ) {
    return _is_hidden($thread) ? $STATE_HIDDEN : $state;
}

async sub _find_command_action_p ( $scope, $command_id ) {
    return undef if !defined $command_id || !length $command_id;
    return await _action_row_p( $scope, { command_id => $command_id } );
}

# A concurrent request that recorded this command, or a minted id already
# stored under it, is answered by the action the command recorded; a minted
# id with none is minted once more. Each insert attempt runs in a savepoint.
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
            return await $self->_finish_leftover_action_p( $scope, $existing,
                $input )
              if $existing;
        }
        if ( !_id_taken($conflict) ) {
            GPForum::Infrastructure::UniqueConflict->rethrow($error);
        }
        $created =
          await GPForum::Infrastructure::UniqueConflict->once_more_p( $scope,
            $insert );
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

    return {
        action   => _action_hash($existing),
        ok       => 1,
        replayed => 1,
    };
}

sub _event_key ($action) {
    return join q{:},
      map { column_of( $action, $_ ) }
      qw(action_type target_type target_id moderation_action_id);
}

sub _action_hash ($row) {
    return { %{$row} }         if ref $row eq 'HASH';
    return { %{ $row->data } } if $row && $row->can('data');
    return {
        map { $_ => column_of( $row, $_ ) }
          qw(action_type actor_user_id command_id created_at metadata
          moderation_action_id reason target_id target_type)
    };
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

sub _functions ($self) {
    return $self->functions // GPForum::X::Unavailable->throw(
        message => 'moderation actions need the PostgreSQL function layer' );
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
the target row has been read held (C<FOR UPDATE>) so two moderators acting on
the same post or thread take turns.

The eight actions are one table, C<%ACTIONS>: the event each records, the
kind of target it changes, whether the target is already there, and the
changes that take it there. One body applies any of them, as a promise;
each blocking method runs that body on the blocking call layer (ADR 0177).

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

=head2 restore_post

As L</hide_post>, setting the post's state to C<visible>, clearing
C<hidden_at> and recording C<post.restored>.

=head2 hide_thread

As L</hide_post> for a thread, keyed by C<thread_id>: state C<hidden>,
action C<thread.hidden>. Nothing else on the thread changes; a locked
thread keeps its C<locked_at>.

=head2 restore_thread

As L</hide_thread>, setting the state back to C<locked> when C<locked_at>
is set and to C<visible> otherwise, and recording C<thread.restored>. A
thread that is not hidden is left as it is.

=head2 lock_thread

As L</hide_thread>, stamping C<locked_at>, setting the state to C<locked>
unless the thread is hidden, which it stays, and recording
C<thread.locked>.

=head2 unlock_thread

As L</hide_thread>, clearing C<locked_at>, setting the state to C<visible>
unless the thread is hidden, which it stays, and recording
C<thread.unlocked>.

=head2 pin_thread

As L</hide_thread>, setting C<pinned> and recording C<thread.pinned>; the
state, hidden or locked, is left as it is. A pinned thread is a repeat.

=head2 unpin_thread

As L</pin_thread>, clearing C<pinned> and recording C<thread.unpinned>.

=head2 reverse_action

Takes an action id, the id of the user reversing it and a reason. In a
transaction, stamps the action's C<reversed_at> and C<reversed_by_user_id>
and records a C<moderation_action.reversed> event and its audit entry.
Returns C<< { moderation_action_id, reversed_at, reversed_by_user_id } >>.
An action already reversed, before or by a reversal that committed while
this one ran, returns that reversal and writes nothing; an unknown action
id returns nothing. The target's state is not changed here.

=head2 hide_post_p, restore_post_p, hide_thread_p, restore_thread_p, lock_thread_p, unlock_thread_p, pin_thread_p, unpin_thread_p

Each action above as a promise, with an optional query context last, in one
transaction on the worker's pooled asynchronous connections.

=head2 reverse_action_p

L</reverse_action> as a promise, with an optional query context last, in one
transaction on the worker's pooled asynchronous connections.

=head1 DIAGNOSTICS

Without the PostgreSQL function layer every action raises
L<GPForum::X::Unavailable>. A missing target returns C<undef> and a missing action an empty return;
neither is thrown. Database errors other than the handled unique conflicts
are rethrown and the transaction rolls back.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Infrastructure::EventRecorder>,
L<GPForum::Infrastructure::SqlFunction>,
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
