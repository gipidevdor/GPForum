# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Controller::Admin::Plugins;

use Const::Fast;
use Mojo::Base 'GPForum::Controller::Admin::Base', -signatures;
use v5.40;
use GPForum::Service::Forum::BodyRenderer;
use GPForum::ViewModel::Admin::IntegrationOverview;

our $VERSION = '0.001';
const my $OK          => 200;
const my $INVALID     => 422;
const my $CONFLICT    => 409;
const my $FORBIDDEN   => 403;
const my $UNAVAILABLE => 503;
const my $MATH_LIMIT  => 4_096;

sub show ($self) {
    return if !$self->authorized_user_id( $self->admin_access->view_action );
    return $self->_page;
}

sub change ($self) {
    my $actor = $self->authorized_write_user_id;
    return if !$actor;
    my $result = $self->gp_configuration->save_plugin(
        {
            actor    => $actor,
            command  => $self->command_id_param,
            expected => $self->param('revision'),
            plugin   => $self->param('plugin'),
            enabled  => $self->param('enabled') // 0,
            mode     => $self->param('mode')    // 'link',
        }
    );
    return $self->_result($result);
}

sub probe ($self) {
    return if !$self->authorized_write_user_id;
    my $url  = $self->param('url') // q{};
    my $card = $self->ui_integration_plugins->resolve($url);
    return $self->_page( $OK, $card ? 'matched' : 'unmatched', $card, $url );
}

sub probe_math ($self) {
    return if !$self->authorized_write_user_id;
    my $source = $self->param('source') // q{};
    return $self->_page( $INVALID, 'invalid' ) if length($source) > $MATH_LIMIT;
    my $html = GPForum::Service::Forum::BodyRenderer->new(
        math_plugins => $self->ui_integration_plugins )->render_safe($source);
    return $self->_page( $OK, q{}, undef, q{}, $source, $html );
}

sub _result ( $self, $result ) {
    my $status =
        $result->{status} eq 'ok'          ? $OK
      : $result->{status} eq 'conflict'    ? $CONFLICT
      : $result->{status} eq 'forbidden'   ? $FORBIDDEN
      : $result->{status} eq 'unavailable' ? $UNAVAILABLE
      :                                      $INVALID;
    $self->res->headers->cache_control('no-store');
    return $self->render(
        json   => $result,
        status => $status
    ) if $self->wants_json;
    if ( $result->{status} eq 'ok' ) {
        $self->flash( success => $self->t('admin.configuration_saved') );
        return $self->redirect_to('admin_plugins');
    }
    $self->gp_configuration->state( $self->gp_configuration->load );
    delete $self->stash->{'ui.integration_plugins'};
    return $self->_page( $status, $result->{status} );
}

sub _page (
    $self,
    $status       = $OK,
    $notice       = q{},
    $probe        = undef,
    $url          = q{},
    $math_source  = q{},
    $math_preview = q{}
  )
{
    my $state    = $self->gp_configuration->state;
    my $plugins  = $self->ui_integration_plugins->catalogue;
    my $overview = GPForum::ViewModel::Admin::IntegrationOverview->new->page(
        $self->gp_config, $self->ui_integration_plugins,
        $state->{available} );
    my @setup = grep { $_->{needs_instances} } @{ $overview->{plugins} };
    for my $plugin ( @{$plugins} ) {
        $plugin->{command_id} = $self->gp_id->uuid;
    }
    $self->res->headers->cache_control('no-store');
    return $self->render(
        json   => { revision => $state->{revision}, plugins => $plugins },
        status => $status
    ) if $self->wants_json;
    return $self->render(
        template      => 'admin/plugins',
        status        => $state->{available} ? $status : $UNAVAILABLE,
        plugins       => $plugins,
        setup_plugins => \@setup,
        revision      => $state->{revision},
        available     => $state->{available},
        notice        => $notice,
        probe         => $probe,
        probe_url     => $url,
        math_source   => $math_source,
        math_preview  => $math_preview,
        probe_command => $self->gp_id->uuid
    );
}

1;

__END__

=head1 NAME

GPForum::Controller::Admin::Plugins - Administrator GUI configuration boundary.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    # Wired by GPForum bootstrap and the administrator routes.

=head1 DESCRIPTION

Implements core-owned GUI settings. Provider modules receive no access to
this service, its database or credentials. See docs/integrations.md.

=head1 SUBROUTINES/METHODS

=head2 show

Authorizes an administrator and renders the management page without caching its response.

=head2 change

Checks CSRF, administration permission and rate limits, then saves settings through the core configuration service.

=head2 probe

Resolves a test URL through the current plugin API without network requests or publishing.

=head2 probe_math

Authorizes an administrator and previews bounded LaTeX through the same
local mathematics capability as the composer and forum posts.

=head1 DIAGNOSTICS

Writes return explicit ok, invalid, conflict, forbidden or unavailable states.
Database errors follow the application's normal error boundary. Secrets and
submitted values are not included in diagnostics.

=head1 CONFIGURATION AND ENVIRONMENT

Installation configuration remains the bootstrap source. Durable overrides
are stored in PostgreSQL through versioned functions and administrator writes.

=head1 DEPENDENCIES

Uses the core configuration and authorization boundaries and PostgreSQL API.

=head1 INCOMPATIBILITIES

Requires the administrator configuration migration for editable settings.

=head1 BUGS AND LIMITATIONS

Host bootstrap settings remain deployment-owned; settings marked for restart
are read during service startup. A failed write never reports success.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. BSD-3-Clause.

=cut
