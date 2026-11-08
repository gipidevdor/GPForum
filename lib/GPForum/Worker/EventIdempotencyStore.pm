# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Worker::EventIdempotencyStore;

use Const::Fast;
use GPForum::Infrastructure::Id;
use GPForum::Infrastructure::UniqueConflict;
use GPForum::Service::Clock;
use GPForum::X::Conflict;
use Mojo::Base 'GPForum::Base', -signatures;
use v5.40;

use GPForum::Infrastructure::SqlFunction;

our $VERSION = '0.001';

has functions => \&GPForum::Infrastructure::SqlFunction::for_service;

# How long a claim is honoured before another worker may take it over. A
# worker killed between claiming and finishing would otherwise park its event
# forever, because the claim row it left behind looks exactly like one held by
# a worker that is still running. Shorter than the outbox's five tries at
# 60 s, 120 s, 180 s and 240 s apart (Service::Outbox::Retry): a message
# whose handler's claim is held waits for its next try, and with a lease
# of 900 s the fifth try came, and the message was a dead letter, before
# the claim of a worker that had died could be taken over.
const my $CLAIM_LEASE_SECONDS => 300;
const my $KEY_CONSTRAINT      => 'event_idempotency_keys_pkey';

__PACKAGE__->requires(qw(schema));
has clock         => sub { return GPForum::Service::Clock->new; };
has lease_seconds => $CLAIM_LEASE_SECONDS;

sub is_done ( $self, $key ) {
    if ( $self->functions ) {
        return $self->_claim( 'is_done', $key );
    }
    my $row = $self->_find($key);
    return 0 if !$row;

    return defined $self->_column( $row, 'completed_at' ) ? 1 : 0;
}

# Returns the claim's token only for the worker that owns the event, and
# false for every other. The primary key does the excluding: the first insert
# wins and every later one conflicts, so two workers can no longer both pass
# this point and both run the side effect. The token names this run of the
# handler: mark_failed releases the claim only when it is still the one this
# run took, not the one a worker took over after this run's lease ran out.
sub begin ( $self, $key, $event_id = undef ) {
    if ( $self->functions ) {
        my $token = GPForum::Infrastructure::Id->uuid;
        return $self->_claim( 'begin', $key,
            _event_id( $key, { event_id => $event_id } ), $token )
          ? $token
          : 0;
    }
    my ( $claimed, $error ) = GPForum::Infrastructure::UniqueConflict->attempt(
        $self->schema,
        sub {
            $self->_insert_claim( $key, $event_id );
            return 1;
        }
    );
    return 1 if $claimed;

    if ( !_claimed_elsewhere($error) ) {
        GPForum::Infrastructure::UniqueConflict->rethrow($error);
    }

    return $self->_take_over($key);
}

# The side effect has happened, so the event is handled whoever holds the
# claim now: completion is recorded whatever the token.
sub mark_done ( $self, $key, $result, $token = undef ) {
    if ( $self->functions ) {
        return $self->_claim( 'done', $key, _event_id( $key, $result ),
            $token );
    }
    my $row = $self->_find($key);

    # Nothing claimed it, which means an older caller reached mark_done
    # without begin. Recording completion directly keeps that path idempotent.
    return $self->_insert_completed( $key, $result ) if !$row;

    $row->update( { completed_at => $self->clock->now_iso8601 } );

    return 1;
}

# Releasing the claim is what makes a failure retryable. Leaving the row would
# suppress every later attempt at the same event, turning one transient error
# into permanent silence. Only the run that holds the claim releases it: a
# run whose lease ran out, and whose claim another worker took over, leaves
# that worker's claim alone.
sub mark_failed ( $self, $key, $error, $token = undef ) {
    if ( $self->functions ) {
        return $self->_claim( 'failed', $key, undef, $token );
    }
    my $row = $self->_find($key);
    return 1 if !$row;
    return 1 if defined $self->_column( $row, 'completed_at' );

    $row->delete;

    return 1;
}

sub _claim ( $self, $operation, $key, $event_id = undef, $token = undef ) {
    return $self->functions->row(
        'ops_event_claim',
        {
            operation      => $operation,
            key            => $key,
            event_id       => $event_id,
            now            => $self->clock->now_iso8601,
            expired_before =>
              $self->clock->epoch_plus_iso8601( -$self->lease_seconds ),
            token => $token,
        }
    )->{claimed} ? 1 : 0;
}

# One statement, so the database is the arbiter of both the expiry and the
# race. Reading the row and then updating it would reintroduce exactly the
# check-then-act gap this class exists to close, and comparing timestamps in
# Perl would have to reconcile now_iso8601 with whatever the driver renders a
# timestamptz as.
sub _take_over ( $self, $key ) {
    my $updated = $self->_resultset->search_rs(
        {
            idempotency_key => $key,
            completed_at    => undef,
            created_at      => {
                q{<} =>
                  $self->clock->epoch_plus_iso8601( -$self->lease_seconds ),
            },
        }
    )->update( { created_at => $self->clock->now_iso8601 } );

    # Numeric, not boolean. DBI reports "no rows matched, but the statement
    # succeeded" as the string "0E0", which is true in boolean context: every
    # worker that lost the insert race would have been told it had taken the
    # claim over, and would have run the side effect anyway.
    return _affected($updated) > 0 ? 1 : 0;
}

sub _insert_claim ( $self, $key, $event_id ) {
    $self->_resultset->create(
        {
            completed_at    => undef,
            created_at      => $self->clock->now_iso8601,
            event_id        => _event_id( $key, { event_id => $event_id } ),
            idempotency_key => $key,
        }
    );

    return 1;
}

sub _insert_completed ( $self, $key, $result ) {
    my ( $inserted, $error ) = GPForum::Infrastructure::UniqueConflict->attempt(
        $self->schema,
        sub {
            my $now = $self->clock->now_iso8601;
            $self->_resultset->create(
                {
                    completed_at    => $now,
                    created_at      => $now,
                    event_id        => _event_id( $key, $result ),
                    idempotency_key => $key,
                }
            );
            return 1;
        }
    );
    return 1 if $inserted;

    if ( !_claimed_elsewhere($error) ) {
        GPForum::Infrastructure::UniqueConflict->rethrow($error);
    }

    return 1;
}

# The key's own row was there first: a unique violation on the primary key
# and no other error, asked of the GPForum::X::Conflict that attempt returns.
sub _claimed_elsewhere ($error) {
    my $conflict = GPForum::X::Conflict->caught($error);

    return $conflict && $conflict->on($KEY_CONSTRAINT) ? 1 : 0;
}

sub _affected ($updated) {
    return 0 if !defined $updated;

    return $updated + 0;
}

sub _column ( $, $row, $name ) {
    return $row->{$name} if ref $row eq 'HASH';

    return $row->$name;
}

sub _find ( $self, $key ) {
    return $self->_resultset->find($key);
}

sub _resultset ($self) {
    return $self->schema->resultset('EventIdempotencyKey');
}

sub _event_id ( $key, $result ) {
    my $from_result = _result_event_id($result);
    if ( length $from_result ) {
        return $from_result;
    }

    return _key_event_id($key);
}

sub _result_event_id ($result) {
    if ( ref $result ne 'HASH' ) {
        return q{};
    }

    my $event_id = $result->{event_id};
    if ( !defined $event_id || !length $event_id ) {
        return q{};
    }

    return $event_id;
}

sub _key_event_id ($key) {
    my ($event_id) = $key =~ m/:([^:]+)\z/msx;
    if ( defined $event_id && length $event_id ) {
        return $event_id;
    }

    return $key;
}

1;
