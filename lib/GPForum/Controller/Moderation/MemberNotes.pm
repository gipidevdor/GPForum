# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Controller::Moderation::MemberNotes;

use Const::Fast;
use Mojo::Base 'GPForum::Controller::Moderation::Base', -signatures;
use v5.40;

use GPForum::Web::Access;
use GPForum::Web::Guard;
use GPForum::Web::MemberNotes;
use GPForum::Web::SecurityEvent;

our $VERSION = '0.001';

const my $HTTP_OK        => 200;
const my $HTTP_CREATED   => 201;
const my $HTTP_FORBIDDEN => 403;
const my $HOME           => 'admin_user_roles';
const my %FLASH => (
    added     => 'moderation.member_note_added',
    edited    => 'moderation.member_note_edited',
    deleted   => 'moderation.member_note_deleted',
    replayed  => 'moderation.member_note_added',
    unchanged => 'moderation.member_note_unchanged',
);

sub create ($self) {
    my $user_id = $self->_writer;
    return if !$user_id;

    return $self->_answer(
        'added',
        $self->gp_member_note_store->add(
            {
                subject_user_id => $self->stash('user_id'),
                author_user_id  => $user_id,
                body            => $self->param('body'),
                command_id      => $self->param('command_id'),
            }
        )
    );
}

sub update ($self) {
    my $user_id = $self->_writer;
    return if !$user_id;

    return $self->_answer(
        'edited',
        $self->gp_member_note_store->edit(
            {
                subject_user_id => $self->stash('user_id'),
                note_id         => $self->stash('note_id'),
                actor_user_id   => $user_id,
                body            => $self->param('body'),
            }
        )
    );
}

sub remove ($self) {
    my $user_id = $self->_writer;
    return if !$user_id;

    return $self->_answer(
        'deleted',
        $self->gp_member_note_store->remove(
            {
                subject_user_id => $self->stash('user_id'),
                note_id         => $self->stash('note_id'),
                actor_user_id   => $user_id,
            }
        )
    );
}

# The staff member writing, or undef once the request is answered: a bad
# CSRF token, nobody signed in, no global member_note.write binding, over
# the moderation write limit, or suspended.
sub _writer ($self) {
    my $notes = GPForum::Web::MemberNotes->new;
    my $user_id =
      $self->authorized_write_user_id( $notes->resource, $notes->write_action );
    return if !$user_id;

    my $decision = $self->gp_suspension_store->can_participate($user_id);
    if ( !$decision->{ok} ) {
        GPForum::Web::SecurityEvent->new->record_event(
            $self,
            'suspended_user_block',
            {
                action => 'member_note.write',
                status => $HTTP_FORBIDDEN,
            }
        );
        GPForum::Web::Guard->new->forbidden( $self,
            { error => 'user is suspended' } );
        return;
    }

    return $user_id;
}

sub _answer ( $self, $done, $answer ) {
    my $status = $answer->{status} // 'invalid';
    my $guard  = GPForum::Web::Guard->new;
    return $self->_not_found('member note not found')
      if $status eq 'not_found';
    return $guard->bad_request(
        $self,
        $self->moderation_access->invalid_request(
            {
                    body => 'a note is 1 to '
                  . $self->gp_member_note_store->maximum_body
                  . ' characters'
            }
        )
    ) if $status eq 'invalid';
    return $guard->conflict( $self,
        { error => 'that command id is another note', title => 'Conflict' } )
      if $status eq 'conflict';

    my $outcome = $status eq 'ok' ? $done : $status;
    return $self->render(
        json => {
            ok      => 1,
            status  => $outcome,
            note_id => $answer->{note_id},
        },
        status => $status eq 'ok'
          && $done eq 'added' ? $HTTP_CREATED : $HTTP_OK,
    ) if $self->_wants_json;

    $self->set_success_flash( $FLASH{$outcome} );
    my $return_to =
      GPForum::Web::Access->new->safe_return_to( $self->param('return_to') );
    return $self->redirect_to( $return_to
          // $self->url_for( $HOME, user_id => $self->stash('user_id') ) );
}

1;

__END__

=head1 NAME

GPForum::Controller::Moderation::MemberNotes - Writing private staff notes on members.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

    $routes->post('/moderation/members/:user_id/notes')
      ->to('Moderation::MemberNotes#create');

=head1 DESCRIPTION

ADR 0138: staff holding the global C<member_note.write> binding add, edit
and delete notes about a member. Each write needs a CSRF token, stays
under the moderation write rate limit, is refused to a suspended staff
member, and is audited without the note's text. The forms work without
JavaScript and answer with a redirect to where they came from (the
member's admin page by default) and a notice, or JSON when asked.

=head1 SUBROUTINES/METHODS

=head2 create

Adds a note; the form's command id keys it, so a second submission adds
nothing.

=head2 update

Replaces a note's text.

=head2 remove

Deletes a note.

=head1 DIAGNOSTICS

An empty or too long note answers 400; a member or note that does not
exist 404; a command id another note holds 409.

=head1 CONFIGURATION AND ENVIRONMENT

None.

=head1 DEPENDENCIES

L<GPForum::Service::Moderation::MemberNoteStore>,
L<GPForum::Web::MemberNotes>.

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
