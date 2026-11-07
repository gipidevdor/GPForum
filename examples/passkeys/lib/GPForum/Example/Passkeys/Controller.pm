# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Example::Passkeys::Controller;

use Mojo::Base 'Mojolicious::Controller', -signatures;
use v5.40;
use Const::Fast;
use Mojo::JSON qw(false true);

our $VERSION = '0.001';
const my $HTTP_BAD_REQUEST  => 400;
const my $HTTP_UNAUTHORIZED => 401;
const my $HTTP_FORBIDDEN    => 403;
const my $HTTP_CONFLICT     => 409;
const my $HTTP_UNAVAILABLE  => 503;

sub challenge ($self) {
    my $account = $self->_account or return;
    if ( ref $self->req->json ne 'HASH' ) {
        return $self->_failure( $HTTP_BAD_REQUEST, 'json_required' );
    }
    my $session = $self->session;
    my $old     = delete $session->{passkey_registration};
    my $entry;
    try {
        $entry = $self->app->challenges->issue( $account->{id},
            $old ? $old->{challenge} : undef );
    }
    catch ($error) {
        return $self->_failure( $HTTP_UNAVAILABLE, 'challenge_unavailable' );
    };
    $session->{passkey_registration} = $entry;
    my $options =
      $self->app->registration->options( $account, $entry->{challenge} );
    return $self->render( json => { publicKey => $options } );
}

sub verify ($self) {
    my $account = $self->_account or return;
    my $pending = delete $self->session->{passkey_registration};
    if (
        !$pending
        || !$self->app->challenges->consume(
            $account->{id}, $pending->{challenge}
        )
      )
    {
        return $self->_failure( $HTTP_CONFLICT, 'challenge_expired_or_used' );
    }
    my $verified;
    try {
        $verified = $self->app->registration->verify( $self->req->json,
            $pending->{challenge} );
    }
    catch ($error) {
        $self->app->log->warn('WebAuthn demonstration registration rejected');
        return $self->_failure( $HTTP_BAD_REQUEST, 'registration_invalid' );
    };

    # Production: persist $verified with the authenticated user in a single
    # canonical transaction, including uniqueness and audit, before success.
    return $self->render(
        json => {
            ok        => true,
            verified  => true,
            persisted => false,
        }
    );
}

sub _account ($self) {
    $self->res->headers->cache_control('private, no-store');
    my $account = $self->session('demo_account');
    if ( ref $account ne 'HASH' ) {
        $self->_failure( $HTTP_UNAUTHORIZED, 'session_required' );
        return undef;
    }
    my $headers = $self->req->headers;
    if ( ( $headers->origin // q{} ) ne $self->app->registration->origin ) {
        $self->_failure( $HTTP_FORBIDDEN, 'origin_invalid' );
        return undef;
    }
    if ( $self->validation->csrf_protect->has_error('csrf_token') ) {
        $self->_failure( $HTTP_FORBIDDEN, 'csrf_invalid' );
        return undef;
    }
    if (
        ( $headers->content_type // q{} ) !~ m{\Aapplication/json(?:;|\z)}msxi )
    {
        $self->_failure( $HTTP_BAD_REQUEST, 'json_required' );
        return undef;
    }
    return $account;
}

sub _failure ( $self, $status, $code ) {
    return $self->render(
        status => $status,
        json   => { ok => false, error => $code }
    );
}

1;

__END__

=head1 NAME

GPForum::Example::Passkeys::Controller - JSON ceremony endpoints for the isolated demo.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    $routes->post($path)->to(controller => $class, action => "challenge");

=head1 DESCRIPTION

Adapts the two registration JSON endpoints to session, CSRF and service boundaries.

=head1 SUBROUTINES/METHODS

=head2 challenge

Checks the example session, fixed Origin, JSON and Mojolicious CSRF header.
Stores a five-minute challenge in the signed session and its server-side ledger.

=head2 verify

Consumes the challenge before validating the response, including on failure.
Returns verified=true and persisted=false. No credential is saved or activated.

=head1 DIAGNOSTICS

JSON errors distinguish expired challenges, invalid registration, session, origin, CSRF and capacity failures. Cryptographic exception details are never sent or logged.

=head1 CONFIGURATION AND ENVIRONMENT

Services and fixed origin are provided by the example application.

=head1 DEPENDENCIES

See the pinned dependencies in examples/passkeys/cpanfile.snapshot.

=head1 INCOMPATIBILITIES

The ephemeral demo identity is not GPForum authentication. Verification does not persist a credential or establish a login.

=head1 BUGS AND LIMITATIONS

No credential persistence or assertion/login ceremony is implemented.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. BSD-3-Clause.

=cut
