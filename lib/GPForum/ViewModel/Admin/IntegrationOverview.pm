# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package GPForum::ViewModel::Admin::IntegrationOverview;
use Mojo::Base -base, -signatures;
use v5.40;
use GPForum::Service::Integration::Readiness;
our $VERSION = '0.001';

# Configuration readiness only; no network probes or credentials enter the view.
sub page ( $self, $config, $registry, $available ) {
    return {
        plugins        => _plugins( $registry, $available ),
        network        => _network( $config, $available ),
        worker_enabled => $config->minion_enabled ? 1 : 0,
    };
}

sub _network ( $config, $available ) {
    my @services = (
        {
            id      => 'discord',
            name    => 'Discord',
            setting => 'discord_webhook',
            anchor  => 'discord-heading'
        },
        {
            id        => 'feeds',
            label_key => 'admin.integrations_feeds',
            setting   => 'syndication_sources',
            anchor    => 'feeds-heading'
        },
        {
            id        => 'openid',
            label_key => 'auth.oidc_settings',
            setting   => 'oidc_issuer',
            route     => 'settings_openid'
        },
    );
    for my $service (@services) {
        my $missing =
          GPForum::Service::Integration::Readiness->missing( $service->{id},
            $config );
        $service->{configured} = $available && !@{$missing} ? 1 : 0;
        $service->{missing}    = $missing;
        if ( @{$missing} ) { $service->{setting} = $missing->[0]; }
    }
    return \@services;
}

sub _plugins ( $registry, $available ) {
    my $plugins = $registry->catalogue;
    my %present = map { $_->{id} => 1 } @{$plugins};
    for my $pair ( [ 'mastodon', 'Mastodon' ], [ 'peertube', 'PeerTube' ] ) {
        next if $present{ $pair->[0] };
        push @{$plugins},
          {
            id              => $pair->[0],
            name            => $pair->[1],
            enabled         => 0,
            needs_instances => 1
          };
    }
    for my $plugin ( @{$plugins} ) {
        $plugin->{state} =
           !$available                 ? 'unavailable'
          : $plugin->{needs_instances} ? 'setup'
          : $plugin->{enabled}         ? 'active'
          :                              'inactive';
        $plugin->{setting} =
          $plugin->{needs_instances} ? $plugin->{id} . '_hosts' : undef;
    }
    return $plugins;
}

1;
__END__

=head1 NAME

GPForum::ViewModel::Admin::IntegrationOverview - Configuration readiness and entry points for installed integrations.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $page = $model->page($config,$registry,$available);

=head1 DESCRIPTION

Builds display data for every installed module, network workflow and worker
configuration. No credential value or network result is returned.

=head1 SUBROUTINES/METHODS

=head2 page

Returns plugin configuration states, network workflow readiness and links to
configuration controls. Federated modules remain discoverable before an
administrator authorizes their first instance. Readiness describes local
configuration, not provider availability or a running external worker.

=head1 DIAGNOSTICS

None.

=head1 CONFIGURATION AND ENVIRONMENT

Uses the request's validated effective configuration and plugin registry.

=head1 DEPENDENCIES

Mojo::Base.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

External connectivity is not tested by rendering this overview.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. BSD-3-Clause.

=cut
