# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Bootstrap::Branding;

use Mojo::Base -strict, -signatures;
use v5.40;

use Const::Fast;

our $VERSION = '0.001';

const my $HTTP_NOT_FOUND   => 404;
const my $BUNDLED_PAGE     => qr{\Amojo/(?:debug|exception|not_found)\z}msx;
const my $APPLICATION_PAGE => qr{\A(?:exception|not_found)(?:[.].*)?\z}msx;

sub register ( $, $application, $config ) {

    # Only the application's own assets are public. In particular, a browser's
    # implicit /favicon.ico must never find the framework's bundled icon.
    $application->static->extra( {} );
    $application->hook(
        after_dispatch => sub ($controller) {
            $controller->res->headers->server('GPForum');
            return;
        }
    );
    $application->hook(
        before_render => sub ( $controller, $arguments ) {
            my $template = $arguments->{template} // q{};
            my $bundled  = $template =~ $BUNDLED_PAGE;
            return if !$bundled && $template !~ $APPLICATION_PAGE;
            $controller->res->headers->cache_control('no-store');
            if ( !$bundled ) {
                $arguments->{system_reference} =
                  $controller->stash('gp_request_id');
                return;
            }

            # The ordinary exception templates use the shared UI. If that UI
            # itself fails, the framework reaches its bundled last resort.
            # Replace that last resort with a small, independent page too.
            my $not_found = ( $arguments->{status} // 0 ) == $HTTP_NOT_FOUND;
            my $kind      = $not_found ? 'not_found' : 'internal';
            my $i18n      = $controller->i18n_service;
            my $locale    = $controller->stash('ui_locale')
              || $i18n->negotiate( $controller->req->headers->accept_language
                  // q{} );
            my $effective = $controller->stash('gp.effective_configuration')
              // $config;
            @{$arguments}{qw(template format handler layout extends)} =
              ( 'system/fallback', 'html', 'ep', undef, undef );
            $arguments->{system_name}   = $effective->site_name;
            $arguments->{system_theme}  = $effective->default_theme;
            $arguments->{system_locale} = $locale;
            $arguments->{system_heading} =
              $i18n->translate( $locale, "forum.error_${kind}_title" );
            $arguments->{system_message} =
              $i18n->translate( $locale, "forum.error_${kind}_message" );
            $arguments->{system_home_label} =
              $i18n->translate( $locale, 'ui.back_to_forum' );
            return;
        }
    );
    return;
}

1;

__END__

=head1 NAME

GPForum::Bootstrap::Branding - Application-owned browser and error surfaces

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    GPForum::Bootstrap::Branding->register($application, $config);

=head1 DESCRIPTION

Disables bundled framework assets and identifies HTTP responses as GPForum.
Normal exception and not-found templates use the forum's system layout. If
those templates fail, the public before_render hook replaces the framework's
bundled error page with an independent, localized fallback. Exception logging
and JSON/text reply helpers retain their framework behavior.

=head1 SUBROUTINES/METHODS

=head2 register

Registers static, response-header and last-resort rendering policies. Takes
the application and its validated installation configuration.

=head1 DIAGNOSTICS

Exceptions remain in application logs. Public error pages expose no stack,
source, request body or environment data.

=head1 CONFIGURATION AND ENVIRONMENT

Uses the installation name and negotiated locale. Public assets come from the
application's configured static paths.

=head1 DEPENDENCIES

L<Mojo::Base> and the registered Good Phorum translation service.

=head1 INCOMPATIBILITIES

Framework debugger pages and their bundled static assets are intentionally
unavailable through the forum's public HTTP surface.

=head1 BUGS AND LIMITATIONS

The fallback still requires the framework renderer and translation catalog.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause license.

=cut
