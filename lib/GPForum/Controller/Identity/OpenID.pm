# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Controller::Identity::OpenID;

use Mojo::Base 'GPForum::Controller::Identity', -async_await;
use v5.40;
use Const::Fast;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Service::Identity::OpenID;
our $VERSION = '0.001';
const my $HTTP_BAD         => 400;
const my $HTTP_UNAVAILABLE => 503;

async sub settings ($self) {
    return $self->redirect_to('login') if !$self->current_user_id;
    my $linked = 0;
    try {
        my $functions =
          GPForum::Infrastructure::SqlFunction->for_schema( $self->gp_schema );
        my $row = await $self->call_p(
            $functions,
            'row',
            'identity_oidc_status',
            {
                actor  => $self->current_user_id,
                issuer => $self->gp_config->oidc_issuer,
            }
        );

        if ($row) { $linked = $row->{result}{linked}; }
    }
    catch ($error) { return $self->identity_unavailable; };
    $self->res->headers->cache_control('private, no-store');
    return $self->render(
        template => 'identity/openid',
        linked   => $linked,
        enabled  => $self->_provider->enabled
    );
}

async sub start ($self) {
    return
      if (
        await $self->await_p( $self->identity_post_guard('identity.login') ) );
    my $actor = $self->current_user_id;
    return $self->render(
        status => $HTTP_BAD,
        text   => $self->t('auth.oidc_failed')
    ) if $actor;
    return ( await $self->await_p( $self->_begin( {} ) ) );
}

async sub link_identity ($self) {
    return
      if (
        await $self->await_p( $self->identity_post_guard('identity.login') ) );
    my $actor = $self->current_user_id or return $self->redirect_to('login');
    return
      if !(
        await $self->await_p(
            $self->participating( $actor, 'identity.oidc.link' ) ) );
    return (
        await $self->await_p(
            $self->_begin(
                {
                    actor_user_id => $actor,
                    password      => $self->param('password'),
                    code          => $self->param('code')
                }
            )
        )
    );
}

sub _begin ( $self, $input ) {
    return $self->respond_p(
        $self->call_p( $self->_provider, 'begin', $input ),
        sub ($result) { return $self->_begin_result($result); },
        sub ($error) {
            return $self->render(
                status => $HTTP_UNAVAILABLE,
                text   => $self->t('auth.oidc_unavailable')
            );
        }
    );
}

sub _begin_result ( $self, $result ) {
    return $self->render(
        status => $HTTP_BAD,
        text   => $self->t('auth.oidc_failed')
    ) if $result->{status} ne 'redirect';
    $self->res->headers->cache_control('private, no-store');
    $self->session( oidc_flow => $result->{flow} );
    return $self->redirect_to( $result->{url} );
}

sub callback ($self) {
    $self->res->headers->cache_control('private, no-store');
    my $flow     = delete $self->session->{oidc_flow};
    my $provider = $self->_provider;
    return $self->respond_p(
        $provider->complete_p(
            {
                flow            => $flow,
                code            => $self->param('code'),
                state           => $self->param('state'),
                actor_user_id   => $self->current_user_id,
                request_address => $self->request_address,
                user_agent      => $self->req->headers->user_agent // 'unknown'
            }
        ),
        async sub ($answer) {
            return ( await $self->await_p( $self->_callback_answer($answer) ) );
        },
        sub ($error) {
            return $self->render(
                status => $HTTP_UNAVAILABLE,
                text   => $self->t('auth.oidc_unavailable')
            );
        }
    );
}

async sub _callback_answer ( $self, $answer ) {
    return (
        await $self->await_p(
            $self->_accept_login(
                $answer, $self->url_for('home')->path->to_string
            )
        )
    ) if $answer->{ok};
    return $self->_ask_second_step($answer)
      if $answer->{status} eq 'second_factor';
    if ( $answer->{status} eq 'linked' ) {
        $self->flash( success => $self->t('auth.oidc_linked') );
        return $self->redirect_to('settings_openid');
    }
    return $self->render(
        status => $HTTP_BAD,
        text   => $self->t('auth.oidc_failed')
    );
}

async sub remove_link ($self) {
    return
      if (
        await $self->await_p( $self->identity_post_guard('identity.login') ) );
    my $actor = $self->current_user_id or return $self->redirect_to('login');
    return $self->respond_p(
        $self->call_p(
            $self->_provider,
            'remove_link',
            {
                actor_user_id => $actor,
                password      => $self->param('password'),
                code          => $self->param('code'),
                session_id    => $self->session('session_id')
            }
        ),
        sub ($answer) { return $self->_removed_link($answer); },
        sub ($error) { return $self->identity_unavailable; }
    );
}

sub _removed_link ( $self, $answer ) {
    return $self->render(
        status => $HTTP_BAD,
        text   => $self->t('auth.oidc_failed')
    ) if $answer->{status} ne 'unlinked';
    $self->flash( success => $self->t('auth.oidc_unlinked') );
    return $self->redirect_to('settings_openid');
}

sub _provider ($self) {
    return GPForum::Service::Identity::OpenID->new(
        query_context    => $self->stash('gp_db_query_stats_token'),
        schema           => $self->gp_schema,
        policy_available => $self->gp_configuration->state->{available} ? 1 : 0,
        config           => $self->gp_config,
        password         => $self->gp_password,
        second_factor    => $self->gp_second_factor
    );
}

1;

__END__

=head1 NAME

GPForum::Controller::Identity::OpenID - Offer opt-in external login without automatic account creation or merging.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $service = GPForum::Controller::Identity::OpenID->new;

=head1 DESCRIPTION

Offer opt-in external login without automatic account creation or merging. Core owns configuration, authorization and presentation.

=head1 SUBROUTINES/METHODS

=head2 settings

Shows the member their explicit external binding and local recovery policy.

=head2 start

CSRF- and rate-protects the start of an optional external login.

=head2 link_identity

Requires a current local session, password and configured MFA before linking.

=head2 callback

Consumes browser state, handles verified claims and reuses the normal local MFA/session response.

=head2 remove_link

Checks a fresh local proof before unlinking and revoking other sessions.

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
