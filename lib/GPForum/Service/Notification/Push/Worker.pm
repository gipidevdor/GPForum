# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Notification::Push::Worker;

use Mojo::Base 'GPForum::Base', -signatures;
use v5.40;
use Const::Fast;
use GPForum::X::Config;
use Time::HiRes    qw(time);
use Crypt::URandom qw(urandom);
use List::Util     qw(max min);
use Mojo::Date;
use Mojo::JSON qw(encode_json);
use Mojo::Promise;
use GPForum::Infrastructure::Id;
use GPForum::Service::Forum::Readability;
use GPForum::Service::Forum::ViewerResolver;
use GPForum::Service::Notification::Push::Transport;

our $VERSION = '0.001';
const my $CLEANUP_SECONDS   => 60;
const my $HTTP_RATE_LIMITED => 429;
const my $HTTP_UNAVAILABLE  => 503;
const my $HTTP_UNAUTHORIZED => 401;
const my $HTTP_FORBIDDEN    => 403;
const my $HTTP_NOT_FOUND    => 404;
const my $HTTP_GONE         => 410;
const my $HTTP_SERVER_ERROR => 500;
const my $MAX_ATTEMPTS      => 8;
const my $BACKOFF_BASE      => 5;
const my $JITTER_BYTES      => 4;
const my $MAX_CONCURRENCY   => 64;
const my $CLEANUP_BATCH     => 500;
const my $MAX_PER_PROVIDER  => 16;
const my $MAX_COOLDOWNS     => 128;
const my $MAX_BACKOFF       => 900;
const my $MAX_RETRY_AFTER   => 86_400;
const my %ACCEPTED          => map { $_ => 1 } qw(200 201 202 204);
__PACKAGE__->requires('store');
has transport => sub ($self) {
    return GPForum::Service::Notification::Push::Transport->new(
        endpoint     => $self->store->endpoint,
        per_provider =>
          min( $MAX_PER_PROVIDER, $self->store->config->push_per_provider )
    );
};
has storage        => sub ($self) { return $self->store->secrets->storage; };
has keys           => sub ($self) { return $self->store->secrets->private; };
has cooldown       => sub { return {}; };
has prepared       => sub { return []; };
has outcomes       => sub { return []; };
has checked_key_id => q{};
has cleanup_at     => 0;
has stats          => sub { return {}; };
has readability    => sub ($self) {
    return GPForum::Service::Forum::Readability->new(
        schema => $self->store->schema );
};
has viewers => sub ($self) {
    return GPForum::Service::Forum::ViewerResolver->new(
        schema => $self->store->schema );
};

sub dispatch_p ($self) {
    return Mojo::Promise->resolve( { disabled => 1 } )
      if !$self->store->enabled;
    $self->_check_configuration;
    if ( $self->cleanup_at <= time ) {
        my $cleaned =
          $self->store->functions->row( 'notification_push_cleanup', {} );
        $self->cleanup_at(
            time + (
                ( $cleaned->{removed} // 0 ) >= $CLEANUP_BATCH
                ? 0
                : $CLEANUP_SECONDS
            )
        );
    }
    $self->outcomes( [] );
    $self->prepared( [] );
    my $lease = GPForum::Infrastructure::Id->new->uuid;
    my $jobs  = $self->store->functions->rows(
        'notification_push_claim',
        {
            lease_id => $lease,
            limit    =>
              min( $MAX_CONCURRENCY, $self->store->config->push_concurrency ),
            per_provider =>
              min( $MAX_PER_PROVIDER, $self->store->config->push_per_provider )
        }
    );
    $self->stats(
        {
            selected  => scalar @{$jobs},
            accepted  => 0,
            retry     => 0,
            failed    => 0,
            expired   => 0,
            cancelled => 0,
            lost      => 0
        }
    );
    my @pending = map { $self->_prepare_p( $_, $lease ) } @{$jobs};
    return Mojo::Promise->resolve( { %{ $self->stats } } ) if !@pending;
    return Mojo::Promise->all(@pending)->then(
        sub {
            return $self->_send_batch_p($lease);

        }
    )->then(
        sub {
            if ( @{ $self->outcomes } ) {
                my $results = $self->store->functions->rows(
                    'notification_push_finish_batch',
                    { outcomes => $self->outcomes }
                );
                for my $result ( @{$results} ) {
                    $self->stats->{
                          $result->{changed}
                        ? $result->{outcome}
                        : 'lost'
                    }++;
                }
            }
            return { %{ $self->stats } };
        }
    );
}

sub _check_configuration ($self) {
    my $public = $self->store->public_config;
    $self->storage;
    my $active = $public->{key_id};
    if ( !exists $self->keys->{keys}{$active} ) {
        $self->keys( $self->store->secrets->private );
    }
    my $private = $self->keys->{keys}{$active};
    if ( !defined $private ) {
        GPForum::X::Config->throw(
            message => 'Push active signing key unavailable' );
    }
    if ( $self->checked_key_id ne $active ) {
        $self->store->crypto->validate_signing_key( $active, $private );
        $self->checked_key_id($active);
    }
    return;
}

sub _send_batch_p ( $self, $lease ) {

    # Resolve DNS first, then refresh all leases, consent and read
    # permissions in one statement immediately before network sends.
    my $fresh =
      @{ $self->prepared }
      ? $self->store->functions->rows( 'notification_push_refresh',
        { lease_id => $lease } )
      : [];
    my %current = map { $_->{delivery_id} => $_ } @{$fresh};
    my @sending;
    for my $plan ( @{ $self->prepared } ) {
        my $job = $current{ $plan->{job}{delivery_id} };
        if ( !$job || !$self->_eligible($job) ) {
            $self->_finish( $plan->{job}, $lease, 'cancelled', 0 );
            next;
        }
        $plan->{job} = $job;
        push @sending, $self->_job_p( $plan, $lease );
    }
    return @sending
      ? Mojo::Promise->all(@sending)
      : Mojo::Promise->resolve;
}

sub _prepare_p ( $self, $job, $lease ) {
    my ( $receiver, $promise );
    try {
        $receiver =
          $self->store->crypto->unseal( $self->storage,
            "subscription:$job->{user_id}:$job->{endpoint_hash}",
            $job->{envelope} );
        $self->store->endpoint->parse( $receiver->{endpoint} );
        $promise = $self->transport->prepare_p( $receiver->{endpoint} );
    }
    catch ($error) {
        $self->_finish( $job, $lease, 'failed', 0 );
        return Mojo::Promise->resolve;
    };
    return $promise->then(
        sub ($transport) {
            push @{ $self->prepared },
              { job => $job, receiver => $receiver, transport => $transport };
            return;
        }
    )->catch(
        sub {
            $self->_finish( $job, $lease, 'retry',
                $self->_backoff( $job->{attempts} ) );
            return;
        }
    );
}

sub _job_p ( $self, $plan, $lease ) {
    my $job = $plan->{job};
    my $promise;
    try {
        my $receiver = $plan->{receiver};
        my $url      = $self->store->endpoint->parse( $receiver->{endpoint} );
        my $origin   = 'https://' . lc $url->host;
        my $cooldown = $self->cooldown->{$origin} // 0;
        if ( $cooldown > time ) {
            $self->_finish( $job, $lease, 'retry', $cooldown - time );
            return Mojo::Promise->resolve;
        }
        my $private = $self->keys->{keys}{ $job->{key_id} };
        if ( !defined $private ) {
            $self->keys( $self->store->secrets->private );
            $private = $self->keys->{keys}{ $job->{key_id} };
        }
        if ( !defined $private ) { die "Push signing key unavailable\n"; }
        my $authorization =
          $self->store->crypto->authorization( $origin, $job->{key_id},
            $private, $self->store->config->push_contact );
        my $payload =
          $job->{kind} eq 'activation'
          ? $self->store->crypto->unseal( $self->storage,
            "activation:$job->{subscription_id}",
            $job->{activation} )
          : { type => 'alert' };
        my $body = $self->store->crypto->encrypt( $receiver->{keys},
            encode_json($payload) );
        $promise = $self->transport->send_prepared_p(
            $plan->{transport},
            {
                Authorization => $authorization,
                TTL           => max( 0, $job->{remaining} ),
                Urgency       => 'normal',
                Topic => $job->{kind} eq 'activation' ? 'activation' : 'inbox',
            },
            $body,
            time + $job->{remaining}
        )->then(
            sub ($response) {
                my ( $outcome, $delay ) =
                  $self->outcome( $response, $job->{attempts} );
                if (   ( $response->code // 0 ) == $HTTP_RATE_LIMITED
                    || ( $response->code // 0 ) == $HTTP_UNAVAILABLE )
                {
                    $self->_pause_origin( $origin, time + $delay );
                }

                # Invalid VAPID is an operator fault: stop this origin briefly,
                # retain the device, and expose a failed metric, not retry spam.
                if (   ( $response->code // 0 ) == $HTTP_UNAUTHORIZED
                    || ( $response->code // 0 ) == $HTTP_FORBIDDEN )
                {
                    $self->_pause_origin( $origin, time + $MAX_BACKOFF );
                }
                $self->_finish( $job, $lease, $outcome, $delay );
                return;
            }
        );
    }
    catch ($error) {
        $self->_finish( $job, $lease, 'failed', 0 );
        return Mojo::Promise->resolve;
    };
    return $promise->catch(
        sub {
            $self->_finish( $job, $lease, 'retry',
                $self->_backoff( $job->{attempts} ) );
            return;
        }
    );
}

sub _pause_origin ( $self, $origin, $until ) {
    my $pauses = $self->cooldown;
    for my $host ( keys %{$pauses} ) {
        if ( $pauses->{$host} <= time ) { delete $pauses->{$host}; }
    }
    if ( !exists $pauses->{$origin} && keys %{$pauses} >= $MAX_COOLDOWNS ) {
        my ($earliest) =
          sort { $pauses->{$a} <=> $pauses->{$b} } keys %{$pauses};
        delete $pauses->{$earliest};
    }
    $pauses->{$origin} = max( $pauses->{$origin} // 0, $until );
    return;
}

sub _eligible ( $self, $job ) {
    return 1 if $job->{kind} eq 'activation';
    return 0
      if !$job->{allowed}
      || !$job->{viewer}
      || $job->{viewer}{status} ne 'active'
      || $job->{viewer}{suspended};

    # Private resources use the same policy as the inbox. Both the source
    # placement and the resolved viewer came in the claim's single query.
    return 1
      if !$job->{placement}
      && $job->{allowed}
      && ( $job->{source_type} // q{} ) eq 'message';
    my $viewer =
      $self->viewers->viewer_from_row( $job->{user_id}, $job->{viewer} );
    return $self->readability->may_read( $viewer, $job->{placement} );
}

sub outcome ( $self, $response, $attempts ) {
    my $code = $response->code // 0;
    return ( 'accepted', 0 ) if exists $ACCEPTED{$code};
    return ( 'expired',  0 ) if $code == $HTTP_NOT_FOUND || $code == $HTTP_GONE;
    return ( 'failed',   0 )
      if $code && $code != $HTTP_RATE_LIMITED && $code < $HTTP_SERVER_ERROR;
    my $retry = $response->headers->header('Retry-After');
    my $after =
        defined $retry && $retry =~ /\A[[:digit:]]{1,8}\z/amsx ? 0 + $retry
      : defined $retry ? ( Mojo::Date->new($retry)->epoch // time ) - time
      :                  0;
    return ( 'retry',
        min( $MAX_RETRY_AFTER, max( $self->_backoff($attempts), $after ) ) );
}

sub _backoff ( $, $attempts ) {
    my $base =
      min( $MAX_BACKOFF, $BACKOFF_BASE * 2**min( $attempts, $MAX_ATTEMPTS ) );
    return
      int( $base / 2 ) +
      unpack( 'N', urandom($JITTER_BYTES) ) % ( int( $base / 2 ) + 1 );
}

sub _finish ( $self, $job, $lease, $outcome, $delay ) {
    push @{ $self->outcomes },
      {
        delivery_id => $job->{delivery_id},
        lease_id    => $lease,
        outcome     => $outcome,
        retry_after => int($delay),
      };
    return;
}

1;

__END__

=head1 NAME

GPForum::Service::Notification::Push::Worker - Dispatch the independent transactional Push outbox in bounded asynchronous batches.

=head1 DESCRIPTION

Dispatch the independent transactional Push outbox in bounded asynchronous batches. See docs/ops/web-push.md for deployment and lifecycle guarantees.

=head1 SUBROUTINES/METHODS

=head2 dispatch_p

Claim up to eight jobs, at most two per provider, send outside database transactions, and commit outcomes in one batch. Returns aggregate counters only.

=head2 outcome

Classify provider acceptance, expired subscriptions, permanent errors and transient retries. Honor bounded Retry-After without extending delivery expiry.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $service = GPForum::Service::Notification::Push::Worker->new(store => $store);

=head1 DIAGNOSTICS

Invalid input fails closed. Transport failures are bounded and reported without receiver capability URLs or key material.

=head1 CONFIGURATION AND ENVIRONMENT

Dependencies and validated settings are supplied by the composition layer. See docs/ops/web-push.md.

=head1 DEPENDENCIES

CryptX supplies cryptographic primitives; Mojolicious supplies asynchronous HTTPS; versioned PostgreSQL API functions own persistence.

=head1 INCOMPATIBILITIES

Private key files require a persistent service account and restrictive filesystem permissions.

=head1 BUGS AND LIMITATIONS

A provider acceptance does not guarantee display. An already accepted notification cannot be recalled.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. BSD-3-Clause.

=cut
