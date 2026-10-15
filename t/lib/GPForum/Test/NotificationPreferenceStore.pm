# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::NotificationPreferenceStore;

use Carp qw(croak);
use Mojo::Base -base;
use v5.40;

use GPForum::Service::Notification::PreferenceStore;

our $VERSION = '0.001';

has fail        => 0;
has preferences => sub { return _default_preferences(); };
has updates     => sub { return []; };

# ADR 0078: the kinds, as the real store reads them without a database (its
# defaults), and the choices stored here.
has defaults => sub {
    return GPForum::Service::Notification::PreferenceStore->new(
        schema    => {},
        functions => undef,
    );
};
has type_updates => sub { return []; };

sub type_preferences_for_user {
    my ( $self, $user_id ) = @_;

    croak 'notification preference load failed' if $self->fail;

    return $self->defaults->type_preferences_for_user($user_id);
}

sub refused_type_preferences {
    my ( $self, $preferences ) = @_;

    return $self->defaults->refused_type_preferences($preferences);
}

sub set_type_preferences {
    my ( $self, $input ) = @_;

    push @{ $self->type_updates }, { %{$input} };

    return { ok => 1, status => 'ok', changed => 0 };
}

sub event_types {
    return GPForum::Service::Notification::PreferenceStore->event_types;
}

sub type_channels {
    return GPForum::Service::Notification::PreferenceStore->type_channels;
}

sub preferences_for_user {
    my ( $self, $user_id ) = @_;

    croak 'notification preference load failed' if $self->fail;

    return [ map { +{ %{$_}, user_id => $user_id, } } @{ $self->preferences } ];
}

sub set_preferences {
    my ( $self, $input ) = @_;

    croak 'notification preference save failed' if $self->fail;

    push @{ $self->updates }, { %{$input} };
    $self->preferences(
        [
            map {
                +{
                    %{$_},
                    description_key => 'notifications.preference.'
                      . $_->{channel}
                      . '.description',
                    label_key => 'notifications.channel.' . $_->{channel},
                }
            } @{ $input->{preferences} }
        ]
    );

    return $self->preferences_for_user( $input->{user_id} );
}

sub channel_names {
    return [qw(in_app email digest)];
}

sub digest_frequency_options {
    return [
        map {
            +{
                label_key => 'notifications.digest_frequency.' . $_,
                value     => $_,
            }
        } qw(immediate daily weekly never)
    ];
}

sub _default_preferences {
    return [
        {
            channel          => 'in_app',
            description_key  => 'notifications.preference.in_app.description',
            digest_frequency => 'immediate',
            enabled          => 1,
            label_key        => 'notifications.channel.in_app',
        },
        {
            channel          => 'email',
            description_key  => 'notifications.preference.email.description',
            digest_frequency => 'daily',
            enabled          => 1,
            label_key        => 'notifications.channel.email',
        },
        {
            channel          => 'digest',
            description_key  => 'notifications.preference.digest.description',
            digest_frequency => 'daily',
            enabled          => 0,
            label_key        => 'notifications.channel.digest',
        },
    ];
}

1;
