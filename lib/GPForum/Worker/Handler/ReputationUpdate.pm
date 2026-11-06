# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Worker::Handler::ReputationUpdate;

use Const::Fast;
use Mojo::Base -base, -signatures;
use v5.40;

use GPForum::Infrastructure::SqlFunction;
use GPForum::Infrastructure::Text qw(has_text);
use GPForum::Jobs::EventPayload;

our $VERSION = '0.001';

has functions => sub ($self) {
    return GPForum::Infrastructure::SqlFunction->for_schema( $self->schema );
};

const my $THREAD_CREATED  => 'thread.created';
const my $POST_CREATED    => 'post.created';
const my $POST_HIDDEN     => 'post.hidden';
const my $POST_RESTORED   => 'post.restored';
const my $THREAD_HIDDEN   => 'thread.hidden';
const my $THREAD_RESTORED => 'thread.restored';
const my $USER_SUSPENDED  => 'user.suspended';
const my $USER_REVOKED    => 'user.suspension_revoked';

const my $THREAD_CREATED_DELTA  => 2;
const my $POST_CREATED_DELTA    => 1;
const my $POST_HIDDEN_DELTA     => -10;
const my $POST_RESTORED_DELTA   => 10;
const my $THREAD_HIDDEN_DELTA   => -10;
const my $THREAD_RESTORED_DELTA => 10;
const my $SUSPENDED_DELTA       => -50;
const my $REVOKED_DELTA         => 50;

const my %POLICY => (
    $THREAD_CREATED =>
      { delta => $THREAD_CREATED_DELTA, reason => 'thread_created' },
    $POST_CREATED => { delta => $POST_CREATED_DELTA, reason => 'post_created' },
    $POST_HIDDEN  => { delta => $POST_HIDDEN_DELTA,  reason => 'post_hidden' },
    $POST_RESTORED =>
      { delta => $POST_RESTORED_DELTA, reason => 'post_restored' },
    $THREAD_HIDDEN =>
      { delta => $THREAD_HIDDEN_DELTA, reason => 'thread_hidden' },
    $THREAD_RESTORED =>
      { delta => $THREAD_RESTORED_DELTA, reason => 'thread_restored' },
    $USER_SUSPENDED =>
      { delta => $SUSPENDED_DELTA, reason => 'user_suspended' },
    $USER_REVOKED =>
      { delta => $REVOKED_DELTA, reason => 'user_suspension_revoked' },
);

has ledger => undef;    # optional: task is only captured
has schema => undef;    # optional: task is only captured
has sink   => undef;    # optional: tests capture tasks

sub supports ( $, $event ) {
    return _policy( $event->{event_type} ) ? 1 : 0;
}

sub handle ( $self, $event ) {
    my $policy = _policy( $event->{event_type} );
    my $task   = {
        action         => 'reputation.record',
        aggregate_id   => $event->{aggregate_id},
        aggregate_type => $event->{aggregate_type},
        delta          => $policy->{delta},
        event_id       => $event->{event_id},
        reason         => $policy->{reason},
    };
    if ( $self->sink ) {
        $self->sink->capture($task);
    }
    $task->{recorded} = $self->_record( $event, $policy );

    return $task;
}

sub _record ( $self, $event, $policy ) {
    return undef if !$self->ledger;

    my $user_id = $self->_subject_user_id($event);
    return { ok => 0, skipped => 1, reason => 'missing_subject' }
      if !has_text($user_id);

    # Once for each event, keyed by the event rather than by what it is
    # about: a post's creation, its hiding and its restoring each count, as a
    # suspension and its revocation do. Keyed by the post, every change after
    # the first was skipped as a duplicate.
    return $self->ledger->record_event(
        {
            actor_id    => $event->{actor_id},
            delta       => $policy->{delta},
            reason      => $policy->{reason},
            source_id   => _source_id($event),
            source_type => $event->{event_type},
            user_id     => $user_id,
        }
    );
}

sub _subject_user_id ( $self, $event ) {
    return $event->{aggregate_id} if _user_subject($event);

    my $author = GPForum::Jobs::EventPayload->value( $event, 'author_user_id' );
    return $author            if has_text($author);
    return $event->{actor_id} if _creation_event($event);

    return $self->_schema_author($event);
}

# The stored post's or thread's author; any other aggregate has none here.
sub _schema_author ( $self, $event ) {
    my $type = $event->{aggregate_type} || q{};
    my $name;
    if ( $type eq 'post' ) {
        $name = 'Post';
    }
    elsif ( $type eq 'thread' ) {
        $name = 'Thread';
    }
    return undef if !$self->schema || !$name;

    if ( $self->functions ) {
        my $row = $self->functions->row( 'ops_worker_aggregate',
            { aggregate_type => $type, aggregate_id => $event->{aggregate_id} }
        );
        return $row ? $row->{author_user_id} : undef;
    }
    my $row = $self->schema->resultset($name)->find( $event->{aggregate_id} );

    return $row ? $row->get_column('author_user_id') : undef;
}

sub _policy ($event_type) {
    return undef if !defined $event_type;
    return undef if !exists $POLICY{$event_type};

    return $POLICY{$event_type};
}

sub _user_subject ($event) {
    my $event_type = $event->{event_type} || q{};

    return $event_type eq $USER_SUSPENDED || $event_type eq $USER_REVOKED
      ? 1
      : 0;
}

sub _creation_event ($event) {
    my $event_type = $event->{event_type} || q{};

    return $event_type eq $THREAD_CREATED || $event_type eq $POST_CREATED
      ? 1
      : 0;
}

sub _source_id ($event) {
    if ( has_text( $event->{event_id} ) ) {
        return $event->{event_id};
    }
    if ( has_text( $event->{aggregate_id} ) ) {
        return $event->{aggregate_id};
    }

    return undef;
}

1;

__END__

=head1 NAME

GPForum::Worker::Handler::ReputationUpdate - Apply trust updates from events.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $handler = GPForum::Worker::Handler::ReputationUpdate->new(
        ledger => $ledger,
        schema => $schema,
    );
    $handler->handle($event) if $handler->supports($event);

=head1 DESCRIPTION

Outbox handler that calls L<GPForum::Service::Community::ReputationLedger> for
created posts and threads, hide/restore, and suspension events. Subject users
come from the event payload or, for moderation actions, the post/thread author.

=head1 SUBROUTINES/METHODS

=head2 supports

True when the event type has an explicit reputation policy.

=head2 handle

Records one ledger event for the subject user, or skips when no subject can be
resolved. The record is keyed by the event: C<source_type> is the event type,
C<source_id> the event id, or the aggregate id when the event has none, so
each change of a post, a thread or a suspension counts once. The ledger skips
a record that still has no source.

=head1 DIAGNOSTICS

Returns C<skipped> with C<missing_subject> when the author cannot be resolved.
The ledger returns C<skipped> with C<missing_source> when source type or id is
absent, without applying a delta. Ledger errors propagate to the outbox
dispatcher.

=head1 CONFIGURATION AND ENVIRONMENT

Wired from L<GPForum::Bootstrap::Workers> onto the existing outbox transport.

=head1 DEPENDENCIES

Uses L<Const::Fast> and L<Mojo::Base>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Does not invent like or helpful-vote events. Lock/unlock and report resolution
do not change trust. Hide/restore need a schema lookup when the payload omits
C<author_user_id>.

=head1 AUTHOR

GPForum Contributors.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 GPForum Contributors. Released under the BSD-3-Clause
license.

=cut
