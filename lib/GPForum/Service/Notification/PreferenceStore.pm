# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Notification::PreferenceStore;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -async_await;
use v5.40;

use Mojo::JSON qw(false true);

use GPForum::Infrastructure::EventRecorder;
use GPForum::Infrastructure::ResultRow;
use GPForum::Infrastructure::Row qw(column_of);
use GPForum::Infrastructure::SqlFunction;
use GPForum::Service::Clock;
use GPForum::X::Unavailable;

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
# api.notification_*: in the inbox every kind is on, by email mentions,
# moderation notices and direct messages (ADR 0139) are.
const my @EVENT_TYPES     => qw(reply mention moderation message);
const my @TYPE_CHANNELS   => qw(in_app email);
const my %IS_EVENT_TYPE   => map { $_ => 1 } @EVENT_TYPES;
const my %IS_TYPE_CHANNEL => map { $_ => 1 } @TYPE_CHANNELS;

# What an unsubscribe link may name: one kind, every one, or the digest --
# the one list the store checks a link against and unsubscribe_scopes gives.
const my @UNSUBSCRIBE_SCOPES       => ( @EVENT_TYPES, qw(all digest) );
const my %IS_UNSUBSCRIBE_SCOPE     => map { $_ => 1 } @UNSUBSCRIBE_SCOPES;
const my $UNSUBSCRIBE_AUDIT_ACTION => 'notification.email_unsubscribed';

has clock => sub { return GPForum::Service::Clock->new; };
__PACKAGE__->requires(qw(schema));
has functions => \&GPForum::Infrastructure::SqlFunction::for_service;
has recorder  => sub ($self) {
    return GPForum::Infrastructure::EventRecorder->new(
        schema => $self->schema );
};

# Each operation is written once, as its promise method (ADR 0177).
GPForum::Infrastructure::SqlFunction->blocking_twins(
    qw(set_preference set_preferences preferences_for_user channel_enabled
      type_preferences_for_user set_type_preferences delivery_plan
      unsubscribe digest_plan claim_digest_send release_digest_send)
);

# One channel's preference, through api.notification_set_preference: a
# preference already holding these values is skipped, any other written,
# and a concurrent insert for the same member and channel is the row this
# write then replaces. On $scope when a command log's transaction gives one.
async sub set_preference_p ( $self, $input, $context = undef, $scope = undef ) {
    my $refused = _refused_channel( $input->{channel} );
    return $refused if $refused;

    $scope //= $self->_functions;
    my $row = await $scope->row_p(
        'notification_set_preference',
        {
            row => {
                %{ _normalized_preference($input) },
                updated_at => $self->clock->now_iso8601,
            }
        },
        $context
    );
    return $row->{result};
}

sub _normalized_preference ($input) {
    return {
        channel          => $input->{channel},
        digest_frequency =>
          _safe_digest_frequency( $input->{digest_frequency} ),
        enabled => $input->{enabled} ? 1 : 0,
        user_id => $input->{user_id},
    };
}

# Every channel is checked before any is written, so a refused request
# leaves the member's preferences as they were. On $scope: the transaction
# a command log runs it in.
async sub set_preferences_p ( $self, $input, $context = undef, $scope = undef )
{
    my @preferences = @{ $input->{preferences} || [] };
    my $refused     = _refused_channels( \@preferences );
    return $refused if $refused;
    $scope //= $self->_functions;

    for my $preference (@preferences) {
        await $self->set_preference_p(
            { %{$preference}, user_id => $input->{user_id} },
            $context, $scope );
    }

    return _preferences_from_rows(
        await $scope->rows_p(
            'notification_list_preferences', { user_id => $input->{user_id} },
            $context
        )
    );
}

sub _refused_channels ($preferences) {
    for my $preference ( @{$preferences} ) {
        my $refused = _refused_channel( $preference->{channel} );
        return $refused if $refused;
    }

    return undef;
}

sub _preferences_from_rows ($rows) {
    return _preferences(
        [ map { GPForum::Infrastructure::ResultRow->from($_) } @{$rows} ] );
}

async sub preferences_for_user_p ( $self, $user_id, $context = undef ) {
    return _preferences_from_rows(
        await $self->_functions->rows_p(
            'notification_list_preferences', { user_id => $user_id },
            $context
        )
    );
}

sub _preferences ($rows) {
    my %stored;
    for my $row ( @{$rows} ) {
        my $channel = column_of( $row, 'channel' );
        next if !_is_channel($channel);
        $stored{$channel} = {
            channel          => $channel,
            digest_frequency =>
              _safe_digest_frequency( column_of( $row, 'digest_frequency' ) ),
            enabled => column_of( $row, 'enabled' ) ? 1 : 0,
            user_id => column_of( $row, 'user_id' ),
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

async sub channel_enabled_p ( $self, $user_id, $channel, $context = undef ) {
    my $safe_channel = _safe_channel($channel);
    for my $preference (
        @{ await $self->preferences_for_user_p( $user_id, $context ) } )
    {
        next if $preference->{channel} ne $safe_channel;

        return $preference->{enabled} ? 1 : 0;
    }

    return 1;
}

# Every kind on both channels, as the settings page shows them: one hash
# per kind with its i18n keys and its channels in order.
async sub type_preferences_for_user_p ( $self, $user_id, $context = undef ) {
    return _type_preferences(
        await $self->_functions->rows_p(
            'notification_type_preferences', { user_id => $user_id },
            $context
        )
    );
}

sub _type_preferences ($rows) {
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
# with status ok or unchanged and how many changed, or the refusal. On
# $scope: the transaction a command log runs it in.
async sub set_type_preferences_p ( $self, $input, $context = undef,
    $scope = undef )
{
    my $refused = $self->refused_type_preferences( $input->{preferences} );
    return $refused if $refused;

    $scope //= $self->_functions;
    return _type_preferences_answer(
        await $scope->row_p(
            'notification_set_type_preferences',
            $self->_type_preference_values($input),
            $context
        )
    );
}

sub _type_preference_values ( $self, $input ) {
    return {
        user_id     => $input->{user_id},
        preferences => [
            map {
                +{
                    event_type => $_->{event_type},
                    channel    => $_->{channel},
                    enabled    => $_->{enabled} ? true : false,
                }
            } @{ $input->{preferences} }
        ],
        now => $self->clock->now_iso8601,
    };
}

sub _type_preferences_answer ($row) {
    $row ||= { status => 'not_found' };
    my $status = $row->{status} // 'not_found';
    return _invalid( 'preferences', 'type preferences were refused' )
      if $status eq 'invalid';
    return { ok => 0, status => $status } if $status eq 'not_found';

    return { ok => 1, status => $status, changed => 0 + $row->{changed} };
}

# Where a notification of this type goes for the member: in_app and email
# (1 or 0), the kind it belongs to, and the address and locale a mail is
# sent with. A member the database does not hold gets the inbox only, as a
# member with no stored preference did. On the call layer of the
# transaction the store was joined to, when it was.
async sub delivery_plan_p ( $self, $user_id, $notification_type,
    $context = undef )
{
    return _delivery_plan(
        await $self->_functions->row_p(
            'notification_delivery_plan',
            {
                user_id           => $user_id,
                notification_type => $notification_type,
            },
            $context
        )
    );
}

sub _delivery_plan ($row) {
    return { in_app => 1, email => 0 } if !$row;

    return {
        (
            exists $row->{web_push}
            ? ( web_push => $row->{web_push} ? 1 : 0 )
            : ()
        ),
        event_type    => $row->{event_type},
        in_app        => $row->{in_app} ? 1 : 0,
        email         => $row->{email}  ? 1 : 0,
        email_address => $row->{email_address},
        locale        => $row->{locale},
    };
}

# The one-click unsubscribe: turns the scope's email off (a kind, or all
# notification email) and audits it. Answers ok with status ok or
# unchanged, or ok 0 with status invalid or not_found. An unknown scope is
# refused before anything is asked.
async sub unsubscribe_p ( $self, $input, $context = undef ) {
    my $scope = $input->{scope} // q{};
    return { ok => 0, status => 'invalid' }
      if !exists $IS_UNSUBSCRIBE_SCOPE{$scope};

    return _unsubscribe_answer(
        $scope,
        await $self->_functions->row_p(
            $self->_unsubscribe_call($input), $context
        )
    );
}

# The function an unsubscribe calls and its values, the audit row built
# here as every audited write builds it.
sub _unsubscribe_call ( $self, $input ) {
    my $scope = $input->{scope};
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
    return $scope eq 'digest'
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
      );
}

sub _unsubscribe_answer ( $scope, $row ) {
    my $status = ( $row || {} )->{status} // 'not_found';
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
    return [@UNSUBSCRIBE_SCOPES];
}

# ADR 0078: whether a queued digest is still to be mailed, read as it is
# sent -- the digest and email channels on, an active account with a
# verified address, not suspended -- with the address and locale.
async sub digest_plan_p ( $self, $user_id, $context = undef ) {
    my $row = await $self->_functions->row_p( 'notification_digest_plan',
        { user_id => $user_id, now => $self->clock->now_iso8601 }, $context );
    return { digest => 0 } if !$row;

    return {
        digest        => $row->{digest} ? 1 : 0,
        frequency     => $row->{frequency},
        email_address => $row->{email_address},
        locale        => $row->{locale},
    };
}

# ADR 0078: a queued digest is mailed at most once. The worker claims it
# before the transport takes it (claimed, or sent when a delivery before
# took it, missing, invalid) and gives the claim back when the transport
# refuses it.
async sub claim_digest_send_p ( $self, $digest, $context = undef ) {
    my $row = await $self->_functions->row_p(
        'notification_digest_claim',
        {
            %{$digest}{qw(user_id frequency period_start event_id)},
            now => $self->clock->now_iso8601,
        },
        $context
    );

    return { status => $row ? $row->{status} : 'missing' };
}

async sub release_digest_send_p ( $self, $digest, $context = undef ) {
    my $row = await $self->_functions->row_p( 'notification_digest_release',
        { %{$digest}{qw(user_id frequency period_start event_id)} }, $context );

    return { status => $row ? $row->{status} : 'unchanged' };
}

sub _functions ($self) {
    return $self->functions // GPForum::X::Unavailable->throw( message =>
          'notification preferences need the PostgreSQL function layer' );
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
member and channel falls back to the row that won
(C<api.notification_set_preference>).

Each operation is written once, as its promise method, against the
PostgreSQL function layer; the blocking methods are its twins (ADR 0177).
There is no fallback: without the function layer a call raises
L<GPForum::X::Unavailable>.

=head1 SUBROUTINES/METHODS

Every C<_p> method takes an optional query context after its arguments;
the writes a command log runs take an optional call layer after it, the
transaction to write in.

=head2 set_preference_p

Takes a hash reference with C<user_id>, C<channel>, C<enabled> and
C<digest_frequency>, checked and coerced as above. Answers the refusal hash
reference when the channel is unknown; otherwise the hash reference written
(C<user_id>, C<channel>, C<enabled>, C<digest_frequency>, C<updated_at>), or,
when the stored row already says the same, that row's values with
C<< skipped => 1 >> and nothing written.

=head2 set_preferences_p

Takes C<user_id> and C<preferences>, an array reference of hashes as for
L</set_preference_p> (the outer C<user_id> wins). When any of them names an
unknown channel, answers the refusal hash reference and writes none of
them. Otherwise applies each in order and answers the member's preferences
as L</preferences_for_user_p> reads them.

=head2 preferences_for_user_p

Takes a user id and answers an array reference with one hash per channel,
in the order C<in_app>, C<email>, C<digest>: C<channel>, C<enabled>,
C<digest_frequency>, C<user_id> (only when a row is stored), and the i18n
keys C<label_key> and C<description_key>. Stored values override the
defaults; a stored row for an unknown channel is ignored, and an unknown
stored frequency reads as C<daily>.

=head2 channel_enabled_p

Takes a user id and a channel (unknown reads as C<in_app>) and answers 1 or
0, from the stored row or the channel's default.

=head2 type_preferences_for_user_p

ADR 0078. Takes a user id and answers an array reference with one hash per
kind of notification (C<reply>, C<mention>, C<moderation>, C<message>):
C<event_type>, C<label_key>, C<description_key> and C<channels>, an array
reference of C<< { channel, enabled, label_key } >> for C<in_app> and
C<email>, stored or by default.

=head2 set_type_preferences_p

Takes C<user_id> and C<preferences> as above and stores them through
C<api.notification_set_type_preferences>: C<< { ok => 1, status => 'ok' |
'unchanged', changed } >>, the refusal of L</refused_type_preferences>, or
C<< { ok => 0, status => 'not_found' } >> for a member who is gone.

=head2 delivery_plan_p

Takes a user id and a notification type and answers C<in_app> and C<email>
(1 or 0), the kind (C<event_type>, undef for a type no control covers),
and the C<email_address> and C<locale> a mail goes out with. Email needs
the email channel and the kind's email on and an active account with a
verified address. A member the database does not hold gets the inbox only.
Read on a transaction's call layer when the store was built with that
layer as its C<functions>.

=head2 unsubscribe_p

Takes C<user_id>, C<scope> (a kind, C<all> for the email channel, or
C<digest> for the digest channel) and C<via> (C<link> or C<one_click>) and
turns that email off, audited as C<notification.email_unsubscribed>.
Answers C<< { ok => 1, status => 'ok' | 'unchanged', scope } >> or
C<< { ok => 0, status => 'invalid' | 'not_found' } >>; an unknown scope is
invalid before anything is asked.

=head2 digest_plan_p

Takes a user id. Answers C<< { digest, frequency, email_address, locale } >>
from C<api.notification_digest_plan>: C<digest> is 1 while a digest is
still to be mailed to the member (ADR 0078).

=head2 claim_digest_send_p

Takes C<< { user_id, frequency, period_start, event_id } >> of a queued
digest. Answers C<< { status } >> from C<api.notification_digest_claim>:
C<claimed> the first time, C<sent> when a delivery before claimed it,
C<missing> or C<invalid>.

=head2 release_digest_send_p

Takes the same digest. Gives its claim back (C<released>, or
C<unchanged>) after the transport refused the mail.

=head2 set_preference, set_preferences, preferences_for_user, channel_enabled, type_preferences_for_user, set_type_preferences, delivery_plan, unsubscribe, digest_plan, claim_digest_send, release_digest_send

The blocking twins: each is its C<_p> method run on the blocking call layer
(ADR 0177), answering the value instead of a promise.

=head2 enabled_channels

Takes a user id and returns a list of the channel names that are on for the
member, in the order of L</preferences_for_user_p> and with its defaults: a
member with no stored rows gets C<in_app> and C<email>.

=head2 refused_type_preferences

Takes an array reference of C<< { event_type, channel, enabled } >> and
returns the C<invalid> refusal for one naming an unknown kind or channel
(or for what is not a list), or undef.

=head2 channel_names

Returns an array reference of the channel names. Needs no instance.

=head2 digest_frequency_options

Returns an array reference of C<< { value, label_key } >> for C<immediate>,
C<daily>, C<weekly> and C<never>. Needs no instance.

=head2 event_types

The kinds, as an array reference. Needs no instance.

=head2 type_channels

The channels a kind is switched on, as an array reference.

=head2 unsubscribe_scopes

The scopes an unsubscribe may name: the kinds, C<all> and C<digest>.

=head1 DIAGNOSTICS

Without the PostgreSQL function layer every read and write raises
L<GPForum::X::Unavailable>; the refusals below are answered before the
layer is asked.

An unknown channel is not raised: L</set_preference_p> and
L</set_preferences_p> answer C<< { ok => 0, status => 'invalid' } >> with
C<error> and C<< errors => { channel } >> saying
C<channel must be one of in_app, email, digest>. Database errors
propagate.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Infrastructure::SqlFunction>, L<GPForum::Infrastructure::Row>,
L<GPForum::Infrastructure::ResultRow>, L<GPForum::Service::Clock>,
L<GPForum::Infrastructure::EventRecorder> (the unsubscribe's audit),
L<GPForum::X::Unavailable>.

Extends L<GPForum::Base>: built without C<schema> it throws
L<GPForum::X::Argument>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

L</channel_enabled_p> still reads an unknown channel as C<in_app>. Nothing in
F<lib/> calls L</enabled_channels>.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
