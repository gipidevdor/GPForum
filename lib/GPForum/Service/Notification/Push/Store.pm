# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Notification::Push::Store;

use Mojo::Base 'GPForum::Base', -signatures, -async_await;
use v5.40;
use Const::Fast;
use Crypt::URandom       qw(urandom);
use Crypt::KeyDerivation qw(hkdf);
use Digest::SHA          qw(sha256_hex hmac_sha256_hex);
use MIME::Base64         qw(encode_base64url);
use GPForum::Infrastructure::Id;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Service::Notification::Push::Crypto;
use GPForum::Service::Notification::Push::Endpoint;
use GPForum::Service::Notification::Push::Secrets;
use GPForum::X::Argument;
use GPForum::X::Config;

our $VERSION = '0.001';
const my $KEY_BYTES     => 32;
const my $AUTH_BYTES    => 16;
const my $KEY_ID_DIGITS => 16;
const my @KINDS         => qw(reply mention moderation message);
const my %KIND          => map { $_ => 1 } @KINDS;
__PACKAGE__->requires(qw(schema config));
has functions => \&GPForum::Infrastructure::SqlFunction::for_service;
has crypto => sub { return GPForum::Service::Notification::Push::Crypto->new; };
has endpoint => sub ($self) {
    return GPForum::Service::Notification::Push::Endpoint->new(
        providers => $self->config->push_providers );
};
has secrets => sub ($self) {
    return GPForum::Service::Notification::Push::Secrets->new(
        directory => $self->config->push_key_directory );
};
has id_service => sub { return GPForum::Infrastructure::Id->new; };

sub enabled ($self) {
    return $self->config->push_enabled ? 1 : 0;
}

sub public_config ($self) {
    return { enabled => 0 } if !$self->enabled;
    my $contact       = $self->config->push_contact;
    my $mail_contact  = qr{\Amailto:[[:alnum:]._%+-]+\@[[:alnum:].-]+\z}amsx;
    my $https_contact = qr{\Ahttps://[[:alnum:].-]+(?:/\S*)?\z}amsx;
    if (   !defined $contact
        || !( $contact =~ $mail_contact || $contact =~ $https_contact ) )
    {
        GPForum::X::Config->throw(
            message => 'Push requires a VAPID contact URI' );
    }
    my $keys   = $self->secrets->public;
    my $id     = $keys->{active};
    my $public = $keys->{keys}{$id};
    $self->crypto->receiver(
        { p256dh => $public, auth => encode_base64url( "\0" x $AUTH_BYTES ) } );
    my $expected_id = substr sha256_hex($public), 0, $KEY_ID_DIGITS;
    if ( $id ne $expected_id ) {
        GPForum::X::Config->throw(
            message => 'invalid Push public key identity' );
    }
    return { enabled => 1, key_id => $id, application_server_key => $public };
}

sub devices ( $self, $user ) {
    return $self->functions->rows( 'notification_push_devices',
        { user_id => $user } );
}

async sub devices_p ( $self, $user, $context = undef ) {
    return await $self->functions->rows_p( 'notification_push_devices',
        { user_id => $user }, $context );
}

sub register ( $self, $user, $session, $input ) {
    return $self->functions->row( 'notification_push_register',
        $self->_register_values( $user, $session, $input ) )->{result};
}

async sub register_p ( $self, $user, $session, $input, $context = undef ) {
    my $values = $self->_register_values( $user, $session, $input );
    return (
        await $self->functions->row_p(
            'notification_push_register', $values, $context
        )
    )->{result};
}

sub _register_values ( $self, $user, $session, $input ) {
    my $public = $self->public_config;
    if ( !$public->{enabled} ) {
        GPForum::X::Argument->throw( message => 'Push disabled' );
    }
    if ( ref $input ne 'HASH'
        || ( $input->{key_id} // q{} ) ne $public->{key_id} )
    {
        GPForum::X::Argument->throw( message => 'invalid Push subscription' );
    }
    my $url = $self->endpoint->parse( $input->{endpoint} );
    $self->crypto->receiver( $input->{keys} );
    my $kinds = $input->{kinds};
    if ( ref $kinds ne 'ARRAY' || !@{$kinds} || @{$kinds} > @KINDS ) {
        GPForum::X::Argument->throw(
            message => 'invalid Push notification kinds' );
    }
    my %seen;

    for my $kind ( @{$kinds} ) {
        if (  !defined $kind
            || ref $kind
            || !exists $KIND{$kind}
            || $seen{$kind}++ )
        {
            GPForum::X::Argument->throw(
                message => 'invalid Push notification kinds' );
        }
    }
    my $storage   = $self->secrets->storage;
    my $index_key = hkdf( $storage, undef, 'SHA256', $KEY_BYTES,
        'GPForum.push.endpoint-index.v1' );
    my $hash     = hmac_sha256_hex( $url->to_string, $index_key );
    my $id       = $self->id_service->uuid;
    my $nonce    = encode_base64url( urandom($KEY_BYTES) );
    my $envelope = $self->crypto->seal( $storage, "subscription:$user:$hash",
        { endpoint => $url->to_string, keys => $input->{keys} } );
    my $activation = $self->crypto->seal( $storage, "activation:$id",
        { type => 'activation', subscription_id => $id, nonce => $nonce } );
    return {
        user_id         => $user,
        session_id      => $session,
        subscription_id => $id,
        endpoint_hash   => $hash,
        envelope        => $envelope,
        provider        => $url->host,
        key_id          => $public->{key_id},
        kinds           => $kinds,
        challenge_hash  => sha256_hex($nonce),
        activation      => $activation,
    };
}

sub confirm ( $self, $user, $session, $input ) {
    return $self->functions->row( 'notification_push_confirm',
        $self->_confirm_values( $user, $session, $input ) )->{result};
}

async sub confirm_p ( $self, $user, $session, $input, $context = undef ) {
    my $values = $self->_confirm_values( $user, $session, $input );
    return (
        await $self->functions->row_p(
            'notification_push_confirm', $values, $context
        )
    )->{result};
}

sub _confirm_values ( $self, $user, $session, $input ) {
    if ( ref $input ne 'HASH' ) {
        GPForum::X::Argument->throw( message => 'invalid Push confirmation' );
    }
    if ( !GPForum::Infrastructure::Id->is_uuid( $input->{subscription_id} ) ) {
        GPForum::X::Argument->throw( message => 'invalid Push binding' );
    }
    $self->crypto->unbase64( $input->{nonce}, $KEY_BYTES );
    return {
        user_id         => $user,
        session_id      => $session,
        subscription_id => $input->{subscription_id},
        challenge_hash  => sha256_hex( $input->{nonce} ),
    };
}

sub revoke ( $self, $user, $id ) {
    return $self->functions->row( 'notification_push_revoke',
        _revoke_values( $user, $id ) )->{result};
}

async sub revoke_p ( $self, $user, $id, $context = undef ) {
    my $values = _revoke_values( $user, $id );
    return (
        await $self->functions->row_p(
            'notification_push_revoke', $values, $context
        )
    )->{result};
}

sub _revoke_values ( $user, $id ) {
    if ( !GPForum::Infrastructure::Id->is_uuid($id) ) {
        GPForum::X::Argument->throw( message => 'invalid Push binding' );
    }
    return { user_id => $user, subscription_id => $id };
}

1;

__END__

=head1 NAME

GPForum::Service::Notification::Push::Store - Own explicit per-device consent and subscription receipt verification.

=head1 DESCRIPTION

Own explicit per-device consent and subscription receipt verification. See docs/ops/web-push.md for deployment and lifecycle guarantees.

=head1 SUBROUTINES/METHODS

=head2 enabled

Return the installation kill-switch state.

=head2 public_config

Return the active public VAPID key and its identity. Private signing keys are never read here.

=head2 devices

List at most ten live device bindings belonging to the authenticated user.

=head2 devices_p

L</devices> as a promise, with an optional query context last, read on the
worker's pooled asynchronous connections.

=head2 register

Validate the receiver and notification kinds, seal capability material, and queue a visible receipt challenge. Does not return the challenge nonce.

=head2 register_p

L</register> as a promise, with an optional query context last; the binding
is written on the worker's pooled asynchronous connections.

=head2 confirm

Activate only the matching pending binding, live session and unexpired single-use receipt nonce.

=head2 confirm_p

L</confirm> as a promise, with an optional query context last, run on the
worker's pooled asynchronous connections.

=head2 revoke

Remove only this user's specified binding and its queued jobs. Does not disclose whether another user owns the id.

=head2 revoke_p

L</revoke> as a promise, with an optional query context last, run on the
worker's pooled asynchronous connections.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $service = GPForum::Service::Notification::Push::Store->new(schema => $schema, config => $config);

=head1 DIAGNOSTICS

Invalid input fails closed. Transport failures are bounded and reported without receiver capability URLs or key material.

=head1 CONFIGURATION AND ENVIRONMENT

Dependencies and validated settings are supplied by the composition layer. See docs/ops/web-push.md.

=head1 DEPENDENCIES

CryptX supplies cryptographic primitives; Mojolicious supplies asynchronous HTTPS; versioned PostgreSQL API functions own persistence.

=head1 INCOMPATIBILITIES

Private key files require a persistent service account and restrictive filesystem permissions.

=head1 BUGS AND LIMITATIONS

A provider acceptance does not guarantee display. An already accepted notification cannot be recalled.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. BSD-3-Clause.

=cut
