# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Web::ManifestPayload;

use Mojo::Base -strict, -signatures;
use v5.40;

our $VERSION = '0.001';

sub build ( $, $config, $themes ) {
    my $color = $themes->theme_colors( $config->default_theme )->[0]{color};
    return {
        name             => $config->site_name,
        short_name       => $config->site_name,
        description      => $config->site_description,
        start_url        => q{.},
        display          => 'standalone',
        background_color => $color,
        theme_color      => $color,
        icons            => [
            {
                src     => 'icon.svg',
                sizes   => 'any',
                type    => 'image/svg+xml',
                purpose => 'any'
            },
            {
                src     => 'icon-192.png',
                sizes   => '192x192',
                type    => 'image/png',
                purpose => 'any'
            },
            {
                src     => 'icon-512.png',
                sizes   => '512x512',
                type    => 'image/png',
                purpose => 'any'
            },
        ],
    };
}

1;

__END__

=head1 NAME

GPForum::Web::ManifestPayload - Installation identity for browser installation

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $manifest = GPForum::Web::ManifestPayload->build($config, $themes);

=head1 DESCRIPTION

Builds the standalone web manifest using the configured community name,
description and default theme. All icons are local exports of the approved
orbit. Relative URLs preserve a reverse proxy's application prefix.

=head1 SUBROUTINES/METHODS

=head2 build

Takes validated configuration and a theme registry. Returns a plain hash for
an application/manifest+json response, without member or session data.

=head1 DIAGNOSTICS

None.

=head1 CONFIGURATION AND ENVIRONMENT

Uses C<GPFORUM_SITE_NAME>, C<GPFORUM_SITE_DESCRIPTION> and C<GPFORUM_DEFAULT_THEME>.

=head1 DEPENDENCIES

L<GPForum::Config> and L<GPForum::Theme::Registry>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

The manifest records the configured default palette, not a member's theme.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause license.

=cut
