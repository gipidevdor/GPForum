# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Forum::ThreadStore;

use Mojo::Base 'GPForum::Base', -signatures;
use v5.40;

use GPForum::Infrastructure::EventRecorder;
use GPForum::Infrastructure::ResultRow::Post;
use GPForum::Infrastructure::ResultRow::Thread;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Service::Clock;

our $VERSION = '0.001';

__PACKAGE__->requires('schema');

has functions => \&GPForum::Infrastructure::SqlFunction::for_service;

has clock      => sub { return GPForum::Service::Clock->new; };
has id_service => sub {
    require GPForum::Infrastructure::Id;
    return GPForum::Infrastructure::Id->new;
};
has recorder => sub ($self) {
    return GPForum::Infrastructure::EventRecorder->new(
        id_service => $self->id_service,
        schema     => $self->schema,
        functions  => $self->functions,
    );
};

# The store's part of api.forum_write_command: the event type, the command
# and the ids and times its write draws. A thread opening draws two events
# and their outbox ids before the single audit id.
sub function_parameters ( $self, $event_type, $command ) {
    my $recorder  = $self->recorder;
    my $write_ids = {
        correlation_id => $self->id_service->uuid,
        event_id       => $recorder->id_service->uuid,
        outbox_id      => $recorder->outbox_builder->id_service->uuid,
    };
    if ( $event_type eq 'thread.created' ) {
        $write_ids->{post_event_id} = $recorder->id_service->uuid;
        $write_ids->{post_outbox_id} =
          $recorder->outbox_builder->id_service->uuid;
    }
    $write_ids->{audit_id}    = $recorder->audit_record->id_service->uuid;
    $write_ids->{recorded_at} = $recorder->audit_record->now_iso8601;
    if ( $event_type eq 'thread.deleted' ) {
        $write_ids->{deleted_at} = $self->clock->now_iso8601;
    }
    return {
        store_type => $event_type,
        command    => $command,
        record     => $write_ids
    };
}

sub function_answer ( $self, $stored ) {
    return $stored if !$stored->{ok};
    my %answer = %{$stored};
    if ( $stored->{thread} ) {
        $answer{thread} =
          GPForum::Infrastructure::ResultRow::Thread->from( $stored->{thread} );
    }
    if ( $stored->{post} ) {
        $answer{post} =
          GPForum::Infrastructure::ResultRow::Post->from( $stored->{post} );
    }
    if ( exists $stored->{skipped} ) {
        $answer{skipped} = $stored->{skipped} ? 1 : undef;
    }
    return \%answer;
}

1;

__END__

=head1 NAME

GPForum::Service::Forum::ThreadStore - The parameters of a thread's write, and the answers it gives.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $store = GPForum::Service::Forum::ThreadStore->new(
        clock      => $clock,
        id_service => $id_service,
        schema     => $schema,
    );
    my $call   = $store->function_parameters( 'thread.created', $command );
    my $answer = $store->function_answer( $row->{stored} );

=head1 DESCRIPTION

A thread is written in PostgreSQL (ADR 0126, ADR 0177) by
C<api.forum_write_command>, with its command log in the same call, which
L<GPForum::Service::Forum::PostingWorkflow> makes: a new thread with its
opening post and its counter row, a title edit, a move, a delete and a
restore. The function takes the thread row under its lock, checks it again
with the rules of L<GPForum::Domain::Thread>, writes it, and records the
domain events (C<thread.created> with C<post.created>, C<thread.updated>,
C<thread.moved>, C<thread.deleted>, C<thread.undeleted>), the audit row and
the outbox rows.

This store gives the function what Perl draws -- the correlation id, the
events', the outbox rows' and the audit row's ids from its recorder's id
services, and the time stamped on them -- and reads its answer back with
the thread and the post as result rows.

=head1 SUBROUTINES/METHODS

=head2 new

Constructor (L<GPForum::Base>). C<schema>, the L<DBIx::Class> schema, is
required: without it L</new> throws L<GPForum::X::Argument>. C<clock>
defaults to L<GPForum::Service::Clock> and stamps C<deleted_at>;
C<id_service> defaults to L<GPForum::Infrastructure::Id>; C<recorder>
defaults to an L<GPForum::Infrastructure::EventRecorder> on them.

=head2 function_parameters

Takes the event type (C<thread.created>, C<thread.updated>,
C<thread.moved>, C<thread.deleted>, C<thread.undeleted>) and the command.
Returns the store's part of C<api.forum_write_command>'s parameters: the
type, the command and the ids and times the write draws -- a new thread's
second event and outbox row too, and C<deleted_at> for a delete.

=head2 function_answer

Takes the C<stored> answer of C<api.forum_write_command>. Returns it as the
store's answer: a refusal as it is, else with the thread and the post as
L<GPForum::Infrastructure::ResultRow::Thread> and
L<GPForum::Infrastructure::ResultRow::Post>, and C<skipped> when the
function says.

=head1 DIAGNOSTICS

None of its own: the function refuses and fails, and the workflow answers.
A store built without a C<schema> throws L<GPForum::X::Argument>.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Base>, L<GPForum::Infrastructure::EventRecorder>,
L<GPForum::Infrastructure::Id>, L<GPForum::Infrastructure::ResultRow::Post>,
L<GPForum::Infrastructure::ResultRow::Thread>,
L<GPForum::Infrastructure::SqlFunction>, L<GPForum::Service::Clock>.

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
