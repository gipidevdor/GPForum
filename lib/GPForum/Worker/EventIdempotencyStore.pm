# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Worker::EventIdempotencyStore;

use Const::Fast;
use GPForum::Infrastructure::Id;
use GPForum::Service::Clock;
use GPForum::X::Unavailable;
use Mojo::Base 'GPForum::Base', -signatures, -async_await;
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

__PACKAGE__->requires(qw(schema));
has clock         => sub { return GPForum::Service::Clock->new; };
has lease_seconds => $CLAIM_LEASE_SECONDS;

# Each operation is written once, as its promise method (ADR 0177): one call
# to api.ops_event_claim, which is the arbiter of both the lease and the race.
GPForum::Infrastructure::SqlFunction->blocking_twins(
    qw(is_done begin mark_done mark_failed));

async sub is_done_p ( $self, $key ) {
    return await $self->_claim_p( 'is_done', $key );
}

# Answers the claim's token only for the worker that owns the event, and
# false for every other. The primary key does the excluding: the first insert
# wins and every later one conflicts, so two workers can no longer both pass
# this point and both run the side effect; a claim older than the lease is
# taken over. The token names this run of the handler: mark_failed releases
# the claim only when it is still the one this run took, not the one a
# worker took over after this run's lease ran out.
async sub begin_p ( $self, $key, $event_id = undef ) {
    my $token = GPForum::Infrastructure::Id->uuid;

    return (
        await $self->_claim_p(
            'begin',                                      $key,
            _event_id( $key, { event_id => $event_id } ), $token
        )
    ) ? $token : 0;
}

# The side effect has happened, so the event is handled whoever holds the
# claim now: completion is recorded whatever the token, and a key nothing
# claimed is recorded completed at once.
async sub mark_done_p ( $self, $key, $result, $token = undef ) {
    return await $self->_claim_p( 'done', $key, _event_id( $key, $result ),
        $token );
}

# Releasing the claim is what makes a failure retryable. Leaving the row would
# suppress every later attempt at the same event, turning one transient error
# into permanent silence. Only the run that holds the claim releases it: a
# run whose lease ran out, and whose claim another worker took over, leaves
# that worker's claim alone.
async sub mark_failed_p ( $self, $key, $error, $token = undef ) {
    return await $self->_claim_p( 'failed', $key, undef, $token );
}

async sub _claim_p ( $self, $operation, $key, $event_id = undef,
    $token = undef )
{
    my $row = await $self->_functions->row_p(
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
    );

    return $row->{claimed} ? 1 : 0;
}

sub _functions ($self) {
    return $self->functions // GPForum::X::Unavailable->throw( message =>
          'the event idempotency store needs the PostgreSQL function layer' );
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
