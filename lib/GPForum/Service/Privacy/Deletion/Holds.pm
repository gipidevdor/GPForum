# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Privacy::Deletion::Holds;

use Const::Fast;
use Mojo::Base 'GPForum::Service::Privacy::Deletion::Core', -async_await;
use v5.40;

use GPForum::Infrastructure::SqlFunction;

our $VERSION = '0.001';

const my $STATUS_PENDING  => 'pending';
const my $STATUS_APPROVED => 'approved';
const my $STATUS_HELD     => 'held';
const my $LEGAL_HOLD      => 'legal hold';

# Each step is written once, as its promise method (ADR 0177).
GPForum::Infrastructure::SqlFunction->blocking_twins(
    qw(hold_request release_hold));

# Holds a request under its lock. The hold itself is made by $make_hold_p,
# given the locked request and the transaction's call layer, in the same
# transaction: a request completed or rejected is closed, and refused
# before any hold is made, where a hold on it -- a stale review page, or a
# hold that raced the erasure -- put an erased member's request back to
# held.
async sub hold_request_p ( $self, $request_id, $actor_id, $reason,
    $make_hold_p, $context = undef )
{
    return await $self->call_layer->transaction_p(
        async sub ($db) {
            my $request =
              await $self->find_privacy_row_p( $db, 'DeletionRequest',
                $request_id, 1, $context );
            return undef                if !$request;
            return _closed($request_id) if !$self->_open_request($request);

            my $hold = await $make_hold_p->( $request, $db );
            my $held =
              await $self->open_hold_p( $db,
                $self->_held_input( $actor_id, $reason, $request, $hold ),
                $context );

            return { %{$held}, error => undef, ok => 1 };
        },
        $context
    );
}

# Ends a hold, and gives the request it held back to where the hold found
# it: approved when its erasure job waits, pending otherwise. Nothing ended
# a hold, so a held request could never be approved or erased. The held
# request is locked before the hold ends (api.privacy_release_hold), the
# order holding a request takes them in. Answers undef for a hold that is
# not, or no longer, in force.
async sub release_hold_p ( $self, $hold_id, $actor_id, $reason,
    $context = undef )
{
    return await $self->call_layer->transaction_p(
        async sub ($db) {
            my $timestamp = $self->clock->now_iso8601;
            my $released  = await $db->row_p( 'privacy_release_hold',
                _release_values( $hold_id, $timestamp ), $context );
            return undef                      if !$released;
            return _released_alone($released) if !$released->{request};

            my $input = _release(
                {
                    actor_id => $actor_id,
                    hold_id  => $hold_id,
                    job      => await $self->latest_row_p(
                        $db, $context,
                        $self->job_query(
                            $released->{request}{deletion_request_id}
                        )
                    ),
                    reason    => $reason,
                    released  => $released,
                    timestamp => $timestamp,
                }
            );
            await $self->set_request_status_p( $db, $input->{request},
                $input->{status}, $context );
            my $action =
              await $self->record_action_p( $db, $input->{request_id},
                _hold_ended_action($input), $context );
            await $self->record_privacy_event_and_audit_p( $db,
                $self->events->hold_ended($input), $context );

            return _released_answer( $input, $action );
        },
        $context
    );
}

# A request already held only reports the hold; otherwise it is held, and
# the action and the event are recorded.
async sub open_hold_p ( $self, $db, $input, $context ) {
    my $request_id = $self->request_id_of($input);
    my $action;
    if ( !$self->already_held( $input->{request} ) ) {
        await $self->set_request_status_p( $db, $input->{request},
            $STATUS_HELD, $context );
        $action = await $self->record_action_p( $db, $request_id,
            $self->_held_action($input), $context );
        await $self->record_privacy_event_and_audit_p( $db,
            $self->events->held($input), $context );
    }

    return _held( $request_id, $action );
}

sub already_held ( $self, $request ) {
    return $self->same_request_status( $request, $STATUS_HELD );
}

sub _held ( $request_id, $action ) {
    return {
        action     => $action,
        error      => 'retention_hold_active',
        ok         => 0,
        request_id => $request_id,
    };
}

sub _held_input ( $self, $actor_id, $reason, $request, $hold ) {
    return {
        actor_id  => $actor_id,
        hold      => $hold,
        reason    => $reason || $LEGAL_HOLD,
        request   => $request,
        timestamp => $self->clock->now_iso8601,
    };
}

sub _held_action ( $self, $input ) {
    return {
        action_type => 'held',
        actor_id    => $input->{actor_id},
        created_at  => $input->{timestamp},
        metadata    => {
            reason            => $input->{reason},
            retention_hold_id =>
              $self->record->column( $input->{hold}, 'retention_hold_id' ),
        },
    };
}

sub _closed ($request_id) {
    return {
        error      => 'deletion request is closed',
        ok         => 0,
        request_id => $request_id,
    };
}

# Pending, approved or held: a request a hold can still act on.
sub _open_request ( $self, $request ) {
    my $status = $self->record->column( $request, 'status' ) || q{};

    return
         $status eq $STATUS_PENDING
      || $status eq $STATUS_APPROVED
      || $status eq $STATUS_HELD ? 1 : 0;
}

sub _release_values ( $hold_id, $timestamp ) {
    return { hold_id => $hold_id, ended_at => $timestamp };
}

sub _released_alone ($released) {
    return { error => undef, hold => $released->{hold}, ok => 1 };
}

# The request a released hold held goes back to approved when its erasure
# job waits, to pending otherwise.
sub _release ($found) {
    my $released = $found->{released};
    return {
        actor_id   => $found->{actor_id},
        hold       => $released->{hold},
        hold_id    => $found->{hold_id},
        reason     => $found->{reason},
        request    => $released->{request},
        request_id => $released->{request}{deletion_request_id},
        status     => $found->{job} ? $STATUS_APPROVED : $STATUS_PENDING,
        timestamp  => $found->{timestamp},
    };
}

sub _hold_ended_action ($input) {
    return {
        action_type => 'hold_ended',
        actor_id    => $input->{actor_id},
        created_at  => $input->{timestamp},
        metadata    => {
            reason            => $input->{reason},
            retention_hold_id => $input->{hold_id},
            status            => $input->{status},
        },
    };
}

sub _released_answer ( $input, $action ) {
    return {
        action     => $action,
        error      => undef,
        hold       => $input->{hold},
        ok         => 1,
        request_id => $input->{request_id},
        status     => $input->{status},
    };
}

1;

__END__

=head1 NAME

GPForum::Service::Privacy::Deletion::Holds - Legal holds on a deletion request.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    # Part of GPForum::Service::Privacy::DeletionWorkflow; callers use that class.

=head1 DESCRIPTION

Place a hold on a request and release it, with the checks and answers that go with each. Each step is written once, as its promise method; the blocking methods are those bodies on the blocking layer (ADR 0177).

GPForum::Service::Privacy::DeletionWorkflow inherits it, so the object a caller builds has every method; this
file holds one part of that class so each part can be read by itself.

=head1 SUBROUTINES/METHODS

=head2 hold_request_p

Takes a request id, the acting user's id, a reason (default C<legal hold>),
a code reference that makes the hold, and an optional query context. The
code takes the locked request and the transaction's call layer and answers
a promise of the retention hold row, so the hold is made in the same
transaction. Returns undef when there is no
such request. Otherwise sets the request C<held>, records a C<held>
deletion action naming the hold and C<privacy.deletion_held>, and returns
C<< { ok => 1, error => undef, request_id, action } >>; C<action> is undef
when the request was already held and nothing was written.

=head2 release_hold_p

Takes a retention hold id, the acting user's id, a reason and an optional
query context; runs in one transaction. Returns undef
when no hold of that id is in force. Otherwise ends it and, when it held a
deletion request, gives the request back to C<approved> (its erasure job is
scheduled) or C<pending>, records a C<hold_ended> deletion action and
C<privacy.retention_hold_ended>, and returns
C<< { ok => 1, error => undef, hold, request_id, status, action } >>; for a
hold that held no request, C<< { ok => 1, error => undef, hold } >>. The held
request is locked before the hold ends, the order a hold takes them in.

=head2 hold_request, release_hold

The blocking twins of the promise methods above (ADR 0177): each runs its
promise method on the blocking layer, the process's own connection and the
transaction it holds, and returns its answer. The code that makes the hold
answers a promise there too.

=head2 open_hold_p

A step the parts of GPForum::Service::Privacy::DeletionWorkflow share.

=head2 already_held

A step the parts of GPForum::Service::Privacy::DeletionWorkflow share.

=head1 DIAGNOSTICS

As GPForum::Service::Privacy::DeletionWorkflow.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

As GPForum::Service::Privacy::DeletionWorkflow.

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
