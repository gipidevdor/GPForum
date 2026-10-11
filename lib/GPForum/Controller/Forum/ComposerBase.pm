# SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
# SPDX-License-Identifier: BSD-3-Clause

package GPForum::Controller::Forum::ComposerBase;

use Const::Fast;
use Mojo::Base 'GPForum::Controller::Forum::Base', -signatures;
use v5.40;

our $VERSION = '0.001';

const my $HTTP_OK          => 200;
const my $HTTP_BAD_REQUEST => 400;
const my $HTTP_CONFLICT    => 409;

const my @FIELDS => qw(draft_id draft_revision kind category_id thread_id
  title body_source visibility command_id);
const my %STATUS => (
    invalid   => 400,
    conflict  => 409,
    not_found => 404,
    forbidden => 403,
    failed    => 503,
);

sub draft_input ( $self, $owner ) {
    return {
        owner_user_id => $owner,
        map { $_ => $self->param($_) } @FIELDS
    };
}

sub save_publish_draft ( $self, $owner, $kind ) {
    return {} if !length( $self->param('draft_id') // q{} );
    my $input = $self->draft_input($owner);
    $input->{kind} = $kind;
    if ( $kind eq 'reply' ) {
        $input->{thread_id} = $self->stash('thread_id');
    }
    my $result = $self->gp_draft_store->save($input);
    if ( !$result->{ok} ) {

        # The successful command may already have consumed the draft. Its
        # stored routine decides replay before looking for that draft again.
        return $input if ( $result->{status} // q{} ) eq 'not_found';
        $self->save_response( $input, $result );
        return undef;
    }
    $self->param( command_id => $result->{draft}{command_id} );
    return $result->{draft};
}

sub save_response ( $self, $input, $result ) {
    my $status = $self->draft_status($result);
    if ( !$result->{ok} ) {
        my $key =
          $status == $HTTP_CONFLICT
          ? 'forum.draft_conflict'
          : 'forum.draft_save_failed';
        $result->{error} = $self->i18n($key);
        return $self->render( json => $result, status => $status )
          if $self->_wants_json;
        $self->stash( composer_draft_error => $result->{error} );
        if ( $status == $HTTP_CONFLICT ) {
            $self->stash( composer_draft_conflict => 1 );
        }
        return $self->compose( $input, $status );
    }
    return $self->render( json => $result, status => $HTTP_OK )
      if $self->_wants_json;
    $self->flash( message => $self->i18n('forum.draft_saved') );
    return $self->redirect_to( $self->_resume_url( $result->{draft} ) );
}

sub compose ( $self, $draft, $status ) {
    $self->private_draft_response;
    return if !$self->_target_allowed($draft);
    $self->stash( composer_draft => $draft, composer_standalone => 1 );
    return $self->_thread_composer( $draft, $status )
      if ( $draft->{kind} // q{} ) eq 'thread';
    my $thread = $self->stash('composer_target_thread');
    return $self->render(
        template         => 'forum/draft_reply',
        status           => $status,
        thread           => $self->gp_forum_view_model->thread($thread),
        reply_command_id => $draft->{command_id}
    );
}

sub _thread_composer ( $self, $draft, $status ) {
    my $categories = $self->gp_category_reader->list_categories(
        { viewer => $self->gp_forum_viewer } );
    my $payload = $self->gp_forum_view_model->new_thread_form(
        categories           => $categories,
        command_id           => $draft->{command_id},
        csrf_token           => $self->csrf_token,
        errors               => {},
        values               => $draft,
        selected_category_id => $draft->{category_id} // q{}
    );
    return $self->render(
        template => 'forum/new_thread',
        status   => $status,
        %{$payload}
    );
}

sub _target_allowed ( $self, $input ) {
    my $kind = $input->{kind} // q{};
    if ( $kind eq 'reply' ) {
        my $thread =
          $self->gp_thread_detail_reader->find_thread( $input->{thread_id},
            $self->gp_forum_viewer );
        if ($thread) {
            $self->stash( composer_target_thread => $thread );
            return 1;
        }
        $self->_not_found('thread not found');
        return 0;
    }
    if ( $kind eq 'thread' ) {
        return 1 if !length( $input->{category_id} // q{} );
        my $category =
          $self->gp_category_reader->find_category( $input->{category_id},
            $self->gp_forum_viewer );
        return 1 if $category;
        $self->_not_found('category not found');
        return 0;
    }
    $self->_not_found('composer not found');
    return 0;
}

sub read_draft_owner ($self) {
    my $owner = $self->_current_user_id;
    if ( !$owner ) { $self->_unauthorized; return undef; }
    return undef if !$self->read_allowed('draft.read');
    return $owner;
}

sub _resume_url ( $self, $draft ) {
    return $self->url_for( 'draft_resume', draft_id => $draft->{draft_id} )
      ->to_string;
}

sub draft_status ( $self, $result ) {
    return $result->{ok} ? $HTTP_OK : $STATUS{ $result->{status} // q{} }
      // $HTTP_BAD_REQUEST;
}

sub private_draft_response ($self) {
    $self->res->headers->cache_control('private, no-store');
    return;
}

1;

__END__

=head1 NAME

GPForum::Controller::Forum::ComposerBase - Private composer response helpers.

=head1 VERSION

Version 0.001.

=head1 SYNOPSIS

Used by the forum composer routes and their tests.

=head1 DESCRIPTION

Shares draft form binding and native composer responses between draft and
publication routes. The draft store owns persistence through PostgreSQL routines.
Publication passes the acknowledged revision and command to its stored routine
so consuming a draft and publishing its content form one atomic operation.

=head1 SUBROUTINES/METHODS

=head2 draft_input

Binds submitted composer fields to the authenticated owner supplied by the
controller and returns the input accepted by the draft store.

=head2 save_publish_draft

Saves the submitted snapshot before publication and returns its acknowledged
draft. An absent consumed draft is left to posting command replay validation.
Other save failures render a response that retains the submitted text.

=head2 save_response

Renders a JSON acknowledgement or redirects the native composer after a save.
Failures return the matching HTTP status and retain the submitted composer text.

=head2 compose

Renders the thread or reply composer after checking access to its target and
stashes the private draft metadata used by the form.

=head2 read_draft_owner

Returns the authenticated owner after applying the draft read rate limit, or
renders the matching authentication or rate-limit error.

=head2 draft_status

Maps a normalized draft store result to its HTTP response status.

=head2 private_draft_response

Sets C<Cache-Control> to C<private, no-store> for a draft response.

=head1 DIAGNOSTICS

Returns explicit draft statuses for the caller.

=head1 CONFIGURATION AND ENVIRONMENT

No environment variables are read directly.

=head1 DEPENDENCIES

L<GPForum::Controller::Forum::Base> and the authenticated draft store.

=head1 INCOMPATIBILITIES

None known.

=head1 BUGS AND LIMITATIONS

Draft retention and authorization are enforced by the production store.

=head1 AUTHOR

Giacomo Picchiarelli.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2026 Giacomo Picchiarelli. Released under the BSD-3-Clause license.

=cut
