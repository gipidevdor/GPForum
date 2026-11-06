# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Bootstrap::Async;
use Mojo::Base -strict, -async_await;
use v5.40;
use GPForum::Bootstrap::Identity;
use GPForum::Service::Forum::Viewer;
use GPForum::Service::Forum::ViewerResolver;
use GPForum::Web::Guard;

our $VERSION = '0.001';

sub register ( $class, $application ) {
    $application->hook(
        around_dispatch => sub ( $next, $controller ) {
            $controller->gp_begin_request;
            return $controller->within_request($next)
              if $controller->req->url->path->to_string eq '/health/live';
            $controller->render_later;
            $class->prepare_p($controller)->then(
                sub {
                    return if $controller->stash('mojo.finished');
                    delete $controller->stash->{'mojo.rendered'};
                    return $controller->within_request($next);
                }
            )->catch(
                sub ($error) {
                    return if $controller->stash('mojo.finished');
                    $controller->log->error(
                        "request preparation failed: $error");
                    return GPForum::Web::Guard->new->service_unavailable(
                        $controller);
                }
            );
            return;
        }
    );
    return;
}

async sub prepare_p ( $class, $controller ) {
    my $url  = $controller->req->url;
    my $path = $url->path->to_string;
    return if $path eq '/health/live';
    if ( $path ne '/metrics' ) {
        my $configuration = $controller->gp_configuration;
        my $state         = await $controller->call_p( $configuration, 'load' );
        $configuration->state($state);
        $controller->stash(
            'gp.effective_configuration' => $configuration->effective_config );
    }
    else {
        $controller->stash(
            'gp.effective_configuration' => $controller->gp_base_config );
    }

    await $controller->await_p(
        $class->_prepare_listener_p( $controller, $path ) );
    await $controller->await_p(
        GPForum::Bootstrap::Identity->validate_session_p($controller) );
    return if $controller->stash('mojo.finished');
    my $user_id = $controller->session('user_id');
    if ( defined $user_id && length $user_id && $path !~ m{\A/u/[^/]+/?\z}msx )
    {
        my $resolver = GPForum::Service::Forum::ViewerResolver->new(
            schema => $controller->gp_schema,
            logger => $controller->log
        );
        my $viewer =
          await $controller->call_p( $resolver, 'resolve', $user_id );
        $controller->stash( 'gp.forum_viewer' => $viewer );
    }
    if ( ( $controller->req->headers->accept // q{} ) !~ /json/msx
        && $path !~ m{\A/(?:health|metrics|realtime)(?:/|\z)}msx )
    {
        my $announcements = [];
        try {
            $announcements =
              await $controller->call_p( $controller->gp_announcement_store,
                'active_announcements', undef );
        }
        catch ($error) {
            $controller->log->warn("announcements degraded: $error");
        };
        $controller->stash( 'gp.announcements' => $announcements );
    }
    return;
}

async sub _prepare_listener_p( $class, $controller, $path ) {

    # Establish LISTEN before a cache can admit a local hit. The helper also
    # constructs the registered cache channels used by this process.
    my $cache = $controller->gp_local_cache;
    if ( $path ne '/metrics' ) {
        if ( $cache->can('bus') && $cache->bus ) {
            await $controller->await_p(
                $controller->gp_pg_notifications->listen_to_p(
                    $cache->bus->channel
                )
            );
        }
        else {
            await $controller->await_p(
                $controller->gp_pg_notifications->ensure_p );
        }
    }
    if (   $path ne '/metrics'
        && !$controller->stash('gpforum.warming')
        && $controller->gp_config->realtime_listener_enabled )
    {
        await $controller->await_p(
            $controller->gp_realtime_listener_supervisor->start_p );
    }
    return;
}

1;

__END__

=head1 NAME

GPForum::Bootstrap::Async - Resolve shared HTTP state before synchronous framework dispatch.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    GPForum::Bootstrap::Async->register($app);

=head1 DESCRIPTION

Loads durable configuration, validates server sessions and resolves the viewer
with native promises before dispatching a route. Rendering stays deferred while
the request waits; liveness and metrics avoid the configuration query.

=head1 SUBROUTINES/METHODS

=head2 register

Installs the request preparation boundary after logging is configured.

=head2 prepare_p

Returns a promise once shared request state is available or the request is refused.

=head1 DIAGNOSTICS

Unavailable state fails closed with a deferred 503 response.

=head1 CONFIGURATION AND ENVIRONMENT

Always active without operator settings.

=head1 DEPENDENCIES

Mojolicious, Future::AsyncAwait and the identity/configuration services.

=head1 INCOMPATIBILITIES

Commands retain their synchronous service interfaces.

=head1 BUGS AND LIMITATIONS

Route-specific service operations use the controller's asynchronous call boundary.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. BSD-3-Clause.

=cut
