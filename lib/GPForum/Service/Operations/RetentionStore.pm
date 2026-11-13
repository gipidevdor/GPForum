# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Operations::RetentionStore;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -signatures;
use v5.40;
use POSIX qw(strftime);

use GPForum::Service::Clock;
use GPForum::Service::Operations::BatchPurge;

use GPForum::Infrastructure::SqlFunction;

our $VERSION = '0.001';
has functions => \&GPForum::Infrastructure::SqlFunction::for_service;

const my $DAY_SECONDS                => 86_400;
const my $OUTBOX_RETENTION_DAYS      => 7;
const my $DEAD_LETTER_RETENTION_DAYS => 30;
const my $REPLAY_MARGIN_DAYS         => 7;
const my $MAX_BATCHES                => 50;
const my $LTE                        => q{<} . q{=};
const my $NOT_EQ                     => q{!} . q{=};
const my @DONE_OUTBOX_STATUSES       => qw(cancelled done);

has batch_purge =>
  sub { return GPForum::Service::Operations::BatchPurge->new; };
has clock => sub { return GPForum::Service::Clock->new; };
__PACKAGE__->requires(qw(schema));

sub purge_sessions ( $self, $input ) {
    return $self->_purge(
        {
            input        => $input,
            order_column => 'expires_at',
            query        => {
                -or => [
                    $self->_expired_at_query,
                    { revoked_at => { $NOT_EQ => undef } }
                ],
            },
            resultset => 'Session',
        }
    );
}

sub purge_identity_tokens ( $self, $input ) {
    return $self->_purge(
        {
            input        => $input,
            order_column => 'expires_at',
            query        => {
                -or => [
                    $self->_expired_at_query,
                    { used_at => { $NOT_EQ => undef } }
                ],
            },
            resultset => 'IdentityToken',
        }
    );
}

sub purge_rate_limit_buckets ( $self, $input ) {
    return $self->_purge(
        {
            input        => $input,
            order_column => 'expires_at',
            query        => $self->_expired_at_query,
            resultset    => 'RateLimitBucket',
        }
    );
}

sub purge_outbox_messages ( $self, $input ) {
    return $self->_purge(
        {
            input        => $input,
            order_column => 'created_at',
            query        => $self->_outbox_query($input),
            resultset    => 'OutboxMessage',
        }
    );
}

# Aged dead letters, then the handler claims no replay can need any more:
# a completed claim outlives the dead-letter retention by a week, so a
# replay still skips every handler that already ran. The claims are kept
# by the function layer only; without it there are none to purge.
sub purge_dead_letters ( $self, $input ) {
    my $letters = $self->_purge(
        {
            input        => $input,
            order_column => 'last_failed_at',
            query        => $self->_dead_letter_query($input),
            resultset    => 'DeadLetter',
        }
    );
    return $letters if !$self->functions;

    my $claims =
      $self->_purge( { input => $input, resultset => 'EventIdempotencyKey' } );
    return { %{$letters}, event_keys_deleted => $claims->{deleted} };
}

# The rows a spec selects, deleted in bounded batches until one comes back
# short of the limit, at most $MAX_BATCHES of them a run. One batch a run
# fell behind any table that fills faster than that: the scheduled jobs run
# hourly, and rate-limit buckets come at one per reader, action and minute.
sub _purge ( $self, $spec ) {
    my $limit   = $self->batch_purge->limit( $spec->{input} );
    my $deleted = 0;
    my $result  = {};
    for ( 1 .. $MAX_BATCHES ) {
        $result = $self->_purge_batch($spec) // {};
        my $batch = $result->{deleted} // 0;
        $deleted += $batch;
        last if $batch < $limit || ( exists $result->{ok} && !$result->{ok} );
    }

    return { %{$result}, deleted => $deleted };
}

# One batch in BatchPurge's order, deleted.
sub _purge_batch ( $self, $spec ) {
    if ( $self->functions ) {
        my $cutoff = $self->clock->now_iso8601;
        if ( $spec->{resultset} eq 'OutboxMessage' ) {
            $cutoff =
              $self->_cutoff_iso( $spec->{input}, 'outbox_retention_days',
                $OUTBOX_RETENTION_DAYS );
        }
        if ( $spec->{resultset} eq 'DeadLetter' ) {
            $cutoff =
              $self->_cutoff_iso( $spec->{input}, 'dead_letter_retention_days',
                $DEAD_LETTER_RETENTION_DAYS );
        }
        if ( $spec->{resultset} eq 'EventIdempotencyKey' ) {
            $cutoff = $self->_days_ago(
                (
                    ( $spec->{input} // {} )->{dead_letter_retention_days}
                      || $DEAD_LETTER_RETENTION_DAYS
                ) + $REPLAY_MARGIN_DAYS
            );
        }
        return $self->functions->row(
            'ops_retention_purge',
            {
                source    => $spec->{resultset},
                cutoff    => $cutoff,
                row_limit => $self->batch_purge->limit( $spec->{input} )
            }
        );
    }
    my $search = $self->schema->resultset( $spec->{resultset} )->search_rs(
        $spec->{query},
        $self->batch_purge->search_attrs(
            $spec->{input}, $spec->{order_column}
        )
    );
    my @rows = $search->can('items') ? $search->items : $search->all;

    return $self->batch_purge->delete_rows( \@rows );
}

sub _expired_at_query ($self) {
    return { expires_at => { $LTE => $self->clock->now_iso8601 } };
}

sub _outbox_query ( $self, $input ) {
    return {
        created_at => {
            $LTE => $self->_cutoff_iso(
                $input, 'outbox_retention_days', $OUTBOX_RETENTION_DAYS
            )
        },
        status => { -in => [@DONE_OUTBOX_STATUSES] },
    };
}

sub _dead_letter_query ( $self, $input ) {
    return {
        last_failed_at => {
            $LTE => $self->_cutoff_iso(
                $input, 'dead_letter_retention_days',
                $DEAD_LETTER_RETENTION_DAYS
            )
        },
    };
}

sub _cutoff_iso ( $self, $input, $field, $default_days ) {
    return $self->_days_ago( ( $input && $input->{$field} ) || $default_days );
}

sub _days_ago ( $self, $days ) {
    return strftime '%Y-%m-%dT%H:%M:%SZ',
      gmtime( $self->clock->now_epoch - ( $days * $DAY_SECONDS ) );
}

1;

__END__

=head1 NAME

GPForum::Service::Operations::RetentionStore - Batched operational deletes.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $store = GPForum::Service::Operations::RetentionStore->new(
        schema => $schema,
    );
    my $result = $store->purge_sessions( { limit => 100 } );

=head1 DESCRIPTION

Deletes stale C<sessions>, C<identity_tokens>, C<rate_limit_buckets>,
completed C<outbox_messages>, and aged C<dead_letters> in bounded batches,
batch after batch until one comes back short of the limit (at most 50 a
run), so a table that fills faster than one batch a run does not grow
without end. Every search includes a row cap. It does not issue unbounded
C<DELETE>.

=head1 SUBROUTINES/METHODS

=head2 purge_sessions

Deletes expired or revoked sessions, oldest expiry first.

=head2 purge_identity_tokens

Deletes expired or consumed identity tokens.

=head2 purge_rate_limit_buckets

Deletes rate-limit windows whose C<expires_at> has passed.

=head2 purge_outbox_messages

Deletes C<done> or C<cancelled> outbox rows older than the retention cutoff.

=head2 purge_dead_letters

Deletes aged dead-letter rows, then, through the function layer, the
completed handler claims older than the dead-letter retention and a week.
Returns the dead-letter purge result with C<event_keys_deleted>.

=head1 DIAGNOSTICS

Persistence errors are raised by DBIx::Class.

=head1 CONFIGURATION AND ENVIRONMENT

Outbox rows default to a 7-day grace after completion. Dead letters default
to 30 days. Both can be overridden on the input hash.

=head1 DEPENDENCIES

Uses L<Const::Fast>, L<GPForum::Service::Clock>,
L<GPForum::Service::Operations::BatchPurge>, L<Mojo::Base>, and L<POSIX>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Pending, failed, and running outbox rows are never deleted. Partition DDL is
not this store's job.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
