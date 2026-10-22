# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Bootstrap::Security;

use v5.40;

use GPForum::OS::UnixListener;
use GPForum::Security::BrowserHeaders;
use GPForum::Web::ClientAddress;
use Mojo::ByteStream;

our $VERSION = '0.001';

sub register {
    my ( undef, %input ) = @_;

    my $application = $input{application};
    my $config      = $input{config};
    my $headers     = GPForum::Security::BrowserHeaders->new(
        include_hsts => $config->requires_secure_transport, );

    $application->sessions->samesite('Lax');
    $application->sessions->secure( $config->requires_secure_transport );

    $application->hook(
        after_dispatch => sub {
            my ($controller) = @_;

            $headers->apply($controller);
        }
    );
    _mask_csrf_token_once_per_response($application);
    GPForum::Web::ClientAddress->register($application);
    GPForum::OS::UnixListener->register($application);

    return;
}

# Mojolicious masks the session's CSRF token against BREACH on every
# csrf_token call: twenty random bytes, read by opening /dev/urandom when
# Crypt::PRNG is not installed, and the thread page has a form on every
# post -- 33 opens a request. BREACH compares one response's size with the
# next, so one mask per response protects as well as one per form: the first
# call's token is kept on the stash and every form on the page carries it,
# and the field is written once rather than through the tag helper 33 times.
# The written field is the one hidden_field writes, attribute for attribute.
# The kept token is the mask of the session's token it was made from: one
# rotated at sign-in or sign-out (Web::CookieSession) is masked afresh.
#
# A page rendered for the public cache (Web::PublicHttpCache) is served to
# every visitor, so its forms get no field at all, and the render leaves
# the session alone (ADR 0141).
sub _mask_csrf_token_once_per_response ($application) {
    my $masked_token = $application->renderer->get_helper('csrf_token');
    my $tag_field    = $application->renderer->get_helper('csrf_field');

    $application->helper(
        csrf_token => sub ($controller) {
            my $kept = $controller->stash->{'gpforum.csrf_token'};
            my $raw  = $controller->session->{csrf_token};
            return $kept->{masked}
              if $kept && defined $raw && $kept->{raw} eq $raw;

            my $masked = $masked_token->($controller);
            $controller->stash->{'gpforum.csrf_token'} = {
                masked => $masked,
                raw    => $controller->session->{csrf_token},
            };
            return $masked;
        }
    );
    $application->helper(
        csrf_field => sub ( $controller, @attributes ) {
            return Mojo::ByteStream->new(q{})
              if $controller->stash->{'gpforum.shared_render'};
            return $tag_field->( $controller, @attributes ) if @attributes;

            my $token = $controller->csrf_token;
            my $kept  = $controller->stash->{'gpforum.csrf_field'};
            return $kept->{field} if $kept && $kept->{token} eq $token;

            my $field =
              Mojo::ByteStream->new(
                    '<input name="csrf_token" type="hidden" value="'
                  . $token
                  . '">' );
            $controller->stash->{'gpforum.csrf_field'} =
              { field => $field, token => $token };
            return $field;
        }
    );

    return;
}

1;
