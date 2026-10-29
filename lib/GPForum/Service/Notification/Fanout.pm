# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Notification::Fanout;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -signatures;
use v5.40;

use GPForum::Service::Forum::ViewerResolver;

our $VERSION = '0.001';

# How many recipients one delivery statement takes. A page bounds what one
# statement's transaction holds -- its rows, a savepoint per recipient, the
# advisory lock each queued mail keeps to COMMIT -- while a thousand
# recipients are still five statements, not the nine thousand of a delivery
# each.
const my $DELIVERY_PAGE => 200;

# The reasons a recipient is skipped, as create_notification names them.
const my $PERMISSION_DENIED => 'permission_denied';
const my $CHANNEL_DISABLED  => 'channel_disabled';
const my $MEMBER_RELATION   => 'member_relation';
const my $IN_APP            => 'in_app';

# The dispatcher whose fan-out this is: its collaborators decide who is
# notified, its builders draw each delivery, its function layer runs the
# statements.
__PACKAGE__->requires('dispatcher');

# Builds the candidates' viewers from the rows the first statement read; it
# makes no statement of its own.
has viewer_resolver => sub ($self) {
    return GPForum::Service::Forum::ViewerResolver->new(
        schema => $self->dispatcher->schema );
};

# The fan-out: the candidates in one statement -- the subscribers, less the
# actor, each with their delivery plan, their relation to the actor and
# their viewer row -- screened as create_notification screens one
# recipient, then delivered a page at a time, each page one statement.
# Returns the results as fanout_to_subscribers answers them, the badges to
# send -- one per notification created, with the recipient's unread count --
# and the counts that failed, each a badge not sent.
sub run ( $self, $input ) {
    my $candidates = $self->_candidates($input);
    my %results    = map { $_ => [] } qw(created duplicates failed skipped);
    my @deliveries = $self->_screened( $input, $candidates, \%results );
    my %badges     = ( badges => [], uncounted => [] );
    while ( my @page = splice @deliveries, 0, $DELIVERY_PAGE ) {
        $self->_delivered( \@page, \%results, \%badges );
    }

    return {
        results => { ok => 1, attempted => scalar @{$candidates}, %results },
        %badges,
    };
}

sub _candidates ( $self, $input ) {
    my $payload = $input->{payload} || {};

    return $self->dispatcher->functions->rows(
        'notification_fanout_candidates',
        {
            target_type       => $input->{target_type},
            target_id         => $input->{target_id},
            notification_type => $input->{notification_type},
            actor_id          => $payload->{actor_id},
            excluded_user_id  => $input->{excluded_recipient_user_id},
        }
    );
}

# create_notification's screening, for every candidate at once and in its
# order: the permission (ADR 0102), the member's plan, the relation to the
# actor (ADR 0130). A candidate refused is a skipped result; the others are
# the deliveries to make, each with its documents for the statement.
sub _screened ( $self, $input, $candidates, $results ) {
    my %viewer   = map { $_->{user_id} => $self->_viewer($_) } @{$candidates};
    my $readable = $self->_readable( $input, $candidates, \%viewer );
    my $at       = $self->dispatcher->clock->now_iso8601;
    my @deliveries;
    for my $candidate ( @{$candidates} ) {
        my $plan    = $self->_plan($candidate);
        my $refusal = $self->_refusal( $input, $candidate, $plan, $readable );
        if ($refusal) {
            push @{ $results->{skipped} }, { ok => 0, %{$refusal} };
            next;
        }
        push @deliveries,
          $self->_delivery( $input, $candidate, $plan,
            $viewer{ $candidate->{user_id} }, $at );
    }

    return @deliveries;
}

sub _refusal ( $self, $input, $candidate, $plan, $readable ) {
    return { skipped => $PERMISSION_DENIED }
      if $readable && !$readable->{ $candidate->{user_id} };
    return { skipped => $CHANNEL_DISABLED, channel => $IN_APP }
      if !$plan->{in_app} && !$plan->{email};
    return { skipped => $MEMBER_RELATION }
      if $self->_silenced( $input, $candidate );

    return undef;
}

# Who among the candidates may be notified about the source, by user id, as
# the permission engine says: given every candidate's viewer at once when it
# takes them (RecipientPolicy's notifiable_readers: one statement for where
# the source sits, none per recipient), else asked one at a time. Undef
# without an engine: everyone.
sub _readable ( $self, $input, $candidates, $viewers ) {
    my $engine = $self->dispatcher->permission_engine or return undef;
    my ( $type, $id ) = @{$input}{qw(source_type source_id)};
    if ( $engine->can('notifiable_readers') ) {
        my @readers = $engine->notifiable_readers( $type, $id,
            map { $viewers->{ $_->{user_id} } } @{$candidates} );

        return { map { $_->user_id => 1 } @readers };
    }
    my $payload = $input->{payload} || {};

    return {
        map  { $_->{user_id} => 1 }
        grep { $engine->can_notify( $_->{user_id}, $type, $id, $payload ) }
          @{$candidates}
    };
}

# The viewer the candidate's row describes; a non-member keeping the id when
# the account is gone (no viewer row came).
sub _viewer ( $self, $candidate ) {
    return $self->viewer_resolver->viewer_from_row( $candidate->{user_id},
        defined $candidate->{status} ? $candidate : undef );
}

# The candidate's delivery plan as the preference store answers it (the row
# carries the store's answer); the inbox alone without a store, as
# create_notification plans without one.
sub _plan ( $self, $candidate ) {
    return { in_app => 1, email => 0 }
      if !$self->dispatcher->preference_store;

    return {
        in_app => $candidate->{in_app} ? 1 : 0,
        email  => $candidate->{email}  ? 1 : 0,
    };
}

# Whether the recipient's relation to the actor silences this kind (ADR
# 0130): the row says whether a relation exists, the store which kinds it
# silences. A store without silenceable (a double) is asked as before.
sub _silenced ( $self, $input, $candidate ) {
    my $relations = $self->dispatcher->relations or return 0;
    my $type      = $input->{notification_type};
    if ( $relations->can('silenceable') ) {
        return $relations->silenceable($type) && $candidate->{silenced}
          ? 1
          : 0;
    }
    my $payload = $input->{payload} || {};

    return $relations->silences( $candidate->{user_id}, $type,
        $payload->{actor_id} ) ? 1 : 0;
}

# One recipient's delivery: the document the statement takes -- the delivery
# as api.notification_deliver takes it, the mail event as
# api.ops_record_event takes it when the plan says email, and the recipient
# as the unread count sees them -- with the recipient's id to match the
# answer by.
sub _delivery ( $self, $input, $candidate, $plan, $viewer, $at ) {
    my $dispatcher = $self->dispatcher;
    my $notification =
      { %{$input}, recipient_user_id => $candidate->{user_id} };
    my %document = (
        recipient_user_id => $candidate->{user_id},
        in_app            => $plan->{in_app},
        email             => $plan->{email},
        %{ $dispatcher->delivery_call( $notification, $at ) },
        %{ $self->_count_view($viewer) },
    );
    if ( $plan->{email} ) {
        my $mail = $dispatcher->email_call($notification);
        $document{email_event}         = $mail->{event};
        $document{email_outbox_id}     = $mail->{outbox_id};
        $document{email_outbox_extras} = $mail->{outbox_extras};
        $document{email_explicit}      = $mail->{explicit} ? 1 : 0;
    }

    return { user_id => $candidate->{user_id}, document => \%document };
}

# The recipient as api.notification_unread_count sees them, as the
# dispatcher's badge count would: with a readability, the viewer; without
# one, every source counts.
sub _count_view ( $self, $viewer ) {
    if ( !$self->dispatcher->readability ) {
        return {
            filter_sources => 0,
            member         => 0,
            global_read    => 0,
            viewer_user_id => undef,
            category_ids   => [],
            space_ids      => [],
        };
    }

    return {
        filter_sources => 1,
        member         => $viewer->member      ? 1 : 0,
        global_read    => $viewer->global_read ? 1 : 0,
        viewer_user_id => $viewer->user_id,
        category_ids   => $viewer->category_ids,
        space_ids      => $viewer->space_ids,
    };
}

# One page of deliveries, one statement: each answer sorted into the results
# by its outcome, a created one with the badge to send, a count that failed
# as a badge not sent. A statement that fails fails every recipient of its
# page, and the fan-out still answers: the outbox retries, and the recipients
# served come back as duplicates.
sub _delivered ( $self, $page, $results, $badges ) {
    my %delivery = map { $_->{user_id} => $_ } @{$page};
    my ( $rows, $failure );
    try {
        $rows =
          $self->dispatcher->functions->rows( 'notification_fanout_deliver',
            { recipients => [ map { $_->{document} } @{$page} ] } );
    }
    catch ($error) {
        $failure = $error;
    };
    if ( defined $failure ) {
        push @{ $results->{failed} },
          map { { recipient_user_id => $_->{user_id}, error => "$failure" } }
          @{$page};

        return;
    }
    for my $row ( @{$rows} ) {
        next if !exists $delivery{ $row->{recipient_user_id} // q{} };
        _sorted( $row, $results, $badges );
    }

    return;
}

sub _sorted ( $row, $results, $badges ) {
    my $outcome = $row->{outcome} // 'failed';
    if ( $outcome eq 'failed' ) {
        push @{ $results->{failed} },
          {
            recipient_user_id => $row->{recipient_user_id},
            error             => $row->{error} // q{},
          };

        return;
    }
    my @mailed = $row->{email_queued} ? ( email_queued => 1 ) : ();
    if ( $outcome eq 'skipped' ) {
        push @{ $results->{skipped} },
          {
            ok      => 0,
            skipped => $CHANNEL_DISABLED,
            channel => $IN_APP,
            @mailed
          };

        return;
    }
    push @{ $results->{ $outcome eq 'duplicate' ? 'duplicates' : 'created' } },
      {
        %{ $row->{result} || {} },
        unread_count => $row->{unread_count},
        @mailed
      };

    # The count failed after the rows were written: the delivery stands,
    # and the badge is not sent, as when the count was its own statement.
    if ( defined $row->{error} ) {
        push @{ $badges->{uncounted} }, $row->{error};
    }
    elsif ( $outcome eq 'created' ) {
        push @{ $badges->{badges} },
          {
            user_id      => $row->{recipient_user_id},
            unread_count => $row->{unread_count},
          };
    }

    return;
}

1;

__END__

=head1 NAME

GPForum::Service::Notification::Fanout - A reply's notifications to a thread's subscribers in four statements.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $fanout = GPForum::Service::Notification::Fanout->new(
        dispatcher => $dispatcher );
    my $outcome = $fanout->run(
        {
            target_type                => 'thread',
            target_id                  => $thread_id,
            source_type                => 'post',
            source_id                  => $post_id,
            notification_type          => 'reply',
            excluded_recipient_user_id => $author_id,
            idempotency_key            => "notification.reply:$event_id",
            payload => { event_id => $event_id, actor_id => $author_id },
        }
    );
    # $outcome->{results}: { ok, attempted, created, duplicates, failed, skipped }
    # $outcome->{badges}:  [ { user_id, unread_count }, ... ]

=head1 DESCRIPTION

The fan-out L<GPForum::Service::Notification::Dispatcher/fanout_to_subscribers>
runs on PostgreSQL. It used to notify each subscriber in turn through
C<create_notification>: the viewer, the delivery plan, the relation to the
actor, the two rows in a transaction of their own, the unread count and the
badge, eight or nine round trips per recipient, so a thread with a thousand
followers was some nine thousand statements inside one outbox message, which
outlived its lease.

Here the fan-out is four statements however many the recipients
(migration 1036): the candidates, where the source sits, the deliveries,
the badges. C<api.notification_fanout_candidates> answers the
subscribers, less the actor, each with their delivery plan, whether a
relation of theirs to the actor exists, and their viewer row. The screening
is C<create_notification>'s, in its order and with the dispatcher's own
collaborators: the permission engine judges the readability of the source
for every candidate's viewer at once (L<GPForum::Service::Notification::RecipientPolicy/notifiable_readers>),
the plan is the preference store's answer the row carries, the relation
store says which kinds a relation silences. The deliveries then go in one
call of C<api.notification_fanout_deliver> per page of 200: each one drawn
by the dispatcher as C<api.notification_deliver> takes it, with the mail
event as C<api.ops_record_event> takes it when the plan says email, and the
recipient as C<api.notification_unread_count> sees them. The badges, one per
notification created, are the dispatcher's to send in one NOTIFY statement.

Without one of the dispatcher's optional collaborators the fan-out behaves
as C<create_notification> does without it: no engine, everyone may be
notified; no preference store, the inbox alone; no relation store, nobody is
silenced; no readability, every source counts in the badge.

=head1 SUBROUTINES/METHODS

=head2 dispatcher

The L<GPForum::Service::Notification::Dispatcher> whose fan-out this is.
Required.

=head2 viewer_resolver

Builds each candidate's L<GPForum::Service::Forum::Viewer> from the row the
first statement read (L<GPForum::Service::Forum::ViewerResolver/viewer_from_row>);
it makes no statement.

=head2 run

Takes what C<fanout_to_subscribers> takes. Returns a hash reference with
C<results>, what C<fanout_to_subscribers> answers --
C<< { ok => 1, attempted, created, duplicates, failed, skipped } >>, a
created or duplicate result carrying C<unread_count> and, when the mail was
queued, C<email_queued> -- C<badges>, an array reference of
C<< { user_id, unread_count } >>, one per notification created and counted,
and C<uncounted>, the errors of the unread counts that failed after their
rows were written: each a badge not sent, its delivery standing. A
recipient the database refused is C<failed> with the message; a delivery
statement that fails as a whole fails every recipient of its page, and the
fan-out still answers.

=head1 DIAGNOSTICS

Dies when the candidates statement does: nothing was written, and the
outbox retries the event.

=head1 CONFIGURATION AND ENVIRONMENT

None of its own; the dispatcher's.

=head1 DEPENDENCIES

L<GPForum::Base>, L<GPForum::Service::Forum::ViewerResolver>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

The candidates are read before they are delivered to, as the subscribers
were before the loop: a member who subscribes between the two statements is
notified from the next reply.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause
license.

=cut
