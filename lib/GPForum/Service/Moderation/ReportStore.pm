# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Moderation::ReportStore;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -async_await;
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

our $VERSION = '0.001';

const my $DEFAULT_QUEUE_LIMIT => 50;
const my $ID_CONSTRAINT       => 'reports_pkey';
const my $OPEN_CONSTRAINT     => 'idx_reports_reporter_target_open_unique';
const my $STATUS_OPEN         => 'open';
const my $STATUS_RESOLVED     => 'resolved';

has clock      => sub { return GPForum::Service::Clock->new; };
has id_service => sub {
    require GPForum::Infrastructure::Id;
    return GPForum::Infrastructure::Id->new;
};
has recorder => \&GPForum::Infrastructure::EventRecorder::for_service;
__PACKAGE__->requires(qw(schema));
has functions => \&GPForum::Infrastructure::SqlFunction::for_service;
has events    => sub { return GPForum::Service::Moderation::Event->new; };

# Each operation is written once, as its promise method (ADR 0177).
GPForum::Infrastructure::SqlFunction->blocking_twins(
    qw(create_report assign_report release_report resolve_report list_queue));

# The member's open report on the same target is reused, whether it was
# there before or a concurrent report won the open key; a minted id already
# stored with no such report is minted once more. It runs in its own
# transaction, or in the one $functions belongs to (a command log's); the
# insert runs in a savepoint, so a lost race is undone alone.
async sub create_report_p ( $self, $input, $context = undef,
    $functions = undef )
{
    my $work = async sub ($scope) {
        return await $self->_create_report_on_p( $scope, $input, $context );
    };
    return await $work->($functions) if $functions;
    return await $self->_functions->transaction_p( $work, $context );
}

async sub _create_report_on_p ( $self, $scope, $input, $context ) {
    my $duplicate =
      await $self->_open_duplicate_report_p( $scope, $input, $context );
    return await $self->_finish_leftover_report_p( $scope, $duplicate, $input,
        $context )
      if $duplicate;

    for my $attempt ( 0, 1 ) {
        my ( $created, $error ) =
          await GPForum::Infrastructure::UniqueConflict->attempt_p(
            $scope,
            async sub ($savepoint) {
                return await $self->_insert_report_p( $savepoint, $input,
                    $context );
            }
          );
        return $created if $created;

        my $conflict = GPForum::X::Conflict->caught($error);
        my $id_taken = $conflict && $conflict->on($ID_CONSTRAINT);
        if ( !$attempt
            && ( $id_taken || $conflict && $conflict->on($OPEN_CONSTRAINT) ) )
        {
            $duplicate =
              await $self->_open_duplicate_report_p( $scope, $input, $context );
            return await $self->_finish_leftover_report_p( $scope, $duplicate,
                $input, $context )
              if $duplicate;
        }
        if ( $attempt || !$id_taken ) {
            GPForum::Infrastructure::UniqueConflict->rethrow($error);
        }
    }
    return undef;
}

async sub _open_duplicate_report_p ( $self, $scope, $input, $context ) {
    return await _report_p(
        $scope,
        {
            map { $_ => $input->{$_} }
              qw(reporter_user_id target_type target_id)
        },
        $context
    );
}

async sub _insert_report_p ( $self, $scope, $input, $context ) {
    my $report = $self->_new_report($input);
    await $scope->row_p( 'moderation_report_insert', { values => $report },
        $context );
    await $self->_record_event_and_audit_p( $scope, $report, $context );
    return $report;
}

sub _new_report ( $self, $input ) {
    return {
        report_id                  => $self->id_service->uuid,
        reporter_user_id           => $input->{reporter_user_id},
        target_type                => $input->{target_type},
        target_id                  => $input->{target_id},
        reason                     => $input->{reason},
        details                    => $input->{details} || q{},
        status                     => $STATUS_OPEN,
        assigned_moderator_user_id => undef,
        created_at                 => $self->clock->now_iso8601,
        resolved_at                => undef,
        resolution                 => undef,
    };
}

# A report whose event an earlier attempt left out gets it now; a report
# already recorded is a duplicate, and the repeat is audited as one.
async sub _finish_leftover_report_p ( $self, $scope, $existing, $input,
    $context )
{
    my $event_key = join q{:}, 'report.created',
      column_of( $existing, 'report_id' );
    my $recorded =
      await $scope->row_p( 'ops_event_recorded', { key => $event_key },
        $context );
    if ( !$recorded->{recorded} ) {
        await $self->_record_event_and_audit_p( $scope, $existing, $context );
        return $existing;
    }
    await $scope->row_p(
        'ops_record_audit',
        $self->recorder->audit_call(
            %{ $self->_duplicate_audit( $existing, $input ) }
        ),
        $context
    );
    return $existing;
}

async sub _record_event_and_audit_p ( $self, $scope, $report, $context ) {
    my $recorded = {
        correlation_id => $self->id_service->uuid,
        report         => $report,
    };
    await $scope->row_p(
        'ops_record_event',
        $self->recorder->event_call(
            %{ $self->events->report_created_envelope($recorded) }
        ),
        $context
    );
    await $scope->row_p(
        'ops_record_audit',
        $self->recorder->audit_call(
            %{ $self->events->report_created_audit($recorded) }
        ),
        $context
    );
    return;
}

sub _duplicate_audit ( $self, $existing, $input ) {
    return $self->events->report_duplicate_audit(
        {
            created_at       => $self->clock->now_iso8601,
            duplicate        => $existing,
            reason           => $input->{reason},
            reporter_user_id => $input->{reporter_user_id},
            target_id        => $input->{target_id},
            target_type      => $input->{target_type},
        }
    );
}

async sub assign_report_p ( $self, $report_id, $moderator_user_id,
    $context = undef )
{
    return await $self->_transition_p(
        {
            report_id => $report_id,
            settled   => sub ($report) {
                return ( column_of( $report, 'assigned_moderator_user_id' )
                      || q{} ) eq $moderator_user_id;
            },
            changes    => { assigned_moderator_user_id => $moderator_user_id },
            event_type => 'report.assigned',
            actor_id   => $moderator_user_id,
            payload    => { assigned_moderator_user_id => $moderator_user_id },
        },
        $context
    );
}

async sub release_report_p ( $self, $report_id, $actor_user_id,
    $context = undef )
{
    return await $self->_transition_p(
        {
            report_id => $report_id,
            settled   => sub ($report) {
                return !
                  defined column_of( $report, 'assigned_moderator_user_id' );
            },
            changes    => { assigned_moderator_user_id => undef },
            event_type => 'report.released',
            actor_id   => $actor_user_id,
            payload    => { assigned_moderator_user_id => undef },
        },
        $context
    );
}

async sub resolve_report_p (
    $self, $report_id, $resolution,
    $actor_user_id = undef,
    $context = undef
  )
{
    my $resolved_at = $self->clock->now_iso8601;
    return await $self->_transition_p(
        {
            report_id => $report_id,
            settled   => sub ($report) {
                return ( column_of( $report, 'status' ) || q{} ) eq
                  $STATUS_RESOLVED;
            },
            changes => {
                status      => $STATUS_RESOLVED,
                resolved_at => $resolved_at,
                resolution  => $resolution,
            },
            event_type => 'report.resolved',
            actor_id   => $actor_user_id,
            payload    => {
                resolution  => $resolution,
                resolved_at => $resolved_at,
            },
        },
        $context
    );
}

# Under the report's lock: a report already where the transition takes it
# is answered as it stands; any other gets the changes, an event and an
# audit entry.
async sub _transition_p ( $self, $spec, $context ) {
    return await $self->_functions->transaction_p(
        async sub ($scope) {
            my $report = await _report_p( $scope,
                { report_id => $spec->{report_id}, hold => 1 } );
            return undef if !$report;

            return _report_transition_hash($report)
              if $spec->{settled}->($report);

            await $scope->row_p(
                'moderation_report_update',
                {
                    report_id => $spec->{report_id},
                    changes   => $spec->{changes}
                }
            );
            %{$report} = ( %{$report}, %{ $spec->{changes} } );
            my ( $event, $audit ) = $self->_transition_records(
                {
                    report     => $report,
                    event_type => $spec->{event_type},
                    actor_id   => $spec->{actor_id},
                    payload    => $spec->{payload},
                }
            );
            await $scope->row_p( 'ops_record_event',
                $self->recorder->event_call( %{$event} ) );
            await $scope->row_p( 'ops_record_audit',
                $self->recorder->audit_call( %{$audit} ) );

            return { report_id => $spec->{report_id}, %{ $spec->{changes} } };
        },
        $context
    );
}

# The queue of reports in a status, oldest first.
async sub list_queue_p ( $self, $options, $context = undef ) {
    my $rows = await $self->_functions->rows_p(
        'moderation_report_queue',
        {
            status    => $options->{status} || $STATUS_OPEN,
            row_limit => $options->{limit}  || $DEFAULT_QUEUE_LIMIT
        },
        $context
    );
    return [ map { GPForum::Infrastructure::ResultRow->from($_) } @{$rows} ];
}

# The resultset the query-plan evidence EXPLAINs for the queue: the
# statement moderation_report_queue runs, ordered by created_at and then
# report_id.
sub queue_resultset ( $self, $options ) {
    return $self->schema->resultset('Report')->search_rs(
        {
            status => $options->{status} || $STATUS_OPEN,
        },
        {
            order_by => [ { -asc => 'created_at' }, { -asc => 'report_id' } ],
            rows     => $options->{limit} || $DEFAULT_QUEUE_LIMIT,
        }
    );
}

# One report, by id or by its reporter's open key; held (FOR UPDATE) when
# asked.
async sub _report_p ( $scope, $input, $context = undef ) {
    return GPForum::Infrastructure::ResultRow->from(
        await $scope->row_p(
            'moderation_report_find',
            {
                report_id        => undef,
                reporter_user_id => undef,
                target_type      => undef,
                target_id        => undef,
                hold             => 0,
                %{$input}
            },
            $context
        )
    );
}

sub _report_transition_hash ($report) {
    return {
        map { $_ => column_of( $report, $_ ) }
          qw(assigned_moderator_user_id report_id resolution resolved_at
          status)
    };
}

# The event and the audit entry of a transition.
sub _transition_records ( $self, $input ) {
    my $recorded = {
        %{$input},
        correlation_id => $self->id_service->uuid,
        created_at     => $self->clock->now_iso8601,
        event_id       => $self->id_service->uuid,
    };
    return (
        $self->events->report_transition_envelope($recorded),
        $self->events->report_transition_audit(
            {
                action         => $input->{event_type},
                actor_id       => $input->{actor_id},
                correlation_id => $recorded->{correlation_id},
                created_at     => $recorded->{created_at},
                metadata       => $input->{payload},
                report         => $input->{report},
            }
        ),
    );
}

sub _functions ($self) {
    return $self->functions // GPForum::X::Unavailable->throw(
        message => 'reports need the PostgreSQL function layer' );
}

1;

__END__

=head1 NAME

GPForum::Service::Moderation::ReportStore - Member reports and their way through the moderation queue.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $store = GPForum::Service::Moderation::ReportStore->new(
        schema => $schema,
    );
    my $report = $store->create_report(
        {
            reporter_user_id => $user_id,
            target_type      => 'post',
            target_id        => $post_id,
            reason           => 'spam',
            details          => 'link farm',
        }
    );
    my $queue = $store->list_queue( { status => 'open', limit => 50 } );
    $store->assign_report( $report_id, $moderator_id );
    $store->resolve_report( $report_id, 'removed', $moderator_id );

=head1 DESCRIPTION

Writes the C<reports> table and records, in the same transaction, a domain
event and an audit entry for each change, built by
L<GPForum::Service::Moderation::Event> and written by
L<GPForum::Infrastructure::EventRecorder>.

A member has at most one open or triaged report per target. Reporting the
same target again returns that report instead of a new one and audits the
attempt as C<report.duplicate_blocked>. If the existing report has no
C<report.created> event yet -- a report left over from a write that did
not finish -- its event and audit are recorded instead. A new report is
inserted inside a savepoint; when the insert loses a race on the open-report
index (C<idx_reports_reporter_target_open_unique>), the other writer's
report is reused the same way, and when it collides on the report id
(C<reports_pkey>), the report is looked up again and, when there is still
none, the insert is retried once with a fresh id.

Assigning, releasing and resolving read the report held (C<FOR UPDATE>)
first. A transition that would change nothing writes nothing and records no
event.

Each operation is written once, as its promise method, through the
C<api.moderation_report_*> functions; its blocking twin, named without
C<_p>, runs the same body on the blocking call layer (ADR 0177).

=head1 SUBROUTINES/METHODS

=head2 create_report

Takes a hash reference with C<reporter_user_id>, C<target_type>,
C<target_id>, C<reason> and an optional C<details> (empty when omitted).
Returns a hash reference of the new C<open> report's columns, or, when the
member already has an open or triaged report on that target, that report's
row.

=head2 create_report_p

L</create_report> as a promise: takes the input, an optional query context
and an optional call layer. It runs in its own transaction or in the one the
call layer belongs to.

=head2 assign_report

Takes a report id and a moderator's user id. Assigns the report to that
moderator and records C<report.assigned>, with the moderator as actor.
Returns C<< { report_id, assigned_moderator_user_id } >>; when it is
already assigned to that moderator, a hash reference of the report's
C<report_id>, C<status>, C<assigned_moderator_user_id>, C<resolution> and
C<resolved_at> instead. Returns an empty list (undef in scalar context)
when there is no such report.

=head2 assign_report_p

L</assign_report> as a promise, with an optional query context last, in one
transaction.

=head2 release_report

Takes a report id and the acting user's id. Clears the assignment and
records C<report.released>. Returns
C<< { report_id, assigned_moderator_user_id => undef } >>; when the report
is not assigned, the report's state hash as for C<assign_report>. Returns
an empty list (undef in scalar context) when there is no such report.

=head2 release_report_p

L</release_report> as a promise, with an optional query context last, in one
transaction.

=head2 resolve_report

Takes a report id, a resolution and, optionally, the acting user's id.
Sets the status to C<resolved> with C<resolved_at> and the resolution, and
records C<report.resolved>. Returns
C<< { report_id, status, resolved_at, resolution } >>; when the report is
already resolved, the report's state hash as for C<assign_report>. Returns
an empty list (undef in scalar context) when there is no such report.

=head2 resolve_report_p

L</resolve_report> as a promise, with an optional query context last, in one
transaction.

=head2 list_queue

Takes a hash reference with optional C<status> (default C<open>) and
C<limit> (default 50). Returns an array reference of the reports in that
status, oldest first.

=head2 list_queue_p

L</list_queue> as a promise, with an optional query context last.

=head2 queue_resultset

Takes the options L</list_queue> takes. Returns the unexecuted C<Report>
resultset of the statement the queue's function runs, for the query-plan
evidence to EXPLAIN.

=head1 DIAGNOSTICS

C<create_report> raises the database error when the insert fails for
any reason other than a unique conflict, when an open-report conflict
leaves no report to reuse, and when the retry after an id collision fails
too. Every write runs in one transaction, so a failure, including a failure to
record the event or the audit entry, rolls the whole change back and
propagates. Without the PostgreSQL function layer every operation raises
L<GPForum::X::Unavailable>.

=head1 CONFIGURATION AND ENVIRONMENT

None. C<clock>, C<id_service>, C<recorder> and C<events> have defaults;
tests pass their own.

=head1 DEPENDENCIES

L<GPForum::Infrastructure::EventRecorder>, L<GPForum::Infrastructure::Id>,
L<GPForum::Infrastructure::Row>, L<GPForum::Infrastructure::SqlFunction>,
L<GPForum::Infrastructure::UniqueConflict>, L<GPForum::X::Conflict>,
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
