# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Search::RebuildRun;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -signatures, -async_await;
use v5.40;

use GPForum::Infrastructure::EventRecorder;
use GPForum::Infrastructure::Id;
use GPForum::Infrastructure::SqlFunction;
use GPForum::X::Unavailable;

our $VERSION = '0.001';

const my $AGGREGATE => 'search_rebuild';
const my $REQUESTED => 'search.rebuild_requested';
const my $COMPLETED => 'search.rebuild_completed';
const my @COUNTS    => qw(indexed pruned unchanged);

has id_service => sub { return GPForum::Infrastructure::Id->new; };
__PACKAGE__->requires(qw(indexer schema));
has functions => \&GPForum::Infrastructure::SqlFunction::for_service;

has recorder => \&GPForum::Infrastructure::EventRecorder::for_service;

# Written once, as its promise method (ADR 0177); the indexer it awaits
# blocks with it.
GPForum::Infrastructure::SqlFunction->blocking_twins(qw(request step latest));
GPForum::Infrastructure::SqlFunction->blocking_parts('indexer');

# A search rebuild the console asks for runs through the outbox, one batch
# per message: whatever runs the dispatcher runs it, a failed step is
# retried and dead-lettered like any other, and a large forum never holds
# the dispatcher for long. This records the first step's event, and its
# outbox message, inside the caller's transaction ($scope, the call layer
# transaction_p hands its work) or in one of its own.
async sub request_p ( $self, $input, $context = undef, $scope = undef ) {
    my $run_id = $self->id_service->uuid;
    await $self->_record_once_p( $REQUESTED, _first_step( $input, $run_id ),
        _cause($input), $context, $scope );

    return { run_id => $run_id };
}

sub _first_step ( $input, $run_id ) {
    return {
        entity_type => $input->{entity_type} || 'all',
        run_id      => $run_id,
        step        => 0,
        totals      => { map { $_ => 0 } @COUNTS },
    };
}

sub _cause ($input) {
    return {
        actor_id       => $input->{actor_id},
        correlation_id => $input->{correlation_id},
    };
}

# One step of the run, for the outbox event that carries it: one batch of
# the rebuild, then the next step's event -- once, however often the
# message is retried -- or the run's completion with its totals.
async sub step_p ( $self, $event, $context = undef ) {
    my $payload =
      ref $event->{domain_payload} eq 'HASH'
      ? $event->{domain_payload}
      : {};
    my $batch = await $self->indexer->rebuild_batch_p(
        {
            after       => $payload->{after},
            entity_type => $payload->{entity_type},
            stage       => $payload->{stage},
        },
        $context
    );
    my %totals =
      map { $_ => ( $payload->{totals}{$_} // 0 ) + ( $batch->{$_} // 0 ) }
      @COUNTS;
    my %carried = (
        entity_type => $payload->{entity_type} || 'all',
        run_id      => $payload->{run_id},
        step        => ( $payload->{step} // 0 ) + 1,
        totals      => \%totals,
    );

    my $next = $batch->{next};
    if ($next) {
        await $self->_record_once_p( $REQUESTED,
            { %carried, after => $next->{after}, stage => $next->{stage} },
            $event, $context );
    }
    else {
        await $self->_record_once_p( $COMPLETED, \%carried, $event, $context );
    }

    return { %{$batch}, totals => \%totals };
}

# The latest run: the event it last recorded -- a step still to run, or its
# completion -- with its totals so far.
async sub latest_p ( $self, $context = undef ) {
    my $row =
      await $self->_functions->row_p( 'search_latest_rebuild', {}, $context );
    return undef if !$row;

    my $payload = $self->recorder->json->decode( $row->{payload} // '{}' );

    return {
        at          => $row->{created_at},
        completed   => $row->{event_type} eq $COMPLETED ? 1 : 0,
        entity_type => $payload->{entity_type},
        run_id      => $payload->{run_id},
        stage       => $payload->{stage},
        totals      => $payload->{totals} || {},
    };
}

sub handles ( $, $event_type ) {
    return ( $event_type // q{} ) eq $REQUESTED ? 1 : 0;
}

# The check, the event and its outbox message are one transaction, as
# SearchIndexing's batch chain records its own. They were three statements
# under autocommit: an outbox write that failed left the event behind, its
# key then said the step was recorded, and every retry returned at once --
# the run stopped there, with no message left to carry it on. Inside the
# caller's transaction ($scope) this is part of it.
async sub _record_once_p ( $self, $type, $payload, $cause, $context,
    $scope = undef )
{
    my ( $key, $event ) = $self->_once_call( $type, $payload, $cause );
    my $work = async sub ($functions) {
        my $recorded =
          await $functions->row_p( 'ops_event_recorded', { key => $key },
            $context );
        return 0 if $recorded->{recorded};

        return await $functions->row_p( 'ops_record_event',
            $self->recorder->event_call( %{$event} ), $context );
    };

    return await(
          $scope
        ? $work->($scope)
        : $self->_functions->transaction_p( $work, $context )
    );
}

sub _functions ($self) {
    return $self->functions // GPForum::X::Unavailable->throw(
        message => 'a search rebuild needs the PostgreSQL database' );
}

# A step's idempotency key and the event recorded under it.
sub _once_call ( $self, $type, $payload, $cause ) {
    my $key = join q{:}, $type, $payload->{run_id},
      $payload->{stage} // 'start',
      $payload->{after} // 'start';
    return (
        $key,
        {
            actor_id       => $cause->{actor_id},
            aggregate_id   => $payload->{run_id},
            aggregate_type => $AGGREGATE,
            causation_id   => $cause->{event_id},
            correlation_id => $cause->{correlation_id}
              || $self->id_service->uuid,
            event_type      => $type,
            idempotency_key => $key,
            payload         => $payload,
        }
    );
}

1;

__END__

=head1 NAME

GPForum::Service::Search::RebuildRun - A search rebuild run through the outbox, one batch per message.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $run = GPForum::Service::Search::RebuildRun->new(
        indexer => $indexer,
        schema  => $schema,
    );
    $run->request( { actor_id => $admin_id } );   # from the console
    $run->step($event);                            # from the outbox handler
    my $latest = $run->latest;

=head1 DESCRIPTION

Splits L<GPForum::Service::Search::Indexer>'s rebuild into steps
(C<rebuild_batch>), each carried by a C<search.rebuild_requested> event and
its outbox message, and closed by C<search.rebuild_completed> with the run's
totals. Each next step is recorded once, keyed by the run, stage and cursor,
so a retried message never forks the run. The check and the event with its
outbox message are written in one transaction (the caller's, when there is
one), so a step that fails part way records nothing and its retry records
it whole.

=head1 SUBROUTINES/METHODS

=head2 request_p

Takes the request (C<entity_type>, C<actor_id> and C<correlation_id>),
an optional query context and an optional transaction call layer.
Starts a run, inside that transaction or in one of its own; answers
C<< { run_id } >>.

=head2 step_p

Takes an outbox event and an optional query context. Runs one step and
records the next, or the completion; answers the batch's counts with the
run's C<totals>.

=head2 latest_p

Takes an optional query context. Answers the latest run's state, or
nothing.

=head2 request, step, latest

The blocking twins of the promise methods above, settled on the blocking
layer (ADR 0177).

=head2 handles

True for the event type a step is carried by.

=head1 DIAGNOSTICS

Dies when the database does; the outbox retries the step. Without the
function layer it throws L<GPForum::X::Unavailable>.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Service::Search::Indexer>,
L<GPForum::Infrastructure::EventRecorder>,
L<GPForum::Infrastructure::SqlFunction>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

A second run requested while one is going runs alongside it; both are
idempotent, so the forum is only indexed twice.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
