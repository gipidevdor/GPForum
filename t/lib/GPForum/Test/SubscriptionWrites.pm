# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Test::SubscriptionWrites;

use Mojo::Base -base, -signatures;
use v5.40;

use GPForum::X::Conflict;

our $VERSION = '0.001';

# A subscription's write alone, without a command log: the store steps
# api.notification_save_subscription and
# api.notification_stamp_subscription, with the row the store draws
# (ADR 0126). Members subscribe through api.community_subscribe_command
# (Community::Workflow); a test that reaches the store step -- a restore, a
# race on the target, a mute -- calls it here.
has store => undef;    # a Notification::SubscriptionStore on PostgreSQL

# The member's subscription to the target, restored when there was one.
sub save_subscription ( $self, $input ) {
    return $self->_saved( $input, 1 );
}

# A new subscription, with no look for an existing one.
sub subscribe ( $self, $input ) {
    return $self->_saved( $input, 0 );
}

sub mute ( $self, $subscription_id ) {
    return $self->_stamped( $subscription_id, undef, 'muted_at' );
}

sub revoke ( $self, $subscription_id ) {
    return $self->_stamped( $subscription_id, undef, 'revoked_at' );
}

sub mute_for_user_target ( $self, $input ) {
    return $self->_stamped( undef, $input, 'muted_at' );
}

sub revoke_for_user_target ( $self, $input ) {
    return $self->_stamped( undef, $input, 'revoked_at' );
}

# A minted id another subscription holds is minted once more.
sub _saved ( $self, $input, $restore ) {
    my $store  = $self->store;
    my $row    = $store->new_subscription_row($input);
    my $result = $self->_save( $row, $restore );
    return $result if !$result->{retry_id};

    $row->{subscription_id} = $store->id_service->uuid;
    $result = $self->_save( $row, $restore );
    if ( $result->{retry_id} ) {
        GPForum::X::Conflict->throw(
            message => 'the replacement id is already stored' );
    }

    return $result;
}

sub _save ( $self, $row, $restore ) {
    return $self->store->functions->row(
        'notification_save_subscription',
        { row => $row, restore => $restore }
    )->{result};
}

sub _stamped ( $self, $id, $input, $column ) {
    my $store = $self->store;
    return $store->functions->row(
        'notification_stamp_subscription',
        {
            id          => $id,
            by_target   => $input ? 1                     : 0,
            user_id     => $input ? $input->{user_id}     : undef,
            target_type => $input ? $input->{target_type} : undef,
            target_id   => $input ? $input->{target_id}   : undef,
            column      => $column,
            stamped_at  => $store->clock->now_iso8601,
        }
    )->{result};
}

1;

__END__

=head1 NAME

GPForum::Test::SubscriptionWrites - A subscription's write alone, through its store steps.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $subscriptions = GPForum::Test::SubscriptionWrites->new(
        store => GPForum::Service::Notification::SubscriptionStore->new(
            schema => $schema ) );
    $subscriptions->save_subscription(
        { user_id => $user, target_type => 'thread', target_id => $thread } );

=head1 DESCRIPTION

Calls C<api.notification_save_subscription> and
C<api.notification_stamp_subscription> with a
L<GPForum::Service::Notification::SubscriptionStore>'s row and clock: the
writes the subscription commands run, without their command log.

=head1 SUBROUTINES/METHODS

=head2 store

The subscription store, on PostgreSQL.

=head2 save_subscription

Saves the member's subscription to the target, restoring the one there was.

=head2 subscribe

Inserts a new subscription without restoring one.

=head2 mute, revoke

Stamp a subscription, by its id, muted or revoked.

=head2 mute_for_user_target, revoke_for_user_target

The same, by the member and the target.

=head1 DIAGNOSTICS

A replacement id that collides too throws L<GPForum::X::Conflict>; the
function's errors propagate.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<Mojo::Base>, L<GPForum::X::Conflict>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

None known.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
