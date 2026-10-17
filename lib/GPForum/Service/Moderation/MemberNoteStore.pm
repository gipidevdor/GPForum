# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Service::Moderation::MemberNoteStore;

use Const::Fast;
use Mojo::Base 'GPForum::Base', -signatures;
use v5.40;

use GPForum::Infrastructure::EventRecorder;
use GPForum::Infrastructure::Id;
use GPForum::Infrastructure::SqlFunction;
use GPForum::Service::Clock;
use GPForum::X::Unavailable;

our $VERSION = '0.001';

# ADR 0138: what a note is audited as, and its bounds.
const my $TARGET       => 'member_note';
const my $SCHEMA       => 1;
const my $MAXIMUM_BODY => 2000;
const my $LIST_LIMIT   => 100;
const my $PER_REPORT   => 3;
const my %ACTION => (
    add    => 'member_note.added',
    edit   => 'member_note.edited',
    delete => 'member_note.deleted',
);

has clock      => sub { return GPForum::Service::Clock->new; };
has id_service => sub { return GPForum::Infrastructure::Id->new; };
has recorder   => sub ($self) {
    return GPForum::Infrastructure::EventRecorder->new(
        id_service => $self->id_service,
        schema     => $self->schema,
    );
};
__PACKAGE__->requires(qw(schema));

# A schema without the function layer -- the in-memory doubles -- holds
# nothing: every call is unavailable.
has functions => sub ($self) {
    return GPForum::Infrastructure::SqlFunction->for_schema( $self->schema );
};

sub maximum_body ($self) { return $MAXIMUM_BODY; }

sub per_report ($self) { return $PER_REPORT; }

# The text as stored: line endings made \n, the ends trimmed. Undef when
# nothing is left or it is too long.
sub body ( $self, $value ) {
    my $body = ( $value // q{} ) =~ s/\r\n?/\n/grmsx;
    $body =~ s/\A \s+ | \s+ \z//gmsx;

    return length $body && length $body <= $MAXIMUM_BODY ? $body : undef;
}

# Adds a note by $input->{author_user_id} about $input->{subject_user_id}.
# The form's command id, when it is a uuid, is the note's id, so the same
# submission again answers replayed. Answers ok, replayed, invalid (with
# the field), not_found or conflict, and the note's id.
sub add ( $self, $input ) {
    return { status => 'not_found' }
      if !_is_uuid( $input->{subject_user_id} );
    my $body = $self->body( $input->{body} );
    return _invalid() if !defined $body;

    my $note_id =
      _is_uuid( $input->{command_id} )
      ? $input->{command_id}
      : $self->id_service->uuid;
    my $now = $self->clock->now_iso8601;
    return $self->_functions->row(
        'moderation_member_note_add',
        {
            note_id         => $note_id,
            subject_user_id => $input->{subject_user_id},
            author_user_id  => $input->{author_user_id},
            body            => $body,
            now             => $now,
            audit           => $self->_audit(
                'add', $input, $note_id, { body_length => length $body }, $now
            ),
        }
    ) // { status => 'invalid' };
}

# Replaces a note's text. Answers ok, unchanged, invalid or not_found.
sub edit ( $self, $input ) {
    return { status => 'not_found' }
      if !_is_uuid( $input->{subject_user_id} )
      || !_is_uuid( $input->{note_id} );
    my $body = $self->body( $input->{body} );
    return _invalid() if !defined $body;

    my $now = $self->clock->now_iso8601;
    return $self->_functions->row(
        'moderation_member_note_edit',
        {
            note_id         => $input->{note_id},
            subject_user_id => $input->{subject_user_id},
            editor_user_id  => $input->{actor_user_id},
            body            => $body,
            now             => $now,
            audit           => $self->_audit(
                'edit', $input, $input->{note_id},
                { body_length => length $body }, $now
            ),
        }
    ) // { status => 'invalid' };
}

# Deletes a note. Answers ok or not_found.
sub remove ( $self, $input ) {
    return { status => 'not_found' }
      if !_is_uuid( $input->{subject_user_id} )
      || !_is_uuid( $input->{note_id} );

    my $now = $self->clock->now_iso8601;
    return $self->_functions->row(
        'moderation_member_note_delete',
        {
            note_id         => $input->{note_id},
            subject_user_id => $input->{subject_user_id},
            audit           =>
              $self->_audit( 'delete', $input, $input->{note_id}, {}, $now ),
        }
    ) // { status => 'invalid' };
}

# The notes about a member, newest first.
sub for_member ( $self, $subject_user_id, $limit = $LIST_LIMIT ) {
    return [] if !_is_uuid($subject_user_id);

    return $self->_functions->rows( 'moderation_member_notes',
        { subject_user_id => $subject_user_id, row_limit => $limit } );
}

# For each report the member it is about, with their newest notes: a hash
# by report id of { subject_user_id, subject_username, note_total, notes }.
sub for_reports ( $self, $report_ids, $per_member = $PER_REPORT ) {
    my @ids = grep { _is_uuid($_) } @{ $report_ids // [] };
    return {} if !@ids;

    my %by_report;
    for my $row (
        @{
            $self->_functions->rows( 'moderation_member_notes_for_reports',
                { report_ids => \@ids, per_member => $per_member } )
        }
      )
    {
        my $entry = $by_report{ $row->{report_id} } //= {
            subject_user_id  => $row->{subject_user_id},
            subject_username => $row->{subject_username},
            note_total       => 0 + ( $row->{note_total} // 0 ),
            notes            => [],
        };
        next if !defined $row->{note_id};
        push @{ $entry->{notes} }, {
            map { $_ => $row->{$_} }
              qw(note_id author_username body created_at updated_at
              updated_by_username)
        };
    }

    return \%by_report;
}

sub _audit ( $self, $kind, $input, $note_id, $metadata, $now ) {
    return $self->recorder->audit_call(
        action     => $ACTION{$kind},
        actor_id   => $input->{actor_user_id} // $input->{author_user_id},
        created_at => $now,
        metadata   =>
          { subject_user_id => $input->{subject_user_id}, %{$metadata} },
        schema_version => $SCHEMA,
        target_id      => $note_id,
        target_type    => $TARGET,
    )->{audit};
}

sub _functions ($self) {
    return $self->functions // GPForum::X::Unavailable->throw(
        message => 'member notes need the PostgreSQL function layer' );
}

sub _invalid {
    return { status => 'invalid', field => 'body' };
}

sub _is_uuid ($value) {
    return GPForum::Infrastructure::Id->is_uuid_spelling( $value // q{} );
}

1;

__END__

=head1 NAME

GPForum::Service::Moderation::MemberNoteStore - Private staff notes on members.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    my $store = GPForum::Service::Moderation::MemberNoteStore->new(
        schema => $schema );
    my $added = $store->add(
        {
            subject_user_id => $member_id,
            author_user_id  => $staff_id,
            body            => 'Warned in private about spam links.',
        }
    );
    my $notes = $store->for_member($member_id);

=head1 DESCRIPTION

The storage of ADR 0138 through the C<api.moderation_member_note*>
functions. Perl normalizes and bounds the text, builds the audit records
(never with the note's text) and reads the results; each write changes the
note and records its audit in one transaction.

=head1 SUBROUTINES/METHODS

=head2 body

The text as it is stored, or undef when it is empty or longer than
L</maximum_body> characters.

=head2 add

Adds a note; the form's command id keys it.

=head2 edit

Replaces a note's text, recording the editor and the time.

=head2 remove

Deletes a note.

=head2 for_member

The notes about a member, newest first, with their authors and editors.

=head2 for_reports

The member each report is about, with their newest notes.

=head2 maximum_body

The longest note: 2000 characters.

=head2 per_report

How many notes are shown beside a report: 3.

=head1 DIAGNOSTICS

Without the PostgreSQL function layer every call raises
L<GPForum::X::Unavailable>.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Infrastructure::SqlFunction>,
L<GPForum::Infrastructure::EventRecorder>.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

None known.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause
license.

=cut
