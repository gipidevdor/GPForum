# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Community::ReputationLedger;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -signatures, -async_await;
use v5.40;

use GPForum::Infrastructure::Text qw(has_text);
use GPForum::Service::Clock;
use GPForum::Infrastructure::Id;
use GPForum::X::Conflict;
use GPForum::X::Unavailable;

use GPForum::Infrastructure::SqlFunction;

our $VERSION = '0.001';

const my $TRUST_LEVEL_ONE_SCORE   => 10;
const my $TRUST_LEVEL_TWO_SCORE   => 50;
const my $TRUST_LEVEL_THREE_SCORE => 150;
const my $TRUST_LEVEL_FOUR_SCORE  => 500;
const my $TRUST_LEVEL_ZERO        => 0;
const my $TRUST_LEVEL_ONE         => 1;
const my $TRUST_LEVEL_TWO         => 2;
const my $TRUST_LEVEL_THREE       => 3;
const my $TRUST_LEVEL_FOUR        => 4;

has clock      => sub { return GPForum::Service::Clock->new; };
has id_service => sub { return GPForum::Infrastructure::Id->new; };
__PACKAGE__->requires(qw(schema));
has functions => \&GPForum::Infrastructure::SqlFunction::for_service;

# Each operation is written once, as its promise method (ADR 0177).
GPForum::Infrastructure::SqlFunction->blocking_twins('record_event');

# reputation_events, trust_score_snapshots and the denormalized user trust
# level are written together, by api.community_record_reputation, in one
# transaction. Without one a failed snapshot write left the ledger crediting
# a delta the score never received.
#
# An event without a source is skipped. The event already stored for its
# source -- before, or by a concurrent request -- is replayed; a minted id
# already stored with no such event is minted once more, in the same
# transaction.
async sub record_event_p ( $self, $input, $context = undef ) {
    return await $self->_functions->transaction_p(
        async
          sub ($scope) { return await $self->_recorded_p( $scope, $input ); },
        $context
    );
}

async sub _recorded_p ( $self, $scope, $input ) {
    my $row = {
        %{$input},
        created_at          => $self->clock->now_iso8601,
        reputation_event_id => _has_source($input)
        ? $self->id_service->uuid
        : undef,
        actor_id      => $input->{actor_id},
        current_score => $input->{current_score},
    };
    my $result =
      ( await $scope->row_p( 'community_record_reputation', { row => $row } ) )
      ->{result};
    return $result if !$result->{retry_id};

    $row->{reputation_event_id} = $self->id_service->uuid;
    $result =
      ( await $scope->row_p( 'community_record_reputation', { row => $row } ) )
      ->{result};
    if ( $result->{retry_id} ) {
        GPForum::X::Conflict->throw(
            message => 'the replacement reputation id is already stored' );
    }

    return $result;
}

sub _functions ($self) {
    return $self->functions // GPForum::X::Unavailable->throw( message =>
          'the reputation ledger needs the PostgreSQL function layer' );
}

sub _has_source ($input) {
    if ( !has_text( $input->{source_type} ) ) {
        return 0;
    }
    if ( !has_text( $input->{source_id} ) ) {
        return 0;
    }

    return 1;
}

sub trust_level_for_score ($score) {
    return $TRUST_LEVEL_FOUR  if $score >= $TRUST_LEVEL_FOUR_SCORE;
    return $TRUST_LEVEL_THREE if $score >= $TRUST_LEVEL_THREE_SCORE;
    return $TRUST_LEVEL_TWO   if $score >= $TRUST_LEVEL_TWO_SCORE;
    return $TRUST_LEVEL_ONE   if $score >= $TRUST_LEVEL_ONE_SCORE;

    return $TRUST_LEVEL_ZERO;
}

1;

__END__

=head1 NAME

GPForum::Service::Community::ReputationLedger - Reputation deltas, the running trust score and the trust level it gives.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $ledger =
      GPForum::Service::Community::ReputationLedger->new( schema => $schema );

    my $result = $ledger->record_event(
        {
            actor_id    => $actor_id,
            delta       => 1,
            reason      => 'post_created',
            source_id   => $post_id,
            source_type => 'post',
            user_id     => $author_id,
        }
    );
    # { ok => 1, event => {...}, snapshot => { score, trust_level, ... } }

    my $level =
      GPForum::Service::Community::ReputationLedger::trust_level_for_score(60);
    # 2

=head1 DESCRIPTION

Each reputation change is a C<reputation_events> row identified by its
source (C<source_type>, C<source_id> and C<user_id>), so a replayed domain
event credits nothing twice. The member's C<trust_score_snapshots> row
holds the running score; it is read with C<FOR UPDATE> and incremented, so
a concurrent delta is not lost, and the trust level it gives is copied to
the user row. The event, the snapshot and the user's trust level are
written in one transaction, by one call to
C<api.community_record_reputation>: written apart, a failed snapshot write
left the ledger crediting a delta the score never received.

The trust levels are 0 below 10 points, 1 from 10, 2 from 50, 3 from 150
and 4 from 500. A member's first snapshot starts from C<current_score> when
the input gives one, 0 otherwise. An event already recorded whose member has
no snapshot, left by an interrupted write, has its snapshot written now.

=head1 SUBROUTINES/METHODS

=head2 record_event_p

Takes a hash reference with C<user_id>, C<delta>, C<source_type>,
C<source_id>, C<actor_id>, C<reason> and an optional C<current_score>, and
an optional query context. In a transaction, resolves with C<< { ok => 1, event, snapshot } >> for a new event;
C<< { ok => 1, skipped => 1, event, snapshot } >> when the source was
already recorded, with the current snapshot or the one just written for a
leftover event; and C<< { ok => 1, skipped => 1, reason => 'missing_source',
snapshot } >>, recording nothing, when C<source_type> or C<source_id> is
empty. The snapshot is C<< { user_id, score, trust_level, calculated_at,
version } >>; for a member without one it has score and level 0 and no
C<calculated_at>.

=head2 record_event

The blocking twin of L</record_event_p> (ADR 0177): the same body, settled
on the blocking layer, as the reputation worker calls it.

=head2 trust_level_for_score

A function, not a method. Takes a score and returns the trust level it
gives, from 0 to 4.

=head1 DIAGNOSTICS

A minted event id that is already stored twice in a row throws
L<GPForum::X::Conflict>; database errors propagate. Either rolls the
transaction back. Without the function layer the ledger throws
L<GPForum::X::Unavailable>.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Infrastructure::SqlFunction>, L<GPForum::X::Conflict>,
L<GPForum::X::Unavailable>, L<GPForum::Infrastructure::Id>,
L<GPForum::Service::Clock>.

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
