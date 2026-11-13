# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause
package GPForum::Controller::Identity::Passkeys;
use Mojo::Base 'GPForum::Controller::Identity', -async_await;
use v5.40;
use Const::Fast;
use Crypt::URandom qw(urandom);
use MIME::Base64   qw(encode_base64url);
our $VERSION = '0.001';
const my $HTTP_BAD          => 400;
const my $HTTP_UNAUTHORIZED => 401;
const my $HTTP_FORBIDDEN    => 403;
const my $HTTP_UNAVAILABLE  => 503;
const my $RANDOM_BYTES      => 32;
const my $REQUEST_LIMIT     => 65_536;

sub _provider ($self) {
    return $self->gp_passkeys;
}

async sub show ($self) {
    return $self->settings_unauthorized if !$self->current_user_id;
    my ( $enabled, $keys );
    try {
        my $provider = $self->_provider;
        $enabled = $provider->enabled;
        $keys =
          ( await $self->call_p( $provider, 'listed', $self->current_user_id )
          );
    }
    catch ($error) { return $self->identity_unavailable; };
    $self->res->headers->cache_control('private, no-store');
    return $self->render(
        template => 'identity/passkeys',
        enabled  => $enabled,
        passkeys => $keys
    );
}
async sub begin_registration ($self) {
    return ( await $self->await_p( $self->_begin('register') ) );
}
async sub begin_login ($self) {
    return ( await $self->await_p( $self->_begin('login') ) );
}

async sub _begin ( $self, $purpose ) {
    return if ( await $self->await_p( $self->_guard($purpose) ) );
    my $binding = encode_base64url( urandom($RANDOM_BYTES) );
    my $options;
    try {
        $options = (
            await $self->call_p(
                $self->_provider,
                'begin',
                {
                    purpose    => $purpose,
                    binding    => $binding,
                    user_id    => $self->current_user_id,
                    session_id => $self->session('session_id'),
                    password   => $self->param('password'),
                    code       => $self->param('code'),
                    label      => $self->param('label')
                }
            )
        );
    }
    catch ($error) { return $self->_refused; };
    if ( !$options ) { return $self->_refused; }
    delete $self->session->{expires};
    $self->session(
        'passkey_'
          . $purpose => {
            binding   => $binding,
            challenge => $options->{challenge},
            return_to => $self->_after_login
          }
    );
    return $self->render( json => { publicKey => $options } );
}
async sub finish_registration ($self) {
    return ( await $self->await_p( $self->_finish('register') ) );
}
async sub finish_login ($self) {
    return ( await $self->await_p( $self->_finish('login') ) );
}

async sub _finish ( $self, $purpose ) {
    return if ( await $self->await_p( $self->_guard($purpose) ) );
    my $flow = delete $self->session->{ 'passkey_' . $purpose };
    return $self->_refused if ref $flow ne 'HASH';
    my $payload;
    try { $payload = $self->req->json; } catch ($error) {
        return $self->_refused;
    };
    my $answer;
    try {
        $answer = (
            await $self->call_p(
                $self->_provider,
                'complete',
                {
                    %{$flow},
                    purpose         => $purpose,
                    credential      => $payload,
                    user_id         => $self->current_user_id,
                    session_id      => $self->session('session_id'),
                    request_address => $self->request_address,
                    user_agent => $self->req->headers->user_agent // 'unknown'
                }
            )
        );
    }
    catch ($error) { return $self->_refused; };
    if ( !$answer ) { return $self->_refused; }
    if ( $purpose eq 'register' ) {
        return $self->render(
            json => {
                ok        => 1,
                persisted => 1,
                next      => $self->url_for('settings_passkeys')->to_string
            }
        );
    }
    if ( $answer->{status} eq 'second_factor' ) {
        my $response = $self->_ask_second_step($answer);
        $self->session( second_factor_return_to => $flow->{return_to} );
        return $response;
    }
    if ( !$answer->{ok} ) { return $self->_refused; }
    $self->_apply_login_session($answer);
    my $next =
      ( await $self->await_p( $self->_second_step_owed( $answer->{user_id} ) ) )
      ? $self->url_for('settings_security')->to_string
      : $self->safe_return_to( $flow->{return_to} );
    return $self->render( json => { ok => 1, next => $next } );
}

async sub revoke ($self) {
    return if ( await $self->await_p( $self->_guard('register') ) );
    return $self->respond_p(
        $self->call_p(
            $self->_provider,
            'revoke',
            {
                user_id    => $self->current_user_id,
                session_id => $self->session('session_id'),
                id         => $self->param('passkey_id'),
                password   => $self->param('password'),
                code       => $self->param('code')
            }
        ),
        sub ($answer) { return $self->_revoked_async($answer); },
        sub ($error) { return $self->_refused; }
    );
}

sub _revoked_async ( $self, $answer ) {
    if ( !$answer ) { return $self->_refused; }
    $self->flash( success => $self->t('auth.passkey_revoked') );
    return $self->redirect_to('settings_passkeys');
}

async sub _guard ( $self, $purpose ) {
    $self->res->headers->cache_control('private, no-store');
    if ( $self->req->body_size > $REQUEST_LIMIT ) {
        return $self->render(
            status => $HTTP_BAD,
            json   => { error => 'passkey_invalid' }
        );
    }
    if ( $self->validation->csrf_protect->has_error('csrf_token') ) {
        return $self->_csrf_failure;
    }
    my $action =
      $purpose eq 'register'
      ? 'identity.second_factor_settings'
      : 'identity.login';
    my $blocked =
      ( await $self->await_p( $self->identity_post_guard($action) ) );
    if ($blocked) { return $blocked; }
    if ( $purpose eq 'register' ) {
        return ( await $self->await_p( $self->_member_guard ) )
          || ( await $self->await_p( $self->_origin_guard ) );
    }
    return ( await $self->await_p( $self->_origin_guard ) );
}

async sub _member_guard ($self) {
    if ( !$self->current_user_id ) {
        return $self->render(
            status => $HTTP_UNAUTHORIZED,
            json   => { error => 'unauthorized' }
        );
    }
    if (
        !(
            await $self->await_p(
                $self->participating(
                    $self->current_user_id, 'identity.passkey'
                )
            )
        )
      )
    {
        return 1;
    }
    return;
}

async sub _origin_guard ($self) {
    my $provider = $self->_provider;
    if ( !$provider->enabled ) {
        return $self->render(
            status => $HTTP_UNAVAILABLE,
            json   => { error => 'passkey_unavailable' }
        );
    }
    if ( ( $self->req->headers->origin // q{} ) ne
        ( await $self->call_p( $provider, 'origin' ) ) )
    {
        return $self->render(
            status => $HTTP_FORBIDDEN,
            json   => { error => 'origin_invalid' }
        );
    }
    return;
}

sub _refused ($self) {
    return $self->render(
        status => $HTTP_BAD,
        json   => { error => $self->t('auth.passkey_failed') }
    );
}
1;

__END__
=head1 NAME

GPForum::Controller::Identity::Passkeys - Account passkey forms and browser ceremonies.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    $routes->get('/settings/passkeys')->to('Identity::Passkeys#show');

=head1 DESCRIPTION

Connects login and settings forms to the passkey service with exact Origin,
CSRF, request-size, participation and rate-limit guards. Existing session and
second-factor response helpers finish authentication.

=head1 SUBROUTINES/METHODS

=head2 show

Lists the signed-in member's active passkeys and the registration/revocation forms.

=head2 begin_registration

Requires a signed-in member and fresh local proof before starting registration.

=head2 finish_registration

Consumes and verifies the browser's registration response, then persists the key.

=head2 begin_login

Starts a discoverable, browser-bound login ceremony from the login form.

=head2 finish_login

Verifies the assertion, starts configured TOTP or opens the standard server session.

=head2 revoke

Requires fresh local proof and revokes the owned credential and other sessions.

=head1 DIAGNOSTICS

CSRF and Origin refusals answer 403; invalid ceremonies answer 400; unsupported configuration answers 503.

=head1 CONFIGURATION AND ENVIRONMENT

Uses the application-owned gp_passkeys helper and the configured public forum origin.

=head1 DEPENDENCIES

Uses the identity and infrastructure modules named above.

=head1 INCOMPATIBILITIES

External identity and TOTP retain their existing account policies.

=head1 BUGS AND LIMITATIONS

Browser cryptographic ceremonies require JavaScript, a compatible authenticator and a secure context.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. BSD-3-Clause.

=cut
