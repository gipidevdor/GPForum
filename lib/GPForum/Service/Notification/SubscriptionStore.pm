# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Notification::SubscriptionStore;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -async_await;
use v5.40;

use GPForum::Infrastructure::Id;
use GPForum::Infrastructure::ResultRow;
use GPForum::Infrastructure::Row qw(column_of);
use GPForum::Infrastructure::SqlFunction;
use GPForum::Service::Clock;
use GPForum::X::Unavailable;

our $VERSION = '0.001';

const my $DEFAULT_PREFERENCE => 'all';

has clock      => sub { return GPForum::Service::Clock->new; };
has id_service => sub { return GPForum::Infrastructure::Id->new; };
__PACKAGE__->requires(qw(schema));
has functions => \&GPForum::Infrastructure::SqlFunction::for_service;

# Each read is written once, as its promise method (ADR 0177). A
# subscription is written by api.community_subscribe_command and
# api.community_target_command (Community::Workflow), with the row
# new_subscription_row draws.
GPForum::Infrastructure::SqlFunction->blocking_twins(
    qw(find_for_user_target status_for_user_target subscribers_list));

# The member's subscription to the target, revoked or not.
async sub find_for_user_target_p ( $self, $user_id, $target_type, $target_id,
    $context = undef )
{
    return GPForum::Infrastructure::ResultRow->from(
        await $self->_functions->row_p(
            @{ $self->find_call( $user_id, $target_type, $target_id ) },
            $context
        )
    );
}

# The call find_for_user_target_p makes: a page that reads the
# subscription with its other reads in one statement
# (Service::Forum::ThreadPageReads) answers it.
sub find_call ( $, $user_id, $target_type, $target_id ) {
    return [
        'notification_find_subscription',
        {
            user_id     => $user_id,
            target_type => $target_type,
            target_id   => $target_id,
        }
    ];
}

# Whether the member is subscribed to the target, muted or not.
async sub status_for_user_target_p ( $self, $user_id, $target_type,
    $target_id, $context = undef )
{
    return { subscribed => 0, muted => 0 } if !$user_id;
    my $subscription =
      await $self->find_for_user_target_p( $user_id, $target_type,
        $target_id, $context );
    return { subscribed => 0, muted => 0 }
      if !$subscription || defined column_of( $subscription, 'revoked_at' );

    return {
        subscribed => 1,
        muted      => defined column_of( $subscription, 'muted_at' ) ? 1 : 0,
        subscription_id => column_of( $subscription, 'subscription_id' ),
        preference      => column_of( $subscription, 'preference' ),
    };
}

# The members subscribed to the target, not muted, whose preference lets a
# notification of this type through.
async sub subscribers_list_p (
    $self, $target_type, $target_id,
    $options = undef,
    $context = undef
  )
{
    my $rows = await $self->_functions->rows_p(
        'notification_subscribers',
        {
            target_type       => $target_type,
            target_id         => $target_id,
            notification_type => $options
            ? $options->{notification_type}
            : undef
        },
        $context
    );
    return [ map { $_->{user_id} } @{$rows} ];
}

# The same members as a list.
sub subscribers_for ( $self, @arguments ) {
    return @{ $self->subscribers_list(@arguments) };
}

# The row api.community_subscribe_command saves: a new id, the request and
# the time.
sub new_subscription_row ( $self, $input ) {
    return {
        subscription_id => $self->id_service->uuid,
        user_id         => $input->{user_id},
        target_type     => $input->{target_type},
        target_id       => $input->{target_id},
        preference      => $input->{preference} || $DEFAULT_PREFERENCE,
        created_at      => $self->clock->now_iso8601,
        muted_at        => undef,
        revoked_at      => undef
    };
}

sub _functions ($self) {
    return $self->functions // GPForum::X::Unavailable->throw(
        message => 'subscriptions need the PostgreSQL function layer' );
}

1;

__END__

=head1 NAME

GPForum::Service::Notification::SubscriptionStore - Saves, mutes and revokes a member's subscriptions and lists a target's subscribers.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $store = GPForum::Service::Notification::SubscriptionStore->new(
        schema => $schema,
    );
    my $status = $store->status_for_user_target( $user_id, 'thread', $thread_id );
    my @user_ids = $store->subscribers_for( 'thread', $thread_id,
        { notification_type => 'reply' } );

=head1 DESCRIPTION

A member has at most one C<subscriptions> row per target. Muting stamps
C<muted_at> and revoking (unsubscribing) stamps C<revoked_at>; neither
deletes the row, and subscribing again clears both and sets the new
C<preference> on the same row. Those are one call each with the command log
(C<api.community_subscribe_command>, C<api.community_target_command>), made
by L<GPForum::Service::Community::Workflow> with the row
L</new_subscription_row> draws; this store reads.

The C<preference> is C<all> (the default), C<mentions> or C<none>, as the
table's check constraint allows. The subscribers listed honour it: C<all>
receives everything, C<none> nothing, and any other value only
notifications of type C<mention>. Each read is written once, as its promise
method; the blocking methods are its twins (ADR 0177).

=head1 SUBROUTINES/METHODS

=head2 new_subscription_row

Takes C<user_id>, C<target_type>, C<target_id> and C<preference> (C<all>
when omitted). Returns the row C<api.community_subscribe_command> saves: a
new id, the request, the time, neither muted nor revoked.

=head2 find_for_user_target_p

Takes a user id, a target type and a target id, and an optional query
context. Answers that member's subscription row for the target, whatever
its state, or undef.

=head2 find_call

Takes what L</find_for_user_target_p> takes; answers the call it makes, the
function's catalogue name and its values. The class answers it too.

=head2 status_for_user_target_p

Takes a user id, a target type and a target id, and an optional query
context. Answers C<< { subscribed => 0, muted => 0 } >> when there is no
user id, no row or a revoked one; otherwise C<< subscribed => 1 >>,
C<muted> (1 when C<muted_at> is set), C<subscription_id> and C<preference>.

=head2 subscribers_list_p

Takes a target type, a target id, an optional hash reference with
C<notification_type> and an optional query context. Answers an array
reference of the user ids subscribed to the target, neither muted nor
revoked, whose preference allows that notification type. Without a
C<notification_type> only C<all> subscribers are listed.

=head2 subscribers_for

The user ids C<subscribers_list> answers, as a list.

=head2 find_for_user_target, status_for_user_target, subscribers_list

The blocking twins: each is its C<_p> method run on the blocking call layer
(ADR 0177), answering the value instead of a promise.

=head1 DIAGNOSTICS

Database errors propagate. Without the PostgreSQL function layer every read
raises L<GPForum::X::Unavailable>.

=head1 CONFIGURATION AND ENVIRONMENT

None. C<clock> and C<id_service> default to L<GPForum::Service::Clock> and
L<GPForum::Infrastructure::Id>, which draw the row a subscription command
writes; tests pass fixed ones.

=head1 DEPENDENCIES

L<Const::Fast>, L<GPForum::Base>, L<GPForum::Infrastructure::Id>,
L<GPForum::Infrastructure::Row>, L<GPForum::Infrastructure::SqlFunction>,
L<GPForum::X::Unavailable>, L<GPForum::Service::Clock>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

The preference is not validated here; a value outside the check
constraint fails at the database.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
