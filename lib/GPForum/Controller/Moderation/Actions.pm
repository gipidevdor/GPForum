# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Controller::Moderation::Actions;

use Mojo::Base 'GPForum::Controller::Moderation::Base', -async_await;
use v5.40;

our $VERSION = '0.001';

sub hide_post ($self) {
    return $self->_moderate( post => 'hide_post', 'post_hidden' );
}

sub restore_post ($self) {
    return $self->_moderate( post => 'restore_post', 'post_restored' );
}

sub lock_thread ($self) {
    return $self->_moderate( thread => 'lock_thread', 'thread_locked' );
}

sub unlock_thread ($self) {
    return $self->_moderate( thread => 'unlock_thread', 'thread_unlocked' );
}

sub pin_thread ($self) {
    return $self->_moderate( thread => 'pin_thread', 'thread_pinned' );
}

sub unpin_thread ($self) {
    return $self->_moderate( thread => 'unpin_thread', 'thread_unpinned' );
}

sub hide_thread ($self) {
    return $self->_moderate( thread => 'hide_thread', 'thread_hidden' );
}

sub restore_thread ($self) {
    return $self->_moderate( thread => 'restore_thread', 'thread_restored' );
}

# One moderation write on a post or a thread: the moderator's right on that
# kind of resource, the workflow's method with the target's id from the
# route, and the status a success answers.
async sub _moderate ( $self, $kind, $method, $outcome ) {
    my $access   = $self->moderation_access;
    my $resource = "${kind}_resource";
    my $status   = "${outcome}_status";
    my $user_id  = (
        await $self->await_p(
            $self->authorized_write_user_id(
                $access->$resource, $access->moderate_action
            )
        )
    );
    return if !$user_id;

    my $result = await $self->call_p(
        $self->gp_moderation_workflow,
        $method,
        {
            actor_user_id => $user_id,
            command_id    => $self->command_id_param,
            "${kind}_id"  => $self->param("${kind}_id"),
            reason        => $self->reason_param,
        }
    );
    return (
        await $self->await_p(
            $self->moderation_write_response( $result, $access->$status )
        )
    );
}

async sub reverse_action ($self) {
    my $access  = $self->moderation_access;
    my $user_id = (
        await $self->await_p(
            $self->authorized_write_user_id(
                $access->moderation_resource,
                $access->reverse_action
            )
        )
    );
    if ( !$user_id ) {
        return;
    }

    return (
        await $self->await_p(
            $self->moderation_write_response(
                (
                    await $self->call_p(
                        $self->gp_moderation_workflow,
                        'reverse_action',
                        {
                            action_id     => $self->param('action_id'),
                            actor_user_id => $user_id,
                            command_id    => $self->command_id_param,
                            reason        => $self->reason_param,
                        }
                    )
                ),
                $access->action_reversed_status,
            )
        )
    );
}

1;

__END__

=head1 NAME

GPForum::Controller::Moderation::Actions - Content moderation write commands.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    $routes->post('/moderation/posts/:post_id/hide')
      ->to('Moderation::Actions#hide_post');

=head1 DESCRIPTION

Hides and restores posts, locks and unlocks threads, and reverses prior
moderation actions through the moderation workflow. Permission names and
write-success statuses live on L<GPForum::Web::ModerationAccess>.

=head1 SUBROUTINES/METHODS

=head2 hide_post

Hides a post.

=head2 restore_post

Restores a hidden post.

=head2 lock_thread

Locks a thread.

=head2 unlock_thread

Unlocks a thread.

=head2 pin_thread

Pins a thread to the top of its category.

=head2 unpin_thread

Unpins a thread.

=head2 hide_thread

Hides a thread.

=head2 restore_thread

Restores a hidden thread.

=head2 reverse_action

Records reversal of a prior moderation action.

=head1 DIAGNOSTICS

CSRF, auth, validation, and missing-target failures use the shared moderation
helpers.

=head1 CONFIGURATION AND ENVIRONMENT

Uses the moderation workflow helper configured during application startup.

=head1 DEPENDENCIES

Uses L<GPForum::Controller::Moderation::Base>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Action history listing remains on the parent moderation controller.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
