# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Bootstrap::Async;
use Mojo::Base -strict, -async_await;
use v5.40;
use GPForum::Bootstrap::Identity;
use GPForum::Service::Forum::Viewer;
use GPForum::Service::Forum::ViewerResolver;
use GPForum::Web::Guard;
use GPForum::Web::HealthPayload;
use GPForum::Infrastructure::Id;
use GPForum::Infrastructure::Text qw(has_text);
use File::Find                    ();
use File::Spec;

our $VERSION = '0.001';

sub register ( $class, $application ) {
    my $static = _static_paths($application);
    $application->hook(
        around_dispatch => sub ( $next, $controller ) {
            $controller->gp_begin_request;
            my $path = $controller->req->url->path;
            if (   $static->{ $path->to_string }
                && $controller->req->method =~ /\A(?:GET|HEAD)\z/ )
            {
                $controller->stash(
                    'gp.session_checked'         => 1,
                    'gp.effective_configuration' => $controller->gp_base_config,
                );
                return $controller->within_request($next);
            }
            if ( $path->to_string eq '/health/live' ) {

                # A public liveness probe never validates a durable session.
                # Response hooks and request observation still run normally.
                if ( _is_live_request($controller) ) {
                    $controller->stash( 'gp.session_checked' => 1 );
                }
                return $controller->within_request($next);
            }
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
    $application->hook(
        before_dispatch => sub ($controller) {
            return if !_is_live_request($controller);
            return if $controller->stash('mojo.rendered');

            # Answer before the static dispatcher probes the filesystem and
            # the router builds an action chain for this stateless endpoint.
            $controller->match->endpoint(
                $application->routes->lookup('health_live') );
            return $controller->render(
                json => GPForum::Web::HealthPayload->live(
                    clock => $controller->gp_clock
                )
            );
        }
    );
    return;
}

sub _is_live_request ($controller) {
    return 0 if $controller->req->url->path->to_string ne '/health/live';
    my $method = $controller->req->method;
    return $method eq 'GET' || $method eq 'HEAD';
}

async sub prepare_p ( $class, $controller ) {
    my $url  = $controller->req->url;
    my $path = $url->path->to_string;
    return if $path eq '/health/live';
    my $prepared =
      $path ne '/metrics'
      ? await $class->_prepare_context_p( $controller, $path )
      : 0;
    if ( $path ne '/metrics' && !$prepared ) {
        my $configuration = $controller->gp_configuration;
        my $state         = await $controller->call_p( $configuration, 'load' );
        $configuration->state($state);
        $controller->stash(
            'gp.effective_configuration' => $configuration->effective_config );
    }
    elsif ( $path eq '/metrics' ) {
        $controller->stash(
            'gp.effective_configuration' => $controller->gp_base_config );
    }

    await $controller->await_p(
        $class->_prepare_listener_p( $controller, $path ) );
    if ( !$prepared ) {
        await $controller->await_p(
            GPForum::Bootstrap::Identity->validate_session_p($controller) );
    }
    return if $controller->stash('mojo.finished');
    my $user_id = $controller->session('user_id');
    if (   !$prepared
        && defined $user_id
        && length $user_id
        && $path !~ m{\A/u/[^/]+/?\z}msx )
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

async sub _prepare_context_p ( $, $controller, $path ) {
    my $configuration = $controller->gp_configuration;
    return 0
      if !$configuration->can('request_context_p')
      || !$configuration->functions;
    my $identity = $controller->gp_identity_store;
    return 0 if !$identity->can('functions') || !$identity->functions;
    my $cookies = GPForum::Bootstrap::Identity->prepare_session($controller);
    my $user    = $controller->session('user_id');
    my $session =
        $cookies->has_server_session($controller)
      ? $controller->session('session_id')
      : undef;
    return 0 if defined $user && !GPForum::Infrastructure::Id->is_uuid($user);
    return 0
      if defined $session && !GPForum::Infrastructure::Id->is_uuid($session);
    my $token   = $controller->session('session_token');
    my $resolve = $path !~ m{\A/u/[^/]+/?\z}msx;
    my $row;
    try {
        $row = await $controller->call_p(
            $configuration,
            'request_context',
            {
                session_id => $session,
                user_id    => $user,
                token_hash => has_text($token)
                ? $identity->session_tokens->hash_token($token)
                : undef,
                now                    => $identity->clock->now_iso8601,
                touch_interval_seconds =>
                  $identity->session_touch_interval_seconds // 300,
                resolve_viewer => $resolve ? 1 : 0,
            }
        );
    }
    catch ($error) {

        # Installation before migration and degraded configuration retain the
        # established fallback. Durable session failures still fail closed in
        # validate_session_p; no cache is admitted without a fresh epoch.
        return 0;
    };
    GPForum::Bootstrap::Identity->accept_session_validation( $controller,
        $row->{validation} );
    if ( $resolve && has_text( $controller->session('user_id') ) ) {
        my $resolver = GPForum::Service::Forum::ViewerResolver->new(
            schema => $controller->gp_schema,
            logger => $controller->log
        );
        $controller->stash( 'gp.forum_viewer' =>
              $resolver->viewer_from_row( $user, $row->{viewer} ) );
    }
    $controller->stash(
        'gp.effective_configuration' => $configuration->effective_config );
    return 1;
}

# A release's bundled public assets are fixed at startup. Only existing
# static filenames enter this set; route names and user supplied files do not.
sub _static_paths ($application) {
    my %paths;
    for my $directory ( @{ $application->static->paths } ) {
        next if !-d $directory;
        File::Find::find(
            {
                no_chdir => 1,
                wanted   => sub {
                    return if !-f $File::Find::name;
                    my $relative =
                      File::Spec->abs2rel( $File::Find::name, $directory );
                    return
                      if $relative =~ m{(?:\A|/)\.}
                      || $relative !~
/\.(?:js|css|svg|png|jpe?g|webp|gif|ico|woff2?|map|txt)\z/;
                    $paths{ '/' . $relative } = 1;
                }
            },
            "$directory"
        );
    }
    return \%paths;
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
GET and HEAD liveness responses render from the normal C<before_dispatch>
hook, before static filesystem lookup and route action dispatch. They never
validate a durable session; request observers and response hooks still run.

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
