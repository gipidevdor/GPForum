# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Realtime::SubscriptionPolicy;

use Const::Fast;
use Mojo::Base -base, -signatures, -async_await;
use v5.40;

use GPForum::Infrastructure::SqlFunction;
use GPForum::Infrastructure::ResultRow;
use GPForum::X::Unavailable;

our $VERSION = '0.001';
has functions => \&GPForum::Infrastructure::SqlFunction::for_service;

const my $ACTION_SUBSCRIBE => 'realtime.subscribe';
const my $STATUS_ACTIVE    => 'active';

has permission_gate => undef; # optional: without one roles grant nothing
has readability     => undef; # optional: without one threads are invisible
has schema          => undef; # optional: without one account status is not read
has suspension_store => undef;  # optional: without one suspensions are not read

# A decision is written once, as its promise method (ADR 0177); permits is
# its blocking twin, the services it asks blocking with it.
GPForum::Infrastructure::SqlFunction->blocking_twins('permits');
GPForum::Infrastructure::SqlFunction->blocking_parts(
    qw(permission_gate readability suspension_store));

# Named `permits` rather than `can`, which would override UNIVERSAL::can.
# actor, action, resource and context are the authorization question;
# collapsing them into one hashref would hide which of them a caller forgot.
# The subscription context is the socket's, not a query context: queries run
# without the request's statistics token. The account and the channel are
# read together, one round trip for a subscription instead of three; the
# account still answers first, and a channel read that failed is thrown
# only for an account that passed, as when it was read after it.
async sub permits_p ( $self, $actor, $action, $resource, $context ) {
    my $refused = _refused( $actor, $action );
    return $refused if $refused;

    # Both reads start before either is awaited. Mojo::Promise->all would
    # settle a tick later, which a blocking caller cannot wait for.
    my $account = $self->_actor_account_status_p($actor);
    my $channel = $self->_channel_decision_p( $actor, $resource );
    $channel->catch( sub { return; } );
    my $answer = await $account;
    return $answer if !$answer->{ok};

    return await $channel;
}

async sub _channel_decision_p ( $self, $actor, $resource ) {
    my $type = $resource->{type} || q{};
    return await $self->_can_thread_p( $actor, $resource ) if $type eq 'thread';
    return await $self->_can_privileged_channel_p( $actor, $resource )
      if $type eq 'admin' || $type eq 'moderation';
    return $self->_can_feed( $actor, $resource ) if $type eq 'feed';

    return _deny('unknown_channel');
}

sub _refused ( $actor, $action ) {
    return _deny('forbidden')               if $action ne $ACTION_SUBSCRIBE;
    return _deny('authentication_required') if !_user_id($actor);
    return undef;
}

# ADR 0102: a thread channel is open to whoever can read the thread -- its
# space, category and thread, live and not hidden -- as every other surface
# judges it. The old check ignored the space, shut members out of
# members-only threads, and trusted a resource_acl table nothing writes.
async sub _can_thread_p ( $self, $actor, $resource ) {
    return _deny('invisible_resource') if !$self->readability;

    return (
        await $self->readability->readable_by_p(
            _user_id($actor), 'thread', $resource->{id}
        )
      )
      ? _allow('thread_readable')
      : _deny('invisible_resource');
}

async sub _can_privileged_channel_p ( $self, $actor, $resource ) {
    my $permission = _privileged_permission($resource);
    return _deny('forbidden') if !$permission;
    my $gate = $self->permission_gate;
    return _deny('forbidden') if !$gate;

    return ( await $gate->allowed_p( $actor, $permission ) )
      ? _allow('permission_allowed')
      : _deny('forbidden');
}

sub _privileged_permission ($resource) {
    my %permission_for = (
        admin      => { resource_type => 'admin',      action => 'view' },
        moderation => { resource_type => 'moderation', action => 'review' },
    );
    return $permission_for{ $resource->{type} };
}

sub _can_feed ( $self, $actor, $resource ) {
    return _allow('own_feed')
      if $resource->{id} eq _user_id($actor)
      || $resource->{id} eq 'personal';

    return _deny('forbidden');
}

# The suspension and the user are read together; the suspension's denial
# answers first, as when it was read before the user.
async sub _actor_account_status_p ( $self, $actor ) {
    my $suspended = $self->_suspended_p( _user_id($actor) );
    my $account   = $self->_account_p($actor);
    $account->catch( sub { return; } );
    my $denied = await $suspended;

    return $denied // await $account;
}

# The denial a suspension store gives, or undef: no store, or one that lets
# the member participate. It fails closed. A suspension store that errors
# or answers nothing is not an answer that the member may participate: a
# failure was ignored, so a suspended member could subscribe whenever the
# store was unreachable.
async sub _suspended_p ( $self, $user_id ) {
    my $store = $self->suspension_store or return undef;
    my $decision;
    try {
        $decision = await $store->can_participate_p($user_id);
    }
    catch ($error) {
        return _deny('forbidden');
    };

    return ref $decision eq 'HASH' && $decision->{ok}
      ? undef
      : _deny('forbidden');
}

# The user's status, read only when there is a schema. Its call layer is
# then required: a schema without one is a wiring fault, not an account
# that may subscribe.
async sub _account_p ( $self, $actor ) {
    return _allow('account_active') if !$self->schema;
    my $functions = $self->functions
      // GPForum::X::Unavailable->throw( message =>
          'the subscription policy needs the PostgreSQL function layer' );

    my $user;
    try {
        $user = GPForum::Infrastructure::ResultRow->from(
            await $functions->row_p(
                'identity_user_by_id', { user_id => _user_id($actor) }
            )
        );
    }
    catch ($error) {
        return _deny('authentication_required');
    };
    return _account_answer($user);
}

sub _account_answer ($user) {
    return _deny('authentication_required') if !$user;

    my $status = _column( $user, 'status' ) || $STATUS_ACTIVE;
    return _deny('forbidden') if $status ne $STATUS_ACTIVE;

    return _allow('account_active');
}

sub _user_id ($actor) {
    return undef             if !defined $actor;
    return $actor->{user_id} if ref $actor eq 'HASH';

    return $actor;
}

sub _column ( $row, $column ) {
    return $row->get_column($column) if $row->can('get_column');

    return $row->{$column};
}

sub _allow ($reason) {
    return { ok => 1, reason => $reason };
}

sub _deny ($reason) {
    return { ok => 0, reason => $reason };
}

1;

__END__

=head1 NAME

GPForum::Service::Realtime::SubscriptionPolicy - Who may subscribe to a thread, feed, admin or moderation channel.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $policy = GPForum::Service::Realtime::SubscriptionPolicy->new(
        permission_gate  => $permission_gate,
        readability      => $readability,
        schema           => $schema,
        suspension_store => $suspension_store,
    );
    my $decision = $policy->permits( $actor, 'realtime.subscribe',
        { type => 'thread', id => $thread_id }, {} );
    # { ok => 1, reason => 'thread_readable' }

=head1 DESCRIPTION

The rule L<GPForum::Service::Realtime::ChannelAuthorizer> asks before a
socket joins a channel (notification channels it decides itself). The
account comes first: the actor must be signed in, allowed to participate by
the suspension store, and an C<active> user. Then the channel type decides:

=over 4

=item thread

Open to whoever can read the thread -- its space, category and thread, live
and not hidden -- as every other surface judges it (ADR 0102), through
L<GPForum::Service::Forum::Readability>.

=item admin, moderation

Need the C<admin.view> or C<moderation.review> permission from the
permission gate.

=item feed

Only the actor's own feed: the id must be the actor's user id or
C<personal>.

=back

It fails closed. A suspension store that errors or gives no answer denies,
since ignoring that failure once let a suspended member subscribe whenever
the store was unreachable; a missing readability service or permission gate
denies too.

=head1 SUBROUTINES/METHODS

=head2 permits

Takes the actor (a hash reference with C<user_id>, or a bare user id), the
action, the resource (C<< { type => ..., id => ... } >>) and a context that
is not read. Named C<permits> rather than C<can>, which would override
C<UNIVERSAL::can>.

Returns C<< { ok => 1, reason => $reason } >> with C<thread_readable>,
C<permission_allowed> or C<own_feed>, or
C<< { ok => 0, reason => $reason } >> with C<forbidden> (an action other
than C<realtime.subscribe>, a suspended or inactive account, or a refused
permission or feed),
C<authentication_required> (no user id, no such user, or a user lookup that
died),
C<invisible_resource> (a thread the actor cannot read) or C<unknown_channel>.

=head2 permits_p

The decision itself, as a promise, with the same arguments: the account,
the suspension, the thread's readability and the role are read on the
worker's pooled asynchronous connections, the account and the channel
together. L</permits> is its blocking twin (ADR 0177), the gate, the
readability and the suspension store blocking with it.

=head1 DIAGNOSTICS

Errors from the suspension store and the user lookup are caught and deny.
A C<schema> without the PostgreSQL function layer raises
L<GPForum::X::Unavailable>: a wiring fault, not an account that may
subscribe.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Service::Forum::Readability>,
L<GPForum::Service::Admin::PermissionGate>,
L<GPForum::Service::Moderation::SuspensionStore>, all passed in by
L<GPForum::Bootstrap::Core>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Without a C<suspension_store> suspensions are not checked, and without a
C<schema> the account status is not. Errors from the readability service and
the permission gate are not caught.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
