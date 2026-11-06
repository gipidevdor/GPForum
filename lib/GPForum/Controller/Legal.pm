# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Controller::Legal;

use Encode qw(encode);
use GPForum::Web::CookieSession;
use GPForum::Web::IdentityAccess;
use GPForum::Web::LegalAccess;
use Mojo::Base 'Mojolicious::Controller', -signatures;
use v5.40;

our $VERSION = '0.001';

sub terms ($self) {
    return $self->_page('terms');
}

sub privacy ($self) {
    return $self->_page('privacy');
}

sub cookies ($self) {
    return $self->_page('cookies');
}

sub notice ($self) {
    return $self->_page('notice');
}

# RFC 9116, served at /.well-known/security.txt (RFC 8615) from the
# settings; with no contact set there is none to serve.
sub security_txt ($self) {
    my $config = $self->gp_config;
    my $text   = GPForum::Web::LegalAccess->new->security_txt(
        contact        => $config->security_contact,
        operator_email => $config->operator_email,
        base_url       => $self->gp_canonical_url->base_url,
        languages      => $self->_locales,
        now            => time,
    );
    return $self->reply->not_found if !defined $text;

    $self->res->headers->cache_control('public, max-age=86400');
    return $self->render( data => encode( 'UTF-8', $text ), format => 'txt' );
}

sub _page ( $self, $page ) {
    my $access = GPForum::Web::LegalAccess->new;
    return $access->render_page(
        $self,
        $access->page_payload(
            $page, $self->_canonical_for($page),
            $self->_facts
        )
    );
}

# What the legal pages state about this forum: the operator's settings, the
# languages a message is answered in, security.txt when one is served, and
# the cookies as the code that sets them names them.
sub _facts ($self) {
    my $config   = $self->gp_config;
    my $identity = GPForum::Web::IdentityAccess->new;
    my $access   = GPForum::Web::LegalAccess->new;
    my $has_security_txt =
      length( $config->security_contact ) || length( $config->operator_email );

    return {
        name            => $config->operator_name,
        address         => $config->operator_address,
        email           => $config->operator_email,
        vat_number      => $config->operator_vat_number,
        register        => $config->operator_register,
        privacy_officer => $config->privacy_officer_email,
        languages       => [
            map { $self->i18n_service->locale_metadata($_)->{native_name} }
              @{ $self->_locales }
        ],
        security_txt => $has_security_txt
        ? $self->gp_canonical_url->base_url . '/.well-known/security.txt'
        : undef,
        cookies => $access->cookie_rows(
            session_name       => $self->app->sessions->cookie_name,
            session_seconds    => GPForum::Web::CookieSession->session_seconds,
            visitor_seconds    => $self->app->sessions->default_expiration,
            locale_name        => $identity->locale_cookie_name,
            theme_name         => $identity->theme_cookie_name,
            device_name        => $identity->device_cookie_name,
            preference_seconds => $identity->preference_cookie_seconds,
        ),
    };
}

# The forum's languages, its default first.
sub _locales ($self) {
    my $default = $self->gp_config->default_locale;
    my @locales = @{ $self->i18n_service->supported_locales };

    return [
        ( grep { $_ eq $default } @locales ),
        sort grep { $_ ne $default } @locales
    ];
}

sub _canonical_for ( $self, $page ) {
    return $self->gp_canonical_url->legal_url($page);
}

1;

__END__

=head1 NAME

GPForum::Controller::Legal - Public terms, privacy, and cookie pages.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    $routes->get('/legal/terms')->to('Legal#terms');

=head1 DESCRIPTION

Renders the public legal pages. HTTP policy and payload shape live on
L<GPForum::Web::LegalAccess>. Canonical URLs come from
L<GPForum::Service::Discovery::CanonicalUrl>.

=head1 SUBROUTINES/METHODS

=head2 terms

Renders the terms of use.

=head2 privacy

Renders the privacy notice.

=head2 cookies

Renders the cookie notice, with the cookies as the code that sets them
names them.

=head2 notice

Renders the legal notice: who runs the forum and the point of contact.

=head2 security_txt

Serves C</.well-known/security.txt> (RFC 9116) from
C<GPFORUM_SECURITY_CONTACT>, or C<GPFORUM_OPERATOR_EMAIL> when it is empty;
404 with neither.

=head1 DIAGNOSTICS

Rendering errors are reported by Mojolicious.

=head1 CONFIGURATION AND ENVIRONMENT

Uses the canonical URL helper configured during application startup.

=head1 DEPENDENCIES

Uses L<Mojolicious::Controller> and L<GPForum::Web::LegalAccess>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Copy describes how this software behaves. A deployed instance still needs
operator-reviewed policy text.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
