# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Worker::MinionRegistrar;

use Const::Fast;
use Mojo::Base -base, -signatures;
use v5.40;

use GPForum::X::Argument;

our $VERSION = '0.001';

const my $OUTBOX_TASK          => 'gpforum.outbox.dispatch';
const my $SEARCH_TASK          => 'gpforum.search.dispatch';
const my $NOTIFICATION_TASK    => 'gpforum.notification.dispatch';
const my $CACHE_TASK           => 'gpforum.cache_invalidation.dispatch';
const my $ATTACHMENT_SCAN_TASK => 'gpforum.attachment_scan.dispatch';
const my $MEDIA_TASK           => 'gpforum.media_processing.dispatch';
const my $DEFAULT_LIMIT        => 100;

# One of the two: a dispatcher for every job, or a factory that builds one
# per job. A job given neither throws GPForum::X::Argument.
has dispatcher         => undef;    # optional: or dispatcher_factory
has dispatcher_factory => undef;    # optional: or dispatcher

sub register ( $self, $minion ) {
    for my $task (
        $OUTBOX_TASK, $SEARCH_TASK,          $NOTIFICATION_TASK,
        $CACHE_TASK,  $ATTACHMENT_SCAN_TASK, $MEDIA_TASK,
      )
    {
        $minion->add_task( $task => $self->_dispatch_task );
    }

    return {
        outbox          => $OUTBOX_TASK,
        search          => $SEARCH_TASK,
        notification    => $NOTIFICATION_TASK,
        cache           => $CACHE_TASK,
        attachment_scan => $ATTACHMENT_SCAN_TASK,
        media           => $MEDIA_TASK,
    };
}

sub _dispatch_task {
    my ($self) = @_;
    return sub {
        my ( $job, $limit ) = @_;

        my $summary =
          $self->_dispatcher_for($job)
          ->dispatch_pending( $limit || $DEFAULT_LIMIT );
        $job->finish($summary);

        return $summary;
    };
}

sub _dispatcher_for ( $self, $job ) {
    return $self->dispatcher                 if $self->dispatcher;
    return $self->dispatcher_factory->($job) if $self->dispatcher_factory;

    GPForum::X::Argument->throw( message => 'outbox dispatcher is required' );
}

1;
