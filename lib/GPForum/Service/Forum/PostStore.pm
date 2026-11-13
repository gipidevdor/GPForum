# SPDX-FileCopyrightText: 2026 GPForum Contributors
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Forum::PostStore;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -signatures;
use v5.40;

use GPForum::Domain::Thread;
use GPForum::Infrastructure::EventRecorder;
use GPForum::Infrastructure::ResultRow::Post;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Service::Clock;

our $VERSION = '0.001';

# ADR 0126: what api.forum_create_reply takes of a reply command for the
# store's write (api.core_forum_store_reply_v1), by part, the parameter
# named after the column (a body's and a revision's post_id and body_id with
# their part's name in front), and the post columns it answers with.
const my @REPLY_POST => qw(
  post_id thread_id author_user_id current_body_id current_revision_id
  position visibility moderation_state version visibility_version
  permission_version hidden_at locked_at deleted_at deleted_by
);
const my %REPLY_PART => (
    body => {
        body_format        => 'body_format',
        body_id            => 'body_id',
        body_rendered_safe => 'body_rendered_safe',
        body_source        => 'body_source',
        post_id            => 'body_post_id',
        source_hash        => 'source_hash',
    },
    revision => {
        body_id         => 'revision_body_id',
        edit_reason     => 'edit_reason',
        editor_user_id  => 'editor_user_id',
        post_id         => 'revision_post_id',
        revision_id     => 'revision_id',
        revision_number => 'revision_number',
    },
);

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

# The store's parameters of api.forum_create_reply: the command's
# values, and the ids and the time this store draws while it writes, in its
# order -- the write's correlation id, the event's id, the outbox row's, the
# audit row's -- and the time the recorder stamps the event and the audit
# row with. Every key of the composer's command is taken.
sub reply_parameters ( $self, $command ) {
    my %parameter = (
        post_signature  => ( $command->{body} // {} )->{post_signature},
        idempotency_key => $command->{idempotency_key},
        map { $_ => $command->{post}{$_} } @REPLY_POST,
    );
    for my $part ( sort keys %REPLY_PART ) {
        my $values = $command->{$part} // {};
        for my $name ( keys %{ $REPLY_PART{$part} } ) {
            $parameter{ $REPLY_PART{$part}{$name} } = $values->{$name};
        }
    }

    my $recorder = $self->recorder;
    $parameter{correlation_id} = $self->id_service->uuid;
    $parameter{event_id}       = $recorder->id_service->uuid;
    $parameter{outbox_id}      = $recorder->outbox_builder->id_service->uuid;
    $parameter{audit_id}       = $recorder->audit_record->id_service->uuid;
    $parameter{recorded_at}    = $recorder->audit_record->now_iso8601;

    return \%parameter;
}

# The names reply_parameters gives values for: what a reply refused before
# the store sends, every one undefined.
sub reply_parameter_names ($self) {
    my @names = (
        @REPLY_POST,
        ( map { values %{ $REPLY_PART{$_} } } sort keys %REPLY_PART ),
        qw(idempotency_key correlation_id event_id outbox_id audit_id
          recorded_at post_signature),
    );

    return @names;
}

# The store's answer from the function's row: its refusal in the words of
# GPForum::Domain::Thread, or the post, skipped when an earlier run of the
# command had stored it whole.
sub reply_answer ( $self, $row ) {
    if ( defined $row->{refusal} ) {
        return {
            ok    => 0,
            error =>
              GPForum::Domain::Thread->reply_refusal_words( $row->{refusal} ),
        };
    }

    return {
        ok   => 1,
        post => GPForum::Infrastructure::ResultRow::Post->from(
            { map { $_ => $row->{$_} } @REPLY_POST }
        ),
        skipped => $row->{skipped} ? 1 : undef,
    };
}

# The store's part of api.forum_write_command: the event type, the command
# and the ids and times its write draws.
sub function_parameters ( $self, $event_type, $command ) {
    my $recorder  = $self->recorder;
    my $write_ids = {
        correlation_id => $self->id_service->uuid,
        event_id       => $recorder->id_service->uuid,
        outbox_id      => $recorder->outbox_builder->id_service->uuid,
        audit_id       => $recorder->audit_record->id_service->uuid,
        recorded_at    => $recorder->audit_record->now_iso8601,
    };
    if ( $event_type eq 'post.deleted' ) {
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
    my $answer = {
        ok   => 1,
        post =>
          GPForum::Infrastructure::ResultRow::Post->from( $stored->{post} ),
    };
    if ( exists $stored->{skipped} ) {
        $answer->{skipped} = $stored->{skipped} ? 1 : undef;
    }
    return $answer;
}

1;

__END__

=head1 NAME

GPForum::Service::Forum::PostStore - The parameters of a post's write, and the answers it gives.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $store = GPForum::Service::Forum::PostStore->new(
        clock      => $clock,
        id_service => $id_service,
        schema     => $schema,
    );

    # A reply, as PostComposer prepared it, for api.forum_create_reply.
    my $values = $store->reply_parameters( $prepared->{command} );
    my $answer = $store->reply_answer($row);

    # An edit, a delete or a restore, for api.forum_write_command.
    my $call = $store->function_parameters( 'post.updated', $command );
    my $edit = $store->function_answer( $row->{stored} );

=head1 DESCRIPTION

A post is written in PostgreSQL (ADR 0126, ADR 0177): a reply by
C<api.forum_create_reply>, an edit, a delete or a restore by
C<api.forum_write_command>, each with its command log in the same call,
which L<GPForum::Service::Forum::PostingWorkflow> makes. The functions take
the thread and the post under their row locks, check them again with the
rules of L<GPForum::Domain::Thread> and L<GPForum::Domain::Post>, write the
post, its body and its revision, keep the thread's reply count, and record
the domain event (C<post.created>, C<post.updated>, C<post.deleted>,
C<post.undeleted>), its audit row and its outbox row.

This store gives them what Perl draws -- the correlation id, the event's,
the outbox row's and the audit row's ids from its recorder's id services,
and the time stamped on them -- and reads their rows back as the store's
answer: a refusal in the words of the domain rules, or the post as a
L<GPForum::Infrastructure::ResultRow::Post>.

=head1 SUBROUTINES/METHODS

=head2 new

Constructor (L<GPForum::Base>). C<schema>, the L<DBIx::Class> schema, is
required: without it L</new> throws L<GPForum::X::Argument>. C<clock>
defaults to L<GPForum::Service::Clock> and stamps C<deleted_at>;
C<id_service> defaults to L<GPForum::Infrastructure::Id> and mints the
correlation ids; C<recorder> defaults to an
L<GPForum::Infrastructure::EventRecorder> on that id service and schema,
whose id services and audit clock this store draws from.

=head2 reply_parameters

Takes a reply command from C<prepare> in
L<GPForum::Service::Forum::PostComposer>: C<post>, C<body>, C<revision> and
C<idempotency_key>. Returns the store's parameters of
C<api.forum_create_reply>, by name: the command's post, body and revision,
its C<idempotency_key> and the body's C<post_signature>, and the ids and the
time the write draws -- the correlation id from C<id_service>, then the
event's, the outbox row's and the audit row's ids from the C<recorder>'s id
services, and the time the recorder stamps the event and the audit row
with.

=head2 reply_parameter_names

The names L</reply_parameters> gives values for: what a reply the workflow
refused before the store sends for them, every one undefined.

=head2 reply_answer

Takes a row with the stored reply's columns, or a C<refusal> code. Returns
the refusal in the words of L<GPForum::Domain::Thread/reply_refusal_words>,
or C<< { ok => 1, post => $post, skipped => $skipped } >>, C<skipped> 1 when
an earlier run of the command had stored the post whole.

=head2 function_parameters

Takes the event type (C<post.updated>, C<post.deleted>, C<post.undeleted>)
and the command. Returns the store's part of C<api.forum_write_command>'s
parameters: the type, the command and the ids and times the write draws,
C<deleted_at> too for a delete.

=head2 function_answer

Takes the C<stored> answer of C<api.forum_write_command>. Returns it as the
store's answer: a refusal as it is, else the post as a
L<GPForum::Infrastructure::ResultRow::Post>, with C<skipped> when the
function says.

=head1 DIAGNOSTICS

None of its own: the functions refuse and fail, and the workflow answers.
A store built without a C<schema> throws L<GPForum::X::Argument>.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Base>, L<GPForum::Domain::Thread>,
L<GPForum::Infrastructure::EventRecorder>, L<GPForum::Infrastructure::Id>,
L<GPForum::Infrastructure::ResultRow::Post>,
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
