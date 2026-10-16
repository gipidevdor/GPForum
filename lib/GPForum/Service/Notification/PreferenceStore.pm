# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Notification::PreferenceStore;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -signatures;
use v5.40;

use Mojo::JSON qw(false true);

use GPForum::Infrastructure::EventRecorder;
use GPForum::Infrastructure::Row;
use GPForum::Infrastructure::UniqueConflict;
use GPForum::Service::Clock;
use GPForum::X::Conflict;
use GPForum::X::Unavailable;

use GPForum::Infrastructure::SqlFunction;
use GPForum::Infrastructure::ResultRow;

our $VERSION = '0.001';

const my @CHANNELS           => qw(in_app email digest);
const my @DIGEST_FREQUENCIES => qw(immediate daily weekly never);
const my %CHANNEL_DEFAULTS => (
    digest => {
        digest_frequency => 'daily',
        enabled          => 0,
    },
    email => {
        digest_frequency => 'daily',
        enabled          => 1,
    },
    in_app => {
        digest_frequency => 'immediate',
        enabled          => 1,
    },
);

# ADR 0078: the kinds of notification a member controls, each on these
# channels, and the scopes an unsubscribe link may name (a kind, or all
# notification email, or the digest). Their defaults live in
# api.notification_*: in the inbox every kind is on, by email mentions and
# moderation notices are.
const my @EVENT_TYPES     => qw(reply mention moderation);
const my @TYPE_CHANNELS   => qw(in_app email);
const my %IS_EVENT_TYPE   => map { $_ => 1 } @EVENT_TYPES;
const my %IS_TYPE_CHANNEL => map { $_ => 1 } @TYPE_CHANNELS;
const my %IS_UNSUBSCRIBE_SCOPE => map { $_ => 1 } @EVENT_TYPES,
  'all', 'digest';
const my $UNSUBSCRIBE_AUDIT_ACTION => 'notification.email_unsubscribed';

has clock => sub { return GPForum::Service::Clock->new; };
__PACKAGE__->requires(qw(schema));
has functions => sub ($self) {
    return GPForum::Infrastructure::SqlFunction->for_schema( $self->schema );
};
has recorder => sub ($self) {
    return GPForum::Infrastructure::EventRecorder->new(
        schema => $self->schema );
};

# A preference already holding these values is skipped; any other is
# written. The preference is keyed by member and channel: a conflict on the
# insert is another request's row, which this write then replaces unless it
# already holds the same values.
sub set_preference ( $self, $input ) {
    my $refused = _refused_channel( $input->{channel} );
    if ($refused) {
        return $refused;
    }

    my $normalized = {
        channel          => $input->{channel},
        digest_frequency =>
          _safe_digest_frequency( $input->{digest_frequency} ),
        enabled => $input->{enabled} ? 1 : 0,
        user_id => $input->{user_id},
    };
    if ( $self->functions ) {
        return $self->functions->row(
            'notification_set_preference',
            {
                row =>
                  { %{$normalized}, updated_at => $self->clock->now_iso8601 }
            }
        )->{result};
    }
    my $existing = $self->_existing_preference($normalized);
    if ( !$existing ) {
        my ( $created, $error ) =
          GPForum::Infrastructure::UniqueConflict->attempt(
            $self->schema,
            sub {
                my $row =
                  { %{$normalized}, updated_at => $self->clock->now_iso8601 };
                $self->schema->resultset('NotificationPreference')
                  ->create($row);
                return $row;
            },
          );
        if ($created) {
            return $created;
        }
        $existing =
          GPForum::X::Conflict->caught($error)
          ? $self->_existing_preference($normalized)
          : undef;
        if ( !$existing ) {
            GPForum::Infrastructure::UniqueConflict->rethrow($error);
        }
    }

    my $enabled = _column( $existing, 'enabled' ) ? 1 : 0;
    my $digest  = _column( $existing, 'digest_frequency' ) || q{};
    if (   $enabled eq $normalized->{enabled}
        && $digest eq $normalized->{digest_frequency} )
    {
        return {
            channel          => _column( $existing, 'channel' ),
            digest_frequency => _column( $existing, 'digest_frequency' ),
            enabled          => $enabled,
            skipped          => 1,
            updated_at       => _column( $existing, 'updated_at' ),
            user_id          => _column( $existing, 'user_id' ),
        };
    }

    my $row = { %{$normalized}, updated_at => $self->clock->now_iso8601, };
    $self->schema->resultset('NotificationPreference')->update_or_create($row);

    return $row;
}

sub _existing_preference ( $self, $normalized ) {
    return $self->schema->resultset('NotificationPreference')->find(
        {
            channel => $normalized->{channel},
            user_id => $normalized->{user_id},
        }
    );
}

# Every channel is checked before any is written, so a refused request
# leaves the member's preferences as they were.
sub set_preferences ( $self, $input ) {
    my @preferences = @{ $input->{preferences} || [] };
    for my $preference (@preferences) {
        my $refused = _refused_channel( $preference->{channel} );
        if ($refused) {
            return $refused;
        }
    }

    for my $preference (@preferences) {
        $self->set_preference(
            {
                %{$preference}, user_id => $input->{user_id},
            }
        );
    }

    return $self->preferences_for_user( $input->{user_id} );
}

sub preferences_for_user ( $self, $user_id ) {
    my %stored;
    my $rows;
    if ( $self->functions ) {
        $rows = [
            map { GPForum::Infrastructure::ResultRow->from($_) } @{
                $self->functions->rows( 'notification_list_preferences',
                    { user_id => $user_id } )
            }
        ];
    }
    else {
        $rows = [
            _rows(
                $self->schema->resultset('NotificationPreference')
                  ->search_rs( { user_id => $user_id } )
            )
        ];
    }
    for my $row ( @{$rows} ) {
        my $channel = _column( $row, 'channel' );
        next if !_is_channel($channel);
        $stored{$channel} = {
            channel          => $channel,
            digest_frequency =>
              _safe_digest_frequency( _column( $row, 'digest_frequency' ) ),
            enabled => _column( $row, 'enabled' ) ? 1 : 0,
            user_id => _column( $row, 'user_id' ),
        };
    }

    my @preferences;
    for my $channel (@CHANNELS) {
        push @preferences,
          {
            %{ $CHANNEL_DEFAULTS{$channel} },
            %{ $stored{$channel} || {} },
            channel         => $channel,
            description_key => "notifications.preference.$channel.description",
            label_key       => "notifications.channel.$channel",
          };
    }

    return \@preferences;
}

sub channel_enabled ( $self, $user_id, $channel ) {
    my $safe_channel = _safe_channel($channel);
    for my $preference ( @{ $self->preferences_for_user($user_id) } ) {
        next if $preference->{channel} ne $safe_channel;

        return $preference->{enabled} ? 1 : 0;
    }

    return 1;
}

# Every kind on both channels, as the settings page shows them: one hash
# per kind with its i18n keys and its channels in order. A schema without
# the function layer (the in-memory doubles) reads the defaults.
sub type_preferences_for_user ( $self, $user_id ) {
    my $rows =
      $self->functions
      ? $self->functions->rows( 'notification_type_preferences',
        { user_id => $user_id } )
      : _default_type_rows();
    my %enabled =
      map { ( "$_->{event_type}:$_->{channel}" => $_->{enabled} ? 1 : 0 ) }
      @{$rows};

    return [ map { _kind( $_, \%enabled ) } @EVENT_TYPES ];
}

sub _kind ( $type, $enabled ) {
    return {
        event_type      => $type,
        label_key       => "notifications.kind.$type",
        description_key => "notifications.kind_description.$type",
        channels        => [
            map {
                +{
                    channel   => $_,
                    enabled   => $enabled->{"$type:$_"} // 0,
                    label_key => "notifications.channel.$_",
                }
            } @TYPE_CHANNELS
        ],
    };
}

# The defaults api.notification_type_preferences answers for a member with
# no stored row: every kind in the inbox, email for all but replies.
sub _default_type_rows {
    my @rows;
    for my $type (@EVENT_TYPES) {
        for my $channel (@TYPE_CHANNELS) {
            push @rows,
              {
                event_type => $type,
                channel    => $channel,
                enabled    => $channel eq 'in_app' || $type ne 'reply' ? 1 : 0,
              };
        }
    }

    return \@rows;
}

# The refusal for choices naming an unknown kind or channel, or undef.
sub refused_type_preferences ( $self, $preferences ) {
    return _invalid( 'preferences', 'type preferences must be a list' )
      if ref $preferences ne 'ARRAY';
    for my $preference ( @{$preferences} ) {
        return _invalid( 'event_type',
            'event_type must be one of ' . join q{, }, @EVENT_TYPES )
          if ref $preference ne 'HASH'
          || !exists $IS_EVENT_TYPE{ $preference->{event_type} // q{} };
        return _invalid( 'channel', 'channel must be one of ' . join q{, },
            @TYPE_CHANNELS )
          if !exists $IS_TYPE_CHANNEL{ $preference->{channel} // q{} };
    }

    return undef;
}

# Stores the member's choice for each kind and channel given. Answers ok
# with status ok or unchanged and how many changed, or the refusal.
sub set_type_preferences ( $self, $input ) {
    my $preferences = $input->{preferences};
    my $refused     = $self->refused_type_preferences($preferences);
    return $refused if $refused;

    my $functions = $self->functions
      // GPForum::X::Unavailable->throw( message =>
          'notification type preferences need the PostgreSQL function layer' );
    my $row = $functions->row(
        'notification_set_type_preferences',
        {
            user_id     => $input->{user_id},
            preferences => [
                map {
                    +{
                        event_type => $_->{event_type},
                        channel    => $_->{channel},
                        enabled    => $_->{enabled} ? true : false,
                    }
                } @{$preferences}
            ],
            now => $self->clock->now_iso8601,
        }
    ) || { status => 'not_found' };
    my $status = $row->{status} // 'not_found';
    return _invalid( 'preferences', 'type preferences were refused' )
      if $status eq 'invalid';
    return { ok => 0, status => $status } if $status eq 'not_found';

    return { ok => 1, status => $status, changed => 0 + $row->{changed} };
}

# Where a notification of this type goes for the member: in_app and email
# (1 or 0), the kind it belongs to, and the address and locale a mail is
# sent with. Without the function layer email is off and the inbox follows
# the in-app channel; a member the database does not hold gets the inbox
# only, as a member with no stored preference did.
sub delivery_plan ( $self, $user_id, $notification_type ) {
    if ( !$self->functions ) {
        return {
            in_app => $self->channel_enabled( $user_id, 'in_app' ),
            email  => 0,
        };
    }
    my $row = $self->functions->row(
        'notification_delivery_plan',
        {
            user_id           => $user_id,
            notification_type => $notification_type,
        }
    );
    return { in_app => 1, email => 0 } if !$row;

    return {
        event_type    => $row->{event_type},
        in_app        => $row->{in_app} ? 1 : 0,
        email         => $row->{email}  ? 1 : 0,
        email_address => $row->{email_address},
        locale        => $row->{locale},
    };
}

# The one-click unsubscribe: turns the scope's email off (a kind, or all
# notification email) and audits it. Answers ok with status ok or
# unchanged, or ok 0 with status invalid or not_found.
sub unsubscribe ( $self, $input ) {
    my $scope = $input->{scope} // q{};
    return { ok => 0, status => 'invalid' }
      if !exists $IS_UNSUBSCRIBE_SCOPE{$scope};

    my $functions = $self->functions // GPForum::X::Unavailable->throw(
        message => 'unsubscribing needs the PostgreSQL function layer' );
    my $audit = $self->recorder->audit_call(
        action      => $UNSUBSCRIBE_AUDIT_ACTION,
        actor_id    => $input->{user_id},
        target_type => 'user',
        target_id   => $input->{user_id},
        metadata    => {
            scope => $scope,
            via   => $input->{via} // 'link',
        },
    )->{audit};
    my $row = $functions->row(
        $scope eq 'digest'
        ? (
            'notification_digest_unsubscribe',
            {
                user_id => $input->{user_id},
                now     => $self->clock->now_iso8601,
                audit   => $audit,
            }
          )
        : (
            'notification_unsubscribe',
            {
                user_id => $input->{user_id},
                scope   => $scope,
                now     => $self->clock->now_iso8601,
                audit   => $audit,
            }
        )
      )
      || { status => 'not_found' };
    my $status = $row->{status} // 'not_found';
    return { ok => 0, status => $status }
      if $status ne 'ok' && $status ne 'unchanged';

    return { ok => 1, status => $status, scope => $scope };
}

sub event_types {
    return [@EVENT_TYPES];
}

sub type_channels {
    return [@TYPE_CHANNELS];
}

sub unsubscribe_scopes {
    return [ @EVENT_TYPES, 'all', 'digest' ];
}

# ADR 0078: whether a queued digest is still to be mailed, read as it is
# sent -- the digest and email channels on, an active account with a
# verified address -- with the address and locale. Without the function
# layer there is no digest.
sub digest_plan ( $self, $user_id ) {
    return { digest => 0 } if !$self->functions;
    my $row =
      $self->functions->row( 'notification_digest_plan',
        { user_id => $user_id } );
    return { digest => 0 } if !$row;

    return {
        digest        => $row->{digest} ? 1 : 0,
        frequency     => $row->{frequency},
        email_address => $row->{email_address},
        locale        => $row->{locale},
    };
}

sub _invalid ( $field, $message ) {
    return {
        error  => $message,
        errors => { $field => $message },
        ok     => 0,
        status => 'invalid',
    };
}

sub channel_names {
    return [@CHANNELS];
}

sub digest_frequency_options {
    return [
        map {
            +{
                label_key => 'notifications.digest_frequency.' . $_,
                value     => $_,
            }
        } @DIGEST_FREQUENCIES
    ];
}

# Read through the defaults, as channel_enabled is. Read from the stored
# rows alone, a member who never saved the settings form had no channel on,
# though every delivery treated in-app and email as on.
sub enabled_channels ( $self, $user_id ) {
    return map { $_->{channel} }
      grep { $_->{enabled} } @{ $self->preferences_for_user($user_id) };
}

# A misspelt channel was written as in_app: a request meant for email turned
# the member's in-app notifications off. It is refused instead, as invalid
# input, before anything is written.
sub _refused_channel ($channel) {
    if ( _is_channel($channel) ) {
        return undef;
    }

    my $message = 'channel must be one of ' . join q{, }, @CHANNELS;

    return {
        error  => $message,
        errors => { channel => $message },
        ok     => 0,
        status => 'invalid',
    };
}

sub _safe_channel ($channel) {
    return $channel if _is_channel($channel);

    return 'in_app';
}

sub _is_channel ($channel) {
    return grep { $_ eq ( $channel || q{} ) } @CHANNELS;
}

sub _safe_digest_frequency ($frequency) {
    for my $allowed (@DIGEST_FREQUENCIES) {
        return $allowed if defined $frequency && $frequency eq $allowed;
    }

    return 'daily';
}

sub _column ( $row, $column ) {
    return GPForum::Infrastructure::Row->column( $row, $column );
}

sub _rows ($search) {
    return $search->all       if $search->can('all');
    return @{ $search->rows } if $search->can('rows');

    return;
}

1;

__END__

=head1 NAME

GPForum::Service::Notification::PreferenceStore - A member's notification channel preferences.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $store = GPForum::Service::Notification::PreferenceStore->new(
        schema => $schema );
    $store->set_preference(
        {
            user_id          => $user_id,
            channel          => 'email',
            enabled          => 0,
            digest_frequency => 'daily',
        }
    );
    my $rows  = $store->preferences_for_user($user_id);
    my $email = $store->channel_enabled( $user_id, 'email' );

=head1 DESCRIPTION

One row per member and channel in C<notification_preferences>, for the three
channels C<in_app>, C<email> and C<digest>. A member with no row has the
defaults: in-app on and immediate, email on with a daily digest frequency,
digest off and daily. The settings page reads and writes through this store,
and the notification dispatcher asks it whether a channel is on.

A write names a known channel or is refused: an unknown channel is
answered with C<< { ok => 0, status => 'invalid', error, errors =>
{ channel } } >> and nothing is written, which the notification workflow
passes up as an invalid request (a 400 from the settings form). The rest of
the input is coerced: an unknown digest frequency is stored as C<daily>, and
C<enabled> as a boolean. A write that would store what is already stored is
skipped, and an insert that loses a race with a concurrent one for the same
member and channel falls back to the row that won.

=head1 SUBROUTINES/METHODS

=head2 set_preference

Takes a hash reference with C<user_id>, C<channel>, C<enabled> and
C<digest_frequency>, checked and coerced as above. Returns the refusal hash
reference when the channel is unknown; otherwise the hash reference written
(C<user_id>, C<channel>, C<enabled>, C<digest_frequency>, C<updated_at>), or,
when the stored row already says the same, that row's values with
C<< skipped => 1 >> and nothing written. A new row is inserted under a
savepoint.

=head2 set_preferences

Takes C<user_id> and C<preferences>, an array reference of hashes as for
L</set_preference> (the outer C<user_id> wins). When any of them names an
unknown channel, returns the refusal hash reference and writes none of
them. Otherwise applies each in order and returns L</preferences_for_user>
(an array reference) for that member.

=head2 preferences_for_user

Takes a user id and returns an array reference with one hash per channel, in
the order C<in_app>, C<email>, C<digest>: C<channel>, C<enabled>,
C<digest_frequency>, C<user_id> (only when a row is stored), and the i18n
keys C<label_key> and C<description_key>. Stored values override the
defaults; a stored row for an unknown channel is ignored, and an unknown
stored frequency reads as C<daily>.

=head2 channel_enabled

Takes a user id and a channel (unknown reads as C<in_app>) and returns 1 or
0, from the stored row or the channel's default.

=head2 channel_names

Returns an array reference of the channel names. Needs no instance.

=head2 digest_frequency_options

Returns an array reference of C<< { value, label_key } >> for C<immediate>,
C<daily>, C<weekly> and C<never>. Needs no instance.

=head2 enabled_channels

Takes a user id and returns a list of the channel names that are on for the
member, in the order of L</preferences_for_user> and with its defaults: a
member with no stored rows gets C<in_app> and C<email>.

=head2 type_preferences_for_user

ADR 0078. Takes a user id and returns an array reference with one hash per
kind of notification (C<reply>, C<mention>, C<moderation>): C<event_type>,
C<label_key>, C<description_key> and C<channels>, an array reference of
C<< { channel, enabled, label_key } >> for C<in_app> and C<email>, stored
or by default. Without the function layer, the defaults.

=head2 refused_type_preferences

Takes an array reference of C<< { event_type, channel, enabled } >> and
returns the C<invalid> refusal for one naming an unknown kind or channel
(or for what is not a list), or undef.

=head2 set_type_preferences

Takes C<user_id> and C<preferences> as above and stores them through
C<api.notification_set_type_preferences>: C<< { ok => 1, status => 'ok' |
'unchanged', changed } >>, the refusal, or C<< { ok => 0, status =>
'not_found' } >> for a member who is gone.

=head2 delivery_plan

Takes a user id and a notification type and returns C<in_app> and C<email>
(1 or 0), the kind (C<event_type>, undef for a type no control covers),
and the C<email_address> and C<locale> a mail goes out with. Email needs
the email channel and the kind's email on and an active account with a
verified address. Without the function layer, C<in_app> follows the
channel and C<email> is 0; a member the database does not hold gets the
inbox only.

=head2 unsubscribe

Takes C<user_id>, C<scope> (a kind, C<all> for the email channel, or
C<digest> for the digest channel) and C<via> (C<link> or C<one_click>) and turns that email off, audited as
C<notification.email_unsubscribed>. Returns C<< { ok => 1, status => 'ok'
| 'unchanged', scope } >> or C<< { ok => 0, status => 'invalid' |
'not_found' } >>.

=head2 event_types

The kinds, as an array reference. Needs no instance.

=head2 type_channels

The channels a kind is switched on, as an array reference.

=head2 unsubscribe_scopes

The scopes an unsubscribe may name: the kinds, C<all> and C<digest>.

=head2 digest_plan

Takes a user id. Returns C<< { digest, frequency, email_address, locale } >>
from C<api.notification_digest_plan>: C<digest> is 1 while a digest is
still to be mailed to the member (ADR 0078); without the function layer,
C<< { digest => 0 } >>.

=head1 DIAGNOSTICS

L</set_type_preferences> and L</unsubscribe> throw
L<GPForum::X::Unavailable> without the function layer.

An unknown channel is not raised: L</set_preference> and
L</set_preferences> return C<< { ok => 0, status => 'invalid' } >> with
C<error> and C<< errors => { channel } >> saying
C<channel must be one of in_app, email, digest>. L</set_preference> rethrows
an insert error that is not a unique conflict, and a unique conflict after
which no row can be found. Other database errors propagate.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Infrastructure::Row>,
L<GPForum::Infrastructure::UniqueConflict>, L<GPForum::X::Conflict>,
L<GPForum::Service::Clock>, L<GPForum::Infrastructure::EventRecorder> (the
unsubscribe's audit), L<GPForum::X::Unavailable>.

Extends L<GPForum::Base>: built without C<schema> it throws
L<GPForum::X::Argument>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

L</channel_enabled> still reads an unknown channel as C<in_app>. Nothing in
F<lib/> calls L</enabled_channels>.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause
license.

=cut
