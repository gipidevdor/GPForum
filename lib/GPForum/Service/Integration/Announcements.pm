# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Integration::Announcements;

use Mojo::Base 'GPForum::Base', -signatures;
use v5.40;
use Const::Fast;
use Digest::SHA qw(sha256_hex);
use POSIX       qw(ceil);
use JSON::MaybeXS;
use GPForum::Infrastructure::Id;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Infrastructure::EventRecorder;
use GPForum::Service::Integration::HttpClient;
use GPForum::Service::Integration::Readiness;
use GPForum::X::Config;
use GPForum::X::Argument;
use GPForum::X::Unavailable;
use GPForum::X::RateLimited;
our $VERSION = '0.001';
const my $REASON_LENGTH         => 500;
const my $DEFAULT_RETRY_SECONDS => 60;
const my $HTTP_CLIENT_ERROR     => 400;
const my $HTTP_RATE_LIMITED     => 429;
const my $HTTP_SERVER_ERROR     => 500;
const my $SUPPRESS_EMBEDS       => 4;
const my $MAX_RETRY_SECONDS     => 86_400;
const my $TITLE_LIMIT           => 256;
has policy_available => 0;
__PACKAGE__->requires(qw(schema config));
has client    => sub { return GPForum::Service::Integration::HttpClient->new; };
has functions => sub ($self) {
    return GPForum::Infrastructure::SqlFunction->for_schema( $self->schema );
};
has recorder => sub ($self) {
    return GPForum::Infrastructure::EventRecorder->new(
        schema => $self->schema );
};

sub enabled ($self) {
    return 0 if !$self->policy_available;
    return
      @{ GPForum::Service::Integration::Readiness->missing( 'discord',
            $self->config )
      } ? 0 : 1;
}

sub _require_policy ($self) {
    if ( !$self->policy_available ) {
        GPForum::X::Unavailable->throw(
            message => 'integration policy unavailable' );
    }
    return;
}

sub _target ($self) {
    my $url        = $self->client->https_url( $self->config->discord_webhook );
    my $webhook_id = qr{[[:digit:]]{15,24}}amsx;
    my $token_part = qr{[[:alnum:]_-]{40,100}}amsx;
    my ( $id, $token ) = $url->path->to_string =~
      m{\A /api/(?:v10/)?webhooks/($webhook_id)/($token_part) \z}amsx;
    if (   lc( $url->host ) ne 'discord.com'
        || length( $url->query->to_string )
        || !defined $id )
    {
        GPForum::X::Config->throw( message => 'invalid Discord webhook' );
    }
    return "https://discord.com/api/v10/webhooks/$id/$token?wait=true";
}

sub request ( $self, $actor, $thread ) {
    $self->_require_policy;
    if ( !$self->enabled ) {
        GPForum::X::Config->throw(
            message => 'Discord announcements are disabled' );
    }

    my $target = $self->_target;
    my $id     = GPForum::Infrastructure::Id->new->uuid;
    return $self->schema->txn_do(
        sub {
            my $row = $self->functions->row(
                'integration_announcement_request',
                {
                    actor        => $actor,
                    announcement => $id,
                    thread       => $thread,
                    target_hash  => sha256_hex($target)
                }
            )->{result};
            if ( $row->{status} eq 'queued' ) {
                $self->recorder->record_event(
                    event_type     => 'integration.discord.requested',
                    aggregate_type => 'thread',
                    aggregate_id   => $thread,
                    actor_id       => $actor,
                    schema_version => 1,
                    payload        => { announcement_id => $id }
                );
                $self->recorder->record_audit(
                    action      => 'integration.discord.requested',
                    actor_id    => $actor,
                    target_type => 'thread',
                    target_id   => $thread,
                    metadata    => { announcement_id => $id }
                );
            }
            return $row;
        }
    );
}

sub retry_checked ( $self, $input ) {
    $self->_require_policy;
    return { status => 'refused' }
      if ( $input->{checked} // q{} ) ne '1'
      || !length( $input->{reason} // q{} )
      || length( $input->{reason} ) > $REASON_LENGTH;
    return $self->schema->txn_do(
        sub {
            my $answer = $self->functions->row(
                'integration_announcement_retry',
                {
                    actor        => $input->{actor_user_id},
                    announcement => $input->{announcement_id},
                    target_hash  => sha256_hex( $self->_target )
                }
            )->{result};
            if ( $answer->{status} eq 'queued' ) {
                $self->recorder->record_event(
                    event_type     => 'integration.discord.requested',
                    aggregate_type => 'integration',
                    aggregate_id   => $input->{announcement_id},
                    actor_id       => $input->{actor_user_id},
                    schema_version => 1,
                    payload => { announcement_id => $input->{announcement_id} }
                );
                $self->recorder->record_audit(
                    action      => 'integration.discord.retried',
                    actor_id    => $input->{actor_user_id},
                    target_type => 'integration',
                    target_id   => $input->{announcement_id},
                    metadata    => { reason => $input->{reason} }
                );
            }
            return $answer;
        }
    );
}

sub deliver ( $self, $id ) {
    $self->_require_policy;
    if (
        length( $self->config->discord_webhook )
        && @{ GPForum::Service::Integration::Readiness->missing( 'discord',
                $self->config )
        }
      )
    {
        GPForum::X::Config->throw(
            message => 'Discord needs complete public HTTPS configuration' );
    }
    my $claim = $self->functions->row( 'integration_announcement_claim',
        { announcement => $id } );
    return { status => 'missing' } if !$claim;
    $claim = $claim->{result};
    return $claim if $claim->{status} ne 'sending';
    if ( !$self->enabled
        || sha256_hex( $self->_target ) ne $claim->{target_hash} )
    {
        return $self->_finish( $id, 'cancelled' );
    }

    # The sending marker already committed. Hold visibility rows only for this
    # bounded request: privacy changes serialize with the actual external send.
    my $answer = $self->schema->txn_do(
        sub {
            my $row = $self->functions->row( 'integration_announcement_payload',
                { announcement => $id } );
            return $self->_finish( $id, 'cancelled' ) if !$row;
            my $topic = $row->{result};
            return $self->_send( $id, $topic );
        }
    );
    if ( $answer->{status} eq 'rate_limited' ) {
        GPForum::X::RateLimited->throw(
            message     => 'Discord rate limited the announcement',
            retry_after => $answer->{retry_after}
        );
    }

    if ( $answer->{status} eq 'failed' ) {
        GPForum::X::Argument->throw(
            message => 'Discord announcement failed; inspect delivery status' );
    }
    return $answer;
}

sub _send ( $self, $id, $topic ) {
    my $base = $self->client->https_url( $self->config->public_base_url );
    my $path = $base->path->to_string;
    $path =~ s{/$}{}msx;
    $base->path( $path . '/t/' . $topic->{thread_id} );
    $base->query(undef);
    my $title = substr $topic->{title}, 0, $TITLE_LIMIT;
    $title =~ s/[\x00-\x1f\x7f`*_~|<>\x5b\x5d()\\]/ /gmsx;
    my $response;
    try {
        $response = $self->client->request(
            'POST',
            $self->_target,
            {
                json => {
                    content          => $title . "\n" . $base,
                    allowed_mentions => { parse => [] },
                    flags            => $SUPPRESS_EMBEDS,
                }
            }
        );
    }
    catch ($error) { return $self->_finish( $id, 'uncertain' ); };
    return $self->_response( $id, $response );
}

sub _response ( $self, $id, $response ) {
    my $code = $response->code;
    if ( $code == $HTTP_RATE_LIMITED ) {
        my $data  = $response->json // {};
        my $delay = $data->{retry_after}
          // $response->headers->header('Retry-After')
          // $DEFAULT_RETRY_SECONDS;

        if ( ref $delay
            || $delay !~ /\A [[:digit:]]+(?:[.][[:digit:]]+)? \z/amsx )
        {
            $delay = $DEFAULT_RETRY_SECONDS;
        }
        return $self->_finish( $id, 'failed' )
          if $delay > $MAX_RETRY_SECONDS;
        $self->_finish( $id, 'queued' );
        return {
            status      => 'rate_limited',
            retry_after => ceil($delay) || 1
        };
    }
    return $self->_finish( $id, 'failed' )
      if $code >= $HTTP_CLIENT_ERROR && $code < $HTTP_SERVER_ERROR;
    my $data = $response->json;
    return $self->_finish( $id, 'uncertain' )
      if !$response->is_success
      || ref $data ne 'HASH'
      || ( $data->{id} // q{} ) !~ /\A [[:digit:]]{1,24} \z/amsx;
    return $self->_finish( $id, 'sent', $data->{id} );
}

sub _finish ( $self, $id, $status, $remote = q{} ) {
    $self->functions->row( 'integration_announcement_finish',
        { announcement => $id, status => $status, remote_id => $remote } );
    return { status => $status };
}

1;

__END__

=head1 NAME

GPForum::Service::Integration::Announcements - Queue and deliver explicitly selected public topics to Discord.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $service = GPForum::Service::Integration::Announcements->new;

=head1 DESCRIPTION

Queue and deliver explicitly selected public topics to Discord. Core owns configuration, authorization and presentation.

=head1 SUBROUTINES/METHODS

=head2 enabled

True only when an administrator configured a Discord webhook.

=head2 request

Authorizes and queues one deduplicated topic/target announcement with its audit entry.

=head2 retry_checked

Queues a retry only after an administrator explicitly confirms remote inspection and supplies an audited reason.

=head2 deliver

Checks the target and current public visibility, disables mentions and retries only definite rate-limit refusals. Ambiguous sends require manual inspection.

=head1 DIAGNOSTICS

Invalid configuration and transport failures raise typed exceptions.

=head1 CONFIGURATION AND ENVIRONMENT

The composition layer supplies validated settings and dependencies.

=head1 DEPENDENCIES

The Good Phorum runtime and the modules named above.

=head1 INCOMPATIBILITIES

Network capabilities are independent of the frozen local Plugin API v1.

=head1 BUGS AND LIMITATIONS

External operations depend on the configured provider and its availability.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. BSD-3-Clause.

=cut
