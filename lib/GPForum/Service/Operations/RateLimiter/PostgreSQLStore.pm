# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Operations::RateLimiter::PostgreSQLStore;

use Const::Fast;
use Digest::SHA qw(sha256_hex);
use Mojo::Base 'GPForum::Base', -async_await;
use v5.40;
use POSIX qw(strftime);

use GPForum::Service::Clock;
use GPForum::Infrastructure::SqlFunction;
use GPForum::X::Unavailable;

our $VERSION = '0.001';

const my $DEFAULT_LIMIT          => 60;
const my $DEFAULT_WINDOW_SECONDS => 60;

has clock => sub { return GPForum::Service::Clock->new; };
__PACKAGE__->requires(qw(schema));
has functions => \&GPForum::Infrastructure::SqlFunction::for_service;

# Each operation is written once, as its promise method (ADR 0177).
GPForum::Infrastructure::SqlFunction->blocking_twins(qw(check snapshot));

# Counts the request in its window's bucket and answers the decision. The
# count is one call, api.ops_rate_limit_check: an upsert, so every worker
# and every node counts in the same row, atomically.
async sub check_p ( $self, $input, $context = undef ) {
    my $limit          = $input->{limit}          || $DEFAULT_LIMIT;
    my $window_seconds = $input->{window_seconds} || $DEFAULT_WINDOW_SECONDS;
    my $now            = $self->clock->now_epoch;
    my $window_start   = $now - ( $now % $window_seconds );
    my $reset_at       = $window_start + $window_seconds;
    my $row            = await $self->_functions->row_p(
        'ops_rate_limit_check',
        {
            scope          => $input->{scope},
            actor_hash     => _actor_hash($input),
            action         => $input->{action},
            window_start   => _iso8601_from_epoch($window_start),
            window_seconds => $window_seconds,
            limit          => $limit,
            now            => _iso8601_from_epoch($now),
            expires_at     => _iso8601_from_epoch($reset_at),
        },
        $context
    );

    return {
        ok  => $row->{observed_count} <= $limit ? 1 : 0,
        key => join( q{:},
            $input->{scope},  $row->{actor_hash},
            $input->{action}, $row->{window_started_at} ),
        limit           => $limit,
        remaining       => _remaining( $limit, $row->{observed_count} ),
        reset_at_epoch  => $reset_at,
        store           => 'postgresql',
        window_seconds  => $window_seconds,
        observed_count  => $row->{observed_count},
        mitigation_hint => 'slow_down',
        actor_hash      => $row->{actor_hash},
    };
}

async sub snapshot_p ( $self, $context = undef ) {
    my $row = await $self->_functions->row_p( 'ops_rate_limit_snapshot',
        { now => $self->clock->now_iso8601 }, $context );
    return {
        buckets => 0 + $row->{buckets},
        store   => 'postgresql',
        status  => 'ok'
    };
}

sub _functions ($self) {
    return $self->functions // GPForum::X::Unavailable->throw(
        message => 'the rate limit store needs the PostgreSQL function layer' );
}

sub _actor_hash ($input) {
    return sha256_hex( join q{:}, $input->{scope}, $input->{actor_id} || q{} );
}

sub _remaining ( $limit, $count ) {
    my $remaining = $limit - $count;

    return $remaining > 0 ? $remaining : 0;
}

sub _iso8601_from_epoch ($epoch) {
    return strftime '%Y-%m-%dT%H:%M:%SZ', gmtime $epoch;
}

1;

__END__

=head1 NAME

GPForum::Service::Operations::RateLimiter::PostgreSQLStore - Rate limit counters shared by every worker, in PostgreSQL.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $store = GPForum::Service::Operations::RateLimiter::PostgreSQLStore
      ->new( schema => $schema );
    my $decision = await $store->check_p(
        {
            action         => 'thread.create',
            actor_id       => $user_id,
            limit          => 30,
            scope          => 'forum_http',
            window_seconds => 60,
        }
    );
    my $snapshot = await $store->snapshot_p;

=head1 DESCRIPTION

The primary store behind L<GPForum::Service::Operations::RateLimiter>. Each
check is one call, C<api.ops_rate_limit_check>, whose body is an
C<INSERT ... ON CONFLICT DO UPDATE> on C<rate_limit_buckets>,
keyed by scope, actor hash, action and the start of the fixed window, so
every Hypnotoad worker and every node counts in the same bucket and the
increment is atomic. The row also counts how many requests went over the
limit (C<blocked_count>) and records when the bucket expires.

The actor is never stored in clear: the bucket holds the SHA-256 of the
scope and the actor id. Windows are aligned on multiples of the window
length in epoch seconds.

=head1 SUBROUTINES/METHODS

=head2 new

Mojo::Base constructor. C<schema> is required: its function layer
(C<functions>) makes the calls. C<clock> defaults to
L<GPForum::Service::Clock>.

Each operation is written once, as its promise method, with an optional
query context last (ADR 0177); C<check> and C<snapshot> are its blocking
twins.

=head2 check_p

Takes a hash reference with C<scope>, C<action>, C<actor_id> (an empty
string when absent), and optional C<limit> and C<window_seconds> (both 60
when absent or zero), and an optional query context. Counts one request and
resolves with a hash reference with
C<ok> (1 while the count is within the limit, 0 above it), C<key>
(scope, actor hash, action and window start joined by colons), C<limit>,
C<remaining> (never below 0), C<reset_at_epoch>, C<< store => 'postgresql' >>,
C<window_seconds>, C<observed_count>, C<< mitigation_hint => 'slow_down' >>
and C<actor_hash>. A refused request is still counted.

=head2 snapshot_p

Resolves with C<< { buckets => $count, store => 'postgresql', status => 'ok' } >>,
where C<$count> is the number of buckets that have not expired yet.

=head1 DIAGNOSTICS

Database errors propagate; L<GPForum::Service::Operations::RateLimiter>
catches them and applies its degradation policy. Without the function layer
the store throws L<GPForum::X::Unavailable>.

=head1 CONFIGURATION AND ENVIRONMENT

None. Limits and windows come from the caller.

=head1 DEPENDENCIES

L<GPForum::Service::Clock>, L<Digest::SHA>, L<POSIX>.

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
