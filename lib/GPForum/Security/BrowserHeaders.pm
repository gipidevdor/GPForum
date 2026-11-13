# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Security::BrowserHeaders;

use Const::Fast;
use Mojo::Base -base, -signatures;
use v5.40;

our $VERSION = '0.001';

const my $HSTS_MAX_AGE => 31_536_000;

has include_hsts  => sub { return 0; };
has embed_origins => sub { return []; };

sub apply ( $self, $controller ) {
    my $headers = $controller->res->headers;

    $headers->header( 'X-Content-Type-Options' => 'nosniff' );
    $headers->header( 'X-Frame-Options'        => 'DENY' );
    $headers->header( 'Referrer-Policy' => 'strict-origin-when-cross-origin' );
    $headers->header( 'Permissions-Policy' =>
          'camera=(), microphone=(), geolocation=(), payment=()' );
    my $policy = $self->content_security_policy;
    if ( ( $headers->header('Service-Worker-Allowed') // q{} ) eq '/push/' ) {
        $policy = q{default-src 'none'; script-src 'self'; connect-src 'self'};
    }
    $headers->content_security_policy($policy);
    $self->_apply_hsts($headers);
    _apply_private_cache($controller);

    return;
}

# A page or JSON answer rendered for a member carries their data and their
# CSRF token: unless the action chose its own caching, no cache keeps it
# (ASVS 5.0 14.3.2). The same URL answers HTML, JSON or an htmx fragment, so
# every such answer varies on the headers that choose among them, or a
# browser shows the cached JSON or fragment when going back to the page.
sub _apply_private_cache ($controller) {
    my $headers = $controller->res->headers;
    return
      if ( $headers->content_type // q{} ) !~
      m{\A(?:text/html|application/json)}imsx;

    my $vary = $headers->vary // q{};
    for my $name (qw(Accept HX-Request)) {
        next if $vary =~ /\b\Q$name\E\b/imsx;
        $headers->append( Vary => $name );
    }
    return if defined $headers->cache_control;
    return if !$controller->session('user_id') && !$headers->set_cookie;

    $headers->cache_control('private, no-store');
    return;
}

sub content_security_policy ($self) {
    return join q{; }, @{ $self->directives };
}

sub hsts_policy {
    return 'max-age=' . $HSTS_MAX_AGE . '; includeSubDomains';
}

sub directives ($self) {
    return [
        q{default-src 'self'},
        q{script-src 'self'},
        q{style-src 'self'},
        q{img-src 'self' data:},
        q{font-src 'self'},
        q{connect-src 'self'},
        q{worker-src 'self'},
        q{frame-src 'self'}
          . join( q{}, map { q{ } . $_ } @{ $self->embed_origins } ),
        q{base-uri 'self'},
        q{form-action 'self'},
        q{frame-ancestors 'none'},
        q{object-src 'none'},
    ];
}

sub _apply_hsts ( $self, $headers ) {
    if ( !$self->include_hsts ) {
        return;
    }

    $headers->header( 'Strict-Transport-Security' => $self->hsts_policy );

    return;
}

1;
