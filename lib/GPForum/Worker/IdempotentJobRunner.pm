# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Worker::IdempotentJobRunner;

use Mojo::Base 'GPForum::Base', -signatures;
use v5.40;

our $VERSION = '0.001';

__PACKAGE__->requires(qw(store));

# The old order was ask, work, record. Nothing held the key between the
# question and the record, so two workers given the same event both passed the
# is_done check, both ran the side effect, and the loser's primary-key
# conflict was swallowed and reported as success.
#
# begin() now claims the key before any work happens and answers whether this
# worker owns it. A worker that does not own it stops here rather than
# duplicating the side effect.
#
# A claim that is not this worker's and not done is held by another worker:
# one still running the handler, or one that died inside its lease. Either
# way the side effect has not happened, so the run is not skipped -- a skip
# read as success, and the outbox acknowledged the message: a worker killed
# mid-handler lost its notifications for good, since the message was done
# before the lease let anyone take the claim over. It fails instead, and the
# outbox tries the message again later: by then the holder has finished
# (the key is done, the run is skipped) or its lease has run out (the claim
# is taken over). The error is kept as it was raised, so a declared failure
# type reaches the outbox's classification.
#
# Only the handler's own failure releases the claim. The side effect has
# happened once the handler returns, so a failure to record that -- the
# database gone between the email leaving and the completion being written --
# is not the handler's failure: released, the claim let the next try send the
# email again. The run succeeds, the message is done, and the claim is left
# to its lease, under the error in unrecorded. A failure to release the claim
# does not replace the handler's own error, which is the one the outbox
# classifies.
sub run ( $self, $idempotency_key, $code, $event_id = undef ) {
    return { ok => 1, skipped => 1 }
      if $self->store->is_done($idempotency_key);

    my $token = $self->store->begin( $idempotency_key, $event_id );
    if ( !$token ) {
        return { ok => 1, skipped => 1 }
          if $self->store->is_done($idempotency_key);

        return {
            error => "handler claim $idempotency_key is held by another worker",
            held  => 1,
            ok    => 0,
            skipped => 0,
        };
    }

    my ( $value, $failure, $failed );
    try {
        $value = $code->();
    }
    catch ($error) {
        ( $failure, $failed ) = ( $error, 1 );
    };
    if ($failed) {
        try {
            $self->store->mark_failed( $idempotency_key, "$failure", $token );
        }
        catch ($release_error) {

            # The claim stays until its lease runs out; the handler's error
            # is still the run's.
        };
        return { ok => 0, skipped => 0, error => $failure };
    }

    my %outcome = ( ok => 1, skipped => 0, result => $value );
    try {
        $self->store->mark_done( $idempotency_key, $value, $token );
    }
    catch ($record_error) {
        $outcome{unrecorded} = "$record_error";
    };

    return \%outcome;
}

1;
