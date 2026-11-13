# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Operations::RateLimiter;

use Const::Fast;
use Digest::SHA qw(sha256_hex);
use Socket      qw(AF_INET6 inet_ntop inet_pton);
use Mojo::Base -base, -async_await;
use v5.40;

use GPForum::Infrastructure::EventRecorder;
use GPForum::Service::Clock;
use GPForum::Service::Operations::RateLimiter::DegradationPolicy;
use GPForum::Service::Operations::RateLimiter::LocalMemoryStore;

use Scalar::Util qw(blessed);

use GPForum::Infrastructure::SqlFunction;

our $VERSION = '0.001';

const my $SCHEMA_VERSION           => 1;
const my $DEFAULT_LIMIT            => 60;
const my $DEFAULT_WINDOW_SECONDS   => 60;
const my $HTTP_TOO_MANY_REQUESTS   => 429;
const my $DENIED_OVER_LIMIT        => 'over_limit';
const my $DENIED_STORE_UNAVAILABLE => 'store_unavailable';
const my $UNAVAILABLE_STORE        => 'unavailable';

has clock              => sub { return GPForum::Service::Clock->new; };
has degradation_policy => sub {
    return GPForum::Service::Operations::RateLimiter::DegradationPolicy->new;
};
has fallback_store => sub {
    my ($self) = @_;

    return GPForum::Service::Operations::RateLimiter::LocalMemoryStore->new(
        clock => $self->clock, );
};
has id_service => sub {
    require GPForum::Infrastructure::Id;
    return GPForum::Infrastructure::Id->new;
};
has primary_store => undef;   # optional: without one the fallback store decides
has recorder      => \&GPForum::Infrastructure::EventRecorder::for_service;
has schema             => undef;  # optional: without one blocks are not audited
has security_telemetry => undef;  # optional: without one nothing is recorded
has stats              => sub {
    return {
        allowed            => 0,
        audit_failures     => 0,
        blocked            => 0,
        blocked_degraded   => 0,
        blocked_over_limit => 0,
        checks             => 0,
        fallback_used      => 0,
        primary_failures   => 0,
    };
};

# The counters and the local buckets are the process's, shared with every
# blocking copy of the limiter: they are built here, before a copy is made,
# or a copy would count in state of its own and lose it.
sub new ( $class, @arguments ) {
    my $self = $class->SUPER::new(@arguments);
    $self->stats;
    $self->fallback_store;

    return $self;
}

# The call layer the decision is read on: the primary store's, or the
# recorder's when only blocks are audited. blocking_copy makes the parts
# block only when the limiter has one.
has functions => sub ($self) {
    for my $part ( $self->primary_store, $self->_auditor ) {
        my $functions =
          blessed $part && $part->can('functions') ? $part->functions : undef;
        return $functions if $functions;
    }
    return undef;
};

# A check is written once, as its promise method (ADR 0177); check is its
# blocking twin, the primary store and the recorder blocking with it.
GPForum::Infrastructure::SqlFunction->blocking_twins('check');

# The recorder is a part only when blocks are audited: without a schema
# there is none to build.
sub blocking_parts ($self) {
    return ( 'primary_store', $self->schema ? 'recorder' : () );
}

async sub check_p ( $self, $input, $context = undef ) {
    $input = _limited_input($input);
    my $decision = await $self->_primary_decision_p( $input, $context );
    $decision //= $self->_degraded_decision($input);
    _mark_denied_reason($decision);
    my $audited = $self->_record_decision( $input, $decision );
    if ($audited) { await $audited; }

    return $decision;
}

sub snapshot ($self) {
    my $store_snapshot = $self->_store_snapshot;

    return {
        %{$store_snapshot},
        degradation_mode => $self->degradation_policy->mode,
        fail_closed      => $self->degradation_policy->fail_closed,
        stats            => { %{ $self->stats } },
    };
}

# The primary store's decision, or undef when there is none or it failed:
# a failure is counted and reported, and the degradation policy decides.
async sub _primary_decision_p ( $self, $input, $context ) {
    my $store = $self->primary_store or return undef;
    my $decision;
    try {
        $decision = await $store->check_p( $input, $context );
    }
    catch ($error) {
        $decision = undef;
    };
    return $decision if $decision;

    $self->stats->{primary_failures} += 1;
    $self->_telemetry(
        'rate_limit_store_degraded',
        {
            action   => $input->{action},
            degraded => 1,
            reason   => 'primary_store_failed',
            store    => 'postgresql',
        },
    );
    return undef;
}

sub _degraded_decision ( $self, $input ) {
    return $self->_check_fallback($input) if !$self->primary_store;
    return $self->_check_fallback($input)
      if !$self->degradation_policy->fail_closed;

    return $self->_fail_closed_decision($input);
}

sub _check_fallback ( $self, $input ) {
    my $decision = $self->fallback_store->check($input);
    if ( $self->primary_store ) {
        $decision->{degraded} = 1;
        $self->stats->{fallback_used} += 1;
    }

    return $decision;
}

sub _fail_closed_decision ( $self, $input ) {
    my $limit          = $input->{limit}          || $DEFAULT_LIMIT;
    my $window_seconds = $input->{window_seconds} || $DEFAULT_WINDOW_SECONDS;

    $self->_telemetry(
        'rate_limit_fail_closed',
        {
            action   => $input->{action},
            degraded => 1,
            reason   => $DENIED_STORE_UNAVAILABLE,
            status   => $HTTP_TOO_MANY_REQUESTS,
            store    => $UNAVAILABLE_STORE,
        },
    );

    return {
        ok              => 0,
        key             => _fail_closed_key($input),
        limit           => $limit,
        remaining       => 0,
        reset_at_epoch  => $self->clock->now_epoch + $window_seconds,
        store           => $UNAVAILABLE_STORE,
        window_seconds  => $window_seconds,
        observed_count  => $limit,
        mitigation_hint => 'retry_after_backoff',
        degraded        => 1,
        denied_reason   => $DENIED_STORE_UNAVAILABLE,
    };
}

# Counts the decision and, for a refusal, reports it; answers the promise
# of the refusal's audit, or undef when none is written.
sub _record_decision ( $self, $input, $decision ) {
    $self->stats->{checks} += 1;
    if ( $decision->{ok} ) {
        $self->stats->{allowed} += 1;
        return undef;
    }

    $self->_record_block_stats($decision);
    $self->_telemetry(
        'rate_limit_hit',
        {
            action   => $input->{action},
            degraded => $decision->{degraded} ? 1 : 0,
            reason   => $decision->{denied_reason},
            status   => $HTTP_TOO_MANY_REQUESTS,
            store    => $decision->{store},
        },
    );
    return $self->_block_audit_p( $input, $decision );
}

sub _record_block_stats ( $self, $decision ) {
    $self->stats->{blocked} += 1;
    my $counter =
      _store_unavailable($decision)
      ? 'blocked_degraded'
      : 'blocked_over_limit';
    $self->stats->{$counter} += 1;

    return;
}

# The first refusal of a window is audited, the request that went past the
# limit; the ones after it are counted (stats, telemetry) and not audited.
# Every refusal was an audit row, all of them on the one rate_limit chain
# behind one lock: a client flooding past its limit cost a chained insert
# for each request the limiter was there to shed.
async sub _block_audit_p ( $self, $input, $decision ) {
    my $recorder = $self->_auditor or return;
    return if _store_unavailable($decision);
    return
         if defined $decision->{observed_count}
      && defined $decision->{limit}
      && $decision->{observed_count} > $decision->{limit} + 1;

    my $audited;
    try {
        $audited = await $recorder->record_audit_p(
            $self->_block_audit_input( $input, $decision ) );
    }
    catch ($error) {
        $audited = undef;
    };
    if ( !$audited ) { $self->stats->{audit_failures} += 1; }

    return;
}

# The recorder of refusals: none without a schema to audit in.
sub _auditor ($self) {
    return $self->schema ? $self->recorder : undef;
}

sub _block_audit_input ( $self, $input, $decision ) {
    return {
        action     => 'rate_limit.blocked',
        actor_id   => _uuid_or_undef( $input->{actor_id} ),
        created_at => $self->clock->now_iso8601,
        metadata   => {
            action         => $input->{action},
            actor_hash     => _actor_hash($input),
            limit          => $decision->{limit},
            observed_count => $decision->{observed_count},
            scope          => $input->{scope},
            store          => $decision->{store},
            window_seconds => $decision->{window_seconds},
        },
        previous_hash  => undef,
        record_hash    => q{},
        schema_version => $SCHEMA_VERSION,
        target_id      => undef,
        target_type    => 'rate_limit',
    };
}

sub _store_snapshot ($self) {
    my $snapshot;
    try {
        $snapshot =
            $self->primary_store
          ? $self->primary_store->snapshot
          : $self->fallback_store->snapshot;
    }
    catch ($error) {
        $snapshot = undef;
    };

    if ($snapshot) {
        if ( $self->primary_store ) {
            $snapshot->{fallback} = $self->fallback_store->snapshot;
        }
        return $snapshot;
    }

    my $fallback = $self->fallback_store->snapshot;
    $fallback->{status}   = 'degraded';
    $fallback->{fallback} = 1;

    return $fallback;
}

sub _telemetry ( $self, $event_type, $metadata ) {
    return undef if !$self->security_telemetry;

    return $self->security_telemetry->record( $event_type, $metadata );
}

sub _mark_denied_reason ($decision) {
    return if $decision->{ok};

    $decision->{denied_reason} ||= $DENIED_OVER_LIMIT;

    return;
}

sub _store_unavailable ($decision) {
    return ( $decision->{denied_reason} || q{} ) eq $DENIED_STORE_UNAVAILABLE
      ? 1
      : 0;
}

sub _fail_closed_key ($input) {
    return join q{:},
      map { defined $_ ? $_ : q{} }
      ( $input->{scope}, $input->{actor_id}, $input->{action} );
}

sub _actor_hash ($input) {
    return sha256_hex( join q{:}, $input->{scope}, $input->{actor_id} || q{} );
}

sub _limited_input ($input) {
    my $actor_id = _limited_actor( $input->{actor_id} );
    return $input if ( $actor_id // q{} ) eq ( $input->{actor_id} // q{} );

    return { %{$input}, actor_id => $actor_id };
}

# One host is routed a whole IPv6 /64, so an anonymous actor keyed by its
# full address would get a fresh budget from each of 2^64 addresses: an
# IPv6 address is limited by its /64. Member ids, IPv4 and IPv4-mapped
# addresses are limited as they are.
sub _limited_actor ($actor_id) {
    return $actor_id if !defined $actor_id || index( $actor_id, q{:} ) < 0;
    my $packed = inet_pton( AF_INET6, $actor_id );
    return $actor_id if !defined $packed || $actor_id =~ /[.]/msx;

    # The first eight bytes, the network, and eight zero bytes for the host.
    return inet_ntop( AF_INET6, pack 'a8 x8', $packed ) . '/64';
}

sub _uuid_or_undef ($value) {
    return defined $value
      && $value =~
      /\A [[:xdigit:]]{8} (?: - [[:xdigit:]]{4} ){3} - [[:xdigit:]]{12} \z/msx
      ? $value
      : undef;
}

1;

__END__

=head1 NAME

GPForum::Service::Operations::RateLimiter - Shared rate limiting with an
explicit degradation policy.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $limiter = GPForum::Service::Operations::RateLimiter->new(
        degradation_policy =>
          GPForum::Service::Operations::RateLimiter::DegradationPolicy
          ->from_config($config),
        primary_store      => $postgresql_store,
        schema             => $schema,
        security_telemetry => $telemetry,
    );

    my $decision = await $limiter->check_p(
        {
            action         => 'thread.create',
            actor_id       => $user_id,
            limit          => 30,
            scope          => 'forum_http',
            window_seconds => 60,
        }
    );

=head1 DESCRIPTION

Counts actions per scope, actor, and window. The authoritative counters live in
PostgreSQL through
L<GPForum::Service::Operations::RateLimiter::PostgreSQLStore> so that every
Hypnotoad worker shares one bucket.

=head2 Local memory is never cluster state

L<GPForum::Service::Operations::RateLimiter::LocalMemoryStore> counts inside a
single process only. Under N Hypnotoad workers it enforces the configured limit
N times over, once per worker, and it loses every bucket on restart. It is
therefore the authoritative store only when C<primary_store> is undefined,
which is the single-process development and unit-test wiring. Whenever
C<primary_store> is set, the local store is a degraded stand-in, never a source
of truth: decisions taken from it are flagged C<< degraded => 1 >>, they are
counted in C<< stats->{fallback_used} >>, and the snapshot reports them under a
C<fallback> key with C<< status => 'degraded' >>. Nothing in this class or its
callers may read a local bucket and present it as a cluster-wide count.

=head2 Degradation policy

When the authoritative store throws,
L<GPForum::Service::Operations::RateLimiter::DegradationPolicy> decides what
happens next:

=over

=item permissive

Serve from the local memory store and mark the decision degraded. Correct for
development, where one process handles all traffic.

=item fail_closed

Deny the request without touching the local store, so no per-process counter is
ever mistaken for cluster state and an attacker who can break the database
cannot buy an unlimited allowance. This is the default, and the mode
L</Bootstrap wiring> derives for staging and the production profiles.

=back

The policy applies only to real degradation. A limiter built without a
C<primary_store> keeps using the local store in both modes, because nothing has
degraded.

=head2 Decision contract

C<check> always returns a hash reference with C<ok>, C<key>, C<limit>,
C<remaining>, C<reset_at_epoch>, C<store>, C<window_seconds>,
C<observed_count>, and C<mitigation_hint>. Two further keys describe failure:

=over

=item C<degraded>

Present and true when the authoritative store was unavailable for this
decision, whichever mode is active.

=item C<denied_reason>

Present on every denial. C<over_limit> means the actor exceeded the configured
allowance and the count is real. C<store_unavailable> means the limiter denied
the request because it could not count authoritatively; C<observed_count> is
then the configured limit rather than a measurement, and C<store> is
C<unavailable>.

=back

=head2 Bootstrap wiring

L<GPForum::Bootstrap::Operations> builds the limiter with a policy derived from
C<< $config->environment >>. There is no dedicated configuration knob for the
mode; add a C<rate_limit_degradation_mode> accessor to L<GPForum::Config> and
L<GPForum::Service::Operations::RateLimiter::DegradationPolicy/from_config>
will prefer it without further changes.

=head1 SUBROUTINES/METHODS

=head2 new

The Mojo::Base constructor. It builds C<stats> and C<fallback_store> at
once: they are the process's state, which the blocking copies of a check
share.

=head2 check_p

Takes the limit input hash reference and an optional query context, and
resolves with the decision described in L</Decision contract>. Records
statistics, security telemetry, and, for the first over-limit denial of a
window, an audit record, written before it resolves. Written once
(ADR 0177): C<check> is its blocking twin, the primary store and the
recorder blocking with it.

=head2 blocking_parts

The attributes a blocking check copies onto the blocking layer: the primary
store, and the recorder when there is a C<schema> to audit in.

=head2 snapshot

Returns the authoritative store snapshot merged with C<degradation_mode>,
C<fail_closed>, and a copy of C<stats>. When the authoritative snapshot throws,
the local snapshot is returned with C<< status => 'degraded' >> and
C<< fallback => 1 >> so the metrics endpoint cannot report a degraded limiter
as healthy.

=head1 DIAGNOSTICS

Telemetry separates the three interesting outcomes.
C<rate_limit_store_degraded> fires once per authoritative store failure.
C<rate_limit_fail_closed> fires only when a request is denied because the store
was unavailable. C<rate_limit_hit> fires for every denial and carries
C<reason>, matching C<denied_reason>.

The counters in C<stats> mirror that split: C<primary_failures> and
C<fallback_used> track degradation, while C<blocked> is the total of
C<blocked_over_limit> and C<blocked_degraded>.

=head1 CONFIGURATION AND ENVIRONMENT

No environment variables are read here. The degradation mode arrives as the
C<degradation_policy> attribute; see L</Bootstrap wiring>.

=head1 DEPENDENCIES

Uses L<Const::Fast>, L<Digest::SHA>, L<Mojo::Base>,
L<GPForum::Infrastructure::EventRecorder>, and L<GPForum::Service::Clock>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

A fail-closed denial writes no audit record, because the audit trail uses the
same schema that just failed. Those denials are visible only through telemetry
and C<< stats->{blocked_degraded} >>.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
