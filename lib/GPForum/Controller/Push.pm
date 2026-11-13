# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Controller::Push;

use Mojo::Base 'GPForum::Controller::Notifications::Base', -async_await;
use v5.40;
use Const::Fast;
use Mojo::JSON qw(decode_json);
use GPForum::Web::Access;
use GPForum::X::Argument;

our $VERSION = '0.001';
const my $HTTP_UNAVAILABLE  => 503;
const my $HTTP_INVALID      => 400;
const my $HTTP_FAILURE      => 500;
const my $ACTIVATION_LIMIT  => 10;
const my $ACTIVATION_WINDOW => 3600;
const my $MAX_BODY          => 8192;
const my $MAX_DOCUMENT      => 6144;
const my %HTTP_STATUS => (
    pending      => 202,
    active       => 200,
    revoked      => 200,
    unauthorized => 401,
    invalid      => 400,
    conflict     => 409,
    limit        => 429,
);

async sub configuration ($self) {
    $self->res->headers->cache_control('private, no-store');
    my $user = $self->member_user_id or return;
    return $self->_rate_limited
      if !(
        await $self->await_p(
            $self->_allowed( $user, 'notification.push.read' ) ) );
    my $configuration;
    try {
        $configuration = $self->gp_push_store->public_config;
        $configuration->{devices} =
          $configuration->{enabled}
          ? ( await $self->call_p( $self->gp_push_store, 'devices', $user ) )
          : [];
        $configuration->{csrf_token} = $self->csrf_token;
    }
    catch ($error) { return $self->system_failure; };
    return $self->render( json => $configuration );
}

async sub register ($self) {
    return ( await $self->await_p( $self->_write('register') ) );
}
async sub confirm ($self) {
    return ( await $self->await_p( $self->_write('confirm') ) );
}
async sub revoke ($self) {
    return ( await $self->await_p( $self->_write('revoke') ) );
}

async sub worker ($self) {
    $self->res->headers->cache_control('private, no-cache');
    $self->res->headers->header( 'Service-Worker-Allowed' => '/push/' );
    $self->res->headers->content_security_policy(
        q{default-src 'none'; script-src 'self'; connect-src 'self'});
    return $self->file_p( $self->app->home->rel_file('assets/push-worker.js') );
}

async sub _write ( $self, $operation ) {
    $self->res->headers->cache_control('private, no-store');
    return $self->_csrf_failure
      if !GPForum::Web::Access->new->same_origin($self);
    my $user = (
        await $self->await_p(
            $self->write_user_id("notification.push.$operation")
        )
    ) or return;
    return $self->render(
        json   => { status => 'disabled' },
        status => $HTTP_UNAVAILABLE
    ) if !$self->gp_push_store->enabled && $operation ne 'revoke';
    if ( $operation eq 'register' ) {
        my $decision = (
            await $self->call_p(
                $self->gp_rate_limiter,
                'check',
                {
                    action         => 'notification.push.register',
                    actor_id       => $user,
                    scope          => 'push_activation',
                    limit          => $ACTIVATION_LIMIT,
                    window_seconds => $ACTIVATION_WINDOW,
                }
            )
        );
        return $self->_rate_limited if !$decision->{ok};
    }
    my $result;
    try {
        my $input = $self->_input;
        $result =
          $operation eq 'revoke'
          ? (
            await $self->call_p(
                $self->gp_push_store, 'revoke',
                $user,                $input->{subscription_id}
            )
          )
          : (
            await $self->call_p(
                $self->gp_push_store,         $operation, $user,
                $self->session('session_id'), $input
            )
          );
    }
    catch ($error) {
        return $self->render(
            json   => { status => 'invalid' },
            status => $HTTP_INVALID
        ) if GPForum::X::Argument->caught($error);
        return $self->system_failure;
    };
    return $self->render(
        json   => $result,
        status => $HTTP_STATUS{ $result->{status} } // $HTTP_FAILURE
    );
}

sub _input ($self) {
    my $raw = $self->param('payload');
    if (   length( $self->req->body ) > $MAX_BODY
        || !defined $raw
        || length($raw) > $MAX_DOCUMENT )
    {
        GPForum::X::Argument->throw( message => 'invalid Push request' );
    }
    my $input;
    try { $input = decode_json($raw); }
    catch ($parse_error) {
        GPForum::X::Argument->throw( message => 'invalid Push document' );
    };
    if ( ref $input ne 'HASH' ) {
        GPForum::X::Argument->throw( message => 'invalid Push request' );
    }
    return $input;
}

1;
