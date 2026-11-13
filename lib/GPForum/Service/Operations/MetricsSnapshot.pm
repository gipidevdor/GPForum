# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Operations::MetricsSnapshot;

use Const::Fast;
use English qw(-no_match_vars);
use Mojo::Base -base, -signatures, -async_await;
use v5.40;

use GPForum::Infrastructure::AsyncQuery;
use GPForum::Infrastructure::AsyncWork;
use GPForum::Infrastructure::Storage;
use Scalar::Util qw(blessed);
use Time::HiRes  qw(time);

use GPForum::Service::Operations::OSPreflight;
use GPForum::Service::Operations::QueryBudget;
use GPForum::Service::Operations::Replication;
use GPForum::Service::Clock;

use GPForum::Infrastructure::SqlFunction;

our $VERSION = '0.001';
has functions => \&GPForum::Infrastructure::SqlFunction::for_service;

const my $MILLISECONDS_PER_SECOND => 1000;
const my $MAX_ERROR_LENGTH        => 240;

has clock          => sub { return GPForum::Service::Clock->new; };
has db_query_stats => undef;    # optional: its section is empty without one
has local_caches   => sub { return []; };
has schema => undef;    # optional: its database sections are empty without one
has rate_limiter        => undef;   # optional: its section is empty without one
has realtime_hub        => undef;   # optional: its section is empty without one
has realtime_supervisor => undef;   # optional: its section is empty without one
has security_telemetry  => undef;   # optional: its section is empty without one
has projection_trackers => sub { return []; };
has query_budget =>
  sub { return GPForum::Service::Operations::QueryBudget->new; };
has replication =>
  sub { return GPForum::Service::Operations::Replication->new; };
has runtime        => undef;    # optional: its sections are empty without one
has runtime_policy => undef;    # optional: its section is empty without one
has started_at     => sub { return time; };

# Its counters are the process's (a per-request dispatcher's would die with
# the request), so the one built for this scrape reads what every request's
# counted. Without it a badge that failed after a write was counted and
# never reported.
has notification_dispatcher => undef;    # optional: no section without one

# Built here, before a blocking copy is made: a lazy start would be drawn
# again in the copy, and the uptime would count from the scrape.
sub new ( $class, @arguments ) {
    my $self = $class->SUPER::new(@arguments);
    $self->started_at;

    return $self;
}

# The snapshot is collected once, as its promise method (ADR 0177); collect
# is its blocking twin.
GPForum::Infrastructure::SqlFunction->blocking_twins('collect');

# Collected in the worker whose counters it reports: the database sections
# read on its call layer, and the host's sections -- ps and the like -- in a
# CPU-only child that never touches PostgreSQL, or in the process on a
# blocking layer, whose promise a child would leave pending. Without a call
# layer (no schema) the database sections are empty.
async sub collect_p ( $self, $context = undef ) {
    my $functions = $self->functions;
    my $os =
      $functions && !$functions->blocking
      ? await GPForum::Infrastructure::AsyncWork->shared->cpu_p(
        sub { return $self->_os_sections; } )
      : $self->_os_sections;
    my $sections = $self->_process_sections($os);
    return {
        %{$sections},
        map { $_ => {} } qw(query_budget_drift database outbox replication)
      }
      if !$functions;

    return {
        %{$sections},
        query_budget_drift =>
          await $self->_query_budget_drift_p( $functions, $context ),
        database    => await $self->_database_p( $functions, $context ),
        outbox      => await $self->_outbox_p( $functions, $context ),
        replication => await $self->_replication_p( $functions, $context ),
    };
}

# Every section but the database's: the process's own counters, with the
# host's sections given.
sub _process_sections ( $self, $os ) {
    my $runtime = $self->runtime;

    return {
        generated_at => $self->clock->now_iso8601,
        process      => {
            pid            => $PROCESS_ID,
            uptime_seconds => int( time - $self->started_at ),
        },
        runtime => $runtime ? $runtime->as_hash : {},
        %{$os},
        runtime_enforcement => _section( $self->runtime_policy, 'report' ),
        local_caches        => [
            grep { defined }
            map  { $_->snapshot } @{ $self->local_caches }
        ],
        realtime          => _section( $self->realtime_hub ),
        realtime_listener => _section( $self->realtime_supervisor ),
        notifications     => $self->_notifications,
        rate_limits       => $self->_rate_limits,
        security          => _section( $self->security_telemetry ),
        projections       => [
            grep { defined }
            map  { $_->observe_lag } @{ $self->projection_trackers }
        ],
        db_query_stats => _section( $self->db_query_stats ),
        async_queries  => $self->schema
          && $self->schema->isa('GPForum::Schema')
          && $self->schema->{gp_async_query}
        ? $self->schema->{gp_async_query}->snapshot
        : {},
        query_budgets => $self->query_budget->snapshot,
    };
}

async sub _query_budget_drift_p ( $self, $functions, $context ) {
    my $report;
    try {
        $report =
          await GPForum::Service::Operations::QueryBudget->new(
            functions => $functions )->drift_report_p($context);
    }
    catch ($error) {
        return {};
    };

    return $report || {};
}

# A SELECT 1, timed: on a pooled connection, or on a blocking layer on the
# handle as it stands -- storage->dbh would ping first, a second round trip
# on every scrape for the probe the SELECT already is.
async sub _database_p ( $self, $functions, $context ) {
    my $started = time;
    my $ok      = 1;
    if ( $functions->blocking ) {
        my $answered = GPForum::Infrastructure::Storage->with_handle(
            $self->schema,
            sub ( $, $dbh ) {
                return scalar $dbh->selectrow_array('SELECT 1');
            }
        );
        $ok = defined $answered ? 1 : 0;
    }
    else {
        try {
            await GPForum::Infrastructure::AsyncQuery->for_schema(
                $self->schema )
              ->run_p( sub ($db) { return $db->query_p('SELECT 1'); },
                $context );
        }
        catch ($error) {
            $ok = 0;
        };
    }

    return {
        ready_latency_ms =>
          int( ( time - $started ) * $MILLISECONDS_PER_SECOND ),
        status => $ok ? 'ok' : 'fail',
    };
}

async sub _outbox_p ( $self, $functions, $context ) {
    my $snapshot;
    try {
        $snapshot = await $functions->row_p( 'ops_outbox_metrics',
            { now => $self->clock->now_iso8601 }, $context );
    }
    catch ($error) {
        return {};
    };

    return $snapshot;
}

# ADR 0058: replication lag is monitored. Read on every scrape -- three
# catalog reads -- and guarded like the database section, so a node that
# cannot read the replication views reports it here instead of failing the
# whole snapshot.
async sub _replication_p ( $self, $functions, $context ) {
    my ( $snapshot, $failure );
    try {
        $snapshot =
          await $self->replication->snapshot_p( $functions, $context );
    }
    catch ($error) {
        $failure = $error;
    };
    return $snapshot if $snapshot;

    return {
        error  => _compact_error($failure),
        status => 'unavailable',
    };
}

# An optional collaborator's section: what it reports, or nothing without it.
sub _section ( $collaborator, $method = 'snapshot' ) {
    return {} if !$collaborator;

    return $collaborator->$method;
}

# The runtime's operating-system sections, each empty without a runtime.
sub _os_sections ($self) {
    my $runtime = $self->runtime;
    if ( !$runtime ) {
        return { map { $_ => {} }
              qw(os os_features os_sockets os_processes os_preflight) };
    }

    my $profile  = $runtime->os_profile;
    my $settings = $runtime->os_feature_settings;

    return {
        os           => $profile->snapshot,
        os_features  => $profile->feature_snapshot($settings),
        os_sockets   => $profile->socket_snapshot($settings),
        os_processes => $profile->process_snapshot,
        os_preflight => GPForum::Service::Operations::OSPreflight->new(
            runtime => $runtime,
            %{ $runtime->os_preflight_settings || {} },
        )->check,
    };
}

# A dispatcher that keeps no counters (a stand-in for one) reports none,
# rather than failing the scrape.
sub _notifications ($self) {
    my $dispatcher = $self->notification_dispatcher;
    return {} if !blessed $dispatcher || !$dispatcher->can('snapshot');

    return $dispatcher->snapshot;
}

sub _rate_limits ($self) {
    return {} if !$self->rate_limiter;

    my $snapshot = $self->rate_limiter->snapshot;
    my $stats    = $snapshot->{stats} || {};

    $snapshot->{rate_limit_allowed} = $stats->{allowed} // 0;
    $snapshot->{rate_limit_blocked} = $stats->{blocked} // 0;
    $snapshot->{degraded_rate_limiter_active} =
      (      ( $snapshot->{status} || q{} ) eq q{degraded}
          || ( $stats->{fallback_used} || 0 ) > 0 ) ? 1 : 0;

    return $snapshot;
}

# Outbox rows due for another attempt.
# Public so the query-plan evidence EXPLAINs what actually runs.
sub retry_backlog_resultset ($self) {
    return $self->schema->resultset('OutboxMessage')->search_rs(
        {
            status          => { -in  => [ 'pending', 'failed' ] },
            next_attempt_at => { '<=' => $self->clock->now_iso8601 },
        }
    );
}

sub _compact_error ($error) {
    $error //= q{};
    $error =~ s/\s+/ /gmsx;
    $error =~ s/\A\s+|\s+\z//gmsx;

    return substr $error, 0, $MAX_ERROR_LENGTH;
}

1;

__END__

=head1 NAME

GPForum::Service::Operations::MetricsSnapshot - The process, runtime and database snapshot behind the metrics endpoint.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $metrics = GPForum::Service::Operations::MetricsSnapshot->new(
        runtime                 => $runtime,
        runtime_policy          => $runtime_policy,
        schema                  => $schema,
        db_query_stats          => $db_query_stats,
        realtime_hub            => $realtime_hub,
        notification_dispatcher => $notification_dispatcher,
        rate_limiter            => $rate_limiter,
        security_telemetry      => $security_telemetry,
        local_caches            => [$local_cache],
    );

    my $snapshot = $metrics->collect;

=head1 DESCRIPTION

Gathers, in one hash, what the operations metrics endpoint reports: the
process id and uptime, the runtime and its OS profile (snapshot, features,
sockets, processes and preflight check), runtime enforcement, local caches,
the realtime hub and its listener supervisor, the notification
dispatcher's badge failures, rate limits, security telemetry, projection
lag, database query statistics, query budgets and their drift, database
readiness, the outbox backlog and replication (ADR 0058). Each collaborator
is optional: a section whose collaborator is not set comes back empty, and
so does the notifications section when the dispatcher has no C<snapshot>;
the database sections are empty without a call layer (C<functions>, built
on a C<GPForum::Schema>).

The database section times a C<SELECT 1>; the outbox, query budget drift and
replication sections are guarded too, so a database that cannot answer turns
them empty, C<fail> or C<unavailable> rather than failing the whole snapshot.
The replication section is L<GPForum::Service::Operations::Replication/snapshot>:
on a primary each standby's replay lag and bytes behind and each slot's
retained WAL, on a standby the age of the last replayed transaction. The rate limit section
adds C<rate_limit_allowed>, C<rate_limit_blocked> and
C<degraded_rate_limiter_active>, which is 1 when the limiter reports
C<degraded> or has used its fallback store.

=head1 SUBROUTINES/METHODS

=head2 new

Builds the snapshot with C<started_at> drawn now, so a blocking copy
(L<GPForum::Infrastructure::SqlFunction/blocking_copy>) counts the uptime
from the same moment.

=head2 collect

The blocking twin of L</collect_p> (ADR 0177): returns the snapshot hash reference with the keys C<generated_at>,
C<process> (C<pid>, C<uptime_seconds> since C<started_at>), C<runtime>,
C<os>, C<os_features>, C<os_sockets>, C<os_processes>, C<os_preflight>,
C<runtime_enforcement>, C<local_caches>, C<realtime>,
C<realtime_listener>, C<notifications> (the notification dispatcher's
L<GPForum::Service::Notification::Dispatcher/snapshot>: C<badge_failures>
and C<last_badge_error>), C<rate_limits>, C<security>, C<projections>,
C<db_query_stats>, C<query_budgets>, C<query_budget_drift>, C<database>
(C<status> C<ok> or C<fail>, and C<ready_latency_ms>), C<outbox>
(C<pending>, C<failed>, C<retry_backlog>, C<dead_letters>) and
C<replication> (the replication snapshot, or C<status> C<unavailable> and the
C<error>).

=head2 collect_p

Answers a promise of the snapshot, collected in the worker whose counters
it reports: the database sections read on its call layer, the host's
sections in a CPU-only child on the pooled layer and in the process on a
blocking one. The snapshot is written once, here.

=head2 retry_backlog_resultset

Returns the resultset of outbox messages that are C<pending> or C<failed>
and due for another attempt (C<next_attempt_at> not after now). It is public
so the query-plan evidence EXPLAINs the query the outbox section counts.
Needs C<schema>.

=head1 DIAGNOSTICS

The database, outbox, query budget drift and replication sections catch
their own errors. Errors from the other collaborators' snapshots propagate from
C<collect_p>. C<retry_backlog_resultset> dies without a C<schema>.

=head1 CONFIGURATION AND ENVIRONMENT

None read here; the bootstrap passes the runtime and its policy.

=head1 DEPENDENCIES

L<GPForum::Service::Operations::OSPreflight>,
L<GPForum::Service::Operations::QueryBudget>,
L<GPForum::Service::Operations::Replication>,
L<GPForum::Service::Clock>, L<Scalar::Util>.

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
