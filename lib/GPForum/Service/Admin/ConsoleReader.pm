# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Admin::ConsoleReader;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -async_await;
use v5.40;

use GPForum::Infrastructure::SqlFunction;
use Mojo::Promise;

use GPForum::Infrastructure::Text qw(has_text);
use GPForum::Service::Operations::QueryBudget;
use GPForum::X::Unavailable;

our $VERSION = '0.001';

const my $DEFAULT_LIMIT => 25;
const my $STATUS_OPEN   => 'open';

has metrics_snapshot => undef;    # optional: the health block shows {}
has query_budget     => sub {
    my ($self) = @_;

    return GPForum::Service::Operations::QueryBudget->new(
        schema => $self->schema );
};
has readiness => undef;           # optional: the health block shows unknown
__PACKAGE__->requires(qw(schema));

has functions => \&GPForum::Infrastructure::SqlFunction::for_service;

# Each read is written once, as its promise method (ADR 0177). The dashboard
# and the health block have no blocking twin: readiness and metrics run the
# host's checks in a CPU-only child, which a blocking caller cannot wait on.
GPForum::Infrastructure::SqlFunction->blocking_twins(
    qw(list_users email_of list_reports async_jobs count_dead_letters
      count_outbox list_outbox list_dead_letters)
);

async sub dashboard_summary_p ( $self, $options, $context = undef ) {
    my $limit = _limit( $options || {} );

    return {
        async  => await $self->async_jobs_p( { limit => $limit }, $context ),
        health => await $self->operations_status_p($context),
        moderation => {
            reports => await $self->list_reports_p(
                {
                    limit  => $limit,
                    status => $STATUS_OPEN,
                },
                $context
            ),
        },
        users => await $self->list_users_p( { limit => $limit }, $context ),
    };
}

async sub list_users_p ( $self, $options, $context = undef ) {
    $options ||= {};
    return await $self->_functions->rows_p( 'admin_console_users',
        { status => _status($options), row_limit => _limit($options) },
        $context );
}

# The only address a console action may mail on an administrator's behalf:
# their own (Admin::Diagnostics' test message). Undef for no such account.
async sub email_of_p ( $self, $user_id, $context = undef ) {
    my $row = await $self->_functions->row_p( 'admin_console_email',
        { user_id => $user_id }, $context );
    return $row ? $row->{email_normalized} : undef;
}

async sub list_reports_p ( $self, $options, $context = undef ) {
    $options ||= {};
    return await $self->_functions->rows_p(
        'admin_console_reports',
        {
            status    => $options->{status} || $STATUS_OPEN,
            row_limit => _limit($options)
        },
        $context
    );
}

# The four reads are independent: all four are sent before the first is
# awaited, so on pooled connections they run together. The totals are
# counted, not measured from the lists: those are truncated to the
# dashboard limit, so their length would stop the queue depth and the
# dead-letter total at 10, the same for eleven rows as for fifty thousand.
async sub async_jobs_p ( $self, $options, $context = undef ) {
    my $dead_letters      = $self->list_dead_letters_p( $options, $context );
    my $outbox            = $self->list_outbox_p( $options, $context );
    my $dead_letter_total = $self->count_dead_letters_p($context);
    my $outbox_total      = $self->count_outbox_p($context);

    return {
        dead_letters         => await $dead_letters,
        outbox_messages      => await $outbox,
        dead_letter_total    => await $dead_letter_total,
        outbox_message_total => await $outbox_total,
    };
}

async sub count_dead_letters_p ( $self, $context = undef ) {
    return await $self->_count_p( 1, $context );
}

async sub count_outbox_p ( $self, $context = undef ) {
    return await $self->_count_p( 0, $context );
}

# A count that fails reads 0, so a failing count does not take the
# dashboard with it.
async sub _count_p ( $self, $dead_letters, $context ) {
    my $count;
    try {
        $count = (
            await $self->_functions->row_p(
                'admin_console_counts', { dead_letters => $dead_letters },
                $context
            )
        )->{total};
    }
    catch ($error) {
        return 0;
    };

    return $count // 0;
}

async sub list_outbox_p ( $self, $options, $context = undef ) {
    $options ||= {};
    return await $self->_functions->rows_p( 'admin_console_outbox',
        { status => _status($options), row_limit => _limit($options) },
        $context );
}

# Each dead letter carries whether it was replayed, and how its replay is
# doing, from the same statement: index lookups per row rather than a second
# query the page's query budget has no room for.
async sub list_dead_letters_p ( $self, $options, $context = undef ) {
    return await $self->_functions->rows_p( 'admin_console_dead_letters',
        { row_limit => _limit( $options || {} ) }, $context );
}

# The health block from the collaborators' own promises: readiness, metrics
# and the stored budgets read on pooled asynchronous connections. A
# collaborator without one -- a test double -- answers its blocking report.
async sub operations_status_p ( $self, $context = undef ) {
    my $readiness = await _safe_call_p(
        sub {
            my $service = $self->readiness;
            return $service->can('check_p')
              ? $service->check_p($context)
              : $service->check;
        },
        { status => 'unknown', checks => [] }
    );
    my $metrics = await _safe_call_p(
        sub {
            my $service = $self->metrics_snapshot;
            return $service->can('collect_p')
              ? $service->collect_p($context)
              : $service->collect;
        },
        {}
    );
    my $query_budgets =
      await _safe_call_p( sub { return $self->query_budget->snapshot; },
        { endpoints => {} } );
    my $query_budget_drift = await _safe_call_p(
        sub {
            my $budget = $self->query_budget;
            return $budget->can('drift_report_p')
              ? $budget->drift_report_p($context)
              : $budget->drift_report( $self->schema );
        },
        { status => 'unknown' }
    );

    return {
        benchmark => {
            configured_command => 'script/benchmark-http --configured --check',
            fixture_command    => 'script/benchmark-http --fixture --check',
            persisted_baseline => 0,
            status             => 'manual',
        },
        metrics            => $metrics,
        query_budget_drift => $query_budget_drift,
        query_budgets      => $query_budgets,
        readiness          => $readiness,
    };
}

# A collector that dies, or is not set, answers its placeholder.
async sub _safe_call_p ( $callback, $fallback ) {
    my $result;
    try {
        $result = await Mojo::Promise->resolve( $callback->() );
    }
    catch ($error) {
        return $fallback;
    };

    return $result // $fallback;
}

sub _status ($options) {
    return has_text( $options->{status} ) ? $options->{status} : undef;
}

sub _limit ($options) {
    return $options->{limit} || $DEFAULT_LIMIT;
}

# The commands read the console too (dead-letter-replay --list), where a
# schema that is not PostgreSQL is a database that is not there.
sub _functions ($self) {
    return $self->functions // GPForum::X::Unavailable->throw(
        message => 'the console needs the PostgreSQL database' );
}

1;

__END__

=head1 NAME

GPForum::Service::Admin::ConsoleReader - Read-only queries behind the administration console.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $reader = GPForum::Service::Admin::ConsoleReader->new(
        metrics_snapshot => $metrics_snapshot,
        readiness        => $readiness,
        schema           => $schema,
    );
    my $summary = await $reader->dashboard_summary_p( { limit => 10 } );
    my $users   = $reader->list_users( { status => 'active', limit => 50 } );
    my $jobs    = $reader->async_jobs( { limit => 25 } );
    my $email   = $reader->email_of($admin_user_id);

=head1 DESCRIPTION

Everything the console's dashboard and lists read: members, open reports,
outbox messages, dead letters and the health of the running system. It
writes nothing.

Every list is bounded by C<limit> (default 25) and selects only the
columns it returns, each row as a plain hash reference. The queue depth and
the dead-letter total are counted, not measured from those lists: the
dashboard used to count a list already cut to its limit, so both totals
stopped at the limit whatever the real number was.

A dead letter carries its replay status from the same statement
(C<api.admin_console_dead_letters>), so the page does not spend a query per
row on it.

The health block never fails the page: readiness, metrics and query budget
each fall back to a placeholder when their collector dies or is not set.
The attributes are C<schema>, which every query needs, C<readiness> and
C<metrics_snapshot>, both optional, and C<query_budget>, which defaults to
a L<GPForum::Service::Operations::QueryBudget> over the schema.

=head1 SUBROUTINES/METHODS

Each read is written once, as its promise method, and the ones a command or
a job reads have a blocking twin (ADR 0177). Every read takes an optional
query context last.

=head2 dashboard_summary_p

Takes a hash reference (or undef) with an optional C<limit>. Resolves with a
hash reference with C<async> (as L</async_jobs_p>), C<health> (as
L</operations_status_p>), C<< moderation => { reports => [...] } >> (the
open reports) and C<users> (as L</list_users_p>), each list bounded by the
limit. It has no blocking twin: the health block's collectors run the
host's checks in a CPU-only child.

=head2 list_users_p

Takes a hash reference (or undef) with optional C<status> and C<limit>.
Resolves with an array reference of the members not deleted, newest first
and then by username, each a hash reference of C<id>, C<username>,
C<display_name>, C<email_normalized>, C<status>, C<trust_level>,
C<email_verified_at>, C<created_at>, C<updated_at> and C<deleted_at>.
C<list_users> is its blocking twin.

=head2 email_of_p

Takes a user id. Resolves with that member's normalized address, or undef
when there is no such member or the account is deleted. It is the only
address a console action may mail on an administrator's behalf: their own,
for L<GPForum::Service::Admin::Diagnostics>' test message. C<email_of> is
its blocking twin.

=head2 list_reports_p

Takes a hash reference (or undef) with optional C<status> (default
C<open>) and C<limit>. Resolves with an array reference of the reports in
that status, oldest first, each a hash reference of C<report_id>,
C<reporter_user_id>, C<target_type>, C<target_id>, C<reason>, C<details>,
C<status>, C<assigned_moderator_user_id>, C<created_at>, C<resolved_at>
and C<resolution>. C<list_reports> is its blocking twin.

=head2 async_jobs_p

Takes a hash reference (or undef) of the options L</list_outbox_p> and
L</list_dead_letters_p> take. Resolves with a hash reference with
C<dead_letters> and C<outbox_messages> (the two lists) and
C<dead_letter_total> and C<outbox_message_total> (the full counts); the
four reads are sent together. C<async_jobs> is its blocking twin.

=head2 count_dead_letters_p

Resolves with the number of rows in C<dead_letters>, or 0 when the count
fails. C<count_dead_letters> is its blocking twin.

=head2 count_outbox_p

Resolves with the number of rows in C<outbox_messages>, whatever their
status, or 0 when the count fails. C<count_outbox> is its blocking twin.

=head2 list_outbox_p

Takes a hash reference (or undef) with optional C<status> and C<limit>.
Resolves with an array reference of outbox messages, newest first, each a
hash reference of its queue, job, lock, attempt and error columns.
C<list_outbox> is its blocking twin.

=head2 list_dead_letters_p

Takes a hash reference (or undef) with an optional C<limit>. Resolves with
an array reference of dead letters, the most recently failed first, each a
hash reference of its source, error and retry columns plus
C<replay_status>: the replay message's status while it is kept,
C<replayed> once only the audit log remembers it, undef when it was never
replayed. C<list_dead_letters> is its blocking twin.

=head2 operations_status_p

Resolves with a hash reference with C<readiness> (the readiness check, or
C<< { status => 'unknown', checks => [] } >>), C<metrics> (the metrics
snapshot, or an empty hash), C<query_budgets> (the query budget snapshot,
or C<< { endpoints => {} } >>), C<query_budget_drift> (the drift report, or
C<< { status => 'unknown' } >>) and C<benchmark>, which names the
benchmark commands and reports C<manual>: no benchmark baseline is
persisted. Readiness, metrics and the stored budgets are read without a
child touching PostgreSQL; a collaborator without a promise answers its
blocking report.

=head1 DIAGNOSTICS

The lists and C<email_of_p> fail when the database does, and every read
throws L<GPForum::X::Unavailable> without the function layer. The counts
answer 0 instead, and L</operations_status_p> its placeholders, so a
failing collector does not take the dashboard with it.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<Const::Fast>, L<GPForum::Base>,
L<GPForum::Infrastructure::SqlFunction>,
L<GPForum::Service::Operations::QueryBudget>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

A count that fails reads as 0, the same as an empty queue.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
