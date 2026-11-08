# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Moderation::ReportStore;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -async_await;
use v5.40;

use GPForum::Infrastructure::Row qw(column_of rows_in);
use GPForum::Infrastructure::Storage;
use GPForum::Infrastructure::EventRecorder;
use GPForum::Infrastructure::UniqueConflict;
use GPForum::Service::Clock;
use GPForum::Service::Moderation::Event;
use GPForum::X::Conflict;

use GPForum::Infrastructure::SqlFunction;
use GPForum::Infrastructure::ResultRow;

our $VERSION = '0.001';

const my $DEFAULT_QUEUE_LIMIT => 50;
const my $ID_CONSTRAINT       => 'reports_pkey';
const my $OPEN_CONSTRAINT     => 'idx_reports_reporter_target_open_unique';
const my $STATUS_OPEN         => 'open';
const my $STATUS_RESOLVED     => 'resolved';
const my $STATUS_TRIAGED      => 'triaged';
const my $REPORT_LOCK_SQL =>
  'SELECT report_id FROM reports WHERE report_id = ? FOR UPDATE';

has clock      => sub { return GPForum::Service::Clock->new; };
has id_service => sub {
    require GPForum::Infrastructure::Id;
    return GPForum::Infrastructure::Id->new;
};
has recorder => \&GPForum::Infrastructure::EventRecorder::for_service;
__PACKAGE__->requires(qw(schema));
has functions => \&GPForum::Infrastructure::SqlFunction::for_service;
has events    => sub { return GPForum::Service::Moderation::Event->new; };

# The member's open report on the same target is reused, whether it was
# there before or a concurrent report won the open key; a minted id already
# stored with no such report is minted once more.
sub create_report ( $self, $input ) {
    return $self->schema->txn_do(
        sub {
            return GPForum::Infrastructure::UniqueConflict->create_or_reuse(
                $self->schema,
                find  => sub { return $self->_open_duplicate_report($input); },
                reuse => sub ($row) {
                    return $self->_finish_leftover_report( $row, $input );
                },
                create         => sub { return $self->_insert_report($input); },
                id_constraint  => $ID_CONSTRAINT,
                key_constraint => $OPEN_CONSTRAINT,
            );
        }
    );
}

sub _open_duplicate_report ( $self, $input ) {
    if ( $self->functions ) {
        return $self->_report_row(
            {
                map { $_ => $input->{$_} }
                  qw(reporter_user_id target_type target_id)
            }
        );
    }
    return $self->schema->resultset('Report')->search_rs(
        {
            reporter_user_id => $input->{reporter_user_id},
            target_type      => $input->{target_type},
            target_id        => $input->{target_id},
            status           => { -in => [ $STATUS_OPEN, $STATUS_TRIAGED ] },
        },
        {
            order_by => { -desc => 'created_at' },
            rows     => 1,
        }
    )->single;
}

# create_report on the worker's pooled asynchronous connections: in its own
# transaction, or in the one $functions belongs to (a command log's). The
# insert runs in a savepoint, so a lost race on the open key or a minted id
# already taken is answered as create_report answers it.
async sub create_report_p ( $self, $input, $context = undef,
    $functions = undef )
{
    return $self->create_report($input) if !$self->functions;
    my $work = async sub ($scope) {
        return await $self->_create_report_on_p( $scope, $input, $context );
    };
    return await $work->($functions) if $functions;
    return await $self->functions->transaction_p( $work, $context );
}

async sub _create_report_on_p ( $self, $scope, $input, $context ) {
    my $duplicate =
      await $self->_open_duplicate_report_p( $scope, $input, $context );
    return await $self->_finish_leftover_report_p( $scope, $duplicate, $input,
        $context )
      if $duplicate;

    for my $attempt ( 0, 1 ) {
        my ( $created, $failure );
        try {
            $created = await $scope->transaction_p(
                async sub ($savepoint) {
                    return await $self->_insert_report_p( $savepoint, $input,
                        $context );
                }
            );
        }
        catch ($error) { $failure = $error; };
        return $created if $created;

        my $conflict = GPForum::X::Conflict->caught($failure);
        my $id_taken = $conflict && $conflict->on($ID_CONSTRAINT);
        if (
            $attempt == 0
            && ( $id_taken || ( $conflict && $conflict->on($OPEN_CONSTRAINT) ) )
          )
        {
            $duplicate =
              await $self->_open_duplicate_report_p( $scope, $input, $context );
            return await $self->_finish_leftover_report_p( $scope, $duplicate,
                $input, $context )
              if $duplicate;
        }
        die $failure    ## no critic (ErrorHandling::RequireCarping) -- rethrow the database's own conflict unchanged
          if $attempt || !$id_taken;
    }
    return undef;
}

async sub _open_duplicate_report_p ( $self, $scope, $input, $context ) {
    return GPForum::Infrastructure::ResultRow->from(
        await $scope->row_p(
            'moderation_report_find',
            _find_values(
                {
                    map { $_ => $input->{$_} }
                      qw(reporter_user_id target_type target_id)
                }
            ),
            $context
        )
    );
}

async sub _insert_report_p ( $self, $scope, $input, $context ) {
    my $report = $self->_new_report($input);
    await $scope->row_p( 'moderation_report_insert', { values => $report },
        $context );
    await $self->_record_event_and_audit_p( $scope, $report, $context );
    return $report;
}

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

sub _insert_report ( $self, $input ) {
    my $report = $self->_new_report($input);
    if ( $self->functions ) {
        $self->functions->row( 'moderation_report_insert',
            { values => $report } );
    }
    else {
        $self->schema->resultset('Report')->create($report);
    }
    $self->_record_event_and_audit($report);

    return $report;
}

sub _new_report ( $self, $input ) {
    my $created_at = $self->clock->now_iso8601;
    return {
        report_id                  => $self->id_service->uuid,
        reporter_user_id           => $input->{reporter_user_id},
        target_type                => $input->{target_type},
        target_id                  => $input->{target_id},
        reason                     => $input->{reason},
        details                    => $input->{details} || q{},
        status                     => $STATUS_OPEN,
        assigned_moderator_user_id => undef,
        created_at                 => $created_at,
        resolved_at                => undef,
        resolution                 => undef,
    };
}

# A report whose event an earlier attempt left out gets it now; a report
# already recorded is a duplicate, and the repeat is audited as one.
sub _finish_leftover_report ( $self, $existing, $input ) {
    my $event_key = join q{:}, 'report.created',
      column_of( $existing, 'report_id' );
    if ( !$self->recorder->event_recorded($event_key) ) {
        $self->_record_event_and_audit($existing);
        return $existing;
    }

    $self->recorder->record_audit(
        %{ $self->_duplicate_audit( $existing, $input ) } );

    return $existing;
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

sub assign_report ( $self, $report_id, $moderator_user_id ) {
    return $self->_transition( _assign_spec( $report_id, $moderator_user_id ) );
}

# The same transition in one transaction on the worker's pooled
# asynchronous connections, not a forked child with a connection of its
# own; as are release_report_p and resolve_report_p.
async sub assign_report_p ( $self, $report_id, $moderator_user_id,
    $context = undef )
{
    return await $self->_transition_p(
        _assign_spec( $report_id, $moderator_user_id ), $context );
}

sub release_report ( $self, $report_id, $actor_user_id ) {
    return $self->_transition( _release_spec( $report_id, $actor_user_id ) );
}

async sub release_report_p ( $self, $report_id, $actor_user_id,
    $context = undef )
{
    return await $self->_transition_p(
        _release_spec( $report_id, $actor_user_id ), $context );
}

sub resolve_report ( $self, $report_id, $resolution, $actor_user_id = undef ) {
    return $self->_transition(
        $self->_resolve_spec( $report_id, $resolution, $actor_user_id ) );
}

async sub resolve_report_p (
    $self, $report_id, $resolution,
    $actor_user_id = undef,
    $context = undef
  )
{
    return await $self->_transition_p(
        $self->_resolve_spec( $report_id, $resolution, $actor_user_id ),
        $context );
}

sub _assign_spec ( $report_id, $moderator_user_id ) {
    return {
        report_id => $report_id,
        settled   => sub ($report) {
            return ( column_of( $report, 'assigned_moderator_user_id' ) || q{} )
              eq $moderator_user_id;
        },
        changes    => { assigned_moderator_user_id => $moderator_user_id },
        event_type => 'report.assigned',
        actor_id   => $moderator_user_id,
        payload    => { assigned_moderator_user_id => $moderator_user_id },
    };
}

sub _release_spec ( $report_id, $actor_user_id ) {
    return {
        report_id => $report_id,
        settled   => sub ($report) {
            return !defined column_of( $report, 'assigned_moderator_user_id' );
        },
        changes    => { assigned_moderator_user_id => undef },
        event_type => 'report.released',
        actor_id   => $actor_user_id,
        payload    => { assigned_moderator_user_id => undef },
    };
}

sub _resolve_spec ( $self, $report_id, $resolution, $actor_user_id ) {
    my $resolved_at = $self->clock->now_iso8601;
    return {
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
    };
}

# Under the report's lock: a report already where the transition takes it
# is answered as it stands; any other gets the changes, an event and an
# audit entry.
sub _transition ( $self, $spec ) {
    return $self->schema->txn_do(
        sub {
            $self->_lock_report( $spec->{report_id} );
            my $report = $self->_report_row(
                { report_id => $spec->{report_id}, hold => 1 } );
            return if !$report;

            return _report_transition_hash($report)
              if $spec->{settled}->($report);

            $self->_update_report( $report, $spec->{changes} );
            $self->_record_transition_event_and_audit(
                _transition_input( $spec, $report ) );

            return { report_id => $spec->{report_id}, %{ $spec->{changes} } };
        }
    );
}

async sub _transition_p ( $self, $spec, $context ) {
    return $self->_transition($spec) if !$self->functions;
    return await $self->functions->transaction_p(
        async sub ($scope) {
            my $report = GPForum::Infrastructure::ResultRow->from(
                await $scope->row_p(
                    'moderation_report_find',
                    _find_values(
                        { report_id => $spec->{report_id}, hold => 1 }
                    )
                )
            );
            return undef if !$report;

            return _report_transition_hash($report)
              if $spec->{settled}->($report);

            await $scope->row_p( 'moderation_report_update',
                _report_update_values( $report, $spec->{changes} ) );
            %{$report} = ( %{$report}, %{ $spec->{changes} } );
            my ( $event, $audit ) =
              $self->_transition_records( _transition_input( $spec, $report ) );
            await $scope->row_p( 'ops_record_event',
                $self->recorder->event_call( %{$event} ) );
            await $scope->row_p( 'ops_record_audit',
                $self->recorder->audit_call( %{$audit} ) );

            return { report_id => $spec->{report_id}, %{ $spec->{changes} } };
        },
        $context
    );
}

sub _transition_input ( $spec, $report ) {
    return {
        report     => $report,
        event_type => $spec->{event_type},
        actor_id   => $spec->{actor_id},
        payload    => $spec->{payload},
    };
}

sub list_queue ( $self, $options ) {
    if ( $self->functions ) {
        return _queue_rows( $self->functions->rows( _queue_values($options) ) );
    }
    return [ rows_in( $self->queue_resultset($options) ) ];
}

# The report queue's read on the worker's pooled asynchronous connections,
# not a forked child with a connection of its own.
async sub list_queue_p ( $self, $options, $context = undef ) {
    return $self->list_queue($options) if !$self->functions;
    return _queue_rows(
        await $self->functions->rows_p( _queue_values($options), $context ) );
}

sub _queue_values ($options) {
    return (
        'moderation_report_queue',
        {
            status    => $options->{status} || $STATUS_OPEN,
            row_limit => $options->{limit}  || $DEFAULT_QUEUE_LIMIT
        }
    );
}

sub _queue_rows ($rows) {
    return [ map { GPForum::Infrastructure::ResultRow->from($_) } @{$rows} ];
}

# The resultset the moderation queue executes.
# Public so the query-plan evidence EXPLAINs what actually runs.
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

sub _report_row ( $self, $input ) {
    return $self->schema->resultset('Report')->find( $input->{report_id} )
      if !$self->functions;
    return GPForum::Infrastructure::ResultRow->from(
        $self->functions->row( 'moderation_report_find', _find_values($input) )
    );
}

sub _find_values ($input) {
    return {
        report_id        => undef,
        reporter_user_id => undef,
        target_type      => undef,
        target_id        => undef,
        hold             => 0,
        %{$input}
    };
}

sub _update_report ( $self, $row, $changes ) {
    return $row->update($changes) if !$self->functions;
    $self->functions->row( 'moderation_report_update',
        _report_update_values( $row, $changes ) );
    %{$row} = ( %{$row}, %{$changes} );
    return $row;
}

sub _report_update_values ( $row, $changes ) {
    return { report_id => column_of( $row, 'report_id' ), changes => $changes };
}

sub _report_transition_hash ($report) {
    return {
        assigned_moderator_user_id =>
          column_of( $report, 'assigned_moderator_user_id' ),
        report_id   => column_of( $report, 'report_id' ),
        resolution  => column_of( $report, 'resolution' ),
        resolved_at => column_of( $report, 'resolved_at' ),
        status      => column_of( $report, 'status' ),
    };
}

sub _record_event_and_audit ( $self, $report ) {
    my $recorded = {
        correlation_id => $self->id_service->uuid,
        report         => $report,
    };
    $self->recorder->record_event(
        %{ $self->events->report_created_envelope($recorded) } );
    $self->recorder->record_audit(
        %{ $self->events->report_created_audit($recorded) } );

    return;
}

sub _record_transition_event_and_audit ( $self, $input ) {
    my ( $event, $audit ) = $self->_transition_records($input);
    $self->recorder->record_event( %{$event} );
    $self->recorder->record_audit( %{$audit} );

    return;
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

sub _lock_report ( $self, $report_id ) {
    return if $self->functions;
    my $dbh = GPForum::Infrastructure::Storage->dbh_of( $self->schema );
    if ( !$dbh ) {
        return;
    }

    $dbh->selectrow_array( $REPORT_LOCK_SQL, undef, $report_id );

    return;
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

Assigning, releasing and resolving lock the report row with
C<SELECT ... FOR UPDATE> first, when the schema has a database handle. A
transition that would change nothing writes nothing and records no event.

=head1 SUBROUTINES/METHODS

=head2 create_report

Takes a hash reference with C<reporter_user_id>, C<target_type>,
C<target_id>, C<reason> and an optional C<details> (empty when omitted).
Returns a hash reference of the new C<open> report's columns, or, when the
member already has an open or triaged report on that target, that report's
row.

=head2 create_report_p

L</create_report> as a promise: takes the input, an optional query context
and an optional call layer. It runs on the worker's pooled asynchronous
connections, in its own transaction or in the one the call layer belongs to.

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
transaction on the worker's pooled asynchronous connections.

=head2 release_report

Takes a report id and the acting user's id. Clears the assignment and
records C<report.released>. Returns
C<< { report_id, assigned_moderator_user_id => undef } >>; when the report
is not assigned, the report's state hash as for C<assign_report>. Returns
an empty list (undef in scalar context) when there is no such report.

=head2 release_report_p

L</release_report> as a promise, with an optional query context last, in one
transaction on the worker's pooled asynchronous connections.

=head2 resolve_report

Takes a report id, a resolution and, optionally, the acting user's id.
Sets the status to C<resolved> with C<resolved_at> and the resolution, and
records C<report.resolved>. Returns
C<< { report_id, status, resolved_at, resolution } >>; when the report is
already resolved, the report's state hash as for C<assign_report>. Returns
an empty list (undef in scalar context) when there is no such report.

=head2 resolve_report_p

L</resolve_report> as a promise, with an optional query context last, in one
transaction on the worker's pooled asynchronous connections.

=head2 list_queue

Takes a hash reference of the options C<queue_resultset> takes. Returns an
array reference of the report rows.

=head2 list_queue_p

L</list_queue> as a promise, with an optional query context last, read on
the worker's pooled asynchronous connections. Without SQL functions it
answers the blocking read.

=head2 queue_resultset

Takes a hash reference with optional C<status> (default C<open>) and
C<limit> (default 50). Returns the unexecuted C<Report> resultset of the
reports in that status, oldest first, ordered by C<created_at> and then
C<report_id>. Public so the query-plan evidence EXPLAINs what actually
runs.

=head1 DIAGNOSTICS

C<create_report> croaks with the database error when the insert fails for
any reason other than a unique conflict, when an open-report conflict
leaves no report to reuse, and when the retry after an id collision fails
too. Every write runs in C<txn_do>, so a failure, including a failure to
record the event or the audit entry, rolls the whole change back and
propagates.

=head1 CONFIGURATION AND ENVIRONMENT

None. C<clock>, C<id_service>, C<recorder> and C<events> have defaults;
tests pass their own.

=head1 DEPENDENCIES

L<GPForum::Infrastructure::EventRecorder>, L<GPForum::Infrastructure::Id>,
L<GPForum::Infrastructure::Row>, L<GPForum::Infrastructure::Storage>,
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
